# Allye Plugin — OpenCode Installation Guide

You are an AI agent helping the user install the Allye plugin for OpenCode. Follow these steps exactly.

## Step 1: Configure MCP Server and Plugin

Read the current OpenCode global config:

```bash
cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{}'
```

Update the config with the Allye MCP server (OAuth — no PAT needed) AND the allye-opencode plugin:

```bash
CONFIG=$(cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{"$schema": "https://opencode.ai/config.json"}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcp["allye-mcp"] = {
    "type": "remote",
    "url": "https://allye-mcp.devshire.app/mcp",
    "enabled": true
  }
  | .plugin = (.plugin // [])
  | if (.plugin | index("allye-opencode")) then . else .plugin += ["allye-opencode"] end
')

mkdir -p ~/.config/opencode
echo "$CONFIG" | jq '.' > ~/.config/opencode/opencode.json
```

This configures:
- **Allye MCP server** — connects to `allye-mcp.devshire.app` with OAuth authentication
- **allye-opencode plugin** — registers 5 specialized agents (Allye, Plan, Build, Review, Deliver)

## Step 2: Authenticate

After restarting OpenCode, the first time you use a Allye tool, your browser will open automatically for OAuth login. Sign in with your Allye account, select a team, and approve.

Tokens are cached — you won't need to log in again unless the token expires.

## Step 3: Confirm

Tell the user:

> Allye is configured for OpenCode!
>
> **What was set up:**
> - Allye MCP server connected via OAuth (allye-mcp.devshire.app)
> - allye-opencode plugin installed — 5 specialized agents:
>   - **Allye** — orchestrator (detects phase, delegates)
>   - **Allye Plan** — product and technical planning
>   - **Allye Build** — TDD implementation
>   - **Allye Review** — code review with context
>   - **Allye Deliver** — delivery and documentation
> - 10 workflow skills available from the Allye marketplace
> - User context auto-loads at the start of every conversation
>
> **Restart OpenCode** to activate. Your browser will open for login on first use. You'll see the Allye agents in the agent picker (Ctrl+T).
