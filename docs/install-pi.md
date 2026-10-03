# Install Allye for Pi

The Pi adapter is a thin native Pi package. Installation/configuration is not
API authorization, release approval, publication, or distribution success. Official
distribution consumes only the API-authorized immutable release identity
(`skill_id`, `release_id`, `version`, canonical SHA-256 hash, and supplied origin); a revoked or
otherwise ineligible release remains blocked until the API returns matching physical
runtime evidence. It does not copy workflow skills or replace Pi's MCP configuration:

- `skills/*/SKILL.md` in this repository remains the canonical skill source;
- the adapter exposes that directory through Pi's `resources_discover` event;
- Allye context and memory are loaded through the already configured `allye`
  MCP server via `pi-mcp-adapter`;
- Herdr is exposed as an optional capability when the Pi session provides `HERDR_ENV=1`.

## Package sources and installer boundary

Install the production package through Pi's native package manager:

```text
pi install npm:allye-pi
```

Use Git only when the repository source is intentional, preferably at a tag:

```text
pi install git:github.com/allye-app/allye-plugin
```

For development against a local checkout:

```text
pi install /absolute/path/to/allye-plugin
```

Pi owns package persistence and runtime dependencies. Removing the package with
`pi remove <the-exact-source>` is a separate, intentional operation; it does not
remove MCP configuration or OAuth credentials.

The repository's `./install.sh install pi` path is fail-closed for shared
runtime configuration unless an API-backed ownership operation authorizes it,
and `./install.sh uninstall pi` does not perform physical removal. Use
`./install.sh status` for inspection; do not describe a blocked installer result
as installation or cleanup success.

## Configure the canonical MCP server

The package never edits Pi's MCP files. Use the effective source displayed by
`/mcp`: project `.mcp.json` or `.pi/mcp.json`,
`~/.config/mcp/mcp.json`, `~/.agents/mcp.json`,
`~/.agents/mcp/mcp.json`, `~/.pi/agent/mcp.json`, or
`$PI_CODING_AGENT_DIR/mcp.json` when that override is set.

Define exactly one server named `allye`:

```json
{
  "allye": {
    "type": "http",
    "url": "https://mcp.allye.app/mcp"
  }
}
```

The effective pi-mcp-adapter source may wrap entries under `mcpServers`; preserve
its existing shape and every unrelated server. Do not add authorization headers
or fixed OAuth client metadata.

Authenticate and connect through the adapter:

```text
/mcp-auth allye
/mcp reconnect allye
```

Use `/reload` after changing the effective config. `/mcp logout allye` clears
only Allye's native credential when an intentional reconnection is needed; it
does not edit or remove the server entry.

Both npm and Git packages use the root Pi manifest and let Pi install
`pi-mcp-adapter` as a runtime dependency. The npm tarball contains the adapter
source, canonical `skills/` directory, and Pi documentation; it is not the full
plugin checkout and is not an installer input.

## Adaptive toolkit

Pi does not select an executor or orchestrator mode. Allye is available as an
adaptive toolkit in the current session. Use `/allye-capabilities` to inspect
Allye/MCP, filesystem, subagent, and Herdr capabilities.

When `HERDR_ENV=1`, the optional `allye_herdr` tool provides bounded `detect`,
`workspace`, `tab`, `spawn`, `dispatch`, `status`, `mark_intervened`, `wait`,
`collect`, and ownership-guarded `cleanup` operations. Without it, Pi continues
locally. Herdr and subagents are capabilities, not prerequisites.
Tasks are recommended for meaningful, delegated, multi-step, or review-heavy
work, but an explicitly approved no-task path is supported.

The adapter does not create specs or tasks or run transitions automatically. When a
spec or task exists, Allye remains the source of truth for scope, decisions, and
evidence; otherwise the user can proceed with proportional verification.

## Existing Pi startup extension

This package includes its own Allye bootstrap. If a user already has a separate
`allye-memory-startup.ts`, both can be loaded without changing global files, but
startup context may be fetched twice. To keep the existing global bootstrap as
the only startup fetcher, set `ALLYE_PI_NATIVE_BOOTSTRAP=0`; canonical skill
loading, capability detection, and team-selection guidance remain available.

When `initialize` reports multiple teams without an active team, the adapter does
not choose one silently and skips team-scoped memory search. If initialization
fails or its payload is unreadable, the bootstrap is also fail-closed and marks
Allye as unavailable rather than pretending a team is resolved. It injects the
team list or connectivity error and instructs the agent to use `allye_team` with
`team_switch` first. In an interactive session, `/allye-team <name|prefix|id>`
is available; in headless mode the same instruction is injected for the
model/user to follow.

## Local development

From the repository root:

```text
npm install
npm run typecheck
npm run test:pi
./install.sh status
jq -e '.pi.extensions and (.pi.skills == ["./skills"])' package.json
```

The extension is at `packages/allye-pi/src/index.ts`. Test it without changing
Pi's global settings with:

```text
pi -e ./packages/allye-pi/src/index.ts -p "Report the available Allye capabilities"
```

When `allye_herdr dispatch` registers a wait, the wait runs inside the Pi
process through managed `pi.exec`. On settlement it persists a durable session
entry, shows a UI notification/message when available, and queues a follow-up
turn to the current Pi session. That message is evidence only and explicitly
tells the agent to run `allye_herdr collect` when a managed spec exists and
inspect Allye `spec_context`, Review memories, and Implementation memories
before declaring completion. Normal completion, timeout, error, and abort are
distinguished.
Manual `herdr agent wait` commands started outside this Pi session (for example
with `nohup` or Bash) do not wake Pi and do not generate this notification.

A real Herdr dispatch still requires `HERDR_ENV=1`, a compatible Herdr session,
and an existing isolated worktree. Pi records execution IDs plus
workspace/tab/pane/agent ownership for safe teardown; it never adopts foreign
panes, stops Herdr, closes panes, merges, pushes, or publishes without explicit
authorization. Cleanup is only allowed after a settled and collected execution;
blocked, unknown, timed-out, interrupted, or manually assumed resources remain open.
