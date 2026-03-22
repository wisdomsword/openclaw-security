---
name: openclaw-security
version: "2.2.0"
description: "OpenClaw security hardening & monitoring. 9-layer defense, 15 checks, auto-harden, config versioning."
description_zh: "OpenClaw 安全加固与监控。9 层防御、15 项检查、自动加固、配置版本管理。"
tags: [security, audit, hardening, openclaw]
category: security
author: MiniClaw
---

# OpenClaw Security

> 🇨🇳 [中文](./SKILL.zh-CN.md)

## Triggers

`security audit`, `安全审计`, `security hardening`, `安全加固`, `check config security`

## Quick Start

```bash
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security

# Full audit → harden → backup (one command)
bash "$SKILL_DIR/scripts/run.sh"

# Or step by step:
bash "$SKILL_DIR/scripts/audit.sh" --full    # audit only
bash "$SKILL_DIR/scripts/harden.sh"           # audit + auto-fix
bash "$SKILL_DIR/scripts/check-config.sh"     # validate config structure
bash "$SKILL_DIR/scripts/config-backup.sh"    # backup config
```

## What It Does

| Phase | Script | Checks |
|-------|--------|--------|
| 1. Config | `audit.sh --config` | groupPolicy, workspaceOnly, bind, auth, sandbox structure |
| 2. Deep | `audit.sh --full` | credentials, permissions, .gitignore, git history, cron, network |
| 3. Health | `run.sh --full` | credential age, cron coverage, config backup |

## Auto-fix

`harden.sh` auto-fixes (no confirmation needed):
- Directory/file permissions (→ 700/600)
- Config type errors (string→object for sandbox/fs/auth)
- Missing .gitignore
- Config backup

Requires user confirmation: `openclaw.json` field changes, gateway restart, credential rotation.

## Config Safety

`check-config.sh` validates and auto-fixes config structure. Common errors it catches:
- `"sandbox": "off"` → `{ "mode": "off" }`
- `"fs": true` → `{ "workspaceOnly": true }`
- `"auth": "token"` → `{ "mode": "token" }`

Full template: `check-config.sh` shows the correct structure.

## Key Security

**Current model:** `.env` (600) → Gateway loads → env vars → agent tools. `workspaceOnly` protects `read/write/edit` but **NOT `exec`**.

**Defense layers:**
| Layer | Status | Effect |
|-------|--------|--------|
| File perms 600 | ✅ | Only owner reads .env/openclaw.json |
| workspaceOnly | ✅ | Blocks file tools (not exec) |
| Group whitelist | ✅ | Only whitelisted users trigger agent |
| DM pairing | ✅ | Private chats require pairing |
| SecureClaw Rule 8 | ✅ | Blocks read→send exfiltration pattern |
| Exec sandbox | ⏸️ | Off by default (personal use) |

**Sandbox mode (strongest protection):** Isolates exec in sandbox, blocks host file access. Tradeoff: limits `brew install`, `openclaw gateway`, etc.

To enable — **requires owner approval:**
```json
"agents": { "defaults": { "sandbox": { "mode": "all" } } }
```

**Personal assistant threat model:** Single trust boundary, one owner. Current layered defense is sufficient. Only attack path is prompt injection → `cat .env` → message exfiltration, blocked by SecureClaw Rule 8.

## Cron Setup

```bash
openclaw cron add --name openclaw-security --cron "0 3 * * *" --tz Asia/Shanghai \
  --message "Run security audit. Report CRITICAL/HIGH to owner." \
  --session isolated --announce --timeout 180
```

## Severity

| 🔴 CRITICAL | 🟠 HIGH | 🟡 WARN | ✅ PASS |
|---|---|---|---|
| Credential leak, config tampered | Loose perms, network exposed | Missing .gitignore, aging creds | OK |
| → Immediate alert | → Alert + confirm | → Report | → Silent |
