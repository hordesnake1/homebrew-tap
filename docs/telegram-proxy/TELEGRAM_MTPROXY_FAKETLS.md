# Telegram MTProxy FakeTLS: `fi1` and `de1`

Эта заметка фиксирует текущее production-состояние MTProxy после cleanup:

- `fi1` (`77.91.78.247`) — только `FakeTLS` на `12443/tcp`
- `de1` (`144.31.187.38`) — только `FakeTLS` на `8443/tcp`
- старый `dd` на `fi1:11443` убран
- старый SOCKS `de1:12443` убран из `sing-box`

## 1. Итоговая карта MTProxy

### 1.1. `fi1` FakeTLS

- сервер: `telegram.yakovlefff.ru`
- IP: `77.91.78.247`
- порт: `12443/tcp`
- контейнер: `mtproxy-faketls`
- каталог: `/opt/mtproxy-faketls`
- режим: TLS transport (`FakeTLS`)

Клиентская ссылка:

```text
https://t.me/proxy?server=telegram.yakovlefff.ru&port=12443&secret=ee2fe6beb2761501dfbf6f0cfd157f8f4a74656c656772616d2e79616b6f766c656666662e7275
```

### 1.2. `de1` FakeTLS

- сервер: `tg.yakovlefff.ru`
- IP: `144.31.187.38`
- порт: `8443/tcp`
- контейнер: `mtproxy`
- каталог: `/opt/mtproxy`
- image: `mtproxy-test` (пока не переименован, но контейнер уже боевой)
- режим: TLS transport (`FakeTLS`)

Клиентская ссылка:

```text
https://t.me/proxy?server=tg.yakovlefff.ru&port=8443&secret=ee7eaa18cf04a5634a2c875da8fb4736d574672e79616b6f766c656666662e7275
```

## 2. Что удалено

### 2.1. `fi1:11443`

Старый baseline `dd`:

- контейнер `mtproxy11443`
- порт `11443/tcp`
- `ufw allow 11443/tcp`

убран и больше не используется.

### 2.2. `de1:12443`

Старый SOCKS inbound в `sing-box`:

- `type: socks`
- `tag: tg-socks`
- `listen_port: 12443`

убран из `/etc/sing-box/config.json`.

## 3. Что дает FakeTLS

`FakeTLS` делает MTProxy похожим на TLS-трафик к реальному домену.

Практически:

- `dd` = проще и надежнее
- `FakeTLS` = лучше маскировка под TLS/HTTPS

После cleanup мы оставили только `FakeTLS`, потому что цель — приватность, а не аварийный fallback на `dd`.

## 4. Рабочая архитектура

Ключевой вывод:

- глобальный `REDIRECT 443` ломает нормальный HTTPS и подписки;
- production-схема должна разделять публичный `443` и loopback `443`.

### 4.1. `fi1`

Публичный `443`:

- сайты и подписки слушают `77.91.78.247:443`

Loopback backend:

- `127.0.0.1:443`
- `server_name telegram.yakovlefff.ru`
- файл: `/etc/nginx/conf.d/mtproxy-faketls-loopback.conf`

Контейнер `mtproxy-faketls` использует:

```yaml
extra_hosts:
  - "telegram.yakovlefff.ru:127.0.0.1"
```

### 4.2. `de1`

Публичный `443`:

- сайты и подписки слушают `144.31.187.38:443`

Loopback backend:

- `127.0.0.1:443`
- `server_name tg.yakovlefff.ru`
- файл: `/etc/nginx/conf.d/mtproxy-faketls-loopback.conf`

`de1` дополнительно использует:

```text
/etc/hosts
127.0.0.1 tg.yakovlefff.ru
```

На `de1` контейнер `mtproxy` использует собственный host-managed entrypoint:

```text
/opt/mtproxy/entrypoint.sh
```

Это было нужно, потому что старый контейнер `mtproxy-test` запускал встроенный `/entrypoint.sh` из image, и правка файла на хосте на него не влияла.

Операционный долг:

- image всё ещё называется `mtproxy-test`;
- старый каталог `/opt/mtproxy_test` можно удалить или архивировать после финальной проверки, потому что боевой контейнер уже работает из `/opt/mtproxy`.

