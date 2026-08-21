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

# URL подписки можно передать первым аргументом или переменной DOSTUP_SUB_URL —
# тогда диалог ввода не показывается. Используется персональным установщиком,
# который присылают конечному пользователю с уже вшитой ссылкой.
#   bash dostup-install.command "https://..."
#   curl -fsSL ... | bash -s -- "https://..."
# Забираем на верхнем уровне: внутри функций $1 — это уже их собственный аргумент.
SUB_URL_ARG="${1:-${DOSTUP_SUB_URL:-}}"

# Админка может передать вместо полного URL короткое имя пользователя.
# Белый список не даёт превратить имя в другой путь или произвольный URL.
SHORT_SUB_URL_BASE="https://sub.92724063.xyz/conf/yaml"

resolve_subscription_arg() {
    local value="$1"
    local LC_ALL=C

    case "$value" in
        http://*|https://*)
            printf '%s\n' "$value"
            return 0
            ;;
    esac

    if [[ "$value" =~ ^[A-Za-z0-9_-]+$ ]]; then
        printf '%s/%s.yaml\n' "$SHORT_SUB_URL_BASE" "$value"
        return 0
    fi

    return 1
}

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
    if ! curl -s --head --connect-timeout 5 --max-time 10 https://github.com > /dev/null; then
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
    curl -s --connect-timeout 10 --max-time 30 "$MIHOMO_RELEASES_API" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

get_release_assets() {
    local version="$1"
    curl -s --connect-timeout 10 --max-time 30 "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/${version}" \
        | sed -n 's/.*"name":[[:space:]]*"\([^"]*\)".*/\1/p' \
        | grep '^mihomo-darwin-' || true
}

get_macos_go_tag_candidates() {
    local macos_version
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "")
    local major="${macos_version%%.*}"

    if [[ "$major" =~ ^[0-9]+$ ]]; then
        if [[ "$major" -ge 13 ]]; then
            printf '%s\n' "go124" "go122" "go120"
        elif [[ "$major" -ge 11 ]]; then
            printf '%s\n' "go122" "go120"
        else
            printf '%s\n' "go120"
        fi
    else
        printf '%s\n' "go120"
    fi
}

asset_available() {
    local assets="$1"
    local filename="$2"
    [[ -z "$assets" ]] && return 0
    echo "$assets" | grep -Fxq "$filename"
}

resolve_mihomo_filename() {
    local arch="$1"
    local version="$2"
    local assets="$3"
    local tag
    local filename

    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        if [[ "$arch" == "amd64" ]]; then
            for filename in \
                "mihomo-darwin-amd64-v1-${tag}-${version}.gz" \
                "mihomo-darwin-amd64-${tag}-${version}.gz" \
                "mihomo-darwin-amd64-compatible-${tag}-${version}.gz"; do
                if asset_available "$assets" "$filename"; then
                    echo "$filename"
                    return 0
                fi
            done
        else
            filename="mihomo-darwin-arm64-${tag}-${version}.gz"
            if asset_available "$assets" "$filename"; then
                echo "$filename"
                return 0
            fi
        fi
    done < <(get_macos_go_tag_candidates)

    if [[ "$arch" == "amd64" ]]; then
        for filename in \
            "mihomo-darwin-amd64-v1-${version}.gz" \
            "mihomo-darwin-amd64-${version}.gz" \
            "mihomo-darwin-amd64-compatible-${version}.gz" \
            "mihomo-darwin-amd64-cgo-${version}.gz"; do
            if asset_available "$assets" "$filename"; then
                echo "$filename"
                return 0
            fi
        done
    else
        for filename in \
            "mihomo-darwin-arm64-${version}.gz" \
            "mihomo-darwin-arm64-cgo-${version}.gz"; do
            if asset_available "$assets" "$filename"; then
                echo "$filename"
                return 0
            fi
        done
    fi

    return 1
}

# Скачивание mihomo
download_mihomo() {
    local arch=$(get_arch)
    local version=$(get_latest_version)
    local assets
    local filename

    if [[ -z "$version" ]]; then
        print_error "Не удалось получить версию mihomo"
        return 1
    fi

    print_step "Скачивание mihomo $version для $arch..."

    # Выбор бинарника с учетом минимальной версии macOS (go120/go122/go124)
    assets=$(get_release_assets "$version")
    if ! filename=$(resolve_mihomo_filename "$arch" "$version" "$assets"); then
        print_error "Не удалось подобрать совместимый бинарник mihomo для macOS"
        return 1
    fi
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
    expected_hash=$(curl -sL --fail --connect-timeout 10 --max-time 30 "$checksum_url" 2>/dev/null | awk '{print $1}')

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
    local tmp_output="${output}.part"

    while [[ $retry -lt $max_retries ]]; do
        if curl -4 -fL --connect-timeout 10 --speed-time 30 --speed-limit 1024 -# -o "$tmp_output" "$url"; then
            if [[ -s "$tmp_output" ]]; then
                mv "$tmp_output" "$output"
                return 0
            fi
        fi
        rm -f "$tmp_output"
        if curl -fL --connect-timeout 10 --speed-time 30 --speed-limit 1024 -# -o "$tmp_output" "$url"; then
            if [[ -s "$tmp_output" ]]; then
                mv "$tmp_output" "$output"
                return 0
            fi
        fi
        rm -f "$tmp_output"
        retry=$((retry + 1))
        print_info "Повтор скачивания ($retry/$max_retries)..."
        sleep 2
    done
    rm -f "$tmp_output"
    return 1
}

# Безопасный bind: external-controller только на loopback.
# Меняет 'external-controller: 0.0.0.0:PORT' (любые кавычки) на '127.0.0.1:PORT'.
# При любой ошибке или невалидном результате оригинал сохраняется.
secure_config() {
    local f="$1" tmp="${1}.sec"
    if sed -E "s/^(external-controller:[[:space:]]*)['\"]?0\.0\.0\.0:([0-9]+)['\"]?(.*)$/\1'127.0.0.1:\2'\3/" "$f" > "$tmp" 2>/dev/null; then
        if [[ -s "$tmp" ]] && validate_yaml "$tmp"; then
            mv "$tmp" "$f"
            return 0
        fi
    fi
    rm -f "$tmp"
    return 0
}

