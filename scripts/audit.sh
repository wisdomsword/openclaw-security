#!/bin/bash
# OpenClaw Security Audit — Cross-platform (macOS + Linux)
# Usage: bash audit.sh [--config|--full]
set -uo pipefail

OC="$HOME/.openclaw"
WS="$OC/workspace"
CF="$OC/openclaw.json"
MODE="${1:---full}"
C=0; H=0; W=0; P=0; F=""

# Cross-platform helpers
perm() { stat -f "%Sp" "$1" 2>/dev/null || stat -c "%A" "$1" 2>/dev/null || echo "?"; }
age()  { local t; t=$(stat -f "%m" "$1" 2>/dev/null || stat -c "%Y" "$1" 2>/dev/null || echo 0); echo $(( ($(date +%s) - t) / 86400 )); }

log() {
    case "$1" in
        C) C=$((C+1)); F+="🔴 $2: $3\n";;
        H) H=$((H+1)); F+="🟠 $2: $3\n";;
        W) W=$((W+1)); F+="🟡 $2: $3\n";;
        P) P=$((P+1)); F+="✅ $2: $3\n";;
    esac
}

# ── Phase 1: Config ──
[ -f "$CF" ] || { echo "❌ Config not found: $CF"; exit 2; }
command -v python3 &>/dev/null || { echo "❌ python3 required"; exit 2; }

cfg=$(python3 - "$CF" <<'PY'
import json,sys; d=json.load(open(sys.argv[1]))
ch=d.get("channels",{}).get("feishu",{})
t=d.get("tools",{}); a=d.get("agents",{}).get("defaults",{})
g=d.get("gateway",{})
for n,ok in [
    ("groupPolicy=allowlist",ch.get("groupPolicy")=="allowlist"),
    ("groupAllowFrom not empty",len(ch.get("groupAllowFrom",[]))>0),
    ("dmPolicy=pairing",ch.get("dmPolicy")=="pairing"),
    ("workspaceOnly",t.get("fs",{}).get("workspaceOnly") is True),
    ("bind=loopback",g.get("bind")=="loopback"),
    ("auth=token",g.get("auth",{}).get("mode")=="token"),
    ("sandbox is object",isinstance(a.get("sandbox"),dict)),
]: print(f"{'P' if ok else 'H'}|{n}|{'OK' if ok else 'FAIL'}")
PY
)
while IFS='|' read -r s n d; do [ -n "$s" ] && log "$s" "Config: $n" "$d"; done <<< "$cfg"

[ "$MODE" = "--config" ] && { # Config-only mode
    echo -e "\n$F"; echo "C=$C H=$H W=$W P=$P"; exit $((C>0?2:H>0?1:0)); }

# ── Phase 2: Deep audit ──
# 2a Credentials
leaks=$(grep -rnE "(sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|ghp_[a-zA-Z0-9]{36}|-----BEGIN.*PRIVATE KEY-----)" \
    "$WS/" --include="*.md" --include="*.json" --include="*.txt" 2>/dev/null \
    | grep -v "SKILL.md" | grep -v "skills/" | grep -v "scripts/" || true)
[ -n "$leaks" ] && log C "Credential Scan" "Secrets found in workspace!" || log P "Credential Scan" "Clean"

# 2b Permissions
perm_ok=true
for d in "$OC/credentials" "$OC/identity" "$OC/logs" "$OC/browser" "$WS/memory"; do
    [ -d "$d" ] || continue; p=$(perm "$d")
    [[ "$p" = "drwx------" || "$p" = "700" ]] && continue
    log H "Permission: $(basename "$d")" "$p → 700"; chmod 700 "$d" 2>/dev/null; perm_ok=false
done
for f in "$CF" "$OC/.env"; do
    [ -f "$f" ] || continue; p=$(perm "$f")
    [[ "$p" = "-rw-------" || "$p" = "600" ]] && continue
    log H "Permission: $(basename "$f")" "$p → 600"; chmod 600 "$f" 2>/dev/null; perm_ok=false
done
$perm_ok && log P "Permissions" "All correct"

