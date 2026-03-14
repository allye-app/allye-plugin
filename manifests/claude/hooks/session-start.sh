#!/bin/bash
set -e

# Fenix Plugin — Claude Code SessionStart Hook
# Injects the using-fenix bootstrap skill at the start of every session.
#
# How it works:
# 1. Tries to fetch the skill from Fenix API via MCP skill export
# 2. Falls back to the local bundled skill file if API is unavailable
# 3. Outputs JSON with additionalContext for Claude to consume

# Read hook input from stdin
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Config — set via install.sh or environment
FENIX_API_URL="${FENIX_API_URL:-}"
FENIX_PAT="${FENIX_PAT:-}"
SKILL_SLUG="using-fenix"

# Find the plugin root (where this script lives: manifests/claude/hooks/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOCAL_SKILL="$PLUGIN_ROOT/skills/bootstrap/using-fenix.md"

# Function: fetch skill from Fenix API
fetch_from_api() {
  if [ -z "$FENIX_API_URL" ] || [ -z "$FENIX_PAT" ]; then
    return 1
  fi

  RESPONSE=$(curl -s --max-time 10 \
    -H "Authorization: Bearer $FENIX_PAT" \
    -H "Content-Type: application/json" \
    "$FENIX_API_URL/api/skills/export?slug=$SKILL_SLUG&format=claude" 2>/dev/null) || return 1

  # Validate we got content back
  if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "null" ]; then
    return 1
  fi

  echo "$RESPONSE"
}

# Function: read local skill file
read_local() {
  if [ -f "$LOCAL_SKILL" ]; then
    cat "$LOCAL_SKILL"
  else
    echo "# Fenix Plugin"
    echo ""
    echo "Fenix bootstrap skill not found. Run install.sh to set up the plugin."
  fi
}

# Try API first, fall back to local file
SKILL_CONTENT=$(fetch_from_api || read_local)

# Persist env vars for the session
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export FENIX_PLUGIN_LOADED=true' >> "$CLAUDE_ENV_FILE"
fi

# Output structured JSON for Claude Code
jq -n --arg ctx "$SKILL_CONTENT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'

exit 0
