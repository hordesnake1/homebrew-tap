# MikroTik + R5S + Mihomo: актуальная инструкция (2026)

Эта версия заменяет старый сценарий `sing-box (tun/nft)` на R5S.

Текущая рабочая схема:
- MikroTik остается основным роутером (PPPoE, NAT, DHCP, firewall).
- R5S (192.168.1.72) работает как узел `mihomo` с transparent proxy (`redir-port`).
- Маршрутизация на MikroTik делается через `mangle -> routing-table to_r5s` (с fallback), `/routing rule` используется для точечных тестов.
- Правила проксирования в mihomo: `GEOSITE/GEOIP ru-blocked`, остальное `DIRECT`.

---

## 1. Целевая топология

```text
Internet
  |
MikroTik (192.168.1.1)
  |
LAN bridge 192.168.1.0/24
  |
R5S Armbian (192.168.1.72) + mihomo
  |
LAN clients
```

---

## 2. Что должно быть удалено (legacy)

На R5S не должно остаться старого `sing-box` стека:

```bash
systemctl status sing-box --no-pager || true
ip rule
nft list tables
```

Ожидаемо:
- `Unit sing-box.service could not be found` (или inactive/disabled, если оставлен файл);
- нет правил с `lookup 2022`/`singtun0`;
- нет таблицы `inet singbox`.

Если legacy еще есть, очистка:

```bash
systemctl stop sing-box 2>/dev/null || true
systemctl disable sing-box 2>/dev/null || true
pkill -9 sing-box 2>/dev/null || true

rm -f /etc/systemd/system/sing-box.service
rm -f /etc/systemd/system/multi-user.target.wants/sing-box.service
systemctl daemon-reload
systemctl reset-failed

ip link del singtun0 2>/dev/null || true
ip route flush table 2022 2>/dev/null || true
while ip rule | grep -q 'lookup 2022'; do ip rule del table 2022 2>/dev/null || true; done
while ip rule | grep -q 'singtun0'; do ip rule del iif singtun0 2>/dev/null || true; done
nft delete table inet singbox 2>/dev/null || true
```

---

## 3. R5S: mihomo и конфиг

### 3.1. Минимальные пакеты

```bash
apt update
apt install -y python3 python3-pip ca-certificates curl iptables
```

`update_subs.py` требует модуль `requests`:

```bash
python3 -m pip install --upgrade requests
```

### 3.2. Конфиг `/opt/docker/mihomo/config/config.yaml`

```yaml
mixed-port: 7890
redir-port: 7892
allow-lan: true
bind-address: 0.0.0.0
mode: rule
log-level: warning
ipv6: false
geodata-mode: true

external-controller: 0.0.0.0:9090
secret: ""

sniffer:
  enable: true
  sniff:
    TLS:
      ports: [443, 8443]
    HTTP:
      ports: [80, 8080-8880]

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  nameserver:
    - 1.1.1.1
    - 8.8.8.8

tun:
  enable: false

proxy-providers:
  sub:
    type: http
    url: "<YOUR_SUBSCRIPTION_URL>"
    path: /root/.config/mihomo/sub.yaml
    interval: 1800
    health-check:
      enable: true
      url: http://cp.cloudflare.com/generate_204
      interval: 180

proxy-groups:
  - name: AUTO
    type: url-test
    url: http://cp.cloudflare.com/generate_204
    interval: 180
    tolerance: 30
    use:
      - sub

  - name: PROXY
    type: select
    proxies:
      - AUTO
      - DIRECT

rules:
  - GEOSITE,ru-blocked,PROXY
  - GEOIP,ru-blocked,PROXY,no-resolve
  - MATCH,DIRECT
```

Применить:

```bash
docker compose -f /opt/docker/mihomo/docker-compose.yml restart
```

### 3.3. Transparent redirect (R5S)

Определи LAN-интерфейс на R5S (в примерах ниже используется `lan1`):

```bash
ip -br link
```

```bash
LAN_IF=lan1
while iptables -t nat -D PREROUTING -i "$LAN_IF" ! -d 192.168.1.0/24 -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 7892 2>/dev/null; do :; done
iptables -t nat -A PREROUTING -i "$LAN_IF" ! -d 192.168.1.0/24 -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 7892

iptables -t nat -L PREROUTING -n -v --line-numbers | grep 7892
```