# Полная проверка профиля настоящим ядром. Mihomo получает отдельную runtime-
# директорию, чтобы проверка не меняла cache.db работающей установки.
validate_mihomo_config() {
    local core="$1" config="$2"
    local runtime log rc name dir

    [[ -x "$core" && -s "$config" ]] || return 1
    runtime=$(mktemp -d "${TMPDIR:-/tmp}/dostup-validate.XXXXXX") || return 1
    log="$LOGS_DIR/mihomo-validation.log"
    mkdir -p "$LOGS_DIR"

    for name in GeoIP.dat GeoSite.dat ASN.mmdb geoip.dat geosite.dat \
        geoip.metadb country.mmdb cache.db; do
        [[ -f "$DOSTUP_DIR/$name" ]] && cp -p "$DOSTUP_DIR/$name" "$runtime/$name"
    done
    for dir in proxies rules proxy_provider rule_provider; do
        [[ -d "$DOSTUP_DIR/$dir" ]] && cp -R "$DOSTUP_DIR/$dir" "$runtime/$dir"
    done

    if "$core" -t -d "$runtime" -f "$config" >"$log" 2>&1; then
        rc=0
    else
        rc=1
    fi
    rm -rf "$runtime"
    return "$rc"
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

    # Безопасный bind для external-controller (0.0.0.0 → 127.0.0.1)
    secure_config "$temp_config"

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
INSTALLER_URL="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.command"
SITES_FILE="$DOSTUP_DIR/sites.json"
API_BASE="http://127.0.0.1:9090"

# Плановое обновление: лог, блокировка, флаги состояния
UPDATER_LOG="$DOSTUP_DIR/logs/updater.log"
LOCK_DIR="$DOSTUP_DIR/.lock"
NOTIFY_FILE="$DOSTUP_DIR/.notify"
SCRIPT_UPDATE_FLAG="$DOSTUP_DIR/.script-update"
CORE_PENDING="$DOSTUP_DIR/mihomo.new"
CORE_BACKUP="$DOSTUP_DIR/mihomo.backup"
CORE_APPLY_RESTARTED=false

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
    curl -s --connect-timeout 10 --max-time 30 "$MIHOMO_RELEASES_API" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

get_release_assets() {
    local version="$1"
    curl -s --connect-timeout 10 --max-time 30 "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/${version}" \
        | sed -n 's/.*"name":[[:space:]]*"\([^"]*\)".*/\1/p' \
        | grep '^mihomo-darwin-' || true
}

get_macos_go_tag_candidates() {
    local macos_version
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "")
    local major="${macos_version%%.*}"

    if [[ "$major" =~ ^[0-9]+$ ]]; then
        if [[ "$major" -ge 13 ]]; then
            printf '%s\n' "go124" "go122" "go120"
        elif [[ "$major" -ge 11 ]]; then
            printf '%s\n' "go122" "go120"
        else
            printf '%s\n' "go120"
        fi
    else
        printf '%s\n' "go120"
    fi
}

asset_available() {
    local assets="$1"
    local filename="$2"
    [[ -z "$assets" ]] && return 0
    echo "$assets" | grep -Fxq "$filename"
}

resolve_mihomo_filename() {
    local arch="$1"
    local version="$2"
    local assets="$3"
    local tag
    local filename

    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        if [[ "$arch" == "amd64" ]]; then
            for filename in \
                "mihomo-darwin-amd64-v1-${tag}-${version}.gz" \
                "mihomo-darwin-amd64-${tag}-${version}.gz" \
                "mihomo-darwin-amd64-compatible-${tag}-${version}.gz"; do
                if asset_available "$assets" "$filename"; then
                    echo "$filename"
                    return 0
                fi
            done
        else
            filename="mihomo-darwin-arm64-${tag}-${version}.gz"
            if asset_available "$assets" "$filename"; then
                echo "$filename"
                return 0
            fi
        fi
    done < <(get_macos_go_tag_candidates)

    if [[ "$arch" == "amd64" ]]; then
        for filename in \
            "mihomo-darwin-amd64-v1-${version}.gz" \
            "mihomo-darwin-amd64-${version}.gz" \
            "mihomo-darwin-amd64-compatible-${version}.gz" \
            "mihomo-darwin-amd64-cgo-${version}.gz"; do
            if asset_available "$assets" "$filename"; then
                echo "$filename"
                return 0
            fi
        done
    else
        for filename in \
            "mihomo-darwin-arm64-${version}.gz" \
            "mihomo-darwin-arm64-cgo-${version}.gz"; do
            if asset_available "$assets" "$filename"; then
                echo "$filename"
                return 0
            fi
        done
    fi

    return 1
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local retry=0
    local tmp_output="${output}.part"
    while [[ $retry -lt 3 ]]; do
        if curl -4 -fL --connect-timeout 10 --speed-time 30 --speed-limit 1024 -# -o "$tmp_output" "$url"; then
            if [[ -s "$tmp_output" ]]; then
                mv "$tmp_output" "$output"
                return 0
            fi
        fi
        rm -f "$tmp_output"
        if curl -fL --connect-timeout 10 --speed-time 30 --speed-limit 1024 -# -o "$tmp_output" "$url"; then
            if [[ -s "$tmp_output" ]]; then
                mv "$tmp_output" "$output"
                return 0
            fi
        fi
        rm -f "$tmp_output"
        retry=$((retry + 1))
        echo -e "${YELLOW}ℹ Повтор ($retry/3)...${NC}"
        sleep 2
    done
    rm -f "$tmp_output"
    return 1
}

verify_mihomo_checksum() {
    local version="$1"
    local filename="$2"
    local archive="$3"
    local checksum_url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}.sha256"
    local expected_hash
    expected_hash=$(curl -sL --fail --connect-timeout 10 --max-time 30 "$checksum_url" 2>/dev/null | awk '{print $1}')

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

# Безопасный bind: external-controller только на loopback
secure_config() {
    local f="$1" tmp="${1}.sec"
    if sed -E "s/^(external-controller:[[:space:]]*)['\"]?0\.0\.0\.0:([0-9]+)['\"]?(.*)$/\1'127.0.0.1:\2'\3/" "$f" > "$tmp" 2>/dev/null; then
        if [[ -s "$tmp" ]] && validate_yaml "$tmp"; then
            mv "$tmp" "$f"
            return 0
        fi
    fi
    rm -f "$tmp"
    return 0
}

# Проверяем профиль настоящим ядром в изолированной runtime-директории.
validate_mihomo_config() {
    local core="$1" config="$2"
    local runtime log rc name dir

    [[ -x "$core" && -s "$config" ]] || return 1
    runtime=$(mktemp -d "${TMPDIR:-/tmp}/dostup-validate.XXXXXX") || return 1
    log="$DOSTUP_DIR/logs/mihomo-validation.log"
    mkdir -p "$DOSTUP_DIR/logs"

    for name in GeoIP.dat GeoSite.dat ASN.mmdb geoip.dat geosite.dat \
        geoip.metadb country.mmdb cache.db; do
        [[ -f "$DOSTUP_DIR/$name" ]] && cp -p "$DOSTUP_DIR/$name" "$runtime/$name"
    done
    for dir in proxies rules proxy_provider rule_provider; do
        [[ -d "$DOSTUP_DIR/$dir" ]] && cp -R "$DOSTUP_DIR/$dir" "$runtime/$dir"
    done

    if "$core" -t -d "$runtime" -f "$config" >"$log" 2>&1; then
        rc=0
    else
        rc=1
    fi
    rm -rf "$runtime"
    return "$rc"
}

