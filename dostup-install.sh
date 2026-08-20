#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

DOSTUP_DIR="${DOSTUP_DIR:-/opt/dostup}"
CONFIG_FILE="$DOSTUP_DIR/config.yaml"
SETTINGS_FILE="$DOSTUP_DIR/settings.json"
MIHOMO_BIN="$DOSTUP_DIR/mihomo"
SITES_FILE="$DOSTUP_DIR/sites.json"
KNOWN_GOOD_DIR="$DOSTUP_DIR/.known-good"
CLI_PATH="${DOSTUP_CLI_PATH:-/usr/local/bin/dostup}"
SERVICE_FILE="${DOSTUP_SERVICE_FILE:-/etc/systemd/system/dostup.service}"
UPDATE_SERVICE_FILE="${DOSTUP_UPDATE_SERVICE_FILE:-/etc/systemd/system/dostup-update.service}"
UPDATE_TIMER_FILE="${DOSTUP_UPDATE_TIMER_FILE:-/etc/systemd/system/dostup-update.timer}"
LOCK_FILE="${DOSTUP_LOCK_FILE:-/run/dostup.lock}"

MIHOMO_RELEASES_API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GEO_RELEASES_API="https://api.github.com/repos/MetaCubeX/meta-rules-dat/releases/latest"
INSTALLER_RELEASES_API="https://api.github.com/repos/RichardMoor75/dostup_vpn/releases?per_page=30"
INSTALLER_RAW_URL="https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.sh"
INSTALLER_BUILD_VERSION="${DOSTUP_INSTALLER_VERSION:-dev}"

SUB_URL=""; PROXY_PORT=""; ACTIVE_STAGE=""; LOCK_FD=""
STAGED_INSTALLER_VERSION=""

MANAGED_FILES=(
  mihomo config.yaml settings.json dostup-manager.sh sites.json
  GeoIP.dat GeoSite.dat ASN.mmdb geoip.dat geosite.dat
  geoip.metadb country.mmdb cache.db
)
RESTART_RELEVANT_FILES=(
  mihomo config.yaml dostup-manager.sh GeoIP.dat GeoSite.dat ASN.mmdb
)

