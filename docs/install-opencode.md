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

## Step 3: Configure MCP Server

Read the current OpenCode global config:

```bash
cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{}'
```

Add the Fenix MCP server. Write the updated config using `jq`, replacing `{PAT}` with the actual token:

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
')

mkdir -p ~/.config/opencode
echo "$CONFIG" | jq '.' > ~/.config/opencode/opencode.json
```

## Step 4: Install Custom Agent

Create the Fenix agent file for OpenCode:

```bash
mkdir -p ~/.config/opencode/agents
```

Write the following content to `~/.config/opencode/agents/fenix.md`:

```markdown
---
name: fenix
description: Fenix workflow agent — structured planning, TDD development, memory protocol, and board progression.
---

# Fenix Agent

You have access to the **Fenix platform** via MCP. Before starting any work:

1. **Search memories** — Run `memory_search` for session state, decisions, and context
2. **Detect the workflow phase** — What does the user need?
3. **Load the right skill** — Use `skill_list` to find and read the appropriate workflow skill
4. **Save memories** — Before the conversation ends, save session state

## Workflow Skills

| User Intent | Skill Slug |
|-------------|------------|
| Define requirements, create epics/features/stories | `fenix-product-planning` |
| Plan tasks for a story, discuss approach | `fenix-technical-planning` |
| Implement code, write tests | `fenix-technical-development` |
| Review code quality | `fenix-technical-review` |
| Finalize delivery, close story | `fenix-technical-delivery` |

## Non-Negotiable Rules

1. **No implementation without tasks.** Plan first, always.
2. **No skipping the discussion phase.** Identify gray areas, present options, capture decisions.
3. **No status changes without work.** "Almost done" is not done.
4. **TDD when applicable.** If you can write the test first, you must.
5. **Memory first.** Always search at start, always save at end.

## Reference Skills

- `fenix-memory-protocol` — When and how to save/search memories
- `fenix-tdd-workflow` — Red-Green-Refactor discipline
- `fenix-board-progression` — How to move items between statuses
- `fenix-tools-quickref` — Complete MCP tools reference
```

## Step 5: Seed Skills into Fenix

### Handle multi-team users

First, validate the PAT response from Step 2. If the user belongs to **multiple teams**, ask:

> You belong to multiple teams:
> - {team 1 name} ({team 1 prefix})
> - {team 2 name} ({team 2 prefix})
>
> Do you want to seed the skills to **all teams** or just one specific team?

- If **all teams**: run the seed loop once for each team, passing the respective `team_id`
- If **one team**: ask which team, then seed only to that one

### Clone and seed

Clone the plugin repo:

```bash
PLUGIN_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/fenix-assistant/fenix-plugin.git "$PLUGIN_DIR"
```

Read the seed file:

```bash
cat "$PLUGIN_DIR/seed/seed-skills.json"
```

For each team being seeded, and for each skill in the `skills` array, read the source file content and create the skill:

```
Action: skill_create
skill_name: {name from seed}
skill_category: {category from seed}
skill_description: {description from seed}
skill_content: {content read from source_file}
skill_scope: team
team_id: {team uuid}
```

If a skill already exists (check with `skill_list` first), use `skill_update` instead.

Clean up after seeding:

```bash
rm -rf "$PLUGIN_DIR"
```

## Step 6: Confirm

Tell the user:

> Fenix is configured for OpenCode!
>
> **What was set up:**
> - Fenix MCP server connected (fenix-mcp.devshire.app)
> - Fenix agent installed (~/.config/opencode/agents/fenix.md)
> - 10 workflow skills seeded into your Fenix database
>
> **Restart OpenCode** to activate the plugin. Then you can:
> - Plan product features (epics, stories)
> - Break stories into tasks with discussion phase
> - Implement with TDD discipline
> - Track progress on boards
> - Save and search memories for cross-session continuity
