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
ICON_APP_URL="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/icon_app.png"
ICON_ON_URL="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/icon_on.png"
ICON_OFF_URL="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/icon_off.png"
STATUSBAR_BIN_URL="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/DostupVPN-StatusBar"

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
    # Важно: при set -e ошибка osascript в if не прерывает скрипт,
    # поэтому fallback на терминал реально сработает.
    if ! result=$(osascript -e "set result to text returned of (display dialog \"$safe_prompt\" default answer \"$safe_default\" buttons {\"OK\"} default button 1)" 2>/dev/null); then
        echo ""
        read -r -p "$prompt " result < /dev/tty
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

# Обновление settings.json (чистый bash, без python3)
update_settings() {
    local key="$1"
    local value="$2"

    if [[ ! -f "$SETTINGS_FILE" ]] || [[ ! -s "$SETTINGS_FILE" ]]; then
        printf '{\n  "%s": "%s"\n}\n' "$key" "$value" > "$SETTINGS_FILE"
        return
    fi

    if grep -q "\"${key}\"" "$SETTINGS_FILE" 2>/dev/null; then
        # Ключ существует — заменяем значение (awk безопасен со спецсимволами)
        key="$key" val="$value" awk '{
            k = ENVIRON["key"]; v = ENVIRON["val"]
            if (index($0, "\"" k "\"")) {
                match($0, /^[[:space:]]*/); ws = substr($0, 1, RLENGTH)
                comma = ""; if (sub(/,[[:space:]]*$/, "")) comma = ","
                print ws "\"" k "\": \"" v "\"" comma
            } else { print }
        }' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        # Ключ не существует — добавляем перед закрывающей }
        if ! grep -qE '"[^"]*":' "$SETTINGS_FILE"; then
            printf '{\n  "%s": "%s"\n}\n' "$key" "$value" > "$SETTINGS_FILE"
        else
            key="$key" val="$value" awk '{
                k = ENVIRON["key"]; v = ENVIRON["val"]
                if (/^[[:space:]]*}[[:space:]]*$/) {
                    if (prev != "" && prev !~ /,$/ && prev ~ /"/) sub(/$/, ",", prev)
                    if (prev != "") print prev
                    printf "  \"%s\": \"%s\"\n}\n", k, v
                    prev = ""; next
                } else {
                    if (prev != "") print prev
                    prev = $0
                }
            } END { if (prev != "") print prev }' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        fi
    fi
}

# Чтение из settings.json (чистый bash, без python3)
read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        sed -n 's/.*"'"$key"'": *"\([^"]*\)".*/\1/p' "$SETTINGS_FILE" 2>/dev/null
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

    local geoip_ok=true
    local geosite_ok=true

    download_with_retry "$GEOIP_URL" "$DOSTUP_DIR/geoip.dat" || geoip_ok=false
    download_with_retry "$GEOSITE_URL" "$DOSTUP_DIR/geosite.dat" || geosite_ok=false

    if $geoip_ok && $geosite_ok; then
        update_settings "last_geo_update" "$(date +%Y-%m-%d)"
        print_success "Geo-базы скачаны"
    else
        print_warning "Geo-базы скачаны не полностью"
    fi

    return 0
}

# Скачивание geo-баз и иконки
download_assets() {
    download_geo
    download_icon
    return 0
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

DOSTUP_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS_FILE="$DOSTUP_DIR/settings.json"
MIHOMO_BIN="$DOSTUP_DIR/mihomo"
CONFIG_FILE="$DOSTUP_DIR/config.yaml"

MIHOMO_RELEASES_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
SITES_FILE="$DOSTUP_DIR/sites.json"

# --- Utility ---
close_terminal_window() {
    local delay="${1:-0.5}"
    (sleep "$delay" && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
    disown
}

# NOTE: Functions below are duplicated from the installer.
# When modifying, ensure changes are reflected in both places.

read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        sed -n 's/.*"'"$key"'": *"\([^"]*\)".*/\1/p' "$SETTINGS_FILE" 2>/dev/null
    fi
}

update_settings() {
    local key="$1"
    local value="$2"
    if [[ ! -f "$SETTINGS_FILE" ]] || [[ ! -s "$SETTINGS_FILE" ]]; then
        printf '{\n  "%s": "%s"\n}\n' "$key" "$value" > "$SETTINGS_FILE"
        return
    fi
    if grep -q "\"${key}\"" "$SETTINGS_FILE" 2>/dev/null; then
        key="$key" val="$value" awk '{
            k = ENVIRON["key"]; v = ENVIRON["val"]
            if (index($0, "\"" k "\"")) {
                match($0, /^[[:space:]]*/); ws = substr($0, 1, RLENGTH)
                comma = ""; if (sub(/,[[:space:]]*$/, "")) comma = ","
                print ws "\"" k "\": \"" v "\"" comma
            } else { print }
        }' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        if ! grep -qE '"[^"]*":' "$SETTINGS_FILE"; then
            printf '{\n  "%s": "%s"\n}\n' "$key" "$value" > "$SETTINGS_FILE"
        else
            key="$key" val="$value" awk '{
                k = ENVIRON["key"]; v = ENVIRON["val"]
                if (/^[[:space:]]*}[[:space:]]*$/) {
                    if (prev != "" && prev !~ /,$/ && prev ~ /"/) sub(/$/, ",", prev)
                    if (prev != "") print prev
                    printf "  \"%s\": \"%s\"\n}\n", k, v
                    prev = ""; next
                } else {
                    if (prev != "") print prev
                    prev = $0
                }
            } END { if (prev != "") print prev }' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        fi
    fi
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

verify_mihomo_checksum() {
    local version="$1"
    local filename="$2"
    local archive="$3"
    local checksum_url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}.sha256"
    local expected_hash
    expected_hash=$(curl -sL --fail "$checksum_url" 2>/dev/null | awk '{print $1}')

    if [[ "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]]; then
        local actual_hash
        actual_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
        [[ "$expected_hash" == "$actual_hash" ]]
    else
        echo -e "${BLUE}ℹ SHA256 не найден, пропуск проверки${NC}"
        return 0
    fi
}

validate_yaml() {
    local content=$(head -c 1000 "$1" 2>/dev/null)
    ! echo "$content" | grep -qiE '<!DOCTYPE|<html|<head' && echo "$content" | grep -qE '^[a-zA-Z_-]+:|^\s*-\s+'
}

# --- API-функции (парсинг JSON через osascript, без python3) ---

get_proxy_providers() {
    local tmp="/tmp/dostup_api_$$.json"
    curl -s --max-time 5 "http://127.0.0.1:9090/providers/proxies" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return; }
    osascript -l JavaScript -e "var data = $.NSData.dataWithContentsOfFile('$tmp'); if (data && data.length > 0) { var str = $.NSString.alloc.initWithDataEncoding(data, 4).js; var o = JSON.parse(str).providers || {}; Object.keys(o).filter(function(k){return k!=='default'}).join('\n'); } else { '' }" 2>/dev/null
    rm -f "$tmp"
}

