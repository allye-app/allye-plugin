#!/bin/bash
# Pairs this Claude Code install with Allye so a SessionStart hook can fetch the user's pinned
# preferences. Used by /allye:hooks (commands/hooks.md):
#   allye-hooks.sh begin   <dataDir>                        verifier -> pairing file, prints the challenge
#   allye-hooks.sh finish  <dataDir> <challenge> <code>     exchanges code + verifier for the credential
#   allye-hooks.sh unpair  <dataDir>                        deletes the local credential and pairing files
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
  printf '%s\n' "Usage: allye-hooks.sh begin <dataDir> | finish <dataDir> <challenge> <pairingCode> | unpair <dataDir>" >&2
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

[ "$ORIGINAL_COUNT" -ge 1 ] || usage
sub="$1"
shift
case "$sub" in
  begin) cmd_begin "$@" ;;
  finish) cmd_finish "$@" ;;
  unpair) cmd_unpair "$@" ;;
  *) usage ;;
esac
