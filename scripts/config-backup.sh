#!/bin/bash
# OpenClaw Config Version Management
# Backs up openclaw.json with timestamp, keeps last 10 versions
# Usage: bash config-backup.sh

set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
CONFIG="$OPENCLAW_DIR/openclaw.json"
BACKUP_DIR="$OPENCLAW_DIR/config-history"
MAX_BACKUPS=10

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/openclaw.json.$TIMESTAMP"

if [ ! -f "$CONFIG" ]; then
    echo "❌ Config file not found: $CONFIG"
    exit 1
fi

cp "$CONFIG" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"

# Cleanup old backups
count=$(ls -1 "$BACKUP_DIR"/openclaw.json.* 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -gt "$MAX_BACKUPS" ]; then
    remove=$((count - MAX_BACKUPS))
    ls -1t "$BACKUP_DIR"/openclaw.json.* | tail -n "$remove" | xargs rm -f
    echo "🧹 Cleaned up $remove old backups (keeping last $MAX_BACKUPS)"
fi

echo "📊 Total backups: $(ls -1 "$BACKUP_DIR"/openclaw.json.* 2>/dev/null | wc -l | tr -d ' ')"
