#!/usr/bin/env bash
# Standalone install.sh test: local file:// archive, fake HOME, and Claude shim.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

INSTALL_SCRIPT="$REPO_ROOT/install.sh"
ARCH="$(uname -m)"
FAIL=0
cleanup_paths=()

ok() { printf '  ok: %s\n' "$1"; }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=1; }
check() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }

cleanup() {
  (( ${#cleanup_paths[@]} )) || return 0
  local path
  for path in "${cleanup_paths[@]}"; do
    [[ ! -e "$path" ]] || rm -rf "$path"
  done
}
trap cleanup EXIT

make_claude_shim() {
  local shim_dir="$1"
  cat > "$shim_dir/claude" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CLAUDE_SHIM_LOG:?}"
SHIM
  chmod +x "$shim_dir/claude"
}

SERVER="$(mktemp -d)"
STAGE_PARENT="$(mktemp -d)"
HOMEISH="$(mktemp -d)"
SHIM_DIR="$(mktemp -d)"
cleanup_paths+=("$SERVER" "$STAGE_PARENT" "$HOMEISH" "$SHIM_DIR")

STAGE="$STAGE_PARENT/vectorshop-cli-test"
mkdir -p "$STAGE"
cp tests/fixtures/fake-vectorshop.sh "$STAGE/vectorshop"
chmod +x "$STAGE/vectorshop"

TARBALL="vectorshop-cli-macos-${ARCH}.tar.gz"
tar -czf "$SERVER/$TARBALL" -C "$STAGE_PARENT" "$(basename "$STAGE")"
(cd "$SERVER" && shasum -a 256 "$TARBALL" > "$TARBALL.sha256")

export VECTORSHOP_BASE_URL="file://$SERVER"
export INSTALL_ROOT="$HOMEISH/.vectorshop"
export BIN_LINK_DIR="$HOMEISH/bin"
export VECTORSHOP_OLD_SKILL_DIR="$HOMEISH/.claude/skills/vectorshop-design"
export CLAUDE_SHIM_LOG="$HOMEISH/claude.log"
export PATH="$SHIM_DIR:$PATH"
BIN_PATH="$INSTALL_ROOT/current/vectorshop"

make_claude_shim "$SHIM_DIR"
: > "$CLAUDE_SHIM_LOG"
mkdir -p "$VECTORSHOP_OLD_SKILL_DIR"
printf 'legacy v0.1 skill' > "$VECTORSHOP_OLD_SKILL_DIR/SKILL.md"

echo "== standalone installer dry-run"
OUT="$(bash "$INSTALL_SCRIPT" --dry-run)"
check '[[ ! -e "$INSTALL_ROOT/current" ]]' "dry-run does not install"
check '[[ ! -s "$CLAUDE_SHIM_LOG" ]]' "dry-run does not call Claude"
check 'grep -Fq "[dry-run] 将注册 MCP" <<<"$OUT"' "dry-run describes MCP registration"
check '[[ -d "$VECTORSHOP_OLD_SKILL_DIR" ]]' "dry-run leaves the legacy skill untouched"

echo "== standalone installer"
: > "$CLAUDE_SHIM_LOG"
bash "$INSTALL_SCRIPT" --yes >/dev/null
check '[[ -x "$BIN_PATH" ]]' "binary is installed"
check '[[ -L "$BIN_LINK_DIR/vectorshop" ]]' "binary symlink is created"
check '[[ "$(wc -l < "$CLAUDE_SHIM_LOG")" -eq 2 ]]' "Claude receives remove and add calls"
check 'grep -Fxq "mcp remove -s user vectorshop" "$CLAUDE_SHIM_LOG"' "old MCP registration is removed"
check 'grep -Fxq "mcp add -s user vectorshop -- $BIN_PATH --mcp" "$CLAUDE_SHIM_LOG"' "new MCP registration uses the installed binary"
check '[[ ! -d "$VECTORSHOP_OLD_SKILL_DIR" ]]' "legacy skill is moved aside"
check '[[ -f "$INSTALL_ROOT/backup/skill-legacy-vectorshop-design/SKILL.md" ]]' "legacy skill backup is retained"
check '"$BIN_PATH" --help >/dev/null' "installed binary starts"

echo "== standalone installer idempotence"
: > "$CLAUDE_SHIM_LOG"
if bash "$INSTALL_SCRIPT" --yes >/dev/null 2>&1; then
  ok "second install succeeds"
else
  bad "second install fails"
fi
check '[[ "$(wc -l < "$CLAUDE_SHIM_LOG")" -eq 2 ]]' "second install repeats exactly two Claude calls"

echo "== standalone installer without Claude"
NOCLAUDE_PATH=""
IFS=':' read -ra path_dirs <<< "$PATH"
for path_dir in "${path_dirs[@]}"; do
  [[ -x "$path_dir/claude" ]] && continue
  NOCLAUDE_PATH="${NOCLAUDE_PATH:+$NOCLAUDE_PATH:}$path_dir"
done
if OUT="$(PATH="$NOCLAUDE_PATH" bash "$INSTALL_SCRIPT" --yes 2>&1)"; then
  ok "install succeeds when Claude is absent"
else
  bad "install fails when Claude is absent"
fi
check 'grep -Fq "未找到 claude 命令" <<<"$OUT"' "missing Claude is explained"
check 'grep -Fq "claude mcp add -s user vectorshop" <<<"$OUT"' "manual registration command is shown"

echo "== standalone installer checksum"
printf 'tampered\n' >> "$SERVER/$TARBALL"
if bash "$INSTALL_SCRIPT" --yes >/dev/null 2>&1; then
  bad "tampered archive is accepted"
else
  ok "tampered archive is rejected"
fi

echo
[[ "$FAIL" -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"
