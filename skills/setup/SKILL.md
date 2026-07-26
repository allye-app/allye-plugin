---
name: setup
description: First-time setup for the Allye plugin. Uses OAuth for ALL platforms — no PAT.
version: "1.2"
category: bootstrap
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
- URL: `https://mcp.allye.app/mcp`
- Headers: `Authorization: Bearer <token>`

**For other platforms:**
Configure the MCP connection with:
- URL: `https://mcp.allye.app/mcp`
- Authorization header: `Bearer <token>`

### Confirm setup:

> **Allye connected via OAuth!**
>
> Start a new session to activate the Allye tools.

## Step 3: Delivery configuration

Ask once, here, rather than at every dispatch. Five parallel stories would otherwise mean
ten identical questions whose answer never varies.

Check whether it already exists before asking anything:

```
user_config(action: "list")
```

If a document named `Allye Delivery Configuration` is present, show it and ask whether to
change it. Otherwise, ask the questions below — one at a time — and create it.

**Question 1 — which agent runs which phase?** Offer the phases that can differ (planning,
technical planning, execution, review, correction) and let the user assign an agent kind to
each. The default is the agent they are running now, for every phase; accepting that default
is a completely reasonable answer and should take one word.

**Question 2 — what arguments does each agent need?** Model selection is not uniform: what
is `--model sonnet --permission-mode auto` for one agent is different syntax for the next.
Store the argument string verbatim; it is passed through unchanged.

**Question 3 — per repo, what is the base branch, and which gitignored files must a fresh
worktree receive?** A worktree inherits neither, and an executor that fails on a missing
`.env` reports a bug that is not one.

**Question 4 — who satisfies each stage after review?** Only ask this when the team's pipeline
has stages between the review gate and done: run `work_statuses()` and look. A Solo or Startup
board goes straight from review to done and needs nothing here — **skip the question entirely
rather than asking it and recording an empty table.**

Where there are stages, offer three answers per stage:

- **`agent`** — the Orchestrator satisfies it and advances. Needs a command, the same way a task
  needs one (`verification-loop` §1): red-capable, deterministic, fast, agent-runnable.
- **`ci`** — an external system satisfies it. Record how to read the result; the Orchestrator
  waits rather than acting.
- **`human`** — the Orchestrator stops and hands over.

Lead with a recommendation so accepting takes one word: scans and automated test suites are
usually `agent` or `ci`; anything that deploys, or that validates in a deployed environment, is
`human` unless the team says otherwise.

Create it:

```
user_config(
  action: "create",
  name: "Allye Delivery Configuration",
  content: "{the document below}"
)
```

Note the field is `name`, not `title` — this is the one tool in the suite that differs.

### Document format

```markdown
# Allye Delivery Configuration

## Phase routing

| Phase | Agent kind | Native args |
|---|---|---|
| product-planning | claude | --model sonnet --permission-mode auto |
| technical-planning | claude | --model sonnet --permission-mode auto |
| execution | opencode | |
| review | claude | --model sonnet --permission-mode auto |
| correction | opencode | |

## Repositories

| Repo | Base branch | Install command | Copy into a fresh worktree |
|---|---|---|---|
| allye-plugin | main | | |
| allye-api | develop | bun install | .env |

## Concurrency

Default parallel stories: 3

## Pipeline handoff

| Status | Satisfied by | Command or signal |
|---|---|---|
| security_scan | agent | just security-scan |
| qa_testing | agent | just test:e2e |
| deploy_staging | ci | GitHub Actions `deploy-staging` |
| deploy_prod | human | |

An unmapped status means **`human`**. Stopping is the safe default: an agent that advances
past a gate nobody told it about has claimed work passed a check that never ran.

Omit this section entirely when the pipeline runs straight from review to done.
```

An empty cell means "nothing required" — leave it empty rather than writing "none", so the
table stays scannable.

### Preflight before routing a phase to a non-Claude agent

A dispatched agent that cannot reach Allye cannot read the story, move a status, or save the
memory the Orchestrator collects its result from — the dispatch will appear to succeed and
produce nothing. Before recording a non-Claude agent for any phase, confirm that agent has
Allye configured: the MCP connection, and for OpenCode the `allye-opencode` package. If it
does not, say so and point at the matching guide in `docs/install-*.md` rather than recording
a route that will fail on first use.

Platform capability also constrains the map. OpenCode has six agent personas; Cursor, Codex,
and Gemini CLI have one agent and no picker — routing a specific persona to them silently
does nothing.

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
