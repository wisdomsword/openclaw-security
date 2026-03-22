#!/bin/bash
# OpenClaw Security Audit Script
# Usage: bash audit.sh [--config|--full|--quick]
#   --config  Phase 1: Config security verification only
#   --full    Phase 1+2: Full audit (default)
#   --quick   Alias for --full

set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
WORKSPACE="$OPENCLAW_DIR/workspace"
CONFIG="$OPENCLAW_DIR/openclaw.json"
MODE="${1:---full}"

CRITICAL=0
HIGH=0
WARN=0
PASS=0
FINDINGS=""

log() {
    local severity="$1" check="$2" detail="$3"
    case "$severity" in
        CRITICAL) CRITICAL=$((CRITICAL+1)); FINDINGS+="🔴 [$severity] $check: $detail\n" ;;
        HIGH)     HIGH=$((HIGH+1));       FINDINGS+="🟠 [$severity] $check: $detail\n" ;;
        WARN)     WARN=$((WARN+1));       FINDINGS+="🟡 [$severity] $check: $detail\n" ;;
        PASS)     PASS=$((PASS+1));       FINDINGS+="✅ [$severity] $check: $detail\n" ;;
    esac
}

# ═══════════════════════════════════════
# Phase 1: Configuration Security
# ═══════════════════════════════════════
check_config() {
    echo "═══ Phase 1: Configuration Security ═══"

    if [ ! -f "$CONFIG" ]; then
        log CRITICAL "Config File" "openclaw.json not found at $CONFIG"
        return
    fi

    python3 - "$CONFIG" <<'PYEOF'
import json, sys

config_path = sys.argv[1]
with open(config_path) as f:
    d = json.load(f)

ch = d.get("channels", {}).get("feishu", {})
tools = d.get("tools", {})
agents = d.get("agents", {}).get("defaults", {})
gw = d.get("gateway", {})

checks = {
    "groupPolicy=allowlist": ch.get("groupPolicy") == "allowlist",
    "groupAllowFrom not empty": len(ch.get("groupAllowFrom", [])) > 0,
    "dmPolicy=pairing": ch.get("dmPolicy") == "pairing",
    "workspaceOnly=true": tools.get("fs", {}).get("workspaceOnly") is True,
    "gateway.bind=loopback": gw.get("bind") == "loopback",
    "gateway.auth=token": gw.get("auth", {}).get("mode") == "token",
    "sandbox declared": "sandbox" in agents,
}

for name, ok in checks.items():
    if ok:
        print(f"PASS|{name}|OK")
    else:
        print(f"HIGH|{name}|Not configured or incorrect value")
PYEOF

    while IFS='|' read -r severity check detail; do
        log "$severity" "Config: $check" "$detail"
    done < <(python3 - "$CONFIG" <<'PYEOF'
import json, sys
config_path = sys.argv[1]
with open(config_path) as f:
    d = json.load(f)
ch = d.get("channels", {}).get("feishu", {})
tools = d.get("tools", {})
agents = d.get("agents", {}).get("defaults", {})
gw = d.get("gateway", {})
checks = {
    "groupPolicy=allowlist": ch.get("groupPolicy") == "allowlist",
    "groupAllowFrom not empty": len(ch.get("groupAllowFrom", [])) > 0,
    "dmPolicy=pairing": ch.get("dmPolicy") == "pairing",
    "workspaceOnly=true": tools.get("fs", {}).get("workspaceOnly") is True,
    "gateway.bind=loopback": gw.get("bind") == "loopback",
    "gateway.auth=token": gw.get("auth", {}).get("mode") == "token",
    "sandbox declared": "sandbox" in agents,
}
for name, ok in checks.items():
    severity = "PASS" if ok else "HIGH"
    detail = "OK" if ok else "Not configured or incorrect value"
    print(f"{severity}|{name}|{detail}")
PYEOF
    )
}

# ═══════════════════════════════════════
# Phase 2: Deep Security Audit
# ═══════════════════════════════════════
check_credentials() {
    echo "═══ Phase 2a: Credential Scan ═══"
    local leaks
    leaks=$(grep -rn -E "(sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|ghp_[a-zA-Z0-9]{36}|xoxb-[a-zA-Z0-9-]{20,}|-----BEGIN (RSA |OPENSSH )?PRIVATE KEY-----)" \
        "$WORKSPACE/" --include="*.md" --include="*.json" --include="*.txt" --include="*.yaml" --include="*.yml" \
        2>/dev/null | grep -v "SKILL.md" | grep -v "skills/" | grep -v "audit\.sh" || true)

    if [ -n "$leaks" ]; then
        log CRITICAL "Credential Scan" "Found potential secrets in workspace!"
        echo "$leaks" | while read -r line; do
            echo "  ⚠️  $line"
        done
    else
        log PASS "Credential Scan" "No leaked credentials found"
    fi

    # Scan for password patterns
    local pw_leaks
    pw_leaks=$(grep -rn -iE "(password|passwd|secret|api.key)\s*[:=]\s*['\"][a-zA-Z0-9+/]{8,}" \
        "$WORKSPACE/" --include="*.md" --include="*.json" --include="*.txt" \
        2>/dev/null | grep -v "SKILL.md" | grep -v "skills/" || true)

    if [ -n "$pw_leaks" ]; then
        log CRITICAL "Password Scan" "Found password patterns in workspace!"
    else
        log PASS "Password Scan" "No password patterns found"
    fi
}

