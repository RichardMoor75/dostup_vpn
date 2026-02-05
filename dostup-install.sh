#!/bin/bash

# ============================================
# Dostup Installer for Mihomo (Linux)
# Ubuntu / Debian (headless server)
# ============================================

set -e

# --- Цвета для вывода ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Пути ---
DOSTUP_DIR="/opt/dostup"
LOGS_DIR="$DOSTUP_DIR/logs"
CONFIG_FILE="$DOSTUP_DIR/config.yaml"
SETTINGS_FILE="$DOSTUP_DIR/settings.json"
MIHOMO_BIN="$DOSTUP_DIR/mihomo"
CLI_PATH="/usr/local/bin/dostup"
SERVICE_FILE="/etc/systemd/system/dostup.service"

# --- URL ---
MIHOMO_RELEASES_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

# --- Глобальные переменные ---
SUB_URL=""
PROXY_PORT=""

# --- Функции вывода ---

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

# --- Проверка root ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от root (sudo)"
        echo "Используйте: sudo bash $0"
        exit 1
    fi
}

# --- Проверка ОС ---
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Не удалось определить ОС"
        exit 1
    fi

    . /etc/os-release

    if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "$ID_LIKE" != *"debian"* && "$ID_LIKE" != *"ubuntu"* ]]; then
        print_error "Поддерживаются только Ubuntu и Debian"
        print_info "Обнаружена ОС: $PRETTY_NAME"
        exit 1
    fi

    print_success "ОС: $PRETTY_NAME"
}

# --- Проверка интернета ---
check_internet() {
    print_step "Проверка подключения к интернету..."
    if ! curl -s --head --connect-timeout 5 https://github.com > /dev/null 2>&1; then
        print_error "Нет подключения к интернету"
        exit 1
    fi
    print_success "Интернет доступен"
}

# --- Определение архитектуры ---
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)
            print_error "Неподдерживаемая архитектура: $arch"
            exit 1
            ;;
    esac
}

# --- Установка зависимостей ---
install_dependencies() {
    print_step "Проверка зависимостей..."
    local need_install=false

    for pkg in curl jq; do
        if ! command -v "$pkg" &>/dev/null; then
            need_install=true
            break
        fi
    done

    if $need_install; then
        print_step "Установка зависимостей (curl, jq)..."
        apt-get update -qq
        apt-get install -y -qq curl jq
        print_success "Зависимости установлены"
    else
        print_success "Зависимости в порядке"
    fi
}

# --- Скачивание с retry ---
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if curl -fL -s -o "$output" "$url" 2>/dev/null; then
            if [[ -s "$output" ]]; then
                return 0
            fi
        fi
        retry=$((retry + 1))
        print_info "Повтор скачивания ($retry/$max_retries)..."
        sleep 2
    done
    return 1
}

