#!/bin/bash
# OpenClaw Security Audit Script
# Cross-platform: macOS + Linux
# Usage: bash audit.sh [--config|--full|--quick]
#   --config  Phase 1: Config security verification only
#   --full    Phase 1+2: Full audit (default)
#   --quick   Alias for --full

set -uo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
WORKSPACE="$OPENCLAW_DIR/workspace"
CONFIG="$OPENCLAW_DIR/openclaw.json"
MODE="${1:---full}"

CRITICAL=0
HIGH=0
WARN=0
PASS=0
FINDINGS=""
ERRORS=""

# ═══════════════════════════════════════
# Cross-platform helpers
# ═══════════════════════════════════════
get_perm() {
    # Cross-platform permission check (macOS: stat -f, Linux: stat -c)
    if stat -f "%Sp" "$1" 2>/dev/null; then
        return 0
    elif stat -c "%A" "$1" 2>/dev/null; then
        return 0
    else
        echo "UNKNOWN"
        return 1
    fi
}

get_age_days() {
    # Cross-platform file age in days
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "-1"
        return
    fi
    local mtime
    if mtime=$(stat -f "%m" "$file" 2>/dev/null); then
        : # macOS
    elif mtime=$(stat -c "%Y" "$file" 2>/dev/null); then
        : # Linux
    else
        echo "-1"
        return
    fi
    local now
    now=$(date +%s)
    echo $(( (now - mtime) / 86400 ))
}

log() {
    local severity="$1" check="$2" detail="$3"
    case "$severity" in
        CRITICAL) CRITICAL=$((CRITICAL+1)); FINDINGS+="🔴 **$check**: $detail\n" ;;
        HIGH)     HIGH=$((HIGH+1));       FINDINGS+="🟠 **$check**: $detail\n" ;;
        WARN)     WARN=$((WARN+1));       FINDINGS+="🟡 **$check**: $detail\n" ;;
        PASS)     PASS=$((PASS+1));       FINDINGS+="✅ **$check**: $detail\n" ;;
        ERROR)    ERRORS+="⚠️ **$check**: $detail\n" ;;
    esac
}

# ═══════════════════════════════════════
# Pre-flight checks
# ═══════════════════════════════════════
preflight() {
    local ok=true

    if [ ! -d "$OPENCLAW_DIR" ]; then
        log CRITICAL "Pre-flight" "OpenClaw directory not found: $OPENCLAW_DIR"
        ok=false
    fi

    if [ ! -f "$CONFIG" ]; then
        log CRITICAL "Pre-flight" "Config file not found: $CONFIG"
        ok=false
    fi

    if ! command -v python3 &>/dev/null; then
        log ERROR "Pre-flight" "python3 not found — config checks will be skipped"
    fi

    if ! command -v openclaw &>/dev/null; then
        log ERROR "Pre-flight" "openclaw CLI not in PATH — cron checks will be skipped"
    fi

    if [ "$ok" = false ]; then
        generate_report
        exit 2
    fi
}

# ═══════════════════════════════════════
# Phase 1: Configuration Security
# ═══════════════════════════════════════
check_config() {
    echo "═══ Phase 1: Configuration Security ═══" >&2

    if ! command -v python3 &>/dev/null; then
        log ERROR "Config" "python3 unavailable — skipping config checks"
        return
    fi

    local config_results
    config_results=$(python3 - "$CONFIG" <<'PYEOF'
import json, sys
config_path = sys.argv[1]
try:
    with open(config_path) as f:
        d = json.load(f)
except Exception as e:
    print(f"CRITICAL|Config Parse|Failed to read config: {e}")
    sys.exit(0)

ch = d.get("channels", {}).get("feishu", {})
tools = d.get("tools", {})
agents = d.get("agents", {}).get("defaults", {})
gw = d.get("gateway", {})

checks = [
    ("groupPolicy=allowlist", ch.get("groupPolicy") == "allowlist"),
    ("groupAllowFrom not empty", len(ch.get("groupAllowFrom", [])) > 0),
    ("dmPolicy=pairing", ch.get("dmPolicy") == "pairing"),
    ("workspaceOnly=true", tools.get("fs", {}).get("workspaceOnly") is True),
    ("gateway.bind=loopback", gw.get("bind") == "loopback"),
    ("gateway.auth=token", gw.get("auth", {}).get("mode") == "token"),
    ("sandbox declared", "sandbox" in agents),
]

for name, ok in checks:
    severity = "PASS" if ok else "HIGH"
    detail = "OK" if ok else "Not configured or incorrect value"
    print(f"{severity}|Config: {name}|{detail}")
PYEOF
    )

    while IFS='|' read -r severity check detail; do
        [ -z "$severity" ] && continue
        log "$severity" "$check" "$detail"
    done <<< "$config_results"
}

