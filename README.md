# vectorshop CLI

**English** · [中文](README.zh-CN.md)

Let **Claude Code**, **Codex**, or **OpenClaw** do vector design for you — posters, menus, business cards, banners. Install once, then just say "make me a poster for a coffee shop". The agent calls this tool to write DSL, render it, **look at the rendered image**, and iterate until it's right, producing a `.vsp` you can drag into [VectorShop](https://vectorshop.app/) for further work.

### Get VectorShop

**[vectorshop.app](https://vectorshop.app/)** — the macOS app the `.vsp` files open in. This CLI is free and gives you a finished 1x PNG plus the editable `.vsp` source; refining that design by hand and exporting at 2x/3x happens in the app.

> For people who already have [Claude Code](https://claude.com/claude-code), [Codex](https://developers.openai.com/codex), or [OpenClaw](https://openclaw.ai/) installed and configured. If you don't write code at all, skip this repo entirely and use the AI chat built into [the VectorShop app](https://vectorshop.app/).

## Install for Claude Code (plugin, recommended)

Run these two commands inside Claude Code:

```
/plugin marketplace add chenyunguiMilook/vectorshop-cli
/plugin install vectorshop-design@vectorshop-cli
```

(Or non-interactively from a terminal:
`claude plugin marketplace add chenyunguiMilook/vectorshop-cli && claude plugin install vectorshop-design@vectorshop-cli`)

Start a new session afterwards. The first run downloads a signed, notarized binary (~34 MB) to `~/.vectorshop/current` — a one-time wait of a few seconds. After that, say "make me a poster" and the agent goes straight to the MCP tools: write DSL, **look at the inline render**, iterate, and only write files when you're happy. **No permission prompts anywhere in the design loop.**

> How the no-prompt part works: the plugin ships a `PreToolUse` hook that auto-approves only its own six tools (`list_categories` / `emit` / `get_example` / `get_skill` / `render` / `export`). It widens no other permission and never edits your `settings.json`; uninstalling the plugin removes it. The first five are read-only and in-memory. `export` writes the `.vsp` / `.png` / `.json` trio to the path given in the conversation, and refuses to overwrite an existing target.

- **Upgrade**: `/plugin update vectorshop-design@vectorshop-cli` (or turn on auto-update for this marketplace under `/plugin` → Marketplaces). The binary aligns itself on your next session.
- **Uninstall**: `/plugin uninstall vectorshop-design@vectorshop-cli`, then optionally `rm -rf ~/.vectorshop` and remove the `/usr/local/bin/vectorshop` symlink if you ever created one.
- Coming from an older version (v0.1 skill / v0.2 `claude mcp add`)? Nothing to clean up by hand — the plugin migrates on first run: it moves the old skill aside and removes the old user-scope MCP registration.

## Install for Codex (plugin)

```bash
codex plugin marketplace add chenyunguiMilook/vectorshop-cli
codex plugin add vectorshop-design@vectorshop-cli
```

Same first-run download (~34 MB to `~/.vectorshop/current`), and the same design loop. Codex auto-approves MCP tool calls by default, so this side ships no hooks at all — nothing to review, nothing to trust, no prompts.

- **Upgrade**: `codex plugin marketplace upgrade vectorshop-cli`. If `codex plugin list` still shows the old version afterwards, run `codex plugin add vectorshop-design@vectorshop-cli` again to pick up the refreshed marketplace snapshot. Either way the pinned binary aligns on your next session — the session you're in keeps running the version it started with, so an upgrade never interrupts you.
- **Uninstall**: `codex plugin remove vectorshop-design`, then `codex plugin marketplace remove vectorshop-cli`.

## Install for OpenClaw (plugin)

```bash
openclaw plugins marketplace list chenyunguiMilook/vectorshop-cli
openclaw plugins install vectorshop-design --marketplace chenyunguiMilook/vectorshop-cli
openclaw plugins enable vectorshop-design
openclaw gateway restart
```

VectorShop is installed as an OpenClaw-compatible plugin bundle with a stdio MCP server and a shared design skill. The first design request downloads the same signed binary to `~/.vectorshop/current`. If a slow connection exceeds OpenClaw's first connection window, restart the Gateway once after the download finishes; subsequent starts are immediate.

Verify the install with `openclaw plugins inspect vectorshop-design`. In a coding or messaging agent, ask for a poster and OpenClaw will use the `vectorshop__*` MCP tools, inspect the inline render, and deliver the PNG plus `.vsp` source.

- **Upgrade**: `openclaw plugins update vectorshop-design`, then restart the Gateway when prompted.
- **Uninstall**: `openclaw plugins uninstall vectorshop-design`.
- **Tools missing in a sandboxed agent?** Allow `bundle-mcp`, `group:plugins`, or `vectorshop__*` in that agent's sandbox tool policy, then restart the Gateway.

> **The Claude Code, Codex, and OpenClaw plugins can live on the same machine.** They share one binary under `~/.vectorshop/`, so there is no reason to pick one. (This is a different question from the script-vs-plugin choice below, which really is either/or.)
>
> That sharing has one consequence worth knowing: `rm -rf ~/.vectorshop` during uninstall removes the binary **all three** plugins use. Any plugin you kept will simply re-download it (~34 MB) on its next run.

## Install via script (fallback, Claude Code only)

```bash
curl -fsSL https://raw.githubusercontent.com/chenyunguiMilook/vectorshop-cli/main/install.sh | bash
```

It downloads and verifies the latest release → installs to `~/.vectorshop/current` → symlinks into `/usr/local/bin` (falling back to a PATH hint if it can't) → and, **only with your consent**, registers itself as a Claude Code MCP server (tools named `mcp__vectorshop__*`).

- See what it would do without touching disk: add `--dry-run`
- Say yes to everything non-interactively: add `--yes`

The script is self-contained and auditable — reading it after `curl` before running it is entirely reasonable.

> **Pick the plugin or the script, not both**: installing both registers two MCP servers doing the same job. (The plugin's first run cleans up the script's registration anyway, but there's no reason to take that detour.)

## Requirements

- macOS (Apple Silicon). The binary is signed with an Apple Developer ID and notarized, so it runs straight after download.
- Claude Code, Codex, and/or OpenClaw, depending on which plugin you install.

## Manual install

Grab `vectorshop-cli-macos-arm64.tar.gz` from [Releases](https://github.com/chenyunguiMilook/vectorshop-cli/releases/latest), extract it, and run `./vectorshop --help` from the extracted directory. The binary and the `*.bundle` resources next to it are one unit — don't move the executable on its own. To register the MCP server by hand:

```bash
claude mcp add -s user vectorshop -- "$PWD/vectorshop" --mcp
```

## Repository boundary

This repository is the source of truth for the public VectorShop agent-plugin delivery layer: all compatible host manifests, the shared design skill, plugin bootstrap/install scripts, plugin tests, documentation, and pinned release hashes live here. The private VectorShop monorepo owns the Swift renderer and produces signed, notarized release archives; binaries are published through this repository's GitHub Releases rather than committed to Git history.

Run the delivery checks locally with:

```bash
python3 tests/check_manifests.py
bash tests/test_plugin.sh
```