# 2c Gitignore
gi="$WS/.gitignore"
if [ ! -f "$gi" ]; then log H "Gitignore" "Missing"
else
    missing=""; for p in "*.env" "memory/" "MEMORY.md" "*.pem" "*.key"; do
        grep -qF "$p" "$gi" 2>/dev/null || missing="$missing $p"; done
    [ -n "$missing" ] && log W "Gitignore" "Missing:$missing" || log P "Gitignore" "Protected"
fi

# 2d Git history
if [ -d "$WS/.git" ]; then
    cc=$(cd "$WS" && git rev-list --count HEAD 2>/dev/null || echo 0); cc=$(echo "$cc"|tr -d ' ')
    if [ "$cc" -gt 0 ] 2>/dev/null; then
        sg=$(cd "$WS" && git log --all -p 2>/dev/null | grep -ciE "(sk-[a-zA-Z0-9]{20,}|password\s*[:=])" || echo 0)
        [ "$sg" -gt 0 ] && log C "Git History" "Secrets in $cc commits!" || log P "Git History" "$cc commits clean"
    else log P "Git History" "No commits"; fi
else log P "Git History" "No git repo"; fi

# 2e Network
net=$(python3 - "$CF" <<'PY'
import json,sys; d=json.load(open(sys.argv[1])); g=d.get("gateway",{})
b=g.get("bind","?"); a=g.get("auth",{})
print(f"{'P' if b=='loopback' else 'H'}|bind={b}|{'OK' if b=='loopback' else 'should be loopback'}")
t=a.get("token",""); m=a.get("mode","?")
print(f"{'P' if m=='token' and len(t)>=32 else 'H'}|auth={m}|{len(t)} chars")
PY
)
while IFS='|' read -r s n d; do [ -n "$s" ] && log "$s" "Network: $n" "$d"; done <<< "$net"

# 2f Cron
if command -v openclaw &>/dev/null; then
    cron_out=$(openclaw cron list 2>/dev/null || echo "")
    if [ -n "$cron_out" ]; then
        echo "$cron_out" | tail -n +2 | grep -v "^$" | while IFS= read -r line; do
            [ -z "$line" ] && continue; name=$(echo "$line"|awk '{print $2}')
            echo "$line" | grep -q "isolated" && echo "P|Cron: $name|isolated ✅" || echo "W|Cron: $name|not isolated"
        done | while IFS='|' read -r s n d; do [ -n "$s" ] && log "$s" "$n" "$d"; done
    fi
fi

# ── Phase 3: Health ──
if [ -f "$OC/.env" ]; then
    a=$(age "$OC/.env")
    [ "$a" -gt 180 ] && log H "Cred Age" ".env ${a}d old — rotate!" || \
    [ "$a" -gt 90 ]  && log W "Cred Age" ".env ${a}d old" || log P "Cred Age" ".env ${a}d fresh"
fi

if command -v openclaw &>/dev/null; then
    cl=$(openclaw cron list 2>/dev/null || echo "")
    echo "$cl" | grep -qi "security" && log P "Cron Coverage" "Security cron exists" || log W "Cron Coverage" "No security cron"
    echo "$cl" | grep -qi "backup" && log P "Backup Cron" "Backup cron exists" || log W "Backup Cron" "No backup cron"
fi

# ── Report ──
mkdir -p "$WS/memory" 2>/dev/null
{
    echo "# Security Audit — $(date '+%Y-%m-%d %H:%M')"
    echo "| Critical | High | Warn | Pass |"
    echo "|----------|------|------|------|"
    echo "| $C | $H | $W | $P |"
    echo ""; echo -e "$F"
} > "$WS/memory/security-audit-$(date +%Y-%m-%d).md" 2>/dev/null

echo ""
echo "═══════════════════════════════════════"
echo -e "$F"
echo "───────────────────────────────────────"
echo "  🔴 $C  🟠 $H  🟡 $W  ✅ $P"
echo "═══════════════════════════════════════"
echo "CRITICAL=$C HIGH=$H WARN=$W PASS=$P"

exit $((C>0?2:H>0?1:0))
