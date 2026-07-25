#!/usr/bin/env bash
# vectorshop plugin 的 MCP command(stdio server 入口)。
# 约定:exec 前 stdout 零输出——stdout 是 MCP 协议通道;一切诊断走 stderr。
# 就绪判定刻意只看「二进制可执行」:版本对齐归 SessionStart hook 管(升级会话先跑旧
# 二进制、下一会话生效),避免把 30s MCP_TIMEOUT 窗口押在 34MB 下载上(设计 §②)。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.vectorshop}"
BIN="$INSTALL_ROOT/current/vectorshop"

if [[ ! -x "$BIN" ]]; then
  # 兜底:hook 没跑完/失败/被 kill 时自己装;ensure 内部有锁,与 hook 并发安全。
  "$SCRIPT_DIR/ensure-vectorshop.sh" || {
    printf 'vectorshop: 二进制安装失败(多为网络问题)。请检查网络后重开会话,或在 /mcp 面板对 vectorshop 执行 retry。\n' >&2
    exit 1
  }
fi
exec "$BIN" --mcp
