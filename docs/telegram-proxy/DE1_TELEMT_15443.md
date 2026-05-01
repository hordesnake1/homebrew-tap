# `de1` `telemt` on `15443/tcp`

Эта заметка фиксирует текущее состояние экспериментального `telemt`-узла на `de1`.

На 31 марта 2026 контейнер обновлён до `telemt` `v3.3.32`.

Статус:

- сервер: `de1` (`144.31.187.38`)
- режим: `telemt` `EE-TLS`
- front domain: `ya.ru`
- порт: `15443/tcp`
- network mode: `host`
- статус: эксперимент рабочий, но не переведён в production

## 1. Что подтверждено

На 31 марта 2026 подтверждено:

- `telemt` стартует корректно;
- Telegram DC connectivity нормальная;
- listener поднят на `0.0.0.0:15443`;
- Telegram клиент подключается;
- в iOS клиенте подтверждено состояние `mtproto: connected`;
- manual update workflow и weekly update check работают;
- upstream docs уточнили, что рабочие клиентские ссылки надо брать только через API `curl -s http://127.0.0.1:9091/v1/users | jq`, а не собирать руками;
- upstream FAQ отдельно фиксирует, что ошибка `Unknown TLS SNI` возникает, если поменяли `tls_domain`, но клиенты продолжают использовать старые ссылки.

Рабочая ссылка:

```text
tg://proxy?server=144.31.187.38&port=15443&secret=eed7692d0df2d1a76dd3f687f5fc0fba7379612e7275
```

## 2. Почему используется `15443`, а не `443`

На `de1` внешний `443/tcp` уже занят `nginx` и HTTPS-сайтом `margarita.yakovlefff.ru`.

Попытка сделать общий `nginx stream :443` с маршрутизацией:

- `ya.ru -> telemt`
- `margarita.yakovlefff.ru -> web backend`

не была доведена до рабочего результата для Telegram-клиента и была откатана.

Практический вывод:

- `telemt` на `15443` — рабочий и проверенный вариант;
- `telemt` на внешнем `443` на этом же IP требует отдельной ingress-архитектуры или отдельного IP/VPS.

## 3. Рабочая конфигурация

Каталог:

```text
/opt/telemt-yaru-test
```

Ключевые файлы:

```text
/opt/telemt-yaru-test/config.toml
/opt/telemt-yaru-test/state/
```

Актуальный конфиг:

```toml
[general]
use_middle_proxy = false
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
public_host = "144.31.187.38"
public_port = 15443

[server]
port = 15443

[server.api]
enabled = true
listen = "0.0.0.0:9091"

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "ya.ru"
mask = true
tls_emulation = true
tls_front_dir = "tlsfront"

[access.users]
yaru = "d7692d0df2d1a76dd3f687f5fc0fba73"
```

## 4. Рабочий запуск

Контейнер запускается не через Docker bridge, а через `--network host`.

Это важно, потому что на `de1` bridge-networking в ходе теста давал ложные проблемы с DNS/egress, из-за чего `telemt` не мог подтянуть `ya.ru` и корректно проверить DC connectivity.

Рабочая команда запуска:

```bash
docker rm -f telemt-yaru-test 2>/dev/null || true

docker run -d \
  --name telemt-yaru-test \
  --restart unless-stopped \
  --network host \
  -v /opt/telemt-yaru-test/config.toml:/app/config.toml:ro \
  -v /opt/telemt-yaru-test/state:/app/cache \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  --security-opt no-new-privileges:true \
  --ulimit nofile=65536:65536 \
  ghcr.io/telemt/telemt:latest
```

## 5. Что смотреть в логах

Проверка состояния:

```bash
docker logs --tail 120 telemt-yaru-test
```

Хорошие признаки:

- `TLS domain: ya.ru`
- `Mask: true -> ya.ru:443`
- `DC/ME Initialized`
- `Listening on 0.0.0.0:15443`
- `Proxy Links (144.31.187.38)`

Текущий остаточный warning, который уже не мешал подключению:

```text
TLS-front fetch not ready within timeout; using cache/default fake cert fallback domain=ya.ru
```

Это значит, что front bootstrap не идеален, но сам proxy уже поднялся и клиентский тест прошёл.

## 6. Проверка слушателя

```bash
ss -lntup | grep ':15443 '
docker ps --filter name=telemt-yaru-test
```

Ожидаемо:

```text
0.0.0.0:15443
```

## 7. Почему не через `nginx stream :443`

Идея `stream :443 = SNI demux` была проверена и откатана.

Причины:

- внешний `443` уже занят `nginx` и сайтом;
- Telegram-клиент не дал рабочего результата на `443` через этот слой;
- `openssl s_client -servername ya.ru -connect 144.31.187.38:443` попадал в сайт `margarita.yakovlefff.ru`, а не в `telemt`;
- `stream-access.log` не дал полезного подтверждения клиентского маршрута для Telegram.

Практический вывод:

- на текущем `de1` оставлять `telemt` на `15443`;
- если понадобится честный `443` для `telemt`, использовать отдельный IP/VPS.

## 8. Быстрый health check

```bash
docker logs --tail 120 telemt-yaru-test
ss -lntup | grep ':15443 '
```

Клиентский тест:

```text
tg://proxy?server=144.31.187.38&port=15443&secret=eed7692d0df2d1a76dd3f687f5fc0fba7379612e7275
```

## 9. Rollback

Остановить экспериментальный узел:

```bash
docker rm -f telemt-yaru-test
ss -lntup | grep ':15443 ' || true
```

Если порт больше не нужен:

```bash
nft -a list ruleset | grep 15443
```

и удалить правило по `handle`, если эксперимент закрывается.

## 10. Auto-update

На `de1` для `telemt-yaru-test` включён weekly update check через `systemd`.

Файлы на хосте:

```text
/usr/local/sbin/update-telemt-yaru-test.sh
/etc/systemd/system/telemt-yaru-update.service
/etc/systemd/system/telemt-yaru-update.timer
```

Модель обновления:

- раз в неделю выполняется `docker pull ghcr.io/telemt/telemt:latest`;
- если digest не изменился, скрипт завершает работу сообщением `already up to date`;
- если digest изменился, контейнер пересоздаётся и проверяется listener `:15443`.

Ручной запуск:

```bash
/usr/local/sbin/update-telemt-yaru-test.sh
```

Ручной запуск `systemd`-unit:

```bash
systemctl start telemt-yaru-update.service
journalctl -u telemt-yaru-update.service -n 50 --no-pager
```

Проверка timer:

```bash
systemctl status telemt-yaru-update.timer --no-pager
systemctl list-timers --all | grep telemt-yaru
```

Быстрый audit:

```bash
docker ps --filter name=telemt-yaru-test
docker image inspect ghcr.io/telemt/telemt:latest --format '{{index .RepoDigests 0}}'
ss -lntup | grep ':15443 ' || true
```

## 11. Operational notes

- это тестовый узел, не основной production ingress;
- current production MTProxy/FakeTLS на `de1` остаётся отдельно;
- если `ya.ru` реально показывает лучшую проходимость в нужной сети, следующий инженерный шаг — отдельный IP/VPS под настоящий `443`, а не новый обходной слой на текущем `de1`.
