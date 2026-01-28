#!/bin/bash

# ============================================
# Dostup Installer for Mihomo (macOS)
# ============================================

set -e

# --- Цвета для вывода ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Пути ---
DOSTUP_DIR="$HOME/dostup"
LOGS_DIR="$DOSTUP_DIR/logs"
CONFIG_FILE="$DOSTUP_DIR/config.yaml"
SETTINGS_FILE="$DOSTUP_DIR/settings.json"
MIHOMO_BIN="$DOSTUP_DIR/mihomo"
DESKTOP_DIR="$HOME/Desktop"

# --- URL ---
MIHOMO_RELEASES_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

# --- Функции ---

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}       Dostup Installer for Mihomo${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Проверка macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "Этот скрипт работает только на macOS"
        exit 1
    fi
}

# Проверка интернета
check_internet() {
    print_step "Проверка подключения к интернету..."
    if ! curl -s --head --connect-timeout 5 https://github.com > /dev/null; then
        print_error "Нет подключения к интернету"
        return 1
    fi
    print_success "Интернет доступен"
    return 0
}

# Определение архитектуры
get_arch() {
    local arch=$(uname -m)
    if [[ "$arch" == "arm64" ]]; then
        echo "arm64"
    else
        echo "amd64"
    fi
}

# Получение последней версии mihomo
get_latest_version() {
    curl -s "$MIHOMO_RELEASES_API" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

# Скачивание mihomo
download_mihomo() {
    local arch=$(get_arch)
    local version=$(get_latest_version)

    if [[ -z "$version" ]]; then
        print_error "Не удалось получить версию mihomo"
        return 1
    fi

    print_step "Скачивание mihomo $version для $arch..."

    # Формируем URL для скачивания
    local filename="mihomo-darwin-${arch}-${version}.gz"
    local download_url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}"

    # Скачиваем с retry и прогрессом
    if ! download_with_retry "$download_url" "$DOSTUP_DIR/mihomo.gz"; then
        print_error "Не удалось скачать mihomo"
        return 1
    fi

    # Проверка SHA256
    print_step "Проверка целостности файла..."
    local checksum_url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}.sha256"
    local expected_hash
    expected_hash=$(curl -sL "$checksum_url" 2>/dev/null | awk '{print $1}')

    if [[ -n "$expected_hash" ]]; then
        local actual_hash
        actual_hash=$(shasum -a 256 "$DOSTUP_DIR/mihomo.gz" | awk '{print $1}')
        if [[ "$expected_hash" != "$actual_hash" ]]; then
            print_error "Ошибка проверки хэша! Файл повреждён."
            rm -f "$DOSTUP_DIR/mihomo.gz"
            return 1
        fi
        print_success "Хэш совпадает"
    else
        print_info "SHA256 не найден, пропуск проверки"
    fi

    # Распаковываем
    gunzip -f "$DOSTUP_DIR/mihomo.gz"
    chmod +x "$MIHOMO_BIN"

    # Снимаем карантин
    xattr -d com.apple.quarantine "$MIHOMO_BIN" 2>/dev/null || true

    # Сохраняем версию
    update_settings "installed_version" "$version"

    print_success "Mihomo $version установлен"
}

# Диалог ввода (osascript)
ask_input() {
    local prompt="$1"
    local default="$2"
    osascript -e "set result to text returned of (display dialog \"$prompt\" default answer \"$default\" buttons {\"OK\"} default button 1)" 2>/dev/null
}

# Валидация URL
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Проверка валидности YAML (без PyYAML)
validate_yaml() {
    local file="$1"
    local content
    content=$(head -c 1000 "$file" 2>/dev/null)

    # Проверяем что это не HTML-страница (ошибка сервера)
    if echo "$content" | grep -qiE '<!DOCTYPE|<html|<head'; then
        return 1
    fi

    # Проверяем базовую структуру YAML (ключ: значение или список)
    if echo "$content" | grep -qE '^[a-zA-Z_-]+:' || echo "$content" | grep -qE '^\s*-\s+'; then
        return 0
    fi

    return 1
}

# Скачивание с retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if curl -L -# -o "$output" "$url" 2>/dev/null; then
            return 0
        fi
        retry=$((retry + 1))
        print_info "Повтор скачивания ($retry/$max_retries)..."
        sleep 2
    done
    return 1
}

# Бэкап конфига
backup_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    fi
}

# Восстановление конфига из бэкапа
restore_config() {
    if [[ -f "${CONFIG_FILE}.backup" ]]; then
        mv "${CONFIG_FILE}.backup" "$CONFIG_FILE"
    fi
}

# Обновление settings.json
update_settings() {
    local key="$1"
    local value="$2"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    # Используем Python для JSON (есть на всех Mac)
    python3 << EOF
import json
with open("$SETTINGS_FILE", "r") as f:
    data = json.load(f)
data["$key"] = "$value"
with open("$SETTINGS_FILE", "w") as f:
    json.dump(data, f, indent=2)
EOF
}