# --- Валидация URL ---
validate_url() {
    [[ "$1" =~ ^https?:// ]]
}

# --- Валидация YAML ---
validate_yaml() {
    local file="$1"
    local content
    content=$(head -c 1000 "$file" 2>/dev/null)

    # Проверяем что это не HTML (ошибка сервера)
    if echo "$content" | grep -qiE '<!DOCTYPE|<html|<head'; then
        return 1
    fi

    # Проверяем базовую структуру YAML
    if echo "$content" | grep -qE '^[a-zA-Z_-]+:'; then
        return 0
    fi

    return 1
}

# --- Проверка свободен ли порт ---
check_port_free() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -qE ":${port}\b"; then
        return 1
    fi
    return 0
}

# --- Поиск свободного порта ---
find_free_port() {
    local port="$1"
    while ! check_port_free "$port"; do
        port=$((port + 1))
        if [[ $port -gt 65535 ]]; then
            print_error "Не удалось найти свободный порт"
            exit 1
        fi
    done
    echo "$port"
}

# --- Обработка конфига для Linux ---
# Удаляет: external-controller, external-ui, tun, rule-providers, RULE-SET правила
# Меняет: DNS listen на 127.0.0.1:1053
# Проверяет: свободность порта mixed-port
# Результат в глобальной переменной PROXY_PORT
process_config() {
    local config="$1"
    local temp="${config}.processing"

    # 1. Удаление external-controller, external-ui, external-ui-url
    sed '/^external-controller:/d; /^external-ui:/d; /^external-ui-url:/d' "$config" > "$temp"

    # 2. Удаление блока tun: (от tun: до следующего ключа верхнего уровня)
    awk 'BEGIN{s=0} /^tun:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"

    # 3. Удаление блока rule-providers:
    awk 'BEGIN{s=0} /^rule-providers:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"

    # 4. Удаление всех правил RULE-SET из rules:
    sed -i '/RULE-SET/d' "$temp"

    # 5. Замена DNS listen: 0.0.0.0:53 → 127.0.0.1:1053
    sed -i 's/listen: 0\.0\.0\.0:53/listen: 127.0.0.1:1053/' "$temp"

    # 6. Проверка порта mixed-port
    local port
    port=$(grep -oP 'mixed-port:\s*\K\d+' "$temp" 2>/dev/null || echo "2080")

    if ! check_port_free "$port"; then
        local new_port
        new_port=$(find_free_port "$port")
        sed -i "s/mixed-port: $port/mixed-port: $new_port/" "$temp"
        print_warning "Порт $port занят, используется $new_port"
        port="$new_port"
    fi

    mv "$temp" "$config"
    PROXY_PORT="$port"
}

# --- Получение последней версии mihomo ---
get_latest_version() {
    curl -s "$MIHOMO_RELEASES_API" | jq -r '.tag_name'
}

# --- Управление settings.json (через jq) ---
update_settings() {
    local key="$1"
    local value="$2"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    local tmp
    tmp=$(jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$SETTINGS_FILE")
    echo "$tmp" > "$SETTINGS_FILE"
}

read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        jq -r --arg k "$key" '.[$k] // ""' "$SETTINGS_FILE" 2>/dev/null
    fi
}

# --- Скачивание mihomo ---
download_mihomo() {
    local arch
    arch=$(detect_arch)

    print_step "Получение последней версии mihomo..."
    local version
    version=$(get_latest_version)

    if [[ -z "$version" || "$version" == "null" ]]; then
        print_error "Не удалось получить версию mihomo"
        return 1
    fi

    print_step "Скачивание mihomo $version для $arch..."

    local filename="mihomo-linux-${arch}-${version}.gz"
    local download_url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}"

    if ! download_with_retry "$download_url" "$DOSTUP_DIR/mihomo.gz"; then
        print_error "Не удалось скачать mihomo"
        return 1
    fi

    # Проверка SHA256
    print_step "Проверка целостности файла..."
    local checksum_url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}.sha256"
    local expected_hash
    expected_hash=$(curl -sL --fail "$checksum_url" 2>/dev/null | awk '{print $1}')

    if [[ "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]]; then
        local actual_hash
        actual_hash=$(sha256sum "$DOSTUP_DIR/mihomo.gz" | awk '{print $1}')
        if [[ "$expected_hash" != "$actual_hash" ]]; then
            print_error "Ошибка проверки хэша! Файл повреждён."
            rm -f "$DOSTUP_DIR/mihomo.gz"
            return 1
        fi
        print_success "Хэш совпадает"
    else
        print_info "SHA256 не найден, пропуск проверки"
    fi

    # Распаковка
    gunzip -f "$DOSTUP_DIR/mihomo.gz"
    chmod +x "$MIHOMO_BIN"

    # Сохраняем версию
    update_settings "installed_version" "$version"

    print_success "Mihomo $version установлен"
}

# --- Запрос URL подписки ---
# Результат в глобальной переменной SUB_URL
ask_subscription_url() {
    local old_url="$1"

    if [[ -n "$old_url" ]]; then
        print_info "Найдена предыдущая подписка"
        echo ""
        echo "1) Оставить текущую подписку"
        echo "2) Ввести новую подписку"
        echo ""
        read -p "Выберите (1 или 2): " choice

        if [[ "$choice" == "2" ]]; then
            read -p "Введите URL подписки (конфига): " SUB_URL
        else
            SUB_URL="$old_url"
            print_success "Используется предыдущая подписка"
        fi
    else
        read -p "Введите URL подписки (конфига): " SUB_URL
    fi
}

# --- Скачивание конфига ---
download_config() {
    local url="$1"
    print_step "Скачивание конфига..."

    # Бэкап старого конфига
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    local temp_config="${CONFIG_FILE}.tmp"
    if ! download_with_retry "$url" "$temp_config"; then
        print_error "Не удалось скачать конфиг"
        [[ -f "${CONFIG_FILE}.bak" ]] && mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        return 1
    fi

    if ! validate_yaml "$temp_config"; then
        print_error "Скачанный конфиг не является валидным YAML"
        rm -f "$temp_config"
        [[ -f "${CONFIG_FILE}.bak" ]] && mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        return 1
    fi

    mv "$temp_config" "$CONFIG_FILE"
    print_success "Конфиг скачан и проверен"
    return 0
}

# --- Скачивание geo-баз ---
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

# --- Создание sites.json ---
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

# --- Установка systemd-сервиса ---
install_service() {
    print_step "Установка systemd-сервиса..."

    cat > "$SERVICE_FILE" << 'EOF'
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
EOF

    systemctl daemon-reload
    systemctl enable dostup >/dev/null 2>&1
    print_success "Сервис установлен и включён в автозагрузку"
}

# --- Установка CLI-обёртки dostup ---
install_cli() {
    print_step "Установка CLI-обёртки dostup..."

    cat > "$CLI_PATH" << 'ENDOFCLI'
#!/bin/bash
# ============================================
# Dostup VPN CLI
# Управление прокси-сервером Mihomo
# ============================================

DOSTUP_DIR="/opt/dostup"
CONFIG_FILE="$DOSTUP_DIR/config.yaml"
SETTINGS_FILE="$DOSTUP_DIR/settings.json"
MIHOMO_BIN="$DOSTUP_DIR/mihomo"
SITES_FILE="$DOSTUP_DIR/sites.json"

MIHOMO_RELEASES_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step()    { echo -e "${YELLOW}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Требуется root. Используйте: sudo dostup $1"
        exit 1
    fi
}

read_settings() {
    local key="$1"
    if [[ -f "$SETTINGS_FILE" ]]; then
        jq -r --arg k "$key" '.[$k] // ""' "$SETTINGS_FILE" 2>/dev/null
    fi
}

update_settings() {
    local key="$1"
    local value="$2"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
    fi
    local tmp
    tmp=$(jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$SETTINGS_FILE")
    echo "$tmp" > "$SETTINGS_FILE"
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local retry=0
    while [[ $retry -lt 3 ]]; do
        if curl -fL -s -o "$output" "$url" 2>/dev/null && [[ -s "$output" ]]; then
            return 0
        fi
        retry=$((retry + 1))
        print_info "Повтор ($retry/3)..."
        sleep 2
    done
    return 1
}

validate_yaml() {
    local content
    content=$(head -c 1000 "$1" 2>/dev/null)
    ! echo "$content" | grep -qiE '<!DOCTYPE|<html|<head' && echo "$content" | grep -qE '^[a-zA-Z_-]+:'
}

check_port_free() {
    ! ss -tlnp 2>/dev/null | grep -qE ":${1}\b"
}

find_free_port() {
    local port="$1"
    while ! check_port_free "$port"; do
        port=$((port + 1))
    done
    echo "$port"
}

process_config() {
    local config="$1"
    local temp="${config}.processing"

    sed '/^external-controller:/d; /^external-ui:/d; /^external-ui-url:/d' "$config" > "$temp"
    awk 'BEGIN{s=0} /^tun:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"
    awk 'BEGIN{s=0} /^rule-providers:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"
    sed -i '/RULE-SET/d' "$temp"
    sed -i 's/listen: 0\.0\.0\.0:53/listen: 127.0.0.1:1053/' "$temp"

    local port
    port=$(grep -oP 'mixed-port:\s*\K\d+' "$temp" 2>/dev/null || echo "2080")
    if ! check_port_free "$port"; then
        local new_port
        new_port=$(find_free_port "$port")
        sed -i "s/mixed-port: $port/mixed-port: $new_port/" "$temp"
        print_warning "Порт $port занят, используется $new_port"
        port="$new_port"
    fi

    mv "$temp" "$config"
    echo "$port"
}

get_proxy_port() {
    grep -oP 'mixed-port:\s*\K\d+' "$CONFIG_FILE" 2>/dev/null || echo "2080"
}

# === Команды ===

do_start() {
    require_root "start"
    if systemctl is-active --quiet dostup; then
        print_info "Dostup уже запущен"
        return 0
    fi
    systemctl start dostup
    sleep 1
    if systemctl is-active --quiet dostup; then
        local port
        port=$(get_proxy_port)
        print_success "Dostup запущен (прокси: http://127.0.0.1:$port)"
    else
        print_error "Не удалось запустить Dostup"
        echo "Проверьте логи: journalctl -u dostup -n 20"
        return 1
    fi
}

do_stop() {
    require_root "stop"
    if ! systemctl is-active --quiet dostup; then
        print_info "Dostup уже остановлен"
        return 0
    fi
    systemctl stop dostup
    print_success "Dostup остановлен"
}

do_update() {
    require_root "restart"

    # 1. Проверка обновления ядра
    print_step "Проверка обновлений ядра..."
    local current_version
    current_version=$(read_settings "installed_version")
    local latest_version
    latest_version=$(curl -s "$MIHOMO_RELEASES_API" | jq -r '.tag_name' 2>/dev/null)

    if [[ -n "$latest_version" && "$latest_version" != "null" && "$current_version" != "$latest_version" ]]; then
        print_step "Обновление ядра: $current_version → $latest_version"
        local arch
        arch=$(uname -m)
        case "$arch" in
            x86_64)  arch="amd64" ;;
            aarch64) arch="arm64" ;;
        esac
        local filename="mihomo-linux-${arch}-${latest_version}.gz"
        local url="https://github.com/MetaCubeX/mihomo/releases/download/${latest_version}/${filename}"

        if download_with_retry "$url" "$DOSTUP_DIR/mihomo.gz"; then
            systemctl stop dostup 2>/dev/null || true
            gunzip -f "$DOSTUP_DIR/mihomo.gz"
            chmod +x "$MIHOMO_BIN"
            update_settings "installed_version" "$latest_version"
            print_success "Ядро обновлено до $latest_version"
        else
            print_error "Не удалось обновить ядро, используем текущую версию"
        fi
    else
        print_success "Ядро актуально ($current_version)"
    fi

    # 2. Обновление конфига
    print_step "Обновление конфига..."
    local sub_url
    sub_url=$(read_settings "subscription_url")
    if [[ -n "$sub_url" ]]; then
        [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        local temp_config="${CONFIG_FILE}.tmp"
        if download_with_retry "$sub_url" "$temp_config"; then
            if validate_yaml "$temp_config"; then
                mv "$temp_config" "$CONFIG_FILE"
                local port
                port=$(process_config "$CONFIG_FILE")
                update_settings "proxy_port" "$port"
                print_success "Конфиг обновлён (порт: $port)"
            else
                print_error "Конфиг невалидный, используем старый"
                rm -f "$temp_config"
                [[ -f "${CONFIG_FILE}.bak" ]] && mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            fi
        else
            print_error "Не удалось скачать конфиг, используем старый"
            [[ -f "${CONFIG_FILE}.bak" ]] && mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        fi
    else
        print_error "URL подписки не задан"
    fi

    # 3. Обновление geo-баз (раз в 14 дней)
    local should_update_geo=false
    local last_geo
    last_geo=$(read_settings "last_geo_update")
    if [[ -n "$last_geo" ]]; then
        local last_ts now_ts diff_days
        last_ts=$(date -d "$last_geo" +%s 2>/dev/null || echo 0)
        now_ts=$(date +%s)
        diff_days=$(( (now_ts - last_ts) / 86400 ))
        [[ $diff_days -ge 14 ]] && should_update_geo=true
    else
        should_update_geo=true
    fi

    if $should_update_geo; then
        print_step "Обновление geo-баз..."
        local geo_ok=true
        download_with_retry "$GEOIP_URL" "$DOSTUP_DIR/geoip.dat" || geo_ok=false
        download_with_retry "$GEOSITE_URL" "$DOSTUP_DIR/geosite.dat" || geo_ok=false
        if $geo_ok; then
            update_settings "last_geo_update" "$(date +%Y-%m-%d)"
            print_success "Geo-базы обновлены"
        fi
    fi

    # 4. Перезапуск
    systemctl restart dostup
    sleep 1
    if systemctl is-active --quiet dostup; then
        local port
        port=$(get_proxy_port)
        print_success "Dostup перезапущен (прокси: http://127.0.0.1:$port)"
    else
        print_error "Не удалось запустить Dostup"
        echo "Проверьте логи: journalctl -u dostup -n 20"
        return 1
    fi
}

do_status() {
    echo ""
    if systemctl is-active --quiet dostup; then
        local port version pid uptime_info
        port=$(get_proxy_port)
        version=$(read_settings "installed_version")
        pid=$(systemctl show dostup -p MainPID --value 2>/dev/null)
        uptime_info=$(systemctl show dostup -p ActiveEnterTimestamp --value 2>/dev/null)

        echo -e "${GREEN}● Dostup VPN — активен${NC}"
        echo ""
        echo "  Прокси:   http://127.0.0.1:$port"
        echo "  Версия:   $version"
        echo "  PID:      $pid"
        echo "  Запущен:  $uptime_info"
    else
        echo -e "${RED}● Dostup VPN — остановлен${NC}"
    fi
    echo ""
}

do_check() {
    if ! systemctl is-active --quiet dostup; then
        print_error "Dostup не запущен. Запустите: sudo dostup start"
        return 1
    fi

    if [[ ! -f "$SITES_FILE" ]]; then
        print_error "Файл sites.json не найден"
        return 1
    fi

    local port proxy
    port=$(get_proxy_port)
    proxy="http://127.0.0.1:$port"

    echo ""
    print_step "Проверка доступа через прокси $proxy..."
    echo ""

    local sites
    sites=$(jq -r '.sites[]' "$SITES_FILE" 2>/dev/null)

    if [[ -z "$sites" ]]; then
        print_error "Не удалось прочитать список сайтов"
        return 1
    fi

    while IFS= read -r site; do
        local code
        code=$(curl -x "$proxy" -s -o /dev/null -w "%{http_code}" --max-time 5 "https://$site" 2>/dev/null || echo "000")
        if [[ "$code" -ge 200 && "$code" -lt 400 ]]; then
            echo -e "  ${GREEN}✓ $site — доступен ($code)${NC}"
        else
            echo -e "  ${RED}✗ $site — недоступен ($code)${NC}"
        fi
    done <<< "$sites"
    echo ""
}

do_log() {
    journalctl -u dostup -f
}

do_uninstall() {
    require_root "uninstall"

    echo ""
    read -p "Вы уверены что хотите удалить Dostup VPN? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Отменено"
        return 0
    fi

    print_step "Удаление Dostup VPN..."

    systemctl stop dostup 2>/dev/null || true
    systemctl disable dostup 2>/dev/null || true
    rm -f /etc/systemd/system/dostup.service
    systemctl daemon-reload

    rm -rf /opt/dostup
    rm -f /usr/local/bin/dostup

    print_success "Dostup VPN полностью удалён"
}

do_help() {
    local port
    port=$(get_proxy_port 2>/dev/null || echo "2080")
    echo ""
    echo -e "${BLUE}Dostup VPN — управление прокси${NC}"
    echo ""
    echo "Использование: sudo dostup <команда>"
    echo ""
    echo "Команды:"
    echo "  start       Запустить VPN"
    echo "  stop        Остановить VPN"
    echo "  restart     Перезапустить + обновить конфиг/ядро/geo"
    echo "  update      Синоним restart"
    echo "  status      Показать статус"
    echo "  check       Проверить доступ к сайтам через прокси"
    echo "  log         Показать логи в реальном времени"
    echo "  uninstall   Полностью удалить Dostup VPN"
    echo "  help        Эта справка"
    echo ""
    echo "Прокси: http://127.0.0.1:$port"
    echo ""
}

# === MAIN ===
case "${1:-help}" in
    start)           do_start ;;
    stop)            do_stop ;;
    restart|update)  do_update ;;
    status)          do_status ;;
    check)           do_check ;;
    log)             do_log ;;
    uninstall)       do_uninstall ;;
    help|*)          do_help ;;