Счетчики у правила должны расти.

---

### 3.4. R5S: Pi-hole без логина

На `r5s` Pi-hole запущен в Docker:

- project dir: `/opt/pihole`
- compose file: `/opt/pihole/docker-compose.yml`
- web UI: `http://192.168.1.72/admin/`

На март 2026 логин в web UI отключён намеренно.

Ключевая настройка в `docker-compose.yml`:

```yaml
FTLCONF_webserver_api_password: ''
```

Важно:

- для Docker это правильный способ отключить пароль;
- `pihole setpassword` не является постоянным решением для контейнера, потому что пересоздание вернёт состояние из compose;
- после изменения compose нужен `docker compose up -d`.

Проверка:

```bash
cd /opt/pihole
docker compose up -d
docker inspect pihole --format '{{json .Config.Env}}' | jq -r '.[]' | grep FTLCONF_webserver_api_password
```

Ожидаемо:

```text
FTLCONF_webserver_api_password=
```

Если браузер всё ещё показывает login:

- открыть `http://192.168.1.72/admin/` в private/incognito;
- очистить cookies/local storage для `192.168.1.72`.

### 3.5. Политика обновления: `watchtower` и `sing-box`

На 17 марта 2026 upstream `SagerNet sing-box` выпустил `v1.13.3`:

