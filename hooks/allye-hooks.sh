#!/bin/bash
# Pairs this Claude Code install with Allye so a SessionStart hook can fetch the user's pinned
# preferences. Used by /allye:hooks (commands/hooks.md):
#   allye-hooks.sh begin   <dataDir>                        verifier -> pairing file, prints the challenge
#   allye-hooks.sh finish  <dataDir> <challenge> <code>     exchanges code + verifier for the credential
#   allye-hooks.sh unpair  <dataDir>                        deletes the local credential and pairing files
#   allye-hooks.sh live    off|on|status <dataDir>          Live reporter switch (ALY-203): off ends the open runs, sets
#                                                           the flag and deletes the spools; on clears the flag; status
#                                                           prints state, spool size and last result (no network call)
#   allye-hooks.sh live    activity off|on|status <dataDir> activity phrases switch (ALY-217.6): off sets the flag
#                                                           live/activity-off, on clears it, status prints it
#
# Runtime: bash 3.2+, curl, jq and sha256sum or shasum. No node, openssl, python or GNU stat.
# The verifier and the token never reach argv, the environment or any output: they travel only
# through files, pipes and curl's stdin config. Response bodies are never printed.
set -u
umask 077
LC_ALL=C   # a plain shell variable (not exported): bash character ranges match bytes only

CRED_NAME="hook-credential.json"
DEFAULT_API_URL="https://api.allye.app"
ORIGINAL_COUNT=$#

TMPS=()
cleanup() { [ "${#TMPS[@]}" -eq 0 ] || rm -f "${TMPS[@]}" 2>/dev/null; return 0; }
trap cleanup EXIT
trap 'exit 130' INT TERM

fail() { printf '%s\n' "$*" >&2; exit 1; }
usage() {
  printf '%s\n' "Usage: allye-hooks.sh begin <dataDir> | finish <dataDir> <challenge> <pairingCode> | unpair <dataDir> | live off|on|status <dataDir> | live activity off|on|status <dataDir>" >&2
  exit 2
}

# ─── Checks ─────────────────────────────────────────────────────────────────

# The data directory is the absolute path the command passes: empty, relative or unexpanded
# (${...}) values and control characters are refused.
valid_dir_arg() {
  case "$1" in
    ''|*'${'*|*[[:cntrl:]]*) return 1 ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

UID_NOW=$(id -u)

# Safe data directory: a real directory (no symlink) owned by the user, mode 0700. A directory
# the user owns is tightened; anything else is refused. $1 = path, $2 = create|nocreate.
secure_dir() {
  local d="$1"
  if [ -L "$d" ]; then fail "The Allye data directory is a symlink; refusing to use it."; fi
  if [ ! -e "$d" ]; then
    [ "$2" = create ] || return 1
    mkdir -p "$d" || fail "Could not create the Allye data directory."
  fi
  [ -n "$(find "$d" -prune -type d -user "$UID_NOW" -print 2>/dev/null)" ] ||
    fail "The Allye data directory is not a directory you own; refusing to use it."
  chmod 700 "$d" || fail "Could not restrict the Allye data directory."
  [ -n "$(find "$d" -prune -type d -user "$UID_NOW" -perm 0700 -print 2>/dev/null)" ] ||
    fail "The Allye data directory is not private (mode 0700); refusing to use it."
}

# Regular file (no symlink) owned by the user without group or other permissions.
safe_file() {
  [ -n "$(find "$1" -prune -type f -user "$UID_NOW" ! -perm -040 ! -perm -020 ! -perm -010 \
    ! -perm -004 ! -perm -002 ! -perm -001 -print 2>/dev/null)" ]
}

