# Dostup VPN: Linux Installer Design

**Дата:** 2026-02-05
**Статус:** Утверждён

## Общее

Установочный скрипт Mihomo для серверных Ubuntu/Debian систем. Одно-командная установка, управление через CLI-обёртку `dostup`, работа через systemd.

## Целевая платформа

- Ubuntu / Debian (headless, без GUI)
- Архитектуры: amd64, arm64

## Архитектура

### Структура файлов

```
/opt/dostup/                    # Рабочая директория
├── mihomo                       # Бинарник
├── config.yaml                  # Обработанный конфиг
├── config.yaml.bak              # Бэкап предыдущего конфига
├── settings.json                # Метаданные (subscription_url, версия, порт, дата geo)
├── sites.json                   # Список сайтов для проверки доступа
├── geoip.dat                    # Geo-база IP
├── geosite.dat                  # Geo-база доменов
└── logs/
    └── mihomo.log               # Логи

/etc/systemd/system/dostup.service  # systemd unit
/usr/local/bin/dostup               # CLI-обёртка
```

### Установка

```bash
wget <url>/dostup-install.sh && sudo bash dostup-install.sh
```

### Поток установки

1. `check_root()` — проверка запуска от root
2. `check_os()` — проверка Ubuntu/Debian (через /etc/os-release)
3. `check_internet()` — curl -s --max-time 5 https://github.com
4. `detect_arch()` — uname -m → amd64 / arm64
5. `install_dependencies()` — apt install -y curl jq (если отсутствуют)
6. `download_mihomo()` — скачать с GitHub, 3 попытки, SHA256
7. `ask_subscription_url()` — read -p в терминале, валидация URL
8. `download_config()` — curl по subscription URL, 3 попытки
9. `validate_config()` — проверка на HTML, наличие ключевых полей
10. `process_config()` — обработка конфига (см. ниже)
11. `download_geodata()` — geoip.dat + geosite.dat
12. `create_settings()` — settings.json
13. `create_sites_json()` — список сайтов для проверки
14. `install_service()` — systemd unit + systemctl enable
15. `install_cli()` — /usr/local/bin/dostup
16. `start_service()` — systemctl start dostup
17. `show_result()` — финальный вывод с инструкцией

## Обработка конфига

При скачивании YAML выполняются преобразования через sed/awk (без Python).

### Удаление

- Строки: `external-controller`, `external-ui`, `external-ui-url`
- Блок `tun:` — от `tun:` до следующего ключа верхнего уровня (строка без начального пробела)
- Блок `rule-providers:` — аналогично
- Все строки в `rules:`, содержащие `RULE-SET`

### Модификация

- `dns.listen`: `0.0.0.0:53` → `127.0.0.1:1053`
- `mixed-port`: проверка через `ss -tlnp | grep :PORT`. Если занят — поиск свободного (начиная с 2080, шаг +1)

### Валидация

- Проверка что файл не HTML (ошибка сервера)
- Проверка наличия ключевых полей: `mixed-port`, `proxy-groups`
- Бэкап предыдущего конфига перед заменой

## systemd-сервис

```ini
[Unit]
Description=Dostup VPN (Mihomo)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/dostup/mihomo -f /opt/dostup/config.yaml
Restart=on-failure
RestartSec=3
User=root
LimitNOFILE=65535
WorkingDirectory=/opt/dostup

[Install]
WantedBy=multi-user.target
```

## CLI-обёртка `dostup`

Bash-скрипт в `/usr/local/bin/dostup`:

| Команда | Действие |
|---|---|
| `dostup start` | `systemctl start dostup` |
| `dostup stop` | `systemctl stop dostup` |
| `dostup restart` | Обновление конфига/ядра/geo + `systemctl restart dostup` |
| `dostup update` | Синоним restart |
| `dostup status` | `systemctl status dostup` + порт, PID, uptime |
| `dostup check` | Проверка доступа к сайтам через прокси (`curl -x`) |
| `dostup log` | `journalctl -u dostup -f` |
| `dostup uninstall` | Остановка, удаление /opt/dostup, сервиса, CLI |
| `dostup help` | Справка по командам |

### Логика restart/update

1. Проверить обновление ядра Mihomo (GitHub API vs settings.json)
2. Скачать свежий конфиг по subscription URL → обработать
3. Обновить geo-базы если прошло >14 дней
4. `systemctl restart dostup`

### Логика check

- Читает sites.json
- Для каждого URL: `curl -x http://127.0.0.1:PORT -s -o /dev/null -w "%{http_code}" --max-time 5 URL`
- Зелёный ✓ (200-399) / Красный ✗ (остальное)

## Вывод после установки

```
════════════════════════════════════════════
  ✓ Dostup VPN установлен и запущен
════════════════════════════════════════════

  Прокси:        http://127.0.0.1:2080
  Статус:        dostup status
  Управление:    dostup start|stop|restart
  Проверка:      dostup check
  Логи:          dostup log

  ── Использование прокси ──

  Разовый запуск программы через прокси:
    HTTPS_PROXY=http://127.0.0.1:2080 HTTP_PROXY=http://127.0.0.1:2080 curl ifconfig.me

  Добавьте алиасы в ~/.bashrc для удобства:
    alias px='HTTPS_PROXY=http://127.0.0.1:2080 HTTP_PROXY=http://127.0.0.1:2080'
    alias codex='px codex'
    alias claude='px claude'
    alias npm='px npm'
    alias pip='px pip'

  Или включите прокси для всей сессии:
    export HTTPS_PROXY=http://127.0.0.1:2080
    export HTTP_PROXY=http://127.0.0.1:2080

════════════════════════════════════════════
```

Порт подставляется динамически из settings.json.

## Зависимости

- `curl` — скачивание, проверка доступа
- `jq` — парсинг settings.json и GitHub API

Оба ставятся через `apt install -y` автоматически.

## Что НЕ делаем (YAGNI)

- GUI-диалоги, ярлыки на рабочем столе
- Поддержка Fedora/Arch/других дистрибутивов
- Настройка файрвола
- Веб-панель управления
- TUN-режим

## Файлы проекта

- `dostup-install.sh` — установочный скрипт (~500-600 строк)
- `ИНСТРУКЦИЯ_LINUX.txt` — пользовательская инструкция на русском
