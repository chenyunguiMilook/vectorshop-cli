<!--
  This README ships by copy: the VectorShop repo holds the source, the public
  vectorshop-cli repo holds the published copy. Edit the source — the next release
  overwrites the copy. English twin (default entry point): README.md; keep both in sync.
-->

# vectorshop CLI

[English](README.md) · **中文**

让 **Claude Code** 或 **Codex** 帮你做矢量设计（海报 / 菜单 / 名片 / banner …）：装一次，之后
直接说「帮我做一张咖啡店海报」，它会自己调用本工具写 DSL、渲染、**看渲染图**、改到满意，
产出可拖进 [VectorShop](https://vectorshop.app/) 继续精修的 `.vsp`。

### 获取 VectorShop

**[vectorshop.app](https://vectorshop.app/)** —— `.vsp` 文件用它打开的 macOS app。本 CLI 免费，
出成品 1x PNG 和可编辑的 `.vsp` 源文件；把设计接手过来手工精修、导出 2x/3x 高清，在 app 里做。

> 面向已安装并登录 [Claude Code](https://claude.com/claude-code) 或
> [Codex](https://developers.openai.com/codex) 的用户。纯非技术用户不必看这个仓库，
> 直接用 [VectorShop app](https://vectorshop.app/) 本体的 AI 聊天即可。

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

## 安装方式二：Codex Plugin

```bash
codex plugin marketplace add chenyunguiMilook/vectorshop-cli
codex plugin add vectorshop-design@vectorshop-cli
```

首跑同样自动下载约 34MB 到 `~/.vectorshop/current`，设计流程完全一致。Codex 默认就对
MCP 工具调用免审批，所以这一侧**一个 hook 都不带**——没有要你审阅的东西，也没有弹窗。

- **升级**：`codex plugin marketplace upgrade vectorshop-cli`。如果之后 `codex plugin list`
  仍显示旧版本，再跑一次 `codex plugin add vectorshop-design@vectorshop-cli` 取刷新后的
  marketplace 快照。无论走哪条，钉版二进制都在下一会话自动对齐——当前会话继续跑它启动时
  的那一版，升级永远不打断你。
- **卸载**：`codex plugin remove vectorshop-design`，然后
  `codex plugin marketplace remove vectorshop-cli`。

> **Claude Code plugin 与 Codex plugin 可以同机共存**：两者共用 `~/.vectorshop/` 下的
> 同一份二进制，不必二选一。（这与下面「脚本 vs plugin」那个真正二选一的选择是两回事。）
>
> 共用带来一个值得知道的后果：卸载时执行 `rm -rf ~/.vectorshop` 会把**两边共用**的二进制
> 一起删掉。留下的那一边下次运行时会自己重新下载（约 34MB）。

## 安装方式三：一行脚本（备选，仅支持 Claude Code）

```bash
curl -fsSL https://raw.githubusercontent.com/chenyunguiMilook/vectorshop-cli/main/install.sh | bash
```

它会：下载校验最新版 → 装到 `~/.vectorshop/current` → 软链到 `/usr/local/bin`
（无权限时给 PATH 兜底）→ **征得你同意后**注册成 Claude Code 的 MCP server
（工具名 `mcp__vectorshop__*`）。

- 先看它会做什么、不落任何盘：加 `--dry-run`
- 非交互一路同意：加 `--yes`

安装脚本自足、可审计——`curl` 出来先读一遍再跑完全 OK。

> **脚本与 plugin 二选一，别双装**：双装会注册两份同功能的 MCP server（plugin 首跑会
> 自动清掉脚本注册的那份，但没必要绕这一圈）。

## 前提

- macOS（Apple Silicon）。二进制经 Apple Developer ID 签名并公证，下载即可运行。
- 已安装 `claude` CLI（Claude Code）和/或 `codex` CLI，取决于你要装哪一侧。

## 手动安装

到 [Releases](https://github.com/chenyunguiMilook/vectorshop-cli/releases/latest) 下
`vectorshop-cli-macos-arm64.tar.gz`，解压后整目录运行 `./vectorshop --help`
（二进制与同目录的 `*.bundle` 资源是一个整体，勿单独移动）。手动注册 MCP：

```bash
claude mcp add -s user vectorshop -- "$PWD/vectorshop" --mcp
```
