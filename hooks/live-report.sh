#!/bin/bash
# Claude Code Live reporter (ALY-203). One asynchronous hook script that branches on hook_event_name.
# Slices ALY-203.2/.3/.5/.6: confirmed events are reduced to contract events, spooled locally with a seq, and sent in batches;
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
HOOK_T0="${EPOCHREALTIME:-}"   # ALY-217.7 (D-27): the start of this run, for the 1.5 s SessionEnd budget (bash 5; empty on 3.2)

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
# A `disabled` marker (written after a 401, BR-07) holds `cred:<sha256 of the token>` and is cleared by the next
# pairing, i.e. when the credential file now holds another token. Any other marker (empty, foreign mode, symlink) keeps
# the reporter inert until it is removed.
if [ -L "$LIVE_DIR/disabled" ]; then exit 0; fi
if [ -e "$LIVE_DIR/disabled" ]; then
  MK=""
  if [ -f "$LIVE_DIR/disabled" ] && [ -n "$(find "$LIVE_DIR/disabled" -prune -type f -user "$UID_NOW" -perm 0600 -print 2>/dev/null)" ]; then
    { IFS= read -r MK <"$LIVE_DIR/disabled"; } 2>/dev/null
  fi
  CFP=$(printf '%s' "$LIVE_TOKEN" | sha_hex) || exit 0
  [[ "$MK" =~ ^cred:[0-9a-f]{64}$ ]] && [ "$MK" != "cred:$CFP" ] || exit 0
  rm -f "$LIVE_DIR/disabled" 2>/dev/null
fi
CFP=""


