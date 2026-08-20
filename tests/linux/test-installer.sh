#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../../dostup-install.sh
source "$ROOT/dostup-install.sh"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

legacy_process_config() {
  local config="$1" temp="${1}.processing" port
  sed '/^external-ui:/d; /^external-ui-url:/d' "$config" > "$temp"
  awk 'BEGIN{s=0} /^tun:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' \
    "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"
  awk 'BEGIN{s=0} /^rule-providers:/{s=1;next} s==1&&/^[^ \t]/{s=0} s==0{print}' \
    "$temp" > "${temp}.2" && mv "${temp}.2" "$temp"
  sed -i '/RULE-SET/d' "$temp"
  sed -i -E 's/^([[:space:]]*)- MATCH,(.*)/\1- MATCH,Auto Select/' "$temp"
  sed -i 's/listen: 0\.0\.0\.0:53/listen: 127.0.0.1:1053/' "$temp"
  sed -i -E "s/^(external-controller:[[:space:]]*)['\"]?0\.0\.0\.0:([0-9]+)['\"]?(.*)$/\1'127.0.0.1:\2'\3/" "$temp"
  port=$(awk -F: '/^mixed-port:/ { value=$2; gsub(/[[:space:]]/, "", value); print value; exit }' "$temp")
  if [[ "$port" != 7890 ]]; then
    sed -i "s/mixed-port: $port/mixed-port: 7890/" "$temp"
  fi
  mv "$temp" "$config"
}

cp "$ROOT/tests/linux/fixtures/profile.yaml" "$TEMP_DIR/expected.yaml"
cp "$ROOT/tests/linux/fixtures/profile.yaml" "$TEMP_DIR/actual.yaml"
legacy_process_config "$TEMP_DIR/expected.yaml"
process_config "$TEMP_DIR/actual.yaml" 7890
cmp "$TEMP_DIR/expected.yaml" "$TEMP_DIR/actual.yaml"

for url in \
  "https://example.com/profile.yaml" \
  "http://localhost/profile.yaml" \
  "http://127.0.0.1:8080/profile.yaml" \
  "http://10.20.30.40/profile.yaml" \
  "http://172.16.0.1/profile.yaml" \
  "http://192.168.1.1/profile.yaml" \
  "http://[::1]/profile.yaml" \
  "http://[fd00::1]/profile.yaml"; do
  validate_url "$url"
done

for url in \
  "http://example.com/profile.yaml" \
  "http://8.8.8.8/profile.yaml" \
  "ftp://example.com/profile.yaml" \
  "https://user:password@example.com/profile.yaml"; do
  if validate_url "$url"; then
    echo "URL должен быть отклонён: $url" >&2
    exit 1
  fi
done

printf 'verified payload\n' > "$TEMP_DIR/payload"
DIGEST="sha256:$(sha256sum "$TEMP_DIR/payload" | awk '{print $1}')"
verify_sha256_digest "$TEMP_DIR/payload" "$DIGEST"
if verify_sha256_digest "$TEMP_DIR/payload" \
  "sha256:0000000000000000000000000000000000000000000000000000000000000000"; then
  echo "Неверный digest был принят" >&2
  exit 1
fi

