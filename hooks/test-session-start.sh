#!/bin/bash
# Assertions for hooks/session-start.sh runtime detection.
# No test framework in this repo — this script IS the harness.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-start.sh"
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

echo "test: no runtime when HERDR_ENV is unset"
OUT=$(echo '{"source":"startup"}' | env -u HERDR_ENV -u HERDR_PANE_ID bash "$HOOK" 2>/dev/null)
HAS=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -c '^Agent runtime:' || true)
check "absent runtime emits no runtime line" "0" "$HAS"

echo "test: no runtime when HERDR_ENV set but herdr binary missing"
OUT=$(echo '{"source":"startup"}' | env HERDR_ENV=1 PATH=/nonexistent bash "$HOOK" 2>/dev/null)
HAS=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -c '^Agent runtime:' || true)
check "missing binary emits no runtime line" "0" "$HAS"

echo "test: output is always valid JSON"
OUT=$(echo '{"source":"startup"}' | env -u HERDR_ENV bash "$HOOK" 2>/dev/null)
echo "$OUT" | jq -e . >/dev/null 2>&1 && VALID=0 || VALID=1
check "hook emits parseable JSON without a runtime" "0" "$VALID"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
