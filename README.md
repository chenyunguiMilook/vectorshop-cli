# vectorshop CLI

让 **Claude Code** 帮你做矢量设计（海报 / 菜单 / 名片 / banner …）：装一次，之后在
Claude Code 里直接说「帮我做一张咖啡店海报」，Claude 会自己调用本工具写 DSL、渲染、
**看渲染图**、改到满意，产出可拖进 VectorShop 继续精修的 `.vsp`。

> 面向已安装并登录 [Claude Code](https://claude.com/claude-code) 的用户（需较新版本，
> 看不到 `/plugin` 命令请先升级）。纯非技术用户请直接用 VectorShop app 本体的 AI 聊天。

## 安装方式一：Claude Code Plugin（推荐）

在 Claude Code 里执行两条命令：

```
/plugin marketplace add chenyunguiMilook/vectorshop-cli
/plugin install vectorshop-design@vectorshop-cli
```

（或在终端非交互执行：
`claude plugin marketplace add chenyunguiMilook/vectorshop-cli && claude plugin install vectorshop-design@vectorshop-cli`）

装完重开会话：首次会自动下载签名公证的二进制（约 34MB）到 `~/.vectorshop/current`
（首跑多等十几秒，仅此一次）。之后说一句「帮我做一张海报」即可——Claude 直接调
MCP 工具写 DSL、**当场看内联渲染图**迭代，满意才落盘交付，设计全程**零权限弹窗**。

> 零弹窗是怎么做到的：本插件自带一个 `PreToolUse` hook，只对自己的 6 个工具
> （`list_categories`/`emit`/`get_example`/`get_skill`/`render`/`export`）自动放行，
> 不放宽任何其它权限、也不修改你的 `settings.json`，卸载插件即失效。其中前五个
> 全内存只读，`export` 会按对话里给出的路径写出 `.vsp`/`.png`/`.json` 三件套
> （目标已存在时拒绝覆盖）。

- **升级**：`/plugin update vectorshop-design@vectorshop-cli`（或在 `/plugin` →
  Marketplaces 里为本 marketplace 打开自动更新）；二进制在下一会话自动对齐。
- **卸载**：`/plugin uninstall vectorshop-design@vectorshop-cli`，然后可选
  `rm -rf ~/.vectorshop` 与删除 `/usr/local/bin/vectorshop` 软链（若装过）。
- 装过旧版（v0.1 skill / v0.2 `claude mcp add`）不用手动清理：plugin 首跑自动迁移
  （挪走旧 skill、移除旧的 user-scope MCP 注册）。

## 安装方式二：一行脚本（备选，不用 plugin 时）

```bash
curl -fsSL https://raw.githubusercontent.com/chenyunguiMilook/vectorshop-cli/main/install.sh | bash
```

它会：下载校验最新版 → 装到 `~/.vectorshop/current` → 软链到 `/usr/local/bin`
（无权限时给 PATH 兜底）→ **征得你同意后**注册成 Claude Code 的 MCP server
（工具名 `mcp__vectorshop__*`）。

- 先看它会做什么、不落任何盘：加 `--dry-run`
- 非交互一路同意：加 `--yes`

安装脚本自足、可审计——`curl` 出来先读一遍再跑完全 OK。

> **两种方式二选一，别双装**：双装会注册两份同功能的 MCP server（plugin 首跑会
> 自动清掉脚本注册的那份，但没必要绕这一圈）。

## 前提

- macOS（Apple Silicon）。二进制经 Apple Developer ID 签名并公证，下载即可运行。
- 已安装 `claude` CLI（Claude Code）。

## 手动安装

到 [Releases](https://github.com/chenyunguiMilook/vectorshop-cli/releases/latest) 下
`vectorshop-cli-macos-arm64.tar.gz`，解压后整目录运行 `./vectorshop --help`
（二进制与同目录的 `*.bundle` 资源是一个整体，勿单独移动）。手动注册 MCP：

```bash
claude mcp add -s user vectorshop -- "$PWD/vectorshop" --mcp
```
