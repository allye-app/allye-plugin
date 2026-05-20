# Allye Plugin — Cursor Installation Guide

You are an AI agent helping the user install the Allye plugin for Cursor. Follow these steps exactly.

## Step 1: Configure MCP Server

Add the Allye MCP server to Cursor's global config (OAuth — no PAT needed):

```bash
CURSOR_MCP="$HOME/.cursor/mcp.json"
mkdir -p "$HOME/.cursor"

CONFIG=$(cat "$CURSOR_MCP" 2>/dev/null || echo '{}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcpServers["allye-mcp"] = {
    "url": "https://allye-mcp.devshire.app/mcp"
  }
')

echo "$CONFIG" | jq '.' > "$CURSOR_MCP"
```

## Step 2: Install .cursorrules

Download and place the Allye cursorrules in the user's project:

```bash
curl -fsSL https://raw.githubusercontent.com/allye-assistant/allye-plugin/main/manifests/cursor/.cursorrules > .cursorrules
```

If the user has an existing `.cursorrules`, append the Allye rules instead of overwriting.

## Step 3: Authenticate

After restarting Cursor, the first time you use a Allye tool, your browser will open automatically for OAuth login. Sign in with your Allye account, select a team, and approve.

## Step 4: Confirm

Tell the user:

> Allye is configured for Cursor!
>
> **What was set up:**
> - Allye MCP server connected via OAuth (~/.cursor/mcp.json)
> - .cursorrules installed with Allye workflow rules
>
> **Restart Cursor** to activate. Your browser will open for login on first use.
