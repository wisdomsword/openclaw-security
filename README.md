# OpenClaw Security Skill 🛡️

Security hardening & continuous monitoring for OpenClaw. 9-layer defense, 15 automated checks, auto-hardening, config versioning.

> 🇨🇳 [中文文档](./SKILL.zh-CN.md)

## Install

```bash
git clone https://github.com/wisdomsword/openclaw-security.git ~/.openclaw/workspace/skills/openclaw-security
```

## Quick Start

```bash
SKILL_DIR=~/.openclaw/workspace/skills/openclaw-security

# Full audit (15 checks)
bash "$SKILL_DIR/scripts/audit.sh" --full

# Auto-hardening (dry run first)
bash "$SKILL_DIR/scripts/harden.sh" --dry-run
bash "$SKILL_DIR/scripts/harden.sh"

# Config backup
bash "$SKILL_DIR/scripts/config-backup.sh"
```

## What It Checks

### Phase 1 — Config Security (7 checks)
| Check | Description |
|-------|-------------|
| groupPolicy | Group chat whitelist policy |
| groupAllowFrom | Whitelisted user list |
| dmPolicy | DM pairing policy |
| workspaceOnly | Filesystem isolation |
| gateway.bind | Gateway network binding |
| gateway.auth | Gateway auth mode |
| sandbox | Sandbox mode declaration |

### Phase 2 — Deep Audit (6 checks)
| Check | Description |
|-------|-------------|
| Credential Scan | API keys/tokens in workspace |
| Directory Permissions | Dirs 700, files 600 |
| .gitignore | Sensitive file patterns |
| Git History | Secrets in commit history |
| Cron Audit | Isolated session usage |
| Network | Gateway loopback only |

### Phase 3 — Automation (2 checks)
| Check | Description |
|-------|-------------|
| Credential Age | .env file older than 90 days |
| Cron Coverage | Security cron jobs exist |

## 9-Layer Defense

```
Layer 1: Group chat whitelist (groupPolicy: allowlist)
Layer 2: File isolation (workspaceOnly: true)
Layer 3: DM pairing (dmPolicy: pairing)
Layer 4: Network isolation (bind: loopback)
Layer 5: Privacy isolation (MEMORY.md main-session only)
Layer 6: Directory permissions (700/600)
Layer 7: Cron isolation (isolated session)
Layer 8: Auto-audit (periodic CRITICAL/HIGH detection)
Layer 9: Config versioning (backup + rollback)
```

## Severity Levels

| Level | Meaning | Response |
|-------|---------|----------|
| 🔴 CRITICAL | Credential leak, config tampered | Immediate alert |
| 🟠 HIGH | Loose permissions, network exposed | Alert + confirmation |
| 🟡 WARN | Missing .gitignore, aging creds | Report only |
| ✅ PASS | Check passed | Silent |

## License

MIT
