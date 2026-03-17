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
4. Configure MCP server at the correct scope
5. Confirm the setup is complete

## Step 1: Detect Plugin Scope

Run this command to find where the Fenix plugin is installed:

```bash
echo "LOCAL:" && cat .claude/settings.local.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null; echo "PROJECT:" && cat .claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null; echo "GLOBAL:" && cat ~/.claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null
```

Determine the scope:

- If fenix appears in **local** or **project** → plugin is installed **per-project**
- If fenix appears in **global** → plugin is installed **globally**
- If none found → default to **global**

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

## Step 4: Configure MCP Server

<EXTREMELY_IMPORTANT>
The MCP configuration depends on the detected scope from Step 1.

### If Per-Project scope (local or project):

Use the `claude mcp add` command with `--scope local`. This registers the MCP server in `~/.claude.json` linked to the current project directory. Each project can have a different PAT for different Fenix tenants.

First, remove any existing fenix-mcp at local scope (in case of reconfiguration):

```bash
claude mcp remove fenix-mcp -s local 2>/dev/null; echo "ready"
```

Then add the MCP server:

```bash
claude mcp add fenix-mcp "https://fenix-mcp.devshire.app/jsonrpc" -t http -s local -H "Authorization: Bearer {PAT}"
```

This stores the MCP config in `~/.claude.json` under the current project path. It is:
- **Not committed to git** — lives in the user's home directory
- **Per-project** — different projects can have different PATs
- **Persistent** — survives plugin updates (not in plugin cache)

### If Global scope:

Use the `claude mcp add` command with `--scope user`. This registers the MCP server globally for all projects.

First, remove any existing fenix-mcp at user scope (in case of reconfiguration):

```bash
claude mcp remove fenix-mcp -s user 2>/dev/null; echo "ready"
```

Then add the MCP server:

```bash
claude mcp add fenix-mcp "https://fenix-mcp.devshire.app/jsonrpc" -t http -s user -H "Authorization: Bearer {PAT}"
```

This applies to all projects that don't have a local MCP override.

Also save PAT as env var for the SessionStart hook:

```bash
SETTINGS=$(cat ~/.claude/settings.json 2>/dev/null || echo '{}')
SETTINGS=$(echo "$SETTINGS" | jq --arg pat "{PAT}" '.env = (.env // {}) | .env.FENIX_PAT = $pat')
echo "$SETTINGS" | jq '.' > ~/.claude/settings.json
```
</EXTREMELY_IMPORTANT>

## Step 5: Verify Connection

After configuring, reload plugins and verify:

```bash
claude mcp list 2>/dev/null || echo "check /mcp in Claude Code"
```

Tell the user:

> **Reload the plugin to activate the MCP connection:**
>
> Run `/reload-plugins` — or if the MCP doesn't connect, open `/plugin` → **Installed** → **fenix** → **fenix-mcp** → **Reconnect**

Wait for the user to confirm it's connected.

## Step 6: Confirm Setup

After the MCP is connected, tell the user:

> Fenix is connected! Authenticated as **{user name}** ({tenant name}).
> MCP configured at **{scope}** level.
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
> Other projects will use the global MCP (if configured).
> Run `/fenix-setup` in each project that uses a different Fenix tenant.

## Error Handling

- If `jq` is not installed: tell the user to install it (`brew install jq` / `sudo apt install jq`)
- If `claude mcp add` fails with "already exists": run `claude mcp remove fenix-mcp -s local` first, then retry
- If the PAT format looks wrong (doesn't start with `fnx_` or `pat_`): warn but still try to validate
- If `/reload-plugins` doesn't pick up the MCP: tell user to open a new session
