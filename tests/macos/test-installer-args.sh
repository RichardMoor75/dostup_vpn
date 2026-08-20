#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
INSTALLER="$PROJECT_DIR/dostup-install.command"

# Загружаем только безопасный префикс установщика с чистой функцией разрешения
# аргумента. Основной сценарий установки при этом не запускается.
INSTALLER_PREFIX="$(sed '/^# --- URL ---/,$d' "$INSTALLER")"
eval "$INSTALLER_PREFIX"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_resolves() {
    local input="$1"
    local expected="$2"
    local actual

    actual="$(resolve_subscription_arg "$input")" || fail "аргумент отклонён: $input"
    [[ "$actual" == "$expected" ]] || fail "$input -> $actual, ожидалось $expected"
}

assert_rejected() {
    local input="$1"
    if resolve_subscription_arg "$input" >/dev/null 2>&1; then
        fail "недопустимый аргумент принят: $input"
    fi
}

capture_top_level_arg() {
    {
        printf '%s\n' "$INSTALLER_PREFIX"
        printf '%s\n' 'printf "%s\n" "$SUB_URL_ARG"'
    } | bash -s -- "$@"
}

assert_resolves "user" "https://sub.92724063.xyz/conf/yaml/user.yaml"
assert_resolves "a_abdrashitova" "https://sub.92724063.xyz/conf/yaml/a_abdrashitova.yaml"
assert_resolves "User-2026" "https://sub.92724063.xyz/conf/yaml/User-2026.yaml"
assert_resolves "https://example.com/profile.yaml?token=abc" "https://example.com/profile.yaml?token=abc"
assert_resolves "http://127.0.0.1/profile.yaml" "http://127.0.0.1/profile.yaml"

assert_rejected ""
assert_rejected "user.yaml"
assert_rejected "../user"
assert_rejected "user/name"
assert_rejected "user name"
assert_rejected "пользователь"
assert_rejected "ftp://example.com/profile.yaml"

[[ -z "$SUB_URL_ARG" ]] || fail "запуск без аргумента не сохранил интерактивный сценарий"

CAPTURED_ARG="$(capture_top_level_arg "user")"
[[ "$CAPTURED_ARG" == "user" ]] || fail "bash -s -- user не передал первый аргумент"

CAPTURED_ENV="$({
    printf '%s\n' "$INSTALLER_PREFIX"
    printf '%s\n' 'printf "%s\n" "$SUB_URL_ARG"'
} | DOSTUP_SUB_URL="env-user" bash -s)"
[[ "$CAPTURED_ENV" == "env-user" ]] || fail "DOSTUP_SUB_URL больше не работает"

CAPTURED_PRECEDENCE="$({
    printf '%s\n' "$INSTALLER_PREFIX"
    printf '%s\n' 'printf "%s\n" "$SUB_URL_ARG"'
} | DOSTUP_SUB_URL="env-user" bash -s -- "arg-user")"
[[ "$CAPTURED_PRECEDENCE" == "arg-user" ]] || fail "аргумент не имеет приоритет над DOSTUP_SUB_URL"

echo "OK: macOS installer accepts full URLs and safe short names"