# The API origin is one of a fixed list: PROD, HML, or loopback with a port (tests, local API).
# Anything else (other hosts, paths, queries, credentials, a trailing slash) is refused. Checked with
# bash patterns: no node. The value is never echoed.
valid_api_url() {
  local re_loop='^http://(localhost|127\.0\.0\.1):[0-9]{1,5}$'
  case "$1" in
    https://api.allye.app|https://api.zeta.allye.app) return 0 ;;
  esac
  [[ "$1" =~ $re_loop ]]
}
API_URL_MSG="ALLYE_API_URL must be exactly one of https://api.allye.app, https://api.zeta.allye.app, http://localhost:<port> or http://127.0.0.1:<port>; nothing was sent."

# Device name from `uname -n` up to the first dot, [A-Za-z0-9 ._-] only, at most 64 characters.
device_name() {
  local n
  n=$(uname -n 2>/dev/null) || n=""
  n="${n%%.*}"
  n="${n//[^A-Za-z0-9 ._-]/-}"
  n="${n:0:64}"
  [ -n "$n" ] || n="device"
  printf '%s' "$n"
}

# sha256 of stdin as lowercase hex; sha256sum, else shasum -a 256.
have_sha() { command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; }
sha_hex() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then out=$(sha256sum); else out=$(shasum -a 256); fi
  printf '%s' "${out%% *}"
}

# Private temporary file in the data directory, removed by the EXIT trap unless renamed.
new_tmp() {  # $1 = directory, $2 = name stem; sets NEW_TMP (no subshell: the trap must see it)
  NEW_TMP=$(mktemp "$1/.$2.XXXXXX") || { [ "${3:-}" = quiet ] && return 1; fail "Could not create a temporary file in the Allye data directory."; }
  TMPS+=("$NEW_TMP")
}

# Text from a file or the API made printable: control and format characters removed.
CLEAN_FILTER='gsub("[\\p{C}\\p{Zl}\\p{Zp}\\x{00A0}\\x{1680}\\x{2000}-\\x{200A}\\x{202F}\\x{205F}\\x{3000}]"; "") | .[0:128]'

# ─── begin ──────────────────────────────────────────────────────────────────

cmd_begin() {
  [ "$#" -eq 1 ] || usage
  local dir="$1" verifier challenge device pf tmp
  valid_api_url "${ALLYE_API_URL:-$DEFAULT_API_URL}" || fail "$API_URL_MSG"
  valid_dir_arg "$dir" || fail "The data directory must be an absolute path (got an empty, relative or unexpanded value)."
  have_sha || fail "Install coreutils (sha256sum) or perl (shasum) to pair."
  secure_dir "$dir" create

  verifier=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
  [[ "$verifier" =~ ^[0-9a-f]{64}$ ]] || fail "Could not read random bytes to start pairing."
  challenge=$(printf '%s' "$verifier" | sha_hex)
  [[ "$challenge" =~ ^[0-9a-f]{64}$ ]] || fail "Could not compute the pairing challenge."
  device=$(device_name)

  pf="$dir/pairing-${challenge:0:16}.json"
  [ ! -e "$pf" ] || fail "A pairing with this challenge already exists; run begin again."
  new_tmp "$dir" pairing; tmp="$NEW_TMP"
  # Hex and a sanitized device name only: printf builtin, so the verifier is never in argv.
  printf '{"verifier":"%s","challenge":"%s","deviceName":"%s"}\n' "$verifier" "$challenge" "$device" >"$tmp" ||
    fail "Could not write the pairing file."
  mv -f "$tmp" "$pf" || fail "Could not write the pairing file."

  printf 'challenge: %s\n' "$challenge"
  printf 'deviceName: %s\n' "$device"
  printf 'clientKind: claude-code\n'
  printf 'Next: call the Allye MCP tool hooks with action hooks_pair_start and these three values, then run finish with the challenge and the returned pairingCode.\n'
}

# ─── finish ─────────────────────────────────────────────────────────────────

# Anything wrong after a 201: the server may hold a credential this install cannot use.
bad_response() {  # $1 = pairing file, $2 = device name
  rm -f "$1"
  fail "The pairing response was not valid; revoke $2 in Settings → Devices and pair again."
}

