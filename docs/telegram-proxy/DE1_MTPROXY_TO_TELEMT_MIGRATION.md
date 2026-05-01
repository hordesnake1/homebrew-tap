# `de1`: migration from old `mtproto-proxy` to `telemt`

Цель:

- заменить flaky `de1` `mtproto-proxy` на `telemt` первым;
- не трогать `fi1`, пока `telemt` не докажет стабильность;
- сохранить быстрый rollback на старый `8443/tcp`.

Статус:

- старый production endpoint на `de1`: `tg.yakovlefff.ru:8443`
- кандидат на замену: `telemt` на `144.31.187.38:15443`
- текущий `telemt` image: `ghcr.io/telemt/telemt:latest`
- текущая версия после обновления: `v3.3.32`

## 1. Что изменилось в upstream docs `3.3.32`

Из двух upstream docs commits:

- `6a781c8bc3cf2f33873a81910d027cc6edb7b508` обновляет `QUICK_START_GUIDE.en.md`
- `3c734bd8111d7a3fda058dc036eb8e2293846b90` обновляет `FAQ.en.md`

Практически для нас это даёт три важных operational правила:

1. Конфиг по пути:

```text
/etc/telemt/telemt.toml
```

а не `/etc/telemt.toml`.

2. Ссылки надо брать только через API:

```bash
curl -s http://127.0.0.1:9091/v1/users | jq
```

Не собирать их руками после смены параметров.

3. Если меняем `tls_domain`, старые ссылки становятся невалидными.

Upstream FAQ теперь явно предупреждает:

- ошибка `Unknown TLS SNI` обычно означает, что сервер уже на новом `tls_domain`,
- а пользователи всё ещё ходят по старым ссылкам с предыдущим доменом.

Это напрямую важно для rollout:

- нельзя quietly поменять `tls_domain` на боевом узле;
- любая смена домена означает перевыдачу ссылок.

Источники:

- [Update QUICK_START_GUIDE.en.md](https://github.com/telemt/telemt/commit/6a781c8bc3cf2f33873a81910d027cc6edb7b508)
- [Update FAQ.en.md](https://github.com/telemt/telemt/commit/3c734bd8111d7a3fda058dc036eb8e2293846b90)

## 2. Что уже известно по `de1`

Подтверждённые факты:

- старый `mtproto-proxy` на `de1:8443` периодически отваливается;
- `telemt` на `de1:15443` технически рабочий;
- `telemt` на `de1:15443` не проходит whitelist/RKN кейс как полноценная замена `443`;
- попытка посадить `telemt` за `nginx stream :443` на этом же IP не дала рабочего результата и была откатана;
- на `de1` уже работает weekly update для `telemt`.

Вывод:

- `de1` действительно лучший кандидат на замену первым;
- но замена должна быть staged, а не "удалить старое и надеяться".

## 3. Целевой rollout для `de1`

### Stage A. Оставить два endpoint одновременно

Пока не удалять старый `8443`.

Держать параллельно:

- old: `tg.yakovlefff.ru:8443`
- new canary: `144.31.187.38:15443`

Задача Stage A:

- собрать реальную стабильность `telemt`;
- понять, становится ли он operationally лучше old `mtproto-proxy`;
- не потерять fallback.

### Stage B. Перевести только `de1`-пользователей на `telemt`

Не трогать `fi1`.

На этом этапе:

- новый primary для `de1` выдаётся как `telemt` link;
- старый `8443` остаётся доступен как rollback endpoint.

### Stage C. Выдержка

Минимум:

- 7-14 дней без пользовательских массовых complaint'ов;
- без повторяющихся down/up симптомов старого `de1` MTProto;
- без новых системных проблем у `telemt` контейнера.

### Stage D. Только потом решать судьбу `8443`

Если `telemt` стабилен:

- либо оставить `8443` как аварийный fallback;
- либо отключить старый контейнер.

Я бы сначала оставил `8443` как rollback, а не удалял сразу.

## 4. Что не делать

Не делать сейчас:

- не переводить `fi1` на `telemt`;
- не трогать рабочий `telegram.yakovlefff.ru:12443`;
- не пытаться снова вешать `telemt` на тот же внешний `443` `de1`;
- не менять `tls_domain` без новой выдачи ссылок;
- не собирать ссылки руками.

## 5. Что именно обновить на `de1`

### 5.1. Образ

Убедиться, что `telemt-yaru-test` уже на `v3.3.32`.

Проверка:

```bash
docker logs --tail 50 telemt-yaru-test
```

Ожидаемо:

```text
Telemt MTProxy v3.3.32
```

### 5.2. Ссылка

Получать боевую ссылку только так:

```bash
curl -s http://127.0.0.1:9091/v1/users | jq
```

Не полагаться на старую сохранённую строку, если менялись:

- `tls_domain`
- `public_host`
- `public_port`
- `users`

### 5.3. Health checks

Минимальный набор:

```bash
docker ps --filter name=telemt-yaru-test
ss -lntup | grep ':15443 '
docker logs --tail 120 telemt-yaru-test
systemctl status telemt-yaru-update.timer --no-pager
```

## 6. Recommended migration decision

Решение на сейчас:

1. `de1 old flaky MTProto` считать первым кандидатом на замену.
2. `fi1` оставить baseline.
3. На `de1` раскатывать только `telemt v3.3.32`.
4. Rollout делать как canary, не как cutover.
5. Старый `8443` не удалять, пока `telemt` не докажет стабильность.

## 7. Minimal rollback

Если `telemt` начинает вести себя хуже:

1. перестать выдавать `telemt` link;
2. вернуть пользователей на:

```text
https://t.me/proxy?server=tg.yakovlefff.ru&port=8443&secret=ee7eaa18cf04a5634a2c875da8fb4736d574672e79616b6f766c656666662e7275
```

3. контейнер `telemt-yaru-test` оставить для анализа логов, не удалять сразу.

## 8. Связанные заметки

- `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/TELEGRAM_MTPROXY_FAKETLS.md`
- `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/DE1_TELEMT_15443.md`
- `/Users/dyakovlev/Documents/sing-box/singbox_vless_stack/TELEMT_SOCKS5_UPSTREAM_DESIGN.md`
