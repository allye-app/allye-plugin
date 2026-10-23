#!/bin/bash
# Claude Code Live reporter (ALY-203). One asynchronous hook script that branches on hook_event_name.
# This skeleton only decides whether it may act; event handling is added by later tasks.
#
# Contract (BR-01, BR-03): always exits 0 and prints nothing to stdout or stderr. It does nothing, and
# creates no file, unless CLAUDE_PLUGIN_DATA is an absolute expanded path, this install holds a valid
# credential (hooks/lib/credential.sh, the ALY-195 checks), `live` is not switched off (flag file
# $CLAUDE_PLUGIN_DATA/live/off), not marked disabled ($CLAUDE_PLUGIN_DATA/live/disabled), and jq, curl
# and a SHA-256 tool exist. Runtime: bash 3.2+, curl, jq, sha256sum or shasum. No node.
set -u
umask 077
LC_ALL=C   # plain shell variable (not exported): bash character ranges match bytes only
exec >/dev/null 2>&1

_src="${BASH_SOURCE[0]}"
case "$_src" in */*) ;; *) _src="./$_src" ;; esac
[ -r "${_src%/*}/lib/credential.sh" ] || exit 0
. "${_src%/*}/lib/credential.sh"

DIR="${CLAUDE_PLUGIN_DATA:-}"
valid_dir_arg "$DIR" || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0
have_sha || exit 0
UID_NOW=$(id -u 2>/dev/null) || exit 0
load_live_credential "$DIR" || exit 0

LIVE_DIR="$DIR/live"
if [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ]; then exit 0; fi
if [ -e "$LIVE_DIR/disabled" ] || [ -L "$LIVE_DIR/disabled" ]; then exit 0; fi

INPUT=$(cat 2>/dev/null) || INPUT=""   # the hook payload; unused until the event tasks land
exit 0
