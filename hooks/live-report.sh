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
# ALY-263.13 (AC-16): DATE_REAL=1 when `date` on the PATH is the system tool (the first PATH hit is /usr/bin/date or /bin/date) and bash has
# EPOCHREALTIME: the clock is then read from bash itself (same instant, no fork). Any other `date` (the fake clock shim of the tests) is called.
DATE_REAL=0
if [ -n "${EPOCHREALTIME:-}" ]; then
  _dl=""; IFS=: read -ra _dp <<<"$PATH"
  for _dq in "${_dp[@]}"; do [ -x "${_dq:-.}/date" ] && [ ! -d "${_dq:-.}/date" ] && { _dl="${_dq:-.}/date"; break; }; done
  case "$_dl" in /usr/bin/date|/bin/date) DATE_REAL=1 ;; esac
fi
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
# - ALY-263.5 (AC-08, D-15): spec_context/spec_get of the main session with a spec key, and a launch with a spec key, are also
#   sent when weaker or identical, once per key per minute ($HASH.touch: up to 16 `KEY ms` lines, 0600, a corrupt file counts
#   as empty); the held binding in $HASH.bind is not changed by such a send.
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
#   ALY-263.12 (AC-14): report lines `phase: stage|publish` (sub.phase) and a column-0, once-per-report `status: ready|approved`
#   (code ready|approved, outcome stays pass) follow the whole-line rules of the other report lines (column 0, exact lowercase
#   key, once; any other value sends nothing). Both are enum metadata, sent even with texts off; `phase` is validated at flush.
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
#   ALY-263.15 (AC-18, D-20, D-21): the same verified read also takes the first column-0 line matching
#   `^- PR: #([1-9][0-9]{0,6})[ \t\r]*$` (any other text on the line, `#0`, `#01`, 8 digits, an indented or lowercase
#   line match nothing; a non-matching `- PR:` line is skipped, the first MATCHING line wins). Its number leaves only as the
#   JSON integer `pr` on the gates event, only when it differs from the last pr sent, stored as a second line of
#   $HASH.gates (an old file with the array alone reads clean: no pr yet). The gates event is sent when the set or the pr
#   changed; it always carries `gates`: the current set when the log has a Gates line, else the last set sent ([] at first).
#   A pr is metadata (sent with texts off) and is validated again at flush (integer 1..9999999; invalid dropped, event kept).
# (The payload is read further down, after the function definitions and the watcher-mode dispatch of ALY-217.)

# A path we may use: absent, or a regular file (no symlink) owned by the user with exactly mode 0600.
private_file_ok() {
  { [ ! -e "$1" ] && [ ! -L "$1" ]; } && return 0
  [ -n "$(find "$1" -prune -type f -user "$UID_NOW" -perm 0600 -print 2>/dev/null)" ]
}
# ALY-263.13 (AC-16): the private-file checks of the main hook path run as ONE find per scan instead of one find per file (a find costs
# about as much as a jq call). priv_scan NAME... checks $LIVE_DIR (a real directory, user, 0700) and each $LIVE_DIR/$HASH.NAME (a regular
# file, no symlink, user, mode 0600) with the very tests of private_file_ok; a file whose name has a size cap (label 1024, tkmem and subs
# 8192, acts, agents and rsm 16384 bytes) is printed a second time when it is also under that cap. PS_OUT keeps the lines (newline-framed),
# PS_NAMES the paths scanned. pfc PATH is private_file_ok answered from the scan (absent = ok); pfcap PATH is "private and under the
# cap". A path the scan did not cover goes through private_file_ok. The scan is repeated under the state lock before the state files are used.
PS_OUT=""; PS_NAMES=""
priv_scan() {
  local a n
  a=("$LIVE_DIR"); PS_NAMES=$'\n'"$LIVE_DIR"$'\n'
  for n in "$@"; do a[${#a[@]}]="$LIVE_DIR/$HASH.$n"; PS_NAMES="$PS_NAMES$LIVE_DIR/$HASH.$n"$'\n'; done
  PS_OUT=$(find "${a[@]}" -prune -user "$UID_NOW" \( \( -type d -perm 0700 \) -o \( -type f -perm 0600 \) \) -print \
    \( \( -name "$HASH.label" -size -1025c \) -o \( -name "$HASH.tkmem" -size -8193c \) -o \( -name "$HASH.subs" -size -8193c \) \
       -o \( -name "$HASH.acts" -size -16385c \) -o \( -name "$HASH.agents" -size -16385c \) -o \( -name "$HASH.rsm" -size -16385c \) \) -print 2>/dev/null)
  PS_OUT=$'\n'"$PS_OUT"$'\n'
  return 0
}
pfc() {
  case "$PS_NAMES" in *$'\n'"$1"$'\n'*) ;; *) private_file_ok "$1"; return ;; esac
  { [ ! -e "$1" ] && [ ! -L "$1" ]; } && return 0
  case "$PS_OUT" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}
pfcap() { case "$PS_OUT" in *$'\n'"$1"$'\n'"$1"$'\n'*) return 0 ;; esac; return 1; }
# live_dir_scan_ok: live_dir_ok for the main path, with the first scan (the directory and the files read before the lock).
live_dir_scan_ok() {
  [ -L "$LIVE_DIR" ] && return 1
  [ -e "$LIVE_DIR" ] || mkdir -m 700 "$LIVE_DIR" 2>/dev/null || [ -d "$LIVE_DIR" ] || return 1   # parallel first hooks race here
  priv_scan label tkmem rsm
  case "$PS_OUT" in *$'\n'"$LIVE_DIR"$'\n'*) return 0 ;; esac
  return 1
}
# The live directory: a real directory owned by the user, mode 0700 (SHD-01); created 0700 when absent.
live_dir_ok() {
  [ -L "$LIVE_DIR" ] && return 1
  [ -e "$LIVE_DIR" ] || mkdir -m 700 "$LIVE_DIR" 2>/dev/null || [ -d "$LIVE_DIR" ] || return 1   # parallel first hooks race here
  [ -n "$(find "$LIVE_DIR" -prune -type d -user "$UID_NOW" -perm 0700 -print 2>/dev/null)" ]
}

# texts_off: display texts are off (BR-03): the activity-off flag or the cached detailed-off flag; any entry counts (fail safe).
texts_off() {
  [ -e "$LIVE_DIR/activity-off" ] || [ -L "$LIVE_DIR/activity-off" ] || [ -e "$LIVE_DIR/detailed-off" ] || [ -L "$LIVE_DIR/detailed-off" ]
}

