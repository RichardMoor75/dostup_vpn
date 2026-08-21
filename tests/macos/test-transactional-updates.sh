#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
INSTALLER="$PROJECT_DIR/dostup-install.command"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

CONTROL_SCRIPT="$(sed -n \
    "/cat > \"\$DOSTUP_DIR\/Dostup_VPN.command\" << 'CONTROLSCRIPT'$/,/^CONTROLSCRIPT$/p" \
    "$INSTALLER" | sed '1d;$d')"
CONTROL_PREFIX="$(printf '%s\n' "$CONTROL_SCRIPT" | sed '/^# === MAIN ===/,$d')"
[[ -n "$CONTROL_PREFIX" ]] || fail "не удалось извлечь управляющий скрипт"
eval "$CONTROL_PREFIX"

DOSTUP_DIR="$TEST_TMP/dostup"
SETTINGS_FILE="$DOSTUP_DIR/settings.json"
MIHOMO_BIN="$DOSTUP_DIR/mihomo"
CONFIG_FILE="$DOSTUP_DIR/config.yaml"
UPDATER_LOG="$DOSTUP_DIR/logs/updater.log"
CORE_PENDING="$DOSTUP_DIR/mihomo.new"
CORE_BACKUP="$DOSTUP_DIR/mihomo.backup"
MOCK_RUNNING_FILE="$TEST_TMP/running"
MOCK_PROFILE_SOURCE="$TEST_TMP/profile-download.yaml"
export MOCK_RUNNING_FILE
mkdir -p "$DOSTUP_DIR/logs" "$TEST_TMP/bin"
printf '0\n' > "$MOCK_RUNNING_FILE"

cat > "$TEST_TMP/bin/pgrep" <<'EOF'
#!/bin/bash
[[ "$(cat "$MOCK_RUNNING_FILE" 2>/dev/null)" == "1" ]]
EOF
chmod +x "$TEST_TMP/bin/pgrep"
PATH="$TEST_TMP/bin:$PATH"
export PATH

xattr() { return 0; }
download_with_retry() { cp "$MOCK_PROFILE_SOURCE" "$2"; }