# ═══════════════════════════════════════
# Phase 2: Deep Security Audit
# ═══════════════════════════════════════
check_credentials() {
    echo "═══ Phase 2a: Credential Scan ═══" >&2

    if [ ! -d "$WORKSPACE" ]; then
        log WARN "Credential Scan" "Workspace directory not found: $WORKSPACE"
        return
    fi

    local found_leaks=false

    # API key patterns (exclude skill docs and script itself)
    local leaks
    leaks=$(grep -rn -E "(sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|ghp_[a-zA-Z0-9]{36}|xoxb-[a-zA-Z0-9-]{20,}|-----BEGIN (RSA |OPENSSH )?PRIVATE KEY-----)" \
        "$WORKSPACE/" --include="*.md" --include="*.json" --include="*.txt" --include="*.yaml" --include="*.yml" \
        2>/dev/null | grep -v "SKILL.md" | grep -v "skills/" | grep -v "scripts/" || true)

    if [ -n "$leaks" ]; then
        log CRITICAL "Credential Scan" "Found potential API keys/tokens in workspace"
        found_leaks=true
    fi

    # Password patterns
    local pw_leaks
    pw_leaks=$(grep -rn -iE "(password|passwd|secret|api.key)\s*[:=]\s*['\"][a-zA-Z0-9+/]{8,}" \
        "$WORKSPACE/" --include="*.md" --include="*.json" --include="*.txt" \
        2>/dev/null | grep -v "SKILL.md" | grep -v "skills/" | grep -v "scripts/" || true)

    if [ -n "$pw_leaks" ]; then
        log CRITICAL "Password Scan" "Found password patterns in workspace"
        found_leaks=true
    fi

    if [ "$found_leaks" = false ]; then
        log PASS "Credential Scan" "No leaked credentials found"
    fi
}

check_permissions() {
    echo "═══ Phase 2b: Directory/File Permissions ═══" >&2
    local all_ok=true

    # Directories that should be 700
    for d in "$OPENCLAW_DIR/credentials" "$OPENCLAW_DIR/identity" \
             "$OPENCLAW_DIR/logs" "$OPENCLAW_DIR/browser" "$WORKSPACE/memory"; do
        if [ -d "$d" ]; then
            local perm
            perm=$(get_perm "$d")
            if [ "$perm" = "drwx------" ] || [ "$perm" = "700" ]; then
                : # OK
            else
                log HIGH "Dir Permission" "$d is $perm (should be drwx------/700)"
                all_ok=false
                chmod 700 "$d" 2>/dev/null && echo "  🔧 Auto-fixed: $d" >&2
            fi
        fi
    done

    # Files that should be 600
    for f in "$CONFIG" "$OPENCLAW_DIR/.env"; do
        if [ -f "$f" ]; then
            local perm
            perm=$(get_perm "$f")
            if [ "$perm" = "-rw-------" ] || [ "$perm" = "600" ]; then
                : # OK
            else
                log HIGH "File Permission" "$f is $perm (should be -rw-------/600)"
                all_ok=false
                chmod 600 "$f" 2>/dev/null && echo "  🔧 Auto-fixed: $f" >&2
            fi
        fi
    done

    if $all_ok; then
        log PASS "Permissions" "All directory/file permissions correct"
    fi
}

