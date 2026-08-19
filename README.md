# Dostup VPN

Простой установщик [Mihomo](https://github.com/MetaCubeX/mihomo) (Meta Clash Core) для macOS, Windows и Linux. Одна команда — и VPN готов к работе.

## Установка

### macOS

Открой Terminal и вставь:

```bash
curl -fsSL --connect-timeout 10 https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.command | bash
```

### Windows

Открой PowerShell и вставь:

```powershell
irm https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.ps1 | iex
```

### Linux (Ubuntu/Debian, сервер)

Скачай и запусти:

```bash
{ curl -fsSL -4 --connect-timeout 10 -o dostup-install.sh https://github.com/RichardMoor75/dostup_vpn/releases/latest/download/dostup-install.sh || curl -fsSL -4 --connect-timeout 10 -o dostup-install.sh https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.sh; } && sudo bash dostup-install.sh
```

До публикации первого `installer-v*` release команда автоматически использует
ветку разработки `master`. После публикации будет выбираться стабильный release;
установленная копия проверяется по SHA-256 digest из GitHub Releases.

### macOS — персональный установщик (для распространяющего)

Чтобы пользователю не пришлось открывать терминал и вводить URL подписки, можно собрать подписанное и нотаризованное приложение: пользователь распаковывает архив, делает двойной клик — и всё ставится само, без предупреждений Gatekeeper.

Требуется Apple Developer ID. Собирается один раз, персонализируется переименованием — имя папки бандла не входит в подпись, поэтому повторная нотаризация на каждого пользователя не нужна:

```bash
export DOSTUP_DEV_ID="Developer ID Application: … (TEAMID)"
export DOSTUP_NOTARY_PROFILE="dostup-notary"
export DOSTUP_SUB_BASE="https://sub.example.com/conf/yaml"

./make-installer-app.sh build                  # один раз: сборка, подпись, нотаризация
./make-installer-app.sh pack a_abdrashitova    # для каждого пользователя
```

На выходе `dist/Установить Dostup VPN [a_abdrashitova].zip`. Приложение берёт слаг из своего имени и собирает ссылку как `<база>/<слаг>.yaml`. Без слага (файл переименован, или собрана обобщённая версия) установщик просто спросит URL, как обычно.

Профиль ключей нотаризации создаётся один раз:

```bash
xcrun notarytool store-credentials "dostup-notary" \
    --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
```

База URL подписки намеренно не хранится в репозитории и подставляется при сборке через `DOSTUP_SUB_BASE`.

## Что делает установщик

- Определяет архитектуру системы (Intel/Apple Silicon, amd64/arm64/386) и возможности CPU (AVX2)
- Скачивает подходящую версию ядра Mihomo с GitHub (compatible-билд для старых CPU без AVX2)
- Запрашивает URL подписки (конфига) через GUI-диалог (на Linux — терминал)
- Скачивает конфиг и проверяет итоговый результат точным ядром Mihomo (`mihomo -t`)
- Защищает API управления: `external-controller` принудительно привязывается к `127.0.0.1` (если в подписке был `0.0.0.0` — переписывается, чтобы API не был доступен извне)
- Скачивает GeoIP, GeoSite и ASN из GitHub Releases и обязательно сверяет SHA-256 digest
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
- Перезапуск, обновление профиля и провайдеров, проверка нод (healthcheck), проверка доступа
- «Обновить скрипт» — появляется только когда вышла новая версия
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
- Перезапуска VPN
- Обновления профиля и прокси-провайдеров
- Проверки нод (healthcheck — какие прокси живые)
- Проверки доступа к заблокированным ресурсам

На Linux используй `sudo dostup start|stop|restart|rollback|status|check|update-providers|healthcheck|log`.

На Linux импорт сохраняет прежнее поведение: блоки `tun` и `rule-providers`,
а также правила `RULE-SET` удаляются; финальный `MATCH` направляется в
`Auto Select`. Прокси-провайдеры из подписки сохраняются.

## Обновления

### macOS — фоновый планировщик

Отдельный LaunchAgent `ru.dostup.vpn.updater` раз в 6 часов проверяет:

- **Профиль** — скачивается по ссылке подписки. Если содержимое не изменилось, ничего не делается. Если изменилось — применяется на лету через API mihomo, **без перезапуска и без разрыва соединения**
- **Ядро Mihomo** — новая версия скачивается рядом с работающей (`mihomo.new`) и подменяется при следующем запуске: перезаписать выполняющийся файл нельзя
- **Geo-базы** — раз в 2 недели
- **Сам скрипт** — сравнение SHA256 с версией на GitHub. При наличии обновления в меню иконки появляется пункт «Обновить скрипт» и приходит уведомление, по клику на которое открывается установщик

Планировщик работает от пользователя и **не требует прав администратора**. Лог: `~/dostup/logs/updater.log`. Форсировать прогон: `launchctl start ru.dostup.vpn.updater`.

Запуск и перезапуск VPN при этом ничего не качают и занимают несколько секунд независимо от состояния канала.

### Windows и Linux

Обновления проверяются при `sudo dostup restart`/`update`: менеджер, ядро
Mihomo, профиль и geo-базы (раз в 2 недели). Linux сначала собирает и проверяет
кандидат, а работающий сервис останавливает только для короткой подмены. При
локальной ошибке запуска выполняется автоматический rollback; сбой внешнего
сайта или нод показывает предупреждение без отката.

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
├── mihomo.new               # Скачанное обновление ядра (macOS, до подмены при перезапуске)
├── config.yaml              # Конфиг из подписки
├── GeoIP.dat                # База IP-адресов (Linux)
├── GeoSite.dat              # База доменов (Linux)
├── ASN.mmdb                 # База ASN (Linux)
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
    ├── updater.log          # Лог планового обновления (macOS)
    └── statusbar-build.log  # Лог сборки menu bar app (macOS, если была попытка компиляции)

# macOS, служебные файлы планировщика:
~/dostup/.script-update      # Флаг: вышла новая версия скрипта
~/dostup/.notify             # Очередь уведомлений для иконки в строке меню
~/dostup/.lock               # Блокировка: не даёт обновлению и перезапуску наложиться

# Linux дополнительно:
/etc/systemd/system/dostup.service   # systemd-сервис
/usr/local/bin/dostup                # CLI-обёртка
/opt/dostup/dostup-manager.sh        # единый установщик/менеджер
/opt/dostup/.known-good/             # один последний рабочий резерв
/run/dostup.lock                     # блокировка параллельных изменений
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
# Остановить menu bar app, планировщик обновлений и их LaunchAgent'ы
launchctl unload ~/Library/LaunchAgents/ru.dostup.vpn.statusbar.plist 2>/dev/null
launchctl unload ~/Library/LaunchAgents/ru.dostup.vpn.updater.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/ru.dostup.vpn.statusbar.plist
rm -f ~/Library/LaunchAgents/ru.dostup.vpn.updater.plist
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
