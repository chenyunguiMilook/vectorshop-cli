#!/usr/bin/env bash
# vectorshop 一行安装脚本（审计友好：curl 出来先读再跑）。
#   curl -fsSL <BASE_URL>/install.sh | bash
# 幂等。--dry-run 只打印不改盘;--yes 非交互自动同意写 permissions.allow。
set -euo pipefail

# ---- 可配置量（环境变量可覆盖;真 URL 上线后填 BASE_URL 默认值即可）--------
BASE_URL="${VECTORSHOP_BASE_URL:-https://github.com/chenyunguiMilook/vectorshop-cli/releases/latest/download}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.vectorshop}"
BIN_LINK_DIR="${BIN_LINK_DIR:-/usr/local/bin}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

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
# SKILL 会回退到绝对路径,且两条 allow 规则(裸名+绝对路径)都已授权(见第 6 步)。
if [[ "$DRY_RUN" -eq 1 ]]; then
  say "[dry-run] 将软链 $BIN → $BIN_LINK_DIR/vectorshop"
elif mkdir -p "$BIN_LINK_DIR" 2>/dev/null && ln -sf "$BIN" "$BIN_LINK_DIR/vectorshop" 2>/dev/null; then
  say "已软链: $BIN_LINK_DIR/vectorshop"
else
  say "提示: 无权限写 $BIN_LINK_DIR,未创建软链。想让裸 vectorshop 进 PATH,二选一手动:"
  say "  sudo ln -sf \"$BIN\" \"$BIN_LINK_DIR/vectorshop\""
  say "  或加进 shell 配置: export PATH=\"$INSTALL_ROOT/current:\$PATH\""
  say "（不建也不影响 Claude:SKILL 回退绝对路径,裸名与绝对路径均已在免确认列表。）"
fi

# ---- 5. 装/更新 Claude Code skill ----------------------------------------
# 总是 --force 重装:SKILL 是生成内容,注入的绝对路径必须指向**本次**安装的 binary。
# 只在「已存在则跳过」会留下指向旧/陈旧 binary 的 SKILL(实测踩过:老 worktree debug 路径)。
if [[ "$DRY_RUN" -eq 1 ]]; then
  say "[dry-run] 将运行: vectorshop install-claude-skill --dir $CLAUDE_SKILLS_DIR --force"
else
  "$BIN" install-claude-skill --dir "$CLAUDE_SKILLS_DIR" --force >/dev/null || die "安装 skill 失败。"
  say "已安装/更新 Claude Code skill → $CLAUDE_SKILLS_DIR/vectorshop-design/（指向本次 binary）"
fi

# ---- 6. permissions.allow（consent-gated）--------------------------------
# 两条都授权:SKILL 命令示例用**裸** `vectorshop`(PATH 找不到时才回退到绝对路径),
# 所以裸名必须也在白名单——否则每条裸 `vectorshop` 命令都弹确认(实测:软链没建成 +
# 只授权绝对路径时,裸命令仍逐条弹)。绝对路径覆盖回退调用。裸名即便没进 PATH 也无害。
RULES=(--rule "Bash($BIN:*)" --rule "Bash(vectorshop:*)")

consent=0
if [[ "$DRY_RUN" -eq 1 ]]; then
  consent=0
elif [[ "$ASSUME_YES" -eq 1 ]]; then
  consent=1
elif [[ -r /dev/tty ]]; then
  printf '把 vectorshop 加进 Claude Code 免确认列表(%s)？Claude 调用本工具将不再逐条弹确认。[y/N] ' \
    "$CLAUDE_SETTINGS" > /dev/tty
  read -r reply < /dev/tty || reply=""
  case "$reply" in y|Y|yes|YES) consent=1 ;; esac
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  say "[dry-run] 征得同意后将写入 $CLAUDE_SETTINGS: ${RULES[*]}"
elif [[ "$consent" -eq 1 ]]; then
  if "$BIN" configure-claude-permissions --settings "$CLAUDE_SETTINGS" "${RULES[@]}" >/dev/null; then
    say "已更新 permissions.allow。"
  else
    say "更新 permissions.allow 失败(不影响安装);可手动加: Bash($BIN:*)"
  fi
else
  say "未修改 permissions.allow。想让 Claude 免确认调用,手动加进 $CLAUDE_SETTINGS 的 permissions.allow:"
  say "  Bash($BIN:*)"
fi

# ---- 完成 ----------------------------------------------------------------
say ""
say "完成 ✅  在 Claude Code 里说「帮我做一张咖啡店海报」即可。"
[[ "$DRY_RUN" -eq 1 ]] && say "（以上为 --dry-run,未改动任何文件。）"
exit 0
