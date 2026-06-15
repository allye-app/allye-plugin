#!/bin/bash
set -e

# Allye Plugin — Claude Code SessionStart Hook
# Injects the using-allye bootstrap skill at the start of every session.
#
# How it works:
# 1. Checks if ALLYE_PAT is configured
# 2. Tries to fetch the skill from Allye API
# 3. Falls back to the local bundled skill file
# 4. Outputs JSON with additionalContext for Claude to consume

# Read hook input from stdin
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Config
ALLYE_API_URL="https://api.allye.app"
ALLYE_PAT="${ALLYE_PAT:-}"
SKILL_SLUG="using-allye"

# Plugin root — always derive from script location (most reliable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_SKILL="$PLUGIN_ROOT/skills/using-allye/SKILL.md"

# Fallback to legacy path if new structure doesn't exist yet
if [ ! -f "$LOCAL_SKILL" ]; then
  LOCAL_SKILL="$PLUGIN_ROOT/skills/bootstrap/using-allye.md"
fi

# Check if PAT is configured — OAuth users won't have PAT set, that's OK
# The .mcp.json handles OAuth automatically. PAT is only for CI/CD fallback.
if [ -z "$ALLYE_PAT" ]; then
  # Check if .mcp.json exists (OAuth mode — no PAT needed)
  MCP_JSON="$PLUGIN_ROOT/.mcp.json"
  if [ -f "$MCP_JSON" ]; then
    # OAuth mode — proceed to load skill without PAT
    ALLYE_PAT=""
  else
    # No PAT and no .mcp.json — need setup
    SETUP_MSG="# Allye Plugin — Setup Required

Welcome to the Allye Agent Plugin! To get started, run:

\`\`\`
/allye-setup
\`\`\`

This will guide you through connecting your Allye account."

    jq -n --arg ctx "$SETUP_MSG" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $ctx
      }
    }'
    exit 0
  fi
fi

# Function: fetch skill from Allye API
fetch_from_api() {
  HTTP_RESULT=$(curl -s --max-time 10 -w "\n%{http_code}" \
    -H "Authorization: Bearer $ALLYE_PAT" \
    -H "Content-Type: application/json" \
    "$ALLYE_API_URL/api/skills/export?slug=$SKILL_SLUG&format=claude" 2>/dev/null) || return 1

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
    echo "# Allye Plugin"
    echo ""
    echo "Bootstrap skill not found. Try reinstalling the plugin."
  fi
}

# Try API first, fall back to local file
SKILL_CONTENT=$(fetch_from_api || read_local)

# Persist env vars for the session
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export ALLYE_PLUGIN_LOADED=true' >> "$CLAUDE_ENV_FILE"

  # Auto-generate tenant slug from current directory name for multi-account OAuth isolation.
  # Each project directory gets a unique slug → unique MCP URL → separate OAuth token.
  # Users can override by setting ALLYE_TENANT_SLUG in their environment.
  if [ -z "$ALLYE_TENANT_SLUG" ]; then
    ALLYE_TENANT_SLUG=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  fi
  echo "export ALLYE_TENANT_SLUG=$ALLYE_TENANT_SLUG" >> "$CLAUDE_ENV_FILE"
fi

# Output structured JSON for Claude Code
jq -n --arg ctx "$SKILL_CONTENT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'

exit 0
