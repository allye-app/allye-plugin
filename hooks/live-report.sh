#!/bin/bash
# Claude Code Live reporter (ALY-203). One asynchronous hook script that branches on hook_event_name.
# Slices ALY-203.2/.3/.5: confirmed events are reduced to contract events and spooled locally with a seq (no sending yet);
# MCP tools are reduced (BR-13) and bind events are derived from four sources (BR-08).
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
# Not in this file yet: sending and flush (ALY-203.6/.7).
#
# ALY-203.3 (BR-13, BR-08):
# - Tool reduction runs BEFORE the 32-character name rule. A name starting `mcp__` is an MCP tool named
#   mcp__<server>__<tool> (Claude Code convention): server `allye` or ending `_allye` (e.g. the plugin server
#   plugin_allye_allye) is the Allye server and gives `allye:<action>` when tool_input.action matches
#   ^[a-z_]{1,40}$, else `mcp`; any other MCP tool is `mcp`; an MCP name with characters outside
#   [A-Za-z0-9_-] is dropped. No other tool_input value is ever read for the tool field.
# - Bind sources, strongest first: skill(4) mcp(3) env(2) branch(1). skill: Skill tool call or
#   UserPromptExpansion for `bridge`/`allye:bridge` with args `<mode> [KEY]`: only the mode enumeration and a
#   key matching the key pattern leave (an invalid mode drops the whole bind, an invalid key only the key).
#   mcp: an Allye MCP call whose tool_input.spec / tool_input.task match the key pattern (a task key does NOT
#   supply a spec part). env: ALLYE_SPEC / ALLYE_TASK of this process, at SessionStart. branch: SessionStart
#   only, when no bind of rank > 1 was sent for the session, through the one safe git call below. Calls made
#   inside a subagent never bind (parallel Pilots would flap the session binding).
# - $HASH.bind holds `<rank>|<bind json>` of the last bind sent. A bind is sent when its rank is higher than
#   the stored one, or equal with a different content; never when weaker or identical.
# - git: `git -c core.fsmonitor= -c core.hooksPath=/dev/null -C <cwd> branch --show-current`, cwd given as its
#   own argv element, never through a shell string; run only when the cwd is an absolute existing directory
#   without control characters; 1-second limit with timeout(1) when present, else a background watchdog
#   that kills git after 1 second. Only the matched key is kept; the branch name is never stored.
#
# ALY-203.4 (BR-09, BR-10):
# - sub_stop outcome: only the first 65536 characters of last_assistant_message are examined (a non-string or
#   missing message counts as empty). A line of its own, from its start, `[ \t]*status:[ \t]*<value>[ \t\r]*`
#   (indentation and trailing blanks/CR allowed, nothing else on the line) decides: the FIRST line starting with
#   `status:` wins, whatever its value. passed|approved|ready -> pass; advisory -> pass + code advisory; failed ->
#   fail; blocked|needs-input|escalate -> blocked; anything else, or no such line -> unknown + code returned. The
#   first line `task: <KEY>` (same layout) contributes the task when it matches the key pattern. The message text
#   is never copied: only the mapped enumeration, the code and a valid key leave.
# - gates: after a PostToolUse of tool Write or Edit in the MAIN session (never inside a subagent) whose
#   tool_input.file_path is textually `<cwd>/.allye/missions/<slug>/log.md` (cwd absolute without control
#   characters, `.`/`..`/`//` segments refused, slug ^[a-z0-9-]{1,80}$). The cwd is resolved physically
#   (`cd -P` + `pwd -P`, no realpath/readlink); `.allye`, `missions`, the slug directory and log.md must not be
#   symlinks, log.md must be a regular file of at most 65536 bytes (size checked first with find; an oversized
#   file is never opened) and is read with `head -c 65536`. The first line starting `- Gates:` is parsed; the
#   complete current set (enumeration order SHIELD_CLEAR, WATCHER_APPROVED, MISSION_COMPLETE, CI_PENDING) of the
#   tokens whose value is neither empty nor the em dash is sent as {type:gates,gates:[...]}, the empty set
#   included, only when it differs from the last set sent ($HASH.gates, same owner/mode/symlink checks; absent
#   means the empty set, so a first all-dash journal sends nothing). No Gates line: nothing. Nothing about the
#   file (path, other lines, sha values) leaves.
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
  [ -e "$LIVE_DIR" ] || mkdir -m 700 "$LIVE_DIR" 2>/dev/null || [ -d "$LIVE_DIR" ] || return 1   # parallel first hooks race here
  [ -n "$(find "$LIVE_DIR" -prune -type d -user "$UID_NOW" -perm 0700 -print 2>/dev/null)" ]
}