test_failed_commit_rolls_back() (
  export DOSTUP_DIR="$TEMP_DIR/live"
  export DOSTUP_SERVICE_FILE="$TEMP_DIR/dostup.service"
  export DOSTUP_UPDATE_SERVICE_FILE="$TEMP_DIR/dostup-update.service"
  export DOSTUP_UPDATE_TIMER_FILE="$TEMP_DIR/dostup-update.timer"
  export DOSTUP_CLI_PATH="$TEMP_DIR/dostup"
  export DOSTUP_LOCK_FILE="$TEMP_DIR/dostup.lock"
  source "$ROOT/dostup-install.sh"

  mkdir -p "$DOSTUP_DIR" "$TEMP_DIR/candidate/runtime"
  printf 'old-core\n' > "$DOSTUP_DIR/mihomo"
  printf 'mixed-port: 7890\nold: true\n' > "$DOSTUP_DIR/config.yaml"
  printf '{"installed_version":"old"}\n' > "$DOSTUP_DIR/settings.json"
  printf 'old-manager\n' > "$DOSTUP_DIR/dostup-manager.sh"
  printf '{"sites":[]}\n' > "$DOSTUP_DIR/sites.json"
  chmod 755 "$DOSTUP_DIR/mihomo" "$DOSTUP_DIR/dostup-manager.sh"
  printf 'old-service\n' > "$SERVICE_FILE"
  printf 'old-cli\n' > "$CLI_PATH"

  printf 'new-core\n' > "$TEMP_DIR/candidate/mihomo"
  printf 'mixed-port: 7890\nnew: true\n' > "$TEMP_DIR/candidate/config.yaml"
  printf '{"installed_version":"new"}\n' > "$TEMP_DIR/candidate/settings.json"
  printf 'new-manager\n' > "$TEMP_DIR/candidate/dostup-manager.sh"
  printf '{"sites":[]}\n' > "$TEMP_DIR/candidate/sites.json"
  chmod 755 "$TEMP_DIR/candidate/mihomo" "$TEMP_DIR/candidate/dostup-manager.sh"

  systemctl() {
    case "$*" in
      'is-active --quiet dostup') return 0 ;;
      'is-active --quiet dostup-update.timer'|'is-enabled --quiet dostup-update.timer')
        return 1 ;;
      *) return 0 ;;
    esac
  }
  local checks=0
  hard_healthcheck() {
    checks=$((checks + 1))
    (( checks > 1 ))
  }
  soft_post_update_check() { return 0; }

  if commit_candidate "$TEMP_DIR/candidate"; then
    echo "Неисправный кандидат был принят" >&2
    exit 1
  fi
  grep -qx 'old-core' "$DOSTUP_DIR/mihomo"
  grep -q 'old: true' "$DOSTUP_DIR/config.yaml"
  grep -qx 'old-service' "$SERVICE_FILE"
  grep -qx 'old-cli' "$CLI_PATH"
  [[ ! -e "$UPDATE_SERVICE_FILE" ]]
  [[ ! -e "$UPDATE_TIMER_FILE" ]]
)

test_successful_commit_creates_known_good() (
  export DOSTUP_DIR="$TEMP_DIR/live-success"
  export DOSTUP_SERVICE_FILE="$TEMP_DIR/success.service"
  export DOSTUP_UPDATE_SERVICE_FILE="$TEMP_DIR/success-update.service"
  export DOSTUP_UPDATE_TIMER_FILE="$TEMP_DIR/success-update.timer"
  export DOSTUP_CLI_PATH="$TEMP_DIR/success-cli"
  export DOSTUP_LOCK_FILE="$TEMP_DIR/success.lock"
  source "$ROOT/dostup-install.sh"

  mkdir -p "$DOSTUP_DIR" "$TEMP_DIR/candidate-success/runtime"
  printf 'old-core\n' > "$DOSTUP_DIR/mihomo"
  printf 'mixed-port: 7890\nold: true\n' > "$DOSTUP_DIR/config.yaml"
  printf '{"installed_version":"old"}\n' > "$DOSTUP_DIR/settings.json"
  chmod 755 "$DOSTUP_DIR/mihomo"

  printf 'new-core\n' > "$TEMP_DIR/candidate-success/mihomo"
  printf 'mixed-port: 7890\nnew: true\n' > "$TEMP_DIR/candidate-success/config.yaml"
  printf '{"installed_version":"new"}\n' > "$TEMP_DIR/candidate-success/settings.json"
  printf 'new-manager\n' > "$TEMP_DIR/candidate-success/dostup-manager.sh"
  printf '{"sites":[]}\n' > "$TEMP_DIR/candidate-success/sites.json"
  chmod 755 "$TEMP_DIR/candidate-success/mihomo" \
    "$TEMP_DIR/candidate-success/dostup-manager.sh"

  systemctl() {
    printf '%s\n' "$*" >> "$TEMP_DIR/success-systemctl.log"
    case "$*" in
      'is-active --quiet dostup-update.timer'|'is-enabled --quiet dostup-update.timer')
        return 1 ;;
      *) return 0 ;;
    esac
  }
  hard_healthcheck() { return 0; }
  soft_post_update_check() { return 0; }

  commit_candidate "$TEMP_DIR/candidate-success"
  grep -qx 'new-core' "$DOSTUP_DIR/mihomo"
  grep -qx 'old-core' "$KNOWN_GOOD_DIR/mihomo"
  grep -Fxq mihomo "$KNOWN_GOOD_DIR/manifest"
  grep -Fqx 'Type=oneshot' "$UPDATE_SERVICE_FILE"
  grep -Fqx 'Persistent=true' "$UPDATE_TIMER_FILE"
  grep -Fqx 'enable dostup-update.timer' "$TEMP_DIR/success-systemctl.log"
  grep -Fqx 'start dostup-update.timer' "$TEMP_DIR/success-systemctl.log"
)

