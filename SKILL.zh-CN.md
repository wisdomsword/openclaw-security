---
name: openclaw-security
version: "2.1.0"
description: "OpenClaw 安全加固与持续监控。9 层防御体系、15 项自动检查、自动加固、配置版本管理。支持单次审计/加固和每日定时检查。"
tags: [security, audit, hardening, openclaw, monitoring, credentials, privacy]
category: security
author: MiniClaw
---

# OpenClaw Security Skill（中文版）

OpenClaw 安全加固与持续监控。三阶段方案融合为一个 Skill。

> 🇬🇧 English: [SKILL.md](./SKILL.md)

## 触发条件

当用户说以下关键词时激活：
- 安全审计、安全检查、security audit、security check
- 安全加固、security hardening
- 检查配置安全、检查凭据

## 路径说明

脚本位于 `skills/openclaw-security/scripts/` 目录下。

**第一步 — 确定路径：**

```bash
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security

# 或动态查找：
find ~/.openclaw/workspace/skills -name "SKILL.md" -path "*/openclaw-security/*" -exec dirname {} \;
```

后续所有命令使用 `$SKILL_DIR`。

## ⚠️ 配置修改规范（关键）

**错误的 JSON 结构会导致 Gateway 崩溃。严格遵循以下模板。**

### 安全配置正确模板

```json
{
  "channels": {
    "feishu": {
      "groupPolicy": "allowlist",
      "groupAllowFrom": ["ou_xxxxxxxxxxxxxxxx"],
      "dmPolicy": "pairing"
    }
  },
  "tools": {
    "profile": "full",
    "fs": {
      "workspaceOnly": true
    }
  },
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "off"
      }
    }
  },
  "gateway": {
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "your-token-here"
    }
  }
}
```

### 常见错误

| 错误写法 | 正确写法 | 原因 |
|---------|---------|------|
| `"sandbox": "off"` | `"sandbox": { "mode": "off" }` | sandbox 必须是对象 |
| `"sandbox": "inherit"` | `"sandbox": { "mode": "inherit" }` | 同上 |
| `"fs": true` | `"fs": { "workspaceOnly": true }` | fs 必须是对象 |
| `"auth": "token"` | `"auth": { "mode": "token", "token": "xxx" }` | auth 必须是对象 |

### 安全编辑流程

1. **备份**：`cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak`
2. **修改**：使用 `edit` 工具精确替换，不要重写整个文件
3. **验证**：`python3 -c "import json; json.load(open('$HOME/.openclaw/openclaw.json'))"`
4. **重启**：`openclaw gateway restart`

## 使用方式

### 单次运行

告诉 agent：`运行安全审计` 或 `执行安全加固`

### 每日定时检查

```bash
openclaw cron add \
  --name "openclaw-security-daily" \
  --cron "0 3 * * *" \
  --tz "Asia/Shanghai" \
  --message "运行 OpenClaw 安全检查，如有 CRITICAL 或 HIGH 问题报告给主人" \
  --session isolated \
  --announce \
  --timeout-seconds 180
```

## 执行流程

### 阶段一 — 配置安全校验

```bash
bash "$SKILL_DIR/scripts/audit.sh" --config
```

检查项：
- `groupPolicy` = `allowlist`（群聊白名单）
- `groupAllowFrom` 包含主人 open_id
- `dmPolicy` = `pairing`（私聊配对）
- `tools.fs.workspaceOnly` = `true`（文件隔离）
- `gateway.bind` = `loopback`（网络隔离）
- `gateway.auth.mode` = `token`（Token 认证）
- `sandbox.mode` 已声明（必须是对象，不能是字符串）

如发现问题，询问用户是否执行加固：
```bash
bash "$SKILL_DIR/scripts/harden.sh"
```

### 阶段二 — 深度安全审计

```bash
bash "$SKILL_DIR/scripts/audit.sh" --full
```

检查项：
1. **凭据泄露扫描** — Workspace 中是否存在 API Key/Token/密码
2. **目录权限检查** — 关键目录 700、关键文件 600
3. **.gitignore 验证** — 敏感文件模式是否受保护
4. **Git 历史扫描** — 历史提交中是否有凭据
5. **Cron 任务审计** — 定时任务是否使用 isolated session
6. **网络暴露检查** — Gateway 是否仅绑定 loopback
7. **凭据健康检查** — .env 文件是否超过 90 天

### 阶段三 — 自动化与版本管理

1. **配置版本备份**
```bash
bash "$SKILL_DIR/scripts/config-backup.sh"
```

2. **凭据健康** — 超过 90 天提醒轮换

3. **Cron 覆盖** — 确认安全定时任务已配置

## 报告格式

```
## 📊 OpenClaw 安全审计报告

**时间：** YYYY-MM-DD HH:MM
**结果：** ✅ 通过 / ⚠️ 存在问题

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 配置安全 | ✅/❌ | ... |
| 凭据扫描 | ✅/❌ | ... |
| ... | ... | ... |

### 建议
- 具体修复建议
```

发现 CRITICAL/HIGH 问题时，立即通知用户，不要等待。

## 自动修复策略

**可自动修复（无需确认）：**
- 目录权限收紧（chmod 700/600）
- 配置结构类型错误（字符串 → 对象）
- 配置备份

**需要用户确认：**
- 修改 `openclaw.json` 字段
- 重启 Gateway
- 轮换凭据

## 严重级别

| 级别 | 含义 | 响应 |
|------|------|------|
| 🔴 CRITICAL | 凭据泄露、配置被篡改 | 立即通知 + 修复建议 |
| 🟠 HIGH | 权限过松、网络暴露 | 通知 + 等待确认 |
| 🟡 WARN | .gitignore 缺失、凭据老化 | 仅报告 |
| ✅ PASS | 检查通过 | 静默 |
