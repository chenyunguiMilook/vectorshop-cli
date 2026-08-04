#!/usr/bin/env bash
# Plugin delivery smoke tests. Everything runs in temporary HOME/install roots.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PLUGIN="plugins/vectorshop-design"
ENSURE="$PLUGIN/scripts/ensure-vectorshop.sh"
BOOTSTRAP="$PLUGIN/scripts/vectorshop-mcp.sh"
ALLOW_HOOK="$PLUGIN/scripts/allow-own-tools.sh"
ARCH="$(uname -m)"
FAIL=0

ok() { printf '  ok: %s\n' "$1"; }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=1; }
check() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }

cleanup_paths=()
cleanup() {
  (( ${#cleanup_paths[@]} )) || return 0
  local path
  for path in "${cleanup_paths[@]}"; do
    [[ ! -e "$path" ]] || rm -rf "$path"
  done
}
trap cleanup EXIT

echo "== static contracts"
python3 tests/check_manifests.py
check '[[ -x "$ENSURE" && -x "$BOOTSTRAP" && -x "$ALLOW_HOOK" ]]' "delivery scripts are executable"

ALLOW_OUT="$(bash "$ALLOW_HOOK")"
check '[[ "$(wc -l <<<"$ALLOW_OUT")" -eq 1 ]]' "Claude approval hook emits one JSON line"
check 'python3 -c "import json,sys; d=json.load(sys.stdin)[\"hookSpecificOutput\"]; assert d[\"hookEventName\"]==\"PreToolUse\"; assert d[\"permissionDecision\"]==\"allow\"" <<<"$ALLOW_OUT"' "Claude approval hook contract"

SERVER="$(mktemp -d)"
STAGE_PARENT="$(mktemp -d)"
HOMEISH="$(mktemp -d)"
WORK="$(mktemp -d)"
SHIM_DIR="$(mktemp -d)"
cleanup_paths+=("$SERVER" "$STAGE_PARENT" "$HOMEISH" "$WORK" "$SHIM_DIR")

STAGE="$STAGE_PARENT/vectorshop-cli-test"
mkdir -p "$STAGE"
apply_fake_binary() {
  apply_target="$1"
  cp tests/fixtures/fake-vectorshop.sh "$apply_target"
  chmod +x "$apply_target"
}
apply_fake_binary "$STAGE/vectorshop"

TARBALL="vectorshop-cli-macos-${ARCH}.tar.gz"
tar -czf "$SERVER/$TARBALL" -C "$STAGE_PARENT" "$(basename "$STAGE")"
(cd "$SERVER" && shasum -a 256 "$TARBALL" > "$TARBALL.sha256")
TB_SHA="$(awk '{print $1}' "$SERVER/$TARBALL.sha256")"
BIN_SHA="$(shasum -a 256 "$STAGE/vectorshop" | awk '{print $1}')"

export INSTALL_ROOT="$HOMEISH/.vectorshop"
export VECTORSHOP_OLD_SKILL_DIR="$HOMEISH/.claude/skills/vectorshop-design"
export VECTORSHOP_CLAUDE_JSON="$HOMEISH/.claude.json"
export VECTORSHOP_MANIFEST_FILE="$WORK/manifest.env"
export VECTORSHOP_BASE_URL="file://$SERVER"
cat > "$VECTORSHOP_MANIFEST_FILE" <<EOF
VSMANIFEST_VERSION="9.9.9"
VSMANIFEST_BASE_URL="file://$SERVER"
VSMANIFEST_TARBALL_SHA256_ARM64="$TB_SHA"
VSMANIFEST_TARBALL_SHA256_X86_64="$TB_SHA"
VSMANIFEST_BIN_SHA256_ARM64="$BIN_SHA"
VSMANIFEST_BIN_SHA256_X86_64="$BIN_SHA"
EOF

cat > "$SHIM_DIR/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CLAUDE_SHIM_LOG:?}"
if [[ "${1:-}" == "mcp" && "${2:-}" == "get" ]]; then
  printf '%s\n' "${CLAUDE_SHIM_MCP_GET:-}"
fi
EOF
chmod +x "$SHIM_DIR/claude"
export CLAUDE_SHIM_LOG="$HOMEISH/claude.log"
: > "$CLAUDE_SHIM_LOG"
export PATH="$SHIM_DIR:$PATH"

BIN="$INSTALL_ROOT/current/vectorshop"
VERSION_FILE="$INSTALL_ROOT/current/VERSION"

echo "== installer"
bash "$ENSURE"
check '[[ -x "$BIN" ]]' "pinned binary installed"
check '[[ "$(cat "$VERSION_FILE")" == "9.9.9" ]]' "VERSION recorded"
check '"$BIN" --help >/dev/null' "installed binary starts"

echo "== shared agent bootstrap"
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'
rm -rf "$INSTALL_ROOT/current"
MCP_LAUNCHER="$(python3 -c 'import json; print(json.load(open("plugins/vectorshop-design/.mcp.json"))["mcpServers"]["vectorshop"]["args"][1])')"
RESP="$(cd "$PLUGIN" && printf '%s\n' "$INIT" | /bin/sh -c "$MCP_LAUNCHER" 2>/dev/null)"
check 'grep -Fq "\"serverInfo\"" <<<"$RESP"' "production --host-agent installs and handshakes"
check '[[ "$(wc -l <<<"$RESP")" -eq 1 ]]' "MCP stdout contains one protocol line"

CLAUDE_RESP="$(cd "$WORK" && printf '%s\n' "$INIT" | CLAUDE_PLUGIN_ROOT="$REPO_ROOT/$PLUGIN" /bin/sh -c "$MCP_LAUNCHER" 2>/dev/null)"
check 'grep -Fq "\"serverInfo\"" <<<"$CLAUDE_RESP"' "shared launcher uses CLAUDE_PLUGIN_ROOT outside plugin cwd"

echo "== shared agent host isolation"
: > "$CLAUDE_SHIM_LOG"
mkdir -p "$VECTORSHOP_OLD_SKILL_DIR"
printf 'legacy' > "$VECTORSHOP_OLD_SKILL_DIR/SKILL.md"
printf '{"mcpServers":{"vectorshop":{"command":"%s"}}}' "$BIN" > "$VECTORSHOP_CLAUDE_JSON"
printf '1.0.0' > "$VERSION_FILE"
CLAUDE_SHIM_MCP_GET="vectorshop: $BIN --mcp (user)" VECTORSHOP_HOST=agent bash "$ENSURE"
check '[[ ! -s "$CLAUDE_SHIM_LOG" ]]' "shared agent host never mutates Claude registration"
check '[[ -f "$VECTORSHOP_OLD_SKILL_DIR/SKILL.md" ]]' "shared agent host leaves Claude legacy skill untouched"

FAKE_ROOT="$(mktemp -d)"
cleanup_paths+=("$FAKE_ROOT")
mkdir -p "$FAKE_ROOT/current"
cat > "$FAKE_ROOT/current/vectorshop" <<'EOF'
#!/usr/bin/env bash
pwd
EOF
chmod +x "$FAKE_ROOT/current/vectorshop"
printf '9.9.9' > "$FAKE_ROOT/current/VERSION"
PLUGIN_DIR="$(cd "$PLUGIN" && pwd)"
REAL_HOME="$(cd "$HOME" && pwd)"
AGENT_CWD="$(cd "$PLUGIN_DIR" && INSTALL_ROOT="$FAKE_ROOT" bash ./scripts/vectorshop-mcp.sh --host-agent </dev/null)"
check '[[ "$AGENT_CWD" == "$REAL_HOME" ]]' "shared agent exports never default into plugin cache"

echo
[[ "$FAIL" -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"
