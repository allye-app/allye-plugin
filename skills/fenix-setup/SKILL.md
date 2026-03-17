---
name: fenix-setup
description: First-time setup for the Fenix plugin. Guides the user through connecting their Fenix account by providing a Personal Access Token (PAT). Auto-detects plugin scope for multi-tenant setups.
---

# Fenix Setup

This skill guides you through connecting the Fenix plugin to the user's Fenix account.

## What you need to do

1. Detect where the plugin is installed (scope)
2. Ask the user for their **Fenix Personal Access Token (PAT)**
3. Validate the PAT
4. Save the PAT to the correct settings file
5. Confirm the setup is complete

## Step 1: Detect Plugin Scope

Run this command to find where the Fenix plugin is installed:

```bash
echo "=== Checking plugin scope ===" && LOCAL=$(cat .claude/settings.local.json 2>/dev/null | jq -r '.enabledPlugins // {} | keys[]' 2>/dev/null | grep -c fenix) && PROJECT=$(cat .claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {} | keys[]' 2>/dev/null | grep -c fenix) && GLOBAL=$(cat ~/.claude/settings.json 2>/dev/null | jq -r '.enabledPlugins // {} | keys[]' 2>/dev/null | grep -c fenix) && echo "local=$LOCAL project=$PROJECT global=$GLOBAL"
```

Determine the scope based on the results:

- If `local > 0` → plugin is installed **locally** in this project → save PAT to `.claude/settings.local.json`
- If `project > 0` → plugin is installed at **project** level → save PAT to `.claude/settings.json`
- If `global > 0` → plugin is installed **globally** → save PAT to `~/.claude/settings.json`
- If none found → default to **global** (`~/.claude/settings.json`)

Also check if a PAT already exists at the detected scope:

```bash
EXISTING_PAT=$(cat {DETECTED_SETTINGS_FILE} 2>/dev/null | jq -r '.env.FENIX_PAT // "not set"')
echo "Existing PAT: $EXISTING_PAT"
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

## Step 4: Save the PAT

<EXTREMELY_IMPORTANT>
Save the PAT to the settings file that matches the detected scope from Step 1.

### If Local scope (`.claude/settings.local.json`):

```bash
mkdir -p .claude
SETTINGS=$(cat .claude/settings.local.json 2>/dev/null || echo '{}')
SETTINGS=$(echo "$SETTINGS" | jq --arg pat "{PAT}" '.env = (.env // {}) | .env.FENIX_PAT = $pat')
echo "$SETTINGS" | jq '.' > .claude/settings.local.json
```

### If Project scope (`.claude/settings.json`):

```bash
mkdir -p .claude
SETTINGS=$(cat .claude/settings.json 2>/dev/null || echo '{}')
SETTINGS=$(echo "$SETTINGS" | jq --arg pat "{PAT}" '.env = (.env // {}) | .env.FENIX_PAT = $pat')
echo "$SETTINGS" | jq '.' > .claude/settings.json
```

### If Global scope (`~/.claude/settings.json`):

```bash
SETTINGS=$(cat ~/.claude/settings.json 2>/dev/null || echo '{}')
SETTINGS=$(echo "$SETTINGS" | jq --arg pat "{PAT}" '.env = (.env // {}) | .env.FENIX_PAT = $pat')
echo "$SETTINGS" | jq '.' > ~/.claude/settings.json
```

The PAT is saved as `FENIX_PAT` env var, which the MCP server uses for authentication.
Note: `.claude/settings.local.json` is automatically gitignored by Claude Code.
</EXTREMELY_IMPORTANT>

## Step 5: Confirm Setup

After saving, tell the user:

> Fenix is connected! Authenticated as **{user name}** ({tenant name}).
> PAT saved at **{scope}** level ({settings file path}).
>
> Start a new conversation to activate the full workflow — or just keep working here.
>
> **What you can do now:**
> - Plan product features (epics, stories)
> - Break stories into tasks with discussion phase
> - Implement with TDD discipline
> - Track progress on boards
> - Save and search memories for cross-session continuity

If saved at local/project scope, also mention:

> **Note:** This PAT applies only in this directory. Other projects will use the global PAT (if configured). Run `/fenix-setup` in each project that uses a different Fenix tenant.

## Error Handling

- If `jq` is not installed: tell the user to install it (`brew install jq` / `sudo apt install jq`)
- If settings file doesn't exist: create it with `{}`
- If the PAT format looks wrong (doesn't start with `fnx_` or `pat_`): warn but still try to validate — the format may change
- If `.claude/` directory doesn't exist for local/project scope: create it with `mkdir -p .claude`
