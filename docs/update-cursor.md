# Allye Plugin — Cursor Update Guide

You are an AI agent helping the user update the Allye plugin for Cursor. Follow these steps exactly.

## Step 1: Update .cursorrules

Download the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/allye-assistant/allye-plugin/main/manifests/cursor/.cursorrules > .cursorrules.new
```

Check if the user has custom rules appended to their `.cursorrules`. If so, merge — don't overwrite:

```bash
diff .cursorrules .cursorrules.new 2>/dev/null
```

If the user has no custom rules, replace:

```bash
mv .cursorrules.new .cursorrules
```

If the user has custom rules, append only the Allye section.

## Step 2: Verify MCP server

Check that the Allye MCP server is configured with OAuth (no PAT headers):

```bash
cat ~/.cursor/mcp.json | jq '.mcpServers["allye-mcp"]'
```

If it has `headers.Authorization` with a PAT, update to OAuth:

```bash
CONFIG=$(cat ~/.cursor/mcp.json)
CONFIG=$(echo "$CONFIG" | jq '.mcpServers["allye-mcp"] = { "url": "https://allye-mcp.devshire.app/mcp" }')
echo "$CONFIG" | jq '.' > ~/.cursor/mcp.json
```

## Step 3: Confirm

Tell the user:

> Allye plugin updated for Cursor!
>
> **Restart Cursor** to activate the new rules. Authentication is now via OAuth — your browser will open on first use.
