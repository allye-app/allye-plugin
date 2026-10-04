#!/bin/bash
# Allye — Claude Code SessionStart hook.
# Injects the shared bootstrap (bootstrap/allye.md) as additionalContext so the
# agent knows the Allye MCP and the Bridge skill are available. Offline: it
# reads only the bundled file and never calls the network.
set -euo pipefail

cat >/dev/null || true  # hook input (unused)

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$PLUGIN_ROOT/bootstrap/allye.md"

if [ -f "$BOOTSTRAP" ]; then
  CONTEXT=$(cat "$BOOTSTRAP")
else
  CONTEXT="Allye bootstrap file is missing at $BOOTSTRAP; reinstall the plugin with /plugin update allye."
fi

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
