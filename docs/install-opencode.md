# Fenix Plugin — OpenCode Installation Guide

You are an AI agent helping the user install the Fenix plugin for OpenCode. Follow these steps exactly.

## Step 1: Configure MCP Server and Plugin

Read the current OpenCode global config:

```bash
cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{}'
```

Update the config with the Fenix MCP server (OAuth — no PAT needed) AND the fenix-opencode plugin:

```bash
CONFIG=$(cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{"$schema": "https://opencode.ai/config.json"}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcp["fenix-mcp"] = {
    "type": "remote",
    "url": "https://fenix-mcp.devshire.app/mcp",
    "enabled": true
  }
  | .plugin = (.plugin // [])
  | if (.plugin | index("fenix-opencode")) then . else .plugin += ["fenix-opencode"] end
')

mkdir -p ~/.config/opencode
echo "$CONFIG" | jq '.' > ~/.config/opencode/opencode.json
```

This configures:
- **Fenix MCP server** — connects to `fenix-mcp.devshire.app` with OAuth authentication
- **fenix-opencode plugin** — registers 5 specialized agents (Fenix, Plan, Build, Review, Deliver)

## Step 2: Authenticate

After restarting OpenCode, the first time you use a Fenix tool, your browser will open automatically for OAuth login. Sign in with your Fenix account, select a team, and approve.

Tokens are cached — you won't need to log in again unless the token expires.

## Step 3: Confirm

Tell the user:

> Fenix is configured for OpenCode!
>
> **What was set up:**
> - Fenix MCP server connected via OAuth (fenix-mcp.devshire.app)
> - fenix-opencode plugin installed — 5 specialized agents:
>   - **Fenix** — orchestrator (detects phase, delegates)
>   - **Fenix Plan** — product and technical planning
>   - **Fenix Build** — TDD implementation
>   - **Fenix Review** — code review with context
>   - **Fenix Deliver** — delivery and documentation
> - 10 workflow skills available from the Fenix marketplace
> - User context auto-loads at the start of every conversation
>
> **Restart OpenCode** to activate. Your browser will open for login on first use. You'll see the Fenix agents in the agent picker (Ctrl+T).