# --- Плановое обновление: инфраструктура ---

log_updater() {
    mkdir -p "$DOSTUP_DIR/logs" 2>/dev/null
    # Обрезаем разросшийся лог, оставляя хвост
    if [[ -f "$UPDATER_LOG" ]] && [[ $(wc -l < "$UPDATER_LOG" 2>/dev/null || echo 0) -gt 500 ]]; then
        tail -n 200 "$UPDATER_LOG" > "${UPDATER_LOG}.tmp" 2>/dev/null && mv "${UPDATER_LOG}.tmp" "$UPDATER_LOG"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$UPDATER_LOG"
}

# Блокировка через mkdir — атомарна. Зависшую (>20 мин) снимаем.
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        return 0
    fi
    if [[ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +20 2>/dev/null)" ]]; then
        log_updater "WARN снята зависшая блокировка"
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR" 2>/dev/null && return 0
    fi
    return 1
}

release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null
}

# Уведомление: текст забирает statusbar-приложение (иконка, единый стиль).
# Если оно не запущено или файл никто не забрал за час — показываем напрямую.
notify_user() {
    local text="$1"
    if [[ -f "$NOTIFY_FILE" ]] && [[ -n "$(find "$NOTIFY_FILE" -maxdepth 0 -mmin +60 2>/dev/null)" ]]; then
        rm -f "$NOTIFY_FILE"
    fi
    if pgrep -x "DostupVPN-StatusBar" > /dev/null 2>&1; then
        printf '%s\n' "$text" >> "$NOTIFY_FILE"
    else
        # Префикс @ACTION@ понимает только statusbar-приложение (делает уведомление
        # кликабельным) — в текстовом fallback его надо убрать
        local plain="${text#@ACTION@}"
        osascript -e "display notification \"${plain//\"/\\\"}\" with title \"Dostup VPN\"" >/dev/null 2>&1 || true
    fi
}

# Перезагрузка конфига работающим mihomo без рестарта процесса
reload_mihomo_config() {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
        -X PUT "${API_BASE}/configs?force=true" \
        -d "{\"path\":\"${CONFIG_FILE}\",\"payload\":\"\"}" 2>/dev/null)
    [[ "$code" == "204" || "$code" == "200" ]]
}