get_rule_providers() {
    local tmp="/tmp/dostup_api_$$.json"
    curl -s --max-time 5 "http://127.0.0.1:9090/providers/rules" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return; }
    osascript -l JavaScript -e "var data = $.NSData.dataWithContentsOfFile('$tmp'); if (data && data.length > 0) { var str = $.NSString.alloc.initWithDataEncoding(data, 4).js; var o = JSON.parse(str).providers || {}; Object.keys(o).join('\n'); } else { '' }" 2>/dev/null
    rm -f "$tmp"
}

parse_healthcheck() {
    local name="$1"
    local tmp="/tmp/dostup_api_$$.json"
    curl -s --max-time 5 "http://127.0.0.1:9090/providers/proxies/$name" -o "$tmp" 2>/dev/null
    if [ -s "$tmp" ]; then
        osascript -l JavaScript -e "var data = $.NSData.dataWithContentsOfFile('$tmp'); if (data && data.length > 0) { var str = $.NSString.alloc.initWithDataEncoding(data, 4).js; var obj = JSON.parse(str); var proxies = obj.proxies || []; var alive = 0, total = 0, lines = []; for (var i = 0; i < proxies.length; i++) { var p = proxies[i]; var nm = p.name || '?'; var h = p.history || []; var delay = h.length > 0 ? h[h.length-1].delay : 0; total++; if (delay > 0) { alive++; lines.push('  ✓ ' + nm + ' — ' + delay + 'ms'); } else { lines.push('  ✗ ' + nm + ' — мёртв'); } } lines.push('  Итого: ' + alive + '/' + total + ' нод'); lines.join('\n'); } else { '  ✗ Ошибка парсинга' }" 2>/dev/null
    else
        echo "  ✗ Не удалось получить данные"
    fi
    rm -f "$tmp"
}

# --- DNS-функции ---

DNS_CONF="$DOSTUP_DIR/original_dns.conf"

get_active_network_service() {
    # Определяем активный сетевой интерфейс через default route
    local device
    device=$(route get default 2>/dev/null | awk '/interface:/{print $2}')
    if [[ -z "$device" ]]; then
        return 1
    fi
    # Маппим device (en0, en1...) на имя сервиса (Wi-Fi, Ethernet...)
    local service=""
    while IFS= read -r line; do
        if [[ "$line" == *"Device: $device"* ]]; then
            echo "$service"
            return 0
        fi
        if [[ "$line" == "Hardware Port:"* ]]; then
            service=$(echo "$line" | sed 's/Hardware Port: //' | sed 's/[[:space:]]*$//')
        fi
    done < <(networksetup -listallhardwareports 2>/dev/null)
    return 1
}

save_and_set_mihomo_dns() {
    local service
    service=$(get_active_network_service)
    if [[ -z "$service" ]]; then
        echo -e "${YELLOW}⚠ Не удалось определить сетевой интерфейс, DNS не переключён${NC}"
        return 0
    fi

    # Сохраняем текущие DNS-серверы
    local current_dns
    current_dns=$(networksetup -getdnsservers "$service" 2>/dev/null)

    echo "$service" > "$DNS_CONF"
    if echo "$current_dns" | grep -q "There aren't any DNS Servers"; then
        echo "empty" >> "$DNS_CONF"
    else
        echo "$current_dns" >> "$DNS_CONF"
    fi

    # Устанавливаем публичные DNS (fail-safe: работают и через TUN, и напрямую)
    sudo -n networksetup -setdnsservers "$service" 8.8.8.8 9.9.9.9
    echo -e "${GREEN}✓ DNS переключён на 8.8.8.8 / 9.9.9.9${NC}"
}

restore_original_dns() {
    if [[ ! -f "$DNS_CONF" ]]; then
        return 0
    fi

    local service
    service=$(head -1 "$DNS_CONF")
    if [[ -z "$service" ]]; then
        rm -f "$DNS_CONF"
        return 0
    fi

    # Читаем сохранённые DNS-серверы (все строки кроме первой)
    local dns_servers
    dns_servers=$(tail -n +2 "$DNS_CONF")

    if [[ "$dns_servers" == "empty" ]]; then
        sudo -n networksetup -setdnsservers "$service" empty
    else
        # Intentionally unquoted: each DNS server must be a separate argument
        sudo -n networksetup -setdnsservers "$service" $dns_servers
    fi

    rm -f "$DNS_CONF"
    echo -e "${GREEN}✓ DNS восстановлен${NC}"
}

check_dns_recovery() {
    # Защита от крэша: если mihomo не работает, а DNS-файл остался — восстановить
    if [[ -f "$DNS_CONF" ]] && ! pgrep -x "mihomo" > /dev/null; then
        echo -e "${YELLOW}⚠ Обнаружен незавершённый DNS-фикс, восстанавливаю...${NC}"
        restore_original_dns
    fi
}

