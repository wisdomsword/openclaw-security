---
name: openclaw-security
version: "2.0.2"
description: OpenClaw 安全加固与监控 Skill。覆盖 9 层防御体系：群聊白名单、文件隔离、DM 配对、网络隔离、隐私隔离、目录权限、Cron 隔离、自动审计、配置版本管理。支持单次审计/加固、每日定时检查。
tags: [security, audit, hardening, openclaw, monitoring, credentials, privacy]
category: security
author: MiniClaw
---

# OpenClaw Security Skill

OpenClaw 安全加固与持续监控。三阶段方案融合为一个 Skill。

## 触发条件

当用户说以下关键词时激活此 Skill：
- 安全审计、安全检查、security audit
- 安全加固、security hardening
- 检查配置安全、检查凭据

## ⚠️ 路径说明

本 Skill 的脚本位于 `skills/openclaw-security/scripts/` 目录下。

**第一步：确定脚本路径**

执行以下命令找到本 SKILL.md 所在目录：
```bash
# 方法 1：如果知道 workspace 路径
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security

# 方法 2：通过 find 查找
find ~/.openclaw/workspace/skills -name "SKILL.md" -path "*/openclaw-security/*" -exec dirname {} \;
```

后续所有命令使用 `$SKILL_DIR` 变量代替路径。

## 使用方式

### 单次运行

告诉 agent：`运行安全审计` 或 `执行安全加固`

### 每日定时检查

通过 cron 添加每日任务：
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

按以下顺序执行三个阶段：

### 阶段一：配置安全校验

**1. 设置路径：**
```bash
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security
```

**2. 运行审计：**
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
- `sandbox.mode` 已声明

如发现问题，询问用户是否执行加固：
```bash
bash "$SKILL_DIR/scripts/harden.sh"
```

### 阶段二：深度安全审计

```bash
bash "$SKILL_DIR/scripts/audit.sh" --full
```

检查项：
1. **凭据泄露扫描** — Workspace 中是否有 API Key/Token/密码泄露
2. **目录权限检查** — 关键目录 700、关键文件 600
3. **.gitignore 验证** — 敏感文件模式是否受保护
4. **Git 历史扫描** — 历史提交中是否有凭据
5. **Cron 任务审计** — 定时任务是否使用 isolated session
6. **网络暴露检查** — Gateway 是否仅绑定 loopback
7. **隐私数据审查** — MEMORY.md 是否可能在群聊中泄露

### 阶段三：自动化与版本管理

1. **配置版本备份**
```bash
bash "$SKILL_DIR/scripts/config-backup.sh"
```

2. **凭据健康检查** — 检查凭据文件年龄，超过 90 天提醒轮换

3. **确认定时任务存在** — 检查是否已配置每日/每周安全 cron

## 报告格式

执行完成后，生成报告并发送给用户：

```
## 📊 OpenClaw 安全审计报告

**时间：** YYYY-MM-DD HH:MM
**结果：** ✅ 通过 / ⚠️ 存在问题

### 审计结果
| 检查项 | 状态 | 说明 |
|--------|------|------|
| 配置安全 | ✅/❌ | ... |
| 凭据扫描 | ✅/❌ | ... |
| 目录权限 | ✅/❌ | ... |
| ... | ... | ... |

### 九层防御体系
- ✅ 第1层：群聊白名单
- ✅ 第2层：文件隔离
- ...

### 建议
- 如有发现，列出具体修复建议
```

如有 CRITICAL/HIGH 发现，立即通知用户，不要等待。

## 自动修复

仅自动修复以下低风险项目（无需确认）：
- 目录权限收紧（chmod 700/600）
- 配置备份

以下操作需用户确认：
- 修改 openclaw.json 配置
- 重启 Gateway
- 轮换凭据

## 严重级别定义

| 级别 | 含义 | 响应 |
|------|------|------|
| 🔴 CRITICAL | 凭据泄露、配置被篡改 | 立即通知 + 建议修复 |
| 🟠 HIGH | 权限过松、网络暴露 | 通知 + 等待确认 |
| 🟡 WARN | .gitignore 缺失、凭据老化 | 报告中列出 |
| ✅ PASS | 检查通过 | 静默通过 |
