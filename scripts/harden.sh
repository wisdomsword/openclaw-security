#!/bin/bash
# OpenClaw Auto-Hardening Script — Cross-platform (macOS + Linux)
# Fixes common security issues automatically
# Usage: bash harden.sh [--dry-run]

set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
WORKSPACE="$OPENCLAW_DIR/workspace"
CONFIG="$OPENCLAW_DIR/openclaw.json"
DRY_RUN="${1:-}"
FIXED=0

# Cross-platform permission getter
get_perm() {
    stat -f "%Sp" "$1" 2>/dev/null || stat -c "%A" "$1" 2>/dev/null || echo "UNKNOWN"
}

fix() {
    local desc="$1"
    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "🔍 [DRY RUN] Would fix: $desc"
    else
        echo "🔧 Fixed: $desc"
        FIXED=$((FIXED+1))
    fi
}

echo "🛡️ OpenClaw Security Hardening"
echo "   Started: $(date '+%Y-%m-%d %H:%M')"
[ "$DRY_RUN" = "--dry-run" ] && echo "   Mode: DRY RUN (no changes)"
echo ""

# ═══════════════════════════════════════
# Pre-flight
# ═══════════════════════════════════════
if [ ! -d "$OPENCLAW_DIR" ]; then
    echo "❌ OpenClaw directory not found: $OPENCLAW_DIR"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "❌ Config file not found: $CONFIG"
    exit 1
fi

# ═══════════════════════════════════════
# Fix 1: Directory Permissions
# ═══════════════════════════════════════
echo "═══ Directory Permissions ═══"
for d in "$OPENCLAW_DIR/credentials" "$OPENCLAW_DIR/identity" \
         "$OPENCLAW_DIR/logs" "$OPENCLAW_DIR/browser" "$WORKSPACE/memory"; do
    if [ -d "$d" ]; then
        perm=$(get_perm "$d")
        if [ "$perm" = "drwx------" ] || [ "$perm" = "700" ]; then
            echo "  ✅ $d: $perm"
        else
            if [ "$DRY_RUN" != "--dry-run" ]; then
                chmod 700 "$d"
            fi
            fix "Directory $d: $perm → 700"
        fi
    else
        echo "  ⏭️  $d: not found (skipped)"
    fi
done

# ═══════════════════════════════════════
# Fix 2: File Permissions
# ═══════════════════════════════════════
echo ""
echo "═══ File Permissions ═══"
for f in "$CONFIG" "$OPENCLAW_DIR/.env"; do
    if [ -f "$f" ]; then
        perm=$(get_perm "$f")
        if [ "$perm" = "-rw-------" ] || [ "$perm" = "600" ]; then
            echo "  ✅ $f: $perm"
        else
            if [ "$DRY_RUN" != "--dry-run" ]; then
                chmod 600 "$f"
            fi
            fix "File $f: $perm → 600"
        fi
    else
        echo "  ⏭️  $f: not found (skipped)"
    fi
done

# ═══════════════════════════════════════
# Fix 3: Create .gitignore if missing
# ═══════════════════════════════════════
echo ""
echo "═══ Gitignore ═══"
if [ ! -f "$WORKSPACE/.gitignore" ]; then
    if [ "$DRY_RUN" != "--dry-run" ]; then
        cat > "$WORKSPACE/.gitignore" <<'EOF'
# OpenClaw workspace .gitignore
# Prevent accidental commit of sensitive data

# Credentials and secrets
*.env
.env.*
*.pem
*.key
*.p12
*.pfx

# OpenClaw internal files
.openclaw/

# Memory files (may contain personal data)
memory/
MEMORY.md

# Browser data
browser/

# Logs
*.log
*.log.*

# OS files
.DS_Store
Thumbs.db

# Editor files
*.swp
*.swo
*~
EOF
    fi
    fix "Created .gitignore with sensitive file patterns"
else
    echo "  ✅ .gitignore exists"
fi

# ═══════════════════════════════════════
# Fix 4: Config backup
# ═══════════════════════════════════════
echo ""
echo "═══ Config Backup ═══"
BACKUP_DIR="$OPENCLAW_DIR/config-history"
if [ "$DRY_RUN" != "--dry-run" ]; then
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    cp "$CONFIG" "$BACKUP_DIR/openclaw.json.$TIMESTAMP"
    # Keep last 10
    count=$(ls -1 "$BACKUP_DIR"/openclaw.json.* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 10 ]; then
        remove=$((count - 10))
        ls -1t "$BACKUP_DIR"/openclaw.json.* | tail -n "$remove" | xargs rm -f
        echo "🧹 Cleaned up $remove old backups"
    fi
    fix "Config backed up to openclaw.json.$TIMESTAMP"
else
    echo "  🔍 [DRY RUN] Would backup config"
fi

# ═══════════════════════════════════════
# Summary
# ═══════════════════════════════════════
echo ""
echo "═══════════════════════════════════════"
if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "  🔍 DRY RUN complete — no changes made"
else
    echo "  🛡️ Hardening complete — $FIXED fixes applied"
fi
echo "═══════════════════════════════════════"
