# Решение проблемы Mihomo на macOS: DNS-утечка в локальной сети

**Дата:** 8 февраля 2026
**Статус:** Исправлено — DNS-фикс автоматизирован в установщике (коммит `86ea203`)

> **Примечание:** Начиная с обновления от 08.02.2026, скрипт `Dostup_VPN.command` автоматически переключает DNS на `198.18.0.1` при запуске и восстанавливает оригинальный при остановке. Ручные алиасы `vpnon`/`vpnoff` больше не нужны. Ниже — описание проблемы и диагностика для справки.

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

Принудительно установить DNS на fake-ip адрес Mihomo:

```bash
sudo networksetup -setdnsservers Wi-Fi 198.18.0.1
```

### Проверка:
```bash
nslookup youtube.com
# Должен вернуть адрес вида 198.18.x.x
```

### Важно:
- Настройка сохраняется после перезагрузки и переподключения к той же сети.
- При **выключении Mihomo** интернет перестанет работать (DNS будет недоступен). Нужно вернуть автоматический DNS:

```bash
sudo networksetup -setdnsservers Wi-Fi empty
```

### Удобные алиасы для ~/.zshrc:

```bash
alias vpnon="sudo networksetup -setdnsservers Wi-Fi 198.18.0.1"
alias vpnoff="sudo networksetup -setdnsservers Wi-Fi empty"
```

После добавления:
```bash
source ~/.zshrc
```

Использование: `vpnon` перед запуском Mihomo, `vpnoff` после выключения.