# ─── ALY-263.1: safe read of a Claude transcript file (AC-02, AC-03, BR-02, D-16) ───
# One budget of 2 seconds is shared by every read of this hook invocation: RD_END (Unix ms) is set ONCE, in the main shell, before the
# first read (never inside a $(...), where the assignment would be lost); rd_left only reads it, so every later read sees less.
RD_END=""
rd_left() {  # prints the budget left as S.mmm; fails once it is spent (or when no deadline was set)
  local now left
  [[ "$RD_END" =~ ^[0-9]{13}$ ]] || return 1
  now=$(now_ms); [[ "$now" =~ ^[0-9]{13}$ ]] || return 1
  left=$((RD_END - now)); [ "$left" -gt 0 ] || return 1
  printf '%d.%03d' $((left / 1000)) $((left % 1000))
}
# claude_safe_tail FILE BYTES [BASENAME-REGEX]: prints "full" or "partial" (the file is larger than BYTES), a newline, then the
# last BYTES bytes of FILE, and succeeds; it fails on any failed check, and the output of a failed call must be ignored (a read
# killed by the budget may have printed part of it). FILE must lie under the physical projects directory of the user's Claude
# config (CLAUDE_CONFIG_DIR, else $HOME/.claude; never from the payload), with every directory below it a real directory (no
# symlink), no `..`, `.`, empty or newline component, and a basename matching the pattern (default: a subagent file); the file
# itself is a regular non-symlink file of the user. Only string checks run here; every filesystem step (cd, -L and -d tests, find)
# and the single open run in ONE child under `timeout` set to the budget left, so a hung mount cannot block the hook. The child
# checks the opened descriptor again and reads only from it (a FIFO swapped in blocks the open and is killed by the budget).
claude_safe_tail() {
  local f="$1" n="$2" re="${3:-}" base left
  [ -n "$re" ] || re='^agent-[A-Za-z0-9_-]{1,64}\.(jsonl|meta\.json)$'
  [[ "$n" =~ ^[0-9]{1,8}$ ]] || return 1
  case "$f" in /*) ;; *) return 1 ;; esac
  case "$f" in *$'\n'*|*//*|*/./*|*/../*|*/.|*/..) return 1 ;; esac
  [[ "${f##*/}" =~ $re ]] || return 1
  base="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  case "$base" in /*) ;; *) return 1 ;; esac
  case "$base" in *$'\n'*) return 1 ;; esac
  command -v timeout >/dev/null 2>&1 || return 1
  left=$(rd_left) || return 1
  timeout "$left" "$BASH" -c '
    unset CDPATH
    f=$1; n=$2; uid=$3
    root=$(cd -P "$4/projects" 2>/dev/null && pwd -P) || exit 1
    case "$root" in /*) ;; *) exit 1 ;; esac
    case "$f" in "$root"/*) ;; *) exit 1 ;; esac
    rel="${f#"$root"/}"
    IFS=/ read -r -a parts <<<"$rel" || exit 1
    [ "${#parts[@]}" -ge 1 ] && [ "${#parts[@]}" -le 8 ] || exit 1
    cur="$root"
    for ((i = 0; i < ${#parts[@]} - 1; i++)); do
      c="${parts[i]}"; [ -n "$c" ] || exit 1
      cur="$cur/$c"
      [ -L "$cur" ] && exit 1
      [ -d "$cur" ] || exit 1
    done
    [ -L "$f" ] && exit 1
    [ -n "$(find "$f" -prune -type f -user "$uid" -print 2>/dev/null)" ] || exit 1
    { exec 3<"$f"; } 2>/dev/null || exit 1
    [ -n "$(find -L /dev/fd/3 -prune -type f -user "$uid" -print 2>/dev/null)" ] || exit 1
    if [ -n "$(find -L /dev/fd/3 -prune -size -"$((n + 1))"c -print 2>/dev/null)" ]; then echo full; else echo partial; fi
    tail -c "$n" <&3 | tr -d "\0"' _ "$f" "$n" "$UID_NOW" "$base" 2>/dev/null
}
# transcript_report FILE: prints the crew report taken from the tail of a subagent transcript, or fails (AC-01, AC-03).
# Candidates, in order: the last SubagentHandback input.message, then the last assistant text block; the first with exactly one
# column-0 `status:` (with a value) and at most one `summary:` wins. Blocks are never joined. Only `assistant` lines count.
# MODE (second argument, ALY-263.11): "report" (default) prints only that report. "both" and "hb" print a first line "COUNT IDENT", a
# newline, then the report ("both": the order above; "hb": the newest handback only, never the text block); they succeed with an empty
# report when none qualifies. COUNT is the number of SubagentHandback tool_use blocks the tail holds (a window count), IDENT the identity of
# the newest one: "i<tool_use id>" when it has an id of at most 40 characters, else "h<first 16 hex of the sha256 of its message>"
# (never the text); "-" when unknown. A read widened to 1 MB gives "- -" (its window differs from the narrow one, so nothing is comparable)
# and no handback in the tail gives "0 -".
transcript_report() {
  local n got out mode="${2:-report}"
  for n in 262144 1048576; do
    got=$(claude_safe_tail "$1" "$n" && printf x) || return 1   # the x keeps the final newline of the tail
    got="${got%x}"
    out=$(printf '%s' "$got" | jq -Rsc --arg mode "$mode" '
      def blocks: .message | objects | .content | if type == "array" then .[] | objects elif type == "string" then {type: "text", text: .} else empty end;
      def good($m): ($m[0:65536] | split("\n") | map(sub("\r\\z"; ""))) as $l
        | [$l[] | select(startswith("status:"))] as $s
        | ($s | length) == 1 and ($s[0] | sub("\\Astatus:[ \t]*"; "") | length) > 0 and ([$l[] | select(startswith("summary:"))] | length) <= 1;
      index("\n") as $i
      | if $i == null then {n: 0, p: false}
        else (.[0:$i]) as $hd
          | (.[$i + 1:] | split("\n") | (if $hd == "partial" then .[1:] else . end) | .[:-1]) as $cl
          | [$cl[] | fromjson? | objects | select(.type == "assistant")] as $a
          | ([$a[] | blocks | select(.type == "tool_use" and .name == "SubagentHandback") | .input | objects | .message | strings] | last) as $hb
          | ([$a[] | blocks | select(.type == "text") | .text | strings] | last) as $tx
          | {n: ($cl | map(select(length > 0)) | length), p: ($hd == "partial"),
             c: ([$a[] | blocks | select(.type == "tool_use" and .name == "SubagentHandback")] | length),
             i: (([$a[] | blocks | select(.type == "tool_use" and .name == "SubagentHandback")] | last | (.id // null) | strings | select(test("\\A[A-Za-z0-9_-]{1,40}\\z"))) // null),
             h: $hb,
             m: ((if $mode == "hb" then [$hb] else [$hb, $tx] end) | map(select(. != null and good(.))) | .[0] | if . == null then null else .[0:65536] end)}
        end' 2>/dev/null) || return 1
    if [ "$(printf '%s' "$out" | jq -r '.n' 2>/dev/null)" = 0 ]; then
      # no complete line fits: widen once, and only when the file is larger than what was read
      [ "$n" = 262144 ] && [ "$(printf '%s' "$out" | jq -r '.p' 2>/dev/null)" = true ] && continue
      return 1
    fi
    if [ "$mode" = report ]; then printf '%s' "$out" | jq -je '.m // empty' 2>/dev/null || return 1
    else
      local cnt idn hmsg
      cnt=$(printf '%s' "$out" | jq -r '.c' 2>/dev/null) && [[ "$cnt" =~ ^[0-9]{1,9}$ ]] || return 1
      idn=-
      if [ "$n" = 1048576 ]; then cnt=-
      elif [ "$cnt" != 0 ]; then
        idn=$(printf '%s' "$out" | jq -r '.i // empty' 2>/dev/null) || idn=""
        if [ -n "$idn" ]; then idn="i$idn"
        else
          hmsg=$(printf '%s' "$out" | jq -j '.h // empty' 2>/dev/null; printf x) || hmsg=x
          hmsg="${hmsg%x}"
          if [ -n "$hmsg" ]; then idn=$(printf '%s' "$hmsg" | sha_hex 2>/dev/null) && idn="h${idn:0:16}" || idn=-; else idn=-; fi
        fi
      fi
      printf '%s %s\n' "$cnt" "$idn"
      printf '%s' "$out" | jq -j '.m // empty' 2>/dev/null
    fi
    return 0
  done
  return 1
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
    if mkdir "$d" 2>/dev/null && ( set -C; if [ -n "${3:-}" ]; then pidlock_rec "$3" >"$d/p"; elif [ "${DATE_REAL:-0}" = 1 ]; then printf '%s %s' "${EPOCHREALTIME%%[.,]*}" "$LOCK_TOKEN" >"$d/t"; else printf '%s %s' "$(date +%s 2>/dev/null)" "$LOCK_TOKEN" >"$d/t"; fi ) 2>/dev/null; then return 0; fi
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
now_ms() { local m; if [ "${DATE_REAL:-0}" = 1 ] && [[ "${EPOCHREALTIME:-}" =~ ^([0-9]{1,12})[.,]([0-9]{3}) ]]; then printf '%s' "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; return 0; fi; m=$(date +%s%3N 2>/dev/null); [[ "$m" =~ ^[0-9]{13,19}$ ]] && m=${m:0:13} || m="$(date +%s 2>/dev/null)000"; printf '%s' "$m"; }
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
  # ALY-263.13 (AC-16, D-18): a full spool loses phrase events first: the oldest `sub_tool` events and the main-session `tool` events
  # that carry an `activity` go before anything else (sub_start, sub_stop, state, bind, gates, label, a tool without a phrase); only when
  # no such event is left do the oldest other lines go, as before. Order is kept.
  # ALY-269.2: a `cmd_end` is an optional refinement (without it the app keeps its derived rule), so it goes after the phrases and before every
  # other kind: phrases, then the oldest cmd_end events, then the rest. A jq failure falls back to the plain newest-500 trim.
  # The type keys are matched on the compact lines the hook writes (`"type":"sub_tool"`): a phrase quote inside a value is escaped, so it
  # can never spell that key.
  if jq -Rrn '
      [inputs] as $l | ($l | length) as $n | ($l | map((utf8bytelength) + 1)) as $b
      | ($l | map(if test("\"type\":\"sub_tool\"") or (test("\"type\":\"tool\"") and test("\"activity\":")) then 0
                    elif test("\"type\":\"cmd_end\"") then 1 else 2 end)) as $ev
      | ([range(0; $n) | select($ev[.] == 0)] + [range(0; $n) | select($ev[.] == 1)] + [range(0; $n) | select($ev[.] == 2)]) as $order
      | (reduce $order[] as $i ({d: {}, n: $n, b: ($b | add // 0)};
          if .n > 500 or .b > 262144 then .d[($i | tostring)] = true | .n -= 1 | .b -= $b[$i] else . end) | .d) as $d
      | range(0; $n) | select($d[tostring] | not) | $l[.]' "$f" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    return 0
  fi
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
      elif .key == "resumed" then (.value == true)
      elif .key == "phase" then (.value | IN("stage","publish"))
      else true end;
    def prok: (.pr | type == "number" and . == floor and . >= 1 and . <= 9999999);
    def keep: with_entries(select(.key | IN("seq","at","type","state","tool","code","sub","bind","gates","pr","activity","label","tu","h","ok")))
      | (if has("tu") and ((.tu | type == "string" and test("\\A[A-Za-z0-9_-]{1,64}\\z")) and (.type | IN("tool","sub_tool","cmd_end")) | not) then del(.tu) else . end)
      | (if has("h") and ((.h | type == "string" and test("\\A[0-9a-f]{64}\\z")) and .type == "cmd_end" | not) then del(.h) else . end)
      | (if has("ok") and ((.ok | type == "boolean") and .type == "cmd_end" | not) then del(.ok) else . end)
      | (if has("pr") and ((.type == "gates" and prok) | not) then del(.pr) else . end)
      | (if (.sub | type) == "object" then .sub |= (with_entries(select(.key | IN("id","type","outcome","task","desc","summary","attempt","next","gate","checks","findings","resumed","phase")) | select(subfld))
          | (if has("checks") then .checks |= pick(["ok","run"]) else . end)
          | (if has("findings") then .findings |= pick(["critical","high","medium","low","info"]) else . end)) else . end);
    def ok: type == "object" and (.seq | type == "number" and . == floor and . >= 1) and (.at | type == "string")
            and (.type | IN("state","tool","sub_start","sub_tool","sub_stop","bind","gates","label","cmd_end"))
            and (if .type == "label" then (.label | type == "object" and (keys - ["text","source","cwd"] | length) == 0
                   and (.text | type == "string" and (explode | length) >= 1 and (explode | length) <= 60) and (.source | IN("explicit","ai"))
                   and (.cwd == null or (.cwd | type == "string" and test("\\A[A-Za-z0-9._-]{1,60}\\z")))) else true end);
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
# ALY-269.2 (AC-12, D-06): the `notu` mark, same shape and safety as the back-off file (`<until epoch> <credential fingerprint>`): set when ingest
# answers 400 to a batch that carried `tu` or `cmd_end` (an API that does not know them), for 10 minutes. While it lasts, batch_build leaves
# `tu` out and skips every cmd_end. The mark belongs to the API, not to a session, so it is kept per credential like the back-off.
NOTUF="$LIVE_DIR/notu"
notu_active() {
  local u="" f="" now
  [ -f "$NOTUF" ] && [ ! -L "$NOTUF" ] && private_file_ok "$NOTUF" || return 1
  { IFS=' ' read -r u f <"$NOTUF"; } 2>/dev/null
  credfp
  [[ "$u" =~ ^[0-9]{1,12}$ ]] && [ "$f" = "$CFP" ] || return 1
  now=$(date +%s 2>/dev/null) || return 1
  [[ "$now" =~ ^[0-9]{1,12}$ ]] && [ "$now" -lt "$u" ]
}
notu_set() {  # SECONDS from now, for this credential; fails (non-zero) when the mark could not be written
  local now tmp
  now=$(date +%s 2>/dev/null) || return 1; credfp
  tmp=$(mktemp "$LIVE_DIR/.notu.XXXXXX" 2>/dev/null) || return 1; TMPF="$tmp"
  printf '%s %s' "$((now + $1))" "$CFP" >"$tmp" 2>/dev/null && mv -f "$tmp" "$NOTUF" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
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
  local n base out rest now strip notu
  BK=0; BMAX=0; BODY=""
  now=$(date +%s 2>/dev/null) || return 1; [[ "$now" =~ ^[0-9]{1,12}$ ]] || return 1
  [ -f "$SPOOL" ] && [ ! -L "$SPOOL" ] || return 1
  n=$(wc -l <"$SPOOL" 2>/dev/null); n=${n//[[:space:]]/}
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || return 1
  # ALY-258.3 (BR-03, AC-14): texts off = the activity-off flag or the detailed-off flag (existence of any entry: fail safe), judged
  # at every flush. Then `activity`, `sub.desc` and `sub.summary` are removed from EVERY event, also from those spooled before the
  # flag existed; the structured fields and the tool events go on. This is the one place a spooled event becomes a request.
  strip=0
  if [ -e "$LIVE_DIR/activity-off" ] || [ -L "$LIVE_DIR/activity-off" ] || [ -e "$LIVE_DIR/detailed-off" ] || [ -L "$LIVE_DIR/detailed-off" ]; then strip=1; fi
  notu=0; if notu_active; then notu=1; fi   # ALY-269.2 (AC-12): after a 400 for tu/cmd_end the batch goes without them
  base=$(printf '{"client":{"kind":"claude-code"},"session":{"hash":"%s"},"events":[' "$HASH")
  out=$(head -n "$n" "$SPOOL" 2>/dev/null | jq -Rn -r --arg base "$base" --arg strip "$strip" --arg notu "$notu" --argjson now "$now" "$(jq_valid_def)"'
    [inputs] as $L
    | (reduce range(0; $L | length) as $i ({evs: [], size: (($base | utf8bytelength) + 2), k: 0, max: 0, done: false};
        if .done then .
        else (($L[$i] | try fromjson catch null)) as $e
          | if ($e | ok | not) then .k = $i + 1
            elif ($e | fresh($now) | not) then .k = $i + 1 | .max = ([.max, $e.seq] | max)
            elif $strip == "1" and $e.type == "label" then .k = $i + 1 | .max = ([.max, $e.seq] | max)   # a label is display text (ALY-263.6, BR-03): not sent while texts are off
            elif $notu == "1" and $e.type == "cmd_end" then .k = $i + 1 | .max = ([.max, $e.seq] | max)   # ALY-269.2: dropped for 10 minutes after a 400
            else ($e | keep | (if $notu == "1" then del(.tu) else . end) | if $strip == "1" then del(.activity) | (if (.sub | type) == "object" then .sub |= del(.desc, .summary) else . end) else . end) as $ev | ($ev | tojson | utf8bytelength) as $len
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
# detailed_cache VALUE (ALY-258.3, D-36, AC-14): VALUE is "false" when the 2xx ack is a valid ack (`.data.accepted` a number) carrying
# the strict boolean `detailed: false`; "clear" when it is a valid ack without that (true, absent, null, another type: absent = true);
# "keep" for a 2xx whose body is not a valid ack (204, empty, truncated, not JSON, a captive-portal page): fail closed, the flag is
# left exactly as it is (never set, never cleared; Shield SHD-01). false writes $LIVE_DIR/detailed-off (empty,
# temp 0600 + mv under the state lock, so a symlink at that name is replaced, never followed) and deletes the Agent stashes of every
# session (no text is stashed any more); other removes the flag. No network call: the answer was already there. Best effort: a lock
# that cannot be taken leaves the flag as it was and the next ack decides again.
detailed_cache() {
  local flag="$LIVE_DIR/detailed-off" tmp tok f base
  [ "$1" = false ] || [ "$1" = clear ] || return 0
  if [ "$1" = false ]; then
    [ -f "$flag" ] && [ ! -L "$flag" ] && private_file_ok "$flag" && return 0
    lock_take "$LOCKD" "${DROP_TRIES:-250}" || return 0
    tok="$LOCK_TOKEN"
    if tmp=$(mktemp "$LIVE_DIR/.detailed.XXXXXX" 2>/dev/null); then
      TMPF="$tmp"
      : >"$tmp" 2>/dev/null && mv -f "$tmp" "$flag" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi
    for f in "$LIVE_DIR"/*; do
      base="${f##*/}"
      [[ "$base" =~ ^[0-9a-f]{64}\.(agents|acts|label)$ ]] || continue
      if [ -L "$f" ] || { [ -f "$f" ] && [ -n "$(find "$f" -prune -type f -user "$UID_NOW" -print 2>/dev/null)" ]; }; then rm -f "$f" 2>/dev/null; fi
    done
    lock_drop "$LOCKD" "$tok"
  else
    { [ -e "$flag" ] || [ -L "$flag" ]; } || return 0
    lock_take "$LOCKD" "${DROP_TRIES:-250}" || return 0
    tok="$LOCK_TOKEN"; rm -f "$flag" 2>/dev/null; lock_drop "$LOCKD" "$tok"
  fi
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
  local rounds=0 status ecode ra before left mt ct det
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
    ecode=$(head -c 65536 "$RESPF" 2>/dev/null | jq -r '.error.message.code | strings' 2>/dev/null | head -n 1)
    # ALY-258.3 (D-36): the same bounded read gives the ack's `detailed` flag; only a 2xx with a valid ack body is looked at (strict boolean false)
    det=keep
    case "$status" in 2??) det=$(head -c 65536 "$RESPF" 2>/dev/null | jq -r 'if (.data | objects | .accepted | numbers) == null then "keep" elif .data.detailed == false then "false" else "clear" end' 2>/dev/null | head -n 1); [ "$det" = false ] || [ "$det" = clear ] || det=keep ;; esac
    rm -f "$RESPF" 2>/dev/null
    [[ "$ecode" =~ ^[A-Z_]{1,60}$ ]] || ecode=""
    case "$status" in
      400)
        # ALY-269.2 (AC-12, D-06): a 400 for a batch that carried `tu` or `cmd_end` is most likely an API that does not know them: mark it for
        # 10 minutes and go round again; the same lines (same seq, nothing renumbered) are rebuilt without those fields and sent once more, so
        # the phrase events are not lost. The test is on the body that was sent (built WITH tu/cmd_end, so before any mark), not on the mark now:
        # another session may have set it while this request was in flight. When the mark cannot be written and is not active, the batch is
        # discarded (no resend loop). A 400 for a body without them is discarded as before.
        case "$BODY" in
          *'"type":"cmd_end"'*|*'"tu":"'*)
            if notu_active || { notu_set 600; notu_active; }; then rm -f "$HDRF" 2>/dev/null; continue; fi ;;
        esac
        spool_drop_sent "$BMAX" || return 1
        [ "$(wc -c <"$SPOOL" 2>/dev/null)" != "$before" ] || return 1 ;;
      2??|413)
        # 413 (and 2xx): the batch is discarded and the next one tried, so a plugin newer than the API (new fields, strict body)
        # loses its batches with a 400; hence the release order API -> plugin (ALY-257 D-10), and the API rolls back only
        # together with the plugin (ALY-258.3 D-37; docs/live-reporting.md, task .5).
        case "$status" in 2??) detailed_cache "$det" ;; esac
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