test_background_no_change_skips_restart() (
  export DOSTUP_DIR="$TEMP_DIR/no-change-live"
  export DOSTUP_SERVICE_FILE="$TEMP_DIR/no-change.service"
  export DOSTUP_UPDATE_SERVICE_FILE="$TEMP_DIR/no-change-update.service"
  export DOSTUP_UPDATE_TIMER_FILE="$TEMP_DIR/no-change-update.timer"
  export DOSTUP_CLI_PATH="$TEMP_DIR/no-change-cli"
  export DOSTUP_LOCK_FILE="$TEMP_DIR/no-change.lock"
  source "$ROOT/dostup-install.sh"

  mkdir -p "$DOSTUP_DIR" "$TEMP_DIR/no-change-units"
  printf 'same-core\n' > "$DOSTUP_DIR/mihomo"
  printf 'mixed-port: 7890\n' > "$DOSTUP_DIR/config.yaml"
  printf '{}\n' > "$DOSTUP_DIR/settings.json"
  printf 'same-manager\n' > "$DOSTUP_DIR/dostup-manager.sh"
  printf '{"sites":[]}\n' > "$DOSTUP_DIR/sites.json"
  chmod 755 "$DOSTUP_DIR/mihomo" "$DOSTUP_DIR/dostup-manager.sh"
  render_installation_candidates "$TEMP_DIR/no-change-units"
  cp "$TEMP_DIR/no-change-units/service" "$SERVICE_FILE"
  cp "$TEMP_DIR/no-change-units/update-service" "$UPDATE_SERVICE_FILE"
  cp "$TEMP_DIR/no-change-units/update-timer" "$UPDATE_TIMER_FILE"
  cp "$TEMP_DIR/no-change-units/cli" "$CLI_PATH"

  prepare_mihomo_candidate() { return 0; }
  prepare_profile_candidate() { PROXY_PORT=7890; return 0; }
  prepare_geo_candidate() {
    settings_set_in "$1/settings.json" last_geo_update 2026-08-20
  }
  prepare_manager_candidate() { return 0; }
  validate_candidate_with_mihomo() { return 0; }
  systemctl() {
    printf '%s\n' "$*" >> "$TEMP_DIR/no-change-systemctl.log"
    return 0
  }

  prepare_and_commit "https://example.com/profile.yaml" background
  [[ ! -s "$TEMP_DIR/no-change-systemctl.log" ]]
  [[ "$(settings_get_from "$SETTINGS_FILE" last_geo_update)" == 2026-08-20 ]]
)

