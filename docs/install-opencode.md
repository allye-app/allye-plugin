# Allye Plugin — OpenCode Installation Guide

You are an AI agent helping the user install the Allye plugin for OpenCode. Preserve unrelated MCP servers, plugins, and credentials.

## Step 1: Configure MCP and the plugin

Read the effective OpenCode config, then merge the canonical Allye entry and
plugin. If the effective config still has the legacy `allye-mcp` entry, first
run `opencode mcp logout allye-mcp`. This clears only that obsolete Allye
registration; do not delete OpenCode's auth store.

```bash
CONFIG=$(cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{"$schema": "https://opencode.ai/config.json"}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcp = (.mcp // {})
  | del(.mcp["allye-mcp"])
  | .mcp.allye = {
      "type": "remote",
      "url": "https://mcp.allye.app/mcp",
      "enabled": true
    }
  | .plugin = (.plugin // [])
  | if (.plugin | index("allye-opencode")) then . else .plugin += ["allye-opencode"] end
')

mkdir -p ~/.config/opencode
echo "$CONFIG" | jq '.' > ~/.config/opencode/opencode.json
```

The targeted `del` removes only the legacy Allye key. It does not clear the
OAuth store or change any unrelated MCP entry. The `allye` entry intentionally
contains no headers or fixed OAuth client metadata.

## Step 2: Authenticate

Restart OpenCode, then use its native OAuth commands:

```bash
opencode mcp auth allye
opencode mcp list
```

OpenCode owns discovery, client registration, token storage, and refresh.

## Step 3: Confirm

Tell the user:

> Allye is configured for OpenCode!
>
> **What was set up:**
> - `allye` MCP server at `https://mcp.allye.app/mcp`, using native OAuth
> - `allye-opencode` plugin with Allye, Plan, Orchestrator, Build, Review, and Deliver agents
> - Workflow guidance that loads context through the authenticated MCP tools
>
> Restart OpenCode to activate the plugin. Use `opencode mcp auth allye` if authentication has not started.
