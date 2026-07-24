# vectorshop CLI

让 **Claude Code** 帮你做矢量设计（海报 / 菜单 / 名片 / banner …）：装一次，之后在
Claude Code 里直接说「帮我做一张咖啡店海报」，Claude 会自己调用本工具写 DSL、渲染、
**看渲染图**、改到满意，产出可拖进 VectorShop 继续精修的 `.vsp`。

> 面向已安装并登录 [Claude Code](https://claude.com/claude-code) 的用户。纯非技术用户请直接用
> VectorShop app 本体的 AI 聊天。

## 一行安装（macOS）

```bash
curl -fsSL https://raw.githubusercontent.com/chenyunguiMilook/vectorshop-cli/main/install.sh | bash
```

它会：下载校验最新版 → 装到 `~/.vectorshop/current` → 软链到 `/usr/local/bin`
（无权限时给 PATH 兜底）→ 安装 Claude Code 技能 → **征得你同意后**把 `vectorshop`
加进 Claude 的免确认列表。之后在 Claude Code 里说一句需求即可。

- 先看它会做什么、不落任何盘：加 `--dry-run`
- 非交互一路同意：加 `--yes`

```bash
curl -fsSL https://raw.githubusercontent.com/chenyunguiMilook/vectorshop-cli/main/install.sh | bash -s -- --dry-run
```

安装脚本自足、可审计——`curl` 出来先读一遍再跑完全 OK。

## 前提

- macOS（Apple Silicon）。二进制经 Apple Developer ID 签名并公证，下载即可运行。
- 已安装 `claude` CLI（Claude Code）。

## 手动安装

到 [Releases](https://github.com/chenyunguiMilook/vectorshop-cli/releases/latest) 下
`vectorshop-cli-macos-arm64.tar.gz`，解压后整目录运行 `./vectorshop --help`
（二进制与同目录的 `*.bundle` 资源是一个整体，勿单独移动）。