test_profile_and_core_changes_require_restart() (
  export DOSTUP_DIR="$TEMP_DIR/change-live"
  export DOSTUP_SERVICE_FILE="$TEMP_DIR/change.service"
  export DOSTUP_UPDATE_SERVICE_FILE="$TEMP_DIR/change-update.service"
  export DOSTUP_UPDATE_TIMER_FILE="$TEMP_DIR/change-update.timer"
  export DOSTUP_CLI_PATH="$TEMP_DIR/change-cli"
  source "$ROOT/dostup-install.sh"

  local stage="$TEMP_DIR/change-candidate" name
  mkdir -p "$DOSTUP_DIR" "$stage"
  for name in "${RESTART_RELEVANT_FILES[@]}"; do
    printf 'same-%s\n' "$name" > "$DOSTUP_DIR/$name"
    cp "$DOSTUP_DIR/$name" "$stage/$name"
  done
  chmod 755 "$DOSTUP_DIR/mihomo" "$DOSTUP_DIR/dostup-manager.sh" \
    "$stage/mihomo" "$stage/dostup-manager.sh"
  render_installation_candidates "$stage"
  cp "$stage/service" "$SERVICE_FILE"
  cp "$stage/update-service" "$UPDATE_SERVICE_FILE"
  cp "$stage/update-timer" "$UPDATE_TIMER_FILE"

  if candidate_requires_restart "$stage"; then
    echo "Неизменный кандидат требует перезапуск" >&2
    exit 1
  fi
  printf 'changed-profile\n' > "$stage/config.yaml"
  candidate_requires_restart "$stage"
  cp "$DOSTUP_DIR/config.yaml" "$stage/config.yaml"
  printf 'changed-core\n' > "$stage/mihomo"
  candidate_requires_restart "$stage"
)

test_component_download_failures_keep_current_files() (
  export DOSTUP_DIR="$TEMP_DIR/component-live"
  source "$ROOT/dostup-install.sh"

  local stage="$TEMP_DIR/component-candidate"
  mkdir -p "$stage"
  printf 'current-core\n' > "$stage/mihomo"
  printf 'mixed-port: 7890\ncurrent: true\n' > "$stage/config.yaml"
  printf '{}\n' > "$stage/settings.json"
  chmod 755 "$stage/mihomo"
  cp "$stage/mihomo" "$TEMP_DIR/component-core.expected"
  cp "$stage/config.yaml" "$TEMP_DIR/component-profile.expected"

  download_with_retry() { return 1; }
  systemctl() { return 1; }
  prepare_mihomo_candidate "$stage"
  prepare_profile_candidate "$stage" "https://example.com/profile.yaml"
  cmp "$TEMP_DIR/component-core.expected" "$stage/mihomo"
  cmp "$TEMP_DIR/component-profile.expected" "$stage/config.yaml"
)

test_rejected_candidate_does_not_touch_service() (
  export DOSTUP_DIR="$TEMP_DIR/rejected-live"
  source "$ROOT/dostup-install.sh"

  local stage="$TEMP_DIR/rejected-candidate"
  mkdir -p "$stage"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$stage/mihomo"
  printf 'mixed-port: 7890\n' > "$stage/config.yaml"
  chmod 755 "$stage/mihomo"
  systemctl() {
    printf '%s\n' "$*" >> "$TEMP_DIR/rejected-systemctl.log"
    return 0
  }
  if validate_candidate_with_mihomo "$stage"; then
    echo "Невалидный кандидат был принят" >&2
    exit 1
  fi
  [[ ! -s "$TEMP_DIR/rejected-systemctl.log" ]]
)

test_lock_conflict_returns_75() (
  export DOSTUP_LOCK_FILE="$TEMP_DIR/conflict.lock"
  source "$ROOT/dostup-install.sh"

  exec 8>"$LOCK_FILE"
  flock -n 8
  set +e
  (acquire_lock) > "$TEMP_DIR/conflict.log" 2>&1
  local status=$?
  set -e
  [[ "$status" -eq 75 ]]
)

