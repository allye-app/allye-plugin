#!/bin/bash
# Claude Code Live reporter (ALY-203). One asynchronous hook script that branches on hook_event_name.
# Slice ALY-203.2: confirmed events are reduced to contract events and spooled locally (no seq, no sending yet).
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


# ─── ALY-203.2: extract allowlisted events from the payload and spool them ───
# BR-02: every value is read by the allowlisted jq program below and matched against its pattern or
# enumeration inside it; a value that fails is DROPPED (never truncated, never sent). Prompts, commands,
# tool inputs and outputs, paths, messages, transcripts and the cwd are never read into the output.
# AC-14: files are keyed by the SHA-256 hex of the session id; the raw id is never written anywhere.
# Not in this slice: seq, sending, flush (ALY-203.5/.6), tool reduction to allye:<action>/mcp and bind
# events (ALY-203.3), sub outcome/task and gates (ALY-203.4). sub_stop carries {id,type} only until .4.
INPUT=$(cat 2>/dev/null) || INPUT=""
[ -n "$INPUT" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r 'if (.session_id | type) == "string" and (.session_id | test("\\A[A-Za-z0-9._:-]{1,128}\\z")) then .session_id else empty end' 2>/dev/null) || exit 0
[ -n "$SID" ] || exit 0
HASH=$(printf '%s' "$SID" | sha_hex) || exit 0
SID=""
[[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || exit 0

SPOOL="$LIVE_DIR/$HASH.spool"
STATEF="$LIVE_DIR/$HASH.state"

# A path we may use: absent, or a regular file (no symlink) owned by the user with exactly mode 0600.
private_file_ok() {
  { [ ! -e "$1" ] && [ ! -L "$1" ]; } && return 0
  [ -n "$(find "$1" -prune -type f -user "$UID_NOW" -perm 0600 -print 2>/dev/null)" ]
}
# The live directory: a real directory owned by the user, mode 0700 (SHD-01); created 0700 when absent.
live_dir_ok() {
  [ -L "$LIVE_DIR" ] && return 1
  [ -e "$LIVE_DIR" ] || mkdir -m 700 "$LIVE_DIR" 2>/dev/null || return 1
  [ -n "$(find "$LIVE_DIR" -prune -type d -user "$UID_NOW" -perm 0700 -print 2>/dev/null)" ]
}

LAST=""
if [ -f "$STATEF" ] && [ ! -L "$STATEF" ] && private_file_ok "$STATEF"; then
  LAST=$(cat "$STATEF" 2>/dev/null) || LAST=""
  case "$LAST" in started|working|waiting_input|idle|error|ended) ;; *) LAST="" ;; esac
fi
AT=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || exit 0

# One program per event (D-06). Output: first line the new last state, then one compact JSON event per line.
JQ_PROG='
def sre($r): type == "string" and test($r);
def idok:   sre("\\A[A-Za-z0-9_-]{1,64}\\z");
def typeok: sre("\\A[A-Za-z0-9:_-]{1,64}\\z");
def toolok: sre("\\A[A-Za-z][A-Za-z0-9_]{0,31}\\z");
def st($s): [{type: "state", state: $s}];
def stc($s; $c): [{type: "state", state: $s, code: $c}];
def subof: if (.agent_id | idok) and (.agent_type | typeok) then {id: .agent_id, type: .agent_type} else null end;
# agent_id is present only when the hook fires inside a subagent (confirmed in the installed CLI schema).
# BR-14 trigger: {type:"trig"} is never output; it only makes a pending waiting_input become working.
# A value failing its pattern drops the tool event but the hook still counts as activity.
def trig: [{type: "trig"}];
def toolev:
  if (.agent_id // null) != null then
    (subof) as $s | if $s != null and (.tool_name | toolok) then [{type: "sub_tool", tool: .tool_name, sub: $s}] else trig end
  elif (.tool_name | toolok) then [{type: "tool", tool: .tool_name}]
  else trig end;
def failcode: .error as $x | if ($x | type) == "string" and (["rate_limit","authentication_failed","billing_error","invalid_request","server_error","max_output_tokens"] | index($x)) != null then "cli_error_" + $x else "cli_error_unknown" end;
def endcode: .reason as $x | if ($x | type) == "string" and (["clear","resume","logout","prompt_input_exit"] | index($x)) != null then "end_" + $x else "end_other" end;
def evs:
  .hook_event_name as $e
  | if   $e == "SessionStart"        then (if (.source | IN("startup","resume","clear","compact","fork")) then st("started") else [] end)
    elif $e == "UserPromptSubmit"    then st("working")
    elif $e == "UserPromptExpansion" then []
    elif $e == "PreToolUse"          then (if .tool_name == "AskUserQuestion" then stc("waiting_input"; "asked_question") else toolev end)
    elif $e == "PostToolUse"         then trig   # D-01: no tool event from Post, only the BR-14 trigger
    elif $e == "PermissionRequest"   then stc("waiting_input"; "permission_prompt")
    elif $e == "Notification"        then (if .notification_type == "permission_prompt" then stc("waiting_input"; "permission_prompt")
                                           elif .notification_type == "idle_prompt" then st("idle") else [] end)
    elif $e == "SubagentStart"       then (subof as $s | if $s != null then [{type: "sub_start", sub: $s}] else trig end)
    elif $e == "SubagentStop"        then (subof as $s | if $s != null then [{type: "sub_stop", sub: $s}] else [] end)
    elif $e == "Stop"                then stc("idle"; "turn_ended")
    elif $e == "StopFailure"         then stc("error"; failcode)
    elif $e == "SessionEnd"          then stc("ended"; endcode)
    else [] end;
# BR-14: the first tool/subagent-start event after waiting_input is preceded by a `state working`.
reduce evs[] as $ev ({out: [], last: $last};
    (if ($ev.type | IN("tool","sub_tool","sub_start","trig")) and .last == "waiting_input"
       then .out += [{type: "state", state: "working"}] | .last = "working" else . end)
    | (if $ev.type == "trig" then . else .out += [$ev] end)
    | if $ev.type == "state" then .last = $ev.state else . end)
| if (.out | length) == 0 then empty else .last, (.out[] | . + {at: $at} | tojson) end'

RESULT=$(printf '%s' "$INPUT" | jq -r --arg last "$LAST" --arg at "$AT" "$JQ_PROG" 2>/dev/null) || exit 0
[ -n "$RESULT" ] || exit 0
case "$RESULT" in *$'\n'*) ;; *) exit 0 ;; esac
NEWLAST="${RESULT%%$'\n'*}"
EVENTS="${RESULT#*$'\n'}"
case "$NEWLAST" in ""|started|working|waiting_input|idle|error|ended) ;; *) exit 0 ;; esac

live_dir_ok || exit 0
private_file_ok "$SPOOL" || exit 0
private_file_ok "$STATEF" || exit 0
printf '%s\n' "$EVENTS" >>"$SPOOL" 2>/dev/null || exit 0
if [ -n "$NEWLAST" ] && [ "$NEWLAST" != "$LAST" ]; then
  TMP=$(mktemp "$LIVE_DIR/.state.XXXXXX" 2>/dev/null) || exit 0
  printf '%s' "$NEWLAST" >"$TMP" 2>/dev/null && mv -f "$TMP" "$STATEF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi
exit 0