esac
ENDOFCLI

    chmod +x "$CLI_PATH"
    print_success "CLI-обёртка установлена: $CLI_PATH"
}

# --- Запуск сервиса ---
start_service() {
    print_step "Запуск Dostup VPN..."
    systemctl start dostup
    sleep 2

    if systemctl is-active --quiet dostup; then
        return 0
    else
        return 1
    fi
}

# --- Финальный вывод ---
show_result() {
    local port="$1"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ Dostup VPN установлен и запущен${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo "  Прокси:        http://127.0.0.1:$port"
    echo "  Статус:        sudo dostup status"
    echo "  Управление:    sudo dostup start|stop|restart"
    echo "  Проверка:      dostup check"
    echo "  Логи:          dostup log"
    echo ""
    echo -e "${BLUE}  ── Использование прокси ──${NC}"
    echo ""
    echo "  Разовый запуск программы через прокси:"
    echo "    HTTPS_PROXY=http://127.0.0.1:$port HTTP_PROXY=http://127.0.0.1:$port curl ifconfig.me"
    echo ""
    echo "  Добавьте алиасы в ~/.bashrc для удобства:"
    echo "    alias px='HTTPS_PROXY=http://127.0.0.1:$port HTTP_PROXY=http://127.0.0.1:$port'"
    echo "    alias codex='px codex'"
    echo "    alias claude='px claude'"
    echo "    alias npm='px npm'"
    echo "    alias pip='px pip'"
    echo ""
    echo "  Или включите прокси для всей сессии:"
    echo "    export HTTPS_PROXY=http://127.0.0.1:$port"
    echo "    export HTTP_PROXY=http://127.0.0.1:$port"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
}


# ============================================
# MAIN — Установка
# ============================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}       Dostup Installer for Mihomo${NC}"
echo -e "${BLUE}         Linux (Ubuntu / Debian)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Проверки
check_root
check_os
check_internet

# Сохраняем старую подписку если есть (до удаления)
OLD_SUB_URL=""
if [[ -f "$SETTINGS_FILE" ]]; then
    if command -v jq &>/dev/null; then
        OLD_SUB_URL=$(jq -r '.subscription_url // ""' "$SETTINGS_FILE" 2>/dev/null)
    else
        OLD_SUB_URL=$(grep -oP '"subscription_url"\s*:\s*"\K[^"]+' "$SETTINGS_FILE" 2>/dev/null || true)
    fi
fi

# Остановка сервиса если запущен
if systemctl is-active --quiet dostup 2>/dev/null; then
    print_step "Остановка запущенного Dostup..."
    systemctl stop dostup
    print_success "Dostup остановлен"
fi

# Удаление старой установки
if [[ -d "$DOSTUP_DIR" ]]; then
    print_step "Удаление старой установки..."
    rm -rf "$DOSTUP_DIR"
    print_success "Старая установка удалена"
fi

# Установка зависимостей
install_dependencies

# Создание директорий
print_step "Создание директорий..."
mkdir -p "$DOSTUP_DIR"
mkdir -p "$LOGS_DIR"
print_success "Директории созданы"

# Скачивание ядра
if ! download_mihomo; then
    print_error "Установка прервана"
    exit 1
fi

# Запрос URL подписки
print_step "Настройка подписки..."
ask_subscription_url "$OLD_SUB_URL"

if [[ -z "$SUB_URL" ]]; then
    print_error "URL подписки не указан"
    exit 1
fi

if ! validate_url "$SUB_URL"; then
    print_error "Неверный формат URL. URL должен начинаться с http:// или https://"
    exit 1
fi

update_settings "subscription_url" "$SUB_URL"

# Скачивание конфига
if ! download_config "$SUB_URL"; then
    print_error "Не удалось скачать конфиг"
    exit 1
fi

# Обработка конфига для Linux
print_step "Обработка конфига для Linux..."
process_config "$CONFIG_FILE"
update_settings "proxy_port" "$PROXY_PORT"
print_success "Конфиг обработан (порт: $PROXY_PORT)"

# Скачивание geo-баз
download_geo

# Создание sites.json
create_sites_json

# Установка systemd-сервиса
install_service

# Установка CLI-обёртки
install_cli

# Первый запуск
if start_service; then
    show_result "$PROXY_PORT"
else
    print_error "Не удалось запустить Dostup VPN"
    echo "Проверьте логи: journalctl -u dostup -n 20"
    exit 1
fi
