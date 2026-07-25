#!/usr/bin/env bash
# vectorshop plugin 的安装/升级/迁移核心——SessionStart hook 与 MCP bootstrap 共用。
# 幂等。所有输出走 stderr:SessionStart hook 的 stdout 会注入会话上下文,必须安静;
# 被 bootstrap 复用时 stdout 是 MCP 协议通道,更不能碰。
# 可覆盖量(测试隔离,沿用 install.sh 惯例):INSTALL_ROOT / VECTORSHOP_BASE_URL /
# VECTORSHOP_MANIFEST_FILE / VECTORSHOP_OLD_SKILL_DIR / VECTORSHOP_CLAUDE_JSON /
# VECTORSHOP_LOCK_WAIT。
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_FILE="${VECTORSHOP_MANIFEST_FILE:-$PLUGIN_ROOT/bin-manifest.env}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.vectorshop}"
OLD_SKILL_DIR="${VECTORSHOP_OLD_SKILL_DIR:-$HOME/.claude/skills/vectorshop-design}"
CLAUDE_JSON="${VECTORSHOP_CLAUDE_JSON:-$HOME/.claude.json}"
LOCK_DIR="$INSTALL_ROOT/.install.lock"

log() { printf 'vectorshop-plugin: %s\n' "$*" >&2; }
die() { log "错误: $*"; exit 1; }

[[ -f "$MANIFEST_FILE" ]] || die "缺少 bin-manifest.env: $MANIFEST_FILE"
# shellcheck source=/dev/null
source "$MANIFEST_FILE"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64)  TARBALL_SHA="${VSMANIFEST_TARBALL_SHA256_ARM64:-}"; PIN_BIN_SHA="${VSMANIFEST_BIN_SHA256_ARM64:-}" ;;
  x86_64) TARBALL_SHA="${VSMANIFEST_TARBALL_SHA256_X86_64:-}"; PIN_BIN_SHA="${VSMANIFEST_BIN_SHA256_X86_64:-}" ;;
  *) die "不支持的架构: $ARCH" ;;
esac

BIN="$INSTALL_ROOT/current/vectorshop"
VERSION_FILE="$INSTALL_ROOT/current/VERSION"
DID_INSTALL=0

TMP=""
HOLDING_LOCK=0
cleanup() {
  # || true:cleanup 在 EXIT trap 里跑,自身失败不能吞锁释放/污染主体退出码。
  [[ -z "$TMP" ]] || rm -rf "$TMP" || true
  [[ "$HOLDING_LOCK" != "1" ]] || rm -rf "$LOCK_DIR" || true
  return 0
}
trap cleanup EXIT

installed_version() { if [[ -f "$VERSION_FILE" ]]; then cat "$VERSION_FILE"; fi; }

up_to_date() { [[ -x "$BIN" && "$(installed_version)" == "$VSMANIFEST_VERSION" ]]; }

# v0.2 / install.sh 装的既有二进制没有 VERSION 文件:裸二进制 sha 与 manifest 匹配则
# 原地认领(补写 VERSION),免重下 34MB。认领也算「安装事件」→ 迁移步无条件走 CLI 确认。
try_adopt_existing() {
  [[ -x "$BIN" && ! -f "$VERSION_FILE" && -n "$PIN_BIN_SHA" ]] || return 1
  local actual; actual="$(shasum -a 256 "$BIN" | awk '{print $1}')"
  [[ "$actual" == "$PIN_BIN_SHA" ]] || return 1
  printf '%s' "$VSMANIFEST_VERSION" > "$VERSION_FILE"
  log "已识别既有 v$VSMANIFEST_VERSION 安装(sha 匹配),免重新下载。"
  DID_INSTALL=1
}

acquire_lock() {
  mkdir -p "$INSTALL_ROOT"
  local waited=0 max_wait="${VECTORSHOP_LOCK_WAIT:-120}"
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    # 陈死锁:mtime 超 10 分钟视为上次异常退出的残留,清掉重抢。
    local lock_mtime now
    if lock_mtime="$(stat -f %m "$LOCK_DIR" 2>/dev/null)"; then
      now="$(date +%s)"
      if (( now - lock_mtime > 600 )); then rm -rf "$LOCK_DIR"; continue; fi
    fi
    (( waited >= max_wait )) && die "等待安装锁超时: $LOCK_DIR"
    sleep 1; waited=$((waited + 1))
  done
  HOLDING_LOCK=1
}

