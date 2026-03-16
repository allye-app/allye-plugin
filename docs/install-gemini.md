# Fenix Plugin — Gemini CLI Installation Guide

You are an AI agent helping the user install the Fenix plugin for Gemini CLI. Follow these steps exactly.

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

- If `200`: Valid. Confirm authentication.
- If `401`/`403`: Invalid. Ask user to retry.

## Step 3: Configure MCP Server

Add the Fenix MCP server to Gemini CLI settings. Replace `{PAT}` with the actual token:

```bash
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
mkdir -p "$HOME/.gemini"

CONFIG=$(cat "$GEMINI_SETTINGS" 2>/dev/null || echo '{}')

CONFIG=$(echo "$CONFIG" | jq --arg pat "{PAT}" '
  .mcpServers["fenix-mcp"] = {
    "httpUrl": "https://fenix-mcp.devshire.app/jsonrpc",
    "headers": {
      "Authorization": ("Bearer " + $pat)
    }
  }
')

echo "$CONFIG" | jq '.' > "$GEMINI_SETTINGS"
```

## Step 4: Install GEMINI.md

Download the Fenix GEMINI.md:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/gemini/GEMINI.md > ~/.gemini/GEMINI.md
```

If the user already has a `~/.gemini/GEMINI.md`, append the Fenix content instead of overwriting.

## Step 5: Confirm

Tell the user:

> Fenix is configured for Gemini CLI!
>
> **What was set up:**
> - Fenix MCP server connected (~/.gemini/settings.json)
> - GEMINI.md installed with Fenix workflow instructions
> - Workflow skills seeded into your Fenix database
>
> **Start a new Gemini session** to begin using Fenix workflows.