do_check_access() {
    echo ""
    echo -e "${YELLOW}▶ Проверка доступа к ресурсам...${NC}"
    echo ""

    if [[ ! -f "$SITES_FILE" ]]; then
        echo -e "${RED}✗ Файл sites.json не найден${NC}"
        return 1
    fi

    # Читаем сайты из JSON (чистый bash, без python3)
    local sites
    sites=$(sed -n 's/.*"\([a-zA-Z0-9._-]*\.[a-zA-Z]\{2,\}\)".*/\1/p' "$SITES_FILE" 2>/dev/null)

    if [[ -z "$sites" ]]; then
        echo -e "${RED}✗ Не удалось прочитать список сайтов${NC}"
        return 1
    fi

    # Проверка сайтов: $1 = "verbose" (с выводом) или "quiet" (только счёт)
    # Результат в глобальных переменных _check_ok, _check_total
    _check_sites() {
        _check_ok=0
        _check_total=0
        while IFS= read -r site; do
            _check_total=$((_check_total + 1))
            if curl -s --head --connect-timeout 7 --max-time 12 "https://$site" > /dev/null 2>&1; then
                [[ "$1" == "verbose" ]] && echo -e "${GREEN}✓ $site — доступен${NC}"
                _check_ok=$((_check_ok + 1))
            else
                [[ "$1" == "verbose" ]] && echo -e "${RED}✗ $site — недоступен${NC}"
            fi
        done <<< "$sites"
    }

    # --- Первая проверка (с выводом каждого сайта) ---
    _check_sites verbose
    echo ""

    local failed=$((_check_total - _check_ok))
    local threshold=$((_check_total / 2))

    # Большинство доступны — всё ОК
    if [[ $failed -le $threshold ]]; then
        return 0
    fi

    # --- Большинство недоступно — перепроверяем ещё 2 раза ---
    echo -e "${YELLOW}⚠ Большинство ресурсов недоступно, перепроверяю...${NC}"

    local attempt
    for attempt in 1 2; do
        sleep 3
        echo -e "${YELLOW}  Повторная проверка ($((attempt + 1))/3)...${NC}"
        _check_sites quiet
        failed=$((_check_total - _check_ok))
        if [[ $failed -le $threshold ]]; then
            echo -e "${GREEN}✓ Доступ есть (${_check_ok}/${_check_total} ресурсов доступны)${NC}"
            return 0
        fi
        echo -e "${RED}  Недоступно: ${failed}/${_check_total}${NC}"
    done

    # --- Подтверждено: доступа нет ---
    echo ""
    echo -e "${RED}✗ Большинство ресурсов недоступно (${failed}/${_check_total})${NC}"
    echo ""
    echo "Возможные причины:"
    echo "  • Конфиг некорректный или подписка истекла"
    echo "  • Сеть блокирует VPN-трафик"
    echo "  • Mihomo не запущен"
    return 1
}

do_stop() {
    echo -e "${YELLOW}▶ Остановка Mihomo...${NC}"
    echo ""
    restore_original_dns
    sudo -n launchctl stop ru.dostup.vpn.mihomo 2>/dev/null || true
    # Fallback: если LaunchDaemon не активен
    if pgrep -x "mihomo" > /dev/null; then
        sudo -n pkill mihomo 2>/dev/null || true
    fi
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

do_update_core() {
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
            if verify_mihomo_checksum "$latest_version" "$filename" "$DOSTUP_DIR/mihomo.gz"; then
                gunzip -f "$DOSTUP_DIR/mihomo.gz"
                chmod +x "$MIHOMO_BIN"
                xattr -d com.apple.quarantine "$MIHOMO_BIN" 2>/dev/null || true
                update_settings "installed_version" "$latest_version"
                echo -e "${GREEN}✓ Ядро обновлено${NC}"
            else
                rm -f "$DOSTUP_DIR/mihomo.gz"
                echo -e "${RED}✗ Ошибка проверки хэша, используем текущую версию${NC}"
            fi
        else
            echo -e "${RED}✗ Не удалось обновить ядро, используем текущую версию${NC}"
        fi
    else
        echo -e "${GREEN}✓ Ядро актуально${NC}"
    fi
}

do_update_config() {
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
}

do_start_quick() {
    # Настройка Application Firewall
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --add "$MIHOMO_BIN" 2>/dev/null || true
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$MIHOMO_BIN" 2>/dev/null || true

    # Запуск через LaunchDaemon
    sudo -n launchctl start ru.dostup.vpn.mihomo
    sleep 4

    if pgrep -x "mihomo" > /dev/null; then
        save_and_set_mihomo_dns
        return 0
    else
        return 1
    fi
}

check_script_update() {
    local current_hash
    current_hash=$(read_settings "installer_hash")
    [[ -z "$current_hash" ]] && return 0

    local url="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.command"
    local tmp="/tmp/dostup-installer-check"
    # Retry: сеть может быть не готова сразу после остановки VPN
    if ! download_with_retry "$url" "$tmp"; then
        rm -f "$tmp"
        return 0
    fi
    local new_hash
    new_hash=$(shasum -a 256 "$tmp" | cut -d' ' -f1)
    if [[ -n "$new_hash" && "$new_hash" != "$current_hash" ]]; then
        if [[ "$DOSTUP_SILENT" == "1" ]]; then
            echo "DOSTUP_SCRIPT_UPDATE"
            rm -f "$tmp"
            return 0
        fi
        echo ""
        echo -e "${YELLOW}▶ Доступно обновление скрипта управления${NC}"
        printf "  Обновить сейчас? (y/N): "
        read -r choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            echo -e "${YELLOW}▶ Обновление...${NC}"
            bash "$tmp"
            exit 0
        fi
    fi
    rm -f "$tmp"
}

do_start() {
    check_script_update
    do_update_core
    do_update_config

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
    echo -e "${YELLOW}▶ Запуск Mihomo...${NC}"
    echo ""

    # Настройка Application Firewall
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --add "$MIHOMO_BIN" 2>/dev/null
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$MIHOMO_BIN" 2>/dev/null

    # Запуск через LaunchDaemon
    sudo -n launchctl start ru.dostup.vpn.mihomo

    sleep 4

    if pgrep -x "mihomo" > /dev/null; then
        save_and_set_mihomo_dns
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

# --- CLI mode (вызов из menu bar app) ---
if [[ -n "$1" ]]; then
    case "$1" in
        start)
            # do shell script вызывает с "> /dev/null 2>&1 &" (Apple TN2065) —
            # возвращается немедленно, скрипт работает в фоне как root
            do_start_quick
            exit 0
            ;;
        stop)
            do_stop >/dev/null
            exit $?
            ;;
        check)
            do_check_access
            echo ""
            echo "Окно закроется через 3 секунды..."
            sleep 3
            close_terminal_window
            exit 0
            ;;
        update-core)
            do_update_core
            echo ""
            echo "Окно закроется через 3 секунды..."
            sleep 3
            close_terminal_window
            exit 0
            ;;
        update-config)
            do_update_config
            echo ""
            echo "Окно закроется через 3 секунды..."
            sleep 3
            close_terminal_window
            exit 0
            ;;
        restart)
            do_stop
            echo ""
            do_start
            echo ""
            echo "Окно закроется через 5 секунд..."
            sleep 5
            close_terminal_window
            exit 0
            ;;
        restart-silent)
            export DOSTUP_SILENT=1
            do_stop >/dev/null 2>&1 || true
            output=$(do_start 2>&1)
            summary=""
            echo "$output" | grep -q "DOSTUP_SCRIPT_UPDATE" && summary="${summary}Обновление скрипта доступно\n"
            echo "$output" | grep -q "Ядро обновлено" && summary="${summary}Ядро обновлено\n"
            echo "$output" | grep -q "Конфиг обновлён" && summary="${summary}Конфиг обновлён\n"
            echo "$output" | grep -q "Geo-базы обновлены" && summary="${summary}Geo-базы обновлены\n"
            if pgrep -x "mihomo" > /dev/null; then
                [[ -z "$summary" ]] && summary="VPN перезапущен" || summary="${summary}VPN перезапущен"
            else
                summary="Ошибка перезапуска"
            fi
            echo -e "$summary"
            exit 0
            ;;
        update-providers)
            echo "Обновление провайдеров..."
            proxy_providers=$(get_proxy_providers)
            if [ -n "$proxy_providers" ]; then
                while IFS= read -r name; do
                    curl -s -X PUT --max-time 15 "http://127.0.0.1:9090/providers/proxies/$name" && echo "✓ $name" || echo "✗ $name"
                done <<< "$proxy_providers"
            else
                echo "✗ Не удалось получить список прокси-провайдеров"
            fi
            rule_providers=$(get_rule_providers)
            if [ -n "$rule_providers" ]; then
                while IFS= read -r name; do
                    curl -s -X PUT --max-time 15 "http://127.0.0.1:9090/providers/rules/$name" && echo "✓ $name" || echo "✗ $name"
                done <<< "$rule_providers"
            else
                echo "✗ Не удалось получить список правил-провайдеров"
            fi
            echo ""
            echo "Окно закроется через 3 секунды..."
            sleep 3
            close_terminal_window
            exit 0
            ;;
        healthcheck)
            echo "Проверка нод..."
            echo ""
            proxy_providers=$(get_proxy_providers)
            if [ -n "$proxy_providers" ]; then
                while IFS= read -r name; do
                    curl -s --max-time 30 "http://127.0.0.1:9090/providers/proxies/$name/healthcheck" > /dev/null 2>&1
                    echo "[$name]"
                    parse_healthcheck "$name"
                    echo ""
                done <<< "$proxy_providers"
            else
                echo "✗ Не удалось получить список провайдеров"
            fi
            read -p "Нажмите Enter для закрытия..." < /dev/tty
            close_terminal_window
            exit 0
            ;;
        status)
            if pgrep -x "mihomo" > /dev/null; then echo "running"; else echo "stopped"; fi
            exit 0
            ;;
        dns-set)
            save_and_set_mihomo_dns
            exit 0
            ;;
        *)
            echo "Unknown command: $1"
            exit 1
            ;;
    esac
