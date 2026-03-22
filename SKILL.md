---
name: openclaw-security
version: "2.1.0"
description: "OpenClaw security hardening & continuous monitoring. 9-layer defense, 15 automated checks, auto-hardening, config versioning. Supports one-shot audit/harden and daily cron."
description_zh: "OpenClaw 安全加固与持续监控。9 层防御体系、15 项自动检查、自动加固、配置版本管理。支持单次审计/加固和每日定时检查。"
tags: [security, audit, hardening, openclaw, monitoring, credentials, privacy]
category: security
author: MiniClaw
---

# OpenClaw Security Skill

Security hardening and continuous monitoring for OpenClaw. Three phases unified into one skill.

> 🇨🇳 中文文档：[SKILL.zh-CN.md](./SKILL.zh-CN.md)

## Triggers

Activate when user says:
- security audit, security check, 安全审计, 安全检查
- security hardening, 安全加固
- check config security, check credentials

## Path Setup

Scripts live in `skills/openclaw-security/scripts/`.

**Step 1 — resolve the skill path:**

```bash
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security

# Or discover it dynamically:
find ~/.openclaw/workspace/skills -name "SKILL.md" -path "*/openclaw-security/*" -exec dirname {} \;
```

Use `$SKILL_DIR` for all subsequent commands.

## ⚠️ Config Modification Rules (Critical)

**Wrong JSON structure will crash the Gateway. Follow this template exactly.**

### Correct Security Config Template

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

### Common Mistakes

| Wrong | Correct | Why |
|-------|---------|-----|
| `"sandbox": "off"` | `"sandbox": { "mode": "off" }` | sandbox must be object |
| `"sandbox": "inherit"` | `"sandbox": { "mode": "inherit" }` | same |
| `"fs": true` | `"fs": { "workspaceOnly": true }` | fs must be object |
| `"auth": "token"` | `"auth": { "mode": "token", "token": "xxx" }` | auth must be object |

### Safe Edit Procedure

1. **Backup**: `cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak`
2. **Edit**: use `edit` tool for precise replacement — never rewrite the whole file
3. **Validate**: `python3 -c "import json; json.load(open('$HOME/.openclaw/openclaw.json'))"`
4. **Restart**: `openclaw gateway restart`

## Usage

### One-shot

Tell agent: `Run security audit` or `Execute security hardening`

### Daily cron

```bash
openclaw cron add \
  --name "openclaw-security-daily" \
  --cron "0 3 * * *" \
  --tz "Asia/Shanghai" \
  --message "Run OpenClaw security check. Report any CRITICAL or HIGH findings to owner." \
  --session isolated \
  --announce \
  --timeout-seconds 180
```

## Execution Flow

### Phase 1 — Config Security Verification

```bash
bash "$SKILL_DIR/scripts/audit.sh" --config
```

Checks:
- `groupPolicy` = `allowlist`
- `groupAllowFrom` contains owner's open_id
- `dmPolicy` = `pairing`
- `tools.fs.workspaceOnly` = `true`
- `gateway.bind` = `loopback`
- `gateway.auth.mode` = `token`
- `sandbox.mode` is declared (object, not string)

If issues found, ask user before hardening:
```bash
bash "$SKILL_DIR/scripts/harden.sh"
```

### Phase 2 — Deep Security Audit

```bash
bash "$SKILL_DIR/scripts/audit.sh" --full
```

Checks:
1. Credential leak scan — API keys/tokens/passwords in workspace
2. Directory permissions — dirs 700, files 600
3. `.gitignore` validation — sensitive patterns protected
4. Git history scan — secrets in commit history
5. Cron task audit — isolated session usage
6. Network exposure — gateway bound to loopback only
7. Credential age — `.env` older than 90 days

### Phase 3 — Automation & Versioning

1. **Config backup**
```bash
bash "$SKILL_DIR/scripts/config-backup.sh"
```

2. **Credential health** — warn if credentials older than 90 days

3. **Cron coverage** — verify security cron jobs exist

## Report Format

```
## 📊 OpenClaw Security Audit Report

**Time:** YYYY-MM-DD HH:MM
**Result:** ✅ Passed / ⚠️ Issues Found

| Check | Status | Detail |
|-------|--------|--------|
| Config Security | ✅/❌ | ... |
| Credential Scan | ✅/❌ | ... |
| ... | ... | ... |

### Recommendations
- Fix suggestions here
```

Report CRITICAL/HIGH findings immediately — do not wait.

## Auto-fix Policy

**Safe to auto-fix (no confirmation needed):**
- Directory permission tightening (chmod 700/600)
- Config structure type errors (string → object)
- Config backup

**Requires user confirmation:**
- Modifying `openclaw.json` fields
- Gateway restart
- Credential rotation

## Severity Levels

| Level | Meaning | Response |
|-------|---------|----------|
| 🔴 CRITICAL | Credential leak, config tampered | Immediate alert + fix suggestion |
| 🟠 HIGH | Loose permissions, network exposed | Alert + wait for confirmation |
| 🟡 WARN | Missing .gitignore, aging credentials | Report only |
| ✅ PASS | Check passed | Silent |