# Обновление профиля по ссылке подписки.
# 0 — профиль изменился и применён, 1 — изменений нет, 2 — ошибка
update_profile() {
    local sub_url tmp new_hash old_hash
    sub_url=$(read_settings "subscription_url")
    if [[ -z "$sub_url" ]]; then
        log_updater "profile: URL подписки не задан"
        return 2
    fi

    tmp="${CONFIG_FILE}.new"
    if ! download_with_retry "$sub_url" "$tmp"; then
        log_updater "profile: не удалось скачать"
        rm -f "$tmp"
        return 2
    fi

    # Истёкшая подписка обычно отдаёт HTML — затирать им рабочий конфиг нельзя
    if ! validate_yaml "$tmp"; then
        log_updater "profile: ответ сервера не YAML (истекла подписка?)"
        rm -f "$tmp"
        return 2
    fi

    secure_config "$tmp"

    # Поверхностной проверки YAML недостаточно: до замены рабочего файла
    # действующее ядро должно принять профиль целиком.
    if ! validate_mihomo_config "$MIHOMO_BIN" "$tmp"; then
        log_updater "profile: mihomo отклонил кандидат, рабочий профиль сохранён"
        rm -f "$tmp"
        return 2
    fi

    new_hash=$(shasum -a 256 "$tmp" | cut -d' ' -f1)
    old_hash=$(shasum -a 256 "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1)
    if [[ -n "$old_hash" && "$new_hash" == "$old_hash" ]]; then
        rm -f "$tmp"
        log_updater "profile: без изменений"
        return 1
    fi

    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    mv "$tmp" "$CONFIG_FILE"

    if ! pgrep -x "mihomo" > /dev/null; then
        log_updater "profile: обновлён (mihomo не запущен, применится при старте)"
        return 0
    fi

    if reload_mihomo_config; then
        log_updater "profile: обновлён и применён"
        return 0
    fi

    log_updater "profile: ОШИБКА перезагрузки, откат на предыдущий"
    if [[ -f "${CONFIG_FILE}.backup" ]]; then
        cp "${CONFIG_FILE}.backup" "$CONFIG_FILE"
        reload_mihomo_config || true
    fi
    return 2
}

# Geo-базы раз в 14 дней. 0 — обновлены, 1 — рано или ошибка
update_geo_if_due() {
    local last_geo last_ts now_ts diff_days ok
    last_geo=$(read_settings "last_geo_update")
    if [[ -n "$last_geo" ]]; then
        last_ts=$(date -j -f "%Y-%m-%d" "$last_geo" "+%s" 2>/dev/null || echo 0)
        now_ts=$(date "+%s")
        diff_days=$(( (now_ts - last_ts) / 86400 ))
        [[ $diff_days -lt 14 ]] && return 1
    fi
    ok=true
    download_with_retry "$GEOIP_URL" "$DOSTUP_DIR/geoip.dat" || ok=false
    download_with_retry "$GEOSITE_URL" "$DOSTUP_DIR/geosite.dat" || ok=false
    if $ok; then
        update_settings "last_geo_update" "$(date +%Y-%m-%d)"
        log_updater "geo: обновлены"
        return 0
    fi
    log_updater "geo: ошибка обновления"
    return 1
}

# Загрузка ядра рядом с работающим. Кандидат проверяется до остановки VPN.
# 0 — кандидат готов к применению, 1 — обновления нет, 2 — ошибка.
preload_core() {
    local current latest pending arch assets filename url
    current=$(read_settings "installed_version")
    latest=$(get_latest_version)
    if [[ -z "$latest" ]]; then
        log_updater "core: не удалось получить последнюю версию"
        return 2
    fi
    if [[ "$current" == "$latest" ]]; then
        rm -f "$CORE_PENDING"
        update_settings "pending_core_version" ""
        log_updater "core: актуально ($current)"
        return 1
    fi
    pending=$(read_settings "pending_core_version")
    if [[ "$pending" == "$latest" && -f "$CORE_PENDING" ]]; then
        if validate_mihomo_config "$CORE_PENDING" "$CONFIG_FILE"; then
            log_updater "core: $latest уже скачано и проверено"
            return 0
        fi
        log_updater "core: ранее скачанный кандидат $latest не прошёл проверку"
        rm -f "$CORE_PENDING"
        update_settings "pending_core_version" ""
    fi

    arch=$(uname -m)
    [[ "$arch" == "arm64" ]] || arch="amd64"
    assets=$(get_release_assets "$latest")
    if ! filename=$(resolve_mihomo_filename "$arch" "$latest" "$assets"); then
        log_updater "core: нет совместимого бинарника для этой версии macOS"
        return 2
    fi
    url="https://github.com/MetaCubeX/mihomo/releases/download/${latest}/${filename}"
    if ! download_with_retry "$url" "${CORE_PENDING}.gz"; then
        log_updater "core: не удалось скачать $latest"
        rm -f "${CORE_PENDING}.gz"
        return 2
    fi
    if ! verify_mihomo_checksum "$latest" "$filename" "${CORE_PENDING}.gz" >/dev/null 2>&1; then
        log_updater "core: ошибка проверки хэша"
        rm -f "${CORE_PENDING}.gz"
        return 2
    fi
    rm -f "$CORE_PENDING"
    if ! gunzip -f "${CORE_PENDING}.gz"; then
        log_updater "core: ошибка распаковки"
        rm -f "${CORE_PENDING}.gz" "$CORE_PENDING"
        return 2
    fi
    chmod +x "$CORE_PENDING"
    xattr -d com.apple.quarantine "$CORE_PENDING" 2>/dev/null || true

    if ! validate_mihomo_config "$CORE_PENDING" "$CONFIG_FILE"; then
        log_updater "core: $latest несовместимо с текущим профилем"
        rm -f "$CORE_PENDING"
        update_settings "pending_core_version" ""
        return 2
    fi

    update_settings "pending_core_version" "$latest"
    log_updater "core: $latest скачано и проверено"
    return 0
}

# Проверка локального API после запуска. Код 401 тоже означает, что новое ядро
# поднялось; авторизация API может быть включена самим профилем.
wait_mihomo_api() {
    local waited=0 code
    while [[ $waited -lt 15 ]]; do
        if ! pgrep -x "mihomo" > /dev/null; then
            return 1
        fi
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
            "${API_BASE}/version" 2>/dev/null || true)
        [[ "$code" == "200" || "$code" == "401" ]] && return 0
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# Атомарное применение проверенного ядра. Если VPN работал, он сразу
# перезапускается; при любой ошибке возвращается предыдущий бинарник.
# 0 — применено, 1 — кандидата нет, 2 — обновление отменено/выполнен откат.
apply_pending_core() {
    local pending previous was_running=false
    CORE_APPLY_RESTARTED=false
    [[ -x "$CORE_PENDING" ]] || return 1

    pending=$(read_settings "pending_core_version")
    previous=$(read_settings "installed_version")
    if ! validate_mihomo_config "$CORE_PENDING" "$CONFIG_FILE"; then
        log_updater "core: кандидат ${pending:-новый} отклонён перед применением"
        rm -f "$CORE_PENDING"
        update_settings "pending_core_version" ""
        return 2
    fi

    if pgrep -x "mihomo" > /dev/null; then
        was_running=true
        if ! do_stop >/dev/null 2>&1; then
            log_updater "core: не удалось остановить VPN, рабочее ядро сохранено"
            return 2
        fi
    fi

    rm -f "$CORE_BACKUP"
    if [[ -f "$MIHOMO_BIN" ]] && ! cp -p "$MIHOMO_BIN" "$CORE_BACKUP"; then
        log_updater "core: не удалось создать резервную копию"
        $was_running && do_start_quick --skip-promote >/dev/null 2>&1 || true
        return 2
    fi
    if ! mv "$CORE_PENDING" "$MIHOMO_BIN"; then
        log_updater "core: не удалось установить кандидат"
        rm -f "$CORE_BACKUP"
        $was_running && do_start_quick --skip-promote >/dev/null 2>&1 || true
        return 2
    fi
    chmod +x "$MIHOMO_BIN"
    xattr -d com.apple.quarantine "$MIHOMO_BIN" 2>/dev/null || true

    if $was_running; then
        if do_start_quick --skip-promote >/dev/null 2>&1 && wait_mihomo_api; then
            CORE_APPLY_RESTARTED=true
        else
            log_updater "core: новое ядро не прошло проверку запуска, откат"
            do_stop >/dev/null 2>&1 || true
            if [[ -f "$CORE_BACKUP" ]]; then
                mv "$CORE_BACKUP" "$MIHOMO_BIN"
                chmod +x "$MIHOMO_BIN"
            fi
            [[ -n "$previous" ]] && update_settings "installed_version" "$previous"
            update_settings "pending_core_version" ""
            if ! do_start_quick --skip-promote >/dev/null 2>&1 || ! wait_mihomo_api; then
                log_updater "core: КРИТИЧНО — предыдущее ядро восстановлено, но VPN не запустился"
            else
                log_updater "core: предыдущее ядро восстановлено и запущено"
            fi
            return 2
        fi
    fi

    rm -f "$CORE_BACKUP"
    [[ -n "$pending" ]] && update_settings "installed_version" "$pending"
    update_settings "pending_core_version" ""
    log_updater "core: применена версия ${pending:-новая}"
    return 0
}

# Совместимость с уже скачанным mihomo.new из предыдущей версии скрипта.
promote_core() {
    [[ -x "$CORE_PENDING" ]] || return 1
    pgrep -x "mihomo" > /dev/null && return 1
    apply_pending_core
}

# Проверка обновления самого скрипта. 0 — обновление найдено ВПЕРВЫЕ (нужно уведомить)
check_script_update_flag() {
    local current_hash new_hash tmp
    current_hash=$(read_settings "installer_hash")
    [[ -z "$current_hash" ]] && return 1
    tmp=$(mktemp "${TMPDIR:-/tmp}/dostup-inst.XXXXXX") || return 1
    if ! download_with_retry "$INSTALLER_URL" "$tmp"; then
        rm -f "$tmp"
        log_updater "script: не удалось проверить обновление"
        return 1
    fi
    new_hash=$(shasum -a 256 "$tmp" | cut -d' ' -f1)
    rm -f "$tmp"
    if [[ -n "$new_hash" && "$new_hash" != "$current_hash" ]]; then
        if [[ ! -f "$SCRIPT_UPDATE_FLAG" ]]; then
            echo "$new_hash" > "$SCRIPT_UPDATE_FLAG"
            log_updater "script: доступно обновление"
            return 0
        fi
        return 1
    fi
    rm -f "$SCRIPT_UPDATE_FLAG"
    return 1
}

# Обновление провайдеров прокси и правил через API. Печатает краткий итог.
refresh_providers() {
    local names name ok fail code
    ok=0
    fail=0
    names=$(get_proxy_providers)
    if [ -n "$names" ]; then
        while IFS= read -r name; do
            code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --max-time 15 \
                "${API_BASE}/providers/proxies/$name" 2>/dev/null || true)
            if [[ "$code" == "200" || "$code" == "204" ]]; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
            fi
        done <<< "$names"
    fi
    names=$(get_rule_providers)
    if [ -n "$names" ]; then
        while IFS= read -r name; do
            code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --max-time 15 \
                "${API_BASE}/providers/rules/$name" 2>/dev/null || true)
            if [[ "$code" == "200" || "$code" == "204" ]]; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
            fi
        done <<< "$names"
    fi
    if [[ $ok -eq 0 && $fail -eq 0 ]]; then
        echo "Провайдеры не найдены"
        return 1
    fi
    if [[ $fail -eq 0 ]]; then
        echo "Провайдеры обновлены ($ok)"
        return 0
    fi
    echo "Провайдеры: $ok обновлено, $fail с ошибкой"
    return 1
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
    local preload_result apply_result

    preload_core
    preload_result=$?
    case "$preload_result" in
        0)
            apply_pending_core
            apply_result=$?
            if [[ "$apply_result" -eq 0 ]]; then
                if $CORE_APPLY_RESTARTED; then
                    echo -e "${GREEN}✓ Ядро обновлено, VPN перезапущен${NC}"
                else
                    echo -e "${GREEN}✓ Ядро обновлено, VPN оставлен остановленным${NC}"
                fi
            else
                echo -e "${RED}✗ Обновление ядра отменено, рабочая версия сохранена${NC}"
            fi
            ;;
        1)
            echo -e "${GREEN}✓ Ядро актуально${NC}"
            ;;
        *)
            echo -e "${RED}✗ Не удалось подготовить обновление, рабочая версия сохранена${NC}"
            ;;
    esac
}