create_fake_core() {
    local path="$1" marker="$2"
    cat > "$path" <<EOF
#!/bin/bash
# $marker
config=""
while [[ \$# -gt 0 ]]; do
    if [[ \$1 == "-f" ]]; then config=\$2; shift 2; else shift; fi
done
[[ -n "\$config" ]] || exit 1
grep -q 'REJECT_BY_MIHOMO' "\$config" && exit 1
exit 0
EOF
    chmod +x "$path"
}

create_fake_core "$MIHOMO_BIN" "old-core"
cat > "$SETTINGS_FILE" <<'EOF'
{
  "subscription_url": "https://example.test/profile.yaml",
  "installed_version": "v-old",
  "pending_core_version": ""
}
EOF
cat > "$CONFIG_FILE" <<'EOF'
mixed-port: 7890
external-controller: '127.0.0.1:9090'
proxies: []
EOF

# Кандидат проходит поверхностную YAML-проверку, но отвергается Mihomo.
cat > "$MOCK_PROFILE_SOURCE" <<'EOF'
mixed-port: 7890
external-controller: 0.0.0.0:9090
proxies: REJECT_BY_MIHOMO
EOF
old_hash="$(shasum -a 256 "$CONFIG_FILE" | awk '{print $1}')"
if update_profile; then
    fail "профиль, отвергнутый Mihomo, был принят"
else
    result=$?
    [[ "$result" -eq 2 ]] || fail "неверный код отказа профиля: $result"
fi
new_hash="$(shasum -a 256 "$CONFIG_FILE" | awk '{print $1}')"
[[ "$old_hash" == "$new_hash" ]] || fail "рабочий профиль изменён после отказа"

# Валидный профиль меняется только точечно и принимается без запуска VPN.
cat > "$MOCK_PROFILE_SOURCE" <<'EOF'
mixed-port: 7890
external-controller: 0.0.0.0:9090
proxies: []
rules:
  - MATCH,DIRECT
EOF
update_profile || fail "валидный профиль не принят"
grep -q "^external-controller: '127.0.0.1:9090'$" "$CONFIG_FILE" || \
    fail "порт управления не привязан к loopback"
grep -q '^  - MATCH,DIRECT$' "$CONFIG_FILE" || \
    fail "профиль был преобразован по правилам Linux"

# При остановленном VPN проверенное ядро применяется, но VPN не запускается.
create_fake_core "$MIHOMO_BIN" "old-core"
create_fake_core "$CORE_PENDING" "new-core"
update_settings "installed_version" "v-old"
update_settings "pending_core_version" "v-new"
printf '0\n' > "$MOCK_RUNNING_FILE"
apply_pending_core || fail "проверенное ядро не применено"
grep -q 'new-core' "$MIHOMO_BIN" || fail "новое ядро не установлено"
[[ "$(cat "$MOCK_RUNNING_FILE")" == "0" ]] || fail "остановленный VPN был запущен"
[[ "$(read_settings installed_version)" == "v-new" ]] || fail "версия ядра не обновлена"
[[ ! -e "$CORE_BACKUP" ]] || fail "резерв ядра не очищен после успеха"

# Работающий VPN сразу перезапускается на проверенном ядре.
create_fake_core "$MIHOMO_BIN" "old-core"
create_fake_core "$CORE_PENDING" "new-core"
update_settings "installed_version" "v-old"
update_settings "pending_core_version" "v-new"
printf '1\n' > "$MOCK_RUNNING_FILE"
do_stop() { printf '0\n' > "$MOCK_RUNNING_FILE"; return 0; }
do_start_quick() { printf '1\n' > "$MOCK_RUNNING_FILE"; return 0; }
wait_mihomo_api() { [[ "$(cat "$MOCK_RUNNING_FILE")" == "1" ]]; }
apply_pending_core || fail "ядро не применено к работающему VPN"
grep -q 'new-core' "$MIHOMO_BIN" || fail "работающий VPN остался на старом ядре"
$CORE_APPLY_RESTARTED || fail "успешный автоматический перезапуск не зафиксирован"

# Если новое ядро не поднимает сервис, возвращаются бинарник и версия.
create_fake_core "$MIHOMO_BIN" "old-core"
create_fake_core "$CORE_PENDING" "new-core"
update_settings "installed_version" "v-old"
update_settings "pending_core_version" "v-bad"
printf '1\n' > "$MOCK_RUNNING_FILE"
do_stop() { printf '0\n' > "$MOCK_RUNNING_FILE"; return 0; }
do_start_quick() {
    if grep -q 'new-core' "$MIHOMO_BIN"; then
        printf '0\n' > "$MOCK_RUNNING_FILE"
        return 1
    fi
    printf '1\n' > "$MOCK_RUNNING_FILE"
    return 0
}
wait_mihomo_api() { [[ "$(cat "$MOCK_RUNNING_FILE")" == "1" ]]; }

if apply_pending_core; then
    fail "неработающее ядро ошибочно принято"
else
    result=$?
    [[ "$result" -eq 2 ]] || fail "неверный код отката ядра: $result"
fi
grep -q 'old-core' "$MIHOMO_BIN" || fail "старое ядро не восстановлено"
[[ "$(read_settings installed_version)" == "v-old" ]] || fail "старая версия не восстановлена"
[[ "$(cat "$MOCK_RUNNING_FILE")" == "1" ]] || fail "VPN не запущен после отката"
[[ ! -e "$CORE_BACKUP" ]] || fail "резерв ядра остался после отката"

cat > "$TEST_TMP/bin/sw_vers" <<'EOF'
#!/bin/bash
printf '%s\n' "$MOCK_MACOS_VERSION"
EOF
cat > "$TEST_TMP/bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' "$MOCK_ARCH"
EOF
chmod +x "$TEST_TMP/bin/sw_vers" "$TEST_TMP/bin/uname"
STATUSBAR_GATE="$(sed -n '/^statusbar_supported_on_this_macos() {$/,/^}$/p' "$INSTALLER")"
[[ -n "$STATUSBAR_GATE" ]] || fail "не удалось извлечь проверку status-bar"
eval "$STATUSBAR_GATE"
export MOCK_MACOS_VERSION MOCK_ARCH
MOCK_ARCH=x86_64
MOCK_MACOS_VERSION=10.14.6
if statusbar_supported_on_this_macos; then fail "status-bar разрешён на Intel macOS 10.14"; fi
MOCK_MACOS_VERSION=10.15.7
statusbar_supported_on_this_macos || fail "status-bar запрещён на Intel macOS 10.15"
MOCK_ARCH=arm64
MOCK_MACOS_VERSION=10.15.7
if statusbar_supported_on_this_macos; then fail "status-bar разрешён на Apple Silicon macOS 10.15"; fi
MOCK_MACOS_VERSION=11.0.1
statusbar_supported_on_this_macos || fail "status-bar запрещён на Apple Silicon macOS 11"

grep -q '^statusbar_supported_on_this_macos()' "$INSTALLER" || \
    fail "нет проверки версии macOS для status-bar"
grep -q '^verify_statusbar_app()' "$INSTALLER" || \
    fail "нет проверки фактического запуска status-bar"
grep -q '<string>10.13</string>' "$INSTALLER" || \
    fail "fallback Dostup_VPN не поддерживает старую macOS"

cmp -s "$PROJECT_DIR/DostupVPN-StatusBar.swift" \
    <(sed -n "/^    cat > \"\$statusbar_dir\/DostupVPN-StatusBar.swift\" << 'SWIFTSOURCE'$/,/^SWIFTSOURCE$/p" \
        "$INSTALLER" | sed '1d;$d') || fail "Swift-исходники рассинхронизированы"

echo "OK: macOS profile/core updates are transactional and status-bar has a safe fallback"
