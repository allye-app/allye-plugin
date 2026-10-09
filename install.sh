#!/bin/bash
# Allye skills installer.
#
# Installs your organization's skills — the ones stored in Allye's Skills
# section for your tenant and teams — into a coding harness on this machine,
# through the API's governed, signed distribution flow.
#
#   ./install.sh list [--scope personal|team|organization] [--query <text>]
#   ./install.sh install <runtime> <skill-slug|skill-id>... [--reinstall]
#   ./install.sh status
#
# Runtimes: claude, codex, opencode, pi, omp.
# Environment: ALLYE_PAT (required for list/install), ALLYE_TEAM_ID or --team,
# ALLYE_API_URL (default https://api.allye.app).
# --reinstall replaces a copy you edited (it is kept under ~/.allye/backups/<runtime>/);
# foreign or unmanaged folders are never touched.
#
# This does not install the Allye plugin, the MCP server or Bridge; see the
# per-harness guides in docs/.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
# Messages can carry text from the API or from node: control characters are dropped and the
# text goes through %s, so it can never move the cursor, set a title or expand a backslash escape.
# Strips ASCII controls, the UTF-8 C1 controls (U+0080-U+009F, e.g. the 8-bit CSI U+009B) and the
# bidi/format characters U+200B-U+200F, U+2028-U+202E, U+2066-U+2069. The sed script is built from
# literal bytes (printf octal), so it is the same on GNU and BSD sed under LC_ALL=C.
# clean_text STRING [BOUND]: cuts the input to BOUND bytes (default 2048, for untrusted server strings; the print_* helpers use 20480 so a path built by the installer is never cut), trims an incomplete trailing UTF-8 sequence left by the cut (iconv -c; skipped when iconv is missing), removes control characters, then repeats the C1 and bidi/format removal to a fixpoint: removing a sequence can join the bytes around it into a new one. At most 16 changing passes (more nesting than that is hostile): over the cap only a fixed placeholder is printed, never a partial result. The head -c cut runs once, before the loop, so the time bound holds.
clean_text() {
  local s p n=0 cut= max="${2:-2048}"
  s=$(printf '%s' "$1" | LC_ALL=C head -c "$max")
  if [ "$(printf '%s' "$1" | LC_ALL=C wc -c)" -gt "$max" ]; then
    cut='...'
    if command -v iconv >/dev/null 2>&1; then s=$(printf '%s' "$s" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true); fi   # -c drops the incomplete tail; iconv may still exit 1 on it, its output is what counts
  fi
  s=$(printf '%s' "$s" | LC_ALL=C tr -d '[:cntrl:]')
  while :; do
    p=$(printf '%s' "$s" | LC_ALL=C sed -E "s/$(printf '\302')[$(printf '\200')-$(printf '\237')]//g; s/$(printf '\342\200')[$(printf '\213')-$(printf '\217')$(printf '\250')-$(printf '\256')]//g; s/$(printf '\342\201')[$(printf '\246')-$(printf '\251')]//g")
    [ "$p" != "$s" ] || break
    n=$((n+1)); [ "$n" -le 16 ] || { printf '[unprintable]'; return 0; }
    s="$p"
  done
  printf '%s%s' "$s" "$cut"
}
print_text()    { clean_text "$1" 20480; }   # installer-built messages: much larger bound than server strings
print_step()    { printf '%b→%b %s\n' "$BLUE" "$NC" "$(print_text "$1")"; }
print_success() { printf '%b✓%b %s\n' "$GREEN" "$NC" "$(print_text "$1")"; }
print_warning() { printf '%b!%b %s\n' "$YELLOW" "$NC" "$(print_text "$1")" >&2; }
print_error()   { printf '%b✗%b %s\n' "$RED" "$NC" "$(print_text "$1")" >&2; }

usage() {
  cat >&2 <<'USAGE'
usage: ./install.sh list [--scope personal|team|organization] [--query <text>] [--team <id>]
       ./install.sh install <claude|codex|opencode|pi|omp> <skill-slug|skill-id>... [--team <id>] [--reinstall]
       ./install.sh status
USAGE
  exit 2
}

for tool in curl jq node; do
  command -v "$tool" >/dev/null 2>&1 || { print_error "$tool is required but was not found on PATH."; exit 1; }
done

# shellcheck source=install/lib.sh
source "$SCRIPT_DIR/install/lib.sh"

VERB="${1:-}"; [ "$#" -eq 0 ] || shift
SCOPE=""; QUERY=""; ARGS=(); REINSTALL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --team) ALLYE_TEAM_ID="${2:?--team needs a team id}"; shift 2 ;;
    --scope) SCOPE="${2:?--scope needs personal, team or organization}"; shift 2 ;;
    --query) QUERY="${2:?--query needs text}"; shift 2 ;;
    --reinstall) REINSTALL=1; shift ;;
    -h|--help) usage ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
export ALLYE_TEAM_ID="${ALLYE_TEAM_ID:-}" ALLYE_REINSTALL="$REINSTALL"

case "$VERB" in
  status)
    allye_status ;;
  list)
    case "$SCOPE" in ""|personal|team|organization) ;; *) print_error "--scope must be personal, team or organization"; exit 2 ;; esac
    check_api_url && require_pat && allye_list "$SCOPE" "$QUERY" ;;
  install)
    [ "${#ARGS[@]}" -ge 1 ] || usage
    check_api_url && require_pat && allye_install "${ARGS[@]}" ;;
  *)
    usage ;;
esac
