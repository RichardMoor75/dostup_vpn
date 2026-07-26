#!/bin/bash
#
# Сборка персонального установщика Dostup VPN (macOS).
#
# Замысел: приложение нотаризуется ОДИН раз, а персонализируется переименованием.
# Имя папки бандла не входит в подпись, тикет нотаризации лежит внутри Contents/ —
# поэтому «Установить Dostup VPN.app» можно переименовать в
# «Установить Dostup VPN [a_abdrashitova].app», и подпись останется валидной.
#
#   ./make-installer-app.sh build              — собрать, подписать, нотаризовать (один раз)
#   ./make-installer-app.sh pack a_abdrashitova [ещё_слаг ...]
#                                              — сделать zip'ы для пользователей
#   ./make-installer-app.sh check              — проверить, что мастер готов к раздаче
#
# Запускать на macOS с Xcode Command Line Tools.

set -euo pipefail

# ============================================
# Настройки — подставь свои
# ============================================

# Имя сертификата целиком, как его показывает: security find-identity -v -p codesigning
DEV_ID="${DOSTUP_DEV_ID:-Developer ID Application: ВАШЕ ИМЯ (TEAMID)}"

# Профиль ключей нотаризации. Создаётся один раз:
#   xcrun notarytool store-credentials "dostup-notary" \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
NOTARY_PROFILE="${DOSTUP_NOTARY_PROFILE:-dostup-notary}"

APP_NAME="Установить Dostup VPN"
BUNDLE_ID="ru.dostup.vpn.installer"

# База URL подписки — БЕЗ завершающего слэша, слаг подставляется как <база>/<слаг>.yaml
# Намеренно НЕ хранится в репозитории: он публичный, а слаги предсказуемы (обычно
# фамилия), поэтому опубликованный шаблон дал бы возможность перебирать чужие подписки.
#   export DOSTUP_SUB_BASE="https://sub.example.com/conf/yaml"
SUB_BASE="${DOSTUP_SUB_BASE:-}"

# ============================================

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SRC_DIR/build"
MASTER_APP="$BUILD_DIR/$APP_NAME.app"
OUT_DIR="$SRC_DIR/dist"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "${YELLOW}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}" >&2; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }

require_macos() {
    [[ "$(uname)" == "Darwin" ]] || { err "Этот скрипт работает только на macOS"; exit 1; }
}

check_identity() {
    if [[ "$DEV_ID" == *"ВАШЕ ИМЯ"* ]]; then
        err "Не задан сертификат подписи."
        echo "  Посмотреть доступные:  security find-identity -v -p codesigning"
        echo "  Затем:                 export DOSTUP_DEV_ID=\"Developer ID Application: … (TEAMID)\""
        exit 1
    fi
    if ! security find-identity -v -p codesigning | grep -qF "$DEV_ID"; then
        err "Сертификат не найден в связке ключей:"
        echo "  $DEV_ID"
        exit 1
    fi
}

# --- Сборка ---------------------------------------------------------------

