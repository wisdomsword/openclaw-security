---
name: openclaw-security
version: "2.2.0"
description: "OpenClaw 安全加固与监控。9 层防御、15 项检查、自动加固、配置版本管理。"
tags: [security, audit, hardening, openclaw]
category: security
author: MiniClaw
---

# OpenClaw Security（中文）

> 🇬🇧 [English](./SKILL.md)

## 触发词

`安全审计`, `安全检查`, `安全加固`, `security audit`, `security hardening`

## 快速开始

```bash
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security

# 完整流程：审计 → 加固 → 备份（一条命令）
bash "$SKILL_DIR/scripts/run.sh"

# 或分步执行：
bash "$SKILL_DIR/scripts/audit.sh" --full    # 仅审计
bash "$SKILL_DIR/scripts/harden.sh"           # 审计 + 自动修复
bash "$SKILL_DIR/scripts/check-config.sh"     # 验证配置结构
bash "$SKILL_DIR/scripts/config-backup.sh"    # 备份配置
```

## 功能

| 阶段 | 脚本 | 检查项 |
|------|------|--------|
| 1. 配置 | `audit.sh --config` | groupPolicy, workspaceOnly, bind, auth, sandbox 结构 |
| 2. 深度 | `audit.sh --full` | 凭据、权限、.gitignore、Git 历史、Cron、网络 |
| 3. 健康 | `run.sh --full` | 凭据年龄、Cron 覆盖、配置备份 |

## 自动修复

`harden.sh` 可自动修复（无需确认）：
- 目录/文件权限（→ 700/600）
- 配置类型错误（sandbox/fs/auth 字符串→对象）
- 缺失 .gitignore
- 配置备份

需用户确认：修改 `openclaw.json`、重启 Gateway、轮换凭据。

## 配置安全

`check-config.sh` 验证并自动修复配置结构。常见错误：
- `"sandbox": "off"` → `{ "mode": "off" }`
- `"fs": true` → `{ "workspaceOnly": true }`
- `"auth": "token"` → `{ "mode": "token" }`

## 定时任务

```bash
openclaw cron add --name openclaw-security --cron "0 3 * * *" --tz Asia/Shanghai \
  --message "运行安全审计，CRITICAL/HIGH 问题报告主人" \
  --session isolated --announce --timeout 180
```

## 严重级别

| 🔴 CRITICAL | 🟠 HIGH | 🟡 WARN | ✅ PASS |
|---|---|---|---|
| 凭据泄露、配置篡改 | 权限过松、网络暴露 | .gitignore 缺失、凭据老化 | 正常 |
| → 立即通知 | → 通知确认 | → 仅报告 | → 静默 |