# ─── ALY-203.2: extract allowlisted events from the payload and spool them ───
# BR-02: every value is read by the allowlisted jq program below and matched against its pattern or
# enumeration inside it; a value that fails is DROPPED (never truncated, never sent). Prompts, commands,
# tool inputs and outputs, paths, messages, transcripts and the cwd are never read into the output; the one exception is
# the activity phrase of ALY-217.6 (an agent-written description or todo form, cleaned and redacted by actphrase in that
# same jq program before anything is spooled or stashed; off while $CLAUDE_PLUGIN_DATA/live/activity-off exists).
# AC-14: files are keyed by the SHA-256 hex of the session id; the raw id is never written anywhere.
# Flush (ALY-203.6/.7, BR-04/06/07/12): see the block before the end of the file.
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
# (The payload is read further down, after the function definitions and the watcher-mode dispatch of ALY-217.)

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
  if [ -e "$1/p" ]; then pidlock_stale "$1"; return; fi   # a pid lock (ALY-217): stale once its holder is gone
  { IFS=' ' read -r ts _ <"$1/t"; } 2>/dev/null
  now=$(date +%s 2>/dev/null) || now=""
  if [[ "$ts" =~ ^[0-9]{1,12}$ ]] && [[ "$now" =~ ^[0-9]{1,12}$ ]]; then [ $((now - ts)) -gt 30 ]; return; fi
  [ -d "$1" ] && [ ! -L "$1" ] && [ -n "$(find "$1" -prune -mmin +1 -print 2>/dev/null)" ]
}
# lock_take DIR TRIES [PID]: a mkdir lock (D-03, portable). TRIES x 20 ms of waiting after the first attempt (0 = try
# once). The holder writes "<epoch> <token>" into DIR/t and keeps its token in LOCK_TOKEN; with PID it is a pid lock
# instead: DIR/p holds "<PID> <start time of PID>" (see pidlock_rec). A stale lock is renamed
# to a unique name by the one breaker holding DIR.brk, judged again there, and only then removed; if the renamed lock turns out fresh (it was replaced
# meanwhile) it is put back and this try fails closed.
lock_take() {
  local d="$1" n="${2:-0}" i=0 old
  LOCK_TOKEN="$$.$RANDOM$RANDOM"
  while :; do
    # mkdir alone does not decide: uutils coreutils (Ubuntu 25.10+) can report success to several concurrent callers, so
    # the lock is the exclusive (noclobber, O_EXCL) creation of DIR/t; a mkdir "winner" that loses that claim has not got it.
    if mkdir "$d" 2>/dev/null && ( set -C; if [ -n "${3:-}" ]; then pidlock_rec "$3" >"$d/p"; else printf '%s %s' "$(date +%s 2>/dev/null)" "$LOCK_TOKEN" >"$d/t"; fi ) 2>/dev/null; then return 0; fi
    if lock_is_stale "$d"; then
      # Only one breaker at a time (a second mkdir lock, itself broken after a minute), so nobody can replace the
      # lock between the verdict and the rename; the renamed lock is judged once more as a safety net.
      [ -n "$(find "$d.brk" -prune -mmin +1 -print 2>/dev/null)" ] && rm -rf "$d.brk" 2>/dev/null
      if mkdir "$d.brk" 2>/dev/null && ( set -C; : >"$d.brk/own" ) 2>/dev/null; then   # same claim as above
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
# ─── ALY-217.1: pid locks (D-20). DIR/p holds "<holder pid> <holder start>"; the lock is stale at once when that
# process is gone (no such pid, a zombie, or the pid now belongs to a process with another start time). ───
# proc_start PID: the start time of a live process (Linux: field 22 of /proc/PID/stat, read after the last `)`;
# elsewhere: the digits of `ps -o lstart=`, 0 when ps is missing). Fails when the process is gone.
proc_start() {
  local l
  [[ "$1" =~ ^[1-9][0-9]{0,9}$ ]] || return 1
  if [ -r "/proc/$1/stat" ]; then
    { IFS= read -r l <"/proc/$1/stat"; } 2>/dev/null || return 1
    l=${l##*) }; set -- $l
    [ "${1:-}" != Z ] && [[ "${20:-}" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "${20}"; return 0
  fi
  kill -0 "$1" 2>/dev/null || return 1
  l=$(ps -o lstart= -p "$1" 2>/dev/null) || l=""; l=${l//[!0-9]/}
  printf '%s' "${l:-0}"
}
pidlock_rec() { local s; s=$(proc_start "$1") || s=""; printf '%s %s' "$1" "$s"; }
pidlock_stale() {
  local p="" s="" cur
  { IFS=' ' read -r p s <"$1/p"; } 2>/dev/null
  if [[ "$p" =~ ^[0-9]{1,10}$ ]]; then cur=$(proc_start "$p") || return 0; [ "$cur" != "$s" ]; return; fi
  [ -d "$1" ] && [ ! -L "$1" ] && [ -n "$(find "$1" -prune -mmin +1 -print 2>/dev/null)" ]   # no readable holder
}
# pidlock_pass DIR FROM TO: the holder record moves from pid FROM to pid TO (temp + mv), only while DIR/p names FROM.
pidlock_pass() {
  local p="" t="$1/p.$3.$RANDOM"
  { IFS=' ' read -r p _ <"$1/p"; } 2>/dev/null
  [ -n "${2:-}" ] && [ "$p" = "$2" ] || return 1
  pidlock_rec "$3" >"$t" 2>/dev/null && mv -f "$t" "$1/p" 2>/dev/null || { rm -f "$t" 2>/dev/null; return 1; }
}
# pidlock_drop DIR PID: removes the lock only while DIR/p names PID.
pidlock_drop() {
  local p=""
  { IFS=' ' read -r p _ <"$1/p"; } 2>/dev/null
  [ -n "${2:-}" ] && [ "$p" = "$2" ] && rm -rf "$1" 2>/dev/null
  return 0
}
# lock_drop DIR TOKEN: removes the lock only while DIR/t still holds this hook's own token.
lock_drop() {
  local t=""
  { IFS=' ' read -r _ t <"$1/t"; } 2>/dev/null
  [ -n "${2:-}" ] && [ "$t" = "$2" ] && rm -rf "$1" 2>/dev/null
  return 0
}
# wall_ms [EPOCHREALTIME value]: wall-clock Unix ms from bash's EPOCHREALTIME (bash 5; never the date shim), else now_ms.
wall_ms() { local t="${1-${EPOCHREALTIME:-}}"; if [[ "$t" =~ ^([0-9]{1,12})[.,]([0-9]{3}) ]]; then printf '%s' "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; else now_ms; fi; }
# uutils coreutils (Ubuntu 25.10+) ignores the width in %3N and prints nanoseconds: keep seconds + the first 3 digits.
now_ms() { local m; m=$(date +%s%3N 2>/dev/null); [[ "$m" =~ ^[0-9]{13,19}$ ]] && m=${m:0:13} || m="$(date +%s 2>/dev/null)000"; printf '%s' "$m"; }
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

# ─── ALY-203.6: flush (BR-04, BR-06) ───
# The flusher is a detached subshell started by the hook that appended the lines, holding the flush lock
# $HASH.flush.lock (a mkdir lock taken in the foreground, try once, so at most one flusher runs; its time is
# refreshed before every batch so the 30-second break never hits a live flusher). It never takes the state lock
# while talking to curl: it reads a snapshot of the complete spool lines, sends, and only then takes the state lock
# briefly to rewrite the spool without the sent lines (seq order is file order, so "sent" is seq <= the batch max).
# Invalid or torn lines are skipped and dropped with the sent ones.
# lock_touch DIR TOKEN: refresh the holder time, only while DIR/t still holds this token; written by temp + mv.
lock_touch() {
  local t=""
  { IFS=' ' read -r _ t <"$1/t"; } 2>/dev/null
  [ -n "${2:-}" ] && [ "$t" = "$2" ] || return 1
  printf '%s %s' "$(date +%s 2>/dev/null)" "$2" >"$1/t.$$" 2>/dev/null && mv -f "$1/t.$$" "$1/t" 2>/dev/null || { rm -f "$1/t.$$" 2>/dev/null; return 1; }
}
# jq_valid_def: the jq definitions shared by the batch builder and the spool rewrite (a line is a valid event or it is dropped).
jq_valid_def() {
  # keep: the event keys, then the keys of `sub` (the nested allowlist: desc ALY-258.1; summary, attempt, next, gate, checks and
  # findings ALY-258.2). A nested value of the wrong type or range is dropped, never repaired (checks/findings: all or nothing).
  printf '%s' 'def i99: type == "number" and . == floor and . >= 0 and . <= 99;
    def pick($ks): with_entries(select(.key | IN($ks[]))) | if (keys | length) == ($ks | length) and all(.[]; i99) then . else null end;
    def subfld: if .key == "summary" then (.value | type == "string" and (explode | length) <= 140)
      elif .key == "attempt" then (.value | type == "number" and IN(0, 1, 2))
      elif .key == "next" then (.value | IN("reviewers","pilot_correction","mothership","watcher","done"))
      elif .key == "gate" then (.value | IN("SHIELD_CLEAR","WATCHER_APPROVED"))
      elif .key == "checks" then (.value | type == "object" and (pick(["ok","run"]) != null))
      elif .key == "findings" then (.value | type == "object" and (pick(["critical","high","medium","low","info"]) != null))
      else true end;
    def keep: with_entries(select(.key | IN("seq","at","type","state","tool","code","sub","bind","gates","activity")))
      | (if (.sub | type) == "object" then .sub |= (with_entries(select(.key | IN("id","type","outcome","task","desc","summary","attempt","next","gate","checks","findings")) | select(subfld))
          | (if has("checks") then .checks |= pick(["ok","run"]) else . end)
          | (if has("findings") then .findings |= pick(["critical","high","medium","low","info"]) else . end)) else . end);
    def ok: type == "object" and (.seq | type == "number" and . == floor and . >= 1) and (.at | type == "string")
            and (.type | IN("state","tool","sub_start","sub_tool","sub_stop","bind","gates"));
    def fresh($now): ((.at | try fromdateiso8601 catch 0) >= ($now - 82800));'
}
# credfp: CFP = sha256 of the token (identifies the credential without storing it).
credfp() { [ -n "$CFP" ] || CFP=$(printf '%s' "$LIVE_TOKEN" | sha_hex); return 0; }
# backoff_active: a back-off file `<until epoch> <credential fingerprint>` written for this credential and not over.
backoff_active() {
  local u="" f="" now
  [ -f "$BACKOFFF" ] && [ ! -L "$BACKOFFF" ] && private_file_ok "$BACKOFFF" || return 1
  { IFS=' ' read -r u f <"$BACKOFFF"; } 2>/dev/null
  credfp
  [[ "$u" =~ ^[0-9]{1,12}$ ]] && [ "$f" = "$CFP" ] || return 1
  now=$(date +%s 2>/dev/null) || return 1
  [[ "$now" =~ ^[0-9]{1,12}$ ]] && [ "$now" -lt "$u" ]
}
backoff_set() {  # SECONDS from now, for this credential
  local now tmp
  now=$(date +%s 2>/dev/null) || return 0; credfp
  tmp=$(mktemp "$LIVE_DIR/.backoff.XXXXXX" 2>/dev/null) || return 0; TMPF="$tmp"
  printf '%s %s' "$((now + $1))" "$CFP" >"$tmp" 2>/dev/null && mv -f "$tmp" "$BACKOFFF" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
# batch_build: sets BK (physical lines consumed), BMAX (highest seq in the batch) and BODY (the request body, empty
# when the consumed lines held no valid event). At most 50 events and 16384 bytes of body; only contract keys are kept.
batch_build() {
  local n base out rest now
  BK=0; BMAX=0; BODY=""
  now=$(date +%s 2>/dev/null) || return 1; [[ "$now" =~ ^[0-9]{1,12}$ ]] || return 1
  [ -f "$SPOOL" ] && [ ! -L "$SPOOL" ] || return 1
  n=$(wc -l <"$SPOOL" 2>/dev/null); n=${n//[[:space:]]/}
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || return 1
  base=$(printf '{"client":{"kind":"claude-code"},"session":{"hash":"%s"},"events":[' "$HASH")
  out=$(head -n "$n" "$SPOOL" 2>/dev/null | jq -Rn -r --arg base "$base" --argjson now "$now" "$(jq_valid_def)"'
    [inputs] as $L
    | (reduce range(0; $L | length) as $i ({evs: [], size: (($base | utf8bytelength) + 2), k: 0, max: 0, done: false};
        if .done then .
        else (($L[$i] | try fromjson catch null)) as $e
          | if ($e | ok | not) then .k = $i + 1
            elif ($e | fresh($now) | not) then .k = $i + 1 | .max = ([.max, $e.seq] | max)
            else ($e | keep) as $ev | ($ev | tojson | utf8bytelength) as $len
              | (if (.evs | length) > 0 then 1 else 0 end) as $sep
              | if ((.evs | length) >= 50) or (((.evs | length) > 0) and ((.size + $sep + $len) > 16384)) then .done = true
                elif (.size + $sep + $len) > 16384 then .k = $i + 1 | .max = ([.max, $ev.seq] | max)
                else .evs += [$ev] | .size += $sep + $len | .k = $i + 1 | .max = ([.max, $ev.seq] | max) end
            end
        end)) as $r
    | $r.k, $r.max, (if ($r.evs | length) > 0 then ($base + ($r.evs | map(tojson) | join(",")) + "]}") else "" end)' 2>/dev/null) || return 1
  BK=${out%%$'\n'*}; rest=${out#*$'\n'}; BMAX=${rest%%$'\n'*}; BODY=""; case "$rest" in *$'\n'*) BODY=${rest#*$'\n'} ;; esac   # an empty body leaves no third line
  [[ "$BK" =~ ^[0-9]+$ ]] && [[ "$BMAX" =~ ^[0-9]+$ ]] && [ "$BK" -gt 0 ] || { BK=0; BMAX=0; BODY=""; return 1; }
  return 0
}
# spool_drop_sent MAX: under the state lock, rewrite the spool without invalid lines and without lines with
# seq <= MAX, MAX being the highest seq of every line the snapshot consumed, sent or skipped (lines appended since
# have a higher seq and stay). The file is replaced by mv, no fd held.
spool_drop_sent() {
  local tmp tok now
  now=$(date +%s 2>/dev/null) || return 1; [[ "$now" =~ ^[0-9]{1,12}$ ]] || return 1
  lock_take "$LOCKD" "${DROP_TRIES:-250}" || return 1
  tok="$LOCK_TOKEN"
  if private_file_ok "$SPOOL" && tmp=$(mktemp "$LIVE_DIR/.spool.XXXXXX" 2>/dev/null); then
    TMPF="$tmp"
    if jq -R -c --argjson m "$1" --argjson now "$now" "$(jq_valid_def)"' fromjson? | select(ok and fresh($now) and .seq > $m)' "$SPOOL" >"$tmp" 2>/dev/null; then
      mv -f "$tmp" "$SPOOL" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else rm -f "$tmp" 2>/dev/null; fi
  fi
  lock_drop "$LOCKD" "$tok"
  return 0
}
# mark_disabled: 401 with an invalid-credential or inactive-account code. The marker names the credential it was
# written for and the spool is discarded; the next pairing clears the marker and the session opens with `state started`.
mark_disabled() {
  local tmp old_token="$LIVE_TOKEN" old_api="$LIVE_API" cur
  credfp
  # Only for the credential that was flushing: after a re-pair a late 401 for the old token must neither disable nor
  # discard what was spooled with the new one (lines of the old credential then stay and go out with the new token).
  load_live_credential "$DIR" || { LIVE_TOKEN="$old_token"; LIVE_API="$old_api"; return 0; }
  cur=$(printf '%s' "$LIVE_TOKEN" | sha_hex); LIVE_TOKEN="$old_token"; LIVE_API="$old_api"
  [ "$cur" = "$CFP" ] || return 0
  tmp=$(mktemp "$LIVE_DIR/.disabled.XXXXXX" 2>/dev/null) || return 0; TMPF="$tmp"
  printf 'cred:%s' "$CFP" >"$tmp" 2>/dev/null && mv -f "$tmp" "$LIVE_DIR/disabled" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  spool_drop_sent 9007199254740991   # if this cannot take the state lock the marker still blocks every send
  return 0
}
# flush_run: the detached part. Returns 0 when the spool was worked through, 1 when it stopped on a failure,
# a back-off, a lost lock or a round that removed nothing. Answers (BR-07): 2xx the batch is sent; 400/413 the batch
# is discarded and the next one tried; 401 with HOOK_CREDENTIAL_INVALID or an inactive-account code disables;
# 403 back-off 1 h; 422 back-off 10 min; 429 back-off Retry-After (1 s to 1 h, 60 s when unreadable); anything
# else (5xx, network, redirects) keeps the spool and retries at a later hook. The response code is read from a
# bounded body with jq and never printed or stored.
# ALY-217.7 (D-27): with FLUSH_DEADLINE (wall-clock Unix ms) set, a round starts only while at least 200 ms are left, and
# its curl limits are cut to what is left (the SessionEnd budget).
flush_run() {
  local rounds=0 status ecode ra before left mt ct
  case "$LIVE_DIR" in *[\"\\]*) return 1 ;; esac   # the path goes into a curl config string
  while [ "$rounds" -lt 20 ]; do
    rounds=$((rounds + 1))
    # at the top of every round: another session may have been told to back off or to disable meanwhile
    if [ -e "$LIVE_DIR/disabled" ] || [ -L "$LIVE_DIR/disabled" ] || [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ] || backoff_active; then return 1; fi
    before=$(wc -c <"$SPOOL" 2>/dev/null) || return 1
    batch_build || return 0
    if [ -z "$BODY" ]; then
      spool_drop_sent "$BMAX" || return 1
      [ "$(wc -c <"$SPOOL" 2>/dev/null)" != "$before" ] || return 1   # nothing was removed: no progress
      continue
    fi
    mt="${SEND_MAXTIME:-8}"; ct="${SEND_CONNECT:-3}"
    if [ -n "${FLUSH_DEADLINE:-}" ]; then
      left=$((FLUSH_DEADLINE - $(wall_ms))); [ "$left" -ge 200 ] || return 1
      if [ "$left" -lt $((mt * 1000)) ]; then mt=$(printf '%d.%03d' $((left / 1000)) $((left % 1000))); [ "$left" -ge $((ct * 1000)) ] || ct="$mt"; fi
    fi
    lock_touch "$FLOCK" "$FTOK" || return 1   # the lock is no longer ours: stop
    printf '%s' "$BODY" >"$BATCHF" 2>/dev/null || return 1
    status=$({
      printf 'url = "%s/api/agent-runs/events"\n' "$LIVE_API"
      printf 'header = "Authorization: Bearer %s"\n' "$LIVE_TOKEN"
      printf 'header = "Content-Type: application/json"\n'
      printf 'header = "Accept: application/json"\n'
      printf 'data-binary = "@%s"\n' "$BATCHF"
      printf 'max-time = %s\nconnect-timeout = %s\nmax-filesize = 65536\nnoproxy = "*"\n' "$mt" "$ct"
    } | curl -q --silent -K - -D "$HDRF" -o "$RESPF" -w '%{http_code}' 2>/dev/null) || { rm -f "$BATCHF" "$HDRF" "$RESPF" 2>/dev/null; return 1; }
    rm -f "$BATCHF" 2>/dev/null
    [[ "$status" =~ ^[0-9]{3}$ ]] || { rm -f "$HDRF" "$RESPF" 2>/dev/null; return 1; }
    ecode=$(head -c 65536 "$RESPF" 2>/dev/null | jq -r '.error.message.code | strings' 2>/dev/null | head -n 1); rm -f "$RESPF" 2>/dev/null
    [[ "$ecode" =~ ^[A-Z_]{1,60}$ ]] || ecode=""
    case "$status" in
      2??|400|413)
        spool_drop_sent "$BMAX" || return 1
        [ "$(wc -c <"$SPOOL" 2>/dev/null)" != "$before" ] || return 1 ;;   # a batch that removed nothing: stop
      401)
        case "$ecode" in
          HOOK_CREDENTIAL_INVALID|USER_INACTIVE|MEMBERSHIP_INACTIVE|TENANT_INACTIVE) mark_disabled ;;
          *) backoff_set 600 ;;
        esac
        rm -f "$HDRF" 2>/dev/null; return 1 ;;
      # 403 and 422 back off whatever the code (more conservative than the codes BR-07 names)
      403) backoff_set 3600; rm -f "$HDRF" 2>/dev/null; return 1 ;;
      422) backoff_set 600; rm -f "$HDRF" 2>/dev/null; return 1 ;;
      429)
        ra=$(grep -i '^retry-after:' "$HDRF" 2>/dev/null | head -n 1 | tr -d '\r'); ra=${ra#*:}; ra=${ra//[[:space:]]/}
        if [[ "$ra" =~ ^[0-9]{1,9}$ ]]; then ra=$((10#$ra)); else ra=60; fi
        [ "$ra" -ge 1 ] || ra=1; [ "$ra" -le 3600 ] || ra=3600
        backoff_set "$ra"; rm -f "$HDRF" 2>/dev/null; return 1 ;;
      *) rm -f "$HDRF" 2>/dev/null; return 1 ;;
    esac
    rm -f "$HDRF" 2>/dev/null
  done
  return 0
}
# flush_loop: runs flush_run, releases the flush lock, then looks at the spool again: a line appended while the last
# pass was finishing (its hook found the lock taken and skipped its own flush) is picked up by another pass (at most 3).
flush_loop() {
  local pass=0 rc
  while :; do
    pass=$((pass + 1))
    flush_run; rc=$?
    lock_drop "$FLOCK" "$FTOK"
    [ "$rc" = 0 ] && [ -s "$SPOOL" ] && [ "$pass" -lt 3 ] || return 0
    lock_take "$FLOCK" 0 || return 0
    FTOK="$LOCK_TOKEN"
  done
}
# flushed_ms: the start of the last flush in Unix ms from $HASH.flushed (13 digits = ms; up to 12 digits = epoch
# seconds, as written by the older version); empty when unknown.
flushed_ms() {
  local last=""
  if [ -f "$FLUSHED" ] && [ ! -L "$FLUSHED" ] && private_file_ok "$FLUSHED"; then { IFS= read -r last <"$FLUSHED"; } 2>/dev/null; fi
  if [[ "$last" =~ ^[0-9]{13}$ ]]; then printf '%s' "$((10#$last))"
  elif [[ "$last" =~ ^[0-9]{1,12}$ ]]; then printf '%s000' "$((10#$last))"; fi
}
stamp_flushed() {  # the flush starts now: $HASH.flushed = Unix ms (temp + mv)
  local tmp
  tmp=$(mktemp "$LIVE_DIR/.flushed.XXXXXX" 2>/dev/null) || return 0; TMPF="$tmp"
  now_ms >"$tmp" 2>/dev/null && mv -f "$tmp" "$FLUSHED" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
flush_due() {  # important events flush at once, others when 2 seconds passed since the last flush started; FLUSH_REM = ms left
  local last now
  FLUSH_REM=0
  [ "$IMPORTANT" = 1 ] && return 0
  last=$(flushed_ms); now=$(now_ms)
  [ -n "$last" ] && [[ "$now" =~ ^[0-9]{13}$ ]] || return 0
  FLUSH_REM=$((2000 - (10#$now - last)))
  [ "$FLUSH_REM" -le 0 ] && { FLUSH_REM=0; return 0; }
  [ "$FLUSH_REM" -le 2000 ] || FLUSH_REM=2000   # a stamp in the future (the clock went back): wait at most 2 s
  return 1
}
# flush_sleeper: the delayed flush (D-20), detached, holding $HASH.flush.wait (a pid lock naming itself) while it sleeps
# FLUSH_REM ms. Awake, it sends nothing when the session is ended, Live is off or disabled, a back-off is active, the
# credential is gone or changed, or the spool is empty; otherwise it tries the flush lock every 100 ms for up to 10 s,
# releases flush.wait (so a line spooled during its send can arm the next sleeper) and runs the normal flush loop.
flush_sleeper() {
  local i=0 st="" old="$CFP"
  sleep "$(printf '%d.%03d' $((FLUSH_REM / 1000)) $((FLUSH_REM % 1000)))"
  if [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ] || [ -e "$LIVE_DIR/disabled" ] || [ -L "$LIVE_DIR/disabled" ]; then return 0; fi
  if [ -f "$STATEF" ] && [ ! -L "$STATEF" ]; then { IFS= read -r st <"$STATEF"; } 2>/dev/null; fi
  [ "$st" != ended ] || return 0
  load_live_credential "$DIR" || return 0
  CFP=""; credfp; [ -n "$old" ] && [ "$CFP" = "$old" ] || return 0
  backoff_active && return 0
  [ -s "$SPOOL" ] || return 0
  until lock_take "$FLOCK" 0; do i=$((i + 1)); [ "$i" -lt 100 ] || return 0; sleep 0.1; done
  FTOK="$LOCK_TOKEN"
  stamp_flushed
  pidlock_drop "$WAITD" "$ME"
  flush_loop
}

# ─── ALY-217.7: the SessionEnd send and the final flusher (D-27, BR-15, NFR-06) ───
# spool_has_end: the spool still holds a `state ended` line (lines are compact jq output, so the text match is exact).
spool_has_end() { [ -f "$SPOOL" ] && [ ! -L "$SPOOL" ] && grep -q '"state":"ended"' "$SPOOL" 2>/dev/null; }
# end_send: SessionEnd, after the state lock is released. In the foreground and bounded: the whole hook stays within 1.5 s
# (deadline 1.3 s after its start, the rest left for the exit). Unless a back-off is active, flush.lock is tried every
# 100 ms for up to 400 ms; with it the spool is sent in order (the ended event last, it has the highest seq) with 1 s
# limits cut to the budget. When the lock stayed busy, a send failed, the budget ran out or an ended line is still in the
# spool, the send is handed to the final flusher. A send that delivered everything starts nothing.
end_send() {
  local i=0 t0
  t0=$(wall_ms "$HOOK_T0"); [ -n "$HOOK_T0" ] || t0=$((t0 - 300))   # bash 3.2: no start stamp, assume 300 ms spent
  [[ "$t0" =~ ^[0-9]{13}$ ]] || return 0
  FLUSH_DEADLINE=$((t0 + 1300))
  if ! backoff_active; then
    while [ $((FLUSH_DEADLINE - $(wall_ms))) -ge 300 ]; do
      if lock_take "$FLOCK" 0; then
        FTOK="$LOCK_TOKEN"; EFTOK="$FTOK"; stamp_flushed
        SEND_MAXTIME=1; SEND_CONNECT=1; DROP_TRIES=10
        flush_run
        rm -f "$BATCHF" "$HDRF" "$RESPF" 2>/dev/null
        lock_drop "$FLOCK" "$EFTOK"; EFTOK=""; FTOK=""
        break
      fi
      i=$((i + 1)); [ "$i" -le 4 ] || break
      sleep 0.1
    done
  fi
  FLUSH_DEADLINE=""; DROP_TRIES=""
  spool_has_end && final_start
  return 0
}
# final_start: at most one final flusher per session through $HASH.final.lock (a pid lock, taken at the first try for this
# hook, then passed to the flusher). The flusher is this script in `final` mode: stdio on /dev/null, SIGHUP ignored, in a
# session of its own through setsid when present.
final_start() {
  local ss=""
  command -v setsid >/dev/null 2>&1 && ss=setsid
  lock_take "$FINALD" 0 "$$" || return 0   # one is already running: it keeps the send (AC-39)
  (
    trap '' HUP
    LIVE_HASH="$HASH" exec $ss "$BASH" "$_src" final
  ) </dev/null >/dev/null 2>&1 &
  pidlock_pass "$FINALD" "$$" "$!" || pidlock_drop "$FINALD" "$$"
}
# final_main: final mode (`live-report.sh final`), reached only after the checks at the top of this file. It runs while
# final.lock names it (it waits up to 2 s for the hook to pass the record), records the credential fingerprint, then
# makes one attempt at once and one after each delay of 2, 5, 15, 30 and 60 s (ALLYE_LIVE_FINAL_DELAYS, test-only: up
# to 5 whole seconds of at most 2 digits). It exits when an attempt leaves no ended line in the spool, when Live is off
# or disabled or the credential is gone or changed, or after its last attempt; on exit it removes final.lock.
final_main() {
  local i=0 d p="" old delays="${ALLYE_LIVE_FINAL_DELAYS:-2 5 15 30 60}"
  HASH="${LIVE_HASH:-}"
  [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || return 0
  [[ "$delays" =~ ^[0-9]{1,2}( [0-9]{1,2}){0,4}$ ]] || delays="2 5 15 30 60"
  live_dir_ok || return 0
  SPOOL="$LIVE_DIR/$HASH.spool"; STATEF="$LIVE_DIR/$HASH.state"; LOCKD="$LIVE_DIR/$HASH.lock"; FLOCK="$LIVE_DIR/$HASH.flush.lock"
  FLUSHED="$LIVE_DIR/$HASH.flushed"; BATCHF="$LIVE_DIR/$HASH.batch"; HDRF="$LIVE_DIR/$HASH.hdr"; RESPF="$LIVE_DIR/$HASH.resp"
  BACKOFFF="$LIVE_DIR/backoff"; FINALD="$LIVE_DIR/$HASH.final.lock"
  ME=""; FSLEEP=""; FTOK=""; TMPF=""
  trap final_exit EXIT
  trap 'exit 0' INT TERM
  cd / 2>/dev/null
  until { p=""; { IFS=' ' read -r p _ <"$FINALD/p"; } 2>/dev/null; [ "$p" = "$$" ]; }; do
    i=$((i + 1)); [ "$i" -le 20 ] || return 0
    sleep 0.1
  done
  ME=$$
  CFP=""; credfp; old="$CFP"; LIVE_TOKEN=""
  [[ "$old" =~ ^[0-9a-f]{64}$ ]] || return 0
  for d in 0 $delays; do
    if [ "$d" != 0 ]; then sleep "$d" & FSLEEP=$!; wait "$FSLEEP"; FSLEEP=""; fi
    final_attempt "$old" && return 0
  done
  return 0
}
# final_attempt FINGERPRINT: returns 1 when the send must be tried again, 0 when there is nothing (more) to do.
final_attempt() {
  local i=0
  if [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ] || [ -e "$LIVE_DIR/disabled" ] || [ -L "$LIVE_DIR/disabled" ]; then return 0; fi
  spool_has_end || return 0
  load_live_credential "$DIR" || return 0
  CFP=""; credfp; [ "$CFP" = "$1" ] || { LIVE_TOKEN=""; return 0; }
  backoff_active && { LIVE_TOKEN=""; return 1; }   # honoured: this attempt sends nothing
  until lock_take "$FLOCK" 0; do i=$((i + 1)); [ "$i" -lt 100 ] || { LIVE_TOKEN=""; return 1; }; sleep 0.1; done
  FTOK="$LOCK_TOKEN"; stamp_flushed
  SEND_MAXTIME=8; SEND_CONNECT=3
  flush_run
  rm -f "$BATCHF" "$HDRF" "$RESPF" 2>/dev/null
  lock_drop "$FLOCK" "$FTOK"; FTOK=""; LIVE_TOKEN=""
  if spool_has_end; then return 1; fi
  return 0
}
final_exit() {
  [ -z "$FSLEEP" ] || kill "$FSLEEP" 2>/dev/null   # this flusher's own sleep child
  LIVE_TOKEN=""
  [ -z "$TMPF" ] || rm -f "$TMPF" "$TMPF.2" 2>/dev/null
  if [ -n "$FTOK" ]; then rm -f "$BATCHF" "$HDRF" "$RESPF" 2>/dev/null; lock_drop "$FLOCK" "$FTOK"; fi
  [ -z "$ME" ] || pidlock_drop "$FINALD" "$ME"
  return 0
}

# ─── ALY-217.2: the session watcher (D-21, BR-03, BR-06, BR-07) ───
# The owner is the Claude Code process the session belongs to. owner_find PID walks up from PID (the hook's parent):
# shells (sh, bash, dash, zsh, ksh, fish; a leading `-` stripped) and wrappers (env, timeout, nohup, stdbuf, setsid,
# flock, script) are skipped; the walk stops at a process of another uid, at PID 1 or after 8 levels; the first other
# process is the owner only if its name (the 15-character comm) is exactly claude, node, bun or node-MainThread (the
# main-thread name Node 26 gives itself); fail safe: tmux, screen, sshd, systemd are never owners. Prints "<pid> <start>". Linux reads only /proc/<pid>/stat and the owner of /proc/<pid>;
# elsewhere `ps -o ppid=,uid=,state=,comm=` (checked manually on macOS). Every value is matched as digits before use.
owner_find() {
  local p="$1" lvl=0 l c pp u st
  while [ "$lvl" -lt 8 ]; do
    lvl=$((lvl + 1))
    [[ "$p" =~ ^[1-9][0-9]{0,9}$ ]] && [ "$p" != 1 ] || return 1
    if [ -r "/proc/$p/stat" ]; then
      { IFS= read -r l <"/proc/$p/stat"; } 2>/dev/null || return 1
      c=${l#*\(}; c=${c%\)*}; l=${l##*) }; set -f; set -- $l; set +f; st="${1:-}"; pp="${2:-}"
      [ -n "$(find "/proc/$p" -prune -user "$UID_NOW" -print 2>/dev/null)" ] || return 1
    elif [ ! -d /proc/self ]; then
      l=$(ps -o ppid=,uid=,state=,comm= -p "$p" 2>/dev/null) || return 1
      set -f; set -- $l; set +f; pp="${1:-}"; u="${2:-}"; st="${3:-}"; shift 3 2>/dev/null || return 1; c="$*"; c=${c##*/}   # no globbing (set -f)
      [[ "$u" =~ ^[0-9]+$ ]] && [ "$u" = "$UID_NOW" ] || return 1
    else return 1; fi
    case "$st" in Z*) return 1 ;; esac
    c=${c#-}
    case "$c" in
      sh|bash|dash|zsh|ksh|fish|env|timeout|nohup|stdbuf|setsid|flock|script) p="$pp"; continue ;;
      claude|node|bun|node-MainThread) st=$(proc_start "$p") || return 1; [[ "$st" =~ ^[0-9]+$ ]] || return 1; printf '%s %s' "$p" "$st"; return 0 ;;
      *) return 1 ;;
    esac
  done
  return 1
}
# watch_held: a live watcher holds $HASH.watch.lock (a pid lock naming it).
watch_held() { [ -d "$WLOCK" ] && ! lock_is_stale "$WLOCK"; }
# watch_start: called with $HASH.watch.lock taken for this hook ($$). Execs this script in watcher mode under env -i
# with only PATH, HOME, CLAUDE_PLUGIN_DATA, LIVE_HASH and the digit-only test knobs ALLYE_LIVE_WATCH,
# ALLYE_LIVE_WATCH_INTERVAL and ALLYE_LIVE_WATCH_CAP (run-cap override, ALY-217.3); stdio on /dev/null, SIGHUP
# ignored, in a session of its own through setsid when present. The lock record then moves to the watcher's pid.
watch_start() {
  local w ss="" v x
  command -v setsid >/dev/null 2>&1 && ss=setsid
  (
    trap '' HUP
    set -- PATH="${PATH:-/usr/bin:/bin}" CLAUDE_PLUGIN_DATA="$DIR" LIVE_HASH="$HASH"
    [ -z "${HOME:-}" ] || set -- "$@" HOME="$HOME"
    for v in ALLYE_LIVE_WATCH ALLYE_LIVE_WATCH_INTERVAL ALLYE_LIVE_WATCH_CAP; do
      x="${!v:-}"; [[ "$x" =~ ^[0-9]{1,9}$ ]] && set -- "$@" "$v=$x"
    done
    exec $ss env -i "$@" "$BASH" "$_src" watch
  ) </dev/null >/dev/null 2>&1 &
  w=$!
  pidlock_pass "$WLOCK" "$$" "$w" || pidlock_drop "$WLOCK" "$$"
}
# watch_main: watcher mode (`live-report.sh watch`), reached only after the checks at the top of this file (absolute
# data dir, tools, valid credential, Live not off or disabled). The fingerprint of the credential is recorded at start
# and the token dropped. It holds $HASH.watch.lock; each interval (ALLYE_LIVE_WATCH_INTERVAL, whole seconds clamped to
# 1-20, default 15) it sleeps, then (ALY-217.3, BR-04, BR-05, NFR-02) refreshes its lock record (only while it names this
# watcher) and exits without sending when the lock is no longer its own, the live directory fails its owner/mode check,
# Live is off or disabled, the credential file is gone, the state is `ended`, `watch` is missing or malformed, or the
# run cap (ALLYE_LIVE_WATCH_CAP seconds, test-only; default and maximum 24 h) is reached. Then one liveness check of the
# owner named in `watch` (re-read every poll, so a later SessionStart under another owner is followed). No jq or curl
# while the owner lives. Owner gone on a first poll: $HASH.watch.gone is created; gone on the next poll too: if
# `state` or `seq` (written only by hooks; flushers rewrite only the spool) is newer than that marker a hook ran, so
# nothing is sent and the count starts over (two more clean misses are needed); otherwise watch_end. On exit, if it still holds the lock, it removes `watch`, the marker, a `flush.wait` whose holder
# is gone, and the lock.
watch_main() {
  local iv="${ALLYE_LIVE_WATCH_INTERVAL:-15}" cap="${ALLYE_LIVE_WATCH_CAP:-86400}" st own="" miss=0
  HASH="${LIVE_HASH:-}"
  [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || return 0
  [[ "$iv" =~ ^[0-9]{1,9}$ ]] || iv=15
  iv=$((10#$iv)); [ "$iv" -ge 1 ] || iv=1; [ "$iv" -le 20 ] || iv=20
  [[ "$cap" =~ ^[0-9]{1,9}$ ]] || cap=86400
  cap=$((10#$cap)); [ "$cap" -ge 1 ] && [ "$cap" -le 86400 ] || cap=86400
  live_dir_ok || return 0
  STATEF="$LIVE_DIR/$HASH.state"; WATCHF="$LIVE_DIR/$HASH.watch"; WLOCK="$LIVE_DIR/$HASH.watch.lock"; GONEF="$LIVE_DIR/$HASH.watch.gone"
  SPOOL="$LIVE_DIR/$HASH.spool"; SEQF="$LIVE_DIR/$HASH.seq"; LOCKD="$LIVE_DIR/$HASH.lock"; FLOCK="$LIVE_DIR/$HASH.flush.lock"
  WAITD="$LIVE_DIR/$HASH.flush.wait"; FLUSHED="$LIVE_DIR/$HASH.flushed"; BATCHF="$LIVE_DIR/$HASH.batch"; HDRF="$LIVE_DIR/$HASH.hdr"
  RESPF="$LIVE_DIR/$HASH.resp"; BACKOFFF="$LIVE_DIR/backoff"
  CFP=""; credfp; WCFP="$CFP"; LIVE_TOKEN=""; LIVE_API=""
  [[ "$WCFP" =~ ^[0-9a-f]{64}$ ]] || return 0
  ME=$$; WSLEEP=""; WHAVE=0; STATE_TOKEN=""; FTOK=""; TMPF=""; ENDF=""
  trap watch_exit EXIT
  trap 'exit 0' INT TERM
  cd / 2>/dev/null
  SECONDS=0
  while :; do
    sleep "$iv" & WSLEEP=$!
    wait "$WSLEEP"; WSLEEP=""
    pidlock_pass "$WLOCK" "$ME" "$ME" || return 0   # lock_touch of a pid lock: fails once the lock is not ours
    [ -d "$LIVE_DIR" ] && live_dir_ok || return 0
    watch_flags_ok || return 0
    st=""
    if [ -f "$STATEF" ] && [ ! -L "$STATEF" ]; then { IFS= read -r st <"$STATEF"; } 2>/dev/null; fi
    [ "$st" != ended ] || return 0
    watch_read || return 0
    [ "$SECONDS" -lt "$cap" ] || return 0
    if [ "$WOWN" != "$own" ]; then own="$WOWN"; miss=0; rm -f "$GONEF" 2>/dev/null; fi   # a new owner: start over
    if ! owner_gone "${own% *}" "${own#* }"; then
      [ "$miss" = 0 ] || { miss=0; rm -f "$GONEF" 2>/dev/null; }
      continue
    fi
    miss=$((miss + 1))
    if [ "$miss" = 1 ]; then
      rm -f "$GONEF" 2>/dev/null; ( set -C; : >"$GONEF" ) 2>/dev/null || return 0
      continue
    fi
    # a hook ran since the first miss (state or seq changed; flushers only rewrite the spool): start over
    if hook_since state seq; then miss=0; rm -f "$GONEF" 2>/dev/null; continue; fi
    watch_end "$own"; [ $? = 3 ] || return 0   # 3: another owner now, or a hook ran meanwhile: keep polling
    own=""; miss=0
  done
}
# watch_flags_ok: Live not off, not disabled, and the credential file still there (its content is read only at send time).
watch_flags_ok() {
  [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ] || [ -e "$LIVE_DIR/disabled" ] || [ -L "$LIVE_DIR/disabled" ] && return 1
  [ -f "$DIR/hook-credential.json" ] && [ ! -L "$DIR/hook-credential.json" ]
}
# watch_read: WOWN = the whole content of `watch`, which must be "<pid> <start>" (^[0-9]+ [0-9]+$, the pid 1-10 digits
# without a leading 0), in a private file; fails otherwise (missing, symlink, foreign mode, extra fields or lines).
watch_read() {
  local l=""
  WOWN=""
  [ -f "$WATCHF" ] && [ ! -L "$WATCHF" ] && private_file_ok "$WATCHF" || return 1
  { IFS= read -r -n 64 -d '' l <"$WATCHF"; } 2>/dev/null
  [ "${#l}" -lt 64 ] && [[ "$l" =~ ^[0-9]+\ [0-9]+$ ]] && [[ "${l%% *}" =~ ^[1-9][0-9]{0,9}$ ]] || return 1
  WOWN="$l"
}
# owner_gone PID START: the owner is gone when `kill -0` says there is no such process, or (Linux) /proc/PID/stat is
# absent, the process is a zombie or its start time is not START. EPERM from kill -0 never means gone (elsewhere the
# process is then taken as alive; on Linux /proc decides).
owner_gone() {
  local e cur
  e=$(kill -0 "$1" 2>&1) || case "$e" in *"No such process"*) return 0 ;; esac
  if [ -d /proc/self ]; then
    [ -r "/proc/$1/stat" ] || return 0
    cur=$(proc_start "$1") || return 0
    [ "$cur" != "$2" ]; return
  fi
  [ -z "$e" ] || return 1
  cur=$(proc_start "$1") || return 1
  [ "$cur" != "$2" ]
}
# hook_since NAME...: one of $LIVE_DIR/$HASH.NAME was modified after the marker was created (a hook ran); also when the
# marker is missing (fail safe: nothing is sent). Called with `state seq`: both are written only by hooks.
hook_since() {
  local n f=()
  [ -f "$GONEF" ] && [ ! -L "$GONEF" ] || return 0
  for n in "$@"; do f+=("$LIVE_DIR/$HASH.$n"); done
  [ -n "$(find "${f[@]}" -prune -newer "$GONEF" -print 2>/dev/null)" ]
}
# watch_end OWNER: the owner was gone on two polls and no hook ran. The credential is loaded again and must have the
# fingerprint recorded at start; one flush attempt of the pending lines (1 s limits; skipped when flush.lock is busy);
# then under the state lock `watch` and `state` are read again (another owner now, or a hook since the marker: return 3,
# the watcher keeps polling; ended or off: nothing is sent), the seq is allocated like `/allye:hooks live off`
# (max(previous + 1, Unix ms), and above every line left in the spool) and the state is written `ended`; after the lock
# is released, unless Live is now off or disabled or a back-off is active (e.g. set by that flush), the event
# `state ended` with code end_process_gone is sent alone in one request (1 s limits). It is never retried. The token
# and API origin are cleared on every return.
watch_end() {
  local rc
  watch_end_run "$@"; rc=$?
  LIVE_TOKEN=""; LIVE_API=""
  return "$rc"
}
watch_end_run() {
  local prev=0 ms new m at body tmp
  case "$LIVE_DIR" in *[\"\\]*) return 0 ;; esac   # the path goes into a curl config string
  watch_flags_ok || return 0
  load_live_credential "$DIR" || return 0
  CFP=""; credfp; [ "$CFP" = "$WCFP" ] || return 0
  SEND_MAXTIME=1; SEND_CONNECT=1
  if [ -s "$SPOOL" ] && lock_take "$FLOCK" 0; then FTOK="$LOCK_TOKEN"; flush_run; lock_drop "$FLOCK" "$FTOK"; FTOK=""; fi
  lock_take "$LOCKD" 50 || return 0
  STATE_TOKEN="$LOCK_TOKEN"; WHAVE=1
  if ! watch_read; then watch_unlock; return 0; fi
  if [ "$WOWN" != "$1" ] || hook_since state seq; then watch_unlock; return 3; fi
  m=""
  if [ -f "$STATEF" ] && [ ! -L "$STATEF" ]; then { IFS= read -r m <"$STATEF"; } 2>/dev/null; fi
  # off under the lock: `/allye:hooks live off` ends the session itself (end_live_off); disabled is checked before the send
  if [ "$m" = ended ] || [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ] || ! private_file_ok "$STATEF" || ! private_file_ok "$SEQF"; then watch_unlock; return 0; fi
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || at=""
  [[ "$at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { watch_unlock; return 0; }
  ms=$(now_ms)
  if [ -f "$SEQF" ] && [ ! -L "$SEQF" ]; then { IFS= read -r prev <"$SEQF"; } 2>/dev/null; fi
  if [[ "$prev" =~ ^(0|[1-9][0-9]{0,15})$ ]] && [ "$prev" -lt 9007199254740991 ] && [ "$prev" -le $((ms + 86400000)) ]; then :; else prev=0; fi
  new=$((prev + 1)); [ "$new" -ge "$ms" ] || new="$ms"
  if [ -s "$SPOOL" ] && private_file_ok "$SPOOL"; then
    m=$(jq -R -n '[inputs | fromjson? | objects | .seq | numbers | floor] | max // 0' "$SPOOL" 2>/dev/null) || m=0
    [[ "$m" =~ ^[0-9]{1,16}$ ]] && [ "$m" -ge "$new" ] && new=$((m + 1))
  fi
  [ "$new" -lt 9007199254740991 ] || { watch_unlock; return 0; }
  body=$(jq -nc --arg h "$HASH" --argjson s "$new" --arg at "$at" \
    '{client: {kind: "claude-code"}, session: {hash: $h}, events: [{seq: $s, at: $at, type: "state", state: "ended", code: "end_process_gone"}]}' 2>/dev/null) || body=""
  [ -n "$body" ] || { watch_unlock; return 0; }
  tmp=$(mktemp "$LIVE_DIR/.seq.XXXXXX" 2>/dev/null) || { watch_unlock; return 0; }; TMPF="$tmp"
  printf '%s' "$new" >"$tmp" 2>/dev/null && mv -f "$tmp" "$SEQF" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; watch_unlock; return 0; }
  tmp=$(mktemp "$LIVE_DIR/.state.XXXXXX" 2>/dev/null) || { watch_unlock; return 0; }; TMPF="$tmp"
  printf 'ended' >"$tmp" 2>/dev/null && mv -f "$tmp" "$STATEF" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; watch_unlock; return 0; }
  TMPF=""
  watch_unlock
  if ! watch_flags_ok || backoff_active; then return 0; fi   # the flush above may have disabled or backed off
  ENDF=$(mktemp "$LIVE_DIR/.end.XXXXXX" 2>/dev/null) || { ENDF=""; return 0; }
  printf '%s' "$body" >"$ENDF" 2>/dev/null || return 0
  {
    printf 'url = "%s/api/agent-runs/events"\n' "$LIVE_API"
    printf 'header = "Authorization: Bearer %s"\n' "$LIVE_TOKEN"
    printf 'header = "Content-Type: application/json"\n'
    printf 'header = "Accept: application/json"\n'
    printf 'data-binary = "@%s"\n' "$ENDF"
    printf 'max-time = 1\nconnect-timeout = 1\nmax-filesize = 65536\nnoproxy = "*"\n'
  } | curl -q --silent -K - -o /dev/null 2>/dev/null
  LIVE_TOKEN=""
  return 0
}
watch_unlock() { [ "$WHAVE" = 1 ] && lock_drop "$LOCKD" "$STATE_TOKEN"; WHAVE=0; return 0; }
watch_exit() {
  local p=""
  [ -z "$WSLEEP" ] || kill "$WSLEEP" 2>/dev/null   # this watcher's own sleep child
  LIVE_TOKEN=""
  [ -z "$TMPF" ] || rm -f "$TMPF" "$TMPF.2" 2>/dev/null
  [ -z "$ENDF" ] || rm -f "$ENDF" 2>/dev/null
  if [ -n "$FTOK" ]; then rm -f "$BATCHF" "$HDRF" "$RESPF" 2>/dev/null; lock_drop "$FLOCK" "$FTOK"; fi
  watch_unlock
  { IFS=' ' read -r p _ <"$WLOCK/p"; } 2>/dev/null
  if [ "$p" = "$ME" ]; then
    rm -f "$WATCHF" "$GONEF" 2>/dev/null
    # a flush.wait whose holder is gone: taken through lock_take (which breaks only a stale lock), then dropped
    [ -d "$WAITD" ] && lock_take "$WAITD" 0 "$ME" && pidlock_drop "$WAITD" "$ME"
    pidlock_drop "$WLOCK" "$ME"
  fi
  return 0
}
if [ "${1:-}" = watch ]; then watch_main; exit 0; fi
if [ "${1:-}" = final ]; then final_main; exit 0; fi

INPUT=$(cat 2>/dev/null) || INPUT=""
[ -n "$INPUT" ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r 'if (.session_id | type) == "string" and (.session_id | test("\\A[A-Za-z0-9._:-]{1,128}\\z")) then .session_id else empty end' 2>/dev/null) || exit 0
[ -n "$SID" ] || exit 0
HASH=$(printf '%s' "$SID" | sha_hex) || exit 0
SID=""
[[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || exit 0

SPOOL="$LIVE_DIR/$HASH.spool"
STATEF="$LIVE_DIR/$HASH.state"

# The live directory is checked before the first read or write (SHD-01), then every read-modify-write of this
# session (state, bind, gates, seq, spool) runs under one lock, so parallel hooks of a session are consistent.
# A hook that cannot get the lock within about 10 seconds gives up and drops its events (it exits 0, silent).
live_dir_ok || exit 0
HAVE_LOCK=0; LOCKD="$LIVE_DIR/$HASH.lock"
TMPF=""
# EFTOK: the flush lock held by this hook's own SessionEnd send (never the lock of a flusher it detached).
EFTOK=""
cleanup() { [ -z "$TMPF" ] || rm -f "$TMPF" "$TMPF.2" 2>/dev/null; [ "$HAVE_LOCK" = 1 ] && lock_drop "$LOCKD" "$STATE_TOKEN"; [ -z "$EFTOK" ] || lock_drop "$FLOCK" "$EFTOK"; return 0; }
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
lock_take "$LOCKD" 500 || exit 0
STATE_TOKEN="$LOCK_TOKEN"; HAVE_LOCK=1
# `/allye:hooks live off` may have run while this hook waited for the lock: it then drops its events (AC-11).
if [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ]; then exit 0; fi
FLOCK="$LIVE_DIR/$HASH.flush.lock"; WAITD="$LIVE_DIR/$HASH.flush.wait"; FTOK=""; FLUSHED="$LIVE_DIR/$HASH.flushed"; BATCHF="$LIVE_DIR/$HASH.batch"; HDRF="$LIVE_DIR/$HASH.hdr"; RESPF="$LIVE_DIR/$HASH.resp"; BACKOFFF="$LIVE_DIR/backoff"; CREDF="$LIVE_DIR/$HASH.cred"
FINALD="$LIVE_DIR/$HASH.final.lock"

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

# agent_id is present only when the hook fires inside a subagent (confirmed in the installed CLI schema).
# BR-14 trigger: {type:"trig"} is never output; it only makes a pending waiting_input become working.
# A value failing its pattern drops the tool event but the hook still counts as activity.
def trig: [{type: "trig"}];
# ─── ALY-217.6: the activity phrase (BR-10, BR-11, D-23, D-24) ───
# Code points stripped (D-04 forbidden set, plus the other format characters the API refuses: \p{Cf}, U+034F, the
# variation selectors and the tag characters; U+FFFD and surrogates as a safety net) and code points read as a space.
def actbad: . < 32 or (. >= 127 and . <= 159) or . == 173 or . == 847 or (. >= 1536 and . <= 1541) or . == 1564 or . == 1757
  or . == 1807 or . == 2192 or . == 2193 or . == 2274 or . == 6158 or (. >= 8203 and . <= 8207) or (. >= 8234 and . <= 8238)
  or (. >= 8288 and . <= 8303) or (. >= 55296 and . <= 57343) or (. >= 65024 and . <= 65039) or . == 65279
  or (. >= 65529 and . <= 65533) or . == 69821 or . == 69837 or (. >= 78896 and . <= 78911) or (. >= 113824 and . <= 113827)
  or (. >= 119155 and . <= 119162) or (. >= 917504 and . <= 917631) or (. >= 917760 and . <= 917999);
def actws: . == 9 or . == 10 or . == 11 or . == 12 or . == 13 or . == 133 or . == 160 or . == 5760 or (. >= 8192 and . <= 8202)
  or . == 8232 or . == 8233 or . == 8239 or . == 8287 or . == 12288;
# D-23 step 4, one token: dropped as a path, URL, email, IP address, long base64/hex string or secret.
def actcore: gsub("\\A[\"\u0027(\\[{<,;.!?]+|[\"\u0027)\\]}>,;.!?]+\\z"; "");
def actpath: test("[/\\\\]") or (actcore | test("\\A(~|[A-Za-z]:)"));
def actdrop:
  actcore as $c
  | test("[/\\\\]") or ($c | test("\\A(~|[A-Za-z]:)")) or contains("://") or ($c | ascii_downcase | startswith("www."))
    or test("[^@]@[^@]+\\.[^@]") or ($c | test("\\A[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]{1,5})?\\z")) or contains("::")
    or ($c | test("\\A[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){2,}\\z")) or test("[0-9A-Fa-f]{16,}")
    or ([match("[A-Za-z0-9+/=_-]{20,}"; "g").string | select(test("[0-9]"))] | length > 0)
    or test("[A-Za-z0-9_-]{24,}")
    # D-20 subset (ALY-258): the distinctive secret prefixes anywhere in the token; sk-/sk_/pk-/rk- only at its start or
    # after a non-alphanumeric (so risk-based survives); arn:; hostnames; colon/dash separated hex pairs.
    or test("(ghp_|gho_|ghs_|github_pat_|xox[abprs]-|AKIA|ASIA|eyJ|glpat-)")
    or test("(\\A|[^A-Za-z0-9])(sk-|sk_|pk-|rk-)")
    or ($c | ascii_downcase | startswith("arn:"))
    or ($c | test("\\A([A-Za-z0-9-]+\\.){2,}[A-Za-z]{2,}\\z"))
    or ($c | test("\\A([A-Za-z0-9-]+\\.)+(com|net|org|io|dev|app|co|br|ai|cloud|info|biz|edu|gov|local|internal|corp|test|lan)\\z"; "i"))
    or test("([0-9A-Fa-f]{2}[:-]){7}[0-9A-Fa-f]{2}")
    or test("[\uff00-\uffef]");   # fullwidth/halfwidth forms: look-alikes of ASCII that the API would NFKC-normalise (the plugin cannot) are dropped whole
# Secrets (D-23 step 4 and Shield SHD-01/03 of ALY-217.6). actkv: `key=value` / `key:value` (also bare `key:`, actbare);
# actkey: a key-like word alone; actsep: a standalone `=` / `:`; actscheme: an auth scheme; actauth: auth/authorization;
# actword: a secret word whose next token (after an optional is/as/=) is its value.
# actwk: the whole-word secret names of D-20 that are too common as substrings (session, sid...) to match inside a word.
def actwk: (. | ascii_downcase) | IN("pwd","pw","cookie","session","sid","passphrase","key","auth","bearer","credential","apikey");
def actkv: test("\\A[^=:]*(key|token|secret|pass|auth|credential)[^=:]*[=:]"; "i") or test("\\A(pwd|pw|cookie|session|sid)[=:]"; "i");
def actbare: test("\\A[^=:]*(key|token|secret|pass|auth|credential)[^=:]*[=:]+[\"\u0027]?\\z"; "i") or test("\\A(pwd|pw|cookie|session|sid)[=:]+[\"\u0027]?\\z"; "i");
def actkey: actcore | (test("(key|token|secret|pass|auth|credential)"; "i") or actwk);
def actsep: actcore | test("\\A[=:]+\\z");
def actscheme: (actcore | ascii_downcase) | IN("basic","bearer","token","digest");
def actauth: (actcore | ascii_downcase | sub("[=:]+\\z"; "")) | IN("auth","authorization","proxy-authorization");
def actword: (actcore | ascii_downcase) | IN("password","passwd","secret","token","apikey","api_key","access_key","private_key","credential","credentials");
def actbearer: (actcore | ascii_downcase) == "bearer";
# The cleaned phrase of a field, or null: (1) strings only; (2) whitespace to spaces, forbidden code points stripped;
# (3) backticked spans removed; (4) token drops (a bare `key:` / `key=`, `key = value`, `key : value`, `password is x`,
# `Authorization [:] Basic|Bearer|Token|Digest x` and `Bearer x` drop the value too, chained); (5) at
# least 3 words and 8 characters; (6) at most $cap code points (ALY-258: 140 for every text), cut at the last space
# (hard cut at $cap-1 when there is none or when that would leave fewer than 8) plus U+2026, so the ellipsis is inside the cap.
# This is the one cleaner of the reporter: a documented subset of the API scrubber (ALY-257 D-20), which stays authoritative.
def actcap: 140;
def actphrase($cap):
  if type != "string" then null else
    .[0:4096] | explode | map(if actws then 32 elif actbad then empty else . end) | implode
    | (try gsub("[\\p{Cc}\\p{Cf}\\p{Cs}]"; "") catch .)
    | gsub("`[^`]*(`|\\z)"; " ")
    | gsub("\\+?\\(?(?<![0-9A-Za-z])[0-9]([ .\\-()]{0,2}[0-9]){9,18}(?![0-9A-Za-z])"; " ")   # 10+ digits with separators/parentheses: account ids, CPF/CNPJ, phones, cards
    | [splits(" +") | select(length > 0)] as $t0
    # a path token is dropped (actdrop) and so are the Capitalized words that follow it, up to the next punctuation (D-20)
    | (reduce $t0[] as $w ({o: [], c: false};
        if ($w | actpath) then .c = true
        elif .c and ($w | test("\\A\\p{Lu}")) then (if ($w | test("[,;.!?:]\\z")) then .c = false else . end)
        else .o += [$w] | .c = false end) | .o) as $t
    | (reduce range(0; $t | length) as $k ({o: [], s: 0};
        $t[$k] as $w | ($t[$k + 1] // "") as $n
        | if .s > 0 then .s -= 1 | (if ($w | actscheme) or ($w | actbare) or ($w | actsep) then .s += 1 else . end)
          elif ($w | actcore | actwk) and ($n | ascii_downcase | IN("is","as")) then .s = 2   # `the key is x`, `session is x`: the whole-word names
          elif ($w | actbearer) then .s = 1
          elif ($w | actauth) and ($n | actscheme) then .s = 1   # the scheme, then (chained) its value
          elif ($w | actkv) then (if ($w | actbare) then .s = 1 else . end)
          elif ($w | actkey) and ($n | actsep) then .s = 1   # the separator, then (chained) the value
          elif ($w | actword) then (if ($n | ascii_downcase | IN("is","as")) then .s = 2 else .s = 1 end)
          elif ($w | actdrop) then .
          else .o += [$w] end)) as $r
    | ($r.o | join(" ")) as $p
    | if ($r.o | length) < 3 or ($p | length) < 8 then null
      elif ($p | length) <= $cap then $p
      else ($p | explode) as $e
        | ([range(0; $cap) | select($e[.] == 32)] | last) as $i
        | (if $i != null and $i >= 8 then $e[0:$i] else $e[0:($cap - 1)] end | implode | sub(" +\\z"; "")) + "\u2026"
      end
  end;
# BR-10 (D-24 a, b, c): the one field read per tool; nothing while the activity-off flag exists.
# $txt is "1" unless texts are off (the activity-off flag; ALY-258.3 adds detailed:false): then no activity, no desc, no stash.
def actof:
  if $txt != "1" then null
  elif .tool_name | IN("Bash","Agent","Task") then ((.tool_input | objects | .description) // null) | actphrase(actcap)
  elif .tool_name == "TodoWrite" then [.tool_input | objects | .todos | arrays | .[] | objects | select(.status == "in_progress")] | .[0] | (objects | .activeForm) // null | actphrase(actcap)
  else null end;
# ALY-258.2 (D-05, D-35): the strict report lines. Over the first 65536 characters, a line counts for a key only when it starts at
# column 0 with the exact lowercase key (LF or CRLF); the key must be on EXACTLY ONE such line, else the field is omitted. Nothing
# but the cleaned summary text is ever kept from the message; every other line is read as an integer or an enum.
def rawlines: (.last_assistant_message | if type == "string" then .[0:65536] else "" end) | split("\n") | map(sub("\r\\z"; ""));
def one($k): [rawlines[] | select(startswith($k + ":"))] | if length == 1 then .[0][($k | length) + 1:] else null end;
def n99: "(0|[1-9][0-9]?)";
def int99: tonumber;
def chipline($k; $re): (one($k) // null) | if . == null then null else ([capture("\\A[ \t]*" + $re + "[ \t]*\\z")?] | .[0]) end;
def newfields($ty):
  (one("summary")) as $sm
  | (chipline("attempt"; "(?<v>[012])")) as $at
  | (chipline("next"; "(?<v>[A-Za-z_-]{1,20})")) as $nx
  | (chipline("gate"; "(?<v>SHIELD_CLEAR|WATCHER_APPROVED)")) as $gt
  | (chipline("checks"; "ok=(?<ok>" + n99 + ") run=(?<run>" + n99 + ")")) as $ck
  | (chipline("severity_counts"; "critical=(?<critical>" + n99 + ") high=(?<high>" + n99 + ") medium=(?<medium>" + n99 + ") low=(?<low>" + n99 + ") info=(?<info>" + n99 + ")")) as $sv
  | {}
  + (if $txt == "1" and $sm != null then ($sm | actphrase(actcap)) as $c | (if $c != null then {summary: $c} else {} end) else {} end)
  + (if $at != null then {attempt: ($at.v | int99)} else {} end)
  + (if $nx != null then ($nx.v | ascii_downcase | gsub("-"; "_")) as $t | (if $t | IN("reviewers","pilot_correction","mothership","watcher","done") then {next: $t} else {} end) else {} end)
  + (if $gt != null and (($gt.v == "SHIELD_CLEAR" and ($ty | test("\\A(allye:)?(bridge-)?shield\\z"))) or ($gt.v == "WATCHER_APPROVED" and ($ty | test("\\A(allye:)?(bridge-)?watcher\\z")))) then {gate: $gt.v} else {} end)
  + (if $ck != null then {checks: ($ck | map_values(int99))} else {} end)
  + (if $sv != null then {findings: ($sv | map_values(int99))} else {} end);
def substop: outcome as $r | (tkline // null) as $t
  | {type: "sub_stop", sub: (subof + {outcome: $r.o} + (if ($t | keyok) then {task: $t} else {} end) + newfields(subof.type))}
    + (if $r.c != null then {code: $r.c} else {} end);
def withact($a): if $a != null then . + {activity: $a} else . end;
def toolev:
  redtool as $t | actof as $a
  | if (.agent_id // null) != null then
    (subof) as $s | if $s != null and $t != null then [{type: "sub_tool", tool: $t, sub: $s} | withact($a)] else trig end
  elif $t != null then [{type: "tool", tool: $t} | withact($a)]
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
# ALY-217.4 (BR-08, D-03, D-22): only the claim-like writes task_start and task_submit (exact, lowercase) bind.
def mcpb:
  ((.tool_input | objects) // {}) as $i
  | if ($i.action | IN("task_start","task_submit") | not) then null else
    ({source: "mcp"} + (if ($i.spec | keyok) then {spec: $i.spec} else {} end) + (if ($i.task | keyok) then {task: $i.task} else {} end))
  | if has("spec") or has("task") then . else null end end;
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
# ALY-217.6 (D-24 b), ALY-258.1 (D-32): the Agent/Task stash, [{t: subagent type, ms: Unix ms, a: cleaned description or "",
# id: the tool_use_id of the PreToolUse when it has one}] oldest first. $stash is the content of $HASH.agents read by the hook
# (empty when absent); entries are checked again, pruned after 60 s and capped at 16. An entry holds no prompt and no raw text.
def stashin:
  ($stash | try fromjson catch []) | (if type == "array" then . else [] end)
  | map(select(type == "object" and (.t | typeok) and (.ms | type == "number") and .ms > ($nowms - 60000) and .ms <= ($nowms + 60000)
               and (.a | type == "string") and (.a == "" or (.a | actphrase(actcap)) == .a)
               and ((has("id") | not) or (.id | idok))
               and ((has("p") | not) or (.p == true and .a == ""))))
  | .[-16:];
# AC-03: the task key of a start is the first dotted task key of the CLEANED description (a key inside a token the cleaner
# dropped is therefore never sent).
def taskof: [match("(?<![A-Za-z0-9])[A-Z][A-Z0-9]{1,9}-[0-9]+\\.[0-9]+"; "g").string] | .[0];
# stashc($starts): $starts are the subs whose first sub_start (real or synthetic, ALY-217.7) this event spools. Correlation
# (D-32): the unexpired entries of the subagent type of the start are counted. Exactly one, and it is not a tombstone: its
# cleaned description is attached as `desc` (and its task key as `task`) to that sub_start and the entry is consumed. None:
# nothing. Several (parallel launches of one type), or a tombstone: nothing; the oldest entry is consumed and every other
# unexpired entry of the type becomes a tombstone ({t, ms, a: "", p: true}, still expiring by its own TTL), so a launch that
# comes in after an ambiguous start cannot be matched to the wrong subagent either (Shield SHD-01). The tool_use_id is stored
# for the day the SubagentStart payload carries it, but today it does not (nor does SubagentStop), so matching is by type
# within the 60 s TTL; two launches of one type in flight can therefore never be told apart, which is why they send no desc.
# {ds: {sub id: {desc, task?}}, st: the new stash or null}.
def stashc($starts):
  if $txt != "1" then {ds: {}, st: null}
  else
    (reduce $starts[] as $s ({q: stashin, ds: {}};
       .q as $q | [range(0; $q | length) | select($q[.].t == $s.type)] as $ix
       | if ($ix | length) == 0 then .
         elif ($ix | length) == 1 and ($q[$ix[0]].p // false | not) then
           $q[$ix[0]].a as $a
           | (if $a != "" then .ds[$s.id] = ({desc: $a} + ($a | taskof | if . != null then {task: .} else {} end)) else . end)
           | .q |= del(.[$ix[0]])
         else .q |= ([range(0; length) as $k | .[$k] | if .t != $s.type then . elif $k == $ix[0] then empty else . + {a: "", p: true} end]) end)) as $c
    | if .hook_event_name == "PreToolUse" and (.tool_name | IN("Agent","Task")) then
        ((.tool_input | objects | .subagent_type) // "general-purpose") as $ty
        | if ($ty | typeok) then {ds: $c.ds, st: (($c.q + [{t: $ty, ms: $nowms, a: (actof // "")} + (if (.tool_use_id | idok) then {id: .tool_use_id} else {} end)]) | .[-16:])}
          elif ($starts | length) > 0 then {ds: $c.ds, st: $c.q} else {ds: {}, st: null} end
      elif ($starts | length) > 0 then {ds: $c.ds, st: $c.q}
      else {ds: {}, st: null} end
  end;
# ─── ALY-217.7: synthetic sub_start (BR-14 of ALY-217, D-26) ───
# $subs is the content of $HASH.subs (one sub id per line), usable only when $subok is "1"; ids failing idok are dropped
# and at most the newest 64 kept. subsc: {out: the events with a sub_start before the first sub_tool / sub_stop of an id not
# in the set and without the sub_start of an id already in it, seen: the new set, new: the subs that got their first sub_start}.
# A sub_start put before a sub_stop carries syn (removed before output): like the sub_stop, it does not end waiting_input.
# Without a usable set ($subok "0"): the events as they are, every real SubagentStart taking its stash entry.
def seenin: [$subs | split("\n")[] | select(idok)] | .[-64:];
def subsc($e):
  if $subok != "1" then {out: $e, seen: null, new: [$e[] | select(.type == "sub_start") | .sub]}
  else
    reduce $e[] as $ev ({out: [], seen: seenin, new: []};
      if ($ev.type | IN("sub_start","sub_tool","sub_stop")) then
        ($ev.sub | {id, type}) as $s
        | if (.seen | any(. == $s.id)) then (if $ev.type == "sub_start" then . else .out += [$ev] end)
          else .seen = ((.seen + [$s.id]) | .[-64:]) | .new += [$s]
            | .out += (if $ev.type == "sub_start" then [$ev]
                      elif $ev.type == "sub_stop" then [{type: "sub_start", sub: $s, syn: true}, $ev]   # not a BR-14 trigger
                      else [{type: "sub_start", sub: $s}, $ev] end) end
      else .out += [$ev] end)
  end;
# BR-14: the first tool/subagent-start event after waiting_input is preceded by a `state working`.
. as $in
| evs as $e0
| (try subsc($e0) catch {out: $e0, seen: null, new: []}) as $sb
| (try stashc($sb.new) catch {ds: {}, st: null}) as $sc
| [$sb.out[] | if .type == "sub_start" then .sub += ($sc.ds[.sub.id] // {}) else . end] as $all
| (reduce $all[] as $ev ({out: [], last: $last};
    (if ($ev.type | IN("tool","sub_tool","sub_start","trig")) and ($ev.syn | not) and .last == "waiting_input"
       then .out += [{type: "state", state: "working"}] | .last = "working" else . end)
    | (if $ev.type == "trig" then . else .out += [$ev | del(.syn)] end)
    | if $ev.type == "state" then .last = $ev.state else . end)) as $r
| $r.last,
  (try ($in | bindc) catch null | if . == null then "-" else tojson end),
  (try ($in | cwdc) catch null | . // "-"),
  (try ($in | gatec) catch null | if . == null then "-", "-" else .[] end),
  (if sstart then "start" elif .hook_event_name == "UserPromptSubmit" then "prompt" else "-" end),
  (if $sc.st == null or ($sc.st | tojson) == $stash or ($sc.st == [] and $stash == "") then "-" else ($sc.st | tojson) end),
  (if $sb.seen == null or ($sb.new | length) == 0 then "-" else ($sb.seen | join(" ")) end),
  ($r.out[] | . + {at: $at} | tojson),
  "."'

# ALY-217.6 (D-25, D-24 b): activity phrases unless $LIVE_DIR/activity-off exists (any kind of entry: fail safe); the
# Agent/Task stash $HASH.agents is read once (bounded, private file only) and passed to the jq program.
ACT=1; if [ -e "$LIVE_DIR/activity-off" ] || [ -L "$LIVE_DIR/activity-off" ]; then ACT=0; fi
# The stash goes to jq through --rawfile (never argv, Shield SHD-02): the file itself when it is private and at most
# 16384 bytes (one find), else /dev/null (an oversized private stash is then simply rewritten).
AGENTSF="$LIVE_DIR/$HASH.agents"; STASHSRC=/dev/null; AGOK=0
if [ "$ACT" = 1 ]; then
  if [ ! -e "$AGENTSF" ] && [ ! -L "$AGENTSF" ]; then AGOK=1
  elif [ ! -L "$AGENTSF" ] && [ -n "$(find "$AGENTSF" -prune -type f -user "$UID_NOW" -perm 0600 -size -16385c -print 2>/dev/null)" ]; then AGOK=1; STASHSRC="$AGENTSF"
  elif private_file_ok "$AGENTSF"; then AGOK=1; fi
fi
# ALY-217.7 (D-26): the seen sub ids $HASH.subs, read under the state lock like the stash: through --rawfile, the file
# itself when it is private and at most 8192 bytes. Absent: an empty set. An oversized private file is rewritten. Any
# other entry (symlink, foreign owner or mode): the set is neither used nor written (SUBOK=0, no synthetic sub_start).
SUBSF="$LIVE_DIR/$HASH.subs"; SUBSRC=/dev/null; SUBOK=0
if [ ! -e "$SUBSF" ] && [ ! -L "$SUBSF" ]; then SUBOK=1
elif [ ! -L "$SUBSF" ] && [ -n "$(find "$SUBSF" -prune -type f -user "$UID_NOW" -perm 0600 -size -8193c -print 2>/dev/null)" ]; then SUBOK=1; SUBSRC="$SUBSF"
elif private_file_ok "$SUBSF"; then SUBOK=1; fi
MS=$(now_ms)
[[ "$MS" =~ ^[1-9][0-9]{0,15}$ ]] || exit 0
RESULT=$(printf '%s' "$INPUT" | jq -r --arg last "$LAST" --arg at "$AT" --arg txt "$ACT" --rawfile stash "$STASHSRC" --arg subok "$SUBOK" --rawfile subs "$SUBSRC" --argjson nowms "$MS" "$JQ_PROG" 2>/dev/null) || exit 0
# Output: new last state, bind candidate (or -), cwd for the branch source (or -), gates path and cwd (or -, -),
# watcher trigger (start = a SessionStart of a known source, prompt = UserPromptSubmit, or -), the new Agent/Task
# stash (or - to leave it), the new seen-set as space-separated ids (or - to leave it), events, "." terminator.
NEWLAST="${RESULT%%$'\n'*}"; REST="${RESULT#*$'\n'}"
CAND="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
CWD="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
GFP="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
GCWD="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
WEV="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
AGT="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
SUBS="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
case "$REST" in .) EVENTS="" ;; *$'\n'.) EVENTS="${REST%$'\n'.}" ;; *) exit 0 ;; esac
case "$NEWLAST" in ""|started|working|waiting_input|idle|error|ended) ;; *) exit 0 ;; esac
[ -n "$CAND" ] && [ -n "$CWD" ] && [ -n "$GFP" ] && [ -n "$GCWD" ] || exit 0
case "$WEV" in start|prompt|-) ;; *) exit 0 ;; esac
case "$AGT" in -|'['*']') ;; *) exit 0 ;; esac
[ "$SUBS" = - ] || [[ "$SUBS" =~ ^[A-Za-z0-9_-]{1,64}( [A-Za-z0-9_-]{1,64}){0,63}$ ]] || exit 0

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

# A session whose credential changed since its last event (a re-pair after a 401, a revoke or an expiry) opens with
# `state started`: the server reopens a run that was ended or revoked only on that state.
credfp
CREDOLD=""; CREDNEW=0
if [ -f "$CREDF" ] && [ ! -L "$CREDF" ] && private_file_ok "$CREDF"; then { IFS= read -r CREDOLD <"$CREDF"; } 2>/dev/null; fi
if [[ "$CREDOLD" =~ ^[0-9a-f]{64}$ ]] && [ "$CREDOLD" != "$CFP" ]; then
  case "$EVENTS" in
    *'"state":"started"'*) ;;   # a SessionStart in this very batch already opens the run
    *'"type":"state"'*) EVENTS=$(printf '{"type":"state","state":"started","at":"%s"}\n%s' "$AT" "$EVENTS") ;;
    *) NEWLAST=started; EVENTS=$(printf '{"type":"state","state":"started","at":"%s"}\n%s' "$AT" "$EVENTS") ;;
  esac
  CREDNEW=1
fi

# seq (BR-05): max(previous + 1, Unix ms) per event, counter in $HASH.seq. A missing, corrupt, foreign or absurd
# (more than a day ahead of the clock, 2^53 or more) counter heals to 0. The counter is written before the
# lines, so a crash can leave a gap but never a repeated seq.
SEQF="$LIVE_DIR/$HASH.seq"
PREV=0   # MS: read once before the jq program (ALY-217.6), shared by the stash times and the seq
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
if [ "$CREDOLD" != "$CFP" ]; then
  TMP=$(mktemp "$LIVE_DIR/.cred.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s' "$CFP" >"$TMP" 2>/dev/null && mv -f "$TMP" "$CREDF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi
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
# The Agent/Task stash (D-24 b): one atomic write (temp 0600 + mv) when it changed; an emptied stash is removed.
if [ "$AGT" != "-" ] && [ "$AGOK" = 1 ]; then
  if [ "$AGT" = "[]" ]; then rm -f "$AGENTSF" 2>/dev/null
  else
    TMP=$(mktemp "$LIVE_DIR/.agents.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
    printf '%s' "$AGT" >"$TMP" 2>/dev/null && mv -f "$TMP" "$AGENTSF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
  fi
fi
# The seen sub ids (D-26): one atomic write (temp 0600 + mv) when an id was added, one id per line, at most 64.
if [ "$SUBS" != - ] && [ "$SUBOK" = 1 ]; then
  TMP=$(mktemp "$LIVE_DIR/.subs.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s\n' $SUBS >"$TMP" 2>/dev/null && mv -f "$TMP" "$SUBSF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi

# Session watcher (ALY-217.2, D-21), still under the state lock: at a SessionStart, or at a UserPromptSubmit when no
# watcher holds the watch lock, and unless ALLYE_LIVE_WATCH is 0 or the session is ended, the trusted owner is recorded
# in $HASH.watch ("<pid> <start>", set -C temp + mv, 0600; a later SessionStart under another owner rewrites it) and,
# when the watch lock can be taken at the first try, one watcher is started. No trusted owner: nothing is written.
WATCHF="$LIVE_DIR/$HASH.watch"; WLOCK="$LIVE_DIR/$HASH.watch.lock"
if [ "${ALLYE_LIVE_WATCH:-1}" != 0 ] && [ "$NEWLAST" != ended ] && { [ "$WEV" = start ] || { [ "$WEV" = prompt ] && ! watch_held; }; }; then
  OWNER=$(owner_find "$PPID") || OWNER=""
  if [[ "$OWNER" =~ ^[0-9]+\ [0-9]+$ ]] && private_file_ok "$WATCHF"; then
    TMP="$WATCHF.$$.$RANDOM"; TMPF="$TMP"
    if ( set -C; printf '%s' "$OWNER" >"$TMP" ) 2>/dev/null && mv -f "$TMP" "$WATCHF" 2>/dev/null; then
      lock_take "$WLOCK" 0 "$$" && watch_start
    else rm -f "$TMP" 2>/dev/null; fi
  fi
fi

# Flush trigger (BR-04, D-20): an important event (state change, subagent start or stop, bind, gates) or 2 seconds since
# the last flush started; otherwise one delayed flush per session (the sleeper above). Nothing during a back-off. The
# state lock is released first; flusher and sleeper are detached with stdio on /dev/null so the hook returns at once.
IMPORTANT=0
case "$EVENTS" in *'"type":"sub_start"'*|*'"type":"sub_stop"'*|*'"type":"bind"'*|*'"type":"gates"'*) IMPORTANT=1 ;; esac
if [ -n "$NEWLAST" ] && [ "$NEWLAST" != "$LAST" ]; then IMPORTANT=1; fi
[ "$CREDNEW" = 1 ] && IMPORTANT=1
# SessionEnd (BR-12, ALY-217.7 BR-15/D-27): the ended event is sent from the hook itself, bounded, else by the final flusher.
SEND_MAXTIME=8; SEND_CONNECT=3
ENDING=0; case "$EVENTS" in *'"state":"ended"'*) ENDING=1 ;; esac
lock_drop "$LOCKD" "$STATE_TOKEN"; HAVE_LOCK=0
if [ "$ENDING" = 1 ]; then end_send
elif backoff_active; then :
elif flush_due; then
  if lock_take "$FLOCK" 0; then
    FTOK="$LOCK_TOKEN"
    stamp_flushed
    (
      trap 'rm -f "$BATCHF" "$HDRF" "$RESPF" "$TMPF" "$TMPF.2" 2>/dev/null; lock_drop "$FLOCK" "$FTOK"' EXIT
      trap 'exit 0' HUP INT TERM
      flush_loop
    ) </dev/null >/dev/null 2>&1 &
  fi
elif lock_take "$WAITD" 0 "$$"; then
  (
    ME="${BASHPID:-}"
    if [ -z "$ME" ]; then   # bash 3.2: the parent of a child sh is this subshell
      TMP=$(mktemp "$LIVE_DIR/.me.XXXXXX" 2>/dev/null) && { sh -c 'printf "%s" "$PPID"' >"$TMP" 2>/dev/null; IFS= read -r ME <"$TMP"; rm -f "$TMP"; }
    fi
    pidlock_pass "$WAITD" "$$" "$ME"
    trap 'rm -f "$BATCHF" "$HDRF" "$RESPF" "$TMPF" "$TMPF.2" 2>/dev/null; lock_drop "$FLOCK" "$FTOK"; pidlock_drop "$WAITD" "$ME"' EXIT
    trap '' HUP
    trap 'exit 0' INT TERM
    flush_sleeper
  ) </dev/null >/dev/null 2>&1 &
  pidlock_pass "$WAITD" "$$" "$!"
fi
LIVE_TOKEN=""
exit 0
