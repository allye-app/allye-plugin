#!/bin/bash
# Test fixture (ALY-290.3): a recording stand-in for curl. It logs argv and environment to $CANARY_LOG, saves the config curl
# receives on stdin (-K -) and every body file that config names (data-binary = "@FILE") under $SPY_DIR while they still exist,
# then runs the real curl from $CANARY_REAL with the same config on stdin. A test greps those copies for a canary.
{ printf "ARGV curl %s\n" "$*"; "$CANARY_REAL/env"; } >>"$CANARY_LOG" 2>/dev/null
cfg="$SPY_DIR/cfg.$$"
"$CANARY_REAL/cat" >"$cfg" 2>/dev/null
n=0
while IFS= read -r line; do
  case "$line" in
    *'data-binary = "@'*)
      f=${line#*\"@}; f=${f%\"*}
      n=$((n + 1)); "$CANARY_REAL/cat" "$f" >"$SPY_DIR/body.$$.$n" 2>/dev/null ;;
  esac
done <"$cfg"
exec "$CANARY_REAL/curl" "$@" <"$cfg"