# Чтение из settings.json
read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        python3 -c "import json; print(json.load(open('$SETTINGS_FILE')).get('$key', ''))" 2>/dev/null
    fi
}

# Скачивание конфига
download_config() {
    local url="$1"
    print_step "Скачивание конфига..."

    # Бэкап старого конфига
    backup_config

    # Скачиваем во временный файл
    local temp_config="${CONFIG_FILE}.tmp"
    if ! download_with_retry "$url" "$temp_config"; then
        print_error "Не удалось скачать конфиг"
        restore_config
        return 1
    fi

    # Проверяем валидность YAML
    if ! validate_yaml "$temp_config"; then
        print_error "Скачанный конфиг не является валидным YAML"
        rm -f "$temp_config"
        restore_config
        return 1
    fi

    # Всё ок, заменяем конфиг
    mv "$temp_config" "$CONFIG_FILE"
    print_success "Конфиг скачан и проверен"
    return 0
}

# Скачивание geo-баз
download_geo() {
    print_step "Скачивание geo-баз..."

    local success=true

    if ! download_with_retry "$GEOIP_URL" "$DOSTUP_DIR/geoip.dat"; then
        print_error "Не удалось скачать geoip.dat"
        success=false
    fi

    if ! download_with_retry "$GEOSITE_URL" "$DOSTUP_DIR/geosite.dat"; then
        print_error "Не удалось скачать geosite.dat"
        success=false
    fi

    if $success; then
        update_settings "last_geo_update" "$(date +%Y-%m-%d)"
        print_success "Geo-базы скачаны"
    fi
}

# Создание скрипта запуска
create_start_script() {
    cat > "$DOSTUP_DIR/dostup-start.command" << 'STARTSCRIPT'
#!/bin/bash

# --- Dostup Start Script ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOSTUP_DIR="$HOME/dostup"
SETTINGS_FILE="$DOSTUP_DIR/settings.json"
MIHOMO_BIN="$DOSTUP_DIR/mihomo"
CONFIG_FILE="$DOSTUP_DIR/config.yaml"

MIHOMO_RELEASES_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

echo ""
echo -e "${BLUE}=== Dostup Start ===${NC}"
echo ""

# Проверка: уже запущен?
if pgrep -x "mihomo" > /dev/null; then
    echo -e "${YELLOW}Mihomo уже запущен${NC}"
    echo ""
    echo "Панель управления: https://metacubex.github.io/metacubexd/"
    echo "API: 127.0.0.1:9090"
    echo ""
    read -p "Нажмите Enter для закрытия..."
    exit 0
fi

# Функции
read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        python3 -c "import json; print(json.load(open('$SETTINGS_FILE')).get('$key', ''))" 2>/dev/null
    fi
}

update_settings() {
    local key="$1"
    local value="$2"
    python3 << EOF
import json
with open("$SETTINGS_FILE", "r") as f:
    data = json.load(f)
data["$key"] = "$value"
with open("$SETTINGS_FILE", "w") as f:
    json.dump(data, f, indent=2)
EOF
}

get_latest_version() {
    curl -s "$MIHOMO_RELEASES_API" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local retry=0
    while [[ $retry -lt 3 ]]; do
        if curl -L -# -o "$output" "$url" 2>/dev/null; then
            return 0
        fi
        retry=$((retry + 1))
        echo -e "${YELLOW}ℹ Повтор ($retry/3)...${NC}"
        sleep 2
    done
    return 1
}

validate_yaml() {
    local content=$(head -c 1000 "$1" 2>/dev/null)
    # Не HTML и содержит YAML-структуру
    ! echo "$content" | grep -qiE '<!DOCTYPE|<html' && echo "$content" | grep -qE '^[a-zA-Z_-]+:|^\s*-\s+'
}

# Проверка обновлений ядра
echo -e "${YELLOW}▶ Проверка обновлений ядра...${NC}"
current_version=$(read_settings "installed_version")
latest_version=$(get_latest_version)

if [[ -n "$latest_version" && "$current_version" != "$latest_version" ]]; then
    echo -e "${YELLOW}▶ Обновление ядра: $current_version → $latest_version${NC}"
    arch=$(uname -m)
    [[ "$arch" == "arm64" ]] && arch="arm64" || arch="amd64"
    filename="mihomo-darwin-${arch}-${latest_version}.gz"
    download_url="https://github.com/MetaCubeX/mihomo/releases/download/${latest_version}/${filename}"

    if download_with_retry "$download_url" "$DOSTUP_DIR/mihomo.gz"; then
        gunzip -f "$DOSTUP_DIR/mihomo.gz"
        chmod +x "$MIHOMO_BIN"
        xattr -d com.apple.quarantine "$MIHOMO_BIN" 2>/dev/null || true
        update_settings "installed_version" "$latest_version"
        echo -e "${GREEN}✓ Ядро обновлено${NC}"
    else
        echo -e "${RED}✗ Не удалось обновить ядро, используем текущую версию${NC}"
    fi
