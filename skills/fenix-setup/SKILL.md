---
name: fenix-setup
description: First-time setup for the Fenix plugin. Guides the user through connecting their Fenix account by providing a Personal Access Token (PAT). Handles multi-tenant setups with per-project MCP configuration.
---

# Fenix Setup

This skill guides you through connecting the Fenix plugin to the user's Fenix account.

## What you need to do

1. Detect where the plugin is installed (scope)
2. Ask the user for their **Fenix Personal Access Token (PAT)**
3. Validate the PAT
4. Configure MCP server + save PAT at the correct scope
5. Confirm the setup is complete

## Step 1: Detect Plugin Scope

Run this command to find where the Fenix plugin is installed:

```bash
echo "=== Checking plugin scope ===" && LOCAL=$(cat .claude/settings.local.json 2>/dev/null | jq -r '.enabledPlugins // {} | keys[]' 2>/dev/null | grep -c fenix) && PROJECT=$(cat .claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {} | keys[]' 2>/dev/null | grep -c fenix) && GLOBAL=$(cat ~/.claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {} | keys[]' 2>/dev/null | grep -c fenix) && echo "local=$LOCAL project=$PROJECT global=$GLOBAL"
```

Determine the scope:

- If `local > 0` or `project > 0` → plugin is installed **per-project** → save PAT + MCP locally
- If `global > 0` → plugin is installed **globally** → save PAT + MCP globally
- If none found → default to **global**

Also check if a PAT already exists:

```bash
echo "=== Existing PAT ===" && echo "Local: $(cat .claude/settings.local.json 2>/dev/null | jq -r '.env.FENIX_PAT // "not set"')" && echo "Global: $(cat ~/.claude/settings.json 2>/dev/null | jq -r '.env.FENIX_PAT // "not set"')"
```

If a PAT already exists, inform the user and ask if they want to replace it.

## Step 2: Ask for the PAT

Say this to the user:

> To connect Fenix, I need your Personal Access Token (PAT).
>
> You can generate one at: **https://fenix.devshire.app** → Settings → API → Generate Token
>
> Paste your PAT here:

Wait for the user to provide the token. It will look like `fnx_XXXXXXXX.XXXXXXXX` (or `pat_XXXXXXXX.XXXXXXXX` for older tokens).

## Step 3: Validate the PAT

Run this command to validate the token against the Fenix API:

```bash
curl -s -w "\n%{http_code}" -H "Authorization: Bearer {PAT}" https://fenix-api.devshire.app/api/auth/profile
```

- If HTTP 200: the PAT is valid. Extract the user name and tenant from the response.
- If HTTP 401/403: the PAT is invalid. Ask the user to check and try again.
- If connection error: Fenix API may be down. Ask the user to try later.

## Step 4: Configure MCP + Save PAT

<EXTREMELY_IMPORTANT>
There are TWO things to configure:
1. **The MCP server** — so Claude Code can connect to Fenix
2. **The PAT as env var** — so the MCP server can authenticate

### Why both are needed

The plugin ships a `.mcp.json` with `${FENIX_PAT}`, but due to a known Claude Code limitation (GitHub #9427), env var expansion in plugin `.mcp.json` files may not work correctly. The fix is to create a project-level `.mcp.json` that takes precedence over the plugin's.

### If Per-Project scope (local or project):

**Step 4a: Create project-level `.mcp.json`**

Check if `.mcp.json` already exists at the project root:

```bash
cat .mcp.json 2>/dev/null | jq '.mcpServers["fenix-mcp"]' 2>/dev/null || echo "not found"
```

If it doesn't exist or doesn't have `fenix-mcp`, create/update it:

```bash
MCP_CONFIG=$(cat .mcp.json 2>/dev/null || echo '{}')
MCP_CONFIG=$(echo "$MCP_CONFIG" | jq '
  .mcpServers["fenix-mcp"] = {
    "type": "http",
    "url": "https://fenix-mcp.devshire.app/jsonrpc",
    "headers": {
      "Authorization": "Bearer ${FENIX_PAT}"
    }
  }
')
echo "$MCP_CONFIG" | jq '.' > .mcp.json
```

This `.mcp.json` uses `${FENIX_PAT}` which is resolved from the settings file below. It's safe to commit — no secrets, just a variable reference.

**Step 4b: Save PAT to `.claude/settings.local.json`**

```bash
mkdir -p .claude
SETTINGS=$(cat .claude/settings.local.json 2>/dev/null || echo '{}')
SETTINGS=$(echo "$SETTINGS" | jq --arg pat "{PAT}" '.env = (.env // {}) | .env.FENIX_PAT = $pat')
echo "$SETTINGS" | jq '.' > .claude/settings.local.json
```

Note: `.claude/settings.local.json` is automatically gitignored by Claude Code — the PAT never enters git.

### If Global scope:

**Step 4a: Configure MCP in `~/.claude.json`**

```bash
CLAUDE_JSON=$(cat ~/.claude.json 2>/dev/null || echo '{}')
CLAUDE_JSON=$(echo "$CLAUDE_JSON" | jq --arg pat "{PAT}" '
  .mcpServers["fenix-mcp"] = {
    "type": "http",
    "url": "https://fenix-mcp.devshire.app/jsonrpc",
    "headers": {
      "Authorization": ("Bearer " + $pat)
    }
  }
')
echo "$CLAUDE_JSON" | jq '.' > ~/.claude.json
```

Note: For global scope, the PAT is hardcoded in `~/.claude.json` because there's no env var resolution at this level. This file is never committed to git.

**Step 4b: Also save PAT as env var in `~/.claude/settings.json`**

```bash
SETTINGS=$(cat ~/.claude/settings.json 2>/dev/null || echo '{}')
SETTINGS=$(echo "$SETTINGS" | jq --arg pat "{PAT}" '.env = (.env // {}) | .env.FENIX_PAT = $pat')
echo "$SETTINGS" | jq '.' > ~/.claude/settings.json
```

This ensures the PAT is available as `FENIX_PAT` env var for the SessionStart hook and any project-level `.mcp.json` files.
</EXTREMELY_IMPORTANT>

## Step 5: Confirm Setup

After saving, tell the user:

> Fenix is connected! Authenticated as **{user name}** ({tenant name}).
> Configuration saved at **{scope}** level.
>
> **What was configured:**
> - MCP server: fenix-mcp.devshire.app
> - PAT saved as FENIX_PAT environment variable
>
> Start a **new conversation** to activate the full workflow.
>
> **What you can do now:**
> - Plan product features (epics, stories)
> - Break stories into tasks with discussion phase
> - Implement with TDD discipline
> - Track progress on boards
> - Save and search memories for cross-session continuity

If saved at per-project scope, also mention:

> **Multi-tenant note:** This PAT applies only in this directory ({cwd}).
> Other projects will use the global PAT (if configured).
> Run `/fenix-setup` in each project that uses a different Fenix tenant.

## Error Handling

- If `jq` is not installed: tell the user to install it (`brew install jq` / `sudo apt install jq`)
- If settings file doesn't exist: create it with `{}`
- If the PAT format looks wrong (doesn't start with `fnx_` or `pat_`): warn but still try to validate
- If `.claude/` directory doesn't exist: create it with `mkdir -p .claude`
- If `.mcp.json` already exists with other MCP servers: merge, don't overwrite — only add/update `fenix-mcp`