check_permissions() {
    echo "═══ Phase 2b: Directory/File Permissions ═══"
    local all_ok=true

    for d in "$OPENCLAW_DIR/credentials" "$OPENCLAW_DIR/identity" \
             "$OPENCLAW_DIR/logs" "$OPENCLAW_DIR/browser" "$WORKSPACE/memory"; do
        if [ -d "$d" ]; then
            local perm
            perm=$(stat -f "%Sp" "$d" 2>/dev/null)
            if [ "$perm" != "drwx------" ]; then
                log HIGH "Dir Permission" "$d is $perm (should be drwx------)"
                all_ok=false
                # Auto-fix
                chmod 700 "$d" 2>/dev/null && echo "  🔧 Auto-fixed: $d → drwx------"
            fi
        fi
    done

    for f in "$CONFIG" "$OPENCLAW_DIR/.env"; do
        if [ -f "$f" ]; then
            local perm
            perm=$(stat -f "%Sp" "$f" 2>/dev/null)
            if [ "$perm" != "-rw-------" ]; then
                log HIGH "File Permission" "$f is $perm (should be -rw-------)"
                all_ok=false
                chmod 600 "$f" 2>/dev/null && echo "  🔧 Auto-fixed: $f → -rw-------"
            fi
        fi
    done

    if $all_ok; then
        log PASS "Permissions" "All directory/file permissions correct"
    fi
}

check_gitignore() {
    echo "═══ Phase 2c: Gitignore Verification ═══"
    local gitignore="$WORKSPACE/.gitignore"
    local all_ok=true

    if [ ! -f "$gitignore" ]; then
        log HIGH "Gitignore" ".gitignore does not exist!"
        all_ok=false
    else
        for p in "*.env" "memory/" "MEMORY.md" "*.pem" "*.key"; do
            if ! grep -q "$p" "$gitignore" 2>/dev/null; then
                log WARN "Gitignore" "Missing pattern: $p"
                all_ok=false
            fi
        done
    fi

    if $all_ok; then
        log PASS "Gitignore" "All sensitive patterns protected"
    fi
}

check_git_history() {
    echo "═══ Phase 2d: Git History Scan ═══"
    if [ ! -d "$WORKSPACE/.git" ]; then
        log PASS "Git History" "No git repo — no history risk"
        return
    fi

    local commit_count
    commit_count=$(cd "$WORKSPACE" && git rev-list --count HEAD 2>/dev/null || echo "0")
    if [ "$commit_count" = "0" ]; then
        log PASS "Git History" "No commits yet — clean"
        return
    fi

    local secrets
    secrets=$(cd "$WORKSPACE" && git log --all -p 2>/dev/null | \
        grep -iE "(sk-[a-zA-Z0-9]{20,}|password\s*[:=]|secret\s*[:=]|token\s*[:=])" | \
        grep -v "SKILL.md" | grep -v "skills/" | head -5 || true)

    if [ -n "$secrets" ]; then
        log CRITICAL "Git History" "Found secrets in git history — rotate immediately!"
    else
        log PASS "Git History" "No secrets found in commit history"
    fi
}

check_cron_tasks() {
    echo "═══ Phase 2e: Cron Task Audit ═══"
    local cron_output
    cron_output=$(openclaw cron list 2>/dev/null || echo "")

    if [ -z "$cron_output" ]; then
        log WARN "Cron Audit" "Cannot list cron tasks"
        return
    fi

    # Check each task uses isolated session
    echo "$cron_output" | grep -v "^ID" | grep -v "^$" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            local name
            name=$(echo "$line" | awk '{print $2}')
            if echo "$line" | grep -q "isolated"; then
                log PASS "Cron: $name" "Uses isolated session ✅"
            elif echo "$line" | grep -q "main"; then
                log WARN "Cron: $name" "Uses main session — consider isolated"
            fi
        fi
    done
}

