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

  systemctl() { return 0; }
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
)

test_successful_commit_creates_known_good() (
  export DOSTUP_DIR="$TEMP_DIR/live-success"
  export DOSTUP_SERVICE_FILE="$TEMP_DIR/success.service"
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

  systemctl() { return 0; }
  hard_healthcheck() { return 0; }
  soft_post_update_check() { return 0; }

  commit_candidate "$TEMP_DIR/candidate-success"
  grep -qx 'new-core' "$DOSTUP_DIR/mihomo"
  grep -qx 'old-core' "$KNOWN_GOOD_DIR/mihomo"
  grep -Fxq mihomo "$KNOWN_GOOD_DIR/manifest"
)

test_failed_commit_rolls_back
test_successful_commit_creates_known_good

bash -n "$ROOT/dostup-install.sh"
echo "Linux installer regression tests: OK"
