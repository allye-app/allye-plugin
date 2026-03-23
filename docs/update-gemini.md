# Fenix Plugin — Gemini CLI Update Guide

You are an AI agent helping the user update the Fenix plugin for Gemini CLI. Follow these steps exactly.

## Step 1: Update GEMINI.md

Download the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/gemini/GEMINI.md > ~/.gemini/GEMINI.md.new
```

Check if the user has custom content in their GEMINI.md. If so, merge — don't overwrite:

```bash
diff ~/.gemini/GEMINI.md ~/.gemini/GEMINI.md.new 2>/dev/null
```

If no custom content, replace:

```bash
mv ~/.gemini/GEMINI.md.new ~/.gemini/GEMINI.md
```

If custom content exists, append only the Fenix section.

## Step 2: Verify MCP server

Check that the Fenix MCP server is configured with OAuth (no PAT headers):

```bash
cat ~/.gemini/settings.json | jq '.mcpServers["fenix-mcp"]'
```

If it has `headers.Authorization` with a PAT, update to OAuth:

```bash
CONFIG=$(cat ~/.gemini/settings.json)
CONFIG=$(echo "$CONFIG" | jq '.mcpServers["fenix-mcp"] = { "httpUrl": "https://fenix-mcp.devshire.app/mcp" }')
echo "$CONFIG" | jq '.' > ~/.gemini/settings.json
```

## Step 3: Confirm

Tell the user:

> Fenix plugin updated for Gemini CLI!
>
> **Start a new Gemini session** to use the updated instructions. Authentication is now via OAuth — your browser will open on first use.
