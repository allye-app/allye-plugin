#!/bin/bash
# Allye skills installer.
#
# Installs your organization's skills — the ones stored in Allye's Skills
# section for your tenant and teams — into a coding harness on this machine,
# through the API's governed, signed distribution flow.
#
#   ./install.sh list [--scope personal|team|organization] [--query <text>]
#   ./install.sh install <runtime> <skill-slug|skill-id>...
#   ./install.sh status
#
# Runtimes: claude, codex, opencode, pi, omp.
# Environment: ALLYE_PAT (required for list/install), ALLYE_TEAM_ID or --team,
# ALLYE_API_URL (default https://api.allye.app).
#
# This does not install the Allye plugin, the MCP server or Bridge; see the
# per-harness guides in docs/.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_step()    { echo -e "${BLUE}→${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1" >&2; }
print_error()   { echo -e "${RED}✗${NC} $1" >&2; }

usage() {
  cat >&2 <<'USAGE'
usage: ./install.sh list [--scope personal|team|organization] [--query <text>] [--team <id>]
       ./install.sh install <claude|codex|opencode|pi|omp> <skill-slug|skill-id>... [--team <id>]
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
SCOPE=""; QUERY=""; ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --team) ALLYE_TEAM_ID="${2:?--team needs a team id}"; shift 2 ;;
    --scope) SCOPE="${2:?--scope needs personal, team or organization}"; shift 2 ;;
    --query) QUERY="${2:?--query needs text}"; shift 2 ;;
    -h|--help) usage ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
export ALLYE_TEAM_ID="${ALLYE_TEAM_ID:-}"

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
