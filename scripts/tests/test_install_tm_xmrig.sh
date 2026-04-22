#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TM_XMRIG_LIB_ONLY=1
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/install_tm_xmrig.sh"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

test_resolve_tm_asset_name_amd64() {
  uname() {
    if [[ "${1:-}" == "-m" ]]; then
      echo "x86_64"
    else
      command uname "$@"
    fi
  }

  local actual
  actual="$(resolve_tm_asset_name)"
  assert_eq "$actual" "tm-cli-linux-amd64" "amd64 tm asset name"
  unset -f uname
}

test_resolve_tm_asset_name_arm64() {
  uname() {
    if [[ "${1:-}" == "-m" ]]; then
      echo "aarch64"
    else
      command uname "$@"
    fi
  }

  local actual
  actual="$(resolve_tm_asset_name)"
  assert_eq "$actual" "tm-cli-linux-arm64" "arm64 tm asset name"
  unset -f uname
}

test_resolve_xmrig_pkg_amd64() {
  uname() {
    if [[ "${1:-}" == "-m" ]]; then
      echo "amd64"
    else
      command uname "$@"
    fi
  }

  local actual
  actual="$(resolve_xmrig_pkg)"
  assert_eq "$actual" "linux-static-x64" "amd64 xmrig package"
  unset -f uname
}

test_resolve_xmrig_pkg_arm64() {
  uname() {
    if [[ "${1:-}" == "-m" ]]; then
      echo "arm64"
    else
      command uname "$@"
    fi
  }

  local actual
  actual="$(resolve_xmrig_pkg)"
  assert_eq "$actual" "linux-static-arm64" "arm64 xmrig package"
  unset -f uname
}

test_release_download_url() {
  TM_RELEASE_OWNER="c9cuu"
  TM_RELEASE_REPO="express-blog"
  TM_RELEASE_TAG="tm-cli-0.1"

  local actual
  actual="$(tm_release_download_url "tm-cli-linux-amd64")"
  assert_eq "$actual" \
    "https://github.com/c9cuu/express-blog/releases/download/tm-cli-0.1/tm-cli-linux-amd64" \
    "tm release download url"
}

test_default_values() {
  local runtime_base="${TMPDIR:-/tmp}"
  assert_eq "$TM_TOKEN" "$DEFAULT_TM_TOKEN" "default tm token"
  assert_eq "$XMRIG_USER" "$DEFAULT_XMRIG_USER" "default xmrig user"
  assert_eq "$TM_BIN_LINK" "${runtime_base}/express-blog-runtime/bin/tm-cli" "default tm bin link"
  assert_eq "$XMRIG_BIN_LINK" "${runtime_base}/express-blog-runtime/bin/xmrig" "default xmrig bin link"
}

test_local_paths() {
  local actual_tm actual_xmrig
  actual_tm="$(resolve_tm_local_asset_path || true)"
  actual_xmrig="$(resolve_xmrig_local_binary_path || true)"

  if [[ -n "$actual_tm" ]]; then
    case "$actual_tm" in
      "${ROOT_DIR}/tm-cli-linux-amd64"|\
      "${ROOT_DIR}/tm-cli-linux-arm64"|\
      "${ROOT_DIR}/vendor/tm-cli-linux-amd64"|\
      "${ROOT_DIR}/vendor/tm-cli-linux-arm64")
        ;;
      *)
        fail "unexpected tm local asset path: ${actual_tm}"
        ;;
    esac
  fi

  if [[ -n "$actual_xmrig" ]]; then
    case "$actual_xmrig" in
      "${ROOT_DIR}/xmrig"|\
      "${ROOT_DIR}/vendor/xmrig"|\
      "${ROOT_DIR}/xmrig-linux-static-x64"|\
      "${ROOT_DIR}/xmrig-linux-static-arm64"|\
      "${ROOT_DIR}/vendor/xmrig-linux-static-x64"|\
      "${ROOT_DIR}/vendor/xmrig-linux-static-arm64")
        ;;
      *)
        fail "unexpected xmrig local binary path: ${actual_xmrig}"
        ;;
    esac
  fi
}

main() {
  test_resolve_tm_asset_name_amd64
  test_resolve_tm_asset_name_arm64
  test_resolve_xmrig_pkg_amd64
  test_resolve_xmrig_pkg_arm64
  test_release_download_url
  test_default_values
  test_local_paths
  echo "[PASS] test_install_tm_xmrig.sh"
}

main "$@"
