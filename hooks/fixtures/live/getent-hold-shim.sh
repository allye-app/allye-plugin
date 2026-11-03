#!/bin/bash
# Test fixture (ALY-290.3): a getent that stays alive while the hook resolves a folder. With $HOLD_STARTED set it creates that file,
# then waits (bounded: 600 polls of 50 ms, no clock assertion) until $HOLD_RELEASE exists, so a test can read /proc while the
# folder check is running. It then answers like a getent that knows nothing (exit 2). Without $HOLD_STARTED it exits 2 at once.
if [ -n "${HOLD_STARTED:-}" ]; then
  : >"$HOLD_STARTED"
  i=0
  while [ ! -e "${HOLD_RELEASE:-/nonexistent}" ] && [ "$i" -lt 600 ]; do "$CANARY_REAL/sleep" 0.05; i=$((i + 1)); done
fi
exit 2