## 5. Что подтверждает рабочее состояние

### 5.1. `fi1`

Loopback backend:

```bash
echo | openssl s_client -connect 127.0.0.1:443 -servername telegram.yakovlefff.ru 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```

MTProxy:

```bash
docker logs mtproxy-faketls 2>&1 | grep -E 'Successfully checked domain|Multiple encrypted client data packets'
```

Ожидаемо:

```text
Successfully checked domain telegram.yakovlefff.ru
Multiple encrypted client data packets are unsupported, so handshake with telegram.yakovlefff.ru will not be fully emulated
```

### 5.2. `de1`

Loopback backend:

```bash
echo | openssl s_client -connect 127.0.0.1:443 -servername tg.yakovlefff.ru 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```

MTProxy:

```bash
docker logs mtproxy 2>&1 | grep -E 'Successfully checked domain|Multiple encrypted client data packets'
```

Ожидаемо:

```text
Successfully checked domain tg.yakovlefff.ru
Multiple encrypted client data packets are unsupported, so handshake with tg.yakovlefff.ru will not be fully emulated
```

## 6. Ограничения

Обе схемы рабочие, но не идеальные.

`mtproto-proxy` на обоих узлах пишет:

```text
Multiple encrypted client data packets are unsupported, so handshake with <domain> will not be fully emulated
```

Это означает:

- `FakeTLS` рабочий;
- домен проходит проверку;
- но эмуляция TLS handshake не полная.

Практически:

- iOS может работать нормально;
- Desktop может вести себя иначе;
- transport остается более хрупким, чем простой `dd`.

## 7. Обновления и `watchtower`

`watchtower` здесь относится только к контейнерам.

Важно:

- `de1` `mtproxy` — Docker-контейнер, его можно держать в общей Docker-политике обновлений;
- `de1` `sing-box` — не контейнер, а `systemd`-сервис `/usr/bin/sing-box`;
- новый релиз upstream `sing-box` не приедет на `de1` через `watchtower`, пока `sing-box` остаётся systemd-бинарником.

На 23 апреля 2026 актуальный stable upstream-релиз: [SagerNet/sing-box v1.13.11](https://github.com/SagerNet/sing-box/releases/tag/v1.13.11).

Практический вывод:

- `watchtower` применим к `mtproxy`, `mihomo`, `pihole` и другим контейнерам;
- для `de1 sing-box` нужен отдельный upgrade-процесс;
- production `de1 sing-box` и `fi1 sing-box` обновлены до `v1.13.11`;
- готовый weekly auto-update делается через `systemd timer`, а не через `watchtower`;
- не считать `watchtower` механизмом обновления `sing-box` на `de1`.

Дополнительно зафиксировано:

- `sing-box-update.timer` активен на `de1` и `fi1`;
- weekly run 19 апреля 2026 на обоих VPS успешно обновил `1.13.7 -> 1.13.8`;
- повторная ручная проверка `/usr/local/sbin/update-sing-box.sh` после обновления до `1.13.11` возвращает `already up to date`.


## 8. Что выдавать клиентам

Выдавать только доменные ссылки:

### `fi1`

```text
https://t.me/proxy?server=telegram.yakovlefff.ru&port=12443&secret=ee2fe6beb2761501dfbf6f0cfd157f8f4a74656c656772616d2e79616b6f766c656666662e7275
```

### `de1`

```text
https://t.me/proxy?server=tg.yakovlefff.ru&port=8443&secret=ee7eaa18cf04a5634a2c875da8fb4736d574672e79616b6f766c656666662e7275
```

Не использовать:

- `77.91.78.247:11443`
- `77.91.78.247:12443` как IP-вариант, если клиент уже умеет домен
- `144.31.187.38:12443`

## 9. Связанные заметки

- подписка `fi1`:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/FI1_SUBSCRIPTION.md`
- общая инструкция по `r5s` и `mihomo`:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/BEGINNER_SETUP.md`
- экспериментальный `telemt` на `de1:15443`:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/DE1_TELEMT_15443.md`
- дизайн `telemt -> SOCKS5 -> sing-box`:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/TELEMT_SOCKS5_UPSTREAM_DESIGN.md`
