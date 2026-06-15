# Allye Plugin — Gemini CLI Installation Guide

You are an AI agent helping the user install the Allye plugin for Gemini CLI. Follow these steps exactly.

## Step 1: Configure MCP Server

Add the Allye MCP server to Gemini CLI settings (OAuth — no PAT needed):

```bash
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
mkdir -p "$HOME/.gemini"

CONFIG=$(cat "$GEMINI_SETTINGS" 2>/dev/null || echo '{}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcpServers["allye-mcp"] = {
    "httpUrl": "https://allye-mcp.devshire.app/mcp"
  }
')

echo "$CONFIG" | jq '.' > "$GEMINI_SETTINGS"
```

## Step 2: Install GEMINI.md

Download the Allye GEMINI.md:

```bash
curl -fsSL https://raw.githubusercontent.com/allye-app/allye-plugin/main/manifests/gemini/GEMINI.md > ~/.gemini/GEMINI.md
```

If the user already has a `~/.gemini/GEMINI.md`, append the Allye content instead of overwriting.

## Step 3: Authenticate

After starting a new Gemini session, the first time you use a Allye tool, your browser will open automatically for OAuth login. Sign in with your Allye account, select a team, and approve.

## Step 4: Confirm

Tell the user:

> Allye is configured for Gemini CLI!
>
> **What was set up:**
> - Allye MCP server connected via OAuth (~/.gemini/settings.json)
> - GEMINI.md installed with Allye workflow instructions
>
> **Start a new Gemini session** to begin using Allye workflows. Your browser will open for login on first use.
