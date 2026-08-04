#!/usr/bin/env bash
# vectorshop plugin 的 MCP command(stdio server 入口)。
# 约定:exec 前 stdout 零输出——stdout 是 MCP 协议通道;一切诊断走 stderr。
# 就绪判定刻意只看「二进制可执行」:版本对齐默认归 SessionStart hook 管(升级会话
# 先跑旧二进制、下一会话生效),避免把 30s MCP_TIMEOUT 窗口押在 34MB 下载上(设计
# §②)。Codex/OpenClaw 没有 Claude SessionStart 预热,version_aligned() 分支替它们
# 在后台补这一课,同样不阻塞本次握手。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.vectorshop}"
BIN="$INSTALL_ROOT/current/vectorshop"
MANIFEST_FILE="${VECTORSHOP_MANIFEST_FILE:-$SCRIPT_DIR/../bin-manifest.env}"

# 只读两个值做比对,零网络、稳态 <10ms。拿不到清单或拿不到版本号时一律「视为对齐」——
# 宁可不升级,也不能因为清单异常就在每次启动时反复起后台下载。
# source 放进子 shell:bootstrap 自身环境保持干净(exec 出去的是 MCP server 进程)。
version_aligned() {
  local want have
  [[ -f "$MANIFEST_FILE" ]] || return 0
  want="$(source "$MANIFEST_FILE" 2>/dev/null; printf '%s' "${VSMANIFEST_VERSION:-}")"
  [[ -n "$want" ]] || return 0
  have="$(cat "$INSTALL_ROOT/current/VERSION" 2>/dev/null || true)"
  [[ "$have" == "$want" ]]
}

# 宿主标记:各自清单通过 argv 标记宿主。未知参数一律静默忽略——将来任一宿主
# 加新开关时,旧脚本不会因此启动失败。
for arg in "$@"; do
  case "$arg" in
    --host-codex) export VECTORSHOP_HOST=codex ;;
    --host-openclaw) export VECTORSHOP_HOST=openclaw ;;
    --host-agent) export VECTORSHOP_HOST=agent ;;
    *) ;;
  esac
done

if [[ ! -x "$BIN" ]]; then
  # 兜底/正路:Claude 侧有 SessionStart hook 预热,这里是 hook 没跑完/失败/被 kill 的
  # 兜底;Codex/OpenClaw 没有 Claude hook,这就是首跑正路——宿主清单里的 300s
  # 连接窗口覆盖 34MB 同步下载。ensure 内部有锁,与 hook 并发安全。
  "$SCRIPT_DIR/ensure-vectorshop.sh" || {
    printf 'vectorshop: 二进制安装失败(多为网络问题)。请检查网络后重开会话,或在 /mcp 面板对 vectorshop 执行 retry。\n' >&2
    exit 1
  }
elif [[ "${VECTORSHOP_HOST:-}" == "codex" || "${VECTORSHOP_HOST:-}" == "openclaw" || "${VECTORSHOP_HOST:-}" == "agent" ]] && ! version_aligned; then
  # Codex/OpenClaw 没有 Claude hook 替我们升级,bootstrap 自己扛;但绝不同步等——本次会话跑旧二进制,
  # 下一会话 fast path 命中新版,与 Claude 侧「升级会话跑旧二进制」的行为一致。
  # current 是原子 mv 替换,已 exec 的进程持有旧二进制文件本身的 inode,不受替换影响。
  # 但这只保证「可执行文件」这一件事:vectorshop 以目录包发布,同目录还有一组
  # *.bundle 资源(Packages/VSCLI/Sources/VSCLICore/ResourceBundleSelfCheck.swift 里
  # Bundle.main.bundleURL 那条候选路径),每次请求都按「路径」惰性重新解析——mv 之后
  # 这条路径指向的是*新版*资源。也就是说:本次会话仍在跑旧二进制的逻辑,但它随时可能
  # 读到新版的资源(字体/模板/DesignSkillKit 范例等),旧逻辑 + 新资源的组合未必兼容。
  # current 与 current.new/current.old 之间还有一个短暂窗口 current 完全不存在。这个
  # 风险是既有的(Claude 侧 SessionStart hook 对存活 server 做的是同一套 mv 替换),
  # 不在本分支引入,也不在本分支修——见 checklist §2.5。
  # stdout 必须丢弃:它是 MCP 协议通道,后台进程继承会污染协议流,并让调用方的
  # 命令替换一直等到后台进程退出。</dev/null 同理丢弃继承来的 stdin——bootstrap 的
  # stdin 是协议通道的另一半。ensure-vectorshop.sh 今天不读 stdin,所以严格说没有
  # 东西会被这一手偷走;加上它只是把「巧合安全」升级成「结构上就不可能」,这份纪律在
  # 这个文件里是一贯的。
  nohup "$SCRIPT_DIR/ensure-vectorshop.sh" </dev/null >/dev/null 2>&1 &
fi
# Codex/OpenClaw 都从 plugin 根解析相对 command/cwd,启动时会把我们钉在安装目录。
# 但 cwd 同时是工具里相对路径的解析基准:export 的 outPath 若是相对路径,会写进
# 宿主 plugin 缓存,下次更新可能被擦掉。挪到 $HOME:仍与 Claude 侧
# (cwd=项目目录)不同,但失败面从「消失在缓存里」降级为「落在家目录」。
# 拿不到用户项目目录是硬约束:PWD 被 bash 启动时改写,Codex 也没给 MCP server
# 注入工作目录相关的环境变量。
if [[ "${VECTORSHOP_HOST:-}" == "codex" || "${VECTORSHOP_HOST:-}" == "openclaw" || "${VECTORSHOP_HOST:-}" == "agent" ]]; then
  cd "$HOME" || true  # || true:$HOME 万一不存在(裸容器/异常账户)时不让 set -e 在
                       # 这里直接炸掉整个 bootstrap——宁可留在原 cwd 往下走 exec。
fi
# BIN 是用 $INSTALL_ROOT 在本文件顶部、任何 cd 之前拼出来的绝对路径(默认
# $HOME/.vectorshop/...;测试覆盖值今天也总是绝对路径)。这不是巧合:上面的 cd 一旦
# 落地,相对 INSTALL_ROOT 拼出的 BIN 就会指错地方——目前 exec "$BIN" 能正常工作,
# 是「BIN 是绝对路径」这个前提撑住的,cd 只是让这件事从「无关紧要」变成「必须为真」。
exec "$BIN" --mcp