RETRY_MSG="Could not finish pairing; run the finish step again within 5 minutes, or revoke the extra device in Settings → Devices if it appears there."

cmd_finish() {
  [ "$#" -eq 3 ] || usage
  local dir="$1" challenge="$2" code="$3" base pf body tmpcred
  local device verifier status crc errcode dataline prev="" date
  [[ "$code" =~ ^alyp_[0-9a-f]{32}$ ]] || fail "The pairing code is malformed; nothing was sent."
  [[ "$challenge" =~ ^[0-9a-f]{64}$ ]] || fail "The challenge is malformed; nothing was sent."
  valid_dir_arg "$dir" || fail "The data directory must be an absolute path (got an empty, relative or unexpanded value)."

  base="${ALLYE_API_URL:-$DEFAULT_API_URL}"
  valid_api_url "$base" || fail "$API_URL_MSG"

  command -v curl >/dev/null 2>&1 || fail "curl is required to pair."
  command -v jq >/dev/null 2>&1 || fail "jq is required to pair."
  have_sha || fail "Install coreutils (sha256sum) or perl (shasum) to pair."

  secure_dir "$dir" create
  pf="$dir/pairing-${challenge:0:16}.json"
  if ! safe_file "$pf"; then fail "No pairing in progress for this challenge. Start again with /allye:hooks pair."; fi
  jq -e --arg c "$challenge" '
    type == "object" and (.challenge == $c)
    and (.verifier | type == "string" and test("\\A[0-9a-f]{64}\\z"))
    and (.deviceName | type == "string" and test("\\A[A-Za-z0-9 ._-]{1,64}\\z"))' "$pf" >/dev/null 2>&1 ||
    fail "The pairing file is damaged. Start again with /allye:hooks pair."
  verifier=$(jq -r '.verifier' "$pf")
  [ "$(printf '%s' "$verifier" | sha_hex)" = "$challenge" ] ||
    fail "The pairing file does not match its challenge. Start again with /allye:hooks pair."
  verifier=""
  device=$(jq -r '.deviceName' "$pf")

  # Previous credential of this install, to name the device the user should revoke.
  if safe_file "$dir/$CRED_NAME"; then
    prev=$(jq -r "(.deviceName // \"\") | tostring | $CLEAN_FILTER" "$dir/$CRED_NAME" 2>/dev/null) || prev=""
  fi

  new_tmp "$dir" exchange; body="$NEW_TMP"
  dataline=$(jq -r --arg code "$code" '"data = " + ({pairingCode: $code, verifier: .verifier} | tojson | tojson)' "$pf") ||
    fail "Could not build the exchange request."

  # The request body (with the verifier) travels in a curl config on stdin, never in argv.
  status=$({
    printf 'url = "%s/api/hook-pairings/exchange"\n' "$base"
    printf 'request = "POST"\n'
    printf 'header = "Content-Type: application/json"\n'
    printf 'header = "Accept: application/json"\n'
    printf 'max-time = 10\n'
    printf 'connect-timeout = 5\n'
    printf 'max-filesize = 65536\n'
    printf '%s\n' "$dataline"
  } | curl -q --silent --show-error -K - -o "$body" -w '%{http_code}' 2>/dev/null)
  crc=$?
  dataline=""

  if [ "$crc" -ne 0 ] || ! [[ "$status" =~ ^[0-9]{3}$ ]] || [ "$status" = 000 ]; then
    fail "$RETRY_MSG"
  fi

  case "$status" in
    201)
      if jq -e '
        (.data | type == "object")
        and (.data.token | type == "string" and test("\\Aalyh_[A-Za-z0-9_-]{43}\\z"))
        and (.data.email | type == "string" and length > 0 and length <= 320)
        and (.data.tenantName | type == "string" and length > 0 and length <= 200)
        and (.data.deviceName | type == "string" and test("\\A[A-Za-z0-9 ._-]{1,64}\\z"))
        and (.data.absoluteExpiresAt | type == "string" and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T"))' \
        "$body" >/dev/null 2>&1; then
        new_tmp "$dir" credential quiet || bad_response "$pf" "$device"
        tmpcred="$NEW_TMP"
        jq --arg apiUrl "$base" "{
            token: .data.token,
            email: (.data.email | $CLEAN_FILTER),
            tenantName: (.data.tenantName | $CLEAN_FILTER),
            deviceName: .data.deviceName,
            apiUrl: \$apiUrl,
            absoluteExpiresAt: .data.absoluteExpiresAt,
            pairedAt: (now | todate)}" "$body" >"$tmpcred" 2>/dev/null || bad_response "$pf" "$device"
        mv -f "$tmpcred" "$dir/$CRED_NAME" || bad_response "$pf" "$device"
        rm -f "$pf"
        printf 'Paired %s as %s in %s; pair again before %s\n' \
          "$(jq -r '.deviceName' "$dir/$CRED_NAME")" \
          "$(jq -r '.email' "$dir/$CRED_NAME")" \
          "$(jq -r '.tenantName' "$dir/$CRED_NAME")" \
          "$(jq -r '.absoluteExpiresAt[0:10]' "$dir/$CRED_NAME")"
        if [ -n "$prev" ]; then
          printf 'This replaced the previous credential of %s; revoke that device in Settings → Devices.\n' "$prev"
        fi
        return 0
      fi
      bad_response "$pf" "$device"
      ;;
    400)
      rm -f "$pf"
      fail "The pairing code is invalid or expired; run /allye:hooks pair again."
      ;;
    401)
      errcode=$(jq -r '.error.message.code // empty' "$body" 2>/dev/null)
      case "$errcode" in
        USER_INACTIVE|MEMBERSHIP_INACTIVE|TENANT_INACTIVE)
          rm -f "$pf"
          fail "Your Allye account or organization is not active." ;;
      esac
      fail "$RETRY_MSG"
      ;;
    2??)
      bad_response "$pf" "$device"
      ;;
    *)
      fail "$RETRY_MSG"
      ;;
  esac
}