fi

check_dns_recovery

# Если mihomo работает, но DNS ещё не переключён — переключить
if [[ ! -f "$DNS_CONF" ]] && pgrep -x "mihomo" > /dev/null; then
    save_and_set_mihomo_dns
fi

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
    echo "3) Обновить прокси и правила"
    echo "4) Проверка нод"
    echo "5) Проверить доступ"
    echo "6) Отмена"
    echo ""
    read -p "Выберите (1-6): " choice < /dev/tty

    case "$choice" in
        1)
            do_stop
            echo ""
            echo "Окно закроется через 3 секунды..."
            sleep 3
            close_terminal_window
            exit 0
            ;;
        2)
            do_stop
            echo ""
            do_start
            echo ""
            echo "Окно закроется через 5 секунд..."
            sleep 5
            close_terminal_window
            exit 0
            ;;
        3)
            echo ""
            echo "Обновление провайдеров..."
            proxy_providers=$(get_proxy_providers)
            if [ -n "$proxy_providers" ]; then
                while IFS= read -r name; do
                    curl -s -X PUT --max-time 15 "http://127.0.0.1:9090/providers/proxies/$name" && echo "✓ $name" || echo "✗ $name"
                done <<< "$proxy_providers"
            else
                echo "✗ Не удалось получить список прокси-провайдеров"
            fi
            rule_providers=$(get_rule_providers)
            if [ -n "$rule_providers" ]; then
                while IFS= read -r name; do
                    curl -s -X PUT --max-time 15 "http://127.0.0.1:9090/providers/rules/$name" && echo "✓ $name" || echo "✗ $name"
                done <<< "$rule_providers"
            else
                echo "✗ Не удалось получить список правил-провайдеров"
            fi
            echo ""
            echo "Окно закроется через 3 секунды..."
            sleep 3
            close_terminal_window
            exit 0
            ;;
        4)
            echo ""
            echo "Проверка нод..."
            echo ""
            proxy_providers=$(get_proxy_providers)
            if [ -n "$proxy_providers" ]; then
                while IFS= read -r name; do
                    curl -s --max-time 30 "http://127.0.0.1:9090/providers/proxies/$name/healthcheck" > /dev/null 2>&1
                    echo "[$name]"
                    parse_healthcheck "$name"
                    echo ""
                done <<< "$proxy_providers"
            else
                echo "✗ Не удалось получить список провайдеров"
            fi
            read -p "Нажмите Enter для закрытия..." < /dev/tty
            close_terminal_window
            exit 0
            ;;
        5)
            do_check_access
            read -p "Нажмите Enter для закрытия..." < /dev/tty
            close_terminal_window
            exit 0
            ;;
        *)
            echo ""
            echo "Отменено"
            echo ""
            echo "Окно закроется через 2 секунды..."
            sleep 2
            close_terminal_window
            exit 0
            ;;
    esac
else
    # Mihomo не запущен — запускаем без вопросов
    do_start
    # Запускаем statusbar app если установлен но не запущен
    STATUSBAR_APP="$DOSTUP_DIR/statusbar/DostupVPN-StatusBar.app"
    if [[ -d "$STATUSBAR_APP" ]] && ! pgrep -x "DostupVPN-StatusBar" > /dev/null; then
        open "$STATUSBAR_APP"
    fi
    echo ""
    echo "Окно закроется через 5 секунд..."
    sleep 5
    close_terminal_window
    exit 0
fi
CONTROLSCRIPT

    chmod +x "$DOSTUP_DIR/Dostup_VPN.command"

    # Удаляем старые скрипты если есть
    rm -f "$DOSTUP_DIR/dostup-start.command" 2>/dev/null
    rm -f "$DOSTUP_DIR/dostup-stop.command" 2>/dev/null
}

