# Решение проблемы Mihomo на macOS: DNS-утечка в локальной сети

**Дата:** 8 февраля 2026
**Статус:** Исправлено — DNS-фикс автоматизирован в установщике

> **Примечание:** Скрипт `Dostup_VPN.command` автоматически переключает DNS на публичные серверы `8.8.8.8` / `9.9.9.9` при каждом запуске Mihomo и восстанавливает оригинальный при остановке. Это fail-safe решение: при активном TUN dns-hijack перехватывает запросы, при утечке мимо TUN — DNS всё равно работает через Google/Quad9. Ручные алиасы больше не нужны. Ниже — описание проблемы и диагностика для справки.

---

## Проблема

Mihomo (MetaCubeXD) установлен на MacBook Pro, TUN включён, правила корректные (проверены на других устройствах), но часть ресурсов недоступна.

## Конфигурация

- **Клиент:** Mihomo с MetaCubeXD Dashboard
- **Режим:** TUN (Mixed stack), utun4
- **Порты:** Mixed 2080, API 9090, DNS 53
- **Fake-IP:** 198.18.0.1
- **Группы прокси:** Auto Select (10 нодов), Gemini, Youtube, InternetPort, Speed, GLOBAL

### TUN-секция конфига:
```yaml
tun:
  enable: true
  stack: mixed
  mtu: 1500
  dns-hijack:
    - any:53
    - tcp://any:53
  auto-route: true
  auto-detect-interface: true
  strict-route: true
  udp-timeout: 300
```

## Диагностика

### Шаг 1: Проверка конфликтов

Проверили наличие конкурирующих VPN/прокси процессов:

```bash
sudo lsof -i -P | grep LISTEN
ifconfig | grep -A2 "utun"
ps aux | grep -iE "vpn|wireguard|openvpn|clash|mihomo|xray|v2ray|sing-box" | grep -v grep
```

**Результат:** Конфликтов нет. Только mihomo (PID 1725) на utun4. Остальные utun0–utun3 — стандартные системные интерфейсы macOS.

### Шаг 2: Проверка DNS

```bash
nslookup youtube.com
```

**Результат:**
```
Server:     10.50.152.210
Address:    10.50.152.210#53

** server can't find youtube.com: NXDOMAIN
```

DNS-запросы шли через корпоративный/локальный DNS-сервер **10.50.152.210**, который блокировал домены (возвращал NXDOMAIN).

### Шаг 3: Подтверждение через scutil

```bash
scutil --dns | head -20
```

**Результат:**
```
DNS configuration

resolver #1
  nameserver[0] : 10.50.152.210
  if_index : 12 (en0)
  flags    : Request A records
  reach    : 0x00020002 (Reachable,Directly Reachable Address)
```

## Причина

DNS-сервер **10.50.152.210** находится в локальной сети (выдаётся по DHCP). Трафик к нему идёт напрямую через физический интерфейс (en0), минуя TUN-интерфейс utun4. Поэтому `dns-hijack: any:53` в конфиге Mihomo его не перехватывал — это особенность работы TUN на macOS с локальным трафиком.

В результате заблокированные домены резолвились через корпоративный DNS и получали NXDOMAIN ещё до того, как трафик попадал в Mihomo.

## Решение

Переключить системный DNS на публичные серверы:

```bash
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8 9.9.9.9
```

Это делается автоматически при запуске Mihomo через скрипт или menu bar app.

### Почему 8.8.8.8, а не 198.18.0.1 (fake-ip)?
- При активном TUN `dns-hijack: any:53` перехватывает запросы к любому DNS — результат идентичен
- При утечке мимо TUN: 8.8.8.8 работает как реальный DNS (fail-safe), а 198.18.0.1 нерутируем в интернете (полный отказ)
- При крэше Mihomo: DNS 8.8.8.8 продолжает работать, 198.18.0.1 — нет

### Важно:
- Настройка применяется ко ВСЕМУ сервису Wi-Fi (все SSID), не к конкретной сети
- При **остановке Mihomo** скрипт автоматически восстанавливает оригинальный DNS
- При крэше — `check_dns_recovery()` восстановит DNS при следующем запуске скрипта

### Ручное восстановление (если нужно):
```bash
sudo networksetup -setdnsservers Wi-Fi empty
```
