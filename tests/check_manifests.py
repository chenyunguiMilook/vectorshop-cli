#!/usr/bin/env python3
"""Cross-host manifest and marketplace contract checks."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugins" / "vectorshop-design"


class ContractError(RuntimeError):
    """A public plugin delivery contract was violated."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load(path: Path) -> dict:
    require(path.is_file(), f"missing JSON file: {path}")
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def resolve_plugin_path(raw: str) -> Path:
    return (ROOT / raw).resolve()


def main() -> None:
    claude = load(PLUGIN / ".claude-plugin" / "plugin.json")
    codex = load(PLUGIN / ".codex-plugin" / "plugin.json")
    claude_market = load(ROOT / ".claude-plugin" / "marketplace.json")
    codex_market = load(ROOT / ".agents" / "plugins" / "marketplace.json")
    codex_mcp_path = codex["mcpServers"]
    require(
        codex_mcp_path == "./.mcp.json",
        "Codex/OpenClaw must use the plugin-root MCP config required by ingestion",
    )
    require(
        "mcpServers" not in claude,
        "Claude must use default .mcp.json discovery instead of a duplicate inline source",
    )
    codex_mcp = load(PLUGIN / codex_mcp_path)["mcpServers"]

    expected_name = "vectorshop-design"
    require(PLUGIN.name == expected_name, "plugin folder name drifted")
    require(
        claude["name"] == codex["name"] == expected_name,
        "Claude and Codex plugin names must match the folder",
    )
    require(claude["version"] == codex["version"], "plugin versions differ")
    require(claude["description"] == codex["description"], "descriptions differ")

    claude_entry = claude_market["plugins"][0]
    codex_entry = codex_market["plugins"][0]
    require(
        claude_entry["name"] == codex_entry["name"] == expected_name,
        "marketplace plugin names differ",
    )
    require(
        resolve_plugin_path(claude_entry["source"]) == PLUGIN.resolve(),
        "Claude marketplace source does not resolve to the canonical plugin",
    )
    require(codex_entry["source"]["source"] == "local", "Codex source must be local")
    require(
        resolve_plugin_path(codex_entry["source"]["path"]) == PLUGIN.resolve(),
        "Codex marketplace source does not resolve to the canonical plugin",
    )
    # Codex marketplace entries require authentication timing metadata even when
    # the plugin itself has no auth provider. ON_INSTALL is the scaffold default.
    require(
        codex_entry["policy"]
        == {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
        "Codex marketplace policy drifted from the required defaults",
    )
    require(codex_entry["category"] == "Productivity", "Codex category drifted")

    require(set(codex_mcp) == {"vectorshop"}, "shared MCP server name drifted")
    codex_server = codex_mcp["vectorshop"]
    require(
        codex_server["command"] == "/bin/sh",
        "shared MCP launcher must use the cross-host shell selector",
    )
    require(codex_server["cwd"] == ".", "Codex MCP cwd drifted")
    require(codex_server["args"][0] == "-c", "shared MCP launcher must use sh -c")
    launcher = codex_server["args"][1]
    require("CLAUDE_PLUGIN_ROOT" in launcher, "launcher omits the Claude plugin root")
    require("--host-agent" in launcher, "launcher omits the production agent flag")
    require(codex_server["startup_timeout_sec"] >= 300, "startup timeout is too short")
    require(
        codex_server["default_tools_approval_mode"] == "auto",
        "Codex tool approval mode drifted",
    )
    require("hooks" not in codex, "Codex manifest must not declare hooks")
    require("SessionStart" in claude["hooks"], "Claude SessionStart hook is missing")
    require("PreToolUse" in claude["hooks"], "Claude PreToolUse hook is missing")

    bootstrap = PLUGIN / "scripts" / "vectorshop-mcp.sh"
    require(bootstrap.is_file(), "bootstrap script is missing")
    require(bool(bootstrap.stat().st_mode & 0o111), "bootstrap script is not executable")

    skill = PLUGIN / "skills" / expected_name / "SKILL.md"
    require(skill.is_file(), "shared skill is missing")
    skill_text = skill.read_text(encoding="utf-8")
    require("[TODO:" not in skill_text, "shared skill contains TODO placeholders")
    require(
        skill_text.startswith("---\nname: vectorshop-design\n"),
        "shared skill frontmatter is invalid",
    )
    require("Call `render`" in skill_text, "shared skill omits the render step")
    require("Call `export`" in skill_text, "shared skill omits the export step")
    require(
        "skills" not in claude,
        "Claude should use its default plugin-root skills/ discovery",
    )
    require(codex["skills"] == "./skills/", "Codex shared skill path drifted")

    print("manifest contracts: PASS")


if __name__ == "__main__":
    main()