do_build() {
    require_macos
    check_identity

    if [[ -z "$SUB_BASE" ]]; then
        err "Не задана база URL подписки."
        echo "  export DOSTUP_SUB_BASE=\"https://sub.example.com/conf/yaml\""
        echo "  (без завершающего слэша; в репозитории не хранится намеренно)"
        exit 1
    fi
    if [[ "$SUB_BASE" != https://* ]]; then
        err "DOSTUP_SUB_BASE должен начинаться с https:// — получено: $SUB_BASE"
        exit 1
    fi

    rm -rf "$BUILD_DIR"
    mkdir -p "$MASTER_APP/Contents/MacOS" "$MASTER_APP/Contents/Resources"

    step "Компиляция лаунчера (universal)..."
    # Оба среза обязательны: arm64 без Rosetta, x86_64 для старых маков.
    # Минимум для arm64 — 11.0: Apple Silicon не существует до Big Sur.
    xcrun swiftc -O -target x86_64-apple-macos10.15 -framework Cocoa \
        -o "$BUILD_DIR/launcher-x86_64" "$SRC_DIR/DostupVPN-Launcher.swift"
    xcrun swiftc -O -target arm64-apple-macos11.0 -framework Cocoa \
        -o "$BUILD_DIR/launcher-arm64" "$SRC_DIR/DostupVPN-Launcher.swift"
    lipo -create -output "$MASTER_APP/Contents/MacOS/DostupVPN-Installer" \
        "$BUILD_DIR/launcher-x86_64" "$BUILD_DIR/launcher-arm64"
    rm -f "$BUILD_DIR/launcher-x86_64" "$BUILD_DIR/launcher-arm64"
    ok "Скомпилирован: $(lipo -archs "$MASTER_APP/Contents/MacOS/DostupVPN-Installer")"

    [[ -f "$SRC_DIR/icon.icns" ]] && cp "$SRC_DIR/icon.icns" "$MASTER_APP/Contents/Resources/AppIcon.icns"

    # LSUIElement=true — лаунчер отрабатывает и молча завершается,
    # в Dock ему появляться незачем
    cat > "$MASTER_APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DostupVPN-Installer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>DostupSubscriptionBase</key>
    <string>$SUB_BASE</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

    step "Подпись Developer ID..."
    # --options runtime (hardened runtime) и --timestamp обязательны для нотаризации
    codesign --force --options runtime --timestamp \
        --sign "$DEV_ID" "$MASTER_APP"
    codesign --verify --strict --verbose=2 "$MASTER_APP"
    ok "Подписано"

    step "Отправка на нотаризацию (обычно 1–5 минут)..."
    local upload="$BUILD_DIR/upload.zip"
    ditto -c -k --keepParent "$MASTER_APP" "$upload"
    if ! xcrun notarytool submit "$upload" --keychain-profile "$NOTARY_PROFILE" --wait; then
        err "Нотаризация не прошла. Подробности:"
        echo "  xcrun notarytool log <submission-id> --keychain-profile \"$NOTARY_PROFILE\""
        exit 1
    fi
    rm -f "$upload"

    step "Прикрепление тикета..."
    xcrun stapler staple "$MASTER_APP"
    ok "Тикет прикреплён — приложение откроется без предупреждений"

    do_check
    echo ""
    info "Готово. Теперь: ./make-installer-app.sh pack <слаг>"
}

# --- Проверка -------------------------------------------------------------

do_check() {
    require_macos
    [[ -d "$MASTER_APP" ]] || { err "Мастер не собран, запусти: $0 build"; exit 1; }

    step "Проверка мастера..."
    echo -n "  архитектуры: "; lipo -archs "$MASTER_APP/Contents/MacOS/DostupVPN-Installer"
    codesign --verify --strict "$MASTER_APP" && ok "подпись валидна"
    xcrun stapler validate "$MASTER_APP" >/dev/null 2>&1 \
        && ok "тикет нотаризации на месте" \
        || { err "тикет не прикреплён — у пользователя будет предупреждение"; exit 1; }
    # Итоговая проверка глазами Gatekeeper: должно быть source=Notarized Developer ID
    spctl -a -vvv -t exec "$MASTER_APP" 2>&1 | sed 's/^/  /'
}

# --- Упаковка на пользователя ---------------------------------------------

do_pack() {
    require_macos
    [[ $# -gt 0 ]] || { err "Укажи хотя бы один слаг: $0 pack a_abdrashitova"; exit 1; }
    [[ -d "$MASTER_APP" ]] || { err "Мастер не собран, запусти: $0 build"; exit 1; }

    mkdir -p "$OUT_DIR"
    local slug target zip
    for slug in "$@"; do
        # Тот же белый список, что и в лаунчере: слаг попадает в URL
        if [[ ! "$slug" =~ ^[A-Za-z0-9_-]+$ ]]; then
            err "Недопустимый слаг: $slug (разрешены буквы, цифры, _ и -)"
            continue
        fi

        target="$OUT_DIR/$APP_NAME [$slug].app"
        zip="$OUT_DIR/$APP_NAME [$slug].zip"
        rm -rf "$target" "$zip"
        cp -R "$MASTER_APP" "$target"

        # Переименование не ломает подпись — убеждаемся в этом сразу
        if ! codesign --verify --strict "$target" 2>/dev/null; then
            err "После переименования подпись стала невалидной: $slug"
            rm -rf "$target"
            continue
        fi

        # ditto, а не zip: сохраняет права и структуру бандла
        ditto -c -k --keepParent "$target" "$zip"
        rm -rf "$target"
        ok "$(basename "$zip")  ($(du -h "$zip" | cut -f1))"
        # База берётся из уже собранного бандла — так видно, что реально зашито
        base=$(defaults read "$MASTER_APP/Contents/Info" DostupSubscriptionBase 2>/dev/null || echo "?")
        echo "     ссылка: $base/$slug.yaml"
    done
    echo ""
    info "Файлы в $OUT_DIR — отправляй пользователю zip целиком"
}

# --- Точка входа ----------------------------------------------------------

case "${1:-}" in
    build) do_build ;;
    check) do_check ;;
    pack)  shift; do_pack "$@" ;;
    *)
        echo "Использование:"
        echo "  $0 build                       собрать, подписать и нотаризовать (один раз)"
        echo "  $0 pack <слаг> [<слаг> ...]    сделать zip'ы для пользователей"
        echo "  $0 check                       проверить готовность мастера"
        exit 1
        ;;
esac