print_step()    { echo -e "${YELLOW}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

check_paths() {
  [[ "$DOSTUP_DIR" == /* && "$DOSTUP_DIR" != "/" ]] ||
    { print_error "Небезопасный путь установки: $DOSTUP_DIR"; return 1; }
}
check_root() {
  [[ $EUID -eq 0 ]] || {
    print_error "Этот скрипт должен быть запущен от root (sudo)"
    echo "Используйте: sudo bash $0"; exit 1
  }
}
require_root() {
  [[ $EUID -eq 0 ]] ||
    { print_error "Требуется root. Используйте: sudo dostup ${1:-}"; exit 1; }
}
check_os() {
  [[ -f /etc/os-release ]] || { print_error "Не удалось определить ОС"; exit 1; }
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != ubuntu && "${ID:-}" != debian &&
        "${ID_LIKE:-}" != *debian* && "${ID_LIKE:-}" != *ubuntu* ]]; then
    print_error "Поддерживаются только Ubuntu и Debian"
    print_info "Обнаружена ОС: ${PRETTY_NAME:-неизвестно}"; exit 1
  fi
  print_success "ОС: ${PRETTY_NAME:-$ID}"
}
install_lock_dependency() {
  command -v flock >/dev/null 2>&1 && return 0
  apt-get update -qq
  apt-get install -y -qq util-linux
}
acquire_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec {LOCK_FD}>"$LOCK_FILE"
  flock -n "$LOCK_FD" ||
    { print_error "Другая операция Dostup уже выполняется"; exit 75; }
}
install_dependencies() {
  print_step "Проверка зависимостей..."
  local command_name missing=false
  for command_name in curl jq gzip sha256sum flock ss; do
    command -v "$command_name" >/dev/null 2>&1 || { missing=true; break; }
  done
  if $missing; then
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl jq gzip coreutils util-linux iproute2
  fi
  print_success "Зависимости в порядке"
}
check_internet() {
  print_step "Проверка подключения к интернету..."
  local host
  for host in https://api.github.com https://raw.githubusercontent.com; do
    if curl -f -sS -4 --head --connect-timeout 5 --max-time 10 \
      --proto '=https' --proto-redir '=https' "$host" >/dev/null 2>&1; then
      print_success "Интернет доступен"; return 0
    fi
  done
  print_error "Нет подключения к интернету"; return 1
}
detect_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    *) print_error "Неподдерживаемая архитектура: $(uname -m)" >&2; return 1 ;;
  esac
}

is_private_ipv4() {
  local a b c d octet
  IFS=. read -r a b c d <<< "$1"
  [[ -n "${a:-}" && -n "${b:-}" && -n "${c:-}" && -n "${d:-}" ]] || return 1
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] && (( 10#$octet <= 255 )) || return 1
  done
  (( 10#$a == 10 || 10#$a == 127 ||
     (10#$a == 172 && 10#$b >= 16 && 10#$b <= 31) ||
     (10#$a == 192 && 10#$b == 168) ))
}
is_private_ipv6() {
  local host="${1,,}"
  [[ "$host" == "::1" || "$host" =~ ^f[cd][0-9a-f]{2}: ||
     "$host" =~ ^fe[89ab][0-9a-f]: ]]
}
extract_url_host() {
  local rest authority host suffix
  rest="${1#*://}"; authority="${rest%%[/?#]*}"
  [[ -n "$authority" && "$authority" != *"@"* ]] || return 1
  if [[ "$authority" == \[* ]]; then
    [[ "$authority" == *"]"* ]] || return 1
    host="${authority#\[}"; host="${host%%\]*}"; suffix="${authority#*\]}"
    [[ -z "$suffix" || "$suffix" =~ ^:[0-9]+$ ]] || return 1
  else
    [[ "${authority//[^:]}" != *"::"* ]] || return 1
    host="${authority%%:*}"; suffix="${authority#"$host"}"
    [[ -z "$suffix" || "$suffix" =~ ^:[0-9]+$ ]] || return 1
  fi
  [[ -n "$host" ]] && printf '%s\n' "$host"
}
validate_url() {
  local url="$1" host
  [[ -n "$url" && "$url" != *[$'\r\n\t ']* ]] || return 1
  case "$url" in
    https://*) host=$(extract_url_host "$url") && [[ -n "$host" ]] ;;
    http://*)
      host=$(extract_url_host "$url") || return 1
      host="${host,,}"
      [[ "$host" == localhost ]] || is_private_ipv4 "$host" || is_private_ipv6 "$host"
      ;;
    *) return 1 ;;
  esac
}

download_with_retry() {
  local url="$1" output="$2" retry=0
  local -a protocol_args
  if [[ "$url" == https://* ]]; then
    protocol_args=(--proto '=https' --proto-redir '=https' -L)
  elif [[ "$url" == http://* ]] && validate_url "$url"; then
    protocol_args=(--proto '=http')
  else
    return 1
  fi
  while (( retry < 3 )); do
    if curl -f -sS -4 --connect-timeout 10 --max-time 120 \
      "${protocol_args[@]}" -o "$output" "$url" 2>/dev/null && [[ -s "$output" ]]; then
      return 0
    fi
    retry=$((retry + 1)); print_info "Повтор скачивания ($retry/3)..."; sleep 2
  done
  return 1
}
verify_sha256_digest() {
  [[ "$2" =~ ^sha256:([a-fA-F0-9]{64})$ ]] || return 1
  local expected="${BASH_REMATCH[1],,}" actual
  actual=$(sha256sum "$1" | awk '{print $1}')
  [[ "$actual" == "$expected" ]]
}
download_verified_release_asset() {
  local json="$1" name="$2" output="$3" count url digest
  count=$(jq --arg n "$name" '[.assets[]? | select(.name == $n)] | length' "$json") ||
    return 1
  [[ "$count" == 1 ]] || return 1
  url=$(jq -r --arg n "$name" '.assets[] | select(.name == $n) |
    .browser_download_url' "$json")
  digest=$(jq -r --arg n "$name" '.assets[] | select(.name == $n) |
    .digest // empty' "$json")
  [[ "$url" == https://* && "$digest" =~ ^sha256:[a-fA-F0-9]{64}$ ]] || return 1
  download_with_retry "$url" "$output" || return 1
  verify_sha256_digest "$output" "$digest" || { rm -f "$output"; return 1; }
}
validate_yaml() {
  [[ -s "$1" ]] || return 1
  if head -c 1000 "$1" | grep -qiE '<!DOCTYPE|<html|<head'; then return 1; fi
  grep -qE '^[a-zA-Z_-]+:' "$1" && grep -qE '^mixed-port:' "$1"
}

check_port_free() {
  local port="$1" allowed="${2:-}"
  [[ -n "$allowed" && "$port" == "$allowed" ]] && return 0
  ! ss -H -tln 2>/dev/null | awk -v p="$port" \
    '$4 ~ (":" p "$") { f=1 } END { exit !f }'
}
find_free_port() {
  local port="$1" allowed="${2:-}"
  while ! check_port_free "$port" "$allowed"; do
    port=$((port + 1))
    (( port <= 65535 )) ||
      { print_error "Не удалось найти свободный порт" >&2; return 1; }
  done
  echo "$port"
}

# Инвариант: последовательность преобразований профиля не изменена.
process_config() {
  local config="$1" allowed="${2:-}" temp="${1}.processing"
  sed '/^external-ui:/d; /^external-ui-url:/d' "$config" > "$temp"
  awk 'BEGIN{s=0} /^tun:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' \
    "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"
  awk 'BEGIN{s=0} /^rule-providers:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' \
    "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"
  sed -i '/RULE-SET/d' "$temp"
  sed -i -E 's/^([[:space:]]*)- MATCH,(.*)/\1- MATCH,Auto Select/' "$temp"
  sed -i 's/listen: 0\.0\.0\.0:53/listen: 127.0.0.1:1053/' "$temp"
  sed -i -E "s/^(external-controller:[[:space:]]*)['\"]?0\.0\.0\.0:([0-9]+)['\"]?(.*)$/\1'127.0.0.1:\2'\3/" "$temp"
  local port desired=7890
  port=$(awk -F: '/^mixed-port:[[:space:]]*[0-9]+/ {
    v=$2; gsub(/[[:space:]]/, "", v); print v; exit }' "$temp")
  [[ -n "$port" ]] || port=7890
  if [[ "$port" != "$desired" ]]; then
    sed -i "s/mixed-port: $port/mixed-port: $desired/" "$temp"; port="$desired"
  fi
  if ! check_port_free "$port" "$allowed"; then
    local new_port
    new_port=$(find_free_port "$port" "$allowed")
    sed -i "s/mixed-port: $port/mixed-port: $new_port/" "$temp"
    print_warning "Порт $port занят, используется $new_port"; port="$new_port"
  fi
  mv "$temp" "$config"; PROXY_PORT="$port"
}
get_proxy_port_from() {
  local port
  port=$(awk -F: '/^mixed-port:[[:space:]]*[0-9]+/ {
    v=$2; gsub(/[[:space:]]/, "", v); print v; exit }' "$1" 2>/dev/null || true)
  echo "${port:-7890}"
}
get_proxy_port() { get_proxy_port_from "$CONFIG_FILE"; }

ensure_settings_file() {
  if [[ ! -s "$1" ]] || ! jq -e 'type == "object"' "$1" >/dev/null 2>&1; then
    printf '{}\n' > "$1"
  fi
  chmod 600 "$1"
}
settings_get_from() {
  [[ -f "$1" ]] && jq -r --arg k "$2" '.[$k] // ""' "$1" 2>/dev/null || true
}
read_settings() { settings_get_from "$SETTINGS_FILE" "$1"; }
settings_set_in() {
  local tmp="${1}.tmp"
  ensure_settings_file "$1"
  jq --arg k "$2" --arg v "$3" '.[$k] = $v' "$1" > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$1"
}

cleanup_active_stage() {
  if [[ -n "$ACTIVE_STAGE" && "$ACTIVE_STAGE" == "$DOSTUP_DIR"/.staging.* &&
        -d "$ACTIVE_STAGE" ]]; then rm -rf -- "$ACTIVE_STAGE"; fi
  ACTIVE_STAGE=""
}
create_stage() {
  mkdir -p "$DOSTUP_DIR"
  local stage
  stage=$(mktemp -d "$DOSTUP_DIR/.staging.XXXXXX")
  chmod 700 "$stage"; echo "$stage"
}
copy_if_present() {
  [[ -e "$1" ]] && cp -aL "$1" "$2"
  return 0
}
migrate_legacy_runtime() {
  local legacy="${DOSTUP_LEGACY_RUNTIME:-/root/.config/mihomo}" name dir
  [[ -d "$legacy" ]] || return 0
  print_step "Миграция runtime Mihomo в $DOSTUP_DIR..."
  for name in GeoIP.dat GeoSite.dat ASN.mmdb geoip.dat geosite.dat \
    geoip.metadb country.mmdb cache.db; do
    [[ -e "$legacy/$name" && ! -e "$DOSTUP_DIR/$name" ]] &&
      cp -aL "$legacy/$name" "$DOSTUP_DIR/$name"
  done
  for dir in proxies rules; do
    if [[ -d "$legacy/$dir" ]]; then
      mkdir -p "$DOSTUP_DIR/$dir"
      cp -a -n -L "$legacy/$dir/." "$DOSTUP_DIR/$dir/"
    fi
  done
  print_success "Runtime проверен; legacy-каталог оставлен без изменений"
}
seed_candidate() {
  local name
  for name in "${MANAGED_FILES[@]}"; do
    copy_if_present "$DOSTUP_DIR/$name" "$1/$name"
  done
  ensure_settings_file "$1/settings.json"
}

prepare_mihomo_candidate() {
  local stage="$1" json="$1/mihomo-release.json" has_current=false
  [[ -x "$stage/mihomo" ]] && has_current=true
  print_step "Проверка обновлений ядра Mihomo..."
  if ! download_with_retry "$MIHOMO_RELEASES_API" "$json" ||
     ! jq -e '.tag_name and (.assets | type == "array")' "$json" >/dev/null; then
    if $has_current; then
      print_warning "Релиз недоступен; остаётся текущее ядро"; return 0
    fi
    print_error "Не удалось получить релиз Mihomo"; return 1
  fi
  local version arch asset archive current
  version=$(jq -r .tag_name "$json"); arch=$(detect_arch) || return 1
  if [[ "$arch" == amd64 ]]; then
    asset="mihomo-linux-amd64-v1-${version}.gz"
  else
    asset="mihomo-linux-arm64-${version}.gz"
  fi
  current=$(settings_get_from "$stage/settings.json" installed_version)
  if $has_current && [[ "$current" == "$version" ]]; then
    print_success "Ядро актуально ($version)"; return 0
  fi
  archive="$stage/$asset"; print_step "Скачивание и проверка Mihomo $version..."
  if ! download_verified_release_asset "$json" "$asset" "$archive"; then
    if $has_current; then
      print_warning "Новое ядро не прошло проверку; остаётся текущее"; return 0
    fi
    print_error "Ядро не прошло обязательную SHA256-проверку"; return 1
  fi
  gzip -t "$archive" 2>/dev/null ||
    { rm -f "$archive"; print_error "Архив Mihomo повреждён"; return 1; }
  gzip -dc "$archive" > "$stage/mihomo.new"
  chmod 755 "$stage/mihomo.new"; mv "$stage/mihomo.new" "$stage/mihomo"; rm -f "$archive"
  settings_set_in "$stage/settings.json" installed_version "$version"
  print_success "Mihomo $version подготовлен"
}

prepare_profile_candidate() {
  local stage="$1" url="$2" has_current=false raw allowed=""
  [[ -s "$stage/config.yaml" ]] && has_current=true
  if [[ -z "$url" ]] || ! validate_url "$url"; then
    if $has_current; then
      print_warning "URL подписки не принят; профиль не изменён"
      PROXY_PORT=$(get_proxy_port_from "$stage/config.yaml"); return 0
    fi
    print_error "Публичная подписка должна использовать HTTPS"; return 1
  fi
  print_step "Скачивание профиля..."; raw="$stage/config.download"
  if ! download_with_retry "$url" "$raw" || ! validate_yaml "$raw"; then
    rm -f "$raw"
    if $has_current; then
      print_warning "Новый профиль недоступен или повреждён; остаётся текущий"
      PROXY_PORT=$(get_proxy_port_from "$stage/config.yaml"); return 0
    fi
    print_error "Не удалось получить корректный профиль"; return 1
  fi
  mv "$raw" "$stage/config.yaml"
  if systemctl is-active --quiet dostup 2>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    allowed=$(get_proxy_port)
  fi
  process_config "$stage/config.yaml" "$allowed"
  settings_set_in "$stage/settings.json" subscription_url "$url"
  settings_set_in "$stage/settings.json" proxy_port "$PROXY_PORT"
  print_success "Профиль подготовлен (порт: $PROXY_PORT)"
}

geo_update_due() {
  local last ts now
  last=$(settings_get_from "$1" last_geo_update)
  [[ -n "$last" ]] || return 0
  ts=$(date -d "$last" +%s 2>/dev/null || echo 0); now=$(date +%s)
  (( (now - ts) / 86400 >= 14 ))
}
prepare_geo_candidate() {
  local stage="$1" json="$1/geo-release.json" tmp="$1/geo-downloads"
  geo_update_due "$stage/settings.json" || return 0
  print_step "Скачивание и проверка GeoIP, GeoSite и ASN..."
  if ! download_with_retry "$GEO_RELEASES_API" "$json" ||
     ! jq -e '.assets | type == "array"' "$json" >/dev/null; then
    print_warning "Geo-базы недоступны; сохраняются текущие"; return 0
  fi
  mkdir -p "$tmp"
  if download_verified_release_asset "$json" geoip.dat "$tmp/GeoIP.dat" &&
     download_verified_release_asset "$json" geosite.dat "$tmp/GeoSite.dat" &&
     download_verified_release_asset "$json" GeoLite2-ASN.mmdb "$tmp/ASN.mmdb"; then
    mv "$tmp/GeoIP.dat" "$stage/GeoIP.dat"
    mv "$tmp/GeoSite.dat" "$stage/GeoSite.dat"
    mv "$tmp/ASN.mmdb" "$stage/ASN.mmdb"
    settings_set_in "$stage/settings.json" last_geo_update "$(date +%Y-%m-%d)"
    print_success "Geo-базы проверены"
  else
    print_warning "Geo-базы не прошли полную SHA256-проверку; сохраняются текущие"
  fi
  rm -rf "$tmp"
}

prepare_runtime_for_test() {
  local stage="$1" runtime="$1/runtime" name dir
  mkdir -p "$runtime"
  for name in GeoIP.dat GeoSite.dat ASN.mmdb geoip.dat geosite.dat \
    geoip.metadb country.mmdb cache.db; do
    copy_if_present "$stage/$name" "$runtime/$name"
  done
  for dir in proxies rules; do
    [[ -d "$DOSTUP_DIR/$dir" ]] && cp -aL "$DOSTUP_DIR/$dir" "$runtime/$dir"
  done
  return 0
}
validate_candidate_with_mihomo() {
  local stage="$1"
  [[ -x "$stage/mihomo" && -s "$stage/config.yaml" ]] ||
    { print_error "Кандидат неполный: нет ядра или профиля"; return 1; }
  prepare_runtime_for_test "$stage"; print_step "Проверка через mihomo -t..."
  if ! "$stage/mihomo" -t -d "$stage/runtime" -f "$stage/config.yaml" \
    >"$stage/mihomo-test.log" 2>&1; then
    print_error "Mihomo отклонил профиль; текущая установка не изменена"
    tail -n 20 "$stage/mihomo-test.log" >&2 || true; return 1
  fi
  copy_if_present "$stage/runtime/cache.db" "$stage/cache.db"
  print_success "Ядро и профиль совместимы"
}

extract_installer_release() {
  local tag
  tag=$(jq -r '[.[] | select(.draft == false and .prerelease == false and
    (.tag_name | startswith("installer-v")))][0].tag_name // empty' "$1") || return 1
  [[ -n "$tag" ]] || return 1
  jq --arg t "$tag" '[.[] | select(.tag_name == $t)][0]' "$1" > "$2"
  STAGED_INSTALLER_VERSION="$tag"
}
prepare_manager_candidate() {
  local stage="$1" list="$1/installer-releases.json" release="$1/installer-release.json"
  local current source="${BASH_SOURCE[0]}"
  current=$(settings_get_from "$stage/settings.json" installer_version)
  if download_with_retry "$INSTALLER_RELEASES_API" "$list" &&
     extract_installer_release "$list" "$release"; then
    if [[ "$current" != "$STAGED_INSTALLER_VERSION" ||
          ! -s "$stage/dostup-manager.sh" ]]; then
      if download_verified_release_asset "$release" dostup-install.sh "$stage/manager.new" &&
         bash -n "$stage/manager.new"; then
        chmod 755 "$stage/manager.new"
        mv "$stage/manager.new" "$stage/dostup-manager.sh"
        settings_set_in "$stage/settings.json" installer_version "$STAGED_INSTALLER_VERSION"
        print_success "Установщик $STAGED_INSTALLER_VERSION проверен по release digest"
        return 0
      fi
      rm -f "$stage/manager.new"; print_warning "Релиз установщика отклонён"
    else
      return 0
    fi
  fi
  if [[ -f "$source" && -r "$source" ]] && bash -n "$source"; then
    cp "$source" "$stage/dostup-manager.sh"; chmod 755 "$stage/dostup-manager.sh"
    settings_set_in "$stage/settings.json" installer_version \
      "${current:-$INSTALLER_BUILD_VERSION}"
    return 0
  fi
  [[ -s "$stage/dostup-manager.sh" ]] && return 0
  # Временная ветка до публикации первого installer-v release.
  print_warning "Installer release ещё не опубликован; используется dev bootstrap"
  if download_with_retry "$INSTALLER_RAW_URL" "$stage/manager.new" &&
     bash -n "$stage/manager.new"; then
    chmod 755 "$stage/manager.new"; mv "$stage/manager.new" "$stage/dostup-manager.sh"
    settings_set_in "$stage/settings.json" installer_version dev-unverified
    return 0
  fi
  print_error "Не удалось подготовить менеджер Dostup"; return 1
}

create_sites_candidate() {
  [[ -s "$1/sites.json" ]] && return 0
  cat > "$1/sites.json" <<'EOF'
{"sites":["instagram.com","youtube.com","facebook.com","rutracker.org","hdrezka.ag","flibusta.is"]}
EOF
}
render_service_candidate() {
  cat > "$1" <<'EOF'
[Unit]
Description=Dostup VPN (Mihomo)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/dostup/mihomo -d /opt/dostup -f /opt/dostup/config.yaml
Restart=on-failure
RestartSec=3
User=root
LimitNOFILE=65535
WorkingDirectory=/opt/dostup

[Install]
WantedBy=multi-user.target
EOF
}
render_update_service_candidate() {
  cat > "$1" <<'EOF'
[Unit]
Description=Dostup VPN background update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/dostup/dostup-manager.sh --cli update-background
User=root
WorkingDirectory=/opt/dostup
Environment=DEBIAN_FRONTEND=noninteractive
StandardInput=null
TimeoutStartSec=30min
EOF
}
render_update_timer_candidate() {
  cat > "$1" <<'EOF'
[Unit]
Description=Dostup VPN background update schedule

[Timer]
OnCalendar=Mon,Thu *-*-* 04:00:00
RandomizedDelaySec=30m
Persistent=true
Unit=dostup-update.service

[Install]
WantedBy=timers.target
EOF
}
render_cli_candidate() {
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
exec /opt/dostup/dostup-manager.sh --cli "$@"
EOF
  chmod 755 "$1"
}
render_installation_candidates() {
  render_service_candidate "$1/service"
  render_update_service_candidate "$1/update-service"
  render_update_timer_candidate "$1/update-timer"
  render_cli_candidate "$1/cli"
}

file_state_matches() {
  if [[ -e "$1" && -e "$2" ]]; then
    cmp -s "$1" "$2"
  else
    [[ ! -e "$1" && ! -e "$2" ]]
  fi
}
candidate_requires_restart() {
  local stage="$1" name
  for name in "${RESTART_RELEVANT_FILES[@]}"; do
    file_state_matches "$stage/$name" "$DOSTUP_DIR/$name" || return 0
  done
  file_state_matches "$stage/service" "$SERVICE_FILE" || return 0
  file_state_matches "$stage/update-service" "$UPDATE_SERVICE_FILE" || return 0
  file_state_matches "$stage/update-timer" "$UPDATE_TIMER_FILE" || return 0
  return 1
}

snapshot_live_files() {
  mkdir -p "$1"; : > "$1/manifest"; local name
  for name in "${MANAGED_FILES[@]}"; do
    if [[ -e "$DOSTUP_DIR/$name" ]]; then
      cp -aL "$DOSTUP_DIR/$name" "$1/$name"
      printf '%s\n' "$name" >> "$1/manifest"
    fi
  done
}
mode_for_file() {
  case "$1" in
    mihomo|dostup-manager.sh) echo 755 ;;
    settings.json) echo 600 ;;
    config.yaml) echo 644 ;;
    *) echo 644 ;;
  esac
}
install_file_atomically() {
  local tmp="${2}.new.$$"
  install -m "$3" "$1" "$tmp"; mv -f "$tmp" "$2"
}
restore_optional_file() {
  if [[ -f "$1" ]]; then
    install_file_atomically "$1" "$2" "$3"
  else
    rm -f "$2"
  fi
}
restore_live_files() {
  local name mode
  for name in "${MANAGED_FILES[@]}"; do
    if grep -Fxq "$name" "$1/manifest" 2>/dev/null; then
      mode=$(mode_for_file "$name")
      install_file_atomically "$1/$name" "$DOSTUP_DIR/$name" "$mode"
    else
      rm -f "$DOSTUP_DIR/$name"
    fi
  done
}
publish_known_good() {
  local old="$DOSTUP_DIR/.known-good.previous.$$"
  rm -rf "$old"
  [[ -d "$KNOWN_GOOD_DIR" ]] && mv "$KNOWN_GOOD_DIR" "$old"
  if mv "$1" "$KNOWN_GOOD_DIR"; then rm -rf "$old"; return 0; fi
  [[ -d "$old" ]] && mv "$old" "$KNOWN_GOOD_DIR"
  return 1
}
get_external_controller() {
  local value
  value=$(awk '/^external-controller:[[:space:]]+/ {
    sub(/^[^:]+:[[:space:]]+/, ""); gsub(/['\''"]/, ""); print; exit }' "$1" ||
    true)
  case "$value" in
    0.0.0.0:*) echo "127.0.0.1:${value##*:}" ;;
    127.0.0.1:*|localhost:*) echo "$value" ;;
    *) echo "" ;;
  esac
}
listener_owned_by_service() {
  local pid
  pid=$(systemctl show dostup -p MainPID --value 2>/dev/null || true)
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  ss -H -ltnp 2>/dev/null | awk -v p="$1" -v n="pid=$pid," \
    '$4 ~ (":" p "$") && index($0,n) { f=1 } END { exit !f }'
}
hard_healthcheck() {
  local port controller attempt
  port=$(get_proxy_port); controller=$(get_external_controller "$CONFIG_FILE")
  for attempt in {1..12}; do
    if systemctl is-active --quiet dostup && listener_owned_by_service "$port"; then
      if [[ -z "$controller" ]] || curl -sS --connect-timeout 2 --max-time 3 \
        -o /dev/null "http://$controller/version" 2>/dev/null; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}
soft_post_update_check() {
  local port
  port=$(get_proxy_port)
  curl -x "http://127.0.0.1:$port" -sS -o /dev/null --connect-timeout 5 \
    --max-time 10 https://www.gstatic.com/generate_204 2>/dev/null || {
      print_warning "Сервис исправен, но внешняя проверка через прокси не прошла"
      print_info "Rollback не выполняется; проверьте ноды: dostup healthcheck"
    }
}
merge_runtime_cache() {
  local dir
  for dir in proxies rules; do
    if [[ -d "$1/$dir" ]]; then
      mkdir -p "$DOSTUP_DIR/$dir"
      cp -aL "$1/$dir/." "$DOSTUP_DIR/$dir/"
    fi
  done
}

commit_nondisruptive_files() {
  local stage="$1" name mode
  for name in settings.json sites.json; do
    if [[ -e "$stage/$name" ]] &&
       ! file_state_matches "$stage/$name" "$DOSTUP_DIR/$name"; then
      mode=$(mode_for_file "$name")
      install_file_atomically "$stage/$name" "$DOSTUP_DIR/$name" "$mode"
    fi
  done
  if ! file_state_matches "$stage/cli" "$CLI_PATH"; then
    install_file_atomically "$stage/cli" "$CLI_PATH" 755
  fi
}

commit_candidate() {
  local stage="$1" had_previous=false was_active=false
  local timer_was_active=false timer_was_enabled=false name mode
  render_installation_candidates "$stage"
  [[ -x "$MIHOMO_BIN" && -s "$CONFIG_FILE" ]] && had_previous=true
  systemctl is-active --quiet dostup 2>/dev/null && was_active=true
  systemctl is-active --quiet dostup-update.timer 2>/dev/null &&
    timer_was_active=true
  systemctl is-enabled --quiet dostup-update.timer 2>/dev/null &&
    timer_was_enabled=true
  mkdir -p "$stage/previous"; snapshot_live_files "$stage/previous/live"
  [[ -f "$SERVICE_FILE" ]] && cp -aL "$SERVICE_FILE" "$stage/previous/service"
  [[ -f "$UPDATE_SERVICE_FILE" ]] &&
    cp -aL "$UPDATE_SERVICE_FILE" "$stage/previous/update-service"
  [[ -f "$UPDATE_TIMER_FILE" ]] &&
    cp -aL "$UPDATE_TIMER_FILE" "$stage/previous/update-timer"
  [[ -f "$CLI_PATH" ]] && cp -aL "$CLI_PATH" "$stage/previous/cli"

  print_step "Короткая остановка для атомарной подмены..."
  systemctl stop dostup 2>/dev/null || true
  for name in "${MANAGED_FILES[@]}"; do
    if [[ -e "$stage/$name" ]]; then
      mode=$(mode_for_file "$name")
      install_file_atomically "$stage/$name" "$DOSTUP_DIR/$name" "$mode"
    fi
  done
  merge_runtime_cache "$stage/runtime"
  install_file_atomically "$stage/service" "$SERVICE_FILE" 644
  install_file_atomically "$stage/update-service" "$UPDATE_SERVICE_FILE" 644
  install_file_atomically "$stage/update-timer" "$UPDATE_TIMER_FILE" 644
  install_file_atomically "$stage/cli" "$CLI_PATH" 755
  if ! systemctl daemon-reload ||
     ! systemctl enable dostup >/dev/null 2>&1 ||
     ! systemctl enable dostup-update.timer >/dev/null 2>&1 ||
     ! systemctl start dostup ||
     ! hard_healthcheck ||
     ! systemctl start dostup-update.timer; then
    print_error "Новая версия локально неисправна; выполняется rollback"
    systemctl stop dostup 2>/dev/null || true
    if ! $had_previous; then
      systemctl disable dostup >/dev/null 2>&1 || true
    fi
    if ! $timer_was_enabled; then
      systemctl disable --now dostup-update.timer >/dev/null 2>&1 || true
    elif ! $timer_was_active; then
      systemctl stop dostup-update.timer 2>/dev/null || true
    fi
    restore_live_files "$stage/previous/live"
    restore_optional_file "$stage/previous/service" "$SERVICE_FILE" 644
    restore_optional_file "$stage/previous/update-service" \
      "$UPDATE_SERVICE_FILE" 644
    restore_optional_file "$stage/previous/update-timer" "$UPDATE_TIMER_FILE" 644
    restore_optional_file "$stage/previous/cli" "$CLI_PATH" 755
    systemctl daemon-reload
    if $timer_was_enabled; then
      systemctl enable dostup-update.timer >/dev/null 2>&1 || true
    else
      systemctl disable dostup-update.timer >/dev/null 2>&1 || true
    fi
    if $timer_was_active; then
      systemctl start dostup-update.timer 2>/dev/null || true
    else
      systemctl stop dostup-update.timer 2>/dev/null || true
    fi
    if $was_active; then
      systemctl start dostup
      if hard_healthcheck; then
        print_success "Предыдущая версия восстановлена"
      else
        print_error "Предыдущая версия восстановлена, но сервис не запустился"
      fi
    elif ! $had_previous; then
      systemctl disable dostup >/dev/null 2>&1 || true
    fi
    return 1
  fi

  if $had_previous && ! publish_known_good "$stage/previous/live"; then
    print_warning "Не удалось обновить known-good резерв"
  fi
  print_success "Новая версия запущена и прошла локальную проверку"
  soft_post_update_check
}
prepare_and_commit() {
  local stage mode="${2:-manual}"
  stage=$(create_stage); ACTIVE_STAGE="$stage"
  seed_candidate "$stage"
  prepare_mihomo_candidate "$stage" || return 1
  prepare_profile_candidate "$stage" "$1" || return 1
  prepare_geo_candidate "$stage"
  prepare_manager_candidate "$stage" || return 1
  create_sites_candidate "$stage"
  render_installation_candidates "$stage"
  validate_candidate_with_mihomo "$stage" || return 1
  if [[ "$mode" == background ]] && ! candidate_requires_restart "$stage"; then
    commit_nondisruptive_files "$stage"
    rm -rf "$stage"; ACTIVE_STAGE=""
    print_success "Значимых обновлений нет; перезапуск не требуется"
    return 0
  fi
  commit_candidate "$stage" || return 1
  rm -rf "$stage"; ACTIVE_STAGE=""
}

ask_subscription_url() {
  local choice
  if [[ -n "$1" ]]; then
    print_info "Найдена предыдущая подписка"
    echo; echo "1) Оставить текущую подписку"; echo "2) Ввести новую подписку"; echo
    read -r -p "Выберите (1 или 2): " choice
    if [[ "$choice" == 2 ]]; then
      read -r -p "Введите URL подписки (конфига): " SUB_URL
    else
      SUB_URL="$1"; print_success "Используется предыдущая подписка"
    fi
  else
    read -r -p "Введите URL подписки (конфига): " SUB_URL
  fi
}
show_result() {
  echo; echo -e "${GREEN}════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✓ Dostup VPN установлен и запущен${NC}"
  echo -e "${GREEN}════════════════════════════════════════════${NC}"; echo
  echo "  Прокси:        http://127.0.0.1:$1"
  echo "  Статус:        sudo dostup status"
  echo "  Управление:    sudo dostup start|stop|restart"
  echo "  Откат:         sudo dostup rollback"
  echo "  Автообновление: понедельник и четверг около 04:00"
  echo "  Проверка:      dostup check"
  echo "  Логи:          dostup log"; echo
}
installer_main() {
  echo; echo -e "${BLUE}============================================${NC}"
  echo -e "${BLUE}       Dostup Installer for Mihomo${NC}"
  echo -e "${BLUE}         Linux (Ubuntu / Debian)${NC}"
  echo -e "${BLUE}============================================${NC}"; echo
  check_paths; check_root; check_os
  install_lock_dependency; acquire_lock; install_dependencies; check_internet
  mkdir -p "$DOSTUP_DIR"; chmod 755 "$DOSTUP_DIR"; migrate_legacy_runtime
  local old=""
  command -v jq >/dev/null 2>&1 && old=$(read_settings subscription_url)
  print_step "Настройка подписки..."; ask_subscription_url "$old"
  [[ -n "$SUB_URL" || -s "$CONFIG_FILE" ]] ||
    { print_error "URL подписки не указан"; return 1; }
  prepare_and_commit "$SUB_URL"
  show_result "$(get_proxy_port)"
}

do_start() {
  require_root start; acquire_lock
  systemctl is-active --quiet dostup &&
    { print_info "Dostup уже запущен"; return 0; }
  systemctl start dostup
  if hard_healthcheck; then
    print_success "Dostup запущен (http://127.0.0.1:$(get_proxy_port))"
  else
    print_error "Не удалось запустить Dostup"; return 1
  fi
}
do_stop() {
  require_root stop; acquire_lock
  systemctl is-active --quiet dostup ||
    { print_info "Dostup уже остановлен"; return 0; }
  systemctl stop dostup; print_success "Dostup остановлен"
}
do_update() {
  require_root update; acquire_lock; install_dependencies; migrate_legacy_runtime
  prepare_and_commit "$(read_settings subscription_url)"
  print_success "Обновление завершено"
}
do_background_update() {
  require_root update-background; acquire_lock
  export DEBIAN_FRONTEND=noninteractive
  install_dependencies; migrate_legacy_runtime
  prepare_and_commit "$(read_settings subscription_url)" background
  print_success "Фоновое обновление завершено"
}
do_status() {
  echo
  if systemctl is-active --quiet dostup; then
    echo -e "${GREEN}● Dostup VPN — активен${NC}"; echo
    echo "  Прокси:       http://127.0.0.1:$(get_proxy_port)"
    echo "  Mihomo:       $(read_settings installed_version)"
    echo "  Установщик:   $(read_settings installer_version)"
    echo "  PID:          $(systemctl show dostup -p MainPID --value)"
    echo "  Запущен:      $(systemctl show dostup -p ActiveEnterTimestamp --value)"
  else
    echo -e "${RED}● Dostup VPN — остановлен${NC}"
  fi
  echo
}
do_check() {
  systemctl is-active --quiet dostup ||
    { print_error "Dostup не запущен"; return 1; }
  [[ -f "$SITES_FILE" ]] || { print_error "Файл sites.json не найден"; return 1; }
  local port proxy site code
  port=$(get_proxy_port); proxy="http://127.0.0.1:$port"
  while IFS= read -r site; do
    code=$(curl -x "$proxy" -s -o /dev/null -w "%{http_code}" --max-time 5 \
      "https://$site" 2>/dev/null || echo 000)
    if [[ "$code" -ge 200 && "$code" -lt 400 ]]; then
      echo -e "  ${GREEN}✓ $site — доступен ($code)${NC}"
    else
      echo -e "  ${RED}✗ $site — недоступен ($code)${NC}"
    fi
  done < <(jq -r '.sites[]' "$SITES_FILE")
}
controller_api_url() {
  local controller
  controller=$(get_external_controller "$CONFIG_FILE")
  [[ -n "$controller" ]] && echo "http://$controller"
}
urlencode() { jq -nr --arg v "$1" '$v | @uri'; }
do_update_providers() {
  require_root update-providers; acquire_lock
  systemctl is-active --quiet dostup || { print_error "Dostup не запущен"; return 1; }
  local api providers name encoded
  api=$(controller_api_url) || { print_error "Локальный API не настроен"; return 1; }
  providers=$(curl -sS --max-time 5 "$api/providers/proxies" |
    jq -r '.providers | keys[] | select(. != "default")' 2>/dev/null || true)
  [[ -n "$providers" ]] || { print_error "Нет прокси-провайдеров"; return 1; }
  while IFS= read -r name; do
    encoded=$(urlencode "$name")
    if curl -sS -X PUT --max-time 15 \
      "$api/providers/proxies/$encoded" >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓ Прокси: $name${NC}"
    else
      echo -e "  ${RED}✗ Прокси: $name${NC}"
    fi
  done <<< "$providers"
}
do_healthcheck() {
  systemctl is-active --quiet dostup || { print_error "Dostup не запущен"; return 1; }
  local api providers name encoded details
  api=$(controller_api_url) || { print_error "Локальный API не настроен"; return 1; }
  providers=$(curl -sS --max-time 5 "$api/providers/proxies" |
    jq -r '.providers | keys[] | select(. != "default")' 2>/dev/null || true)
  while IFS= read -r name; do
    encoded=$(urlencode "$name")
    curl -sS --max-time 30 "$api/providers/proxies/$encoded/healthcheck" \
      >/dev/null 2>&1 || true
    echo -e "${BLUE}[$name]${NC}"
    details=$(curl -sS --max-time 5 "$api/providers/proxies/$encoded" || true)
    jq -r '.proxies[]? | "\(.name)\t\(.history[-1].delay // 0)"' <<< "$details" |
      while IFS=$'\t' read -r node delay; do
        if [[ "$delay" -gt 0 ]] 2>/dev/null; then
          echo -e "  ${GREEN}✓ $node — ${delay}ms${NC}"
        else
          echo -e "  ${RED}✗ $node — dead${NC}"
        fi
      done
  done <<< "$providers"
}
do_rollback() {
  require_root rollback; acquire_lock
  [[ -f "$KNOWN_GOOD_DIR/manifest" ]] ||
    { print_error "Known-good резерв ещё не создан"; return 1; }
  local stage current
  stage=$(create_stage); ACTIVE_STAGE="$stage"; current="$stage/current"
  snapshot_live_files "$current"
  systemctl stop dostup 2>/dev/null || true
  restore_live_files "$KNOWN_GOOD_DIR"; systemctl start dostup
  if ! hard_healthcheck; then
    print_error "Резерв неисправен; возвращается текущая версия"
    systemctl stop dostup 2>/dev/null || true
    restore_live_files "$current"; systemctl start dostup
    hard_healthcheck || true; return 1
  fi
  publish_known_good "$current" || print_warning "Не сохранён обратный резерв"
  rm -rf "$stage"; ACTIVE_STAGE=""; print_success "Откат выполнен"
}
do_log() { journalctl -u dostup -n 50 -f; }
do_uninstall() {
  require_root uninstall; acquire_lock
  local answer
  read -r -p "Удалить Dostup VPN? (y/N): " answer
  [[ "$answer" == y || "$answer" == Y ]] || { echo "Отменено"; return 0; }
  systemctl disable --now dostup-update.timer 2>/dev/null || true
  systemctl stop dostup-update.service 2>/dev/null || true
  systemctl clean --what=state dostup-update.timer 2>/dev/null || true
  systemctl stop dostup 2>/dev/null || true
  systemctl disable dostup 2>/dev/null || true
  rm -f "$SERVICE_FILE" "$UPDATE_SERVICE_FILE" "$UPDATE_TIMER_FILE"
  systemctl daemon-reload
  rm -rf "$DOSTUP_DIR"; rm -f "$CLI_PATH"
  print_success "Dostup VPN полностью удалён"
}
do_help() {
  echo "Dostup VPN — sudo dostup <команда>"
  echo "start | stop | restart | update | rollback | status | check"
  echo "update-providers | healthcheck | log | uninstall | help"
}
cli_main() {
  case "${1:-help}" in
    start) do_start ;;
    stop) do_stop ;;
    restart|update) do_update ;;
    update-background) do_background_update ;;
    rollback) do_rollback ;;
    status) do_status ;;
    check) do_check ;;
    update-providers) do_update_providers ;;
    healthcheck) do_healthcheck ;;
    log) do_log ;;
    uninstall) do_uninstall ;;
    help|-h|--help) do_help ;;
    *) print_error "Неизвестная команда: $1"; do_help; return 1 ;;
  esac
}
main() {
  trap cleanup_active_stage EXIT
  check_paths
  if [[ "${1:-}" == --cli ]]; then shift; cli_main "$@"; else installer_main "$@"; fi
}
[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"
