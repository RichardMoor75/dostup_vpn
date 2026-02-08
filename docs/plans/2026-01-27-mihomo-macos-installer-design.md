# Mihomo macOS Installer — Design Document

**Дата:** 2026-01-27
**Статус:** Утверждён (исторический документ, актуальная реализация значительно расширена)

---

## Цель

Создать простой установщик Mihomo для macOS, который можно отправить через Telegram. Пользователь скачивает один файл, кликает — и всё настраивается автоматически.

---

## Файлы

### Что отправляется пользователю:
```
dostup-install.command    # Единственный файл для установки
```

### Что создаётся после установки:
```
~/dostup/
├── mihomo                  # Ядро (скачивается автоматически)
├── config.yaml             # Конфиг подписки
├── settings.json           # Настройки (URL, даты обновлений)
├── geoip.dat               # Geo-база IP
├── geosite.dat             # Geo-база доменов
├── dostup-start.command    # Скрипт запуска
├── dostup-stop.command     # Скрипт остановки
└── logs/
    └── mihomo.log          # Логи

~/Desktop/
├── Dostup Start.command    # Ярлык запуска
└── Dostup Stop.command     # Ярлык остановки

~/Library/LaunchAgents/
└── com.dostup.mihomo.plist # Автозапуск (опционально)
```

---

## Логика установщика (dostup-install.command)

1. **Проверка окружения**
   - Убедиться что это macOS
   - Проверить доступ в интернет

2. **Определение типа Mac**
   - Apple Silicon (arm64) → mihomo-darwin-arm64
   - Intel (x86_64) → mihomo-darwin-amd64

3. **Создание структуры**
   - `mkdir -p ~/dostup/logs`

4. **Скачивание ядра**
   - Получить последнюю версию с GitHub API (MetaCubeX/mihomo)
   - Скачать нужный архив
   - Распаковать в ~/dostup/mihomo
   - `chmod +x`
   - `xattr -d com.apple.quarantine` — снять карантин

5. **Настройка подписки**
   - Показать диалог для ввода URL подписки (osascript)
   - Скачать конфиг → ~/dostup/config.yaml
   - Скачать geoip.dat и geosite.dat

6. **Создание скриптов**
   - Сгенерировать dostup-start.command
   - Сгенерировать dostup-stop.command
   - `chmod +x` для обоих

7. **Ярлыки на рабочий стол**
   - Скопировать скрипты на ~/Desktop/

8. **Автозапуск (опционально)**
   - Спросить пользователя через диалог
   - Если да → создать LaunchAgent + setuid бит

9. **Первый запуск**
   - Запросить пароль (sudo)
   - Запустить mihomo
   - Показать сообщение с адресом панели

---

## Логика скрипта запуска (dostup-start.command)

1. **Проверка статуса**
   - Если mihomo уже запущен → сообщение и выход

2. **Проверка обновлений ядра**
   - Сравнить текущую версию с последней на GitHub
   - Если есть новая → обновить

3. **Скачивание конфига**
   - Скачать по URL из settings.json
   - При ошибке → использовать старый

4. **Обновление geo-баз (раз в 2 недели)**
   - Проверить last_geo_update в settings.json
   - Если > 14 дней → скачать новые

5. **Запуск**
   - `sudo ~/dostup/mihomo -d ~/dostup/`
   - Проверить что процесс запустился

6. **Сообщение об успехе**
   - Показать адрес панели: https://metacubex.github.io/metacubexd/
   - API: 127.0.0.1:9090
   - Закрыть окно через 5 сек

---

## Логика скрипта остановки (dostup-stop.command)

1. **Проверка статуса**
   - Если не запущен → сообщение и выход

2. **Остановка**
   - `sudo pkill mihomo`

3. **Проверка**
   - Убедиться что остановлен
   - Закрыть окно через 3 сек

---

## Обработка ошибок

- При ошибках показать сообщение, но попытаться запустить с имеющимися файлами
- Если ядро и конфиг уже есть — запуск возможен даже без интернета

---

## Безопасность macOS

### Карантин скачанных файлов
- Пользователю нужно: ПКМ → "Открыть" при первом запуске установщика
- Для mihomo: автоматически снимаем `xattr -d com.apple.quarantine`

### Права для TUN
- Требуется sudo для запуска
- Для автозапуска: setuid бит (`chmod +s`)

---

## settings.json

```json
{
  "subscription_url": "https://...",
  "installed_version": "1.18.0",
  "last_geo_update": "2026-01-27",
  "autostart_enabled": false
}
```

---

## URL для скачивания

- **Ядро:** https://github.com/MetaCubeX/mihomo/releases/latest
- **GeoIP:** https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat
- **GeoSite:** https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat
- **Панель:** https://metacubex.github.io/metacubexd/
