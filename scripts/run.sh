#!/bin/bash
# OpenClaw Security — All-in-one entry point
# Usage: bash run.sh [--audit|--harden|--full]
#   --audit   Audit only (default)
#   --harden  Audit + auto-fix
#   --full    Audit + harden + backup

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"

MODE="${1:---full}"
EXIT_CODE=0

# Color output (no color if piped)
if [ -t 1 ]; then
    RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[0;34m'; RST='\033[0m'
else
    RED=''; GRN=''; YLW=''; BLU=''; RST=''
fi

log() { echo -e "${BLU}[$1]${RST} $2"; }
ok()  { echo -e "  ${GRN}✅${RST} $1"; }
warn(){ echo -e "  ${YLW}⚠️${RST}  $1"; }
fail(){ echo -e "  ${RED}❌${RST} $1"; }

echo ""
echo "🔒 OpenClaw Security — Mode: $MODE"
echo "   $(date '+%Y-%m-%d %H:%M %Z')"
echo ""

# Phase 1+2: Audit
log "1/3" "Running security audit..."
audit_output=$("$SCRIPTS/audit.sh" --full 2>&1)
audit_exit=$?
echo "$audit_output" | grep -E "^(✅|🟡|🟠|🔴|⚠️)" | sed 's/^/  /'

# Parse summary
eval "$(echo "$audit_output" | grep "^CRITICAL=" | tail -1)"

if [ "${CRITICAL:-0}" -gt 0 ]; then
    EXIT_CODE=2
elif [ "${HIGH:-0:-0}" -gt 0 ]; then
    EXIT_CODE=1
fi

# Phase 3a: Harden if requested
if [ "$MODE" = "--harden" ] || [ "$MODE" = "--full" ]; then
    echo ""
    log "2/3" "Auto-hardening..."
    "$SCRIPTS/harden.sh" 2>&1 | sed 's/^/  /'
fi

# Phase 3b: Backup if full
if [ "$MODE" = "--full" ]; then
    echo ""
    log "3/3" "Config backup..."
    "$SCRIPTS/config-backup.sh" 2>&1 | sed 's/^/  /'
fi

echo ""
echo "═══════════════════════════════════════"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "  ${GRN}✅ All clear${RST}"
elif [ $EXIT_CODE -eq 1 ]; then
    echo -e "  ${YLW}⚠️  HIGH issues found${RST}"
else
    echo -e "  ${RED}🔴 CRITICAL issues found!${RST}"
fi
echo "═══════════════════════════════════════"

exit $EXIT_CODE