check_gitignore() {
    echo "═══ Phase 2c: Gitignore Verification ═══" >&2
    local gitignore="$WORKSPACE/.gitignore"

    if [ ! -f "$gitignore" ]; then
        log HIGH "Gitignore" ".gitignore does not exist — sensitive files may be committed"
        return
    fi

    local all_ok=true
    local missing=""
    for p in "*.env" "memory/" "MEMORY.md" "*.pem" "*.key"; do
        if ! grep -qF "$p" "$gitignore" 2>/dev/null; then
            all_ok=false
            missing="$missing $p"
        fi
    done

    if $all_ok; then
        log PASS "Gitignore" "All sensitive patterns protected"
    else
        log WARN "Gitignore" "Missing patterns:$missing"
    fi
}

check_git_history() {
    echo "═══ Phase 2d: Git History Scan ═══" >&2

    if [ ! -d "$WORKSPACE/.git" ]; then
        log PASS "Git History" "No git repo — no history risk"
        return
    fi

    local commit_count
    commit_count=$(cd "$WORKSPACE" && git rev-list --count HEAD 2>/dev/null) || commit_count="0"
    commit_count=$(echo "$commit_count" | tr -d ' ')

    if [ "$commit_count" = "0" ]; then
        log PASS "Git History" "No commits yet — clean"
        return
    fi

    local secrets
    secrets=$(cd "$WORKSPACE" && git log --all -p 2>/dev/null | \
        grep -iE "(sk-[a-zA-Z0-9]{20,}|password\s*[:=]|secret\s*[:=]|token\s*[:=])" | \
        grep -v "SKILL.md" | grep -v "skills/" | head -5 || true)

    if [ -n "$secrets" ]; then
        log CRITICAL "Git History" "Found secrets in git history — rotate credentials immediately!"
    else
        log PASS "Git History" "No secrets found in $commit_count commits"
    fi
}

check_cron_tasks() {
    echo "═══ Phase 2e: Cron Task Audit ═══" >&2

    if ! command -v openclaw &>/dev/null; then
        log WARN "Cron Audit" "openclaw CLI not available — skipping"
        return
    fi

    if ! openclaw cron list >/dev/null 2>&1; then
        log WARN "Cron Audit" "Cannot list cron tasks"
        return
    fi

    local cron_output
    cron_output=$(openclaw cron list 2>/dev/null)

    # Skip header line, check each task
    echo "$cron_output" | tail -n +2 | grep -v "^$" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name
        name=$(echo "$line" | awk '{print $2}')
        if echo "$line" | grep -q "isolated"; then
            log PASS "Cron: $name" "Uses isolated session ✅"
        elif echo "$line" | grep -q "main"; then
            log WARN "Cron: $name" "Uses main session — consider isolated for security"
        fi
    done
}

check_network() {
    echo "═══ Phase 2f: Network Exposure ═══" >&2

    if ! command -v python3 &>/dev/null; then
        log ERROR "Network" "python3 unavailable — skipping"
        return
    fi

    local net_results
    net_results=$(python3 - "$CONFIG" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
gw = d.get("gateway", {})
bind = gw.get("bind", "unknown")
if bind == "loopback":
    print(f"PASS|Gateway Binding|Bound to loopback only")
else:
    print(f"HIGH|Gateway Binding|Bound to {bind} (should be loopback)")
auth = gw.get("auth", {}).get("mode", "unknown")
if auth == "token":
    token = gw.get("auth", {}).get("token", "")
    if len(token) >= 32:
        print(f"PASS|Gateway Auth|Token mode, {len(token)} chars")
    else:
        print(f"HIGH|Gateway Auth|Token too short: {len(token)} chars (recommend 32+)")
else:
    print(f"WARN|Gateway Auth|Mode: {auth} (recommend token)")
PYEOF
    )

    while IFS='|' read -r severity check detail; do
        [ -z "$severity" ] && continue
        log "$severity" "$check" "$detail"
    done <<< "$net_results"
}