# ─── ALY-263.1: crew result from the subagent transcript (AC-01, AC-02, D-10). At a SubagentStop whose message has no column-0
# `status:` line (with a value), the report is read from the subagent transcript and replaces last_assistant_message in the
# in-memory payload, so the parser below is unchanged. File I/O is here, before the state lock; any failure keeps the payload.
# ─── ALY-263.4: dispatch description from the subagent metadata file (AC-07, D-03, D-14). At every SubagentStop the metadata file
# next to the subagent transcript is read (same safe open, same shared budget) and only its `description` string is put in the
# in-memory payload as `meta_desc` (a key of that name in the payload itself is removed first); the jq program cleans it and sends
# it as sub.desc unless texts are off. Nothing else of the file is kept; any failure sends nothing extra.
# agent_file_of EXT: prints the path of the subagent file with extension EXT (jsonl or meta.json) from $TRF, or fails. A path given
# by the payload is used for the transcript as it is; for the metadata file it must be agent-<hook agent id>.jsonl, with .meta.json.
agent_file_of() {
  local p t s i
  p=$(printf '%s' "$TRF" | jq -r '.a // empty' 2>/dev/null) || p=""
  t=$(printf '%s' "$TRF" | jq -r '.t // empty' 2>/dev/null) || t=""
  s=$(printf '%s' "$TRF" | jq -r '.s // empty' 2>/dev/null) || s=""
  i=$(printf '%s' "$TRF" | jq -r '.i // empty' 2>/dev/null) || i=""
  if [ -n "$p" ]; then
    if [ "$1" = jsonl ]; then printf '%s' "$p"; return 0; fi
    [[ "$i" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && [ "${p##*/}" = "agent-$i.jsonl" ] || return 1
    printf '%s' "${p%.jsonl}.meta.json"; return 0
  fi
  if [[ "$s" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && [[ "$i" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && [ -n "$t" ]; then printf '%s' "${t%/*}/$s/subagents/agent-$i.$1"; return 0; fi
  return 1
}
# meta_description FILE: prints the description string of the metadata file (at most 64 KB, a JSON object), or fails. When the file
# carries an agent id key (agentId or agent_id) it must equal the hook agent id, else the description is dropped.
meta_description() {
  local got hd
  got=$(claude_safe_tail "$1" 65536 && printf x) || return 1
  got="${got%x}"; hd="${got%%$'\n'*}"
  [ "$hd" = full ] || return 1
  printf '%s' "${got#*$'\n'}" | jq -je --arg id "$(printf '%s' "$TRF" | jq -r '.i // empty' 2>/dev/null)" '
    objects | select(((.agentId // .agent_id // $id) | . == $id)) | .description | strings | select(length > 0) | .[0:4096]' 2>/dev/null
}
HBC=-1; HBK=""
{
  # ALY-263.13 (AC-16): the stop read below can only select a payload that names SubagentStop; a payload without that text, and without a
  # backslash (a JSON escape could spell the name), skips the jq call
  TRF=""
  case "$INPUT" in *SubagentStop*|*\\*) TRF=$(printf '%s' "$INPUT" | jq -c '
    select(.hook_event_name == "SubagentStop")
    | {a: ((.agent_transcript_path | strings) // ""), t: ((.transcript_path | strings) // ""), s: ((.session_id | strings) // ""), i: ((.agent_id | strings) // ""),
       ns: ([(.last_assistant_message | strings | split("\n") | .[] | sub("\r\\z"; "") | select(test("\\Astatus:[ \t]*[^ \t]")))] | length == 0)}
    | select([.a, .t, .s, .i | test("\n")] | any | not)' 2>/dev/null) || TRF="" ;; esac
  if [ -n "$TRF" ]; then
    RD_END="$(( $(now_ms) + 2000 ))"   # the one deadline of this invocation, set here in the main shell (never in a $(...))
    # One read of the subagent transcript tail at every stop (ALY-263.11): the report when the message has no status line, and the
    # handback count recorded for the resume close (HBC, -1 when unknown). Nothing of the transcript is kept but that integer.
    TRP=$(agent_file_of jsonl) || TRP=""
    if [ -n "$TRP" ] && TRB=$(transcript_report "$TRP" both) && [[ "${TRB%%$'\n'*}" =~ ^([0-9]{1,9}|-)\ ([ih][A-Za-z0-9_-]{1,40}|-)$ ]]; then
      HBC="${BASH_REMATCH[1]}"; HBK="${BASH_REMATCH[2]}"; [ "$HBC" != - ] || HBC=-1; [ "$HBK" != - ] || HBK=""
      TRR="${TRB#*$'\n'}"; [[ "$TRB" == *$'\n'* ]] || TRR=""
      if [ -n "$TRR" ] && [ "$(printf '%s' "$TRF" | jq -r '.ns' 2>/dev/null)" = true ]; then
        TRN=$(printf '%s' "$INPUT" | jq -c --rawfile m <(printf '%s' "$TRR") '.last_assistant_message = $m' 2>/dev/null) && [ -n "$TRN" ] && INPUT="$TRN"
      fi
    fi
    MDS=""
    if MDP=$(agent_file_of meta.json) && MDS=$(meta_description "$MDP"; printf x); then MDS="${MDS%x}"; else MDS=""; fi
    TRN=$(printf '%s' "$INPUT" | jq -c --rawfile d <(printf '%s' "$MDS") 'del(.meta_desc) | if $d != "" then .meta_desc = $d else . end' 2>/dev/null) && [ -n "$TRN" ] && INPUT="$TRN"
  fi
} 2>/dev/null

SPOOL="$LIVE_DIR/$HASH.spool"
STATEF="$LIVE_DIR/$HASH.state"

# The live directory is checked before the first read or write (SHD-01), then every read-modify-write of this
# session (state, bind, gates, seq, spool) runs under one lock, so parallel hooks of a session are consistent.
# A hook that cannot get the lock within about 10 seconds gives up and drops its events (it exits 0, silent).
live_dir_scan_ok || exit 0
HAVE_LOCK=0; LOCKD="$LIVE_DIR/$HASH.lock"
TMPF=""
# EFTOK: the flush lock held by this hook's own SessionEnd send (never the lock of a flusher it detached).
EFTOK=""
cleanup() { [ -z "$TMPF" ] || rm -f "$TMPF" "$TMPF.2" 2>/dev/null; [ "$HAVE_LOCK" = 1 ] && lock_drop "$LOCKD" "$STATE_TOKEN"; [ -z "$EFTOK" ] || lock_drop "$FLOCK" "$EFTOK"; return 0; }
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

# ─── ALY-263.6: session label inputs (AC-09, AC-02, D-17), read outside the lock like the subagent files. A check is due at a
# SessionStart of a known source and, for any other event of the main session (not SessionEnd), when $HASH.label ("<ms> <json>": the time
# of the last check and the last value sent, 0600, at most 1024 bytes) is missing, older than a minute or from the future. The session
# transcript (<session id>.jsonl, id ^[A-Za-z0-9_-]{1,64}$) is read through the same safe open and the same 2 s budget as the subagent
# files, last 262144 bytes, invalid JSON lines skipped; a failed read only means no title. LBLIN is the JSON the jq program cleans, or
# null. The working directory basename (`cwd`) goes inside the label and only with a label text (the API requires the text); it is
# taken only from a real directory, so a payload cwd that names nothing sends nothing.
LBLIN=null; LBLDUE=0; LBLSTORED=""; LBLMS=""
label_state_read() {  # sets LBLMS and LBLSTORED from $LBLF, or empties them (absent, not private, oversized or off the shape)
  local l
  LBLMS=""; LBLSTORED=""
  LBLBAD=0
  [ -f "$LBLF" ] && [ ! -L "$LBLF" ] || { { [ -e "$LBLF" ] || [ -L "$LBLF" ]; } && ! pfc "$LBLF" && LBLBAD=1; return 0; }
  # ALY-263.13: LBLBAD marks a file that EXISTS but is not a private regular file: nothing can be written over it, so no due check runs
  pfcap "$LBLF" || { pfc "$LBLF" || LBLBAD=1; return 0; }
  { IFS= read -r l <"$LBLF"; } 2>/dev/null
  if [[ "$l" =~ ^([0-9]{13})\ (\{.*\})$ ]]; then LBLMS="${BASH_REMATCH[1]}"; LBLSTORED="${BASH_REMATCH[2]}"; fi
}
LBLF="$LIVE_DIR/$HASH.label"
if ! texts_off; then
  label_state_read
  # ALY-263.13: no clock fork when the stored time is plainly recent: bash's own clock decides "not due" (the date shim of the tests
  # sets a fake clock, so any other case, a stored time ahead of the real clock included, goes through now_ms as before).
  LBLNOW=""
  if [[ "$LBLMS" =~ ^[0-9]{13}$ ]] && [[ "${EPOCHREALTIME:-}" =~ ^([0-9]{1,12})[.,]([0-9]{3}) ]]; then
    LBLNOW="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    { [ "$LBLNOW" -ge "$LBLMS" ] && [ $((LBLNOW - LBLMS)) -lt 60000 ]; } || LBLNOW=""
  fi
  [ -n "$LBLNOW" ] || LBLNOW=$(now_ms)
  LBLTHR=1
  if [[ "$LBLNOW" =~ ^[0-9]{13}$ ]] && [[ "$LBLMS" =~ ^[0-9]{13}$ ]] && [ "$LBLNOW" -ge "$LBLMS" ] && [ $((LBLNOW - LBLMS)) -lt 60000 ]; then LBLTHR=0; fi
  case "$INPUT" in *SessionStart*) LBLMAYBE=1 ;; *) LBLMAYBE=$LBLTHR ;; esac
  [ "$LBLBAD" = 1 ] && LBLMAYBE=0
  if [ "$LBLMAYBE" = 1 ]; then
    LBP=$(printf '%s' "$INPUT" | jq -c '
      select(.hook_event_name | strings | . != "" and . != "SessionEnd") | select((.agent_id // null) == null)
      | {st: ((.hook_event_name == "SessionStart") and (.source | IN("startup","resume","clear","compact","fork"))),
         sid: ((.session_id | strings) // ""), tp: ((.transcript_path | strings) // ""), cwd: ((.cwd | strings) // "")}
      | select([.sid, .tp | test("[\u0000-\u001f\u007f]")] | any | not)
      | .cwd |= (if test("[\u0000-\u001f\u007f]") then "" else . end)' 2>/dev/null) || LBP=""
    if [ -n "$LBP" ] && { [ "$LBLTHR" = 1 ] || [ "$(printf '%s' "$LBP" | jq -r '.st' 2>/dev/null)" = true ]; }; then
      LBLDUE=1
      LBLT=""; LBLA=""; LBLC0=""
      LBLSID=$(printf '%s' "$LBP" | jq -r '.sid' 2>/dev/null) || LBLSID=""
      LBLTP=$(printf '%s' "$LBP" | jq -r '.tp' 2>/dev/null) || LBLTP=""
      LBLCWD=$(printf '%s' "$LBP" | jq -r '.cwd' 2>/dev/null) || LBLCWD=""
      if [[ "$LBLSID" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && [ "${LBLTP##*/}" = "$LBLSID.jsonl" ]; then
        [[ "$RD_END" =~ ^[0-9]{13}$ ]] || RD_END="$(( $(now_ms) + 2000 ))"
        if LBLGOT=$(claude_safe_tail "$LBLTP" 262144 '^[A-Za-z0-9_-]{1,64}\.jsonl$' && printf x); then
          LBLGOT="${LBLGOT%x}"
          LBLTT=$(printf '%s' "$LBLGOT" | jq -sRc '
            index("\n") as $i
            | if $i == null then empty else
                (.[0:$i]) as $hd
                | (.[$i + 1:] | split("\n") | (if $hd == "partial" then .[1:] else . end) | .[:-1]) as $cl
                | [$cl[] | fromjson? | objects] as $o
                | {t: ([$o[] | select(.type == "custom-title") | .customTitle | strings] | last | if . == null then null else .[0:4096] end),
                   a: ([$o[] | select(.type == "ai-title") | .aiTitle | strings] | last | if . == null then null else .[0:4096] end)}
              end' 2>/dev/null) || LBLTT=""
        else LBLTT=""; fi
      else LBLTT=""; fi
      [ -n "$LBLTT" ] || LBLTT='{"t":null,"a":null}'
      LBLBASE=""
      case "$LBLCWD" in
        /*) if [ "${#LBLCWD}" -le 4096 ] && [ -d "$LBLCWD" ]; then LBLBASE="${LBLCWD%"${LBLCWD##*[!/]}"}"; LBLBASE="${LBLBASE##*/}"; fi ;;
      esac
      # the title and the basename go to jq on stdin, never through argv
      LBLIN=$({ printf '%s\n' "$LBLTT"; printf '%s' "$LBLBASE" | jq -Rc . ; printf '%s' "$LBP" | jq -c '.st'; } | jq -sc '.[0] + {c: (.[1] | if . == "" then null else . end), st: .[2]}' 2>/dev/null) || LBLIN=null
      [ -n "$LBLIN" ] || LBLIN=null
      LBLTT=""; LBLGOT=""
    fi
  fi
fi

# ─── ALY-263.10: task key inputs (AC-10, D-07, D-14, AC-02), read outside the lock like the other files. TKPFX: the one project prefix of
# the strongest binding ($HASH.bind, the touched spec keys of $HASH.touch): exactly one distinct project, else "" (no binding or several
# projects). TKID/TKDESC: at the FIRST tool of an agent id (no entry marked tried in $HASH.tkmem) the metadata file is read through the same
# safe open and the same 2 s budget as at the stop; whatever the result the jq program records the attempt, so it is never repeated. Only
# while texts are on.
TKPFX=""; TKID=""; TKDESC=""
tk_prefix() {  # sets TKPFX
  local b="" t="" all p first="" mixed=0
  if [ -f "$LIVE_DIR/$HASH.bind" ] && [ ! -L "$LIVE_DIR/$HASH.bind" ] && private_file_ok "$LIVE_DIR/$HASH.bind"; then b=$(head -c 1200 "$LIVE_DIR/$HASH.bind" 2>/dev/null) || b=""; fi
  if [ -f "$LIVE_DIR/$HASH.touch" ] && [ ! -L "$LIVE_DIR/$HASH.touch" ] && private_file_ok "$LIVE_DIR/$HASH.touch"; then t=$(head -c 1200 "$LIVE_DIR/$HASH.touch" 2>/dev/null) || t=""; fi
  all=$( { printf '%s\n' "$b" | LC_ALL=C grep -oE '"(spec|task)":"[A-Z][A-Z0-9]{1,9}-[0-9]' | LC_ALL=C sed -E 's/^"[a-z]+":"//; s/-[0-9]$//'
           printf '%s\n' "$t" | LC_ALL=C grep -oE '^[A-Z][A-Z0-9]{1,9}-[0-9]' | LC_ALL=C sed -E 's/-[0-9]$//'; } 2>/dev/null)
  while IFS= read -r p; do   # no sort in the hook PATH: distinct by hand
    [ -n "$p" ] || continue
    if [ -z "$first" ]; then first="$p"; elif [ "$p" != "$first" ]; then mixed=1; fi
  done <<<"$all"
  if [ "$mixed" = 0 ] && [[ "$first" =~ ^[A-Z][A-Z0-9]{1,9}$ ]]; then TKPFX="$first"; fi
}
tk_tried() {  # tk_tried ID: succeeds when $HASH.tkmem holds an entry of ID marked tried (a private regular file of at most 8192 bytes)
  local f="$LIVE_DIR/$HASH.tkmem" c
  [ -f "$f" ] && [ ! -L "$f" ] || return 1
  pfcap "$f" || return 1
  { IFS= read -r -d '' -N 8192 c <"$f"; } 2>/dev/null; [ -n "$c" ] || return 1   # builtin read: no fork
  [[ "$c" =~ \[\"$1\",\"([A-Z][A-Z0-9]{1,9}-[0-9]+(\.[0-9]+)?)?\",1\] ]]
}
# ALY-263.13 (AC-16): the hot path of a subagent tool event is cheap. The project prefix (about ten forks) is computed only where it is
# used: at a SubagentStart and a SubagentStop (a stash entry may give a task key to a first or synthetic sub_start) and at the PreToolUse
# of an agent id whose first-tool attempt is not recorded (TKID set). A PreToolUse whose payload holds the literal "agent_id" key
# exactly once, with an id that matches the pattern and is already recorded as tried, skips the parse and the prefix altogether: the
# jq read below can only reach the same answer (a single occurrence is either the top-level id or nothing the read would accept).
TKFAST=0
if ! texts_off; then
  case "$INPUT" in *PreToolUse*'"agent_id"'*)
    if [[ "$INPUT" =~ \"agent_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,64})\" ]]; then
      TKQ="${BASH_REMATCH[1]}"; TKX="${INPUT//\"agent_id\"/}"
      if [ $(( ${#INPUT} - ${#TKX} )) -eq 10 ] && tk_tried "$TKQ"; then TKFAST=1; fi
    fi ;;
  esac
fi
if [ "$TKFAST" = 0 ] && ! texts_off; then
  case "$INPUT" in *SubagentStart*|*SubagentStop*) tk_prefix ;; esac
  case "$INPUT" in *SubagentStart*|*'"agent_id"'*)
    case "$INPUT" in *PreToolUse*)
      TRF=$(printf '%s' "$INPUT" | jq -c '
        select(.hook_event_name == "PreToolUse") | select((.agent_id | strings | test("\\A[A-Za-z0-9_-]{1,64}\\z")) // false)
        | {a: "", t: ((.transcript_path | strings) // ""), s: ((.session_id | strings) // ""), i: .agent_id}
        | select([.t, .s | test("\n")] | any | not)' 2>/dev/null) || TRF=""
      if [ -n "$TRF" ]; then
        TKI=$(printf '%s' "$TRF" | jq -r '.i' 2>/dev/null) || TKI=""
        if [[ "$TKI" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && ! tk_tried "$TKI"; then
          TKID="$TKI"; tk_prefix
          [[ "$RD_END" =~ ^[0-9]{13}$ ]] || RD_END="$(( $(now_ms) + 2000 ))"
          if MDP=$(agent_file_of meta.json) && TKDESC=$(meta_description "$MDP"; printf x); then TKDESC="${TKDESC%x}"; else TKDESC=""; fi
        fi
      fi
      TRF="" ;;
    esac ;;
  esac
fi

# ─── ALY-263.11 (AC-12, D-05, D-19): the transcript-tail close of a resumed segment, inputs read outside the lock. $HASH.rsm: line 1 is
# the earliest time (ms) any tail check may run, or "-" while no segment could be closed; line 2 is the JSON [[id, type, SubagentHandback
# count at the last stop (-1 unknown), "s" stopped | "r" resumed and open | "c" closed from the tail, ms of the last tail check, identity of
# the newest handback at that stop ("" unknown)]] (at most 64, 0600, no text: the identity is a tool_use id or 16 hex of a sha256). Only an
# "r" entry with a known count and identity can be closed, so only those set line 1. A non-due event costs ZERO forks: one builtin `read`
# of line 1 and arithmetic on $EPOCHREALTIME (or `date` on a bash without it). A due event at a hook that is neither a SubagentStop nor a
# SessionEnd first checks the file is private (the RSOK test), then reads at most 2 due ids (an id at most once a minute, the time of every
# check is stored, a failed read too), each transcript through the same safe open and the same shared 2 s budget as the stop. TCL is the
# JSON the jq program turns into a sub_stop under the lock: [{id, c: count or null, k: identity or "", m: the newest handback report}];
# the jq program re-reads the state under the lock and closes only an entry still "r" whose newest identity DIFFERS from the recorded one
# and whose count is not lower; a count or identity of a widened read, or unknown, never closes (a window count alone proves nothing).
# A file of the former shape (no line 1) is read by the jq program but never sets a check: its entries cannot close either.
TCL='[]'
case "$INPUT" in
  *'"SubagentStop"'*|*'"SessionEnd"'*) ;;
  *)
    RSD=""
    if [ -f "$LIVE_DIR/$HASH.rsm" ] && [ ! -L "$LIVE_DIR/$HASH.rsm" ]; then { IFS= read -r RSD <"$LIVE_DIR/$HASH.rsm"; } 2>/dev/null; fi
    if [[ "$RSD" =~ ^[0-9]{1,16}$ ]]; then
      if [ -n "${EPOCHREALTIME:-}" ]; then RSNOW="${EPOCHREALTIME/[.,]/}"; RSNOW="${RSNOW:0:13}"; else RSNOW=$(now_ms); fi
      if [[ "$RSNOW" =~ ^[0-9]{13}$ ]] && { [ "$RSNOW" -ge "$RSD" ] || [ $((RSD - RSNOW)) -gt 120000 ]; } \
         && pfcap "$LIVE_DIR/$HASH.rsm"; then
        RSH=""; { IFS= read -r -d '' -N 16384 RSH <"$LIVE_DIR/$HASH.rsm"; } 2>/dev/null
        RSH="${RSH#*$'\n'}"
        RSDUE=$(printf '%s' "$RSH" | jq -r --argjson now "$RSNOW" '
          [ .[]? | select(type == "array" and length == 6 and (.[0] | type == "string" and test("\\A[A-Za-z0-9_-]{1,64}\\z"))
              and (.[1] | type == "string" and test("\\A[A-Za-z0-9:_-]{1,64}\\z")) and .[3] == "r" and (.[2] | type == "number") and .[2] >= 0
              and (.[5] | type == "string" and length > 0)
              and (.[4] | type == "number") and (.[4] == 0 or .[4] > $now or $now - .[4] >= 60000)) | .[0] ][:2] | .[]' 2>/dev/null) || RSDUE=""
        if [ -n "$RSDUE" ]; then
          RSP=$(printf '%s' "$INPUT" | jq -c '{a: "", t: ((.transcript_path | strings) // ""), s: ((.session_id | strings) // "")} | select([.t, .s | test("\n")] | any | not)' 2>/dev/null) || RSP=""
          if [ -n "$RSP" ]; then
            [[ "$RD_END" =~ ^[0-9]{13}$ ]] || RD_END="$(( $(now_ms) + 2000 ))"
            RSL=""
            while IFS= read -r RSI; do
              [[ "$RSI" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || continue
              TRF=$(printf '%s' "$RSP" | jq -c --arg i "$RSI" '. + {i: $i}' 2>/dev/null) || TRF=""
              RSC=null; RSK=""; RSM=""
              if [ -n "$TRF" ] && TRP=$(agent_file_of jsonl) && TRB=$(transcript_report "$TRP" hb) \
                 && [[ "${TRB%%$'\n'*}" =~ ^([0-9]{1,9}|-)\ ([ih][A-Za-z0-9_-]{1,40}|-)$ ]]; then
                [ "${BASH_REMATCH[1]}" = - ] || RSC="${BASH_REMATCH[1]}"
                [ "${BASH_REMATCH[2]}" = - ] || RSK="${BASH_REMATCH[2]}"
                [[ "$TRB" == *$'\n'* ]] && RSM="${TRB#*$'\n'}"
              fi
              RSL="$RSL$(jq -nc --arg i "$RSI" --argjson c "$RSC" --arg k "$RSK" --rawfile m <(printf '%s' "$RSM") '{id: $i, c: $c, k: $k, m: $m}' 2>/dev/null)"$'\n'
            done <<<"$RSDUE"
            TRF=""
            TCL=$(printf '%s' "$RSL" | jq -sc '.' 2>/dev/null) || TCL='[]'
            [ -n "$TCL" ] || TCL='[]'
          fi
        fi
      fi
    fi ;;
esac

lock_take "$LOCKD" 500 || exit 0
STATE_TOKEN="$LOCK_TOKEN"; HAVE_LOCK=1
# `/allye:hooks live off` may have run while this hook waited for the lock: it then drops its events (AC-11).
if [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ]; then exit 0; fi
FLOCK="$LIVE_DIR/$HASH.flush.lock"; WAITD="$LIVE_DIR/$HASH.flush.wait"; FTOK=""; FLUSHED="$LIVE_DIR/$HASH.flushed"; BATCHF="$LIVE_DIR/$HASH.batch"; HDRF="$LIVE_DIR/$HASH.hdr"; RESPF="$LIVE_DIR/$HASH.resp"; BACKOFFF="$LIVE_DIR/backoff"; CREDF="$LIVE_DIR/$HASH.cred"
FINALD="$LIVE_DIR/$HASH.final.lock"

LAST=""
priv_scan state agents acts tkmem rsm label subs spool cred seq
if [ -f "$STATEF" ] && [ ! -L "$STATEF" ] && pfc "$STATEF"; then
  LAST=$(cat "$STATEF" 2>/dev/null) || LAST=""
  case "$LAST" in started|working|waiting_input|idle|error|ended) ;; *) LAST="" ;; esac
fi
if [ "$DATE_REAL" = 1 ]; then TZ=UTC printf -v AT '%(%Y-%m-%dT%H:%M:%SZ)T' "${EPOCHREALTIME%%[.,]*}" 2>/dev/null || exit 0
else AT=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || exit 0; fi

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
# ALY-258 (SHD-01 of ALY-257): the API network rules. A token is split on = , ; [ ] ( ) | and every piece is tested whole, without
# leading/trailing `:` and without a `:port` suffix, as an e-mail, IPv4 (with port), IPv6, URL/www/arn:, hostname (also *.internal,
# *.local, *.corp) or a digit shape of 10+ digits. Mirrors pieceIsIdentifier of agent-run-text-scrub.ts.
def actbare: gsub("\\A[\"\u0027(\\[{<\u201c\u2018\u00ab]+"; "") | gsub("[\"\u0027)\\]}>\u201d\u2019\u00bb,;!?.]+\\z"; "");
def actident:
  length > 0 and (
    (contains("@") and contains("."))
    or test("\\A[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]{1,5})?\\z")
    or (test("\\A[0-9A-Fa-f.:]{3,}\\z") and ([match(":"; "g")] | length) as $n | $n >= 2 and (contains("::") or $n == 7))
    or (ascii_downcase | (contains("://") or contains("www.") or startswith("arn:")))
    or (ascii_downcase | test("\\.(internal|local|corp)\\z") or test("\\A([a-z0-9-]+\\.)+[a-z]{2,24}\\z"))
    or (test("\\A[0-9()+./-]*\\z") and ([match("[0-9]"; "g")] | length) >= 10));
def actnet:
  [splits("[=,;\\[\\]()|]")] | any(
    actbare as $b | ($b | actident) or ($b | gsub("\\A:+|:+\\z"; "") | . as $t | actident or (sub(":[0-9]{1,5}\\z"; "") | . != $t and actident)));
# ALY-263.9: the secret-shaped drops shared by actdrop and the basename of the classifier (a file name is not a hostname: only these apply to it).
def namedrop:
  test("[0-9A-Fa-f]{16,}")
  or ([match("[A-Za-z0-9+/=_-]{20,}"; "g").string | select(test("[0-9]"))] | length > 0)
  or test("[A-Za-z0-9_-]{24,}")
  # D-20 subset (ALY-258): the distinctive secret prefixes anywhere in the token; sk-/sk_/pk-/rk- only at its start or
  # after a non-alphanumeric (so risk-based survives); arn:; hostnames; colon/dash separated hex pairs.
  or test("(ghp_|gho_|ghs_|github_pat_|xox[abprs]-|AKIA|ASIA|eyJ|glpat-)")
  or test("(\\A|[^A-Za-z0-9])(sk-|sk_|pk-|rk-)");
def actdrop:
  actcore as $c
  | test("[/\\\\]") or ($c | test("\\A(~|[A-Za-z]:)")) or contains("://") or ($c | ascii_downcase | startswith("www."))
    or test("[^@]@[^@]+\\.[^@]") or ($c | test("\\A[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]{1,5})?\\z")) or contains("::")
    or ($c | test("\\A[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){2,}\\z"))
    or namedrop
    or ($c | ascii_downcase | startswith("arn:"))
    or ($c | test("\\A([A-Za-z0-9-]+\\.){2,}[A-Za-z]{2,}\\z"))
    or ($c | test("\\A([A-Za-z0-9-]+\\.)+(com|net|org|io|dev|app|co|br|ai|cloud|info|biz|edu|gov|local|internal|corp|test|lan)\\z"; "i"))
    or test("([0-9A-Fa-f]{2}[:-]){7}[0-9A-Fa-f]{2}")
    or actnet
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
# ALY-263.6 (AC-09): the minimum of words and characters is a parameter; every text but the session label keeps 3 words and 8 characters.
def actclean($cap; $minw; $minc):
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
    | if ($r.o | length) < $minw or ($p | length) < $minc then null
      elif ($p | length) <= $cap then $p
      else ($p | explode) as $e
        | ([range(0; $cap) | select($e[.] == 32)] | last) as $i
        | (if $i != null and $i >= 8 then $e[0:$i] else $e[0:($cap - 1)] end | implode | sub(" +\\z"; "")) + "\u2026"
      end
  end;
def actphrase($cap): actclean($cap; 3; 8);
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
  | (chipline("phase"; "(?<v>stage|publish)")) as $ph
  | (chipline("checks"; "ok=(?<ok>" + n99 + ") run=(?<run>" + n99 + ")")) as $ck
  | (chipline("severity_counts"; "critical=(?<critical>" + n99 + ") high=(?<high>" + n99 + ") medium=(?<medium>" + n99 + ") low=(?<low>" + n99 + ") info=(?<info>" + n99 + ")")) as $sv
  | {}
  + (if $txt == "1" and $sm != null then ($sm | actphrase(actcap)) as $c | (if $c != null then {summary: $c} else {} end) else {} end)
  + (if $at != null then {attempt: ($at.v | int99)} else {} end)
  + (if $nx != null then ($nx.v | ascii_downcase | gsub("-"; "_")) as $t | (if $t | IN("reviewers","pilot_correction","mothership","watcher","done") then {next: $t} else {} end) else {} end)
  + (if $gt != null and (($gt.v == "SHIELD_CLEAR" and ($ty | test("\\A(allye:)?(bridge-)?shield\\z"))) or ($gt.v == "WATCHER_APPROVED" and ($ty | test("\\A(allye:)?(bridge-)?watcher\\z")))) then {gate: $gt.v} else {} end)
  + (if $ph != null then {phase: $ph.v} else {} end)
  + (if $ck != null then {checks: ($ck | map_values(int99))} else {} end)
  + (if $sv != null then {findings: ($sv | map_values(int99))} else {} end);
# ALY-263.4 (AC-07): meta_desc is set only by the shell from the metadata file; cleaned like the other texts, nothing while texts are off.
def metadesc: if $txt == "1" then ((.meta_desc | if type == "string" then actphrase(actcap) else null end) as $d | if $d != null then {desc: $d} else {} end) else {} end;
# ALY-263.12 (AC-14): the code ready|approved only from a status line at column 0, once per report, whose first-match outcome is pass.
def statuscode: (chipline("status"; "(?<v>ready|approved)")) as $sc | if $sc != null and (stline | IN("ready","approved")) and stline == $sc.v then $sc.v else null end;
def substop: outcome as $r | (statuscode // $r.c) as $cd | (tkline // null) as $t
  | {type: "sub_stop", sub: (subof + {outcome: $r.o} + (if ($t | keyok) then {task: $t} else {} end) + newfields(subof.type) + metadesc)}
    + (if $cd != null then {code: $cd} else {} end);
def withact($a): if $a != null then . + {activity: $a} else . end;
# ALY-263.3, ALY-263.9 (AC-05, AC-06, AC-13, D-08, D-12): the one phrase builder of a subagent tool call (slice .13 moves the main session
# to it): (a) the description path (actof, free text: the cleaner keeps its 3-word minimum), else (b) a CONSTANT template of the
# D-08 table with at most one allowlisted slot (one basename or one Allye key). Nothing else of the tool input is ever emitted;
# templates skip the 3-word minimum. The table, by tool:
#   Read -> "Read <basename>" | "Read a file"; Edit, MultiEdit, NotebookEdit -> "Edit <basename>" | "Edit a file"; Write -> "Write <basename>" | "Edit a file"
#     (basename = last component of file_path / notebook_path, accepted by deftbase: shape, a letter, the denylist and the actdrop drops)
#   Grep -> "Search the code"; Glob -> "Find files"
#   Skill -> "Load the <role> skill" only for the 12 crew roles (allye:bridge-<role> or bridge-<role>); else no phrase
#   Allye MCP (server allye / *_allye) by suffix + tool_input.action: __tasks task_start|task_submit|task_complete -> "Start|Submit|Complete task KEY";
#     __specs spec_get|spec_context -> "Read spec KEY"; __kb kb_read|kb_search|kb_tree -> "Read a KB page", kb_update|kb_section|kb_create -> "Update a KB page";
#     KEY must match keyok, else the keyless form ("Start a task", "Read a spec"); every other MCP and unknown tool: no phrase
#   Bash without a description: leading VAR=value words are dropped UNREAD, then by argv0 (basename of the first word) and only a fixed word:
#     vitest -> "Run vitest"; jest -> "Run jest"; eslint | lint -> "Lint"; tsc | typecheck -> "Typecheck" (tsc -b|--build -> "Build"); build -> "Build";
#     git diff -> "Read the diff"; git status -> "Check git status"; make build -> "Build"; node --test* -> "Run tests";
#     npm|pnpm|yarn|bun [run] <script> and npx|bunx|pnpx <tool>: test -> "Run tests", lint, typecheck, build, vitest, jest, eslint, tsc as above;
#     bun test -> "Run tests"; anything else (also any command holding a secret) -> "Run a command"
def namedeny: ascii_downcase | test("\\A\\.env|credential|secret|token|passw|private|\\.pem\\z|\\.key\\z|id_(rsa|ed25519|ecdsa)|\\.p12\\z|\\.pfx\\z|kubeconfig|netrc|npmrc|pairing|hook-|service-account|keystore|\\.tfstate|\\.kdbx");
def deftbase: if type == "string" and test("\\A[A-Za-z0-9._-]{1,60}\\z") and test("[A-Za-z]") and (test("\\A\\.+\\z") | not) and (namedeny | not) and (namedrop | not) then . else null end;
def pathbase: if type == "string" then (split("/") | last) | deftbase else null end;
def filetpl($verb; $fallback; $f): ((.tool_input | objects | .[$f]) | pathbase) as $b | if $b != null then $verb + " " + $b else $fallback end;
def crewroles: ["armorer","architect","copilot","dispatcher","medic","navigator","optimizer","pilot","recon","shield","strategist","watcher"];
def skilltpl: ((.tool_input | objects | (.skill // .name)) | if type == "string" then (capture("\\A(allye:)?bridge-(?<r>[a-z]+)\\z")? // null) | (objects | .r) else null end) as $r
  | if $r != null and ($r | IN(crewroles[])) then "Load the " + $r + " skill" else null end;
def keyslot($f): ((.tool_input | objects | .[$f]) | if type == "string" and keyok then . else null end);
def mcptpl:
  if allyesrv | not then null else
    (.tool_name | split("__") | last) as $sfx
    | ((.tool_input | objects | .action) // "") as $a
    | if ($a | type) != "string" then null
      elif $sfx == "tasks" and ($a | IN("task_start","task_submit","task_complete")) then
        ({task_start: "Start", task_submit: "Submit", task_complete: "Complete"}[$a]) as $v | (keyslot("task")) as $k | if $k != null then $v + " task " + $k else $v + " a task" end
      elif $sfx == "specs" and ($a | IN("spec_get","spec_context")) then (keyslot("spec")) as $k | if $k != null then "Read spec " + $k else "Read a spec" end
      elif $sfx == "kb" and ($a | IN("kb_read","kb_search","kb_tree")) then "Read a KB page"
      elif $sfx == "kb" and ($a | IN("kb_update","kb_section","kb_create")) then "Update a KB page"
      else null end
  end;
def bscript($s): if $s == "test" then "Run tests" elif $s == "lint" then "Lint" elif $s == "typecheck" then "Typecheck" elif $s == "build" then "Build"
  elif $s == "vitest" then "Run vitest" elif $s == "jest" then "Run jest" elif $s == "eslint" then "Lint" elif $s == "tsc" then "Typecheck" else null end;
def dropvars: if length > 0 and (.[0] | test("\\A[A-Za-z_][A-Za-z0-9_]*=")) then (.[1:] | dropvars) else . end;
def bwcls:
  (.[0] // "" | sub("\\A.*/"; "")) as $a | (.[1] // "") as $b
  | if $a == "vitest" then "Run vitest" elif $a == "jest" then "Run jest" elif $a == "eslint" or $a == "lint" then "Lint"
    elif $a == "tsc" then (if (.[1:] | any(. == "-b" or . == "--build")) then "Build" else "Typecheck" end)
    elif $a == "typecheck" then "Typecheck" elif $a == "build" then "Build"
    elif $a == "git" then (if $b == "diff" then "Read the diff" elif $b == "status" then "Check git status" else null end)
    elif $a == "make" then (if $b == "build" then "Build" else null end)
    elif $a == "node" then (if $b | startswith("--test") then "Run tests" else null end)
    elif $a | IN("npm","pnpm","yarn","bun") then bscript(if $b == "run" then (.[2] // "") else $b end)
    elif $a | IN("npx","bunx","pnpx") then (.[1:] | bwcls)
    else null end;
def bashtpl: ((.tool_input | objects | .command) | if type == "string" then .[0:4096] | [splits("[ \t\r\n]+") | select(length > 0)] | dropvars | bwcls else null end) // "Run a command";
def tooltpl:
  if (.tool_name | type) != "string" then null
  elif .tool_name == "Read" then filetpl("Read"; "Read a file"; "file_path")
  elif .tool_name | IN("Edit","MultiEdit") then filetpl("Edit"; "Edit a file"; "file_path")
  elif .tool_name == "Write" then filetpl("Write"; "Edit a file"; "file_path")
  elif .tool_name == "NotebookEdit" then filetpl("Edit"; "Edit a file"; "notebook_path")
  elif .tool_name == "Grep" then "Search the code"
  elif .tool_name == "Glob" then "Find files"
  elif .tool_name == "Skill" then skilltpl
  elif .tool_name == "Bash" then bashtpl
  elif .tool_name | startswith("mcp__") then mcptpl
  else null end;
def toolphrase: if $txt != "1" then null else ([actof // tooltpl] | .[0]) end;
# ALY-269.2 (AC-02, D-01): `tu`, the hook call id, only when it passes idok (omitted otherwise, never null); only on tool and sub_tool events.
def tuf: if (.tool_use_id | idok) then {tu: .tool_use_id} else {} end;
def toolev:
  redtool as $t
  | if (.agent_id // null) != null then
    (subof) as $s | if $s != null and $t != null then toolphrase as $a | [({type: "sub_tool", tool: $t, sub: $s} + tuf) | withact($a)] else trig end
  elif $t != null then toolphrase as $m | [({type: "tool", tool: $t} + tuf) | withact($m)]
  else trig end;
# ALY-269.2 (AC-02, D-01, D-13): the end of a call, from PostToolUse (ok true) and PostToolUseFailure (ok false, never read from the response).
# The trigger stays first. hk is an internal marker that bash replaces by `h` (the sha256 of the canonical input) or removes; a subagent whose
# id fails its pattern sends the trigger alone, like a tool event does.
def cmdend($ok):
  [{type: "trig"}] + (
    if (.agent_id // null) != null then (subof) as $s | if $s != null then [{type: "cmd_end", ok: $ok, sub: $s} + tuf + {hk: true}] else [] end
    else [{type: "cmd_end", ok: $ok} + tuf + {hk: true}] end);
def failcode: .error as $x | if ($x | type) == "string" and (["rate_limit","authentication_failed","billing_error","invalid_request","server_error","max_output_tokens"] | index($x)) != null then "cli_error_" + $x else "cli_error_unknown" end;
def endcode: .reason as $x | if ($x | type) == "string" and (["clear","resume","logout","prompt_input_exit"] | index($x)) != null then "end_" + $x else "end_other" end;
def evs:
  .hook_event_name as $e
  | if   $e == "SessionStart"        then (if (.source | IN("startup","resume","clear","compact","fork")) then st("started") else [] end)
    elif $e == "UserPromptSubmit"    then st("working")
    elif $e == "UserPromptExpansion" then []
    elif $e == "PreToolUse"          then (if .tool_name == "AskUserQuestion" then stc("waiting_input"; "asked_question") else toolev end)
    elif $e == "PostToolUse"         then cmdend(true)    # D-01: no tool event from Post; the BR-14 trigger and the command end (ALY-269.2)
    elif $e == "PostToolUseFailure"  then cmdend(false)
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
    | if ($t | length) > 0 and ($t[0] | IN(modes[])) then {source: "skill", role: "bridge", mode: $t[0]} + kv($t[1] // null) | if has("spec") then . + {touch: true} else . end else null end
  else null end;
# ALY-217.4 (BR-08, D-03, D-22): only the claim-like writes task_start and task_submit (exact, lowercase) bind.
# ALY-263.5 (AC-08, D-15): spec_context/spec_get with a spec key is a touch candidate; the internal `touch` marker is cut off in bash and never leaves.
def mcpb:
  ((.tool_input | objects) // {}) as $i
  | if ($i.action | IN("spec_context","spec_get")) then
      (if ($i.spec | type) == "string" and ($i.spec | test("\\A[A-Z][A-Z0-9]{1,9}-[0-9]+\\z")) then {source: "mcp", spec: $i.spec, touch: true} else null end)
    elif ($i.action | IN("task_start","task_submit") | not) then null else
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
# AC-03, ALY-263.10 (AC-10, D-07): the task key of a start or of a first tool is taken from the CLEANED description (a key inside a token
# the cleaner dropped is therefore never sent). tkfull: every full KEY-N.M (project [A-Z][A-Z0-9]{1,9}, N 1-4 digits, M 1-3 digits, not glued
# to a word, `-`, `_` or `.` before it nor to a letter, digit or `.digit` after it); tkbare: every bare N.M (same borders, and a `-` or `/`
# before it is a border too, so `aly-263.3` and the number inside a full key give nothing). A full key wins over bare ones; exactly one
# distinct candidate is taken, two distinct ones are ambiguous (nothing). $pfx is the one project prefix of the bindings ("" = none or
# several projects): a full key of another project than a single bound one is dropped, a bare key needs the prefix. Roles that carry no task
# key (dispatcher, recon, strategist, architect, armorer) give nothing.
def tkroleok: (. // "") | test("(\\A|[:-])(dispatcher|recon|strategist|architect|armorer)\\z") | not;
def tkfull: [match("(?<![A-Za-z0-9._-])[A-Z][A-Z0-9]{1,9}-[0-9]{1,4}\\.[0-9]{1,3}(?![A-Za-z0-9]|\\.[0-9])"; "g").string] | unique;
def tkbare: [match("(?<![A-Za-z0-9._/-])[0-9]{1,4}\\.[0-9]{1,3}(?![A-Za-z0-9]|\\.[0-9])"; "g").string] | unique;
def taskkey($pfx; $ty):
  if ($ty | tkroleok | not) then null
  else tkfull as $f
    | if ($f | length) > 0 then
        (if ($f | length) == 1 and ($pfx == "" or ($f[0] | startswith($pfx + "-"))) then $f[0] else null end)
      else tkbare as $b
        | (if ($b | length) == 1 and ($pfx | test("\\A[A-Z][A-Z0-9]{1,9}\\z")) then $pfx + "-" + $b[0] else null end)
      end
  end;
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
           | (if $a != "" then .ds[$s.id] = ({desc: $a} + ($a | taskkey($tkpfx; $s.type) | if . != null then {task: .} else {} end)) else . end)
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
# ALY-263.3 (AC-05, D-02, D-18): $acts is the content of $HASH.acts, [[sub id, last phrase]] oldest first, at most 16 agents,
# usable only when $actok is "1". actdd: a sub_tool phrase equal to the previous phrase of the SAME agent is removed (the event goes
# on); every other phrase is kept, so a batch of phrases is never collapsed. {out: the events, st: the new memory or null}.
def actseen: ($acts | try fromjson catch []) | (if type == "array" then . else [] end)
  | map(select(type == "array" and length == 2 and (.[0] | idok) and (.[1] | type == "string") and (.[1] | length) <= 140)) | .[-16:];
def actdd($e):
  if $actok != "1" then {out: $e, st: null}
  else
    reduce $e[] as $ev ({out: [], s: actseen, ch: false};
      if ($ev.type == "sub_tool" or $ev.type == "tool") and ($ev.activity | type) == "string" then
        ($ev.sub.id // "_main_") as $i | ((.s | map(select(.[0] == $i)) | .[0][1]) // null) as $p
        | if $p == $ev.activity then .out += [$ev | del(.activity)]
          else .out += [$ev] | .s = (((.s | map(select(.[0] != $i))) + [[$i, $ev.activity]]) | .[-16:]) | .ch = true end
      else .out += [$ev] end)
    | {out: .out, st: (if .ch then .s else null end)}
  end;
# ─── ALY-263.10 (AC-10, D-07, D-14): sub.task on the first sub_tool of an agent id ───
# $tkmem is the content of $HASH.tkmem, [[sub id, task key sent or "", tried 0|1]] oldest first (at most 64), usable only when $tkok is "1";
# an entry off the shape is dropped (a corrupt or old file counts as empty). $tkid is the agent id whose metadata description (the
# --rawfile $tkdesc, "" when the read failed) the shell read for this event, or "". A sub_start that carries a task records it (tried 0). The
# sub_tool of $tkid whose entry is not tried yet takes the key from the cleaned description and sends it only when it differs from the value
# already sent for that agent; the attempt is recorded either way (tried 1), so a failed read is never repeated. {out: events, st: memory or null}.
def tkmemin: ($tkmem | try fromjson catch []) | (if type == "array" then . else [] end)
  | map(select(type == "array" and length == 3 and (.[0] | idok) and (.[1] | type == "string") and (.[1] == "" or (.[1] | keyok)) and (.[2] == 0 or .[2] == 1))) | .[-64:];
def tkpass($e):
  if $tkok != "1" or $txt != "1" then {out: $e, st: null}
  else
    reduce $e[] as $ev ({out: [], m: tkmemin, ch: false};
      ($ev.sub.id // null) as $i
      | (if $i == null then null else (.m | map(select(.[0] == $i)) | .[0]) end) as $o
      | if $ev.type == "sub_start" and ($ev.sub.task // null) != null and $o == null then
          .out += [$ev] | .m = ((.m + [[$i, $ev.sub.task, 0]]) | .[-64:]) | .ch = true
        elif $ev.type == "sub_tool" and $i != null and $i == $tkid and ($o == null or $o[2] == 0) then
          (if $o != null then $o[1] else "" end) as $sent
          | (($tkdesc | actphrase(actcap)) as $d | if $d != null then ($d | taskkey($tkpfx; $ev.sub.type)) else null end) as $k
          | .out += [if $k != null and $k != $sent then $ev | .sub.task = $k else $ev end]
          | .m = (((.m | map(select(.[0] != $i))) + [[$i, (if $k != null then $k else $sent end), 1]]) | .[-64:]) | .ch = true
        else .out += [$ev] end)
    | {out: .out, st: (if .ch then .m else null end)}
  end;
# ─── ALY-263.11 (AC-12, D-05, D-19): sub.resumed and the tail close ───
# $rsm is the content of $HASH.rsm (line 1 the next-check time, ignored here; the rest the JSON), usable only when $rsok is "1"; an entry off
# the shape (an old or corrupt file) is dropped, an entry of the former five fields gets the unknown identity "", at most 64 kept, the newest
# last. The first sub_tool or sub_stop of an id whose entry is "s" or "c" (the plugin already sent its stop) carries sub.resumed: true; a
# flagged tool makes the entry "r" (open), a stop makes it "s" again with the count $hbc and the identity $hbk of the newest handback read at
# this stop, so only the first event after each stop is flagged. A real stop for an entry "c" with the same known identity is the stop the
# tail close already sent: dropped. $tcl (a --rawfile) holds the transcript reads of the shell: an entry still "r" with a known count and
# identity, whose newest identity differs from the recorded one and whose count is not lower, gets one sub_stop built by substop from the newest
# handback report (the same fields, gates and text rules as a real stop, no resumed flag), state "c" with the new count and identity; every
# other entry read only gets the time of the check ($nowms). rsdue: the earliest next check of the entries that can still be closed ("-" none).
def rsraw: ($rsm | split("\n")) | (if ((.[0] // "") | test("\\A([0-9]+|-)\\z")) then .[1:] else . end) | join("\n");
def rsmin: (rsraw | try fromjson catch []) | (if type == "array" then . else [] end)
  | map(select(type == "array" and (length == 5 or length == 6)) | (if length == 5 then . + [""] else . end)
      | select((.[0] | idok) and (.[1] | typeok) and (.[2] | type == "number" and . == floor and . >= -1 and . <= 1000000000)
        and (.[3] | IN("s","r","c")) and (.[4] | type == "number" and . == floor and . >= 0)
        and (.[5] | type == "string" and test("\\A([ih][A-Za-z0-9_-]{1,40})?\\z")))) | .[-64:];
def rsput($m; $e): (($m | map(select(.[0] != $e[0]))) + [$e]) | .[-64:];
def tclin: ($tcl | try fromjson catch []) | (if type == "array" then . else [] end)
  | map(select(type == "object" and (.id | idok) and ((.c == null) or (.c | type == "number" and . >= 0 and . <= 1000000000))
      and ((.k | type) == "string") and (.k | test("\\A([ih][A-Za-z0-9_-]{1,40})?\\z")) and ((.m | type) == "string"))) | .[:2];
def rsdue($m): [$m[] | select(.[3] == "r" and .[2] >= 0 and .[5] != "") | (if .[4] == 0 then 0 else ([.[4], $nowms] | min) + 60000 end)]
  | if length == 0 then "-" else (min | tostring) end;
def rspass($e):
  if $rsok != "1" then {out: $e, st: null}
  else
    reduce $e[] as $ev ({out: [], m: rsmin, ch: false};
      ($ev.sub.id // null) as $i
      | (if $i == null then null else (.m | map(select(.[0] == $i)) | .[0]) end) as $o
      | if $ev.type == "sub_tool" and $o != null and ($o[3] == "s" or $o[3] == "c") then
          .out += [$ev | .sub.resumed = true] | .m = rsput(.m; [$i, $o[1], $o[2], "r", $o[4], $o[5]]) | .ch = true
        elif $ev.type == "sub_stop" and $i != null then
          if $o != null and $o[3] == "c" and $hbk != "" and $hbk == $o[5] then .m = rsput(.m; [$i, $o[1], $o[2], "s", $o[4], $o[5]]) | .ch = true
          else .out += [if $o != null and $o[3] == "s" then $ev | .sub.resumed = true else $ev end]
            | .m = rsput(.m; [$i, $ev.sub.type, $hbc, "s", 0, $hbk]) | .ch = true end
        else .out += [$ev] end)
    | reduce tclin[] as $t (.;
        (.m | map(select(.[0] == $t.id)) | .[0]) as $o
        | if $o == null or $o[3] != "r" then .
          elif $t.c != null and $t.k != "" and $o[2] >= 0 and $o[5] != "" and $t.k != $o[5] and $t.c >= $o[2] then
            .out += [({agent_id: $t.id, agent_type: $o[1], last_assistant_message: $t.m} | substop)]
            | .m = rsput(.m; [$t.id, $o[1], $t.c, "c", $nowms, $t.k]) | .ch = true
          else .m = rsput(.m; [$t.id, $o[1], $o[2], "r", $nowms, $o[5]]) | .ch = true end)
    | {out: .out, st: (if .ch then .m else null end)}
  end;
# ─── ALY-263.6 (AC-09, D-04, D-17): the session label ───
# $lblraw (a --rawfile, never argv: it holds the title) is read by the shell outside the lock: {t: last custom-title string or null, a: last ai-title string or null, c: the basename of
# the working directory (a real directory) or null, st: true at a SessionStart}; it is the JSON null when no check is due or texts are off.
# Sources, first one that survives the cleaner: env ALLYE_SESSION_LABEL (explicit), customTitle (explicit), aiTitle (ai); only the
# custom-title key can make an explicit label. The cleaner is actclean with 60 characters and no minimum (a title can be one word).
# cwd (the basename): exactly one path component through the D-08 basename rules (shape, denylist, the long/hex/secret drops of actdrop;
# all-dot names are not names). The API requires the label text, so a basename is never sent alone: no label text, nothing is sent.
def lblbase: if type == "string" and test("\\A[A-Za-z0-9._-]{1,60}\\z") and (test("\\A\\.+\\z") | not) and (namedeny | not) and (actdrop | not) then . else null end;
def lblnorm: actclean(60; 1; 2);
def lblc:
  if $txt != "1" or ($lblraw | try fromjson catch null | type) != "object" then null else
    ($lblraw | fromjson) as $lbl
    | ($lbl.c | lblbase) as $b
    | ([(($ENV.ALLYE_SESSION_LABEL | lblnorm) | select(. != null) | {text: ., source: "explicit"}),
        (($lbl.t | lblnorm) | select(. != null) | {text: ., source: "explicit"}),
        (($lbl.a | lblnorm) | select(. != null) | {text: ., source: "ai"})] | .[0]) as $l
    | if $l != null then $l + (if $b != null then {cwd: $b} else {} end) else null end
  end;
# BR-14: the first tool/subagent-start event after waiting_input is preceded by a `state working`.
. as $in
| evs as $e0
| (try subsc($e0) catch {out: $e0, seen: null, new: []}) as $sb
| (try stashc($sb.new) catch {ds: {}, st: null}) as $sc
| [$sb.out[] | if .type == "sub_start" then .sub += ($sc.ds[.sub.id] // {}) else . end] as $all0
| (try actdd($all0) catch {out: $all0, st: null}) as $ad
| (try tkpass($ad.out) catch {out: $ad.out, st: null}) as $tk
| (try rspass($tk.out) catch {out: $tk.out, st: null}) as $rs
| $rs.out as $all
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
  (if $ad.st == null then "-" else ($ad.st | tojson) end),
  (try ($in | lblc) catch null | if . == null then "-" else tojson end),
  (if $tk.st == null then "-" else ($tk.st | tojson) end),
  (if $rs.st == null then "-" else ($rs.st | tojson) end),
  (if $rs.st == null then "-" else rsdue($rs.st) end),
  ($r.out[] | . + {at: $at} | tojson),
  "."'

# ALY-217.6 (D-25, D-24 b): activity phrases unless $LIVE_DIR/activity-off exists (any kind of entry: fail safe); the
# Agent/Task stash $HASH.agents is read once (bounded, private file only) and passed to the jq program.
# ALY-258.3 (BR-03): texts are also off while $LIVE_DIR/detailed-off exists (the cached `detailed: false` of the ingest ack; any entry).
ACT=1
if texts_off; then ACT=0; fi
# The stash goes to jq through --rawfile (never argv, Shield SHD-02): the file itself when it is private and at most
# 16384 bytes (one find), else /dev/null (an oversized private stash is then simply rewritten).
AGENTSF="$LIVE_DIR/$HASH.agents"; STASHSRC=/dev/null; AGOK=0
# ALY-258.3 (BR-03, AC-08): with texts off the Agent stash is deleted (a symlink as the link only, a regular file only when it is ours),
# under the state lock the hook holds here; nothing is read from it and nothing is written back.
if [ "$ACT" = 0 ] && { [ -L "$AGENTSF" ] || { [ -f "$AGENTSF" ] && [ -n "$(find "$AGENTSF" -prune -type f -user "$UID_NOW" -print 2>/dev/null)" ]; }; }; then rm -f "$AGENTSF" 2>/dev/null; fi
if [ "$ACT" = 1 ]; then
  if [ ! -e "$AGENTSF" ] && [ ! -L "$AGENTSF" ]; then AGOK=1
  elif pfcap "$AGENTSF"; then AGOK=1; STASHSRC="$AGENTSF"
  elif pfc "$AGENTSF"; then AGOK=1; fi
fi
# ALY-217.7 (D-26): the seen sub ids $HASH.subs, read under the state lock like the stash: through --rawfile, the file
# itself when it is private and at most 8192 bytes. Absent: an empty set. An oversized private file is rewritten. Any
# other entry (symlink, foreign owner or mode): the set is neither used nor written (SUBOK=0, no synthetic sub_start).
# ALY-263.3 (D-18, BR-03): the last phrase of each subagent, $HASH.acts, read like the stash (private file, at most 16384 bytes: 16 multibyte phrases).
# It holds phrases, so it exists only while texts are on: with texts off it is deleted (a symlink as the link only) and never written.
ACTSF="$LIVE_DIR/$HASH.acts"; ACTSRC=/dev/null; ACTOK=0
if [ "$ACT" = 0 ]; then
  if [ -L "$ACTSF" ] || { [ -f "$ACTSF" ] && [ -n "$(find "$ACTSF" -prune -type f -user "$UID_NOW" -print 2>/dev/null)" ]; }; then rm -f "$ACTSF" 2>/dev/null; fi
elif [ ! -e "$ACTSF" ] && [ ! -L "$ACTSF" ]; then ACTOK=1
elif pfcap "$ACTSF"; then ACTOK=1; ACTSRC="$ACTSF"
elif pfc "$ACTSF"; then ACTOK=1; fi
# ALY-263.10: the task memory $HASH.tkmem (ids, task keys, 0/1; no text), read like the phrase memory: the private file itself when at most
# 8192 bytes, absent = empty, any other entry (symlink, foreign owner or mode) = neither used nor written. With texts off it is not used.
TKF="$LIVE_DIR/$HASH.tkmem"; TKSRC=/dev/null; TKOK=0
if [ "$ACT" = 1 ]; then
  if [ ! -e "$TKF" ] && [ ! -L "$TKF" ]; then TKOK=1
  elif pfcap "$TKF"; then TKOK=1; TKSRC="$TKF"
  elif pfc "$TKF"; then TKOK=1; fi
fi
# ALY-263.11: the resume state $HASH.rsm (ids, types, counts, markers, times; no text, so it is kept with texts off too), read like the task
# memory: the private file itself when at most 16384 bytes, absent = empty, any other entry (symlink, foreign owner or mode) = neither used nor written.
RSMF="$LIVE_DIR/$HASH.rsm"; RSMSRC=/dev/null; RSOK=0
if [ ! -e "$RSMF" ] && [ ! -L "$RSMF" ]; then RSOK=1
elif pfcap "$RSMF"; then RSOK=1; RSMSRC="$RSMF"
elif pfc "$RSMF"; then RSOK=1; fi
# ALY-263.6 (BR-03): the label state holds the label text, so like the phrases it exists only while texts are on.
LBLF="$LIVE_DIR/$HASH.label"
if [ "$ACT" = 0 ] && { [ -L "$LBLF" ] || { [ -f "$LBLF" ] && [ -n "$(find "$LBLF" -prune -type f -user "$UID_NOW" -print 2>/dev/null)" ]; }; }; then rm -f "$LBLF" 2>/dev/null; fi
SUBSF="$LIVE_DIR/$HASH.subs"; SUBSRC=/dev/null; SUBOK=0
if [ ! -e "$SUBSF" ] && [ ! -L "$SUBSF" ]; then SUBOK=1
elif pfcap "$SUBSF"; then SUBOK=1; SUBSRC="$SUBSF"
elif pfc "$SUBSF"; then SUBOK=1; fi
MS=$(now_ms)
[[ "$MS" =~ ^[1-9][0-9]{0,15}$ ]] || exit 0
RESULT=$(printf '%s' "$INPUT" | jq -r --arg last "$LAST" --arg at "$AT" --arg txt "$ACT" --rawfile stash "$STASHSRC" --arg subok "$SUBOK" --rawfile subs "$SUBSRC" --arg actok "$ACTOK" --rawfile acts "$ACTSRC" --rawfile lblraw <(printf '%s' "$LBLIN") --arg tkok "$TKOK" --rawfile tkmem "$TKSRC" --arg tkid "$TKID" --rawfile tkdesc <(printf '%s' "$TKDESC") --arg tkpfx "$TKPFX" --arg rsok "$RSOK" --rawfile rsm "$RSMSRC" --argjson hbc "$HBC" --arg hbk "$HBK" --rawfile tcl <(printf '%s' "$TCL") --argjson nowms "$MS" "$JQ_PROG" 2>/dev/null) || exit 0
# Output: new last state, bind candidate (or -), cwd for the branch source (or -), gates path and cwd (or -, -),
# watcher trigger (start = a SessionStart of a known source, prompt = UserPromptSubmit, or -), the new Agent/Task
# stash (or - to leave it), the new seen-set as space-separated ids (or - to leave it), the new last-phrase memory (or -),
# the label candidate (or -), the new task memory (or -), events, "." terminator.
NEWLAST="${RESULT%%$'\n'*}"; REST="${RESULT#*$'\n'}"
CAND="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
CWD="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
GFP="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
GCWD="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
WEV="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
AGT="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
SUBS="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
ACTS="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
LBLC="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
TKMC="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
RSMC="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
RSDC="${REST%%$'\n'*}"; REST="${REST#*$'\n'}"
case "$REST" in .) EVENTS="" ;; *$'\n'.) EVENTS="${REST%$'\n'.}" ;; *) exit 0 ;; esac
case "$NEWLAST" in ""|started|working|waiting_input|idle|error|ended) ;; *) exit 0 ;; esac
[ -n "$CAND" ] && [ -n "$CWD" ] && [ -n "$GFP" ] && [ -n "$GCWD" ] || exit 0
case "$WEV" in start|prompt|-) ;; *) exit 0 ;; esac
case "$AGT" in -|'['*']') ;; *) exit 0 ;; esac
[ "$SUBS" = - ] || [[ "$SUBS" =~ ^[A-Za-z0-9_-]{1,64}( [A-Za-z0-9_-]{1,64}){0,63}$ ]] || exit 0
case "$ACTS" in -|'['*']') ;; *) exit 0 ;; esac
case "$LBLC" in -|'{'*'}') ;; *) exit 0 ;; esac
case "$TKMC" in -|'['*']') ;; *) exit 0 ;; esac
case "$RSMC" in -|'['*']') ;; *) exit 0 ;; esac
[[ "$RSDC" =~ ^(-|[0-9]{1,16})$ ]] || exit 0

# ─── ALY-269.2 (AC-02, AC-05, D-08, D-13): `h` of a cmd_end. Only PostToolUse and PostToolUseFailure events carry the marker, so every other
# event pays nothing. h = sha256 hex of the canonical JSON (`jq -S -c`, streamed: the input never goes through argv) of [tool_name, tool_input],
# or of tool_input.questions alone for AskUserQuestion (PostToolUse adds answers/annotations to tool_input). A missing hash tool, a jq failure or
# an input of another shape leaves `h` out; the marker is always removed.
case "$EVENTS" in
  *',"hk":true'*)
    CJ=$(printf '%s' "$INPUT" | jq -S -c 'if .tool_name == "AskUserQuestion" then (.tool_input | objects | .questions | arrays) // empty
      elif (.tool_name | type) == "string" and (.tool_input | type) == "object" then [.tool_name, .tool_input] else empty end' 2>/dev/null) || CJ=""
    CH=""
    if [ -n "$CJ" ]; then CH=$(printf '%s\n' "$CJ" | sha_hex 2>/dev/null) || CH=""; fi
    CJ=""
    if [[ "$CH" =~ ^[0-9a-f]{64}$ ]]; then EVENTS="${EVENTS/,\"hk\":true/,\"h\":\"$CH\"}"; else EVENTS="${EVENTS/,\"hk\":true/}"; fi ;;
esac

# ─── ALY-203.3: binding (BR-08). Strength: skill 4 > mcp 3 > env 2 > branch 1. ───
# ALY-263.5 (AC-08, D-15): a candidate with the internal touch marker (spec_context/spec_get or a launch with a spec key) is
# also sent when weaker than the held binding, once per key per minute; the marker never leaves and the held binding stays.
TOUCH=0; TOUCHSUF=',"touch":true}'
case "$CAND" in *"$TOUCHSUF") TOUCH=1; CAND="${CAND%"$TOUCHSUF"}}" ;; esac
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

BINDLINE=""; TOUCHONLY=0; TOUCHNEW=""
if [ "$CAND" != "-" ]; then
  case "$CAND" in
    '{"source":"skill"'*) NR=4 ;; '{"source":"mcp"'*) NR=3 ;; '{"source":"env"'*) NR=2 ;; '{"source":"branch"'*) NR=1 ;; *) NR=0 ;;
  esac
  SEND=0
  if [ "$NR" -gt 0 ]; then
    if [ -z "$BRANK" ] || [ "$NR" -gt "$BRANK" ]; then SEND=1
    elif [ "$NR" -eq "$BRANK" ] && [ "$NR|$CAND" != "$BSTORED" ]; then SEND=1; fi
  fi
  if [ "$TOUCH" = 1 ] && [ "$NR" -gt 0 ] && [[ "$CAND" =~ \"spec\":\"([A-Z][A-Z0-9]{1,9}-[0-9]+)\" ]]; then
    TKEY="${BASH_REMATCH[1]}"; TOUCHF="$LIVE_DIR/$HASH.touch"; TOLD=""
    if private_file_ok "$TOUCHF"; then
      if [ -f "$TOUCHF" ]; then
        TOLD=$(head -c 1200 "$TOUCHF" 2>/dev/null) || TOLD=""
        # a corrupt file (a line off the shape, more than 16 lines) counts as empty
        if printf '%s\n' "$TOLD" | LC_ALL=C grep -qvE '^([A-Z][A-Z0-9]{1,9}-[0-9]+ [0-9]{13})?$' || [ "$(printf '%s\n' "$TOLD" | wc -l | tr -d ' ')" -gt 16 ]; then TOLD=""; fi
      fi
      TSEEN=$(printf '%s\n' "$TOLD" | while IFS=' ' read -r k m; do [ "$k" = "$TKEY" ] && printf '%s' "$m"; done)
      TNEW=$(printf '%s\n' "$TOLD" | grep -v "^$TKEY " | grep -E '^[A-Z]' | tail -n 15)
      TOUCHNEW="${TNEW:+$TNEW$'\n'}$TKEY $MS"
      if [ "$SEND" = 0 ] && { [ -z "$TSEEN" ] || [ "$(( MS - TSEEN ))" -ge 60000 ] || [ "$(( MS - TSEEN ))" -lt 0 ]; }; then SEND=1; TOUCHONLY=1; fi
    fi
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
GATELINE=""; GNEW=""; PRNEW=""; PLAST=""; PRSEND=""; GEFF=""; PWRITE=""
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
    # two lines out: the gates array (or -) and the pr digits (or -); nothing else of the file is printed
    GOUT=$(head -c 65536 "$GPATH" 2>/dev/null | jq -Rrs '
      ["SHIELD_CLEAR","WATCHER_APPROVED","MISSION_COMPLETE","CI_PENDING"] as $set
      | split("\n") as $ls
      | ($ls | map(select(test("\\A- Gates:"))) | .[0]) as $l
      | ($ls | map(select(test("\\A- PR: #[1-9][0-9]{0,6}[ \t\r]*\\z"))) | .[0]) as $p
      | (if $l == null then "-"
         else ([($l | sub("\\A- Gates:"; "") | split("\u00b7")[]
                  | gsub("\\A[ \t]+|[ \t\r]+\\z"; "") | split(" ") | map(select(length > 0)))
                | select(length >= 2 and .[1] != "\u2014") | .[0]]) as $on
              | [$set[] | select(. as $n | $on | index($n) != null)] | tojson
         end),
        (if $p == null then "-" else ($p | sub("\\A- PR: #"; "") | gsub("[ \t\r]"; "")) end)' 2>/dev/null) || GOUT=""
    GNEW=${GOUT%%$'\n'*}; PRNEW=""; case "$GOUT" in *$'\n'*) PRNEW=${GOUT#*$'\n'} ;; esac
    case "$GNEW" in "["*"]") ;; *) GNEW="" ;; esac
    [[ "$PRNEW" =~ ^[1-9][0-9]{0,6}$ ]] || PRNEW=""
  fi
  GPATH=""
fi
if [ -n "$GNEW" ] || [ -n "$PRNEW" ]; then
  GLAST="[]"
  if [ -f "$GATEF" ] && [ ! -L "$GATEF" ]; then
    if private_file_ok "$GATEF"; then
      # line 1: the set last sent; optional line 2: the pr last sent (ALY-263.15). An old file holds the array alone.
      GLAST=""; PLAST=""
      { IFS= read -r GLAST; IFS= read -r PLAST; } <"$GATEF" 2>/dev/null || true   # no head: the 64 KB probe counts head calls
      case "$GLAST" in "["*"]") ;; *) GLAST="[]" ;; esac
      [[ "$PLAST" =~ ^[1-9][0-9]{0,6}$ ]] || PLAST=""
    else GNEW=""; PRNEW=""; fi
  elif ! private_file_ok "$GATEF"; then GNEW=""; PRNEW=""; fi
  GSEND=0
  if [ -n "$GNEW" ] && [ "$GNEW" != "$GLAST" ]; then GSEND=1; fi
  if [ -n "$PRNEW" ] && [ "$PRNEW" != "$PLAST" ]; then GSEND=1; PRSEND="$PRNEW"; fi
  if [ "$GSEND" = 1 ]; then
    GEFF="${GNEW:-$GLAST}"; PWRITE="${PRNEW:-$PLAST}"
    GATELINE=$(jq -nc --argjson g "$GEFF" --arg at "$AT" --arg pr "$PRSEND" \
      '{type: "gates", gates: $g, at: $at} + (if $pr != "" then {pr: ($pr | tonumber)} else {} end)' 2>/dev/null) || GATELINE=""
  fi
fi
if [ -n "$GATELINE" ]; then
  if [ -n "$EVENTS" ]; then EVENTS="$EVENTS"$'\n'"$GATELINE"; else EVENTS="$GATELINE"; fi
fi

# ─── ALY-263.6: the label event (AC-09). The candidate of the jq program is sent only when it differs from the last value sent
# ($HASH.label, judged again here under the lock); a check that sends nothing still records its time (at most one check a minute).
# The file holds display text, so it is written only while texts are on (BR-03) and only over a private name.
label_state_write() {  # label_state_write VALUE-JSON: "<ms> <json>", temp 0600 + mv; best effort
  local tmp
  [[ "$MS" =~ ^[0-9]{13}$ ]] || return 0
  tmp=$(mktemp "$LIVE_DIR/.label.XXXXXX" 2>/dev/null) || return 0; TMPF="$tmp"
  printf '%s %s' "$MS" "$1" >"$tmp" 2>/dev/null && mv -f "$tmp" "$LBLF" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
LBLLINE=""; LBLWRITE=""
if [ "$LBLDUE" = 1 ] && [ "$ACT" = 1 ] && pfc "$LBLF"; then
  label_state_read
  [ -n "$LBLSTORED" ] || LBLSTORED='{}'
  LBLWRITE=now
  if [ "$LBLC" != "-" ] && [ "$LBLC" != "$LBLSTORED" ]; then
    LBLLINE=$(printf '%s' "$LBLC" | jq -c --arg at "$AT" '{type: "label", label: ., at: $at}' 2>/dev/null) || LBLLINE=""
    if [ -n "$LBLLINE" ]; then
      if [ -n "$EVENTS" ]; then EVENTS="$EVENTS"$'\n'"$LBLLINE"; else EVENTS="$LBLLINE"; fi
      LBLSTORED="$LBLC"; LBLWRITE=after
    fi
  fi
fi

# The resume state (ALY-263.11): one atomic write (temp 0600 + mv) when an entry changed. Also written when the event sends nothing, so
# the time of a tail check is kept (the once-a-minute bound); the same condition as the label time: a usable spool and state.
rsm_write() {
  [ "$RSMC" != - ] && [ "$RSOK" = 1 ] || return 0
  local t
  t=$(mktemp "$LIVE_DIR/.rsm.XXXXXX" 2>/dev/null) || return 0; TMPF="$t"
  printf '%s\n%s' "$RSDC" "$RSMC" >"$t" 2>/dev/null && mv -f "$t" "$RSMF" 2>/dev/null || rm -f "$t" 2>/dev/null
}
# nothing to send: the time of the check is still recorded, but only where the spool and the state are usable (as for any claim)
if [ -z "$EVENTS" ]; then
  if [ "$LBLWRITE" = now ] && pfc "$SPOOL" && pfc "$STATEF"; then label_state_write "$LBLSTORED"; fi
  if [ "$RSMC" != - ] && pfc "$SPOOL" && pfc "$STATEF"; then rsm_write; fi
  exit 0
fi
pfc "$SPOOL" || exit 0
pfc "$STATEF" || exit 0

# A session whose credential changed since its last event (a re-pair after a 401, a revoke or an expiry) opens with
# `state started`: the server reopens a run that was ended or revoked only on that state.
credfp
CREDOLD=""; CREDNEW=0
if [ -f "$CREDF" ] && [ ! -L "$CREDF" ] && pfc "$CREDF"; then { IFS= read -r CREDOLD <"$CREDF"; } 2>/dev/null; fi
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
if [ -f "$SEQF" ] && [ ! -L "$SEQF" ] && pfc "$SEQF"; then
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
if [ -n "$BINDLINE" ] && [ "$TOUCHONLY" != 1 ]; then
  TMP=$(mktemp "$LIVE_DIR/.bind.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s|%s' "$NR" "$CAND" >"$TMP" 2>/dev/null && mv -f "$TMP" "$BINDF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi
if [ -n "$BINDLINE" ] && [ -n "$TOUCHNEW" ]; then
  TMP=$(mktemp "$LIVE_DIR/.touch.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s\n' "$TOUCHNEW" >"$TMP" 2>/dev/null && mv -f "$TMP" "$TOUCHF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi
if [ "$LBLWRITE" = after ] || [ "$LBLWRITE" = now ]; then label_state_write "$LBLSTORED"; fi
if [ -n "$GATELINE" ]; then
  TMP=$(mktemp "$LIVE_DIR/.gates.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  { printf '%s' "$GEFF"; if [ -n "$PWRITE" ]; then printf '\n%s' "$PWRITE"; fi; } >"$TMP" 2>/dev/null && mv -f "$TMP" "$GATEF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
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

# The last phrase per subagent (ALY-263.3): one atomic write (temp 0600 + mv) when a phrase was kept; never with texts off.
if [ "$ACTS" != - ] && [ "$ACTOK" = 1 ] && [ "$ACT" = 1 ]; then
  TMP=$(mktemp "$LIVE_DIR/.acts.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s' "$ACTS" >"$TMP" 2>/dev/null && mv -f "$TMP" "$ACTSF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi

# The task memory (ALY-263.10): one atomic write (temp 0600 + mv) when an entry changed; never with texts off.
if [ "$TKMC" != - ] && [ "$TKOK" = 1 ] && [ "$ACT" = 1 ]; then
  TMP=$(mktemp "$LIVE_DIR/.tkmem.XXXXXX" 2>/dev/null) || exit 0; TMPF="$TMP"
  printf '%s' "$TKMC" >"$TMP" 2>/dev/null && mv -f "$TMP" "$TKF" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi

rsm_write

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