# Скачивание иконок
download_icon() {
    print_step "Скачивание иконок..."
    if download_with_retry "$ICON_URL" "$DOSTUP_DIR/icon.icns"; then
        print_success "Иконка скачана"
    else
        print_warning "Не удалось скачать иконку (будет использована стандартная)"
    fi
    # Иконка приложения для уведомлений (512x512 PNG)
    download_with_retry "$ICON_APP_URL" "$DOSTUP_DIR/icon_app.png" 2>/dev/null || true
    # Иконки для статусбара (36x36 PNG)
    mkdir -p "$DOSTUP_DIR/statusbar"
    download_with_retry "$ICON_ON_URL" "$DOSTUP_DIR/statusbar/icon_on.png" 2>/dev/null || true
    download_with_retry "$ICON_OFF_URL" "$DOSTUP_DIR/statusbar/icon_off.png" 2>/dev/null || true
    return 0
}

# Создание .app bundle в ~/Applications
create_desktop_shortcuts() {
    print_step "Создание приложения в ~/Applications..."

    local apps_dir="$HOME/Applications"
    mkdir -p "$apps_dir"
    local app_path="$apps_dir/Dostup_VPN.app"

    # Удаляем старые ярлыки (рабочий стол — legacy, ~/Applications — текущий)
    rm -f "$DESKTOP_DIR/Dostup Start.command" 2>/dev/null
    rm -f "$DESKTOP_DIR/Dostup Stop.command" 2>/dev/null
    rm -f "$DESKTOP_DIR/Dostup_VPN.command" 2>/dev/null
    rm -rf "$DESKTOP_DIR/Dostup_VPN.app" 2>/dev/null
    rm -rf "$apps_dir/Dostup_VPN.app" 2>/dev/null

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

    print_success "Приложение Dostup_VPN создано в ~/Applications"
}

