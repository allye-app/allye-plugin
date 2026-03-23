#!/bin/bash
set -e

# Fenix Plugin — Claude Code SessionStart Hook
# Injects the using-fenix bootstrap skill at the start of every session.
#
# How it works:
# 1. Checks if FENIX_PAT is configured
# 2. Tries to fetch the skill from Fenix API
# 3. Falls back to the local bundled skill file
# 4. Outputs JSON with additionalContext for Claude to consume

# Read hook input from stdin
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Config
FENIX_API_URL="https://fenix-api.devshire.app"
FENIX_PAT="${FENIX_PAT:-}"
SKILL_SLUG="using-fenix"

# Plugin root — always derive from script location (most reliable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_SKILL="$PLUGIN_ROOT/skills/using-fenix/SKILL.md"

# Fallback to legacy path if new structure doesn't exist yet
if [ ! -f "$LOCAL_SKILL" ]; then
  LOCAL_SKILL="$PLUGIN_ROOT/skills/bootstrap/using-fenix.md"
fi

# Check if PAT is configured — OAuth users won't have PAT set, that's OK
# The .mcp.json handles OAuth automatically. PAT is only for CI/CD fallback.
if [ -z "$FENIX_PAT" ]; then
  # Check if .mcp.json exists (OAuth mode — no PAT needed)
  MCP_JSON="$PLUGIN_ROOT/.mcp.json"
  if [ -f "$MCP_JSON" ]; then
    # OAuth mode — proceed to load skill without PAT
    FENIX_PAT=""
  else
    # No PAT and no .mcp.json — need setup
    SETUP_MSG="# Fenix Plugin — Setup Required

Welcome to the Fenix Agent Plugin! To get started, run:

\`\`\`
/fenix-setup
\`\`\`

This will guide you through connecting your Fenix account."

    jq -n --arg ctx "$SETUP_MSG" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $ctx
      }
    }'
    exit 0
  fi
fi

# Function: fetch skill from Fenix API
fetch_from_api() {
  HTTP_RESULT=$(curl -s --max-time 10 -w "\n%{http_code}" \
    -H "Authorization: Bearer $FENIX_PAT" \
    -H "Content-Type: application/json" \
    "$FENIX_API_URL/api/skills/export?slug=$SKILL_SLUG&format=claude" 2>/dev/null) || return 1

  HTTP_CODE=$(echo "$HTTP_RESULT" | tail -1)
  RESPONSE=$(echo "$HTTP_RESULT" | sed '$d')

  # Only accept 200 responses with non-empty content
  if [ "$HTTP_CODE" != "200" ] || [ -z "$RESPONSE" ] || [ "$RESPONSE" = "null" ]; then
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
    echo "Bootstrap skill not found. Try reinstalling the plugin."
  fi
}

# Try API first, fall back to local file
SKILL_CONTENT=$(fetch_from_api || read_local)

# Persist env vars for the session
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export FENIX_PLUGIN_LOADED=true' >> "$CLAUDE_ENV_FILE"

  # Auto-generate tenant slug from current directory name for multi-account OAuth isolation.
  # Each project directory gets a unique slug → unique MCP URL → separate OAuth token.
  # Users can override by setting FENIX_TENANT_SLUG in their environment.
  if [ -z "$FENIX_TENANT_SLUG" ]; then
    FENIX_TENANT_SLUG=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  fi
  echo "export FENIX_TENANT_SLUG=$FENIX_TENANT_SLUG" >> "$CLAUDE_ENV_FILE"
fi

# Output structured JSON for Claude Code
jq -n --arg ctx "$SKILL_CONTENT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'

exit 0