check_network() {
    echo "═══ Phase 2f: Network Exposure ═══"
    python3 - "$CONFIG" <<'PYEOF' | while IFS='|' read -r severity check detail; do
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
gw = d.get("gateway", {})
bind = gw.get("bind", "unknown")
if bind == "loopback":
    print(f"PASS|Gateway Binding|Bound to loopback only")
else:
    print(f"HIGH|Gateway Binding|Bound to: {bind} (should be loopback)")
auth = gw.get("auth", {}).get("mode", "unknown")
if auth == "token":
    token = gw.get("auth", {}).get("token", "")
    if len(token) >= 32:
        print(f"PASS|Gateway Auth|Token mode, {len(token)} chars")
    else:
        print(f"HIGH|Gateway Auth|Token too short: {len(token)} chars")
else:
    print(f"WARN|Gateway Auth|Mode: {auth} (recommend token)")
PYEOF
        log "$severity" "$check" "$detail"
    done
}

# ═══════════════════════════════════════
# Phase 3: Credential Health & Backup
# ═══════════════════════════════════════
check_credential_age() {
    echo "═══ Phase 3a: Credential Age Check ═══"
    local env_age
    env_age=$(( ($(date +%s) - $(stat -f "%m" "$OPENCLAW_DIR/.env" 2>/dev/null || echo "0")) / 86400 ))

    if [ "$env_age" -gt 90 ]; then
        log WARN "Credential Age" ".env is ${env_age} days old — consider rotation"
    elif [ "$env_age" -gt 180 ]; then
        log HIGH "Credential Age" ".env is ${env_age} days old — rotate now!"
    else
        log PASS "Credential Age" ".env is ${env_age} days old — fresh"
    fi
}

check_cron_coverage() {
    echo "═══ Phase 3b: Cron Coverage Check ═══"
    local cron_list
    cron_list=$(openclaw cron list 2>/dev/null || echo "")

    local has_security=false has_backup=false
    if echo "$cron_list" | grep -q "security"; then
        has_security=true
    fi
    if echo "$cron_list" | grep -q "backup"; then
        has_backup=true
    fi

    if $has_security; then
        log PASS "Security Cron" "Security audit cron exists"
    else
        log WARN "Security Cron" "No security audit cron — consider adding daily check"
    fi

    if $has_backup; then
        log PASS "Backup Cron" "Config backup cron exists"
    else
        log WARN "Backup Cron" "No config backup cron — consider adding monthly backup"
    fi
}

# ═══════════════════════════════════════
# Report
# ═══════════════════════════════════════
generate_report() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "  OpenClaw Security Audit Report"
    echo "  $(date '+%Y-%m-%d %H:%M %Z')"
    echo "═══════════════════════════════════════"
    echo ""
    echo -e "$FINDINGS"
    echo "───────────────────────────────────────"
    echo "  🔴 Critical: $CRITICAL"
    echo "  🟠 High:     $HIGH"
    echo "  🟡 Warning:  $WARN"
    echo "  ✅ Passed:   $PASS"
    echo "───────────────────────────────────────"

    # Save to file
    local report_file="$WORKSPACE/memory/security-audit-$(date +%Y-%m-%d).md"
    mkdir -p "$WORKSPACE/memory"
    {
        echo "# Security Audit — $(date '+%Y-%m-%d %H:%M')"
        echo ""
        echo "| Level | Count |"
        echo "|-------|-------|"
        echo "| 🔴 Critical | $CRITICAL |"
        echo "| 🟠 High | $HIGH |"
        echo "| 🟡 Warning | $WARN |"
        echo "| ✅ Passed | $PASS |"
        echo ""
        echo "## Findings"
        echo ""
        echo -e "$FINDINGS"
    } > "$report_file"
    echo "📄 Report saved: $report_file"

    # Exit code
    if [ "$CRITICAL" -gt 0 ]; then
        echo ""
        echo "🔴 RESULT: CRITICAL issues found!"
        exit 2
    elif [ "$HIGH" -gt 0 ]; then
        echo ""
        echo "🟠 RESULT: HIGH issues found."
        exit 1
    else
        echo ""
        echo "✅ RESULT: All checks passed."
        exit 0
    fi
}

# ═══════════════════════════════════════
# Main
# ═══════════════════════════════════════
main() {
    echo "🔒 OpenClaw Security Audit — Mode: $MODE"
    echo "   Started: $(date '+%Y-%m-%d %H:%M')"
    echo ""

    # Phase 1 always runs
    check_config

    if [ "$MODE" = "--full" ] || [ "$MODE" = "--quick" ]; then
        check_credentials
        check_permissions
        check_gitignore
        check_git_history
        check_cron_tasks
        check_network
        check_credential_age
        check_cron_coverage
    fi

    generate_report
}

main
