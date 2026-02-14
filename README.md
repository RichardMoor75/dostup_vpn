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

- Определяет архитектуру системы (Intel/Apple Silicon, amd64/arm64/386)
- Скачивает последнюю версию ядра Mihomo с GitHub
- Запрашивает URL подписки (конфига) через GUI-диалог (на Linux — терминал)
- Скачивает и валидирует конфиг (проверка YAML)
- Скачивает geo-базы (geoip.dat, geosite.dat)
- Создаёт иконку управления VPN (macOS — menu bar, Windows — системный трей, Linux — CLI `dostup`)
- Создаёт ярлык `Dostup_VPN` на рабочем столе (macOS/Windows) и systemd-сервис (Linux)
- Настраивает брандмауэр (macOS Application Firewall / Windows Firewall)
- Защита от DNS-утечки: умная проверка и переключение DNS (macOS)
- Запускает Mihomo

## Управление

### macOS — иконка в меню-баре

На Mac с установленным Xcode CLT (`swiftc`) автоматически создаётся приложение в строке меню:

- Цветная иконка (зелёный кот) — VPN работает, серая — остановлен
- Запуск / остановка VPN одним кликом (без запроса пароля)
- Проверка доступа, обновление ядра и конфига
- Автозапуск при входе в систему (LaunchAgent)

Если Xcode CLT не установлен — создаётся ярлык **Dostup_VPN** на рабочем столе.

### Windows — иконка в системном трее

При установке автоматически создаётся приложение в области уведомлений (системный трей):

- Цветная иконка (зелёный кот) — VPN работает, серая — остановлен
- Запуск / остановка VPN одним кликом (без UAC)
- Обновление прокси и правил, проверка доступа
- Автозапуск при входе в Windows (ярлык в автозагрузке)
- Автоперезапуск при краше (Windows Service)

Также на рабочем столе создаётся ярлык **Dostup_VPN** с интерактивным меню.

### Все платформы

На рабочем столе появится ярлык **Dostup_VPN** (macOS/Windows) или команда `dostup` (Linux). Запусти для:

- Остановки VPN
- Перезапуска VPN (с обновлением конфига и ядра)
- Обновления провайдеров прокси и правил
- Проверки доступа к заблокированным ресурсам

На Linux используй `sudo dostup start|stop|restart|status|check|log`.

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
/opt/dostup/                 # Linux

├── mihomo                   # Ядро (mihomo.exe на Windows)
├── config.yaml              # Конфиг из подписки
├── geoip.dat                # База IP-адресов
├── geosite.dat              # База доменов
├── settings.json            # Настройки (URL подписки, версия)
├── sites.json               # Список сайтов для проверки доступа
├── icon.ico                 # Иконка для ярлыков (Windows)
├── original_dns.conf        # Сохранённый DNS (macOS, создаётся при проверке доступа)
├── Dostup_VPN.command       # Скрипт управления (macOS)
├── Dostup_VPN.ps1           # Скрипт управления (Windows)
├── DostupVPN-Tray.ps1       # Tray-приложение (Windows)
├── DostupVPN-Service.exe    # Windows Service обёртка (Win 10+)
├── icon_on.png              # Иконка трея: VPN работает (Windows)
├── icon_off.png             # Иконка трея: VPN остановлен (Windows)
├── statusbar/               # Menu bar приложение (macOS, если есть swiftc)
│   ├── DostupVPN-StatusBar.app
│   ├── icon_on.png          # Зелёная иконка (VPN работает)
│   └── icon_off.png         # Серая иконка (VPN остановлен)
└── logs/
    └── mihomo.log           # Логи

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
pkill -f DostupVPN-StatusBar 2>/dev/null
# Восстановить DNS (если mihomo запущен)
IFACE=$(route get default 2>/dev/null | awk '/interface:/{print $2}')
sudo networksetup -setdnsservers "$(networksetup -listallhardwareports | grep -B1 "Device: $IFACE" | head -1 | sed 's/Hardware Port: //')" empty
sudo pkill mihomo
rm -rf ~/dostup
rm -rf ~/Desktop/Dostup_VPN.app
```

### Windows (PowerShell от администратора)
```powershell
# Остановить сервис, VPN и tray-приложение
sc.exe stop DostupVPN 2>$null; sc.exe delete DostupVPN 2>$null
Stop-Process -Name mihomo -Force -ErrorAction SilentlyContinue
Get-WmiObject Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'DostupVPN-Tray' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
# Удалить файлы и ярлыки
Remove-Item -Recurse -Force "$env:USERPROFILE\dostup"
Remove-Item "$env:USERPROFILE\Desktop\Dostup_VPN.lnk" -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\DostupVPN-Tray.lnk" -ErrorAction SilentlyContinue
```

### Linux
```bash
sudo dostup uninstall
```

## Лицензия

MIT