# ─── ALY-203.5: lock, seq and spool cap (BR-04, BR-05, SHD-01..03) ───
# lock_is_stale DIR: the holder time (first field of DIR/t) is more than 30 seconds old; without a readable time,
# the directory itself is more than a minute old (find -mmin).
lock_is_stale() {
  local ts="" now
  { IFS=' ' read -r ts _ <"$1/t"; } 2>/dev/null
  now=$(date +%s 2>/dev/null) || now=""
  if [[ "$ts" =~ ^[0-9]{1,12}$ ]] && [[ "$now" =~ ^[0-9]{1,12}$ ]]; then [ $((now - ts)) -gt 30 ]; return; fi
  [ -d "$1" ] && [ ! -L "$1" ] && [ -n "$(find "$1" -prune -mmin +1 -print 2>/dev/null)" ]
}
# lock_take DIR TRIES: a mkdir lock (D-03, portable). TRIES x 20 ms of waiting after the first attempt (0 = try
# once). The holder writes "<epoch> <token>" into DIR/t and keeps its token in LOCK_TOKEN. A stale lock is renamed
# to a unique name by the one breaker holding DIR.brk, judged again there, and only then removed; if the renamed lock turns out fresh (it was replaced
# meanwhile) it is put back and this try fails closed.
lock_take() {
  local d="$1" n="${2:-0}" i=0 old
  LOCK_TOKEN="$$.$RANDOM$RANDOM"
  while :; do
    if mkdir "$d" 2>/dev/null; then printf '%s %s' "$(date +%s 2>/dev/null)" "$LOCK_TOKEN" >"$d/t" 2>/dev/null; return 0; fi
    if lock_is_stale "$d"; then
      # Only one breaker at a time (a second mkdir lock, itself broken after a minute), so nobody can replace the
      # lock between the verdict and the rename; the renamed lock is judged once more as a safety net.
      [ -n "$(find "$d.brk" -prune -mmin +1 -print 2>/dev/null)" ] && rm -rf "$d.brk" 2>/dev/null
      if mkdir "$d.brk" 2>/dev/null; then
        old="$d.old.$$.$RANDOM"
        if lock_is_stale "$d" && mv "$d" "$old" 2>/dev/null; then
          if lock_is_stale "$old"; then rm -rf "$old" 2>/dev/null
          else [ -e "$d" ] || mv "$old" "$d" 2>/dev/null; rm -rf "$old" "$d.brk" 2>/dev/null; return 1; fi
        fi
        rm -rf "$d.brk" 2>/dev/null
        continue
      fi
    fi
    i=$((i + 1)); [ "$i" -gt "$n" ] && return 1
    sleep 0.02
  done
}
# lock_drop DIR TOKEN: removes the lock only while DIR/t still holds this hook's own token.
lock_drop() {
  local t=""
  { IFS=' ' read -r _ t <"$1/t"; } 2>/dev/null
  [ -n "${2:-}" ] && [ "$t" = "$2" ] && rm -rf "$1" 2>/dev/null
  return 0
}
now_ms() { local m; m=$(date +%s%3N 2>/dev/null); [[ "$m" =~ ^[0-9]{13,16}$ ]] || m="$(date +%s 2>/dev/null)000"; printf '%s' "$m"; }
# spool_trim FILE DIR: bounded growth when sending never succeeds (SHD-03): keep the newest 500 lines and at most
# 262144 bytes; a line cut by the byte limit is dropped whole. Called under the state lock.
spool_trim() {
  local f="$1" d="$2" lines bytes tmp
  bytes=$(wc -c <"$f" 2>/dev/null) || return 0; bytes=${bytes//[[:space:]]/}
  lines=$(wc -l <"$f" 2>/dev/null) || return 0; lines=${lines//[[:space:]]/}
  [[ "$bytes" =~ ^[0-9]+$ ]] && [[ "$lines" =~ ^[0-9]+$ ]] || return 0
  [ "$bytes" -le 262144 ] && [ "$lines" -le 500 ] && return 0
  tmp=$(mktemp "$d/.spool.XXXXXX" 2>/dev/null) || return 0
  TMPF="$tmp"
  tail -n 500 "$f" >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  bytes=$(wc -c <"$tmp" 2>/dev/null); bytes=${bytes//[[:space:]]/}
  if [[ "$bytes" =~ ^[0-9]+$ ]] && [ "$bytes" -gt 262144 ]; then
    tail -c 262144 "$tmp" 2>/dev/null | sed 1d >"$tmp.2" 2>/dev/null && mv -f "$tmp.2" "$tmp" 2>/dev/null
    rm -f "$tmp.2" 2>/dev/null
  fi
  mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

# The live directory is checked before the first read or write (SHD-01), then every read-modify-write of this
# session (state, bind, gates, seq, spool) runs under one lock, so parallel hooks of a session are consistent.
# A hook that cannot get the lock within about 10 seconds gives up and drops its events (it exits 0, silent).
live_dir_ok || exit 0
HAVE_LOCK=0; LOCKD="$LIVE_DIR/$HASH.lock"
TMPF=""
cleanup() { [ -z "$TMPF" ] || rm -f "$TMPF" "$TMPF.2" 2>/dev/null; [ "$HAVE_LOCK" = 1 ] && lock_drop "$LOCKD" "$LOCK_TOKEN"; return 0; }
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
lock_take "$LOCKD" 500 || exit 0
HAVE_LOCK=1

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
def keyok:  sre("\\A[A-Z][A-Z0-9]{1,9}-[0-9]+(\\.[0-9]+)?\\z");
# MCP tool names are mcp__<server>__<tool>; the Allye server is `allye` or ends with `_allye`.
def mcpname: (.tool_name | sre("\\Amcp__[A-Za-z0-9_-]{1,200}\\z"));
def allyesrv: mcpname and ((.tool_name | split("__")) as $p | ($p | length) >= 3 and ($p[1] | . == "allye" or endswith("_allye")));
# BR-13, applied before the 32-character rule: a string (the reduced tool) or null (dropped).
def redtool:
  if (.tool_name | type) != "string" then null
  elif (.tool_name | startswith("mcp__")) then
    if mcpname | not then null
    elif allyesrv then (((.tool_input | objects | .action) // null) | if sre("\\A[a-z_]{1,40}\\z") then "allye:" + . else "mcp" end)
    else "mcp" end
  elif (.tool_name | toolok) then .tool_name
  else null end;
def st($s): [{type: "state", state: $s}];
def stc($s; $c): [{type: "state", state: $s, code: $c}];
def subof: if (.agent_id | idok) and (.agent_type | typeok) then {id: .agent_id, type: .agent_type} else null end;
# BR-09: outcome and task from whole lines of the first 65536 characters of the crew message; nothing else is kept.
def msglines: (.last_assistant_message | if type == "string" then .[0:65536] else "" end) | split("\n");
def stline: [msglines[] | capture("\\A[ \t]*status:[ \t]*(?<v>[^ \t\r]*)[ \t\r]*\\z")? | .v] | .[0];
def tkline: [msglines[] | capture("\\A[ \t]*task:[ \t]*(?<v>[^ \t\r]*)[ \t\r]*\\z")? | .v] | .[0];
def outcome:
  (stline // "") as $v
  | if   $v | IN("passed","approved","ready") then {o: "pass"}
    elif $v == "advisory" then {o: "pass", c: "advisory"}
    elif $v == "failed" then {o: "fail"}
    elif $v | IN("blocked","needs-input","escalate") then {o: "blocked"}
    else {o: "unknown", c: "returned"} end;
def substop: outcome as $r | (tkline // null) as $t
  | {type: "sub_stop", sub: (subof + {outcome: $r.o} + (if ($t | keyok) then {task: $t} else {} end))}
    + (if $r.c != null then {code: $r.c} else {} end);
# agent_id is present only when the hook fires inside a subagent (confirmed in the installed CLI schema).
# BR-14 trigger: {type:"trig"} is never output; it only makes a pending waiting_input become working.
# A value failing its pattern drops the tool event but the hook still counts as activity.
def trig: [{type: "trig"}];
def toolev:
  redtool as $t
  | if (.agent_id // null) != null then
    (subof) as $s | if $s != null and $t != null then [{type: "sub_tool", tool: $t, sub: $s}] else trig end
  elif $t != null then [{type: "tool", tool: $t}]
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
    elif $e == "SubagentStop"        then (subof as $s | if $s != null then [substop] else [] end)
    elif $e == "Stop"                then stc("idle"; "turn_ended")
    elif $e == "StopFailure"         then stc("error"; failcode)
    elif $e == "SessionEnd"          then stc("ended"; endcode)
    else [] end;
# BR-08: the bind candidate of this event (null when none). ALLYE_SPEC/ALLYE_TASK are read from the environment ($ENV), never from argv.
def modes: ["launch","mission","blueprint","dispatch","repair","optimize","shield","inspect","survey"];
def kv($k): if ($k | keyok) then (if ($k | contains(".")) then {task: $k} else {spec: $k} end) else {} end;
def skillb($name; $args):
  if ($name | type) == "string" and ($name | IN("bridge","allye:bridge")) and ($args | type) == "string" and ($args | length) <= 300 then
    [$args | match("[^ \t\r\n]+"; "g").string] as $t
    | if ($t | length) > 0 and ($t[0] | IN(modes[])) then {source: "skill", role: "bridge", mode: $t[0]} + kv($t[1] // null) else null end
  else null end;
def mcpb:
  ((.tool_input | objects) // {}) as $i
  | ({source: "mcp"} + (if ($i.spec | keyok) then {spec: $i.spec} else {} end) + (if ($i.task | keyok) then {task: $i.task} else {} end))
  | if has("spec") or has("task") then . else null end;
def envb:
  ({source: "env", role: "session"} + (if ($ENV.ALLYE_SPEC | keyok) then {spec: $ENV.ALLYE_SPEC} else {} end) + (if ($ENV.ALLYE_TASK | keyok) then {task: $ENV.ALLYE_TASK} else {} end))
  | if has("spec") or has("task") then . else null end;
def sstart: .hook_event_name == "SessionStart" and (.source | IN("startup","resume","clear","compact","fork"));
def bindc:
  .hook_event_name as $e
  | if $e == "PreToolUse" and (.agent_id // null) == null then
      (if .tool_name == "Skill" then ((.tool_input | objects) // {}) as $i | skillb($i.skill; $i.args)
       elif allyesrv then mcpb else null end)
    elif $e == "UserPromptExpansion" then skillb(.command_name; .command_args)
    elif sstart then envb
    else null end;
def cwdc:
  if sstart and (.cwd | type) == "string" and (.cwd | length) <= 4096 and (.cwd | test("\\A/")) and (.cwd | test("[\u0000-\u001f\u007f]") | not) then .cwd else null end;
# BR-10: [file_path, cwd] of a Write/Edit PostToolUse of the main session, both absolute strings without control characters.
def pathok: type == "string" and length <= 4096 and test("\\A/") and (test("[\u0000-\u001f\u007f]") | not);
def gatec:
  ([.tool_input | objects | .file_path] | .[0]) as $fp
  | if .hook_event_name == "PostToolUse" and (.tool_name | IN("Write","Edit")) and (.agent_id // null) == null
       and ($fp | pathok) and (.cwd | pathok)
    then [$fp, .cwd] else null end;
# BR-14: the first tool/subagent-start event after waiting_input is preceded by a `state working`.
. as $in
| (reduce evs[] as $ev ({out: [], last: $last};
    (if ($ev.type | IN("tool","sub_tool","sub_start","trig")) and .last == "waiting_input"
       then .out += [{type: "state", state: "working"}] | .last = "working" else . end)
    | (if $ev.type == "trig" then . else .out += [$ev] end)
    | if $ev.type == "state" then .last = $ev.state else . end)) as $r
| $r.last,
  (try ($in | bindc) catch null | if . == null then "-" else tojson end),
  (try ($in | cwdc) catch null | . // "-"),
  (try ($in | gatec) catch null | if . == null then "-", "-" else .[] end),
  ($r.out[] | . + {at: $at} | tojson),
  "."'

RESULT=$(printf '%s' "$INPUT" | jq -r --arg last "$LAST" --arg at "$AT" "$JQ_PROG" 2>/dev/null) || exit 0
# Output: new last state, bind candidate (or -), cwd for the branch source (or -), events, "." terminator.
NEWLAST="${RESULT%%$'\n'*}"; REST="${RESULT#*$'\n'}"
CAND="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
CWD="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
GFP="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
GCWD="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
case "$REST" in .) EVENTS="" ;; *$'\n'.) EVENTS="${REST%$'\n'.}" ;; *) exit 0 ;; esac
case "$NEWLAST" in ""|started|working|waiting_input|idle|error|ended) ;; *) exit 0 ;; esac
[ -n "$CAND" ] && [ -n "$CWD" ] && [ -n "$GFP" ] && [ -n "$GCWD" ] || exit 0

# ─── ALY-203.3: binding (BR-08). Strength: skill 4 > mcp 3 > env 2 > branch 1. ───
BINDF="$LIVE_DIR/$HASH.bind"
BRANK=""; BSTORED=""
if [ "$CAND" != "-" ] || [ "$CWD" != "-" ]; then
  if [ -f "$BINDF" ] && [ ! -L "$BINDF" ]; then
    if private_file_ok "$BINDF"; then
      BSTORED=$(cat "$BINDF" 2>/dev/null) || BSTORED=""
      BRANK="${BSTORED%%|*}"
      case "$BRANK" in 1|2|3|4) ;; *) BRANK=""; BSTORED="" ;; esac
    else CAND="-"; CWD="-"; fi
  elif ! private_file_ok "$BINDF"; then CAND="-"; CWD="-"; fi
fi

# The only git call: safe flags, cwd as a separate argv element, 1-second limit (timeout(1) if present,
# else a watchdog that kills git). Output is the current branch (first line) or nothing.
branch_of() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 1 git -c core.fsmonitor= -c core.hooksPath=/dev/null -C "$1" branch --show-current </dev/null 2>/dev/null
  else
    {
      git -c core.fsmonitor= -c core.hooksPath=/dev/null -C "$1" branch --show-current </dev/null 2>/dev/null &
      gp=$!
      ( sleep 1; kill "$gp" ) >/dev/null 2>&1 &
      wp=$!
      wait "$gp"
      kill "$wp"
    } 2>/dev/null
  fi
}
if [ "$CAND" = "-" ] && [ "$CWD" != "-" ] && { [ -z "$BRANK" ] || [ "$BRANK" -le 1 ]; } && [ -d "$CWD" ]; then
  if command -v git >/dev/null 2>&1; then
    GOUT=$(branch_of "$CWD") || GOUT=""
    GOUT="${GOUT%%$'\n'*}"
    GUP=$(printf '%s' "$GOUT" | tr 'a-z' 'A-Z')
    if [[ "$GUP" =~ ^(BRIDGE/)?([A-Z][A-Z0-9]{1,9}-[0-9]+(\.[0-9]+)?)- ]]; then
      GKEY="${BASH_REMATCH[2]}"
      case "$GKEY" in *.*) CAND=$(jq -nc --arg k "$GKEY" '{source: "branch", task: $k}' 2>/dev/null) || CAND="-" ;;
                      *)   CAND=$(jq -nc --arg k "$GKEY" '{source: "branch", spec: $k}' 2>/dev/null) || CAND="-" ;; esac
      [ -n "$CAND" ] || CAND="-"
    fi
    GOUT=""; GUP=""
  fi
fi

BINDLINE=""
if [ "$CAND" != "-" ]; then
  case "$CAND" in
    '{"source":"skill"'*) NR=4 ;; '{"source":"mcp"'*) NR=3 ;; '{"source":"env"'*) NR=2 ;; '{"source":"branch"'*) NR=1 ;; *) NR=0 ;;
  esac
  SEND=0
  if [ "$NR" -gt 0 ]; then
    if [ -z "$BRANK" ] || [ "$NR" -gt "$BRANK" ]; then SEND=1
    elif [ "$NR" -eq "$BRANK" ] && [ "$NR|$CAND" != "$BSTORED" ]; then SEND=1; fi
  fi
  if [ "$SEND" = 1 ]; then
    BINDLINE=$(jq -nc --argjson b "$CAND" --arg at "$AT" '{type: "bind", bind: $b, at: $at}' 2>/dev/null) || BINDLINE=""
  fi
