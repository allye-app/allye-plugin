# Fenix Plugin — OpenCode Installation Guide

You are an AI agent helping the user install the Fenix plugin for OpenCode. Follow these steps exactly.

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

- If the last line is `200`: PAT is valid. Extract the user's name from the JSON response and confirm: "Authenticated as {name}."
- If the last line is `401` or `403`: PAT is invalid. Ask the user to check and try again.
- If connection fails: Fenix API may be down. Ask the user to try later.

## Step 3: Configure MCP Server and Plugin

Read the current OpenCode global config:

```bash
cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{}'
```

Update the config with the Fenix MCP server AND the fenix-opencode plugin. Replace `{PAT}` with the actual token:

```bash
CONFIG=$(cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{"$schema": "https://opencode.ai/config.json"}')

CONFIG=$(echo "$CONFIG" | jq --arg pat "{PAT}" '
  .mcp["fenix-mcp"] = {
    "type": "remote",
    "url": "https://fenix-mcp.devshire.app/jsonrpc",
    "headers": {
      "Authorization": ("Bearer " + $pat)
    },
    "enabled": true
  }
  | .plugin = (.plugin // [])
  | if (.plugin | index("fenix-opencode")) then . else .plugin += ["fenix-opencode"] end
')

mkdir -p ~/.config/opencode
echo "$CONFIG" | jq '.' > ~/.config/opencode/opencode.json
```

This configures:
- **Fenix MCP server** — connects to `fenix-mcp.devshire.app` with your PAT
- **fenix-opencode plugin** — registers 5 specialized agents (Fenix, Plan, Build, Review, Deliver)

## Step 4: Confirm

Tell the user:

> Fenix is configured for OpenCode!
>
> **What was set up:**
> - Fenix MCP server connected (fenix-mcp.devshire.app)
> - fenix-opencode plugin installed — 5 specialized agents:
>   - **Fenix** — orchestrator (detects phase, delegates)
>   - **Fenix Plan** — product and technical planning
>   - **Fenix Build** — TDD implementation
>   - **Fenix Review** — code review with context
>   - **Fenix Deliver** — delivery and documentation
> - 10 workflow skills available from the Fenix marketplace (no seed needed)
> - User context auto-loads at the start of every conversation
>
> **Restart OpenCode** to activate. You'll see the Fenix agents in the agent picker (Ctrl+T).
