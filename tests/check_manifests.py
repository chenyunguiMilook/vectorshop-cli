#!/usr/bin/env python3
"""Cross-host manifest and marketplace contract checks."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugins" / "vectorshop-design"


def load(path: Path) -> dict:
    assert path.is_file(), f"missing JSON file: {path}"
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def resolve_plugin_path(raw: str) -> Path:
    return (ROOT / raw).resolve()


def main() -> None:
    claude = load(PLUGIN / ".claude-plugin" / "plugin.json")
    codex = load(PLUGIN / ".codex-plugin" / "plugin.json")
    claude_market = load(ROOT / ".claude-plugin" / "marketplace.json")
    codex_market = load(ROOT / ".agents" / "plugins" / "marketplace.json")
    claude_mcp = claude["mcpServers"]
    codex_mcp = load(PLUGIN / ".mcp.json")["mcpServers"]

    expected_name = "vectorshop-design"
    assert PLUGIN.name == expected_name
    assert claude["name"] == codex["name"] == expected_name
    assert claude["version"] == codex["version"]
    assert claude["description"] == codex["description"]

    claude_entry = claude_market["plugins"][0]
    codex_entry = codex_market["plugins"][0]
    assert claude_entry["name"] == codex_entry["name"] == expected_name
    assert resolve_plugin_path(claude_entry["source"]) == PLUGIN.resolve()
    assert codex_entry["source"]["source"] == "local"
    assert resolve_plugin_path(codex_entry["source"]["path"]) == PLUGIN.resolve()
    assert codex_entry["policy"] == {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL",
    }
    assert codex_entry["category"] == "Productivity"

    assert set(claude_mcp) == set(codex_mcp) == {"vectorshop"}
    codex_server = codex_mcp["vectorshop"]
    assert codex_server["command"] == "./scripts/vectorshop-mcp.sh"
    assert codex_server["cwd"] == "."
    assert "--host-agent" in codex_server["args"]
    assert codex_server["startup_timeout_sec"] >= 300
    assert codex_server["default_tools_approval_mode"] == "auto"
    assert "hooks" not in codex
    assert "SessionStart" in claude["hooks"]
    assert "PreToolUse" in claude["hooks"]

    bootstrap = PLUGIN / "scripts" / "vectorshop-mcp.sh"
    assert bootstrap.is_file()
    assert bootstrap.stat().st_mode & 0o111

    skill = PLUGIN / "skills" / expected_name / "SKILL.md"
    assert skill.is_file()
    skill_text = skill.read_text(encoding="utf-8")
    assert "[TODO:" not in skill_text
    assert skill_text.startswith("---\nname: vectorshop-design\n")
    assert "Call `render`" in skill_text
    assert "Call `export`" in skill_text
    assert claude["skills"] == codex["skills"] == "./skills/"

    print("manifest contracts: PASS")


if __name__ == "__main__":
    main()