test_background_command_is_noninteractive() (
  source "$ROOT/dostup-install.sh"
  require_root() { return 0; }
  acquire_lock() { return 0; }
  install_dependencies() { return 0; }
  migrate_legacy_runtime() { return 0; }
  read_settings() { printf 'https://example.com/profile.yaml\n'; }
  prepare_and_commit() { [[ "$2" == background ]]; }
  do_background_update < /dev/null
)

test_timer_units_and_uninstall() (
  export DOSTUP_DIR="$TEMP_DIR/uninstall-live"
  export DOSTUP_SERVICE_FILE="$TEMP_DIR/uninstall.service"
  export DOSTUP_UPDATE_SERVICE_FILE="$TEMP_DIR/uninstall-update.service"
  export DOSTUP_UPDATE_TIMER_FILE="$TEMP_DIR/uninstall-update.timer"
  export DOSTUP_CLI_PATH="$TEMP_DIR/uninstall-cli"
  source "$ROOT/dostup-install.sh"

  local units="$TEMP_DIR/verify-units"
  mkdir -p "$units" "$DOSTUP_DIR"
  render_service_candidate "$units/dostup.service"
  render_update_service_candidate "$units/dostup-update.service"
  render_update_timer_candidate "$units/dostup-update.timer"
  grep -Fqx 'ExecStart=/opt/dostup/dostup-manager.sh --cli update-background' \
    "$units/dostup-update.service"
  grep -Fqx 'StandardInput=null' "$units/dostup-update.service"
  grep -Fqx 'OnCalendar=Mon,Thu *-*-* 04:00:00' "$units/dostup-update.timer"
  grep -Fqx 'RandomizedDelaySec=30m' "$units/dostup-update.timer"
  grep -Fqx 'Persistent=true' "$units/dostup-update.timer"
  systemd-analyze calendar 'Mon,Thu *-*-* 04:00:00' >/dev/null
  local verify_output
  if ! verify_output=$(systemd-analyze verify --man=no --generators=no \
      "$units/dostup.service" "$units/dostup-update.service" \
      "$units/dostup-update.timer" 2>&1); then
    if [[ "$verify_output" == *'SO_PASSCRED failed: Operation not permitted'* ]]; then
      echo "systemd-analyze verify: пропущено из-за ограничений sandbox"
    else
      printf '%s\n' "$verify_output" >&2
      exit 1
    fi
  fi

  cp "$units/dostup.service" "$SERVICE_FILE"
  cp "$units/dostup-update.service" "$UPDATE_SERVICE_FILE"
  cp "$units/dostup-update.timer" "$UPDATE_TIMER_FILE"
  printf 'cli\n' > "$CLI_PATH"
  systemctl() {
    printf '%s\n' "$*" >> "$TEMP_DIR/uninstall-systemctl.log"
    return 0
  }
  require_root() { return 0; }
  acquire_lock() { return 0; }
  do_uninstall <<< y
  [[ ! -e "$SERVICE_FILE" ]]
  [[ ! -e "$UPDATE_SERVICE_FILE" ]]
  [[ ! -e "$UPDATE_TIMER_FILE" ]]
  grep -Fqx 'disable --now dostup-update.timer' \
    "$TEMP_DIR/uninstall-systemctl.log"
  grep -Fqx 'clean --what=state dostup-update.timer' \
    "$TEMP_DIR/uninstall-systemctl.log"
)

test_failed_commit_rolls_back
test_successful_commit_creates_known_good
test_background_no_change_skips_restart
test_profile_and_core_changes_require_restart
test_component_download_failures_keep_current_files
test_rejected_candidate_does_not_touch_service
test_lock_conflict_returns_75
test_background_command_is_noninteractive
test_timer_units_and_uninstall

bash -n "$ROOT/dostup-install.sh"
echo "Linux installer regression tests: OK"