- релиз: [SagerNet/sing-box v1.13.3](https://github.com/SagerNet/sing-box/releases/tag/v1.13.3)

Важно не смешивать два разных контура обновлений:

1. Docker-сервисы
   - могут обновляться через `watchtower`;
   - сюда относятся только контейнеры.

2. Текущий production `sing-box` на `de1`
   - запущен не в Docker;
   - это `systemd`-сервис с бинарником `/usr/bin/sing-box`;
   - `watchtower` его не обновляет и не должен считаться источником обновления для этого узла.

Практический вывод:

- `watchtower` имеет смысл только для контейнеризированных сервисов;
- если `sing-box` часто обновляется и нужен auto-update, его нужно либо:
  - перевести в Docker и уже потом включать в `watchtower`;
  - либо обновлять отдельным `systemd timer`/скриптом вне `watchtower`.

На апрель 2026 правильное ожидание такое:

- `de1 sing-box` и `fi1 sing-box` обновляются отдельно от `watchtower`;
- контейнерные сервисы вроде `mtproxy`, `mihomo`, `pihole` могут жить по своей Docker-политике;
- нельзя считать, что новый релиз `sing-box` автоматически приедет на `de1` или `fi1`, пока сервис остаётся systemd-бинарником.

Текущее production-состояние после ручного обновления 23 апреля 2026:

- пакетный бинарник: `/usr/bin/sing-box`;
- активная версия: `v1.13.11`;
- `systemd` unit использует `/usr/bin/sing-box`, а не legacy `/usr/local/bin/sing-box`;
- weekly auto-update timer активен на обоих VPS:
  - `de1`
  - `fi1`

Готовые файлы для следующего обновления лежат в репозитории:

- скрипт: `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/update-sing-box.sh`;
- unit: `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/sing-box-update.service`;
- timer: `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/sing-box-update.timer`.

Установка на `de1` и `fi1`:

```bash
install -m 0755 /Users/dyakovlev/Documents/sing-box/singbox_vless_stack/update-sing-box.sh /usr/local/sbin/update-sing-box.sh
install -m 0644 /Users/dyakovlev/Documents/sing-box/singbox_vless_stack/sing-box-update.service /etc/systemd/system/sing-box-update.service
install -m 0644 /Users/dyakovlev/Documents/sing-box/singbox_vless_stack/sing-box-update.timer /etc/systemd/system/sing-box-update.timer
systemctl daemon-reload
systemctl enable --now sing-box-update.timer
systemctl list-timers --all | grep sing-box-update
```

Смысл таймера:

- проверка обновления раз в неделю;
- окно запуска: воскресенье `05:30` по локальному времени сервера;
- `RandomizedDelaySec=30m` уменьшает одновременные скачивания;
- script сохраняет текущий конфиг через `dpkg --force-confold`;
- script берет `releases/latest` у `SagerNet/sing-box`, то есть ориентируется на актуальный stable release, а не на alpha/prerelease.

Проверено 23 апреля 2026:

- `de1`: `sing-box-update.timer` активен, прошлый weekly run 19 апреля 2026 успешно обновил `1.13.7 -> 1.13.8`;
- `fi1`: `sing-box-update.timer` активен, прошлый weekly run 19 апреля 2026 успешно обновил `1.13.7 -> 1.13.8`;
- после ручного обновления до `1.13.11` повторный запуск `/usr/local/sbin/update-sing-box.sh` на обоих серверах корректно возвращает `already up to date`.

Ручная проверка:

```bash
systemctl status sing-box-update.timer --no-pager
systemctl list-timers --all | grep sing-box-update
systemctl status sing-box-update.service --no-pager
/usr/local/sbin/update-sing-box.sh
journalctl -u sing-box-update.service -n 20 --no-pager
```

Ожидаемо:

- timer: `active (waiting)`;
- service: `inactive (dead)` после успешного запуска;
- при актуальной версии script пишет:
  - `current version: X.Y.Z`
  - `target version: X.Y.Z`
  - `already up to date`

Manual update note:

- при ручной установке нового бинаря (`install ... /usr/bin/sing-box`) допустимо выполнить `systemctl daemon-reload` перед `systemctl restart sing-box`, чтобы не ловить предупреждение systemd о том, что unit file changed on disk.

---

## 4. Обновление geo и выбор ноды

Используем `singbox_vless_stack/update_subs.py` (версия для mihomo-only).

Источники:
- `geoip.dat`: `runetfreedom/russia-blocked-geoip`
- `geosite.dat`: `runetfreedom/russia-blocked-geosite`

Команды:

```bash
python3 /opt/docker/mihomo/update_subs.py --geo-update --restart-on-geo
MIHOMO_SECRET="" python3 /opt/docker/mihomo/update_subs.py --select-proxy --group AUTO
```

Лог:

```bash
tail -n 80 /opt/docker/mihomo/logs/update_subs.jsonl
```

Ожидаемо: `geo updated` для обоих файлов и `mihomo restarted` при изменениях.

### 4.1. Несколько подписок: `AUTO (url-test)` + `PROXY (select)` через генератор

Схема:
- `AUTO` автоматически выбирает более быстрый узел среди providers.
- `PROXY` использует `AUTO` (и имеет ручной fallback на `DIRECT`).
- Для ручного закрепления узла используйте API выбор в группе `AUTO` (`--group AUTO`).
- URL подписок хранятся в `/opt/docker/mihomo/subscriptions.env`.

Важно:
- локальный `mihomo` на `r5s` может работать как от subscription/provider, так и от вручную описанного блока `proxies:` в `/opt/docker/mihomo/config/config.yaml`;
- клиентская подписка `https://fi1.yakovlefff.ru/sub.txt#sub` является отдельным артефактом и не обновляется автоматически от факта правки `config.yaml` на `r5s`;
- если в инфраструктуру добавлены новые узлы `FI1-TROJAN` и `FI1-ANYTLS`, их нужно отдельно добавить в `sub.txt`, если эта подписка используется клиентами.

На март 2026 это особенно важно, потому что были добавлены:
- `FI1-TROJAN` (`77.91.78.247:15443`, `sni=telegram.yakovlefff.ru`)
- `FI1-ANYTLS` (`77.91.78.247:16443`, `sni=telegram.yakovlefff.ru`)

Итог:
- правка `/opt/docker/mihomo/config/config.yaml` влияет на `r5s`;
- правка `https://fi1.yakovlefff.ru/sub.txt#sub` нужна отдельно для внешних клиентов и приложений, которые живут от subscription URL.
- старый `SS-vanya-NL` из `fi1` subscription удалён и больше не должен возвращаться в `/opt/subs/sub.txt`.

Отдельные заметки:
- subscription `fi1`:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/FI1_SUBSCRIPTION.md`
- Telegram MTProxy FakeTLS:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/TELEGRAM_MTPROXY_FAKETLS.md`

### 4.2. Проверка `AUTO_HYBRID` на `r5s`

На март 2026 `AUTO_HYBRID` на `r5s` должен содержать ровно пять узлов:

- `VPS-HY2-FI`
- `VPS-VLESS-TCP-FI`
- `VPS-SS-FI`
- `FI1-TROJAN`
- `FI1-ANYTLS`

Важно:

- `AUTO_HYBRID` в `mihomo` — это `url-test`, а не round-robin;
- он не "крутит" узлы по кругу;
- он периодически измеряет задержку и выбирает лучший живой узел автоматически.

Проверка текущего состава и выбранного узла:

```bash
curl -s http://127.0.0.1:9090/proxies/AUTO_HYBRID | jq
```

Ручная проверка задержек по всем узлам:

```bash
for p in VPS-HY2-FI VPS-VLESS-TCP-FI VPS-SS-FI FI1-TROJAN FI1-ANYTLS; do
  echo "=== $p ==="
  curl -s -X GET "http://127.0.0.1:9090/proxies/$p/delay?timeout=5000&url=https://www.gstatic.com/generate_204" | jq
done
```

Ожидаемое поведение:

- `AUTO_HYBRID.now` может измениться сам без ручного вмешательства;
- группа должна выбрать узел с наименьшей задержкой;
- например, в одной из проверок `FI1-ANYTLS` стал лучшим и `AUTO_HYBRID` автоматически переключился на него.

Проверка автоматического failover:

1. Временно уронить текущий лучший узел на `fi1` или `de1`.
2. Подождать 1-2 цикла health-check.
3. Проверить, что `AUTO_HYBRID` сам выбрал следующий лучший узел.

Пример наблюдения:

```bash
for i in 1 2 3 4 5 6; do
  date
  curl -s http://127.0.0.1:9090/proxies/AUTO_HYBRID | jq '.now'
  sleep 30
done
```

1. Создать файл переменных:

```bash
cat >/opt/docker/mihomo/subscriptions.env <<'EOF'
SUB_URL_1="https://brock2.argonaft1.online/sub/MTc0OTc3MTk5LDE3NzEwMTMyMjkN-JAaH5Uzx"
SUB_URL_2="https://obhoddash1.argonaft2.online/sub/MTc0OTc3MTk5UzEsMTc3MTEwMTExMw8q1__d7265"
# SUB_URL_3=""
EOF
```

2. Создать рендер-скрипт:

```bash
cat >/opt/docker/mihomo/render_config.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=/opt/docker/mihomo/subscriptions.env
OUT=/opt/docker/mihomo/config/config.yaml
source "$ENV_FILE"

urls=()
for k in SUB_URL_1 SUB_URL_2 SUB_URL_3; do
  v="${!k:-}"
  [ -n "$v" ] && urls+=("$v")
done

if [ "${#urls[@]}" -eq 0 ]; then
  echo "No SUB_URL_* set"; exit 1
fi

{
cat <<'YAML'
mixed-port: 7890
redir-port: 7892
allow-lan: true
bind-address: 0.0.0.0
mode: rule
log-level: warning
ipv6: false
geodata-mode: true

external-controller: 0.0.0.0:9090
secret: ""

sniffer:
  enable: true
  sniff:
    TLS:
      ports: [443, 8443]
    HTTP:
      ports: [80, 8080-8880]

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  nameserver:
    - 1.1.1.1
    - 8.8.8.8

tun:
  enable: false

proxy-providers:
YAML

for i in "${!urls[@]}"; do
  n=$((i+1))
  cat <<YAML
  sub$n:
    type: http
    url: "${urls[$i]}"
    path: /root/.config/mihomo/sub$n.yaml
    interval: 1800
    health-check:
      enable: true
      url: http://cp.cloudflare.com/generate_204
      interval: 180

YAML
done

cat <<'YAML'
proxy-groups:
  - name: AUTO
    type: url-test
    url: http://cp.cloudflare.com/generate_204
    interval: 180
    tolerance: 30
    use:
YAML

for i in "${!urls[@]}"; do
  n=$((i+1))
  echo "      - sub$n"
done

cat <<'YAML'
  - name: PROXY
    type: select
    proxies:
      - AUTO
      - DIRECT

rules:
  - GEOSITE,ru-blocked,PROXY
  - GEOIP,ru-blocked,PROXY,no-resolve
  - MATCH,DIRECT

external-ui: ui
external-ui-name: zashboard
external-ui-url: "https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
YAML
} > "$OUT"

echo "Rendered $OUT with ${#urls[@]} provider(s)"
EOF

chmod +x /opt/docker/mihomo/render_config.sh
```

3. Применить:

```bash
/opt/docker/mihomo/render_config.sh
docker compose -f /opt/docker/mihomo/docker-compose.yml restart
sleep 4
```

4. Проверка:

```bash
curl -s http://127.0.0.1:9090/proxies/AUTO
curl -s http://127.0.0.1:9090/proxies/PROXY
```

5. Добавление/удаление подписки:

Добавить 3-ю подписку:

```bash
echo 'SUB_URL_3="https://example.com/sub/..."' >> /opt/docker/mihomo/subscriptions.env
/opt/docker/mihomo/render_config.sh
docker compose -f /opt/docker/mihomo/docker-compose.yml restart
```

Удалить подписку:

```bash
sed -i '/^SUB_URL_3=/d' /opt/docker/mihomo/subscriptions.env
/opt/docker/mihomo/render_config.sh
docker compose -f /opt/docker/mihomo/docker-compose.yml restart
```

---

## 5. MikroTik: рабочая схема `mangle + to_r5s` (RouterOS 7)

### 5.1. Базовые маршруты таблицы `to_r5s`

```routeros
/routing table print where name="to_r5s"
/ip route print where routing-table=to_r5s
```

Должно быть:
- `0.0.0.0/0 -> 192.168.1.72` distance=1 (primary)
- `0.0.0.0/0 -> pppoe-out1` distance=2 (fallback)

### 5.2. Привести `mark-route` к таблице `to_r5s` (и убрать legacy `*401`)

```routeros
/ip firewall mangle set [find where comment="R5S policy mark-route"] new-routing-mark=to_r5s
/ip route remove [find where routing-table="*401" and comment="R5S policy primary"]
/ip route remove [find where routing-table="*401" and comment="R5S policy fallback"]
```

### 5.3. Убедиться, что policy-mangle включен

```routeros
/ip firewall mangle print detail where comment~"R5S policy"
```

Ожидаемо:
- `R5S policy mark-conn` и `R5S policy mark-route` не disabled.
- `R5S policy mark-route` использует `new-routing-mark=to_r5s`.

### 5.4. Тест только для одного хоста (опционально)

```routeros
/routing rule remove [find where comment="R5S TEST 192.168.1.254"]
/routing rule remove [find where comment="R5S self bypass"]
/routing rule add src-address=192.168.1.254/32 action=lookup-only-in-table table=to_r5s comment="R5S TEST 192.168.1.254"
/routing rule add src-address=192.168.1.72/32 action=lookup table=main comment="R5S self bypass"
/routing rule print detail where comment~"R5S"
```

### 5.5. Проверка маршрутизации через RouterOS 7 синтаксис

```routeros
/routing rule print detail where comment~"R5S"
/ip route print detail where routing-table=to_r5s
/tool/ping address=1.1.1.1 routing-table=to_r5s count=5
/tool/traceroute address=8.8.8.8 routing-table=to_r5s
```

Если в вашей сборке не принимается `routing-table` у ping/traceroute, проверяйте через `src-address` хоста с rule:

```routeros
/ping address=1.1.1.1 src-address=192.168.1.254 count=5
/tool/traceroute address=8.8.8.8 src-address=192.168.1.254
```

Если в `forward` остался временный rule `TEMP block QUIC for byedpi test`, он будет блокировать UDP/443 (QUIC) для клиентов. После тестов его лучше отключить:

```routeros
/ip firewall filter disable [find where comment="TEMP block QUIC for byedpi test"]
```

---

## 6. Проверка, что правила реально матчатся

На R5S:

```bash
docker logs -f --since=10s mihomo | grep -E 'youtube|googlevideo|facebook|fbcdn|chatgpt|match'
```

Корректный результат:
- блокируемые домены: `GeoSite(ru-blocked) using PROXY[...]`
- остальное: `Match using DIRECT`

Пример уже валидного поведения:
- `www.youtube.com`, `*.googlevideo.com`, `www.facebook.com`, `*.fbcdn.net` -> `PROXY`
- `yandex.ru`, `mail.ru`, `github.com` (часть) -> `DIRECT`

---

## 7. Типовые проблемы

### 7.1. `ModuleNotFoundError: No module named 'requests'`

```bash
python3 -m pip install --upgrade requests
```

### 7.2. `geosite.dat` 404

Проверь, что используется правильный релиз-репозиторий:
- не `russia-blocked-geoip` для `geosite.dat`
- а `russia-blocked-geosite`

### 7.3. В логе есть `Load GeoSite rule: cn`

Это не ошибка само по себе. Важнее runtime match-логи (`using PROXY`/`DIRECT`).

### 7.4. Zashboard: отдельная страница обзора и статистика

Если используешь веб-панель Zashboard, можно подключить UI из релиза:

```bash
EXTERNAL_UI_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
```

Дальше в панели:
- `Настройки -> Настройки обзора -> Разделить страницу с обзором -> ВКЛ`
- слева появится отдельная вкладка `Обзор`.

На вкладке `Обзор` доступны графики и агрегация статистики по интервалам времени/типам трафика.

---

## 8. Откат (быстро вернуть прямой интернет)

На MikroTik:

```routeros
/routing rule remove [find where comment="R5S TEST 192.168.1.254"]
/ip firewall mangle disable [find where comment="R5S policy mark-route"]
/ip firewall mangle disable [find where comment="R5S policy mark-conn"]
```

Тогда весь трафик пойдет штатно через основной WAN MikroTik.

## 8.1 Вернуть трафик точечно на тестовые ip .254 и .78

/ip firewall mangle disable [find where comment="R5S policy mark-conn"]
/ip firewall mangle disable [find where comment="R5S policy mark-route"]

/routing rule remove [find where comment="R5S TEST"]
/routing rule add src-address=192.168.1.254/32 action=lookup-only-in-table table=to_r5s comment="R5S TEST"
/routing rule add src-address=192.168.1.239/32 action=lookup-only-in-table table=to_r5s comment="R5S TEST"
/routing rule add src-address=192.168.1.65/32 action=lookup-only-in-table table=to_r5s comment="R5S TEST 192.168.1.65"
/routing rule add src-address=192.168.1.240/32 action=lookup-only-in-table table=to_r5s comment="R5S TEST 192.168.1.240 AppleTV"
/routing rule add src-address=192.168.1.78/32 action=lookup-only-in-table table=to_r5s comment="R5S TEST"


192.168.1.240
# оставить один bypass для R5S
/routing rule remove [find where comment="R5S self bypass"]
/routing rule add src-address=192.168.1.72/32 action=lookup table=main comment="R5S self bypass"

## 8.2 Вернуть трафик для всех


# 1) включить policy mangle обратно
/ip firewall mangle enable [find where comment="R5S policy mark-conn"]
/ip firewall mangle enable [find where comment="R5S policy mark-route"]

# 2) проверить, что route-mark = to_r5s (не legacy *401)
/ip firewall mangle set [find where comment="R5S policy mark-route"] new-routing-mark=to_r5s

# 3) (опционально) вернуть тестовое правило для одного хоста
/routing rule add src-address=192.168.1.254/32 action=lookup-only-in-table table=to_r5s comment="R5S TEST 192.168.1.254"

# 4) bypass для самого R5S (чтобы не ловить петли)
/routing rule add src-address=192.168.1.72/32 action=lookup table=main comment="R5S self bypass"


---

## 9. Краткий чек-лист прод-состояния

- На MikroTik активны `R5S policy mark-conn` и `R5S policy mark-route` с `new-routing-mark=to_r5s`.
- На R5S нет legacy `sing-box` сервиса/таблиц/правил.
- В `mihomo` включен `redir-port: 7892`, `tun: false`.
- Есть iptables REDIRECT `LAN_IF -> 7892` и растут счетчики.
- `update_subs.py --geo-update` успешно обновляет `geoip.dat` и `geosite.dat`.
- В логах `mihomo` блокируемые ресурсы идут через `GeoSite(ru-blocked) using PROXY`.
