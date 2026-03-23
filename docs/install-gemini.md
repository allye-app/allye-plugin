# Fenix Plugin — Gemini CLI Installation Guide

You are an AI agent helping the user install the Fenix plugin for Gemini CLI. Follow these steps exactly.

## Step 1: Configure MCP Server

Add the Fenix MCP server to Gemini CLI settings (OAuth — no PAT needed):

```bash
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
mkdir -p "$HOME/.gemini"

CONFIG=$(cat "$GEMINI_SETTINGS" 2>/dev/null || echo '{}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcpServers["fenix-mcp"] = {
    "httpUrl": "https://fenix-mcp.devshire.app/mcp"
  }
')

echo "$CONFIG" | jq '.' > "$GEMINI_SETTINGS"
```

## Step 2: Install GEMINI.md

Download the Fenix GEMINI.md:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/gemini/GEMINI.md > ~/.gemini/GEMINI.md
```

If the user already has a `~/.gemini/GEMINI.md`, append the Fenix content instead of overwriting.

## Step 3: Authenticate

After starting a new Gemini session, the first time you use a Fenix tool, your browser will open automatically for OAuth login. Sign in with your Fenix account, select a team, and approve.

## Step 4: Confirm

Tell the user:

> Fenix is configured for Gemini CLI!
>
> **What was set up:**
> - Fenix MCP server connected via OAuth (~/.gemini/settings.json)
> - GEMINI.md installed with Fenix workflow instructions
>
> **Start a new Gemini session** to begin using Fenix workflows. Your browser will open for login on first use.
