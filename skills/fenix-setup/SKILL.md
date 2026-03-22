---
name: fenix-setup
description: First-time setup for the Fenix plugin. Guides the user through connecting their Fenix account via OAuth (default) or PAT (for CLI/CI/CD). Handles multi-tenant setups with per-project MCP configuration.
---

# Fenix Setup

This skill guides you through connecting the Fenix plugin to the user's Fenix account.

## How Authentication Works

Fenix supports two authentication methods:

1. **OAuth 2.1** (default for interactive use) — The plugin's `.mcp.json` points to `https://fenix-mcp.devshire.app/mcp`. When Claude Code or Claude Desktop connects, the OAuth flow triggers automatically: browser opens → login → select team → approve → done.

2. **PAT (Personal Access Token)** — Fallback for CI/CD pipelines and headless environments where a browser isn't available.

## Scenario A: OAuth (Recommended)

If the user is using Claude Code or Claude Desktop interactively:

1. The `.mcp.json` is already included in the plugin — no configuration needed.
2. On first tool call, the MCP server returns a 401 with a `WWW-Authenticate` header.
3. Claude automatically opens the browser for the OAuth consent flow.
4. The user logs in at Fenix, selects a team, and approves.
5. Done — tokens are cached automatically.

Tell the user:

> Fenix uses OAuth for authentication. The first time you use a Fenix tool, your browser will open for login.
>
> **No setup required!** Just start using Fenix tools and the auth flow will trigger automatically.
>
> If you're in a CI/CD or headless environment, say "I need PAT setup" and I'll guide you through it.

### Multi-Team / Multi-Project OAuth

Each project directory can have its own OAuth session with a different team:

- Token is scoped to the team selected during consent.
- To switch teams, the user can revoke and re-authenticate.
- Different project directories maintain separate OAuth sessions.

## Scenario B: PAT (CI/CD / Headless)

If the user explicitly asks for PAT setup or is in a headless environment:

### Step 1: Detect Plugin Scope

Run this command to find where the Fenix plugin is installed:

```bash
echo "LOCAL:" && cat .claude/settings.local.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null; echo "PROJECT:" && cat .claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null; echo "GLOBAL:" && cat ~/.claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null
```

Determine the scope:

- If fenix appears in **local** or **project** → plugin is installed **per-project**
- If fenix appears in **global** → plugin is installed **globally**
- If none found → default to **global**

### Step 2: Ask for the PAT

Say this to the user:

> To connect Fenix via PAT, I need your Personal Access Token.
>
> You can generate one at: **https://fenix.devshire.app** → Settings → API → Generate Token
>
> Paste your PAT here:

Wait for the user to provide the token. It will look like `fnx_XXXXXXXX.XXXXXXXX` (or `pat_XXXXXXXX.XXXXXXXX` for older tokens).

### Step 3: Validate the PAT

Run this command to validate the token against the Fenix API:

```bash
curl -s -w "\n%{http_code}" -H "Authorization: Bearer {PAT}" https://fenix-api.devshire.app/api/auth/profile
```

- If HTTP 200: the PAT is valid. Extract the user name and tenant from the response.
- If HTTP 401/403: the PAT is invalid. Ask the user to check and try again.
- If connection error: Fenix API may be down. Ask the user to try later.

### Step 4: Configure MCP Server

<EXTREMELY_IMPORTANT>
The MCP configuration depends on the detected scope from Step 1.

### If Per-Project scope (local or project):

First, remove any existing fenix-mcp at local scope:

```bash
claude mcp remove fenix-mcp -s local 2>/dev/null; echo "ready"
```

Then add the MCP server with PAT:

```bash
claude mcp add fenix-mcp "https://fenix-mcp.devshire.app/mcp" -t http -s local -H "Authorization: Bearer {PAT}"
```

### If Global scope:

First, remove any existing fenix-mcp at user scope:

```bash
claude mcp remove fenix-mcp -s user 2>/dev/null; echo "ready"
```

Then add the MCP server with PAT:

```bash
claude mcp add fenix-mcp "https://fenix-mcp.devshire.app/mcp" -t http -s user -H "Authorization: Bearer {PAT}"
```

Note: The endpoint is now `/mcp` (not `/jsonrpc`). The old `/jsonrpc` endpoint still works but is deprecated.
</EXTREMELY_IMPORTANT>

### Step 5: Verify Connection

After configuring, reload plugins and verify:

```bash
claude mcp list 2>/dev/null || echo "check /mcp in Claude Code"
```

Tell the user:

> **Reload the plugin to activate the MCP connection:**
>
> Run `/reload-plugins` — or if the MCP doesn't connect, open `/plugin` → **Installed** → **fenix** → **fenix-mcp** → **Reconnect**

### Step 6: Confirm Setup

After the MCP is connected, tell the user:

> Fenix is connected! Authenticated as **{user name}** ({tenant name}).
> MCP configured at **{scope}** level with PAT authentication.
>
> Start a **new conversation** to activate the full workflow.

## Error Handling

- If `jq` is not installed: tell the user to install it (`brew install jq` / `sudo apt install jq`)
- If `claude mcp add` fails with "already exists": run `claude mcp remove fenix-mcp -s local` first, then retry
- If the PAT format looks wrong (doesn't start with `fnx_` or `pat_`): warn but still try to validate
- If `/reload-plugins` doesn't pick up the MCP: tell user to open a new session