else
    echo -e "${GREEN}✓ Ядро актуально${NC}"
fi

# Скачивание конфига
echo -e "${YELLOW}▶ Скачивание конфига...${NC}"
sub_url=$(read_settings "subscription_url")
if [[ -n "$sub_url" ]]; then
    # Бэкап старого конфига
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"

    temp_config="${CONFIG_FILE}.tmp"
    if download_with_retry "$sub_url" "$temp_config"; then
        if validate_yaml "$temp_config"; then
            mv "$temp_config" "$CONFIG_FILE"
            echo -e "${GREEN}✓ Конфиг обновлён${NC}"
        else
            echo -e "${RED}✗ Конфиг невалидный YAML, используем старый${NC}"
            rm -f "$temp_config"
            [[ -f "${CONFIG_FILE}.backup" ]] && mv "${CONFIG_FILE}.backup" "$CONFIG_FILE"
        fi
    else
        echo -e "${RED}✗ Не удалось скачать конфиг, используем старый${NC}"
        [[ -f "${CONFIG_FILE}.backup" ]] && mv "${CONFIG_FILE}.backup" "$CONFIG_FILE"
    fi
else
    echo -e "${RED}✗ URL подписки не задан${NC}"
fi

# Обновление geo-баз (раз в 2 недели)
last_geo=$(read_settings "last_geo_update")
if [[ -n "$last_geo" ]]; then
    last_ts=$(date -j -f "%Y-%m-%d" "$last_geo" "+%s" 2>/dev/null || echo 0)
    now_ts=$(date "+%s")
    diff_days=$(( (now_ts - last_ts) / 86400 ))

    if [[ $diff_days -ge 14 ]]; then
        echo -e "${YELLOW}▶ Обновление geo-баз...${NC}"
        curl -L -o "$DOSTUP_DIR/geoip.dat" "$GEOIP_URL" 2>/dev/null
        curl -L -o "$DOSTUP_DIR/geosite.dat" "$GEOSITE_URL" 2>/dev/null
        update_settings "last_geo_update" "$(date +%Y-%m-%d)"
        echo -e "${GREEN}✓ Geo-базы обновлены${NC}"
    fi
fi

# Запуск
echo -e "${YELLOW}▶ Запуск Mihomo (требуется пароль администратора)...${NC}"
echo ""

# Сначала получаем sudo-права (запрос пароля)
if ! sudo -v; then
    echo -e "${RED}✗ Не удалось получить права администратора${NC}"
    read -p "Нажмите Enter для закрытия..."
    exit 1
fi

# Запускаем полностью отвязанным от терминала
sudo sh -c "nohup '$MIHOMO_BIN' -d '$DOSTUP_DIR' > '$DOSTUP_DIR/logs/mihomo.log' 2>&1 &"

sleep 2

if pgrep -x "mihomo" > /dev/null; then
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}✓ Mihomo успешно запущен!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Панель управления: https://metacubex.github.io/metacubexd/"
    echo "API: 127.0.0.1:9090"
    echo ""
    echo "Окно закроется через 5 секунд..."
    # Запускаем закрытие в фоне и сразу выходим, чтобы не было предупреждения
    (sleep 5 && osascript -e 'tell application "Terminal" to close front window saving no' &) 2>/dev/null
    exit 0
else
    echo -e "${RED}✗ Не удалось запустить Mihomo${NC}"
    echo "Проверьте логи: $DOSTUP_DIR/logs/mihomo.log"
    echo ""
    read -p "Нажмите Enter для закрытия..."
fi
STARTSCRIPT

    chmod +x "$DOSTUP_DIR/dostup-start.command"
}

# Создание скрипта остановки
create_stop_script() {
    cat > "$DOSTUP_DIR/dostup-stop.command" << 'STOPSCRIPT'
#!/bin/bash

# --- Dostup Stop Script ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=== Dostup Stop ===${NC}"
echo ""

if ! pgrep -x "mihomo" > /dev/null; then
    echo -e "${YELLOW}Mihomo не запущен${NC}"
    echo ""
    echo "Окно закроется через 2 секунды..."
    (sleep 2 && osascript -e 'tell application "Terminal" to close front window saving no' &) 2>/dev/null
    exit 0
fi

echo -e "${YELLOW}▶ Остановка Mihomo (требуется пароль администратора)...${NC}"
echo ""

sudo pkill mihomo

sleep 2

if ! pgrep -x "mihomo" > /dev/null; then
    echo ""
    echo -e "${GREEN}✓ Mihomo остановлен${NC}"
    echo ""
    echo "Окно закроется через 3 секунды..."
    (sleep 3 && osascript -e 'tell application "Terminal" to close front window saving no' &) 2>/dev/null
    exit 0
else
    echo -e "${RED}✗ Не удалось остановить Mihomo${NC}"
    echo "Попробуйте: sudo pkill -9 mihomo"
    echo ""
    read -p "Нажмите Enter для закрытия..."
fi
STOPSCRIPT

    chmod +x "$DOSTUP_DIR/dostup-stop.command"
}

