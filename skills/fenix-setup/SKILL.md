---
name: fenix-setup
description: First-time setup for the Fenix plugin. Guides the user through connecting their Fenix account by providing a Personal Access Token (PAT).
---

# Fenix Setup

This skill guides you through connecting the Fenix plugin to the user's Fenix account.

## What you need to do

1. Ask the user for their **Fenix Personal Access Token (PAT)**
2. Validate the PAT
3. Save it to Claude Code's environment configuration
4. Confirm the setup is complete

## Step 1: Ask for the PAT

Say this to the user:

> To connect Fenix, I need your Personal Access Token (PAT).
>
> You can generate one at: **https://fenix.devshire.app** → Settings → API → Generate Token
>
> Paste your PAT here:

Wait for the user to provide the token. It will look like `fnx_XXXXXXXX.XXXXXXXX` (or `pat_XXXXXXXX.XXXXXXXX` for older tokens).

## Step 2: Validate the PAT

Run this command to validate the token against the Fenix API:

```bash
curl -s -w "\n%{http_code}" -H "Authorization: Bearer {PAT}" https://fenix-api.devshire.app/api/auth/profile
```

- If HTTP 200: the PAT is valid. Extract the user name and tenant from the response.
- If HTTP 401/403: the PAT is invalid. Ask the user to check and try again.
- If connection error: Fenix API may be down. Ask the user to try later.

## Step 3: Save the PAT

<EXTREMELY_IMPORTANT>
Save the PAT to Claude Code's user-level settings so it persists across sessions.
The PAT must be set as the environment variable `FENIX_PAT`.

Run this command:
```bash
# Read current settings
SETTINGS=$(cat ~/.claude/settings.json 2>/dev/null || echo '{}')

# Add FENIX_PAT to env
SETTINGS=$(echo "$SETTINGS" | jq --arg pat "{PAT}" '.env = (.env // {}) | .env.FENIX_PAT = $pat')

# Write back
echo "$SETTINGS" | jq '.' > ~/.claude/settings.json
```

This ensures the PAT is available to both the Fenix MCP server and the SessionStart hook.
</EXTREMELY_IMPORTANT>

## Step 4: Confirm Setup

After saving, tell the user:

> Fenix is connected! Authenticated as **{user name}** ({tenant name}).
>
> The Fenix MCP server and plugin are now configured. Start a new conversation to activate the full workflow — or just keep working here.
>
> **What you can do now:**
> - Plan product features (epics, stories)
> - Break stories into tasks with discussion phase
> - Implement with TDD discipline
> - Track progress on boards
> - Save and search memories for cross-session continuity

## Error Handling

- If `jq` is not installed: tell the user to install it (`brew install jq` / `sudo apt install jq`)
- If `~/.claude/settings.json` doesn't exist: create it with `{}`
- If the PAT format looks wrong (doesn't start with `fnx_` or `pat_`): warn but still try to validate — the format may change
