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
# tool inputs and outputs, paths, messages, transcripts and the cwd are never read into the output.
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
    # mkdir alone does not decide: uutils coreutils (Ubuntu 25.10+) can report success to several concurrent callers, so
    # the lock is the exclusive (noclobber, O_EXCL) creation of DIR/t; a mkdir "winner" that loses that claim has not got it.
    if mkdir "$d" 2>/dev/null && ( set -C; printf '%s %s' "$(date +%s 2>/dev/null)" "$LOCK_TOKEN" >"$d/t" ) 2>/dev/null; then return 0; fi
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
# lock_drop DIR TOKEN: removes the lock only while DIR/t still holds this hook's own token.
lock_drop() {
  local t=""
  { IFS=' ' read -r _ t <"$1/t"; } 2>/dev/null
  [ -n "${2:-}" ] && [ "$t" = "$2" ] && rm -rf "$1" 2>/dev/null
  return 0
}
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
  printf '%s' 'def keep: with_entries(select(.key | IN("seq","at","type","state","tool","code","sub","bind","gates")));
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
  lock_take "$LOCKD" 250 || return 1
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
flush_run() {
  local rounds=0 status ecode ra before
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
    lock_touch "$FLOCK" "$FTOK" || return 1   # the lock is no longer ours: stop
    printf '%s' "$BODY" >"$BATCHF" 2>/dev/null || return 1
    status=$({
      printf 'url = "%s/api/agent-runs/events"\n' "$LIVE_API"
      printf 'header = "Authorization: Bearer %s"\n' "$LIVE_TOKEN"
      printf 'header = "Content-Type: application/json"\n'
      printf 'header = "Accept: application/json"\n'
      printf 'data-binary = "@%s"\n' "$BATCHF"
      printf 'max-time = %s\nconnect-timeout = %s\nmax-filesize = 65536\nnoproxy = "*"\n' "${SEND_MAXTIME:-8}" "${SEND_CONNECT:-3}"
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
flush_due() {  # important events flush at once, others when 5 seconds passed since the last flush started
  local last="" now
  backoff_active && return 1
  [ "$IMPORTANT" = 1 ] && return 0
  if [ -f "$FLUSHED" ] && [ ! -L "$FLUSHED" ] && private_file_ok "$FLUSHED"; then IFS= read -r last <"$FLUSHED" 2>/dev/null; fi
  now=$(date +%s 2>/dev/null) || return 1
  [[ "$last" =~ ^[0-9]{1,12}$ ]] && [[ "$now" =~ ^[0-9]{1,12}$ ]] || return 0
  [ $((now - last)) -ge 5 ]
}

# The live directory is checked before the first read or write (SHD-01), then every read-modify-write of this
# session (state, bind, gates, seq, spool) runs under one lock, so parallel hooks of a session are consistent.
# A hook that cannot get the lock within about 10 seconds gives up and drops its events (it exits 0, silent).
live_dir_ok || exit 0
HAVE_LOCK=0; LOCKD="$LIVE_DIR/$HASH.lock"
TMPF=""
cleanup() { [ -z "$TMPF" ] || rm -f "$TMPF" "$TMPF.2" 2>/dev/null; [ "$HAVE_LOCK" = 1 ] && lock_drop "$LOCKD" "$STATE_TOKEN"; return 0; }
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
lock_take "$LOCKD" 500 || exit 0
STATE_TOKEN="$LOCK_TOKEN"; HAVE_LOCK=1
# `/allye:hooks live off` may have run while this hook waited for the lock: it then drops its events (AC-11).
if [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ]; then exit 0; fi
FLOCK="$LIVE_DIR/$HASH.flush.lock"; FLUSHED="$LIVE_DIR/$HASH.flushed"; BATCHF="$LIVE_DIR/$HASH.batch"; HDRF="$LIVE_DIR/$HASH.hdr"; RESPF="$LIVE_DIR/$HASH.resp"; BACKOFFF="$LIVE_DIR/backoff"; CREDF="$LIVE_DIR/$HASH.cred"

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

# Flush trigger (BR-04): an important event (state change, subagent start or stop, bind, gates) or 5 seconds since
# the last flush. The state lock is released first; the flusher is detached so the hook returns at once.
IMPORTANT=0
case "$EVENTS" in *'"type":"sub_start"'*|*'"type":"sub_stop"'*|*'"type":"bind"'*|*'"type":"gates"'*) IMPORTANT=1 ;; esac
if [ -n "$NEWLAST" ] && [ "$NEWLAST" != "$LAST" ]; then IMPORTANT=1; fi
[ "$CREDNEW" = 1 ] && IMPORTANT=1
# SessionEnd (BR-12): the final event goes out through a request limited to one second.
SEND_MAXTIME=8; SEND_CONNECT=3
case "$EVENTS" in *'"state":"ended"'*) SEND_MAXTIME=1; SEND_CONNECT=1 ;; esac
lock_drop "$LOCKD" "$STATE_TOKEN"; HAVE_LOCK=0
if flush_due && lock_take "$FLOCK" 0; then
  FTOK="$LOCK_TOKEN"
  TMP=$(mktemp "$LIVE_DIR/.flushed.XXXXXX" 2>/dev/null) && { TMPF="$TMP"; date +%s >"$TMP" 2>/dev/null && mv -f "$TMP" "$FLUSHED" 2>/dev/null || rm -f "$TMP" 2>/dev/null; }
  (
    trap 'rm -f "$BATCHF" "$HDRF" "$RESPF" "$TMPF" "$TMPF.2" 2>/dev/null; lock_drop "$FLOCK" "$FTOK"' EXIT
    trap 'exit 0' HUP INT TERM
    flush_loop
  ) </dev/null >/dev/null 2>&1 &
fi
LIVE_TOKEN=""
exit 0
