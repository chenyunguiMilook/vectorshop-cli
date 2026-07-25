#!/usr/bin/env bash
# vectorshop 一行安装脚本（审计友好：curl 出来先读再跑）。
# 推荐改用 Claude Code Plugin 安装(README「安装方式一」);本脚本是不用 plugin 时的备选,功能不变。
#   curl -fsSL <BASE_URL>/install.sh | bash
# 幂等。--dry-run 只打印不改盘;--yes 非交互自动同意注册 MCP server。
set -euo pipefail

# ---- 可配置量（环境变量可覆盖;真 URL 上线后填 BASE_URL 默认值即可）--------
BASE_URL="${VECTORSHOP_BASE_URL:-https://github.com/chenyunguiMilook/vectorshop-cli/releases/latest/download}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.vectorshop}"
BIN_LINK_DIR="${BIN_LINK_DIR:-/usr/local/bin}"

DRY_RUN=0; ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) echo "用法: install.sh [--dry-run] [--yes]"; exit 0 ;;
    *) echo "未知参数: $arg" >&2; exit 64 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---- 1. 预检 --------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "本工具仅支持 macOS。"
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) die "不支持的架构: $ARCH" ;; esac
for tool in curl tar shasum; do
  command -v "$tool" >/dev/null 2>&1 || die "缺少必需命令: $tool"
done

TARBALL_NAME="vectorshop-cli-macos-${ARCH}.tar.gz"
TARBALL_URL="$BASE_URL/$TARBALL_NAME"
SHA_URL="$TARBALL_URL.sha256"

say "== vectorshop 安装 =="
say "提示: 若你用 Claude Code,推荐改用 Plugin 安装(见 README);本脚本为备选路径。"
say "架构: $ARCH   源: $TARBALL_URL"
say "安装到: $INSTALL_ROOT/current"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---- 2. 下载 + sha256 校验 ------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  say "[dry-run] 将下载 $TARBALL_URL 与 $SHA_URL 并 shasum 校验"
else
  curl -fsSL "$TARBALL_URL" -o "$TMP/$TARBALL_NAME" || die "下载失败: $TARBALL_URL"
  curl -fsSL "$SHA_URL"     -o "$TMP/$TARBALL_NAME.sha256" || die "下载校验文件失败: $SHA_URL"
  ( cd "$TMP" && shasum -a 256 -c "$TARBALL_NAME.sha256" ) \
    || die "sha256 校验不通过,已中止(产物可能损坏或被篡改)。"
  say "sha256 校验通过。"
fi

# ---- 3. 解压 + 原子替换 ---------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  say "[dry-run] 将解压并原子替换 $INSTALL_ROOT/current"
else
  mkdir -p "$TMP/extract"
  tar -xzf "$TMP/$TARBALL_NAME" -C "$TMP/extract"
  INNER="$(find "$TMP/extract" -maxdepth 1 -type d -name 'vectorshop-cli-*' | head -1)"
  [[ -n "$INNER" ]] || die "tarball 结构异常:未找到 vectorshop-cli-* 目录。"
  [[ -x "$INNER/vectorshop" ]] || die "tarball 里没有可执行的 vectorshop。"
  mkdir -p "$INSTALL_ROOT"
  rm -rf "$INSTALL_ROOT/current.new" "$INSTALL_ROOT/current.old"
  cp -R "$INNER" "$INSTALL_ROOT/current.new"
  [[ -e "$INSTALL_ROOT/current" ]] && mv "$INSTALL_ROOT/current" "$INSTALL_ROOT/current.old"
  mv "$INSTALL_ROOT/current.new" "$INSTALL_ROOT/current"
  rm -rf "$INSTALL_ROOT/current.old"
  xattr -dr com.apple.quarantine "$INSTALL_ROOT/current" 2>/dev/null || true
  say "已安装到 $INSTALL_ROOT/current"
fi

BIN="$INSTALL_ROOT/current/vectorshop"

# ---- 4. 软链（无权限不 sudo,给兜底并继续）--------------------------------
# 软链只是便利:进 PATH 后裸 `vectorshop` 能直接跑。建不成也不影响 Claude——
# MCP 注册(见第 5 步)用的是绝对路径,不依赖这个软链。
if [[ "$DRY_RUN" -eq 1 ]]; then
  say "[dry-run] 将软链 $BIN → $BIN_LINK_DIR/vectorshop"
