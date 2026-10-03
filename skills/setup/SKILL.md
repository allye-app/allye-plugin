---
name: setup
description: First-time setup for the Allye plugin. Uses OAuth for ALL platforms — no PAT.
version: "1.3"
category: bootstrap
---

# Allye Setup

<EXTREMELY_IMPORTANT>
## Allye MCP always uses native OAuth

Configure one remote server named `allye` at `https://mcp.allye.app/mcp`. Let the
host runtime perform discovery, dynamic client registration, authorization-code
exchange, token storage, and refresh. Static bearer headers, PATs, fixed client
IDs, tenant-specific URLs, and external login helpers are not part of setup.
</EXTREMELY_IMPORTANT>

## Step 1: Detect the platform

Infer the current platform from the runtime when possible. Otherwise ask which
supported agent the user wants to configure.

## Step 2: Configure and authenticate one Allye entry

Preserve every unrelated server and credential. If an older Allye entry exists
under another name, identify its effective config source, remove only that
entry through the host's native management command, and keep only `allye`.

### Claude Code / Claude Desktop

The plugin's `.mcp.json` already declares `allye`. Open the MCP or plugin panel,
select **Allye**, and choose **Connect**. The browser completes consent.

For an intentional reconnect, use **Clear authentication** for Allye, then
**Authenticate/Connect**. Do not sign out of the host account.

### Codex

```bash
codex mcp get allye >/dev/null 2>&1 \
  || codex mcp add allye --url https://mcp.allye.app/mcp
codex mcp login allye
```

If a legacy Allye entry has a different name, use `codex mcp logout <old-name>`
and `codex mcp remove <old-name>` for that entry only before adding `allye`.

### OpenCode

Its effective `opencode.json` must contain:

```json
{
  "mcp": {
    "allye": {
      "type": "remote",
      "url": "https://mcp.allye.app/mcp",
      "enabled": true
    }
  }
}
```

Preserve the rest of the file, then authenticate and confirm:

```bash
opencode mcp auth allye
opencode mcp list
```

### Pi with pi-mcp-adapter

Use the effective MCP source shown by `/mcp` and define an `allye` remote server
at the canonical URL. The Allye repository installer does not write Pi's MCP
configuration.

Authenticate and connect in Pi:

```text
/mcp-auth allye
/mcp reconnect allye
```

Use `/reload` after changing the effective config source. `/mcp logout allye`
clears only Allye's native credential when the user explicitly requests a
reconnection.

### Other native MCP clients

Add a remote HTTP MCP server named `allye` at the canonical URL and use the
client's native OAuth action. Preserve unrelated configuration and credentials.

## Step 3: Confirm MCP access

Start or reload the host session, confirm the `allye` server is connected, and
invoke a read-only Allye tool. Tenant selection happens during consent; the URL
never contains a tenant slug.

## Step 4: Delivery configuration

Ask once, here, rather than at every dispatch. Five parallel specs would otherwise mean
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

**Question 4 — who satisfies each stage after review?** The task flow itself is fixed
(`todo → in_progress → in_review → done`), so ask the user whether anything outside it must
happen between review and `task_complete` (QA, a scan, a deploy). Most teams go straight from
review to done and need nothing here — **skip the question entirely when the answer is no,
rather than recording an empty table.**

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

Default parallel specs: 3

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

A dispatched agent that cannot reach Allye cannot read the spec, move a status, or save the
memory the Orchestrator collects its result from — the dispatch will appear to succeed and
produce nothing. Before recording a non-Claude agent for any phase, confirm that agent has
Allye configured: the MCP connection, and for OpenCode the `allye-opencode` package. If it
does not, say so and point at the matching guide in `docs/install-*.md` rather than recording
a route that will fail on first use.

Platform capability also constrains the map. OpenCode has six agent personas; Cursor, Codex,
and Gemini CLI have one agent and no picker — routing a specific persona to them silently
does nothing.

## Authentication lifecycle

The host runtime rotates access and refresh tokens automatically. A normal
restart, an HTTP 403 authorization result, or an HTTP 503 dependency failure
does not require clearing credentials or opening the browser.

An explicit grant revocation or the 90-day grant limit requires a new consent.
When the user intentionally reconnects, clear only the `allye` entry:

- **Claude Code/Desktop:** Allye → **Clear authentication** → **Authenticate/Connect**
- **Codex:** `codex mcp logout allye`, then `codex mcp login allye`
- **OpenCode:** `opencode mcp logout allye`, then `opencode mcp auth allye`
- **Pi:** `/mcp logout allye`, then `/mcp-auth allye` and `/mcp reconnect allye`
- **Other clients:** use the host's clear/reconnect action scoped to `allye`
