# OpenClaw Security Skill 🛡️

OpenClaw 安全加固与持续监控。9 层防御体系、15 项自动检查、自动加固、配置版本管理。

> 🇬🇧 [English](./README.md) | 📖 [中文文档](./SKILL.zh-CN.md)

## 安装

```bash
git clone https://github.com/wisdomsword/openclaw-security.git ~/.openclaw/workspace/skills/openclaw-security
```

## 快速开始

```bash
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security

# 完整审计（15 项检查）
bash "$SKILL_DIR/scripts/audit.sh" --full

# 自动加固（先干跑）
bash "$SKILL_DIR/scripts/harden.sh" --dry-run
bash "$SKILL_DIR/scripts/harden.sh"

# 配置备份
bash "$SKILL_DIR/scripts/config-backup.sh"
```

## 检查项目

### 阶段一 — 配置安全（7 项）
| 检查 | 说明 |
|------|------|
| groupPolicy | 群聊白名单策略 |
| groupAllowFrom | 白名单用户列表 |
| dmPolicy | 私聊配对策略 |
| workspaceOnly | 文件系统隔离 |
| gateway.bind | Gateway 网络绑定 |
| gateway.auth | Gateway 认证模式 |
| sandbox | 沙箱模式声明 |

### 阶段二 — 深度审计（6 项）
| 检查 | 说明 |
|------|------|
| 凭据扫描 | Workspace 中 API Key/Token 泄露 |
| 目录权限 | 关键目录 700、文件 600 |
| .gitignore | 敏感文件保护 |
| Git 历史 | 历史提交凭据泄露 |
| Cron 审计 | 定时任务会话隔离 |
| 网络暴露 | Gateway 仅 loopback |

### 阶段三 — 自动化（2 项）
| 检查 | 说明 |
|------|------|
| 凭据健康 | .env 文件超过 90 天 |
| Cron 覆盖 | 安全定时任务是否存在 |

## 九层防御体系

```
第1层：群聊白名单 (groupPolicy: allowlist)
第2层：文件隔离 (workspaceOnly: true)
第3层：DM 配对 (dmPolicy: pairing)
第4层：网络隔离 (bind: loopback)
第5层：隐私隔离 (MEMORY.md 仅主会话)
第6层：目录权限 (700/600)
第7层：Cron 隔离 (isolated session)
第8层：自动审计 (定期 CRITICAL/HIGH 检测)
第9层：配置版本管理 (备份 + 回滚)
```

## 许可

MIT