fi
if [ -n "$BINDLINE" ]; then
  if [ -n "$EVENTS" ]; then EVENTS="$EVENTS"$'\n'"$BINDLINE"; else EVENTS="$BINDLINE"; fi
fi

# ─── ALY-203.4: gates (BR-10). Every check must pass before the file is opened. ───
GATEF="$LIVE_DIR/$HASH.gates"
GATELINE=""; GNEW=""
mission_log_of() {  # prints the physical log.md path for GFP/GCWD, or fails
  local fp="$1" cwd="$2" phys slug p
  case "$cwd/" in */./*|*/../*|*//*) return 1 ;; esac
  case "$fp" in *//*|*/./*|*/../*) return 1 ;; esac
  case "$fp" in "$cwd"/.allye/missions/*/log.md) ;; *) return 1 ;; esac
  slug="${fp#"$cwd"/.allye/missions/}"; slug="${slug%/log.md}"
  [[ "$slug" =~ ^[a-z0-9-]{1,80}$ ]] || return 1
  [ -d "$cwd" ] || return 1
  phys=$(unset CDPATH; cd -P "$cwd" 2>/dev/null && pwd -P) || return 1
  case "$phys" in /*) ;; *) return 1 ;; esac
  for p in "$phys/.allye" "$phys/.allye/missions" "$phys/.allye/missions/$slug"; do
    [ -L "$p" ] && return 1
    [ -d "$p" ] || return 1
  done
  p="$phys/.allye/missions/$slug/log.md"
  [ -L "$p" ] && return 1
  [ -f "$p" ] || return 1
  [ -n "$(find "$p" -prune -type f -size -65537c -print 2>/dev/null)" ] || return 1
  printf '%s' "$p"
}
if [ "$GFP" != "-" ] && [ "$GCWD" != "-" ]; then
  GPATH=$(mission_log_of "$GFP" "$GCWD") || GPATH=""
  if [ -n "$GPATH" ]; then
    GNEW=$(head -c 65536 "$GPATH" 2>/dev/null | jq -Rrs '
      ["SHIELD_CLEAR","WATCHER_APPROVED","MISSION_COMPLETE","CI_PENDING"] as $set
      | (split("\n") | map(select(test("\\A- Gates:"))) | .[0]) as $l
      | if $l == null then empty
        else ([($l | sub("\\A- Gates:"; "") | split("\u00b7")[]
                 | gsub("\\A[ \t]+|[ \t\r]+\\z"; "") | split(" ") | map(select(length > 0)))
               | select(length >= 2 and .[1] != "\u2014") | .[0]]) as $on
             | [$set[] | select(. as $n | $on | index($n) != null)] | tojson
        end' 2>/dev/null) || GNEW=""
    case "$GNEW" in "["*"]") ;; *) GNEW="" ;; esac
  fi
  GPATH=""
fi
if [ -n "$GNEW" ]; then
  GLAST="[]"
  if [ -f "$GATEF" ] && [ ! -L "$GATEF" ]; then
    if private_file_ok "$GATEF"; then
      GLAST=$(cat "$GATEF" 2>/dev/null) || GLAST="[]"
      case "$GLAST" in "["*"]") ;; *) GLAST="[]" ;; esac
    else GNEW=""; fi
  elif ! private_file_ok "$GATEF"; then GNEW=""; fi
  if [ -n "$GNEW" ] && [ "$GNEW" != "$GLAST" ]; then
    GATELINE=$(jq -nc --argjson g "$GNEW" --arg at "$AT" '{type: "gates", gates: $g, at: $at}' 2>/dev/null) || GATELINE=""
  fi
fi
if [ -n "$GATELINE" ]; then
  if [ -n "$EVENTS" ]; then EVENTS="$EVENTS"$'\n'"$GATELINE"; else EVENTS="$GATELINE"; fi
fi

[ -n "$EVENTS" ] || exit 0
private_file_ok "$SPOOL" || exit 0
private_file_ok "$STATEF" || exit 0

# seq (BR-05): max(previous + 1, Unix ms) per event, counter in $HASH.seq. A missing, corrupt, foreign or absurd
# (more than a day ahead of the clock, 2^53 or more) counter heals to 0. The counter is written before the
# lines, so a crash can leave a gap but never a repeated seq.
SEQF="$LIVE_DIR/$HASH.seq"
MS=$(now_ms); PREV=0
if [ -f "$SEQF" ] && [ ! -L "$SEQF" ] && private_file_ok "$SEQF"; then
  IFS= read -r PREV <"$SEQF" 2>/dev/null
  if [[ "$PREV" =~ ^(0|[1-9][0-9]{0,15})$ ]] && [ "$PREV" -lt 9007199254740991 ] && [ "$PREV" -le $((MS + 86400000)) ]; then :; else PREV=0; fi
fi
SEQJQ='reduce inputs as $e ({p: $p, o: []}; (if .p + 1 > $ms then .p + 1 else $ms end) as $s | .p = $s | .o += [{seq: $s} + $e])
  | .o[], .p'
SEQOUT=$(printf '%s\n' "$EVENTS" | jq -c -n --argjson p "$PREV" --argjson ms "$MS" "$SEQJQ" 2>/dev/null) \
  || SEQOUT=$(printf '%s\n' "$EVENTS" | jq -c -n --argjson p 0 --argjson ms "$MS" "$SEQJQ" 2>/dev/null) || exit 0
NEWSEQ="${SEQOUT##*$'\n'}"; EVENTS="${SEQOUT%$'\n'*}"
[[ "$NEWSEQ" =~ ^[0-9]{1,16}$ ]] && [ -n "$EVENTS" ] || exit 0
TMP=$(mktemp "$LIVE_DIR/.seq.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
printf '%s' "$NEWSEQ" >"$TMP" 2>/dev/null && mv -f "$TMP" "$SEQF" 2>/dev/null || { rm -f "$TMP" 2>/dev/null; exit 0; }

# The lines first, then the state that records them as sent: if the append fails nothing is claimed.
if [ -s "$SPOOL" ] && [ -n "$(tail -c 1 "$SPOOL" 2>/dev/null)" ]; then EVENTS=$'\n'"$EVENTS"; fi   # torn tail: start on a fresh line
printf '%s\n' "$EVENTS" >>"$SPOOL" 2>/dev/null || exit 0
spool_trim "$SPOOL" "$LIVE_DIR"
if [ -n "$NEWLAST" ] && [ "$NEWLAST" != "$LAST" ]; then
  TMP=$(mktemp "$LIVE_DIR/.state.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s' "$NEWLAST" >"$TMP" 2>/dev/null && mv -f "$TMP" "$STATEF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi
if [ -n "$BINDLINE" ]; then
  TMP=$(mktemp "$LIVE_DIR/.bind.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s|%s' "$NR" "$CAND" >"$TMP" 2>/dev/null && mv -f "$TMP" "$BINDF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi
if [ -n "$GATELINE" ]; then
  TMP=$(mktemp "$LIVE_DIR/.gates.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s' "$GNEW" >"$TMP" 2>/dev/null && mv -f "$TMP" "$GATEF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi
exit 0
