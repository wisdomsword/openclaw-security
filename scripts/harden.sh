#!/bin/bash
# OpenClaw Auto-Hardening — Cross-platform
# Usage: bash harden.sh [--dry-run]
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OC="$HOME/.openclaw"; WS="$OC/workspace"; CF="$OC/openclaw.json"
DRY="${1:-}"; N=0

perm() { stat -f "%Sp" "$1" 2>/dev/null || stat -c "%A" "$1" 2>/dev/null || echo "?"; }
fix()  { [ "$DRY" = "--dry-run" ] && echo "🔍 [DRY] $1" || { echo "🔧 $1"; N=$((N+1)); }; }

echo "🛡️ OpenClaw Hardening$([ "$DRY" = "--dry-run" ] && echo " (dry-run)")"

# 1. Directory permissions
for d in "$OC/credentials" "$OC/identity" "$OC/logs" "$OC/browser" "$WS/memory"; do
    [ -d "$d" ] || continue; p=$(perm "$d")
    [[ "$p" = "drwx------" || "$p" = "700" ]] && echo "  ✅ $(basename $d)" || {
        [ "$DRY" != "--dry-run" ] && chmod 700 "$d"; fix "$(basename $d): $p → 700"; }
done

# 2. File permissions
for f in "$CF" "$OC/.env"; do
    [ -f "$f" ] || continue; p=$(perm "$f")
    [[ "$p" = "-rw-------" || "$p" = "600" ]] && echo "  ✅ $(basename $f)" || {
        [ "$DRY" != "--dry-run" ] && chmod 600 "$f"; fix "$(basename $f): $p → 600"; }
done

# 3. Config structure validation & fix
echo ""
"$SKILL_DIR/scripts/check-config.sh" $([ "$DRY" = "--dry-run" ] && echo "" || echo "--fix")

# 4. .gitignore
echo ""
[ -f "$WS/.gitignore" ] && echo "  ✅ .gitignore exists" || {
    [ "$DRY" != "--dry-run" ] && cat > "$WS/.gitignore" <<'EOF'
# OpenClaw workspace
*.env .env.* *.pem *.key *.p12 *.pfx
.openclaw/ memory/ MEMORY.md browser/
*.log *.log.* .DS_Store Thumbs.db *.swp *.swo *~
EOF
    fix "Created .gitignore"; }

# 5. Config backup
echo ""
BACKUP_DIR="$OC/config-history"
if [ "$DRY" != "--dry-run" ]; then
    mkdir -p "$BACKUP_DIR"; ts=$(date +%Y%m%d-%H%M%S)
    cp "$CF" "$BACKUP_DIR/openclaw.json.$ts"
    cnt=$(ls -1 "$BACKUP_DIR"/openclaw.json.* 2>/dev/null | wc -l | tr -d ' ')
    [ "$cnt" -gt 10 ] && { rm=$(ls -1t "$BACKUP_DIR"/openclaw.json.* | tail -n $((cnt-10))); [ -n "$rm" ] && echo "$rm" | xargs rm -f; }
    fix "Config backed up → openclaw.json.$ts"
else echo "  🔍 [DRY] Would backup config"; fi

echo ""
echo "═══════════════════════════════════════"
echo "  🛡️ Done — $N fix(es) applied"
echo "═══════════════════════════════════════"
