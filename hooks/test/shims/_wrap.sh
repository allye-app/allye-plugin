#!/bin/bash
# Logging shim body: _wrap.sh <tool> <args...>. Records argv and the environment of every call
# in $SHIM_LOG, then runs the real tool from $SHIM_REAL. For curl it also refuses any host that
# is not loopback (NFR-02) and logs only the non-secret config lines.
set -u
tool="$1"; shift
log="${SHIM_LOG:?}"
{ printf '%s' "$tool"; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >>"$log/calls.log"
env >>"$log/environ.log"
loopback() {
  case "$1" in
    http://127.0.0.1|http://127.0.0.1:*|http://localhost|http://localhost:*|"http://[::1]"|"http://[::1]:"*) return 0 ;;
  esac
  return 1
}
if [ "$tool" = curl ]; then
  cfg=$(cat)
  for a in "$@"; do
    case "$a" in http://*|https://*) loopback "${a%%/api*}" || { echo "curl shim: refused non-loopback $a" >&2; echo "REFUSED $a" >>"$log/refused.log"; exit 97; } ;; esac
  done
  url=$(printf '%s\n' "$cfg" | sed -n 's/^url = "\(.*\)"$/\1/p')
  printf '%s\n' "$cfg" | grep -E '^(url|request|max-time|connect-timeout|max-filesize|proto) ' >>"$log/curl-config.log"
  if [ -n "$url" ] && ! loopback "${url%%/api*}"; then
    echo "curl shim: refused non-loopback $url" >&2; echo "REFUSED $url" >>"$log/refused.log"; exit 97
  fi
  printf '%s\n' "$cfg" | "$SHIM_REAL/curl" "$@"
  exit $?
fi
if [ "$tool" = uname ] && [ -n "${SHIM_UNAME_OUT:-}" ]; then printf '%s\n' "$SHIM_UNAME_OUT"; exit 0; fi
exec "$SHIM_REAL/$tool" "$@"
