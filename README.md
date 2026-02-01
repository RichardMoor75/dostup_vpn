# Dostup VPN

Простой установщик [Mihomo](https://github.com/MetaCubeX/mihomo) (Meta Clash Core) для macOS и Windows. Одна команда — и VPN готов к работе.

## Установка

### macOS

Открой Terminal и вставь:

```bash
curl -sL https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.command | bash
```

### Windows

Открой PowerShell и вставь:

```powershell
irm https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.ps1 | iex
```

## Что делает установщик

- Определяет архитектуру системы (Intel/Apple Silicon, amd64/arm64/386)
- Скачивает последнюю версию ядра Mihomo с GitHub
- Запрашивает URL подписки (конфига) через GUI-диалог
- Скачивает и валидирует конфиг (проверка YAML)
- Скачивает geo-базы (geoip.dat, geosite.dat)
- Создаёт ярлык `Dostup_VPN` на рабочем столе
- Настраивает брандмауэр (macOS Application Firewall / Windows Firewall)
- Запускает Mihomo

## Управление

После установки на рабочем столе появится ярлык **Dostup_VPN**. Запусти его для:

- Остановки VPN
- Перезапуска VPN (с обновлением конфига и ядра)
- Проверки доступа к заблокированным ресурсам

При каждом запуске автоматически проверяются обновления:
- Ядро Mihomo (при наличии новой версии)
- Конфиг (скачивается заново)
- Geo-базы (раз в 2 недели)

## Панель управления

После запуска VPN доступна веб-панель:

- **URL:** https://metacubex.github.io/metacubexd/
- **API:** `127.0.0.1:9090`

## Требования

### macOS
- macOS 10.15+ (Catalina и новее)
- Права администратора (для запуска Mihomo)

### Windows
- Windows 7/8/10/11
- PowerShell 3.0+ (встроен в Windows)
- Права администратора

## Структура файлов

После установки создаётся папка:

```
~/dostup/                    # macOS: /Users/username/dostup/
%USERPROFILE%\dostup\        # Windows: C:\Users\username\dostup\

├── mihomo                   # Ядро (mihomo.exe на Windows)
├── config.yaml              # Конфиг из подписки
├── geoip.dat                # База IP-адресов
├── geosite.dat              # База доменов
├── settings.json            # Настройки (URL подписки, версия)
├── sites.json               # Список сайтов для проверки доступа
├── Dostup_VPN.command       # Скрипт управления (macOS)
├── Dostup_VPN.ps1           # Скрипт управления (Windows)
└── logs/
    └── mihomo.log           # Логи
```

## Проверка доступа

Функция "Проверить доступ" проверяет работоспособность VPN, пытаясь подключиться к заблокированным ресурсам. Список сайтов хранится в `sites.json`:

```json
{
  "sites": [
    "instagram.com",
    "youtube.com",
    "facebook.com",
    "rutracker.org",
    "hdrezka.ag",
    "flibusta.is"
  ]
}
```

Можно добавить свои сайты, отредактировав этот файл.

## Удаление

### macOS
```bash
sudo pkill mihomo
rm -rf ~/dostup
rm -rf ~/Desktop/Dostup_VPN.app
```

### Windows (PowerShell от администратора)
```powershell
Stop-Process -Name mihomo -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:USERPROFILE\dostup"
Remove-Item "$env:USERPROFILE\Desktop\Dostup_VPN.lnk"
```

## Лицензия

MIT
