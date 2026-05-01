# `fi1` Subscription: `https://fi1.yakovlefff.ru/sub.txt`

Эта заметка фиксирует, что именно публикуется через:

```text
https://fi1.yakovlefff.ru/sub.txt#sub
```

и зачем это нужно отдельно от локального `mihomo` на `r5s`.

## 1. Что это за файл

Реальный файл на `fi1`:

```text
/opt/subs/sub.txt
```

Публичная раздача через nginx:

- vhost: `fi1.yakovlefff.ru`
- URL: `https://fi1.yakovlefff.ru/sub.txt`

Это plaintext subscription со строками URI, а не base64 и не YAML.

## 2. Почему эта подписка важна

Нужно различать два разных контура:

1. Локальный runtime на `r5s`
   - файл: `/opt/docker/mihomo/config/config.yaml`
   - влияет только на `mihomo` на `r5s`

2. Внешняя клиентская подписка
   - файл: `/opt/subs/sub.txt`
   - URL: `https://fi1.yakovlefff.ru/sub.txt#sub`
   - используется внешними клиентами и приложениями, которые импортируют subscription URL

Ключевой вывод:

- правка `config.yaml` на `r5s` не обновляет `sub.txt` автоматически;
- новые входы на `fi1` нужно добавлять в `sub.txt` отдельно.

## 3. Текущее содержимое

На март 2026 `sub.txt` содержит:

```text
ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206Qnlsb0IxK2JFVUxQaXVZS0hGWGdCdz09@77.91.78.247:7443#VPS-SS-FI
vless://5d673db7-06bb-4bc1-b414-4f8be3f7ab29@77.91.78.247:9443?encryption=none&security=tls&sni=fi1.yakovlefff.ru&type=tcp#VPS-VLESS-TCP-FI
hysteria2://Q2p%2BO7tFy8Etl6jL5nc2pig9GxQ%3D@77.91.78.247:8443?sni=fi1.yakovlefff.ru&insecure=0#VPS-HY2-FI
trojan://9730408528f439524409fb6b8d108641@77.91.78.247:15443?security=tls&sni=telegram.yakovlefff.ru&allowInsecure=0#FI1-TROJAN
anytls://3b1838d3e6f4123068e1e0c813906dd6@77.91.78.247:16443?sni=telegram.yakovlefff.ru&insecure=0#FI1-ANYTLS
```

## 4. Новые узлы, которые были добавлены

`SS-vanya-NL` из подписки удалён и больше не должен публиковаться в `/opt/subs/sub.txt`.

### 4.1. `FI1-TROJAN`

- сервер: `77.91.78.247`
- порт: `15443`
- пароль: `9730408528f439524409fb6b8d108641`
- `sni`: `telegram.yakovlefff.ru`

URI:

```text
trojan://9730408528f439524409fb6b8d108641@77.91.78.247:15443?security=tls&sni=telegram.yakovlefff.ru&allowInsecure=0#FI1-TROJAN
```

### 4.2. `FI1-ANYTLS`

- сервер: `77.91.78.247`
- порт: `16443`
- пароль: `3b1838d3e6f4123068e1e0c813906dd6`
- `sni`: `telegram.yakovlefff.ru`

URI:

```text
anytls://3b1838d3e6f4123068e1e0c813906dd6@77.91.78.247:16443?sni=telegram.yakovlefff.ru&insecure=0#FI1-ANYTLS
```

## 5. Как обновлять `sub.txt`

Порядок:

1. Сделать backup файла.
2. Добавить новые URI в `/opt/subs/sub.txt`.
3. Проверить локальный файл.
4. Проверить публичный URL через `curl`.

Шаблон:

```bash
SUB=/opt/subs/sub.txt
cp -a "$SUB" "$SUB.bak.$(date +%F-%H%M%S)"
sed -n '1,120p' "$SUB"
curl -fsSL https://fi1.yakovlefff.ru/sub.txt | sed -n '1,120p'
```

## 6. Что зависит от корректного HTTPS на `fi1.yakovlefff.ru`

`sub.txt` должен обслуживаться через нормальный публичный `443` с сертификатом:

```text
CN = fi1.yakovlefff.ru
```

Это важно, потому что старая схема `FakeTLS` с глобальным `REDIRECT 443` ломала нормальный HTTPS на `fi1.yakovlefff.ru`.

Текущая рабочая схема:

- публичный `443` обслуживает `fi1.yakovlefff.ru`;
- `FakeTLS` использует отдельный loopback backend на `127.0.0.1:443`;
- `sub.txt` и `FakeTLS` больше не конфликтуют.

## 7. Связанные заметки

- `Telegram FakeTLS`:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/TELEGRAM_MTPROXY_FAKETLS.md`
- общая инструкция по `r5s` и `mihomo`:
  - `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/BEGINNER_SETUP.md`
