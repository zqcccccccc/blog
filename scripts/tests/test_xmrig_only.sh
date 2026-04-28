#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "${message}: missing '${needle}'"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "${message}: unexpected '${needle}'"
  fi
}

test_status_is_xmrig_only() {
  local output
  output="$(XMRIG_ONLY_TEST_MODE=1 bash "${ROOT_DIR}/scripts/install_xmrig.sh" status)"

  assert_contains "$output" "XMRig 配置" "status output"
  assert_contains "$output" "XMRig 运行状态" "status output"
  assert_not_contains "$output" "TM CLI 配置" "status output"
  assert_not_contains "$output" "TM CLI 运行状态" "status output"
}

test_apply_alias_maps_to_force() {
  local output
  output="$(XMRIG_ONLY_TEST_MODE=1 bash "${ROOT_DIR}/scripts/install_xmrig.sh" apply)"

  assert_contains "$output" "mode=force" "apply alias"
  assert_not_contains "$output" "TM CLI" "apply alias output"
}

main() {
  test_status_is_xmrig_only
  test_apply_alias_maps_to_force
  echo "[PASS] test_xmrig_only.sh"
}

main "$@"
