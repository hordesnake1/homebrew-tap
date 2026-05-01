# `de1`: migrate current MTProxy container to `teleproxy + sing-box SOCKS5 upstream`

Цель:

- проверить текущее состояние `de1` перед изменениями;
- заменить текущий `de1` `mtproxy` контейнер на `teleproxy`;
- пустить egress `teleproxy` через локальный `SOCKS5` от `sing-box`;
- сохранить быстрый rollback на старый `8443/tcp`.

Статус:

- живой SSH-check из этой сессии не прошёл: `144.31.187.38:22` timeout;
- поэтому ниже зафиксирован точный runbook для выполнения на VPS;
- текущая исходная точка берётся из репозитория, а не из live shell.

## 1. Что считается текущим состоянием `de1`

По репозиторию на начало апреля 2026:

- production Telegram endpoint на `de1`: `tg.yakovlefff.ru:8443`;
- контейнер: `mtproxy`;
- каталог: `/opt/mtproxy`;
- внешний `443/tcp` уже занят `nginx` и сайтом `margarita.yakovlefff.ru`;
- `sing-box` на `de1` работает как `systemd` сервис, а не как контейнер.

Связанные заметки:

- `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/TELEGRAM_MTPROXY_FAKETLS.md`
- `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/TELEMT_SOCKS5_UPSTREAM_DESIGN.md`

## 2. Почему схема именно такая

Для текущего `de1` нельзя просто занять внешний `443` под `teleproxy`, потому что:

- `443/tcp` уже используется web ingress;
- предыдущие попытки multiplex/demux на этом узле были хрупкими;
- нужен минимальный и обратимый change set.

Поэтому стартовый вариант должен быть таким:

```text
Telegram client
  -> teleproxy on de1:8443
  -> local SOCKS5 127.0.0.1:19080
  -> sing-box
  -> internet
  -> Telegram DC
```

Важно:

- `SOCKS5` нужен только как локальный upstream для самого `teleproxy`;
- наружу `127.0.0.1:19080` не публикуется;
- входящая маскировка для клиента остаётся задачей `teleproxy`, а не `sing-box`.

## 3. Что проверить на VPS до изменений

Под `root` на `de1`:

```bash
hostname
id
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker logs --tail 120 mtproxy
ss -lntup | grep -E ':(443|8443|8888|19080) ' || true
systemctl status sing-box --no-pager
sing-box version
```

Ожидаемо до миграции:

- контейнер `mtproxy` жив;
- listener `:8443` поднят;
- внешний `:443` занят не `teleproxy`, а `nginx`/web stack;
- `sing-box` установлен как системный сервис;
- `:19080` пока никем не занят.

Если `:19080` уже занят, выбрать другой loopback port и поправить его во всех шагах ниже.

## 4. Backup перед переделкой

```bash
set -euo pipefail

mkdir -p /root/backup-mtproxy-"$(date +%F-%H%M%S)"
BK="$(ls -dt /root/backup-mtproxy-* | head -1)"

docker inspect mtproxy > "$BK/docker-inspect-mtproxy.json"
docker logs --tail 500 mtproxy > "$BK/mtproxy.log" 2>&1 || true
cp -a /opt/mtproxy "$BK/opt-mtproxy"
cp -a /etc/sing-box "$BK/etc-sing-box"
ss -lntup > "$BK/ss-before.txt"
systemctl cat sing-box > "$BK/sing-box.unit.txt"
```

## 5. Поднять локальный `sing-box` SOCKS5 upstream

Минимальный конфиг:

Файл `/etc/sing-box/teleproxy-upstream.json`:

```json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "teleproxy-socks-in",
      "listen": "127.0.0.1",
      "listen_port": 19080
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
```

Отдельный unit удобнее не мешать с текущим production `sing-box`:

Файл `/etc/systemd/system/sing-box-teleproxy-upstream.service`:

```ini
[Unit]
Description=sing-box SOCKS5 upstream for teleproxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/teleproxy-upstream.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

Применение:

```bash
systemctl daemon-reload
systemctl enable --now sing-box-teleproxy-upstream.service
systemctl status sing-box-teleproxy-upstream.service --no-pager
ss -lntup | grep ':19080 '
curl --socks5-hostname 127.0.0.1:19080 https://ifconfig.me
```

Это минимальная проверка, что локальный SOCKS5 реально ходит наружу.

## 6. Поднять `teleproxy` вместо текущего `mtproxy`

Upstream `teleproxy` по docs:

- Docker image: `ghcr.io/teleproxy/teleproxy:latest`
- `EE_DOMAIN` включает Fake-TLS;
- `DIRECT_MODE=true` включает direct-to-DC;
- `SECRET` можно задавать явно;
- stats endpoint по умолчанию на `8888/tcp`.

Практическое решение для первого rollout:

- использовать `8443/tcp`, не трогая внешний `443`;
- сохранить домен `tg.yakovlefff.ru` как Fake-TLS backend;
- поднять backend website на loopback `127.0.0.1:443` как и сейчас;
- запустить `teleproxy` в `--network host`, чтобы не ловить bridge surprises.

Важно:

- у `teleproxy` нет штатного `SOCKS5 upstream` флага;
- значит эта схема имеет смысл только если сам `de1` egress уже завернут в нужный путь на уровне host routing или отдельного namespace;
- просто поднять `127.0.0.1:19080` недостаточно, если `teleproxy` не умеет сам dial через SOCKS5.

Иными словами:

- `sing-box SOCKS5 upstream` как локальный сервис подготовить можно;
- но для `teleproxy` он не подключается так же прямо, как это проектировалось для `telemt`;
- поэтому для `teleproxy` минимально честный first step: сначала заменить контейнер, не добавляя upstream-chaining в data plane.

Команда запуска `teleproxy` как drop-in замены `mtproxy` на `8443`:

```bash
docker rm -f teleproxy-de1 2>/dev/null || true