# ═══════════════════════════════════════
# Phase 3: Credential Health & Backup
# ═══════════════════════════════════════
check_credential_age() {
    echo "═══ Phase 3a: Credential Age Check ═══" >&2

    if [ ! -f "$OPENCLAW_DIR/.env" ]; then
        log WARN "Credential Age" ".env file not found"
        return
    fi

    local env_age
    env_age=$(get_age_days "$OPENCLAW_DIR/.env")

    if [ "$env_age" -eq -1 ]; then
        log WARN "Credential Age" "Cannot determine .env age"
    elif [ "$env_age" -gt 180 ]; then
        log HIGH "Credential Age" ".env is ${env_age} days old — rotate now!"
    elif [ "$env_age" -gt 90 ]; then
        log WARN "Credential Age" ".env is ${env_age} days old — consider rotation"
    else
        log PASS "Credential Age" ".env is ${env_age} days old — fresh"
    fi
}

check_cron_coverage() {
    echo "═══ Phase 3b: Cron Coverage Check ═══" >&2

    if ! command -v openclaw &>/dev/null; then
        log WARN "Cron Coverage" "openclaw CLI not available — skipping"
        return
    fi

    if ! openclaw cron list >/dev/null 2>&1; then
        log WARN "Cron Coverage" "Cannot list cron tasks"
        return
    fi

    local cron_list
    cron_list=$(openclaw cron list 2>/dev/null)

    local has_security=false has_backup=false
    if echo "$cron_list" | grep -qi "security"; then
        has_security=true
    fi
    if echo "$cron_list" | grep -qi "backup"; then
        has_backup=true
    fi

    if $has_security; then
        log PASS "Security Cron" "Security audit cron exists"
    else
        log WARN "Security Cron" "No security audit cron — consider: openclaw cron add --name security-audit --cron '0 3 * * *'"
    fi

    if $has_backup; then
        log PASS "Backup Cron" "Config backup cron exists"
    else
        log WARN "Backup Cron" "No config backup cron — consider: openclaw cron add --name config-backup --cron '0 2 1 * *'"
    fi
}

# ═══════════════════════════════════════
# Report
# ═══════════════════════════════════════
generate_report() {
    local total=$((CRITICAL + HIGH + WARN + PASS))

    echo "" >&2
    echo "═══════════════════════════════════════" >&2
    echo "  OpenClaw Security Audit Report" >&2
    echo "  $(date '+%Y-%m-%d %H:%M %Z')" >&2
    echo "═══════════════════════════════════════" >&2
    echo "" >&2
    echo -e "$FINDINGS" >&2

    if [ -n "$ERRORS" ]; then
        echo "── Errors ──" >&2
        echo -e "$ERRORS" >&2
    fi

    echo "───────────────────────────────────────" >&2
    echo "  🔴 Critical: $CRITICAL" >&2
    echo "  🟠 High:     $HIGH" >&2
    echo "  🟡 Warning:  $WARN" >&2
    echo "  ✅ Passed:   $PASS" >&2
    echo "  ⚠️  Errors:   $(echo -e "$ERRORS" | grep -c '^' 2>/dev/null || echo 0)" >&2
    echo "  📊 Total:    $total checks" >&2
    echo "───────────────────────────────────────" >&2

    # Save to file
    local report_file="$WORKSPACE/memory/security-audit-$(date +%Y-%m-%d).md"
    mkdir -p "$WORKSPACE/memory" 2>/dev/null
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
        if [ -n "$ERRORS" ]; then
            echo ""
            echo "## Errors"
            echo ""
            echo -e "$ERRORS"
        fi
    } > "$report_file" 2>/dev/null
    echo "📄 Report saved: $report_file" >&2

    # Output machine-readable summary for agent consumption
    echo "CRITICAL=$CRITICAL HIGH=$HIGH WARN=$WARN PASS=$PASS TOTAL=$total"
}

# ═══════════════════════════════════════
# Main
# ═══════════════════════════════════════
main() {
    echo "🔒 OpenClaw Security Audit — Mode: $MODE" >&2
    echo "   Started: $(date '+%Y-%m-%d %H:%M')" >&2
    echo "" >&2

    preflight
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