install_pinned() {
  [[ -n "$TARBALL_SHA" ]] || die "该架构($ARCH)暂无预编译产物(现仅 arm64,Intel 在后续计划)。"
  acquire_lock
  # 双检:等锁期间可能已被并发方(hook/bootstrap 另一侧)装好。
  up_to_date && return 0
  local base_url="${VECTORSHOP_BASE_URL:-$VSMANIFEST_BASE_URL}"
  local tarball="vectorshop-cli-macos-${ARCH}.tar.gz"
  TMP="$(mktemp -d)"
  touch "$LOCK_DIR"   # 刷新锁 mtime:合法长下载(烂网>10min)不被等待者当陈死锁抢走
  log "下载 vectorshop v$VSMANIFEST_VERSION(约 34MB): $base_url/$tarball"
  curl -fsSL "$base_url/$tarball" -o "$TMP/$tarball" || die "下载失败: $base_url/$tarball"
  curl -fsSL "$base_url/$tarball.sha256" -o "$TMP/$tarball.sha256" || die "下载校验文件失败: $base_url/$tarball.sha256"
  ( cd "$TMP" && shasum -a 256 -c "$tarball.sha256" >/dev/null 2>&1 ) \
    || die "sha256 与 Release 附带校验不符,中止(产物可能损坏)。"
  # 第二重校验:manifest 钉死的 sha 是防篡改锚——Release 资产可被替换,git 历史不能。
  local actual; actual="$(shasum -a 256 "$TMP/$tarball" | awk '{print $1}')"
  [[ "$actual" == "$TARBALL_SHA" ]] \
    || die "sha256 与 plugin 钉死值不符(期望 $TARBALL_SHA 实际 $actual),拒绝安装。"
  mkdir -p "$TMP/extract"
  tar -xzf "$TMP/$tarball" -C "$TMP/extract"
  local inner; inner="$(find "$TMP/extract" -maxdepth 1 -type d -name 'vectorshop-cli-*' | head -1)"
  [[ -n "$inner" ]] || die "tarball 结构异常:未找到 vectorshop-cli-* 目录。"
  [[ -x "$inner/vectorshop" ]] || die "tarball 里没有可执行的 vectorshop。"
  rm -rf "$INSTALL_ROOT/current.new" "$INSTALL_ROOT/current.old"
  cp -R "$inner" "$INSTALL_ROOT/current.new"
  printf '%s' "$VSMANIFEST_VERSION" > "$INSTALL_ROOT/current.new/VERSION"
  [[ -e "$INSTALL_ROOT/current" ]] && mv "$INSTALL_ROOT/current" "$INSTALL_ROOT/current.old"
  mv "$INSTALL_ROOT/current.new" "$INSTALL_ROOT/current"
  rm -rf "$INSTALL_ROOT/current.old"
  xattr -dr com.apple.quarantine "$INSTALL_ROOT/current" 2>/dev/null || true
  log "已安装 v$VSMANIFEST_VERSION → $INSTALL_ROOT/current"
  DID_INSTALL=1
}

# 换代交付物必须清上一代残留,「不再安装」≠「已卸载」(v0.1→v0.2 真机实锤教训)。
legacy_registration_hinted() {
  # 毫秒级预检:user-scope MCP 注册落盘在 ~/.claude.json;两个 grep 都命中才值得
  # 起 claude CLI(约几百 ms)确认。文件位置若随版本漂移,兜底=安装/认领会话的
  # 无条件确认(见下),漏检不积累。
  [[ -f "$CLAUDE_JSON" ]] || return 1
  grep -q '"vectorshop"' "$CLAUDE_JSON" && grep -q '\.vectorshop' "$CLAUDE_JSON"
}

migrate_legacy() {
  # v0.1 skill:触发词会盖过 MCP 工具,把 Claude 引回 shell+写文件老流程 → 弹窗回归。
  # 挪走备份而非删除,可回滚。
  if [[ -d "$OLD_SKILL_DIR" ]]; then
    mkdir -p "$INSTALL_ROOT/backup"
    rm -rf "$INSTALL_ROOT/backup/skill-legacy-vectorshop-design"
    mv "$OLD_SKILL_DIR" "$INSTALL_ROOT/backup/skill-legacy-vectorshop-design"
    log "已挪走 v0.1 旧 skill → $INSTALL_ROOT/backup/skill-legacy-vectorshop-design"
  fi
  # v0.2 user-scope 注册:plugin server 与手动注册按 endpoint 判重(同名不判重),
  # 不清会两份 server 同时跑。endpoint 守卫:只删指向 .vectorshop/ 安装根的注册,
  # 用户自己注册的自定义构建不动;只动 user scope。
  if [[ "$DID_INSTALL" == "1" ]] || legacy_registration_hinted; then
    if command -v claude >/dev/null 2>&1; then
      if claude mcp get vectorshop 2>/dev/null | grep -q '\.vectorshop/'; then
        if claude mcp remove -s user vectorshop >/dev/null 2>&1; then
          log "已移除 v0.2 的 user-scope MCP 注册(由 plugin 自带 server 接管)。"
        fi
      fi
    fi
  fi
}

up_to_date || try_adopt_existing || install_pinned
migrate_legacy
