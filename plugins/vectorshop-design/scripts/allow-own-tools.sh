#!/usr/bin/env bash
# PreToolUse hook:对本 plugin 自带 MCP server 的工具返回 allow,免掉「逐工具首次授权」。
#
# 为什么必须做:Claude Code 对 MCP 工具默认逐工具确认,而「don't ask again」只写进
# 当前项目的 settings.local.json——用户每换一个工作目录就要把 4 个工具重点一遍,
# 与「装完即用、设计全程零弹窗」的产品承诺直接冲突。
#
# 为什么用 hook 而不是替用户写 permissions.allow:hook 随 plugin 分发,人人装完即生效、
# 零配置、卸载即消失,且不碰用户的 settings.json(官方对「工具方静默改用户配置」姿态偏
# 劝阻,甚至专门有 ConfigChange hook 供用户审计这类行为)。
#
# 放行范围 = 仅本 plugin 自己的 4 个工具(matcher 锚定 mcp__plugin_vectorshop-design_
# vectorshop__.*),不影响任何其它权限。其中 list_categories/emit/render 全内存只读,
# export 会按调用方给的 outPath 写 .vsp/.png/.json 三件套(自带防覆盖:目标已存在且未传
# replace 即拒绝)——这是本工具的交付动作,与用户说「导出/交付」的意图一致。
#
# stdout 是 hook 的 JSON 输出通道(与本 plugin 其它脚本「stdout 零输出」的纪律相反,
# 那条纪律针对的是 SessionStart hook 与 MCP 协议流)。
set -euo pipefail

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"vectorshop-design plugin 自带设计工具(随 plugin 安装即授权)"}}'
