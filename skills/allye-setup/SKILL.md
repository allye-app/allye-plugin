---
name: allye-setup
description: First-time setup for the Allye plugin. Uses OAuth for ALL platforms — no PAT.
---

# Allye Setup

<EXTREMELY_IMPORTANT>
## Allye ALWAYS uses OAuth. Never ask for a PAT.

The setup flow depends on whether the platform supports native MCP OAuth:

- **Claude Code / Claude Desktop** → OAuth is automatic via `.mcp.json`. No setup needed.
- **All other platforms** (OpenCode, Cursor, Codex, Gemini, etc.) → Run the OAuth browser login script.

**NEVER ask the user for a PAT. NEVER mention PAT as an option.**
</EXTREMELY_IMPORTANT>

## Step 1: Detect Platform

Check which platform/agent is running. You can infer this from:
- The environment (Claude Code has `CLAUDE_CODE` env, Claude Desktop has specific hooks)
- The available tools and context
- Or simply ask: "Which platform are you using?"

## Step 2A: Claude Code / Claude Desktop (Native OAuth)

If the user is on Claude Code or Claude Desktop:

> **Allye is already configured!** The plugin's `.mcp.json` handles OAuth automatically.
>
> The first time you use a Allye tool, your browser will open for login.
> Just start using Allye — try asking me to search memories or list work items.

**Stop here. No further setup needed.**

## Step 2B: Other Platforms (OAuth via Browser Login Script)

For OpenCode, Cursor, Codex, Gemini, or any platform without native MCP OAuth:

Tell the user:

> I'll run the Allye OAuth login to connect your account via browser.

### Run the OAuth login script:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/oauth-login.sh"
```

If `CLAUDE_PLUGIN_ROOT` is not set, find the script:

```bash
SCRIPT=$(find ~/.claude/plugins -name "oauth-login.sh" -path "*/allye*" 2>/dev/null | head -1) || SCRIPT=$(find . -name "oauth-login.sh" 2>/dev/null | head -1); echo "$SCRIPT"
```

Then run it:

```bash
bash "$SCRIPT"
```

The script will:
1. Open the browser for Allye OAuth login
2. Start a local callback server on port 9316
3. After the user logs in and selects a team, capture the authorization code
4. Exchange the code for tokens
5. Output `ALLYE_ACCESS_TOKEN=...` and `ALLYE_REFRESH_TOKEN=...`

### Configure the platform with the obtained token:

**For OpenCode:**
The `opencode.json` manifest uses `${ALLYE_ACCESS_TOKEN}`. Set the env var:

```bash
export ALLYE_ACCESS_TOKEN="<the token from the script>"
```

Or update `opencode.json` directly with the token.

**For Cursor:**
Add MCP server in Cursor settings (Settings → MCP Servers):
- Name: `allye-mcp`
- URL: `https://allye-mcp.devshire.app/mcp`
- Headers: `Authorization: Bearer <token>`

**For other platforms:**
Configure the MCP connection with:
- URL: `https://allye-mcp.devshire.app/mcp`
- Authorization header: `Bearer <token>`

### Confirm setup:

> **Allye connected via OAuth!**
>
> Start a new session to activate the Allye tools.

## Token Refresh

OAuth tokens expire. When a token expires:
- **Claude Code/Desktop**: Automatic refresh via OAuth flow
- **Other platforms**: Run the login script again: `bash scripts/oauth-login.sh`

## Error Handling

- `python3` not found → Required for the OAuth callback server. Install Python 3.
- `openssl` not found → Required for PKCE. Install OpenSSL.
- Browser doesn't open → Copy the URL from the terminal and open manually.
- Port 9316 in use → Run with a different port: `bash scripts/oauth-login.sh 9317`
- `jq` not found → `brew install jq` / `sudo apt install jq`
