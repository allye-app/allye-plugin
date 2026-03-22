---
name: fenix-setup
description: First-time setup for the Fenix plugin. OAuth is the default — no PAT needed for interactive use. PAT is only for CI/CD.
---

# Fenix Setup

<EXTREMELY_IMPORTANT>
## DEFAULT BEHAVIOR: OAuth (No Setup Needed)

If the user runs `/fenix-setup` interactively (Claude Code or Claude Desktop):

**DO NOT ask for a PAT. DO NOT run scope detection. DO NOT start the PAT flow.**

Instead, tell the user exactly this:

> **Fenix uses OAuth — no setup required!**
>
> The plugin's `.mcp.json` is already configured. The first time you use a Fenix tool,
> your browser will open automatically for login.
>
> Just start a new conversation and use any Fenix tool (e.g., ask me to search memories
> or list work items). The OAuth flow will trigger on the first request.
>
> If you're in a **CI/CD pipeline or headless environment** where a browser isn't available,
> say **"I need PAT setup"** and I'll guide you through manual configuration.

**Then stop. Do not proceed further unless the user explicitly says they need PAT setup.**
</EXTREMELY_IMPORTANT>

## How OAuth Works (for context)

1. The plugin includes `.mcp.json` pointing to `https://fenix-mcp.devshire.app/mcp`
2. When Claude Code calls an MCP tool, the server returns 401 with `WWW-Authenticate` header
3. Claude Code automatically opens the browser for the OAuth consent flow
4. User logs in at Fenix, selects a team, approves
5. Tokens are cached — subsequent requests work without re-authentication

### Multi-Team / Multi-Project

- Each project directory maintains its own OAuth session
- Token is scoped to the team selected during consent
- To switch teams, revoke and re-authenticate

---

## PAT Setup (Only When User Explicitly Requests It)

Only proceed with this section if the user says something like:
- "I need PAT setup"
- "I'm in CI/CD"
- "I can't open a browser"
- "headless environment"

### Step 1: Detect Plugin Scope

Run this command to find where the Fenix plugin is installed:

```bash
echo "LOCAL:" && cat .claude/settings.local.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null; echo "PROJECT:" && cat .claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null; echo "GLOBAL:" && cat ~/.claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {}' 2>/dev/null
```

- If fenix appears in **local** or **project** → per-project scope
- If fenix appears in **global** → global scope
- If none found → default to **global**

### Step 2: Ask for the PAT

> To connect Fenix via PAT, I need your Personal Access Token.
>
> Generate one at: **https://fenix.devshire.app** → Settings → API → Generate Token
>
> Paste your PAT here:

Token format: `fnx_XXXXXXXX.XXXXXXXX` or `pat_XXXXXXXX.XXXXXXXX`

### Step 3: Validate the PAT

```bash
curl -s -w "\n%{http_code}" -H "Authorization: Bearer {PAT}" https://fenix-api.devshire.app/api/auth/profile
```

- HTTP 200: valid — extract user name and tenant
- HTTP 401/403: invalid — ask user to retry
- Connection error: API may be down

### Step 4: Configure MCP Server

**Per-Project scope:**

```bash
claude mcp remove fenix-mcp -s local 2>/dev/null; echo "ready"
claude mcp add fenix-mcp "https://fenix-mcp.devshire.app/mcp" -t http -s local -H "Authorization: Bearer {PAT}"
```

**Global scope:**

```bash
claude mcp remove fenix-mcp -s user 2>/dev/null; echo "ready"
claude mcp add fenix-mcp "https://fenix-mcp.devshire.app/mcp" -t http -s user -H "Authorization: Bearer {PAT}"
```

### Step 5: Verify and Confirm

```bash
claude mcp list 2>/dev/null || echo "check /mcp in Claude Code"
```

> Fenix connected! Authenticated as **{user name}** ({tenant name}).
> MCP configured at **{scope}** level with PAT authentication.
>
> Start a **new conversation** to activate.

## Error Handling

- `jq` not installed → `brew install jq` / `sudo apt install jq`
- `claude mcp add` fails → remove first, then retry
- PAT format wrong → warn but still validate
- `/reload-plugins` doesn't work → open new session