do_update_config() {
    echo -e "${YELLOW}▶ Скачивание конфига...${NC}"
    sub_url=$(read_settings "subscription_url")
    if [[ -n "$sub_url" ]]; then
        [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"

        temp_config="${CONFIG_FILE}.tmp"
        if download_with_retry "$sub_url" "$temp_config"; then
            if validate_yaml "$temp_config"; then
                secure_config "$temp_config"
                if validate_mihomo_config "$MIHOMO_BIN" "$temp_config"; then
                    mv "$temp_config" "$CONFIG_FILE"
                    echo -e "${GREEN}✓ Конфиг обновлён и проверен${NC}"
                else
                    echo -e "${RED}✗ Mihomo отклонил новый конфиг, используем старый${NC}"
                    rm -f "$temp_config"
                    [[ -f "${CONFIG_FILE}.backup" ]] && mv "${CONFIG_FILE}.backup" "$CONFIG_FILE"
                fi
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
    [[ "${1:-}" == "--skip-promote" ]] || promote_core || true

    # Настройка Application Firewall
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --add "$MIHOMO_BIN" 2>/dev/null || true
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$MIHOMO_BIN" 2>/dev/null || true

    # Запуск через LaunchDaemon
    sudo -n launchctl start ru.dostup.vpn.mihomo
    wait_mihomo_started

    if pgrep -x "mihomo" > /dev/null; then
        save_and_set_mihomo_dns
        return 0
    else
        return 1
    fi
}

# Ожидание готовности mihomo вместо фиксированного sleep: большой конфиг или
# медленные провайдеры могут не уложиться в 4 секунды и дать ложный «не запустился».
wait_mihomo_started() {
    local waited=0
    while [[ $waited -lt 20 ]]; do
        sleep 1
        waited=$((waited + 1))
        if pgrep -x "mihomo" > /dev/null; then
            # Процесс есть — даём ему дочитать конфиг и поднять листенеры
            sleep 2
            return 0
        fi
    done
    return 1
}

do_start() {
    # Здесь намеренно НЕТ сетевых операций: запуск идёт при выключенном VPN,
    # и любая загрузка с GitHub в этот момент может висеть минутами.
    # Профиль, geo-базы, ядро и обновление скрипта тянет фоновый ru.dostup.vpn.updater.
    if promote_core; then
        echo -e "${GREEN}✓ Установлена обновлённая версия ядра${NC}"
    fi

    # Запуск
    echo -e "${YELLOW}▶ Запуск Mihomo...${NC}"
    echo ""

    # Настройка Application Firewall
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --add "$MIHOMO_BIN" 2>/dev/null
    sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$MIHOMO_BIN" 2>/dev/null

    # Запуск через LaunchDaemon
    sudo -n launchctl start ru.dostup.vpn.mihomo

    wait_mihomo_started

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
            if ! acquire_lock; then
                echo "Обновление уже выполняется, попробуйте позже"
                exit 0
            fi
            trap release_lock EXIT
            if ! do_stop >/dev/null 2>&1; then
                # Ошибку остановки нельзя глушить: без неё launchctl start — no-op,
                # и «перезапуск» выглядел бы успешным, хотя жив старый процесс
                # со старым конфигом.
                log_updater "restart: не удалось остановить mihomo"
                # do_stop успел вернуть системный DNS, а VPN остался жив —
                # возвращаем публичный, иначе запросы пойдут мимо туннеля
                if pgrep -x "mihomo" > /dev/null && [[ ! -f "$DNS_CONF" ]]; then
                    save_and_set_mihomo_dns >/dev/null 2>&1
                fi
                echo "Не удалось остановить VPN"
                exit 0
            fi
            core_msg=""
            promote_core >/dev/null 2>&1 && core_msg="Ядро обновлено. "
            do_start >/dev/null 2>&1
            if pgrep -x "mihomo" > /dev/null; then
                echo "${core_msg}VPN перезапущен"
            else
                log_updater "restart: mihomo не поднялся"
                echo "Ошибка перезапуска"
            fi
            exit 0
            ;;
        scheduled-update)
            # Вызывается LaunchAgent'ом ru.dostup.vpn.updater раз в 6 часов
            if ! acquire_lock; then
                log_updater "плановое обновление пропущено: занято"
                exit 0
            fi
            trap release_lock EXIT
            log_updater "--- плановое обновление ---"
            update_profile
            case $? in
                0) notify_user "Профиль обновлён" ;;
            esac
            update_geo_if_due
            preload_core
            core_prepare_result=$?
            if [[ "$core_prepare_result" -eq 0 ]]; then
                apply_pending_core
                core_apply_result=$?
                if [[ "$core_apply_result" -eq 0 ]]; then
                    if $CORE_APPLY_RESTARTED; then
                        notify_user "Ядро обновлено, VPN автоматически перезапущен"
                    else
                        notify_user "Ядро обновлено, VPN оставлен остановленным"
                    fi
                elif [[ "$core_apply_result" -eq 2 ]]; then
                    notify_user "Обновление ядра отменено, рабочая версия сохранена"
                fi
            fi
            check_script_update_flag && \
                notify_user "@ACTION@Доступно обновление Dostup VPN — нажмите, чтобы обновить"
            exit 0
            ;;
        update-profile-silent)
            # Кнопка «Обновить прокси и правила» из меню иконки
            if ! acquire_lock; then
                echo "Обновление уже выполняется"
                exit 0
            fi
            trap release_lock EXIT
            profile_msg=""
            update_profile
            case $? in
                0) profile_msg="Профиль обновлён. " ;;
                2) profile_msg="Профиль обновить не удалось. " ;;
            esac
            echo "${profile_msg}$(refresh_providers)"
            exit 0
            ;;
        self-update)
            # Запускается в Терминале: установщику нужны пароль и ответы пользователя
            echo ""
            echo -e "${YELLOW}▶ Обновление Dostup VPN${NC}"
            echo ""
            tmp_installer=$(mktemp "${TMPDIR:-/tmp}/dostup-inst.XXXXXX") || exit 1
            if ! download_with_retry "$INSTALLER_URL" "$tmp_installer"; then
                echo -e "${RED}✗ Не удалось скачать установщик${NC}"
                rm -f "$tmp_installer"
                read -p "Нажмите Enter для закрытия..." < /dev/tty
                exit 1
            fi
            if ! head -1 "$tmp_installer" | grep -q '^#!/bin/bash'; then
                echo -e "${RED}✗ Скачанный файл не похож на установщик${NC}"
                rm -f "$tmp_installer"
                read -p "Нажмите Enter для закрытия..." < /dev/tty
                exit 1
            fi
            rm -f "$SCRIPT_UPDATE_FLAG"
            bash "$tmp_installer"
            rm -f "$tmp_installer"
            exit 0
            ;;
        update-providers)
            echo "Обновление профиля..."
            update_profile
            case $? in
                0) echo -e "${GREEN}✓ Профиль обновлён${NC}" ;;
                1) echo -e "${GREEN}✓ Профиль без изменений${NC}" ;;
                *) echo -e "${RED}✗ Профиль обновить не удалось${NC}" ;;
            esac
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
            echo "Обновление профиля..."
            update_profile
            case $? in
                0) echo -e "${GREEN}✓ Профиль обновлён${NC}" ;;
                1) echo -e "${GREEN}✓ Профиль без изменений${NC}" ;;
                *) echo -e "${RED}✗ Профиль обновить не удалось${NC}" ;;
            esac
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
    download_with_retry "$ICON_APP_URL" "$DOSTUP_DIR/icon_app.png" || true
    # Иконки для статусбара (36x36 PNG)
    mkdir -p "$DOSTUP_DIR/statusbar"
    download_with_retry "$ICON_ON_URL" "$DOSTUP_DIR/statusbar/icon_on.png" || true
    download_with_retry "$ICON_OFF_URL" "$DOSTUP_DIR/statusbar/icon_off.png" || true
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
    <string>10.13</string>
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

