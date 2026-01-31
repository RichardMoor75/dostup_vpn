# MEMORY

## Project Goal
Создание установщика Mihomo (VPN) для macOS и Windows — пользователь вставляет одну команду в терминал, и всё настраивается автоматически.

## Tech Stack
- Bash (.command скрипты для macOS)
- PowerShell (.ps1 скрипты для Windows)
- Python3 (для работы с JSON, встроен в macOS)
- osascript (нативные диалоги macOS с fallback на терминал)

## Server Hosting
Скрипты размещены на сервере для простой установки:
- URL: `https://files.richard-moor.ru/Install/dostup_vpn/`
- Локальный путь для деплоя: `/media/rishat/Cloud/rawfiles/rawfiles/Install/dostup_vpn/`
- Файлы: `dostup-install.command`, `dostup-install.ps1`, `icon.ico`, `icon.icns`, инструкции

## Installation Commands
**macOS:**
```
curl -sL https://files.richard-moor.ru/Install/dostup_vpn/dostup-install.command | bash
```

**Windows:**
```
irm https://files.richard-moor.ru/Install/dostup_vpn/dostup-install.ps1 | iex
```

## Features
- Автоопределение архитектуры (Intel/Apple Silicon, amd64/arm64/386)
- Скачивание ядра mihomo с GitHub с retry (3 попытки)
- Проверка SHA256 хэша (если доступен)
- Диалог для ввода URL подписки (GUI с fallback на терминал)
- Валидация URL подписки
- Скачивание и валидация конфига (проверка YAML)
- Бэкап конфига перед обновлением
- Скачивание geo-баз (geoip.dat, geosite.dat)
- Единый скрипт управления `Dostup_VPN` (запуск/остановка/перезапуск) с автообновлением
- Создание одного ярлыка на рабочем столе (старые удаляются при переустановке)
- Кастомная иконка для ярлыков (автоматическое скачивание и применение)
- Автозакрытие окон (с fallback на Enter)
- Автонастройка брандмауэра Windows (удаление блокировок, создание разрешений)

## Completed
- [x] macOS установщик (`dostup-install.command`)
- [x] Windows установщик (`dostup-install.ps1`)
- [x] Инструкции (`ИНСТРУКЦИЯ.txt`, `ИНСТРУКЦИЯ_WINDOWS.txt`)
- [x] Размещение на сервере для one-liner установки
- [x] Удалена опция автозагрузки (не нужна)
- [x] Добавлены retry, валидация YAML, бэкап конфига
- [x] Добавлена проверка SHA256 хэша
- [x] Fallback на терминальный ввод если GUI не работает
- [x] Переустановка: всегда удаляет старую установку, останавливает mihomo, спрашивает о подписке
- [x] Единый скрипт управления `Dostup_VPN` вместо отдельных start/stop (один ярлык на рабочем столе)
- [x] Кастомная иконка (котик) для ярлыков — автоскачивание и применение через JXA (macOS) / IconLocation (Windows)

## ВАЖНО: Workflow
- **После любых изменений в скриптах — ВСЕГДА копировать в `/media/rishat/Cloud/rawfiles/rawfiles/Install/dostup_vpn/`**
- Прежде чем что-то менять — сначала обсудить с объяснениями
- Общаться на русском языке

## Notes
- GUI диалоги через osascript могут не работать на Mac без Xcode — используется fallback на терминал
- SHA256 файлы не публикуются для mihomo — проверка пропускается если хэш недоступен
- Windows Firewall: автонастройка через netsh с UAC (удаляет все правила для mihomo.exe включая блокировки, создаёт разрешающие)
- Windows 7/8 поддерживается: fallback для PowerShell < 5 (Expand-ZipFile, Get-FileSHA256) и netsh для брандмауэра
- macOS Application Firewall: автонастройка через socketfilterfw (--add и --unblockapp)
