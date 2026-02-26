# Dostup VPN

Простой установщик [Mihomo](https://github.com/MetaCubeX/mihomo) (Meta Clash Core) для macOS, Windows и Linux. Одна команда — и VPN готов к работе.

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

### Linux (Ubuntu/Debian, сервер)

Скачай и запусти:

```bash
wget https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.sh && sudo bash dostup-install.sh
```

## Что делает установщик

- Определяет архитектуру системы (Intel/Apple Silicon, amd64/arm64/386) и возможности CPU (AVX2)
- Скачивает подходящую версию ядра Mihomo с GitHub (compatible-билд для старых CPU без AVX2)
- Запрашивает URL подписки (конфига) через GUI-диалог (на Linux — терминал)
- Скачивает и валидирует конфиг (проверка YAML)
- Скачивает geo-базы (geoip.dat, geosite.dat)
- Создаёт иконку управления VPN (macOS — menu bar, Windows — системный трей, Linux — CLI `dostup`)
- macOS menu bar: при наличии рабочего `swiftc` собирает локально (через `xcrun swiftc`), при ошибке/отсутствии — скачивает готовый бинарник
- Создаёт приложение `Dostup_VPN` (macOS — ~/Applications, Windows — ярлык на рабочем столе) и systemd-сервис (Linux)
- Настраивает брандмауэр и исключение Windows Defender (macOS Application Firewall / Windows Firewall)
- Защита от DNS-утечки: автопереключение DNS на 8.8.8.8/9.9.9.9 при старте VPN (macOS, Windows 10+)
- Запускает Mihomo и проверяет доступность нод (healthcheck) — если ни одна нода не отвечает, предупреждает и предлагает остановить VPN

## Управление

### macOS — иконка в меню-баре

При установке автоматически создаётся приложение в строке меню:

- Цветная иконка (зелёный кот) — VPN работает, серая — остановлен
- Запуск / остановка VPN одним кликом (без запроса пароля)
- Перезапуск, обновление прокси и правил, проверка нод (healthcheck), проверка доступа
- «Выход» — остановка VPN и закрытие иконки
- Автозапуск при входе в систему (LaunchAgent) и при старте VPN из приложения

Приложение **Dostup_VPN** также устанавливается в `~/Applications` (доступно через Spotlight и Launchpad) для управления через Terminal.

### Windows — иконка в системном трее

При установке автоматически создаётся приложение в области уведомлений (системный трей):

- Цветная иконка (зелёный кот) — VPN работает, серая — остановлен
- Запуск / остановка VPN одним кликом (без UAC)
- Обновление прокси и правил, проверка нод (healthcheck), проверка доступа
- «Выход» — остановка VPN и закрытие иконки
- Автозапуск при входе в Windows и при старте VPN из ярлыка
- Автоперезапуск при краше (Windows Service)

Также на рабочем столе создаётся ярлык **Dostup_VPN** с интерактивным меню.

### Все платформы

Приложение **Dostup_VPN** (macOS — Spotlight/Launchpad, Windows — ярлык на рабочем столе) или команда `dostup` (Linux). Запусти для:

- Остановки VPN
- Перезапуска VPN (с обновлением конфига и ядра)
- Обновления провайдеров прокси и правил
- Проверки нод (healthcheck — какие прокси живые)
- Проверки доступа к заблокированным ресурсам

На Linux используй `sudo dostup start|stop|restart|status|check|update-providers|healthcheck|log`.

На Linux при каждом обновлении конфига автоматически добавляется кастомный rule-provider `proxy-rules` (правила маршрутизации с сервера) и соответствующее правило `RULE-SET` перед `MATCH`.

При каждом запуске автоматически проверяются обновления:
- Скрипт управления (сравнение SHA256 с версией на GitHub)
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
- Права администратора (один раз при установке)

### Windows
- Windows 7/8/10/11
- PowerShell 3.0+ (встроен в Windows)
- Права администратора (один раз при установке)

### Linux
- Ubuntu / Debian (headless сервер)
- Архитектура amd64 или arm64
- Права root

## Структура файлов

После установки создаётся папка:

```
~/dostup/                    # macOS: /Users/username/dostup/
%USERPROFILE%\dostup\        # Windows: C:\Users\username\dostup\
                             # (или C:\dostup\ если имя профиля содержит кириллицу)
/opt/dostup/                 # Linux

├── mihomo                   # Ядро (mihomo.exe на Windows)
├── config.yaml              # Конфиг из подписки
├── geoip.dat                # База IP-адресов
├── geosite.dat              # База доменов
├── settings.json            # Настройки (URL подписки, версия)
├── sites.json               # Список сайтов для проверки доступа
├── icon.ico                 # Иконка для ярлыков (Windows)
├── original_dns.conf        # Сохранённый DNS (macOS, создаётся при запуске VPN)
├── original_dns.json        # Сохранённый DNS (Windows 10+, создаётся при запуске VPN)
├── dns-helper.ps1           # DNS-переключатель (Windows 10+)
├── Dostup_VPN.command       # Скрипт управления (macOS)
├── Dostup_VPN.ps1           # Скрипт управления (Windows)
├── DostupVPN-Tray.ps1       # Tray-приложение (Windows)
├── DostupVPN-Service.exe    # Windows Service обёртка (Win 10+)
├── icon_on.png              # Иконка трея: VPN работает (Windows)
├── icon_off.png             # Иконка трея: VPN остановлен (Windows)
├── statusbar/               # Menu bar приложение (macOS)
│   ├── DostupVPN-StatusBar.app
│   ├── icon_on.png          # Зелёная иконка (VPN работает)
│   └── icon_off.png         # Серая иконка (VPN остановлен)
└── logs/
    ├── mihomo.log           # Логи Mihomo
    └── statusbar-build.log  # Лог сборки menu bar app (macOS, если была попытка компиляции)

# Linux дополнительно:
/etc/systemd/system/dostup.service   # systemd-сервис
/usr/local/bin/dostup                # CLI-обёртка
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
# Остановить menu bar app и LaunchAgent
launchctl unload ~/Library/LaunchAgents/ru.dostup.vpn.statusbar.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/ru.dostup.vpn.statusbar.plist
pkill -x DostupVPN-StatusBar 2>/dev/null
# Остановить mihomo LaunchDaemon
sudo launchctl stop ru.dostup.vpn.mihomo 2>/dev/null
sudo launchctl unload /Library/LaunchDaemons/ru.dostup.vpn.mihomo.plist 2>/dev/null
sudo rm -f /Library/LaunchDaemons/ru.dostup.vpn.mihomo.plist
sudo rm -f /etc/sudoers.d/dostup-vpn
# Восстановить DNS
IFACE=$(route get default 2>/dev/null | awk '/interface:/{print $2}')
SERVICE=$(networksetup -listallhardwareports | grep -B1 "Device: $IFACE" | head -1 | sed 's/Hardware Port: //')
sudo networksetup -setdnsservers "$SERVICE" empty 2>/dev/null
sudo pkill mihomo 2>/dev/null
rm -rf ~/dostup
rm -rf ~/Applications/Dostup_VPN.app
rm -rf ~/Desktop/Dostup_VPN.app 2>/dev/null
```

### Windows (PowerShell от администратора)
```powershell
# Остановить сервис, VPN и tray-приложение
sc.exe stop DostupVPN 2>$null; sc.exe delete DostupVPN 2>$null
Stop-Process -Name mihomo -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'DostupVPN-Tray' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
# Определить папку установки
$d = if (Test-Path "C:\dostup\mihomo.exe") { "C:\dostup" } elseif (Test-Path "$env:ProgramData\dostup\mihomo.exe") { "$env:ProgramData\dostup" } else { "$env:USERPROFILE\dostup" }
# Восстановить DNS (Win 10+)
powershell -ExecutionPolicy Bypass -NoProfile -File "$d\dns-helper.ps1" restore 2>$null
# Удалить файлы и ярлыки
Remove-Item -Recurse -Force $d
Remove-Item "$env:USERPROFILE\Desktop\Dostup_VPN.lnk" -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\DostupVPN-Tray.lnk" -ErrorAction SilentlyContinue
```

### Linux
```bash
sudo dostup uninstall
```

## Лицензия

MIT
