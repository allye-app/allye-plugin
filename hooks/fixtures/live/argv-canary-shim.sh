#!/bin/bash
# Test fixture (ALY-290.5): a logging stand-in for any tool. It appends its argv and its whole environment to $CANARY_LOG,
# then runs the real tool from $CANARY_REAL. A test uses it to prove a held folder string never reaches argv or env of a process.
tool=${0##*/}
{ printf "ARGV %s %s\n" "$tool" "$*"; "$CANARY_REAL/env"; } >>"$CANARY_LOG" 2>/dev/null
exec "$CANARY_REAL/$tool" "$@"