# ─── unpair ─────────────────────────────────────────────────────────────────

cmd_unpair() {
  [ "$#" -eq 1 ] || usage
  local dir="$1" device="" f found=0
  valid_dir_arg "$dir" || fail "The data directory must be an absolute path (got an empty, relative or unexpanded value)."
  if ! secure_dir "$dir" nocreate; then
    printf 'Nothing to unpair: this install has no Allye hook credential.\n'
    return 0
  fi
  if safe_file "$dir/$CRED_NAME" && command -v jq >/dev/null 2>&1; then
    device=$(jq -r "(.deviceName // \"\") | tostring | $CLEAN_FILTER" "$dir/$CRED_NAME" 2>/dev/null) || device=""
  fi
  for f in "$dir/$CRED_NAME" "$dir"/pairing-*.json; do
    if [ -e "$f" ] || [ -L "$f" ]; then rm -f "$f" && found=1; fi
  done
  if [ -n "$device" ]; then
    printf 'Unpaired %s from this install. Revoke the device in Settings → Devices so its credential stops working.\n' "$device"
  elif [ "$found" -eq 1 ]; then
    printf 'Removed the local Allye hook files. Revoke this install'"'"'s device in Settings → Devices so its credential stops working.\n'
  else
    printf 'Nothing to unpair: this install has no Allye hook credential.\n'
  fi
}

# ─── live off | on | status (ALY-203, BR-11, BR-12) ─────────────────────────