docker run -d \
  --name teleproxy-de1 \
  --restart unless-stopped \
  --network host \
  -e PORT=8443 \
  -e STATS_PORT=8888 \
  -e EE_DOMAIN=tg.yakovlefff.ru:443 \
  -e DIRECT_MODE=true \
  -e SECRET=PUT_32_HEX_SECRET_HERE:de1 \
  -e EXTERNAL_IP=144.31.187.38 \
  -e STATS_ALLOW_NET=127.0.0.1/32 \
  -v /opt/teleproxy/data:/opt/teleproxy/data \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  --security-opt no-new-privileges:true \
  --ulimit nofile=65536:65536 \
  ghcr.io/teleproxy/teleproxy:latest
```

Перед этим старый `mtproxy` лучше остановить, но не удалять:

```bash
docker stop mtproxy
```

Если хочешь zero-ish downtime, сначала остановить `mtproxy`, потом сразу стартовать `teleproxy-de1`.

## 7. Что проверить после запуска `teleproxy`

```bash
docker ps --filter name=teleproxy-de1
docker logs --tail 200 teleproxy-de1
ss -lntup | grep -E ':(8443|8888) '
curl -fsS http://127.0.0.1:8888/ | head
```

Дальше снять connection links:

```bash
docker logs teleproxy-de1 2>&1 | grep -E 't\.me/proxy|tg://proxy|Connection Links' -A 5
```

Проверки снаружи:

```bash
echo | openssl s_client -connect 144.31.187.38:8443 -servername tg.yakovlefff.ru 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```

Ожидаемо:

- listener `:8443` поднят;
- stats endpoint жив;
- в логах есть connection link;
- `openssl` видит сертификат backend сайта, а не ошибку рукопожатия.

## 8. Что делать с `SOCKS5 upstream` на самом деле

Для `teleproxy` текущий upstream-path такой:

- `teleproxy` умеет Fake-TLS, secrets, limits, direct-to-DC, monitoring;
- но в актуальных docs нет нативного `SOCKS5 upstream` режима.

Поэтому есть два честных варианта:

1. Сначала перевести `de1` с `mtproxy` на `teleproxy` без chaining.
2. Если нужен именно управляемый upstream через `sing-box`, оставаться на `telemt`, где такая архитектура уже проектировалась осмысленно.

Если цель именно `teleproxy`, то `sing-box` здесь полезнее как:

- отдельный egress policy layer на хосте;
- а не как локальный SOCKS5, в который `teleproxy` умеет подключаться напрямую.

## 9. Rollback

Если `teleproxy` ведёт себя хуже:

```bash
docker rm -f teleproxy-de1
docker start mtproxy
ss -lntup | grep ':8443 '
docker logs --tail 120 mtproxy
```

Если временный upstream `sing-box` больше не нужен:

```bash
systemctl disable --now sing-box-teleproxy-upstream.service
rm -f /etc/systemd/system/sing-box-teleproxy-upstream.service
rm -f /etc/sing-box/teleproxy-upstream.json
systemctl daemon-reload
```

## 10. Recommended decision

На сейчас решение такое:

1. На VPS сначала честно проверить live state командами из раздела 3.
2. Если нужен именно `teleproxy`, мигрировать только `mtproxy -> teleproxy` на `8443`.
3. `sing-box` рядом можно поднять, но не считать, что `teleproxy` начнёт использовать его как SOCKS5 upstream сам по себе.
4. Если upstream chaining обязателен, не переделывать этот узел на `teleproxy`, а продолжать линию `telemt -> SOCKS5 -> sing-box`.

## 11. Источники

- [Teleproxy Home](https://teleproxy.github.io/)
- [Teleproxy Docker Quick Start](https://teleproxy.github.io/docker/)
- [Teleproxy Docker Configuration](https://teleproxy.github.io/docker/configuration/)
- [Teleproxy Fake-TLS](https://teleproxy.github.io/features/fake-tls/)
- [Teleproxy Direct Mode](https://teleproxy.github.io/features/direct-mode/)
