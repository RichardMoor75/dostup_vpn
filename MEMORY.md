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
- Единый скрипт управления `Dostup_VPN` (запуск/остановка/перезапуск/проверка доступа) с автообновлением
- Проверка доступа к заблокированным ресурсам (список в `sites.json`)
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
- [x] Windows: HTML-фильтр в валидаторе YAML (защита от ошибок сервера)
- [x] Geo-базы: дата обновления записывается только при успешном скачивании
- [x] Windows control script: безопасный парсинг даты с try/catch
- [x] macOS: защита от injection в osascript (экранирование кавычек)
- [x] macOS: защита от injection в Python (передача через env variables)
- [x] Остановка mihomo: цикл ожидания с timeout вместо фиксированного sleep (race condition fix)
- [x] macOS: фикс закрытия окна терминала (osascript в фоне + disown, чтобы не было диалога подтверждения)
- [x] Проверка доступа к ресурсам: опция в меню + `sites.json` с редактируемым списком сайтов
- [x] Добавлен flibusta.is в список сайтов по умолчанию
- [x] Переписаны инструкции для пользователей (ASCII-схема меню, подробные шаги, troubleshooting)
- [x] Добавлен файл LICENSE (MIT)
- [x] Код-ревью: удалён дублированный exit, исправлено unsafe чтение sites.json, согласована проверка `<head` в validate_yaml
- [x] macOS: заменён .command ярлык на .app bundle (Dostup_VPN.app) — нет видимого расширения
- [x] Windows 7/8/8.1: полная поддержка старых систем:
  - TLS 1.2 включается явно (старый PowerShell использует TLS 1.0 по умолчанию)
  - User-Agent header для GitHub API (без него 403)
  - Синтаксис New-Object вместо ::new() (PowerShell 4 совместимость)
  - JSON без BOM (WriteAllText вместо Set-Content -Encoding UTF8)
  - Чтение settings.json с try/catch и fallback
  - Compatible build mihomo для старых Windows (mihomo-windows-amd64-compatible)
  - TUN блок удаляется из конфига (драйвер wintun проблемный на Win 8)
  - Автоматическая настройка системного прокси (реестр) при запуске/остановке
  - Проверка доступа к сайтам через прокси

## ВАЖНО: Workflow
- **После любых изменений в скриптах — ВСЕГДА копировать в `/media/rishat/Cloud/rawfiles/rawfiles/Install/dostup_vpn/`**
- Прежде чем что-то менять — сначала обсудить с объяснениями
- Общаться на русском языке

## Notes
- GUI диалоги через osascript могут не работать на Mac без Xcode — используется fallback на терминал
- SHA256 файлы не публикуются для mihomo — проверка пропускается если хэш недоступен
- Windows Firewall: автонастройка через netsh с UAC (удаляет все правила для mihomo.exe включая блокировки, создаёт разрешающие)
- Windows 7/8/8.1 полностью поддерживается: compatible build, системный прокси вместо TUN, совместимый синтаксис PowerShell
- Firefox на Win 7/8 может требовать ручной настройки прокси (Настройки → Сеть → "Использовать системные настройки прокси")
- macOS Application Firewall: автонастройка через socketfilterfw (--add и --unblockapp)
- Безопасность: все входные данные экранируются перед использованием в osascript/python
- Остановка процесса: используется цикл ожидания (до 10 сек) для надёжности
