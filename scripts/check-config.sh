#!/bin/bash
# OpenClaw Config Structure Validator & Auto-fixer
# Validates openclaw.json security-related fields, auto-fixes type errors
# Usage: bash check-config.sh [--fix]

set -uo pipefail

CONFIG="$HOME/.openclaw/openclaw.json"
FIX="${1:-}"

if [ ! -f "$CONFIG" ]; then
    echo "❌ Config not found: $CONFIG"
    exit 2
fi

# JSON validity
if ! python3 -c "import json; json.load(open('$CONFIG'))" 2>/dev/null; then
    echo "❌ Invalid JSON in $CONFIG"
    exit 2
fi

python3 - "$CONFIG" "$FIX" <<'PYEOF'
import json, sys

config_path = sys.argv[1]
do_fix = sys.argv[2] == "--fix"

with open(config_path) as f:
    d = json.load(f)

issues = []
fixed = []

def check(path, value, expected_type, fix_value=None):
    """Check a nested path. If wrong type and fix_value provided, fix it."""
    keys = path.split(".")
    obj = d
    for k in keys[:-1]:
        obj = obj.get(k, {})
    actual = obj.get(keys[-1])
    
    if not isinstance(actual, expected_type):
        issues.append((path, type(actual).__name__, expected_type.__name__))
        if do_fix and fix_value is not None:
            obj[keys[-1]] = fix_value
            fixed.append(path)

# Security config checks
ch = d.get("channels", {}).get("feishu", {})
checks = [
    ("groupPolicy", ch.get("groupPolicy"), str, "allowlist"),
    ("dmPolicy", ch.get("dmPolicy"), str, "pairing"),
]

tools = d.get("tools", {})
fs = tools.get("fs")
if isinstance(fs, bool):
    issues.append(("tools.fs", "bool", "dict"))
    if do_fix:
        tools["fs"] = {"workspaceOnly": fs}
        fixed.append("tools.fs")
elif isinstance(fs, dict):
    if fs.get("workspaceOnly") is not True:
        issues.append(("tools.fs.workspaceOnly", str(type(fs.get("workspaceOnly"))), "True"))

agents_defaults = d.get("agents", {}).get("defaults", {})
sandbox = agents_defaults.get("sandbox")
if isinstance(sandbox, str):
    issues.append(("agents.defaults.sandbox", "str", "dict"))
    if do_fix:
        agents_defaults["sandbox"] = {"mode": sandbox}
        fixed.append("agents.defaults.sandbox")
elif sandbox is None:
    issues.append(("agents.defaults.sandbox", "None", "dict"))
    if do_fix:
        agents_defaults["sandbox"] = {"mode": "off"}
        fixed.append("agents.defaults.sandbox")

gw = d.get("gateway", {})
auth = gw.get("auth")
if isinstance(auth, str):
    issues.append(("gateway.auth", "str", "dict"))
    if do_fix:
        gw["auth"] = {"mode": auth}
        fixed.append("gateway.auth")

bind = gw.get("bind")
if bind != "loopback":
    issues.append(("gateway.bind", repr(bind), "'loopback'"))

# Output
if not issues:
    print("✅ Config structure valid")
else:
    for path, actual, expected in issues:
        if path in fixed:
            print(f"🔧 Fixed: {path} ({actual} → {expected})")
        else:
            print(f"⚠️  {path}: is {actual}, should be {expected}")

if do_fix and fixed:
    with open(config_path, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"💾 Saved {len(fixed)} fix(es) to config")
elif issues and not do_fix:
    print(f"\n💡 Run with --fix to auto-repair")

sys.exit(1 if issues else 0)
PYEOF
