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
ICON_URL="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/icon.icns"

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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
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

    # Проверка SHA256 (если доступен)
    print_step "Проверка целостности файла..."
    local checksum_url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}.sha256"
    local expected_hash
    expected_hash=$(curl -sL --fail "$checksum_url" 2>/dev/null | awk '{print $1}')

    # Проверяем что хэш выглядит как SHA256 (64 hex символа)
    if [[ "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]]; then
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

# Диалог ввода (osascript с fallback на терминал)
ask_input() {
    local prompt="$1"
    local default="$2"
    local result

    # Экранируем кавычки и бэкслеши для AppleScript
    local safe_prompt="${prompt//\\/\\\\}"
    safe_prompt="${safe_prompt//\"/\\\"}"
    local safe_default="${default//\\/\\\\}"
    safe_default="${safe_default//\"/\\\"}"

    # Пробуем osascript (GUI диалог)
    result=$(osascript -e "set result to text returned of (display dialog \"$safe_prompt\" default answer \"$safe_default\" buttons {\"OK\"} default button 1)" 2>/dev/null)
    local osascript_exit=$?

    # Если osascript не сработал (ошибка GUI) - используем терминал
    if [[ $osascript_exit -ne 0 ]]; then
        echo ""
        read -p "$prompt " result < /dev/tty
    fi

    echo "$result"
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
        if curl -fL --connect-timeout 10 --max-time 120 -# -o "$output" "$url" 2>/dev/null; then
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
    # Передаём значения через env variables для безопасности
    SETTINGS_FILE="$SETTINGS_FILE" KEY="$key" VALUE="$value" python3 << 'EOF'
import json, os
settings_file = os.environ['SETTINGS_FILE']
key = os.environ['KEY']
value = os.environ['VALUE']
with open(settings_file, "r") as f:
    data = json.load(f)
data[key] = value
with open(settings_file, "w") as f:
    json.dump(data, f, indent=2)
EOF
}

# Чтение из settings.json
read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        SETTINGS_FILE="$SETTINGS_FILE" KEY="$key" python3 -c "import json, os; print(json.load(open(os.environ['SETTINGS_FILE'])).get(os.environ['KEY'], ''))" 2>/dev/null
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

# Создание файла sites.json для проверки доступа
create_sites_json() {
    local sites_file="$DOSTUP_DIR/sites.json"
    if [[ ! -f "$sites_file" ]]; then
        cat > "$sites_file" << 'EOF'
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
EOF
    fi
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

# Создание скрипта управления (единый start/stop)
create_control_script() {
    cat > "$DOSTUP_DIR/Dostup_VPN.command" << 'CONTROLSCRIPT'
#!/bin/bash

# --- Dostup VPN Control Script ---

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
SITES_FILE="$DOSTUP_DIR/sites.json"

# Функции
read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        SETTINGS_FILE="$SETTINGS_FILE" KEY="$key" python3 -c "import json, os; print(json.load(open(os.environ['SETTINGS_FILE'])).get(os.environ['KEY'], ''))" 2>/dev/null
    fi
}

update_settings() {
    local key="$1"
    local value="$2"
    SETTINGS_FILE="$SETTINGS_FILE" KEY="$key" VALUE="$value" python3 << 'EOF'
import json, os
settings_file = os.environ['SETTINGS_FILE']
key = os.environ['KEY']
value = os.environ['VALUE']
with open(settings_file, "r") as f:
    data = json.load(f)
data[key] = value
with open(settings_file, "w") as f:
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
        if curl -fL --connect-timeout 10 --max-time 120 -# -o "$output" "$url" 2>/dev/null; then
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
    ! echo "$content" | grep -qiE '<!DOCTYPE|<html|<head' && echo "$content" | grep -qE '^[a-zA-Z_-]+:|^\s*-\s+'
}

do_check_access() {
    echo ""
    echo -e "${YELLOW}▶ Проверка доступа к ресурсам...${NC}"
    echo ""

    if [[ ! -f "$SITES_FILE" ]]; then
        echo -e "${RED}✗ Файл sites.json не найден${NC}"
        return 1
    fi

    # Читаем сайты из JSON (безопасно через env variable)
    local sites
    sites=$(SITES_FILE="$SITES_FILE" python3 -c "import json, os; print('\n'.join(json.load(open(os.environ['SITES_FILE']))['sites']))" 2>/dev/null)

    if [[ -z "$sites" ]]; then
        echo -e "${RED}✗ Не удалось прочитать список сайтов${NC}"
        return 1
    fi

    while IFS= read -r site; do
        # Проверяем доступность через curl с таймаутом 5 сек
        if curl -s --head --connect-timeout 5 --max-time 10 "https://$site" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ $site — доступен${NC}"
        else
            echo -e "${RED}✗ $site — недоступен${NC}"
        fi
    done <<< "$sites"

    echo ""
}

do_stop() {
    echo -e "${YELLOW}▶ Остановка Mihomo (требуется пароль администратора)...${NC}"
    echo ""
    sudo pkill -9 mihomo 2>/dev/null || true
    # Ожидание с timeout
    stop_timeout=10
    while pgrep -x "mihomo" > /dev/null && [[ $stop_timeout -gt 0 ]]; do
        sleep 1
        stop_timeout=$((stop_timeout - 1))
    done
    if ! pgrep -x "mihomo" > /dev/null; then
        echo -e "${GREEN}✓ Mihomo остановлен${NC}"
        return 0
    else
        echo -e "${RED}✗ Не удалось остановить Mihomo${NC}"
        echo "Попробуйте перезагрузить компьютер"
        return 1
    fi
}

do_start() {
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
    should_update_geo=false
    last_geo=$(read_settings "last_geo_update")
    if [[ -n "$last_geo" ]]; then
        last_ts=$(date -j -f "%Y-%m-%d" "$last_geo" "+%s" 2>/dev/null || echo 0)
        now_ts=$(date "+%s")
        diff_days=$(( (now_ts - last_ts) / 86400 ))
        [[ $diff_days -ge 14 ]] && should_update_geo=true
    else
        should_update_geo=true
    fi

    if $should_update_geo; then
        echo -e "${YELLOW}▶ Обновление geo-баз...${NC}"
        geo_ok=true
        if ! download_with_retry "$GEOIP_URL" "$DOSTUP_DIR/geoip.dat"; then
            echo -e "${RED}✗ Не удалось скачать geoip.dat${NC}"
            geo_ok=false
        fi
        if ! download_with_retry "$GEOSITE_URL" "$DOSTUP_DIR/geosite.dat"; then
            echo -e "${RED}✗ Не удалось скачать geosite.dat${NC}"
            geo_ok=false
        fi
        if $geo_ok; then
            update_settings "last_geo_update" "$(date +%Y-%m-%d)"
            echo -e "${GREEN}✓ Geo-базы обновлены${NC}"
        fi
    fi

    # Запуск
    echo -e "${YELLOW}▶ Запуск Mihomo (требуется пароль администратора)...${NC}"
    echo ""

    if ! sudo -v; then
        echo -e "${RED}✗ Не удалось получить права администратора${NC}"
        return 1
    fi

    # Настройка Application Firewall
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$MIHOMO_BIN" 2>/dev/null
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$MIHOMO_BIN" 2>/dev/null

    # Создаём лог-файл от текущего пользователя (чтобы не был root-owned)
    : > "$DOSTUP_DIR/logs/mihomo.log"

    # Запускаем
    sudo sh -c "nohup '$MIHOMO_BIN' -d '$DOSTUP_DIR' >> '$DOSTUP_DIR/logs/mihomo.log' 2>&1 &"

    sleep 4

    if pgrep -x "mihomo" > /dev/null; then
        echo ""
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}✓ Mihomo успешно запущен!${NC}"
        echo -e "${GREEN}============================================${NC}"
        echo ""
        echo "Панель управления: https://metacubex.github.io/metacubexd/"
        echo "API: 127.0.0.1:9090"
        return 0
    else
        echo -e "${RED}✗ Не удалось запустить Mihomo${NC}"
        echo "Проверьте логи: $DOSTUP_DIR/logs/mihomo.log"
        return 1
    fi
}

# === MAIN ===

echo ""
echo -e "${BLUE}=== Dostup VPN ===${NC}"
echo ""

if pgrep -x "mihomo" > /dev/null; then
    # Mihomo запущен — показываем меню
    echo -e "${GREEN}Mihomo работает${NC}"
    echo ""
    echo "Панель управления: https://metacubex.github.io/metacubexd/"
    echo "API: 127.0.0.1:9090"
    echo ""
    echo "1) Остановить"
    echo "2) Перезапустить"
    echo "3) Проверить доступ"
    echo "4) Отмена"
    echo ""
    read -p "Выберите (1-4): " choice < /dev/tty

    case "$choice" in
        1)
            do_stop
            echo ""
            echo "Окно закроется через 3 секунды..."
            sleep 3
            (sleep 0.5 && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
            disown
            exit 0
            ;;
        2)
            do_stop
            echo ""
            do_start
            echo ""
            echo "Окно закроется через 5 секунд..."
            sleep 5
            (sleep 0.5 && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
            disown
            exit 0
            ;;
        3)
            do_check_access
            read -p "Нажмите Enter для закрытия..." < /dev/tty
            (sleep 0.5 && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
            disown
            exit 0
            ;;
        *)
            echo ""
            echo "Отменено"
            echo ""
            echo "Окно закроется через 2 секунды..."
            sleep 2
            (sleep 0.5 && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
            disown
            exit 0
            ;;
    esac
else
    # Mihomo не запущен — запускаем без вопросов
    do_start
    echo ""
    echo "Окно закроется через 5 секунд..."
    sleep 5
    (sleep 0.5 && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
    disown
    exit 0
fi
CONTROLSCRIPT

    chmod +x "$DOSTUP_DIR/Dostup_VPN.command"

    # Удаляем старые скрипты если есть
    rm -f "$DOSTUP_DIR/dostup-start.command" 2>/dev/null
    rm -f "$DOSTUP_DIR/dostup-stop.command" 2>/dev/null
}

# Скачивание иконки
download_icon() {
    print_step "Скачивание иконки..."
    if download_with_retry "$ICON_URL" "$DOSTUP_DIR/icon.icns"; then
        print_success "Иконка скачана"
        return 0
    else
        print_warning "Не удалось скачать иконку (будет использована стандартная)"
        return 1
    fi
}

# Создание .app bundle на рабочем столе
create_desktop_shortcuts() {
    print_step "Создание приложения на рабочем столе..."

    local app_path="$DESKTOP_DIR/Dostup_VPN.app"

    # Удаляем старые ярлыки если есть
    rm -f "$DESKTOP_DIR/Dostup Start.command" 2>/dev/null
    rm -f "$DESKTOP_DIR/Dostup Stop.command" 2>/dev/null
    rm -f "$DESKTOP_DIR/Dostup_VPN.command" 2>/dev/null
    rm -rf "$DESKTOP_DIR/Dostup_VPN.app" 2>/dev/null

    # Создаём структуру .app bundle
    mkdir -p "$app_path/Contents/MacOS"
    mkdir -p "$app_path/Contents/Resources"

    # Копируем иконку
    if [[ -f "$DOSTUP_DIR/icon.icns" ]]; then
        cp "$DOSTUP_DIR/icon.icns" "$app_path/Contents/Resources/AppIcon.icns"
    fi

    # Создаём Info.plist
    cat > "$app_path/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Dostup_VPN</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>ru.richard-moor.dostup-vpn</string>
    <key>CFBundleName</key>
    <string>Dostup VPN</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
</dict>
</plist>
PLIST

    # Создаём исполняемый файл (запускает control script в Terminal)
    cat > "$app_path/Contents/MacOS/Dostup_VPN" << 'LAUNCHER'
#!/bin/bash
open -a Terminal "$HOME/dostup/Dostup_VPN.command"
LAUNCHER

    chmod +x "$app_path/Contents/MacOS/Dostup_VPN"

    print_success "Приложение Dostup_VPN создано на рабочем столе"
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

    # Настройка Application Firewall (разрешаем mihomo)
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$MIHOMO_BIN" 2>/dev/null
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$MIHOMO_BIN" 2>/dev/null

    # Создаём лог-файл от текущего пользователя (чтобы не был root-owned)
    : > "$LOGS_DIR/mihomo.log"

    # Запускаем полностью отвязанным от терминала
    sudo sh -c "nohup '$MIHOMO_BIN' -d '$DOSTUP_DIR' >> '$LOGS_DIR/mihomo.log' 2>&1 &"

    sleep 4

    if pgrep -x "mihomo" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Показ финального сообщения
show_success_message() {
    # Пробуем GUI диалог, если не работает - просто пропускаем
    osascript << EOF 2>/dev/null
display dialog "Mihomo успешно установлен и запущен!

Панель управления:
https://metacubex.github.io/metacubexd/

API: 127.0.0.1:9090

На рабочем столе создан ярлык:
• Dostup_VPN — запуск/остановка/перезапуск" buttons {"OK"} default button 1 with title "Dostup"
EOF
}

# ============================================
# MAIN
# ============================================

print_header

# Проверки
check_macos

# Сохраняем старую подписку если есть (файл может быть с правами root)
OLD_SUB_URL=""
if [[ -f "$SETTINGS_FILE" ]]; then
    OLD_SUB_URL=$(sudo cat "$SETTINGS_FILE" 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('subscription_url', ''))" 2>/dev/null || true)
fi

# Остановка mihomo если запущен
if pgrep -x "mihomo" > /dev/null; then
    print_step "Остановка запущенного Mihomo..."
    sudo pkill -9 mihomo 2>/dev/null || true
    # Ожидание с timeout вместо фиксированного sleep
    stop_timeout=10
    while pgrep -x "mihomo" > /dev/null && [[ $stop_timeout -gt 0 ]]; do
        sleep 1
        stop_timeout=$((stop_timeout - 1))
    done
    # Проверка что остановился
    if pgrep -x "mihomo" > /dev/null; then
        print_error "Не удалось остановить Mihomo"
        echo "Закройте все программы использующие dostup и попробуйте снова"
        read -p "Нажмите Enter для закрытия..."
        exit 1
    fi
    print_success "Mihomo остановлен"
fi

# Удаление старой установки
if [[ -d "$DOSTUP_DIR" ]]; then
    print_step "Удаление старой установки..."
    sudo rm -rf "$DOSTUP_DIR"
    print_success "Старая установка удалена"
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

if [[ -n "$OLD_SUB_URL" ]]; then
    # Есть старая подписка — спрашиваем что делать
    print_info "Найдена предыдущая подписка"
    echo ""
    echo "1) Оставить текущую подписку"
    echo "2) Ввести новую подписку"
    echo ""
    read -p "Выберите (1 или 2): " choice < /dev/tty

    if [[ "$choice" == "2" ]]; then
        SUB_URL=$(ask_input "Введите URL подписки (конфига):" "")
    else
        SUB_URL="$OLD_SUB_URL"
        print_success "Используется предыдущая подписка"
    fi
else
    # Нет старой подписки — запрашиваем новую
    SUB_URL=$(ask_input "Введите URL подписки (конфига):" "")
fi

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

# Создание sites.json
create_sites_json

# Скачивание иконки
download_icon

# Создание скрипта управления
print_step "Создание скрипта управления..."
create_control_script
print_success "Скрипт создан"

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
    echo "Ярлык на рабочем столе:"
    echo "  • Dostup_VPN — запуск/остановка/перезапуск"
    echo ""

    show_success_message
else
    print_error "Не удалось запустить Mihomo"
    echo "Проверьте логи: $LOGS_DIR/mihomo.log"
fi

echo ""
echo "Окно закроется через 5 секунд..."
sleep 5
(sleep 0.5 && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
disown
exit 0
