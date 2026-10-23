# Credential helper shared by the Live reporter (hooks/live-report.sh). SOURCED, never executed: it
# only defines functions (no set, exit, trap or top-level command). The caller sets UID_NOW (the
# user's id) and LC_ALL=C (plain variable) before calling anything here.
#
# valid_dir_arg, safe_file, have_sha, sha_hex and valid_api_url are verbatim copies of the functions of
# the same name in hooks/allye-hooks.sh (valid_api_url also mirrors hooks/session-preferences.sh);
# hooks/test-live-report.sh pins every body so the copies cannot drift. The ALY-195 scripts are not
# refactored to source this file (deviation from the "extract" option of ALY-203 Technical).

valid_dir_arg() {
  case "$1" in
    ''|*'${'*|*[[:cntrl:]]*) return 1 ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

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

# sha256 of stdin as lowercase hex; sha256sum, else shasum -a 256.
have_sha() { command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; }
sha_hex() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then out=$(sha256sum); else out=$(shasum -a 256); fi
  printf '%s' "${out%% *}"
}

# load_live_credential DIR: succeeds (0) only for a valid ALY-195 credential in DIR, setting LIVE_TOKEN
# and LIVE_API; otherwise returns 1 silently. Checks, all copied from session-preferences.sh: absolute
# directory argument, a real directory (no symlink) owned by the user with mode 0700, a credential file
# that is a regular file (no symlink) owned by the user without group or other permissions, the shape
# and token pattern of the credential, and a valid API origin. Nothing is ever printed or created.
load_live_credential() {
  local dir="$1" cred body
  LIVE_TOKEN=""; LIVE_API=""
  valid_dir_arg "$dir" || return 1
  [ ! -L "$dir" ] || return 1
  [ -n "$(find "$dir" -prune -type d -user "$UID_NOW" -perm 0700 -print 2>/dev/null)" ] || return 1
  cred="$dir/hook-credential.json"
  [ ! -L "$cred" ] || return 1
  safe_file "$cred" || return 1
  body=$(cat "$cred" 2>/dev/null) || return 1
  printf '%s' "$body" | jq -e '
    type == "object"
    and (.token | type == "string" and test("\\Aalyh_[A-Za-z0-9_-]{43}\\z"))
    and (.apiUrl | type == "string")
    and (.email | type == "string")
    and (.tenantName | type == "string")' >/dev/null 2>&1 || return 1
  LIVE_TOKEN=$(printf '%s' "$body" | jq -r '.token' 2>/dev/null) || { LIVE_TOKEN=""; return 1; }
  LIVE_API=$(printf '%s' "$body" | jq -r '.apiUrl' 2>/dev/null) || { LIVE_TOKEN=""; LIVE_API=""; return 1; }
  [[ "$LIVE_TOKEN" =~ ^alyh_[A-Za-z0-9_-]{43}$ ]] && valid_api_url "$LIVE_API" || { LIVE_TOKEN=""; LIVE_API=""; return 1; }
  return 0
}
