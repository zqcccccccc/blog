#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TM_XMRIG_LIB_ONLY=1
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/install_tm_xmrig.sh"

usage() {
  cat <<'EOF'
用法:
  bash scripts/run_tm_xmrig_local.sh [run|status|force]

模式说明:
  默认    自动执行。若 TM CLI + XMRig 都在运行，则仅展示状态；否则执行安装/启动流程。
  status  仅展示当前 TM CLI 和 XMRig 状态，不做安装/重启。
  force   强制执行安装/启动流程。

说明:
  这个脚本只使用项目内已有的本地二进制，不会下载任何文件。
  保留 scripts/install_tm_xmrig.sh 作为“可下载”的兜底脚本。
EOF
}

require_local_binary() {
  local label="$1"
  local file_path="$2"

  if [[ -z "$file_path" || ! -f "$file_path" ]]; then
    err "${label} 本地二进制不存在。"
    err "请把对应 Linux 二进制放到项目根目录，或改用 scripts/install_tm_xmrig.sh。"
    return 1
  fi
}

install_tm_binary() {
  local local_asset target_path
  local_asset="$(resolve_tm_local_asset_path || true)"
  require_local_binary "TM CLI" "$local_asset"

  ensure_runtime_dirs
  target_path="${TM_INSTALL_DIR}/$(resolve_tm_asset_name)"
  log "使用本地 TM CLI: ${local_asset}"
  run_root install -m 0755 "$local_asset" "$target_path"
  run_root ln -sf "$target_path" "$TM_BIN_LINK"
  ok "TM CLI 已安装: ${TM_BIN_LINK} -> ${target_path}"
}

install_xmrig_binary() {
  local local_bin target_path pkg
  pkg="$(resolve_xmrig_pkg)"
  local_bin="${PROJECT_ROOT}/xmrig-${pkg}"
  if [[ ! -f "$local_bin" ]]; then
    local_bin="$(resolve_xmrig_local_binary_path || true)"
  fi
  require_local_binary "XMRig" "$local_bin"

  ensure_runtime_dirs
  target_path="${XMRIG_INSTALL_DIR}/xmrig"
  log "使用本地 XMRig: ${local_bin}"
  run_root install -m 0755 "$local_bin" "$target_path"
  run_root ln -sf "$target_path" "$XMRIG_BIN_LINK"
  ok "XMRig 已安装: ${XMRIG_BIN_LINK}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