elif mkdir -p "$BIN_LINK_DIR" 2>/dev/null && ln -sf "$BIN" "$BIN_LINK_DIR/vectorshop" 2>/dev/null; then
  say "已软链: $BIN_LINK_DIR/vectorshop"
else
  say "提示: 无权限写 $BIN_LINK_DIR,未创建软链。想让裸 vectorshop 进 PATH,二选一手动:"
  say "  sudo ln -sf \"$BIN\" \"$BIN_LINK_DIR/vectorshop\""
  say "  或加进 shell 配置: export PATH=\"$INSTALL_ROOT/current:\$PATH\""
  say "（不建也不影响 Claude:MCP 注册用的是绝对路径,软链只服务你手动在终端敲裸 vectorshop。）"
fi

# ---- 5. 注册 Claude Code MCP server(Phase 2:取代 skill + permissions 白名单)----
# 一次注册,设计全程零权限弹窗;Claude Code 里的工具名 mcp__vectorshop__*。
# remove 先行保证幂等(add 遇同名报错);remove/add 必须同 scope(-s user:全局可用)。

# 5.0 迁移:挪走 v0.1 装的旧 skill。旧 SKILL 的触发词会盖过 MCP 工具,Claude 照旧
# shell CLI + 写中间文件 → 权限弹窗回归(v0.1→v0.2 升级实测踩过)。挪走备份而非删除,
# 可回滚;测试用 VECTORSHOP_OLD_SKILL_DIR 指到临时目录,绝不动测试机真实 HOME。
OLD_SKILL_DIR="${VECTORSHOP_OLD_SKILL_DIR:-$HOME/.claude/skills/vectorshop-design}"
if [[ -d "$OLD_SKILL_DIR" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    say "[dry-run] 将挪走 v0.1 旧 skill(与 MCP 冲突): $OLD_SKILL_DIR → $INSTALL_ROOT/backup/"
  else
    mkdir -p "$INSTALL_ROOT/backup"
    rm -rf "$INSTALL_ROOT/backup/skill-legacy-vectorshop-design"
    mv "$OLD_SKILL_DIR" "$INSTALL_ROOT/backup/skill-legacy-vectorshop-design"
    say "已挪走 v0.1 旧 Claude skill(会把 Claude 引回 shell 老流程)→ 备份在 $INSTALL_ROOT/backup/skill-legacy-vectorshop-design"
  fi
fi

MCP_ADD_CMD="claude mcp add -s user vectorshop -- \"$BIN\" --mcp"

if ! command -v claude >/dev/null 2>&1; then
  say "提示: 未找到 claude 命令(Claude Code)。装好后手动注册:"
  say "  $MCP_ADD_CMD"
elif [[ "$DRY_RUN" -eq 1 ]]; then
  say "[dry-run] 将注册 MCP: claude mcp remove -s user vectorshop; $MCP_ADD_CMD"
else
  consent=0
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    consent=1
  elif [[ -r /dev/tty ]]; then
    printf '把 vectorshop 注册成 Claude Code 的 MCP server(scope: user)?注册后说「做一张海报」即可全程免弹窗出图。[y/N] ' > /dev/tty
    read -r reply < /dev/tty || reply=""
    case "$reply" in y|Y|yes|YES) consent=1 ;; esac
  fi
  if [[ "$consent" -eq 1 ]]; then
    claude mcp remove -s user vectorshop >/dev/null 2>&1 || true
    if claude mcp add -s user vectorshop -- "$BIN" --mcp >/dev/null; then
      say "已注册 MCP server(scope: user)。"
    else
      say "注册失败(不影响安装);可手动: $MCP_ADD_CMD"
    fi
  else
    say "未注册。想启用,手动运行: $MCP_ADD_CMD"
  fi
fi

# ---- 完成 ----------------------------------------------------------------
say ""
say "完成 ✅  在 Claude Code 里说「帮我做一张咖啡店海报」即可(工具名 mcp__vectorshop__*)。"
[[ "$DRY_RUN" -eq 1 ]] && say "（以上为 --dry-run,未改动任何文件。）"
exit 0