# The three lock functions and the pid-lock helpers they call (proc_start, pidlock_rec, pidlock_stale, ALY-217) are
# verbatim copies of those in hooks/live-report.sh (the reporter's per-session state lock protects the seq counter and
# the spool); hooks/test-allye-hooks.sh pins the bodies so the copies cannot drift. This script takes only time locks;
# a pid lock (DIR/p, "<holder pid> <holder start>") is stale once its holder is gone.
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
# instead (DIR/p, see pidlock_rec). A stale lock is renamed
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
# lock_drop DIR TOKEN: removes the lock only while DIR/t still holds this hook's own token.
lock_drop() {
  local t=""
  { IFS=' ' read -r _ t <"$1/t"; } 2>/dev/null
  [ -n "${2:-}" ] && [ "$t" = "$2" ] && rm -rf "$1" 2>/dev/null
  return 0
}

private_regular() { [ -n "$(find "$1" -prune -type f -user "$UID_NOW" -perm 0600 -print 2>/dev/null)" ]; }

# live_send BODYFILE: one POST to the ingest route of the credential's host, the credential only in a curl config on
# stdin, a 1-second limit (the SessionEnd budget of BR-12); succeeds only on a 2xx. The answer is never read or printed.
live_send() {
  local code
  code=$({
    printf 'url = "%s/api/agent-runs/events"\n' "$LIVE_API"
    printf 'header = "Authorization: Bearer %s"\n' "$LIVE_TOKEN"
    printf 'header = "Content-Type: application/json"\n'
    printf 'header = "Accept: application/json"\n'
    printf 'data-binary = "@%s"\n' "$1"
    printf 'max-time = 1\nconnect-timeout = 1\nmax-filesize = 65536\nnoproxy = "*"\n'
  } | curl -q --silent -K - -o /dev/null -w '%{http_code}' 2>/dev/null) || return 1
  case "$code" in 2[0-9][0-9]) return 0 ;; *) return 1 ;; esac
}