# Готовый Swift-бинарник собран с deployment target 10.15 для Intel и 11.0
# для Apple Silicon. На более старом Mac VPN остаётся доступен через
# ~/Applications/Dostup_VPN.app.
statusbar_supported_on_this_macos() {
    local version major minor arch
    version=$(sw_vers -productVersion 2>/dev/null || true)
    major=${version%%.*}
    minor=${version#*.}; minor=${minor%%.*}
    arch=$(uname -m)

    # Если версию определить не удалось, безопаснее попробовать запуск и
    # положиться на runtime-проверку ниже.
    [[ "$major" =~ ^[0-9]+$ ]] || return 0
    if [[ "$arch" == "arm64" ]]; then
        [[ "$major" -ge 11 ]]
    else
        [[ "$major" -gt 10 ]] || \
            { [[ "$major" -eq 10 ]] && [[ "${minor:-0}" -ge 15 ]]; }
    fi
}

verify_statusbar_app() {
    local app_path="$1" waited=0 pid
    local binary_path="$app_path/Contents/MacOS/DostupVPN-StatusBar"
    local launch_log="$LOGS_DIR/statusbar-launch.log"
    mkdir -p "$LOGS_DIR"
    : > "$launch_log"
    pkill -x "DostupVPN-StatusBar" 2>/dev/null || true

    # Первый запуск напрямую сохраняет сообщение dyld о недостающей библиотеке.
    # Затем приложение перезапускается через LaunchServices для правильной
    # bundle identity и уведомлений.
    [[ -x "$binary_path" ]] || return 1
    "$binary_path" >>"$launch_log" 2>&1 &
    pid=$!
    sleep 3
    if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null || true
        return 1
    fi
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    if ! /usr/bin/open -a "$app_path" 2>>"$launch_log"; then
        return 1
    fi
    while [[ $waited -lt 8 ]]; do
        sleep 1
        waited=$((waited + 1))
        if [[ $waited -ge 3 ]] && pgrep -x "DostupVPN-StatusBar" > /dev/null; then
            # Процесс должен пережить ещё один цикл: так ловятся ошибки dyld,
            # при которых приложение появляется и сразу завершается.
            sleep 2
            pgrep -x "DostupVPN-StatusBar" > /dev/null && return 0
        fi
    done
    return 1
}

disable_statusbar_app() {
    local plist="$HOME/Library/LaunchAgents/ru.dostup.vpn.statusbar.plist"
    launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
    pkill -x "DostupVPN-StatusBar" 2>/dev/null || true
}

# Создание menu bar приложения
create_statusbar_app() {
    print_step "Создание menu bar приложения..."

    local statusbar_dir="$DOSTUP_DIR/statusbar"
    local app_path="$statusbar_dir/DostupVPN-StatusBar.app"

    mkdir -p "$statusbar_dir"
    mkdir -p "$app_path/Contents/MacOS"
    mkdir -p "$app_path/Contents/Resources"

    if ! statusbar_supported_on_this_macos; then
        local macos_version
        macos_version=$(sw_vers -productVersion 2>/dev/null || echo "неизвестна")
        print_warning "Menu bar недоступен на macOS $macos_version"
        print_info "VPN будет работать через приложение Dostup_VPN"
        disable_statusbar_app
        rm -rf "$statusbar_dir"
        return 0
    fi

    # Иконки для статусбара уже скачаны в download_icon()
    # Копируем иконку приложения для уведомлений
    if [[ -f "$DOSTUP_DIR/icon.icns" ]]; then
        cp "$DOSTUP_DIR/icon.icns" "$app_path/Contents/Resources/AppIcon.icns"
    fi

    # Записываем Swift-исходник
    cat > "$statusbar_dir/DostupVPN-StatusBar.swift" << 'SWIFTSOURCE'
import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var restartMenuItem: NSMenuItem!
    private var updateProvidersMenuItem: NSMenuItem!
    private var healthcheckMenuItem: NSMenuItem!
    private var checkMenuItem: NSMenuItem!
    private var updateScriptMenuItem: NSMenuItem!
    private var timer: Timer?

    // Пока идёт перезапуск, таймер не трогает заголовок статуса —
    // иначе через 5 секунд «Перезапуск...» сменяется на «VPN остановлен»
    // и пользователь считает, что перезапуск не сработал.
    private var isRestarting = false

    private var colorIcon: NSImage?
    private var grayIcon: NSImage?

    private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    private var controlScript: String {
        return homeDir + "/dostup/Dostup_VPN.command"
    }
    // Флаг наличия обновления ставит планировщик (control script)
    private var scriptUpdateFlag: String {
        return homeDir + "/dostup/.script-update"
    }
    // Очередь уведомлений от фоновых bash-задач
    private var notifyFile: String {
        return homeDir + "/dostup/.notify"
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Устанавливаем иконку приложения для уведомлений
        if let appIcon = NSImage(contentsOfFile: homeDir + "/dostup/icon_app.png") {
            NSApplication.shared.applicationIconImage = appIcon
        }
        // Без делегата клики по уведомлениям никуда не приходят
        NSUserNotificationCenter.default.delegate = self
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

        // Update script (виден только когда планировщик нашёл обновление)
        updateScriptMenuItem = NSMenuItem(title: "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} \u{0441}\u{043A}\u{0440}\u{0438}\u{043F}\u{0442}", action: #selector(updateScript), keyEquivalent: "")
        updateScriptMenuItem.target = self
        updateScriptMenuItem.isHidden = true
        menu.addItem(updateScriptMenuItem)

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

        drainPendingNotifications()
        updateScriptMenuItem.isHidden = !FileManager.default.fileExists(atPath: scriptUpdateFlag)

        // Во время перезапуска состоянием меню управляет restartVPN()
        if isRestarting { return }

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

    // MARK: - Pending Notifications

    // Фоновые задачи (планировщик ru.dostup.vpn.updater) складывают текст сюда,
    // чтобы уведомление ушло от приложения — с иконкой и в едином стиле.
    private func drainPendingNotifications() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: notifyFile) else { return }
        let content = (try? String(contentsOfFile: notifyFile, encoding: .utf8)) ?? ""
        try? fm.removeItem(atPath: notifyFile)

        var actionable = false
        var texts: [String] = []
        for raw in content.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("@ACTION@") {
                actionable = true
                texts.append(String(line.dropFirst(8)))
            } else {
                texts.append(line)
            }
        }
        guard !texts.isEmpty else { return }
        showNotification(title: "Dostup VPN",
                         text: texts.joined(separator: "\n"),
                         actionable: actionable)
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
        isRestarting = true
        restartMenuItem.isEnabled = false
        updateProvidersMenuItem.isEnabled = false
        statusMenuItem.title = "\u{21BB} \u{041F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0441}\u{043A}..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let output = self.runControlScript("restart-silent")
            let text = output.isEmpty ? "VPN \u{043F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0449}\u{0435}\u{043D}" : output

            DispatchQueue.main.async {
                self.isRestarting = false
                self.showNotification(title: "Dostup VPN", text: text)
                self.updateStatus()
            }
        }
    }

    @objc private func updateProviders() {
        updateProvidersMenuItem.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // Профиль по ссылке подписки + провайдеры прокси и правил.
            // Логика целиком в control script: её можно менять без пересборки бинарника.
            let output = self.runControlScript("update-profile-silent")
            let text = output.isEmpty ? "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}\u{0438}\u{0435} \u{0437}\u{0430}\u{0432}\u{0435}\u{0440}\u{0448}\u{0435}\u{043D}\u{043E}" : output
            DispatchQueue.main.async {
                self.showNotification(title: "Dostup VPN", text: text)
                self.updateStatus()
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

    // Установщику нужны пароль и ответы пользователя — только в Терминале
    @objc private func updateScript() {
        runInTerminal(argument: "self-update")
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

    // Синхронный вызов control script с чтением stdout.
    // Читаем ДО waitUntilExit: иначе при выводе больше размера буфера пайпа
    // дочерний процесс заблокируется на записи, а мы — в ожидании его выхода.
    private func runControlScript(_ argument: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [controlScript, argument]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

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

    // MARK: - Notifications

    private func showNotification(title: String, text: String, actionable: Bool = false) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        notification.contentImage = NSImage(contentsOfFile: homeDir + "/dostup/icon_app.png")
        if actionable {
            notification.hasActionButton = true
            notification.actionButtonTitle = "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C}"
            notification.userInfo = ["action": "self-update"]
        }
        NSUserNotificationCenter.default.deliver(notification)
    }

    // Приложение живёт в статусбаре и формально почти всегда «активно» —
    // без этого системa решит не показывать уведомление.
    func userNotificationCenter(_ center: NSUserNotificationCenter,
                                shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter,
                                didActivate notification: NSUserNotification) {
        guard let action = notification.userInfo?["action"] as? String else { return }
        // Кнопка действия видна только в стиле «Предупреждения»; в «Баннерах»
        // работает клик по телу уведомления — обрабатываем оба случая.
        switch notification.activationType {
        case .actionButtonClicked, .contentsClicked:
            runInTerminal(argument: action)
        default:
            break
        }
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
    local swiftc_bin=""
    local dev_dir=""
    local statusbar_build_log="$LOGS_DIR/statusbar-build.log"

    # Приоритет: локальная компиляция, если swiftc действительно доступен.
    # Проверяем реальный бинарник через xcode-select, чтобы не триггерить shim-диалог CLT.
    dev_dir=$(xcode-select -p 2>/dev/null || true)
    if [[ -n "$dev_dir" ]] && [[ -x "${dev_dir}/usr/bin/swiftc" ]]; then
        swiftc_bin="${dev_dir}/usr/bin/swiftc"
    elif pkgutil --pkg-info=com.apple.pkg.CLTools_Executables &>/dev/null && [[ -x "/usr/bin/swiftc" ]]; then
        swiftc_bin="/usr/bin/swiftc"
    fi

    if [[ -n "$swiftc_bin" ]]; then
        print_info "Найден swiftc, компиляция menu bar приложения..."
        mkdir -p "$LOGS_DIR"
        : > "$statusbar_build_log"
        local compile_ok=false
        if [[ -x "/usr/bin/xcrun" ]]; then
            if /usr/bin/xcrun swiftc -O -o "$binary_path" \
                -framework Cocoa \
                "$statusbar_dir/DostupVPN-StatusBar.swift" 2>"$statusbar_build_log"; then
                compile_ok=true
            fi
        else
            if "$swiftc_bin" -O -o "$binary_path" \
                -framework Cocoa \
                "$statusbar_dir/DostupVPN-StatusBar.swift" 2>"$statusbar_build_log"; then
                compile_ok=true
            fi
        fi
        if $compile_ok; then
            xattr -d com.apple.quarantine "$app_path" 2>/dev/null || true
            chmod +x "$binary_path"
            if verify_statusbar_app "$app_path"; then
                installed=true
                print_success "Menu bar приложение скомпилировано и запущено"
            else
                print_warning "Скомпилированное menu bar приложение не запустилось"
                rm -f "$binary_path"
            fi
        else
            print_warning "Не удалось скомпилировать menu bar приложение, попытка скачивания..."
            if [[ -s "$statusbar_build_log" ]]; then
                print_info "Лог компиляции: $statusbar_build_log"
                print_info "Ошибка: $(tail -n 2 "$statusbar_build_log" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
            fi
        fi
    else
        print_info "swiftc не найден, попытка скачать готовый бинарник..."
    fi

    if ! $installed; then
        print_info "Скачивание menu bar приложения..."
        if download_with_retry "$STATUSBAR_BIN_URL" "$binary_path"; then
            chmod +x "$binary_path"
            xattr -d com.apple.quarantine "$binary_path" 2>/dev/null || true
            xattr -d com.apple.quarantine "$app_path" 2>/dev/null || true
            if verify_statusbar_app "$app_path"; then
                installed=true
                print_success "Menu bar приложение скачано и запущено"
            else
                print_warning "Готовое menu bar приложение несовместимо с этой macOS"
                print_info "Лог запуска: $LOGS_DIR/statusbar-launch.log"
                rm -f "$binary_path"
            fi
        else
            print_warning "Не удалось скачать готовый бинарник menu bar приложения"
        fi
    fi

    # --- Результат ---
    if $installed; then
        create_launch_agent
        print_success "Menu bar приложение установлено"
    else
        print_warning "Menu bar приложение не установлено"
        print_info "VPN будет работать через приложение Dostup_VPN"
        disable_statusbar_app
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

# LaunchAgent планового обновления: профиль, geo-базы, ядро, проверка скрипта.
# Раз в 6 часов от пользователя. Для короткого перезапуска ядра используются
# только заранее разрешённые sudoers-команды без запроса пароля. Пропущенный
# из-за сна интервал launchd отработает при пробуждении.
create_updater_agent() {
    print_step "Настройка планового обновления (раз в 6 часов)..."

    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_path="$plist_dir/ru.dostup.vpn.updater.plist"
    local control_script="$DOSTUP_DIR/Dostup_VPN.command"

    mkdir -p "$plist_dir"

    cat > "$plist_path" << UPPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ru.dostup.vpn.updater</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${control_script}</string>
        <string>scheduled-update</string>
    </array>
    <key>StartInterval</key>
    <integer>21600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>LowPriorityIO</key>
    <true/>
    <key>Nice</key>
    <integer>5</integer>
</dict>
</plist>
UPPLIST

    launchctl unload "$plist_path" 2>/dev/null || true
    launchctl load "$plist_path" 2>/dev/null || true

    print_success "Плановое обновление настроено"
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

# Переданный аргумент проверяем и преобразуем ДО удаления старой установки:
# иначе кривая ссылка или имя снесёт рабочую конфигурацию и ничего не поставит.
if [[ -n "$SUB_URL_ARG" ]]; then
    ORIGINAL_SUB_URL_ARG="$SUB_URL_ARG"
    if ! SUB_URL_ARG="$(resolve_subscription_arg "$SUB_URL_ARG")"; then
        print_error "Неверная ссылка или короткое имя подписки:"
        echo "  $ORIGINAL_SUB_URL_ARG"
        echo "  Укажите полный URL либо имя из букв, цифр, _ и -"
        echo ""
        read -p "Нажмите Enter для закрытия..." < /dev/tty || true
        exit 1
    fi

    if ! validate_url "$SUB_URL_ARG"; then
        print_error "Не удалось сформировать URL подписки"
        echo ""
        read -p "Нажмите Enter для закрытия..." < /dev/tty || true
        exit 1
    fi
fi

# Сохраняем старую подписку если есть (файл может быть с правами root)
OLD_SUB_URL=""
if [[ -f "$SETTINGS_FILE" ]]; then
    OLD_SUB_URL=$(sudo sed -n 's/.*"subscription_url": *"\([^"]*\)".*/\1/p' "$SETTINGS_FILE" 2>/dev/null || true)
fi

# Остановка statusbar app и планировщика обновлений
launchctl unload "$HOME/Library/LaunchAgents/ru.dostup.vpn.statusbar.plist" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/ru.dostup.vpn.updater.plist" 2>/dev/null || true
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
        read -p "Нажмите Enter для закрытия..." < /dev/tty || true
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
    read -p "Нажмите Enter для закрытия..." < /dev/tty || true
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
    read -p "Нажмите Enter для закрытия..." < /dev/tty || true
    exit 1
fi

# Запрос URL подписки
print_step "Настройка подписки..."

if [[ -n "$SUB_URL_ARG" ]]; then
    # Подписка передана снаружи — ничего не спрашиваем.
    # Аргумент имеет приоритет над сохранённой: пользователю могли прислать новый профиль.
    SUB_URL="$SUB_URL_ARG"
    print_success "Подписка получена из параметра запуска"
elif [[ -n "$OLD_SUB_URL" ]]; then
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
    read -p "Нажмите Enter для закрытия..." < /dev/tty || true
    exit 1
fi

# Валидация URL
if ! validate_url "$SUB_URL"; then
    print_error "Неверный формат URL. URL должен начинаться с http:// или https://"
    read -p "Нажмите Enter для закрытия..." < /dev/tty || true
    exit 1
fi

update_settings "subscription_url" "$SUB_URL"

# Скачивание конфига
if ! download_config "$SUB_URL"; then
    print_error "Не удалось скачать конфиг"
    read -p "Нажмите Enter для закрытия..." < /dev/tty || true
    exit 1
fi

# Скачивание geo-баз и иконки
download_assets

# Финальная проверка связки ядра и профиля до создания/запуска сервиса.
print_step "Проверка профиля через Mihomo..."
if ! validate_mihomo_config "$MIHOMO_BIN" "$CONFIG_FILE"; then
    print_error "Mihomo отклонил профиль"
    echo "Рабочие файлы не будут запущены. Подробности: $LOGS_DIR/mihomo-validation.log"
    read -p "Нажмите Enter для закрытия..." < /dev/tty || true
    exit 1
fi
print_success "Ядро и профиль совместимы"

# Создание sites.json
create_sites_json

# Создание скрипта управления
print_step "Создание скрипта управления..."
create_control_script
print_success "Скрипт создан"

# Ярлыки на рабочем столе
create_desktop_shortcuts

# Menu bar приложение (компиляция, fallback на скачивание бинарника)
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

# Планировщик ставим последним: у него RunAtLoad, и первый прогон должен
# пройти уже при поднятом VPN, а не посреди установки.
create_updater_agent

echo ""
echo "Окно закроется через 5 секунд..."
sleep 5
(sleep 0.5 && osascript -e 'tell application "Terminal" to close front window saving no' &>/dev/null) &
exit 0
