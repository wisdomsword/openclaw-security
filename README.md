# OpenClaw Security Skill 🛡️

OpenClaw 安全加固与持续监控 Skill，覆盖 9 层防御体系、15 项自动检查。

## 功能

- **安全审计** — 15 项自动化安全检查
- **自动加固** — 一键修复常见安全问题
- **配置版本管理** — 带时间戳的配置备份
- **定时监控** — 通过 cron 每日/每周自动检查

## 安装

```bash
# 克隆到 skills 目录
git clone https://github.com/wisdomsword/openclaw-security.git ~/.openclaw/workspace/skills/openclaw-security
```

或通过 ClawHub：
```bash
clawhub install openclaw-security
```

## 使用

### 单次审计
告诉你的 agent：`运行安全审计` 或 `security audit`

### 自动加固
```bash
# 干跑检查（不修改任何文件）
bash scripts/harden.sh --dry-run

# 执行加固
bash scripts/harden.sh
```

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

## 检查项目

### 阶段一：配置安全（7 项）
| 检查 | 说明 |
|------|------|
| groupPolicy | 群聊白名单策略 |
| groupAllowFrom | 白名单用户列表 |
| dmPolicy | 私聊配对策略 |
| workspaceOnly | 文件系统隔离 |
| gateway.bind | Gateway 网络绑定 |
| gateway.auth | Gateway 认证模式 |
| sandbox | 沙箱模式声明 |

### 阶段二：深度审计（6 项）
| 检查 | 说明 |
|------|------|
| 凭据扫描 | Workspace 中 API Key/Token 泄露 |
| 目录权限 | 关键目录 700、文件 600 |
| .gitignore | 敏感文件保护 |
| Git 历史 | 历史提交凭据泄露 |
| Cron 审计 | 定时任务会话隔离 |
| 网络暴露 | Gateway 仅 loopback |

### 阶段三：自动化（2 项）
| 检查 | 说明 |
|------|------|
| 凭据健康 | 凭据文件年龄检查 |
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

## 严重级别

| 级别 | 含义 | 响应 |
|------|------|------|
| 🔴 CRITICAL | 凭据泄露、配置篡改 | 立即通知 |
| 🟠 HIGH | 权限过松、网络暴露 | 通知 + 确认 |
| 🟡 WARN | .gitignore 缺失、凭据老化 | 报告中列出 |
| ✅ PASS | 检查通过 | 静默通过 |

## 许可

MIT
