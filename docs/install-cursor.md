# Fenix Plugin — Cursor Installation Guide

You are an AI agent helping the user install the Fenix plugin for Cursor. Follow these steps exactly.

## Step 1: Ask for the Fenix PAT

Say this to the user:

> To connect Fenix, I need your Personal Access Token (PAT).
>
> You can generate one at: **https://fenix.devshire.app** → Settings → API → Generate Token
>
> Paste your PAT here:

Wait for the user to provide the token.

## Step 2: Validate the PAT

Run this command, replacing `{PAT}` with the user's token:

```bash
curl -s -w "\n%{http_code}" -H "Authorization: Bearer {PAT}" https://fenix-api.devshire.app/api/auth/profile
```

- If the last line is `200`: PAT is valid. Extract the user's name and confirm: "Authenticated as {name}."
- If `401`/`403`: PAT is invalid. Ask the user to check and try again.

## Step 3: Configure MCP Server

Add the Fenix MCP server to Cursor's global config. Replace `{PAT}` with the actual token:

```bash
CURSOR_MCP="$HOME/.cursor/mcp.json"
mkdir -p "$HOME/.cursor"

CONFIG=$(cat "$CURSOR_MCP" 2>/dev/null || echo '{}')

CONFIG=$(echo "$CONFIG" | jq --arg pat "{PAT}" '
  .mcpServers["fenix-mcp"] = {
    "url": "https://fenix-mcp.devshire.app/jsonrpc",
    "headers": {
      "Authorization": ("Bearer " + $pat)
    }
  }
')

echo "$CONFIG" | jq '.' > "$CURSOR_MCP"
```

## Step 4: Install .cursorrules

Download and place the Fenix cursorrules in the user's project:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/cursor/.cursorrules > .cursorrules
```

If the user has an existing `.cursorrules`, append the Fenix rules instead of overwriting.

## Step 5: Seed Skills

If the user belongs to **multiple teams**, ask whether to seed skills to all teams or just one. Then clone the plugin repo temporarily and seed skills into Fenix using the MCP tools. For each team and each skill in `seed/seed-skills.json`, use `skill_create` (with `team_id`) or `skill_update` via the Fenix MCP. See OpenCode install guide Step 5 for the full procedure.

## Step 6: Confirm

Tell the user:

> Fenix is configured for Cursor!
>
> **What was set up:**
> - Fenix MCP server connected (~/.cursor/mcp.json)
> - .cursorrules installed with Fenix workflow rules
> - Workflow skills seeded into your Fenix database
>
> **Restart Cursor** to activate. Then start using Fenix workflows in your conversations.
