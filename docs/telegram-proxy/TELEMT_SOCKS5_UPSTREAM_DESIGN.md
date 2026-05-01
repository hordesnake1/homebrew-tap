# Design: `telemt -> SOCKS5 -> sing-box -> internet`

Эта заметка описывает резервную схему, в которой `telemt` выходит к Telegram DC не напрямую, а через локальный `SOCKS5`, поднятый на том же VPS через `sing-box`.

Статус:

- это design note;
- в production не внедрялось;
- закладывается как contingency plan на случай, если direct DC connectivity с VPS деградирует.

## 1. Зачем вообще нужен chaining

Схема вида:

```text
Telegram client -> telemt -> SOCKS5 -> sing-box -> internet -> Telegram DC
```

нужна не для входящей маскировки от РКН.

Она нужна для серверного egress, если:

- сам VPS плохо ходит до Telegram DC;
- direct route нестабилен;
- нужно быстро переключить upstream без замены клиентских ссылок.

Важно:

- `FakeTLS` / `ya.ru` решают входящую маскировку клиента к proxy;
- `SOCKS5 upstream` решает только исходящий путь самого `telemt`.

Это разные уровни.

## 2. Почему именно `sing-box`

Для этой роли `sing-box` удобен как локальный egress-router:

- умеет поднимать локальный `SOCKS5` inbound;
- умеет направлять трафик через нужный outbound;
- легко живёт как `systemd`-бинарник на VPS;
- проще operationally, чем городить отдельный контейнерный relay для минимального случая.

Если later понадобится более сложное chaining, можно смотреть в сторону `gost`, но базовый резервный вариант проще проектировать через `sing-box`.

## 3. Целевая топология

```text
Telegram client
  |
telemt (:15443 or :443)
  |
local SOCKS5 127.0.0.1:19080
  |
sing-box
  |
chosen outbound
  |
Telegram DC
```

На том же VPS:

- `telemt` продолжает принимать клиентов;
- `sing-box` поднимает только локальный `SOCKS5` и не торчит наружу;
- `telemt` использует этот `SOCKS5` как upstream.

## 4. Когда это стоит включать

Включать только если появился реальный симптом:

- `telemt` пишет `No DC connectivity`;
- или Telegram DC с этого VPS reachable нестабильно;
- или direct path деградировал по качеству.

Не включать просто «на всякий случай»:

- это лишний hop;
- это добавляет latency и точку отказа;
- пока direct path на `de1` нормальный, схема избыточна.

## 5. Минимальный `sing-box` дизайн

Ниже не production-ready полный конфиг VPS, а минимальный смысловой контур именно для upstream-SOCKS.

```json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "telemt-socks-in",
      "listen": "127.0.0.1",
      "listen_port": 19080,
      "users": []
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

Это baseline.

Дальше вместо `direct` можно подставить нужный outbound:

- `shadowsocks`
- `vless`
- `trojan`
- `wireguard`
- другой `socks`

Если нужен именно multi-hop через другой relay, он проектируется уже на уровне outbound `sing-box`.

## 6. Что должно быть у `telemt`

Нужна поддержка upstream через SOCKS5.

В upstream issue `telemt/telemt#1` обсуждается именно feature request для `SOCKS5 as upstream`:

- цель: направлять трафик `telemt` через внешний `SOCKS5`, например через Clash/VPN.

Это подтверждает саму полезность схемы как резервной архитектуры, но не делает её обязательной для твоего текущего `de1`, где direct DC connectivity уже нормальная.

## 7. Практический deployment pattern

Если когда-нибудь понадобится включать такой режим на VPS:

1. Поднять отдельный локальный `sing-box` только для upstream-SOCKS.
2. Слушать только `127.0.0.1:19080`.
3. Проверить `curl --socks5-hostname 127.0.0.1:19080 https://ifconfig.me`.
4. Только потом перевести `telemt` на этот `SOCKS5` upstream.
5. Держать direct-режим как rollback path.

## 8. Плюсы

- быстрый fallback без смены клиентских ссылок;
- можно маршрутизировать upstream через другой transport/регион;
- можно использовать уже знакомый `sing-box` стек.

## 9. Минусы

- дополнительный hop;
- выше latency;
- ещё один локальный сервис и ещё один конфиг;
- сложнее отладка, потому что надо разделять входящую проблему и upstream-проблему.

## 10. Решение для текущего состояния

На март 2026 решение такое:

- `de1 telemt` использовать в direct mode;
- `telemt -> SOCKS5 -> sing-box` держать как запасной дизайн;
- внедрять только если direct route до Telegram DC реально начнёт деградировать.

Это соответствует текущим логам `telemt` на `de1`, где direct DC connectivity уже рабочая.