# Создание ярлыков на рабочем столе
create_desktop_shortcuts() {
    print_step "Создание ярлыков на рабочем столе..."

    cp "$DOSTUP_DIR/dostup-start.command" "$DESKTOP_DIR/Dostup Start.command"
    cp "$DOSTUP_DIR/dostup-stop.command" "$DESKTOP_DIR/Dostup Stop.command"

    chmod +x "$DESKTOP_DIR/Dostup Start.command"
    chmod +x "$DESKTOP_DIR/Dostup Stop.command"

    print_success "Ярлыки созданы на рабочем столе"
}

# Запуск mihomo
start_mihomo() {
    print_step "Запуск Mihomo (требуется пароль администратора)..."
    echo ""

    # Сначала получаем sudo-права (запрос пароля)
    if ! sudo -v; then
        print_error "Не удалось получить права администратора"
        return 1
    fi

    # Запускаем полностью отвязанным от терминала
    sudo sh -c "nohup '$MIHOMO_BIN' -d '$DOSTUP_DIR' > '$LOGS_DIR/mihomo.log' 2>&1 &"

    sleep 2

    if pgrep -x "mihomo" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Показ финального сообщения
show_success_message() {
    osascript << EOF
display dialog "Mihomo успешно установлен и запущен!

Панель управления:
https://metacubex.github.io/metacubexd/

API: 127.0.0.1:9090

На рабочем столе созданы ярлыки:
• Dostup Start — для запуска
• Dostup Stop — для остановки" buttons {"OK"} default button 1 with title "Dostup"
EOF
}

# ============================================
# MAIN
# ============================================

print_header

# Проверки
check_macos

# Проверка: первый запуск или нет?
if [[ -f "$MIHOMO_BIN" && -f "$SETTINGS_FILE" ]]; then
    print_info "Обнаружена существующая установка"
    print_info "Запустите 'Dostup Start' с рабочего стола для запуска"
    echo ""
    read -p "Нажмите Enter для закрытия..."
    exit 0
fi

# Проверка интернета
if ! check_internet; then
    echo ""
    read -p "Нажмите Enter для закрытия..."
    exit 1
fi

# Создание папок
print_step "Создание папки ~/dostup..."
mkdir -p "$DOSTUP_DIR"
mkdir -p "$LOGS_DIR"
print_success "Папка создана"

# Скачивание ядра
if ! download_mihomo; then
    print_error "Установка прервана"
    read -p "Нажмите Enter для закрытия..."
    exit 1
fi

# Запрос URL подписки
print_step "Настройка подписки..."
SUB_URL=$(ask_input "Введите URL подписки (конфига):" "")

if [[ -z "$SUB_URL" ]]; then
    print_error "URL подписки не указан"
    read -p "Нажмите Enter для закрытия..."
    exit 1
fi

# Валидация URL
if ! validate_url "$SUB_URL"; then
    print_error "Неверный формат URL. URL должен начинаться с http:// или https://"
    read -p "Нажмите Enter для закрытия..."
    exit 1
fi

update_settings "subscription_url" "$SUB_URL"

# Скачивание конфига
if ! download_config "$SUB_URL"; then
    print_error "Не удалось скачать конфиг"
    read -p "Нажмите Enter для закрытия..."
    exit 1
fi

# Скачивание geo-баз
download_geo

# Создание скриптов
print_step "Создание скриптов..."
create_start_script
create_stop_script
print_success "Скрипты созданы"

# Ярлыки на рабочем столе
create_desktop_shortcuts

# Первый запуск
echo ""
if start_mihomo; then
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}    Установка завершена успешно!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Панель управления: https://metacubex.github.io/metacubexd/"
    echo "API: 127.0.0.1:9090"
    echo ""
    echo "Ярлыки на рабочем столе:"
    echo "  • Dostup Start — для запуска"
    echo "  • Dostup Stop — для остановки"
    echo ""

    show_success_message
else
    print_error "Не удалось запустить Mihomo"
    echo "Проверьте логи: $LOGS_DIR/mihomo.log"
fi

echo ""
echo "Окно закроется через 5 секунд..."
(sleep 5 && osascript -e 'tell application "Terminal" to close front window saving no' &) 2>/dev/null
exit 0