# Создание menu bar приложения
create_statusbar_app() {
    print_step "Создание menu bar приложения..."

    local statusbar_dir="$DOSTUP_DIR/statusbar"
    local app_path="$statusbar_dir/DostupVPN-StatusBar.app"

    mkdir -p "$statusbar_dir"
    mkdir -p "$app_path/Contents/MacOS"
    mkdir -p "$app_path/Contents/Resources"

    # Иконки для статусбара уже скачаны в download_icon()
    # Копируем иконку приложения для уведомлений
    if [[ -f "$DOSTUP_DIR/icon.icns" ]]; then
        cp "$DOSTUP_DIR/icon.icns" "$app_path/Contents/Resources/AppIcon.icns"
    fi

    # Записываем Swift-исходник
    cat > "$statusbar_dir/DostupVPN-StatusBar.swift" << 'SWIFTSOURCE'
import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var restartMenuItem: NSMenuItem!
    private var updateProvidersMenuItem: NSMenuItem!
    private var healthcheckMenuItem: NSMenuItem!
    private var checkMenuItem: NSMenuItem!
    private var timer: Timer?

    private var colorIcon: NSImage?
    private var grayIcon: NSImage?

    private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    private var controlScript: String {
        return homeDir + "/dostup/Dostup_VPN.command"
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Устанавливаем иконку приложения для уведомлений
        if let appIcon = NSImage(contentsOfFile: homeDir + "/dostup/icon_app.png") {
            NSApplication.shared.applicationIconImage = appIcon
        }
        loadIcons()
        setupStatusItem()
        setupMenu()
        startTimer()
        updateStatus()
    }

    // MARK: - Icons

    private func loadIcons() {
        let statusbarDir = homeDir + "/dostup/statusbar"
        let size = NSSize(width: 18, height: 18)

        if let on = NSImage(contentsOfFile: statusbarDir + "/icon_on.png") {
            on.size = size
            on.isTemplate = false
            colorIcon = on
        }
        if let off = NSImage(contentsOfFile: statusbarDir + "/icon_off.png") {
            off.size = size
            off.isTemplate = false
            grayIcon = off
        }
    }

    // MARK: - StatusItem & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = colorIcon {
                button.image = icon
            } else {
                button.title = "VPN"
            }
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Status line (disabled, info only)
        statusMenuItem = NSMenuItem(title: "\u{25CF} VPN \u{0440}\u{0430}\u{0431}\u{043E}\u{0442}\u{0430}\u{0435}\u{0442}", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle VPN
        toggleMenuItem = NSMenuItem(title: "\u{041E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} VPN", action: #selector(toggleVPN), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        // Restart VPN
        restartMenuItem = NSMenuItem(title: "\u{041F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0441}\u{0442}\u{0438}\u{0442}\u{044C}", action: #selector(restartVPN), keyEquivalent: "")
        restartMenuItem.target = self
        menu.addItem(restartMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Update providers
        updateProvidersMenuItem = NSMenuItem(title: "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} \u{043F}\u{0440}\u{043E}\u{043A}\u{0441}\u{0438} \u{0438} \u{043F}\u{0440}\u{0430}\u{0432}\u{0438}\u{043B}\u{0430}", action: #selector(updateProviders), keyEquivalent: "")
        updateProvidersMenuItem.target = self
        menu.addItem(updateProvidersMenuItem)

        // Healthcheck
        healthcheckMenuItem = NSMenuItem(title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{043A}\u{0430} \u{043D}\u{043E}\u{0434}", action: #selector(healthcheckProviders), keyEquivalent: "")
        healthcheckMenuItem.target = self
        menu.addItem(healthcheckMenuItem)

        // Check access
        checkMenuItem = NSMenuItem(title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{0438}\u{0442}\u{044C} \u{0434}\u{043E}\u{0441}\u{0442}\u{0443}\u{043F}", action: #selector(checkAccess), keyEquivalent: "")
        checkMenuItem.target = self
        menu.addItem(checkMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Exit
        let exitMenuItem = NSMenuItem(title: "\u{0412}\u{044B}\u{0445}\u{043E}\u{0434}", action: #selector(exitApp), keyEquivalent: "q")
        exitMenuItem.target = self
        menu.addItem(exitMenuItem)

        statusItem.menu = menu
    }

    // MARK: - Timer & Status

    private func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: 5.0, target: self,
                                     selector: #selector(updateStatus),
                                     userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }

    @objc private func updateStatus() {
        let running = isMihomoRunning()

        // Update icon
        if let button = statusItem.button {
            if colorIcon != nil {
                button.image = running ? colorIcon : grayIcon
                button.title = ""
            } else {
                button.title = "VPN"
            }
        }

        // Update menu items
        restartMenuItem.isEnabled = running
        updateProvidersMenuItem.isEnabled = running
        healthcheckMenuItem.isEnabled = running
        checkMenuItem.isEnabled = running
        if running {
            statusMenuItem.title = "\u{25CF} VPN \u{0440}\u{0430}\u{0431}\u{043E}\u{0442}\u{0430}\u{0435}\u{0442}"
            toggleMenuItem.title = "\u{041E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} VPN"
        } else {
            statusMenuItem.title = "\u{25CB} VPN \u{043E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}"
            toggleMenuItem.title = "\u{0417}\u{0430}\u{043F}\u{0443}\u{0441}\u{0442}\u{0438}\u{0442}\u{044C} VPN"
        }
    }

    // MARK: - Process Check

    private func isMihomoRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "mihomo"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: - Actions

    @objc private func toggleVPN() {
        let running = isMihomoRunning()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let task = Process()

            if running {
                // Stop: через control script (обрабатывает DNS restore)
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                let ePath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
                task.arguments = ["-c", "'" + ePath + "' stop"]
            } else {
                // Start: напрямую через launchctl (без пароля, через sudoers)
                task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                task.arguments = ["-n", "/bin/launchctl", "start", "ru.dostup.vpn.mihomo"]
            }

            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.showNotification(title: "Dostup VPN",
                                          text: "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}: \(error.localizedDescription)")
                    self.updateStatus()
                }
                return
            }

            if running {
                DispatchQueue.main.async {
                    self.showNotification(title: "Dostup VPN",
                                          text: "Dostup VPN \u{043E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}")
                    self.updateStatus()
                }
            } else {
                // Mihomo нужно время на запуск — ждём 5 сек и проверяем
                Thread.sleep(forTimeInterval: 5.0)
                let started = self.isMihomoRunning()
                if started {
                    // Переключаем DNS на публичные (fail-safe)
                    let dnsTask = Process()
                    dnsTask.executableURL = URL(fileURLWithPath: "/bin/bash")
                    let ePath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
                    dnsTask.arguments = ["-c", "'" + ePath + "' dns-set"]
                    dnsTask.standardOutput = FileHandle.nullDevice
                    dnsTask.standardError = FileHandle.nullDevice
                    try? dnsTask.run()
                    dnsTask.waitUntilExit()
                }
                DispatchQueue.main.async {
                    if started {
                        self.showNotification(title: "Dostup VPN",
                                              text: "Dostup VPN \u{0437}\u{0430}\u{043F}\u{0443}\u{0449}\u{0435}\u{043D}")
                    } else {
                        self.showNotification(title: "Dostup VPN",
                                              text: "\u{041D}\u{0435} \u{0443}\u{0434}\u{0430}\u{043B}\u{043E}\u{0441}\u{044C} \u{0437}\u{0430}\u{043F}\u{0443}\u{0441}\u{0442}\u{0438}\u{0442}\u{044C} VPN")
                    }
                    self.updateStatus()
                }
            }
        }
    }

    @objc private func restartVPN() {
        restartMenuItem.isEnabled = false
        statusMenuItem.title = "\u{21BB} \u{041F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0441}\u{043A}..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self.controlScript, "restart-silent"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = output.isEmpty ? "VPN \u{043F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0449}\u{0435}\u{043D}" : output

            DispatchQueue.main.async {
                self.showNotification(title: "Dostup VPN", text: text)
                self.updateStatus()
                self.restartMenuItem.isEnabled = self.isMihomoRunning()
            }
        }
    }

    @objc private func updateProviders() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let api = "http://127.0.0.1:9090"
            var allOk = true
            let semaphore = DispatchSemaphore(value: 0)

            // Update proxy providers dynamically
            if let url = URL(string: "\(api)/providers/proxies"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let providers = json["providers"] as? [String: Any] {
                for name in providers.keys where name != "default" {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    var request = URLRequest(url: URL(string: "\(api)/providers/proxies/\(encoded)")!)
                    request.httpMethod = "PUT"
                    request.timeoutInterval = 15
                    URLSession.shared.dataTask(with: request) { _, response, _ in
                        if let http = response as? HTTPURLResponse, !(200...204).contains(http.statusCode) {
                            allOk = false
                        }
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()
                }
            } else {
                allOk = false
            }

            // Update rule providers dynamically
            if let url = URL(string: "\(api)/providers/rules"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let providers = json["providers"] as? [String: Any] {
                for name in providers.keys {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    var request = URLRequest(url: URL(string: "\(api)/providers/rules/\(encoded)")!)
                    request.httpMethod = "PUT"
                    request.timeoutInterval = 15
                    URLSession.shared.dataTask(with: request) { _, response, _ in
                        if let http = response as? HTTPURLResponse, !(200...204).contains(http.statusCode) {
                            allOk = false
                        }
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()
                }
            }

            DispatchQueue.main.async {
                self?.showNotification(
                    title: "Dostup VPN",
                    text: allOk ? "\u{041F}\u{0440}\u{043E}\u{0432}\u{0430}\u{0439}\u{0434}\u{0435}\u{0440}\u{044B} \u{043E}\u{0431}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}\u{044B}" : "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430} \u{043E}\u{0431}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}\u{0438}\u{044F} \u{043F}\u{0440}\u{043E}\u{0432}\u{0430}\u{0439}\u{0434}\u{0435}\u{0440}\u{043E}\u{0432}"
                )
            }
        }
    }

    @objc private func healthcheckProviders() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let api = "http://127.0.0.1:9090"
            var summaryLines: [String] = []
            let semaphore = DispatchSemaphore(value: 0)

            if let url = URL(string: "\(api)/providers/proxies"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let providers = json["providers"] as? [String: Any] {
                for name in providers.keys where name != "default" {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    // Run healthcheck
                    var request = URLRequest(url: URL(string: "\(api)/providers/proxies/\(encoded)/healthcheck")!)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 30
                    URLSession.shared.dataTask(with: request) { _, _, _ in
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()

                    // Get detailed results
                    if let detailUrl = URL(string: "\(api)/providers/proxies/\(encoded)"),
                       let detailData = try? Data(contentsOf: detailUrl),
                       let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                       let proxies = detailJson["proxies"] as? [[String: Any]] {
                        var alive = 0
                        var totalDelay = 0
                        let total = proxies.count
                        for proxy in proxies {
                            if let history = proxy["history"] as? [[String: Any]],
                               let last = history.last,
                               let delay = last["delay"] as? Int,
                               delay > 0 {
                                alive += 1
                                totalDelay += delay
                            }
                        }
                        let avg = alive > 0 ? totalDelay / alive : 0
                        if alive > 0 {
                            summaryLines.append("\(name): \(alive)/\(total) (avg \(avg)ms)")
                        } else {
                            summaryLines.append("\(name): 0/\(total)")
                        }
                    } else {
                        summaryLines.append("\(name): \u{043E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}")
                    }
                }
            } else {
                summaryLines.append("\u{041D}\u{0435}\u{0442} \u{0434}\u{0430}\u{043D}\u{043D}\u{044B}\u{0445}")
            }

            let text = summaryLines.joined(separator: "\n")
            DispatchQueue.main.async {
                self?.showNotification(
                    title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{043A}\u{0430} \u{043D}\u{043E}\u{0434}",
                    text: text
                )
            }
        }
    }

    @objc private func checkAccess() {
        runInTerminal(argument: "check")
    }

    @objc private func exitApp() {
        let running = isMihomoRunning()
        if !running {
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            let ePath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
            task.arguments = ["-c", "'" + ePath + "' stop"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Helpers

    private func runInTerminal(argument: String) {
        // Используем временный .command файл вместо AppleScript automation Terminal
        // (AppleScript automation блокируется macOS без подписи приложения)
        let escapedPath = controlScript.replacingOccurrences(of: "'", with: "'\\''")
        let escapedArg = argument.replacingOccurrences(of: "'", with: "'\\''")
        let tempScript = homeDir + "/dostup/statusbar/run_command.command"
        let content = "#!/bin/bash\nbash '\(escapedPath)' '\(escapedArg)'\n"
        try? content.write(toFile: tempScript, atomically: true, encoding: .utf8)

        // chmod +x
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", tempScript]
        try? chmod.run()
        chmod.waitUntilExit()

        // open -a Terminal (не требует Automation permissions)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", tempScript]
        try? open.run()
    }

    private func showNotification(title: String, text: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        notification.contentImage = NSImage(contentsOfFile: homeDir + "/dostup/icon_app.png")
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
SWIFTSOURCE

    # Info.plist (LSUIElement=true — нет иконки в Dock)
    cat > "$app_path/Contents/Info.plist" << 'SBPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DostupVPN-StatusBar</string>
    <key>CFBundleIdentifier</key>
    <string>ru.dostup.vpn.statusbar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>Dostup VPN Status Bar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
SBPLIST

    local binary_path="$app_path/Contents/MacOS/DostupVPN-StatusBar"
    local installed=false

    # --- Способ 1: скачать предкомпилированный бинарник ---
    print_info "Скачивание menu bar приложения..."
    if download_with_retry "$STATUSBAR_BIN_URL" "$binary_path"; then
        chmod +x "$binary_path"
        xattr -d com.apple.quarantine "$binary_path" 2>/dev/null || true
        xattr -d com.apple.quarantine "$app_path" 2>/dev/null || true
        installed=true
        print_success "Menu bar приложение скачано"
    else
        print_info "Не удалось скачать, попытка компиляции..."

        # --- Способ 2 (fallback): компиляция через swiftc ---
        # pkgutil не является шимом и не вызывает диалог установки CLT
        if pkgutil --pkg-info=com.apple.pkg.CLTools_Executables &>/dev/null; then
            print_info "Компиляция Swift (это может занять несколько секунд)..."
            if swiftc -O -o "$binary_path" \
                -framework Cocoa \
                "$statusbar_dir/DostupVPN-StatusBar.swift" 2>/dev/null; then
                xattr -d com.apple.quarantine "$app_path" 2>/dev/null || true
                installed=true
                print_success "Menu bar приложение скомпилировано"
            else
                print_warning "Не удалось скомпилировать menu bar приложение"
            fi
        else
            print_info "Xcode CLT не найден, пропуск компиляции"
        fi
    fi

    # --- Результат ---
    if $installed; then
        create_launch_agent
        print_success "Menu bar приложение установлено"
    else
        print_warning "Menu bar приложение не установлено"
        print_info "VPN будет работать через приложение Dostup_VPN"
        rm -rf "$statusbar_dir"
    fi
}

# Создание LaunchAgent для автозапуска menu bar приложения
create_launch_agent() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_path="$plist_dir/ru.dostup.vpn.statusbar.plist"

    mkdir -p "$plist_dir"

    # Используем полный путь к .app
    local app_full_path="$DOSTUP_DIR/statusbar/DostupVPN-StatusBar.app"

    cat > "$plist_path" << LAPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ru.dostup.vpn.statusbar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>${app_full_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
LAPLIST

    # Перезагружаем LaunchAgent (unload старый → load новый)
    launchctl unload "$plist_path" 2>/dev/null || true
    launchctl load "$plist_path" 2>/dev/null || true
}

# Создание LaunchDaemon для mihomo (системный сервис)
create_launch_daemon() {
    print_step "Создание LaunchDaemon для mihomo..."

    local plist_path="/Library/LaunchDaemons/ru.dostup.vpn.mihomo.plist"
    local log_path="$HOME/dostup/logs/mihomo.log"
    local mihomo_path="$HOME/dostup/mihomo"
    local dostup_path="$HOME/dostup"

    # Создаём директорию для логов с правами для root и текущего пользователя
    mkdir -p "$LOGS_DIR"
    chmod 777 "$LOGS_DIR"

    sudo tee "$plist_path" > /dev/null << LDPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ru.dostup.vpn.mihomo</string>
    <key>ProgramArguments</key>
    <array>
        <string>${mihomo_path}</string>
        <string>-d</string>
        <string>${dostup_path}</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>${log_path}</string>
    <key>StandardErrorPath</key>
    <string>${log_path}</string>
</dict>
</plist>
LDPLIST

    sudo chmod 644 "$plist_path"
    sudo launchctl load "$plist_path" 2>/dev/null || true

    print_success "LaunchDaemon создан"
}

# Создание sudoers-записи для passwordless управления VPN
create_sudoers_entry() {
    print_step "Настройка passwordless управления VPN..."

    local sudoers_tmp="/tmp/dostup-sudoers.tmp"
    local sudoers_path="/etc/sudoers.d/dostup-vpn"

    local mihomo_path_escaped="$HOME/dostup/mihomo"
    cat > "$sudoers_tmp" << SUDOERS
# DostupVPN — passwordless VPN management for admin users
%admin ALL=(root) NOPASSWD: /bin/launchctl start ru.dostup.vpn.mihomo
%admin ALL=(root) NOPASSWD: /bin/launchctl stop ru.dostup.vpn.mihomo
%admin ALL=(root) NOPASSWD: /bin/launchctl load /Library/LaunchDaemons/ru.dostup.vpn.mihomo.plist
%admin ALL=(root) NOPASSWD: /bin/launchctl unload /Library/LaunchDaemons/ru.dostup.vpn.mihomo.plist
# DNS: wildcard needed for service name + restore of saved DNS servers
%admin ALL=(root) NOPASSWD: /usr/sbin/networksetup -setdnsservers *
%admin ALL=(root) NOPASSWD: /usr/libexec/ApplicationFirewall/socketfilterfw --add ${mihomo_path_escaped}
%admin ALL=(root) NOPASSWD: /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp ${mihomo_path_escaped}
SUDOERS

    # Валидация перед установкой
    if sudo visudo -cf "$sudoers_tmp" 2>/dev/null; then
        sudo cp "$sudoers_tmp" "$sudoers_path"
        sudo chmod 0440 "$sudoers_path"
        rm -f "$sudoers_tmp"
        print_success "Passwordless управление настроено"
    else
        rm -f "$sudoers_tmp"
        print_warning "Не удалось создать sudoers-запись (VPN будет запрашивать пароль)"
    fi
}

# --- DNS-функция (installer): восстановление при переустановке ---
# NOTE: Similar to restore_original_dns() in control script,
# but uses interactive sudo (not -n) since installer runs interactively.

DNS_CONF_INSTALLER="$DOSTUP_DIR/original_dns.conf"

restore_original_dns_installer() {
    if [[ ! -f "$DNS_CONF_INSTALLER" ]]; then
        return 0
    fi

    local service
    service=$(head -1 "$DNS_CONF_INSTALLER")
    if [[ -z "$service" ]]; then
        rm -f "$DNS_CONF_INSTALLER"
        return 0
    fi

    local dns_servers
    dns_servers=$(tail -n +2 "$DNS_CONF_INSTALLER")

    if [[ "$dns_servers" == "empty" ]]; then
        sudo networksetup -setdnsservers "$service" empty
    else
        # Intentionally unquoted: each DNS server must be a separate argument
        sudo networksetup -setdnsservers "$service" $dns_servers
    fi

    rm -f "$DNS_CONF_INSTALLER"
    print_success "DNS восстановлен"
}

# Запуск mihomo
start_mihomo() {
    print_step "Запуск Mihomo..."
    echo ""

    # Настройка Application Firewall (разрешаем mihomo)
    # sudo ещё интерактивный при первой установке
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$MIHOMO_BIN" 2>/dev/null
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$MIHOMO_BIN" 2>/dev/null

    # Запуск через LaunchDaemon
    sudo launchctl start ru.dostup.vpn.mihomo

    sleep 4

    if pgrep -x "mihomo" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Показ финального сообщения
show_success_message() {
    local statusbar_msg=""
    if [[ -d "$DOSTUP_DIR/statusbar/DostupVPN-StatusBar.app" ]]; then
        statusbar_msg="
Иконка в menu bar — управление VPN из статусбара"
    fi
    # Пробуем GUI диалог, если не работает - просто пропускаем
    osascript << EOF 2>/dev/null
display dialog "Mihomo успешно установлен и запущен!

Панель управления:
https://metacubex.github.io/metacubexd/

API: 127.0.0.1:9090

Приложение Dostup_VPN в ~/Applications
(доступно через Spotlight и Launchpad)${statusbar_msg}" buttons {"OK"} default button 1 with title "Dostup"
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
    OLD_SUB_URL=$(sudo sed -n 's/.*"subscription_url": *"\([^"]*\)".*/\1/p' "$SETTINGS_FILE" 2>/dev/null || true)
fi

# Остановка statusbar app
launchctl unload "$HOME/Library/LaunchAgents/ru.dostup.vpn.statusbar.plist" 2>/dev/null || true
pkill -x "DostupVPN-StatusBar" 2>/dev/null || true

# Остановка mihomo через LaunchDaemon (если загружен)
sudo launchctl stop ru.dostup.vpn.mihomo 2>/dev/null || true
sudo launchctl unload /Library/LaunchDaemons/ru.dostup.vpn.mihomo.plist 2>/dev/null || true

# Остановка mihomo если запущен (fallback для старых версий)
if pgrep -x "mihomo" > /dev/null; then
    print_step "Остановка запущенного Mihomo..."
    restore_original_dns_installer
    sudo pkill mihomo 2>/dev/null || true
    # Ожидание с timeout вместо фиксированного sleep
    stop_timeout=10
    while pgrep -x "mihomo" > /dev/null && [[ $stop_timeout -gt 0 ]]; do
        sleep 1
        stop_timeout=$((stop_timeout - 1))
    done
    # Force kill если SIGTERM не помог
    if pgrep -x "mihomo" > /dev/null; then
        sudo pkill -9 mihomo 2>/dev/null || true
        sleep 1
    fi
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
    sudo rm -f /Library/LaunchDaemons/ru.dostup.vpn.mihomo.plist
    sudo rm -f /etc/sudoers.d/dostup-vpn
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

# Скачивание geo-баз и иконки
download_assets

# Создание sites.json
create_sites_json

# Создание скрипта управления
print_step "Создание скрипта управления..."
create_control_script
print_success "Скрипт создан"

# Ярлыки на рабочем столе
create_desktop_shortcuts

# Menu bar приложение (скачивание бинарника, fallback на компиляцию)
create_statusbar_app

# Passwordless управление VPN (sudoers)
create_sudoers_entry

# LaunchDaemon для mihomo (системный сервис)
create_launch_daemon

# Save installer hash for self-update detection
installer_hash=$(curl -sL --max-time 10 "https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.command" | shasum -a 256 | cut -d' ' -f1)
if [[ -n "$installer_hash" ]]; then
    update_settings "installer_hash" "$installer_hash"
fi

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
    echo "Приложение Dostup_VPN в ~/Applications"
    echo "  (доступно через Spotlight и Launchpad)"
    if [[ -d "$DOSTUP_DIR/statusbar/DostupVPN-StatusBar.app" ]]; then
        echo "  • Иконка в menu bar (автозапуск при логине)"
    fi
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
exit 0
