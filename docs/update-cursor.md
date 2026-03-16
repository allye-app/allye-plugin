# Fenix Plugin — Cursor Update Guide

You are an AI agent helping the user update the Fenix plugin for Cursor. Follow these steps exactly.

## Step 1: Update .cursorrules

Download the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/cursor/.cursorrules > ~/.cursor/.cursorrules.new
```

Check if the user has custom rules appended to their `.cursorrules`. If so, merge — don't overwrite:

```bash
diff ~/.cursor/.cursorrules ~/.cursor/.cursorrules.new 2>/dev/null
```

If the user has no custom rules, replace:

```bash
mv ~/.cursor/.cursorrules.new ~/.cursor/.cursorrules
```

If the user has custom rules, append only the Fenix section.

## Step 2: Verify MCP server

Check that the Fenix MCP server is still configured:

```bash
cat ~/.cursor/mcp.json | jq '.mcpServers["fenix-mcp"]'
```

If it's missing, re-configure it (ask the user for their PAT if needed).

## Step 3: Confirm

Tell the user:

> Fenix plugin updated for Cursor!
>
> **Restart Cursor** to activate the new rules.
