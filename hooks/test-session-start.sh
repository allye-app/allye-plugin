#!/bin/bash
# Assertions for hooks/session-start.sh. No framework: this script is the harness.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-start.sh"
BOOTSTRAP="$SCRIPT_DIR/../bootstrap/allye.md"
PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1))
  fi
}

OUT=$(echo '{"source":"startup"}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | jq -e . >/dev/null 2>&1 && VALID=0 || VALID=1
check "hook emits parseable JSON" "0" "$VALID"
check "hook event name" "SessionStart" "$(echo "$OUT" | jq -r '.hookSpecificOutput.hookEventName')"
CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
check "context is the shared bootstrap verbatim" "$(cat "$BOOTSTRAP")" "$CTX"

# Offline: the hook never calls the network or reads credentials.
check "hook makes no network calls" "0" "$(grep -cE 'curl|wget|ALLYE_PAT' "$HOOK")"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