cmd_live() {
  local scope=""
  if [ "$#" -ge 1 ] && [ "$1" = activity ]; then scope=activity; shift; fi
  [ "$#" -eq 2 ] || usage
  local action="$1" dir="$2" live src h f base sessions="" n_spool=0 n_bytes=0 n_sess=0 lines bytes
  local ended=0 failed=0 body seqf statef prev ms new at pids=() p running=0 until_ fp now tok send
  case "$action" in off|on|status) ;; *) usage ;; esac
  valid_dir_arg "$dir" || fail "The data directory must be an absolute path (got an empty, relative or unexpanded value)."
  src="${BASH_SOURCE[0]}"; case "$src" in */*) ;; *) src="./$src" ;; esac
  command -v jq >/dev/null 2>&1 || fail "jq is required."
  # shellcheck source=lib/credential.sh
  . "${src%/*}/lib/credential.sh" 2>/dev/null || fail "The reporter's credential helper is missing."
  if ! load_live_credential "$dir"; then
    printf 'Live reporting is not available: this install is not paired with Allye (run /allye:hooks pair).\n'
    return 0
  fi
  live="${dir:?}/live"
  if [ -L "$live" ]; then fail "The live directory is a symlink; refusing to use it."; fi
  if [ -e "$live" ] && [ -z "$(find "$live" -prune -type d -user "$UID_NOW" -perm 0700 -print 2>/dev/null)" ]; then
    fail "The live directory is not a private directory you own (mode 0700); refusing to use it."
  fi
  if [ "$scope" = activity ]; then LIVE_TOKEN=""; cmd_live_activity "$action" "$live"; return 0; fi

  # Sessions known locally: the distinct <sha256> prefixes of the reporter's files.
  if [ -d "$live" ]; then
    for f in "$live"/*; do
      [ -e "$f" ] || continue
      base="${f##*/}"
      if [[ "$base" =~ ^([0-9a-f]{64})\.(spool|seq|state|bind|gates|cred|flushed)$ ]]; then
        h="${BASH_REMATCH[1]}"
        case " $sessions " in *" $h "*) ;; *) sessions="$sessions $h"; n_sess=$((n_sess + 1)) ;; esac
      fi
    done
  fi

  case "$action" in
    status)
      for f in "$live"/*.spool; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        lines=$(wc -l <"$f" 2>/dev/null) || continue; lines=${lines//[[:space:]]/}
        bytes=$(wc -c <"$f" 2>/dev/null) || continue; bytes=${bytes//[[:space:]]/}
        [[ "$lines" =~ ^[0-9]+$ ]] && [[ "$bytes" =~ ^[0-9]+$ ]] || continue
        n_spool=$((n_spool + lines)); n_bytes=$((n_bytes + bytes))
      done
      if [ -e "$live/off" ] || [ -L "$live/off" ]; then printf 'Live reporting: off\n'; else printf 'Live reporting: on\n'; fi
      activity_line "$live"
      printf 'Sessions with local data: %s\n' "$n_sess"
      printf 'Spooled events: %s (%s bytes)\n' "$n_spool" "$n_bytes"
      if [ -e "$live/disabled" ] || [ -L "$live/disabled" ]; then
        printf 'Last result: credential rejected by Allye (401); pair again to resume\n'
      else
        until_=""; fp=""
        if [ -f "$live/backoff" ] && [ ! -L "$live/backoff" ] && private_regular "$live/backoff"; then { IFS=' ' read -r until_ fp <"$live/backoff"; } 2>/dev/null; fi
        now=$(date +%s 2>/dev/null) || now=0
        if [[ "$until_" =~ ^[0-9]{1,12}$ ]] && [ "$fp" = "$(printf '%s' "$LIVE_TOKEN" | sha_hex)" ] && [ "$now" -lt "$until_" ]; then
          printf 'Last result: backing off for %s more seconds after an Allye answer\n' "$((until_ - now))"
        else
          printf 'Last result: none recorded\n'
        fi
      fi
      LIVE_TOKEN=""
      ;;
    on)
      if [ -e "$live/off" ] || [ -L "$live/off" ]; then rm -f "${live:?}/off" || fail "Could not remove the live-off flag."; fi
      printf 'Live reporting is on.\n'
      LIVE_TOKEN=""
      ;;
    off)
      case "$live" in *[\"\\]*) fail "The data directory path cannot be used for the live reporter." ;; esac
      [ -d "$live" ] || mkdir -m 700 "$live" 2>/dev/null || fail "Could not create the live directory."
      # The flag first, so no new hook spools or sends while the runs are ended below.
      new_tmp "$live" off; : >"$NEW_TMP" || fail "Could not write the live-off flag."
      mv -f "$NEW_TMP" "$live/off" || fail "Could not write the live-off flag."
      at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || at=""
      ms=$(date +%s%3N 2>/dev/null); [[ "$ms" =~ ^[0-9]{13,16}$ ]] || ms="$(date +%s 2>/dev/null)000"
      for h in $sessions; do
        statef="$live/$h.state"; seqf="$live/$h.seq"
        if [ -f "$statef" ] && [ ! -L "$statef" ] && private_regular "$statef"; then
          prev=""; { IFS= read -r prev <"$statef"; } 2>/dev/null
          if [ "$prev" = ended ]; then rm -f "${live:?}/${h:?}.spool"; continue; fi
        fi
        # A session whose lock stays taken cannot be ended cleanly, but its spool is still deleted (off means nothing
        # is sent afterwards); the run is then ended by Allye after a period of silence.
        if ! lock_take "$live/$h.lock" 50; then failed=$((failed + 1)); rm -f "${live:?}/${h:?}.spool"; continue; fi
        tok="$LOCK_TOKEN"; send=1
        if [ -e "$live/disabled" ] || [ -L "$live/disabled" ] || [ -z "$at" ]; then send=0; fi
        if [ "$send" = 1 ]; then
          # seq as the reporter allocates it: max(previous + 1, Unix ms), previous read from the same counter file.
          prev=0
          if [ -f "$seqf" ] && [ ! -L "$seqf" ] && private_regular "$seqf"; then { IFS= read -r prev <"$seqf"; } 2>/dev/null; fi
          if [[ "$prev" =~ ^(0|[1-9][0-9]{0,15})$ ]] && [ "$prev" -lt 9007199254740991 ] && [ "$prev" -le $((ms + 86400000)) ]; then :; else prev=0; fi
          new=$((prev + 1)); [ "$new" -ge "$ms" ] || new="$ms"
          new_tmp "$live" seq; printf '%s' "$new" >"$NEW_TMP" && mv -f "$NEW_TMP" "$seqf"
          new_tmp "$live" offbody; body="$NEW_TMP"
          jq -nc --arg h "$h" --argjson s "$new" --arg at "$at" \
            '{client: {kind: "claude-code"}, session: {hash: $h}, events: [{seq: $s, at: $at, type: "state", state: "ended", code: "end_live_off"}]}' >"$body" || send=0
          # The state is set to ended before the request is made, and a failed end is not retried: Allye ends the
          # run by itself after a period of silence (the reporter is off, so nothing else will resend it).
          if [ "$send" = 1 ]; then
            new_tmp "$live" state; printf 'ended' >"$NEW_TMP" && mv -f "$NEW_TMP" "$statef"
          fi
        fi
        rm -f "${live:?}/${h:?}.spool"
        lock_drop "$live/$h.lock" "$tok"
        if [ "$send" = 1 ]; then
          live_send "$body" &
          pids+=("$!"); running=$((running + 1))
          if [ "$running" -ge 4 ]; then
            for p in "${pids[@]}"; do if wait "$p"; then ended=$((ended + 1)); else failed=$((failed + 1)); fi; done
            pids=(); running=0
          fi
        fi
      done
      for p in ${pids[@]+"${pids[@]}"}; do if wait "$p"; then ended=$((ended + 1)); else failed=$((failed + 1)); fi; done
      LIVE_TOKEN=""
      printf 'Live reporting is off; local spools deleted.\n'
      printf 'Ended %s session(s) on Allye.\n' "$ended"
      if [ "$failed" -gt 0 ]; then printf '%s session(s) could not be ended now (their local spools were deleted); Allye ends them by itself after a period of silence.\n' "$failed"; fi
      ;;
  esac
}

# ─── live activity off | on | status (ALY-217.6: BR-12, D-25) ───────────────
# The reporter attaches no activity phrase and keeps no Agent stash while $live/activity-off exists (any kind of entry).
# Called after the pairing and live-directory checks of cmd_live (owner, mode 0700, no symlink); no network call.
activity_line() {
  if [ -e "$1/activity-off" ] || [ -L "$1/activity-off" ]; then printf 'Live activity phrases: off\n'; else printf 'Live activity phrases: on\n'; fi
}
cmd_live_activity() {
  local action="$1" live="$2"
  case "$action" in
    status) activity_line "$live" ;;
    on)
      if [ -e "$live/activity-off" ] || [ -L "$live/activity-off" ]; then rm -f "${live:?}/activity-off" || fail "Could not remove the activity-off flag."; fi
      printf 'Live activity phrases are on.\n'
      ;;
    off)
      [ -d "$live" ] || mkdir -m 700 "$live" 2>/dev/null || fail "Could not create the live directory."
      new_tmp "$live" activity-off; : >"$NEW_TMP" || fail "Could not write the activity-off flag."
      mv -f "$NEW_TMP" "$live/activity-off" || fail "Could not write the activity-off flag."
      printf 'Live activity phrases are off; tool events are still reported.\n'
      ;;
  esac
}

[ "$ORIGINAL_COUNT" -ge 1 ] || usage
sub="$1"
shift
case "$sub" in
  begin) cmd_begin "$@" ;;
  finish) cmd_finish "$@" ;;
  unpair) cmd_unpair "$@" ;;
  live) cmd_live "$@" ;;
  *) usage ;;
esac
