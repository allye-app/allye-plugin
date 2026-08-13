# Install Allye for Pi

The Pi adapter is a thin native Pi package. It does not copy workflow skills or
replace Pi's MCP configuration:

- `skills/*/SKILL.md` in this repository remains the canonical skill source;
- the adapter exposes that directory through Pi's `resources_discover` event;
- Allye context and memory are loaded through the already configured `allye`
  MCP server via `pi-mcp-adapter`;
- Herdr is exposed as an optional capability when the Pi session provides `HERDR_ENV=1`.

## Official package sources

### npm (default production install)

```text
./install.sh install pi
# equivalent to:
pi install npm:allye-pi

./install.sh uninstall pi
# equivalent to:
pi remove npm:allye-pi
```

The installer delegates installation and persistence to Pi's official package
manager. It never edits `~/.pi/agent/settings.json` manually and the default
source is always the published npm package. Restart Pi (or run `/reload`) after
installation.

### Git

Use Git when you want Pi to install the repository package directly, preferably
at a tag for reproducibility:

```text
pi install git:github.com/allye-app/allye-plugin
pi remove git:github.com/allye-app/allye-plugin
```

This is separate from `./install.sh install pi`, which intentionally remains an
npm install.

### Local checkout (development only)

A checkout path is supported, but only through an explicit opt-in so a normal
production install cannot accidentally load uncommitted code:

```text
cd /path/to/allye-plugin
ALLYE_PI_INSTALL_SOURCE=local ./install.sh install pi
ALLYE_PI_INSTALL_SOURCE=local ./install.sh uninstall pi
```

That delegates to `pi install /absolute/path/to/allye-plugin` and
`pi remove /absolute/path/to/allye-plugin`. Pi manages the package settings and
runtime dependencies in every case; `skills/*/SKILL.md` remains the single
canonical skill tree.

The installer deliberately does **not** edit any MCP file. Relative project
paths are resolved from the installer `PWD`, or from `ALLYE_PI_PROJECT_DIR` when
installing for a different project. Configure Allye in
one of the sources supported by `pi-mcp-adapter`: project `.mcp.json` or
`.pi/mcp.json`, `~/.config/mcp/mcp.json`, `~/.agents/mcp.json`, `~/.agents/mcp/mcp.json`, or
`~/.pi/agent/mcp.json` (or `$PI_CODING_AGENT_DIR/mcp.json` when that Pi
override is set). For example, use an
`allye` server pointing to `https://mcp.allye.app/mcp/<tenant-slug>`.
Authenticate with `/mcp-auth allye` when required. Existing MCP servers are
preserved. `./install.sh install pi` reports the first supported source that
already contains Allye and warns only when none does.

Both npm and Git packages use the root Pi manifest and let Pi install
`pi-mcp-adapter` as a runtime dependency. The npm tarball contains the adapter
source, canonical `skills/` directory, and Pi documentation; it is not the full
plugin checkout and is not the installer input.

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

The adapter does not create work items or change statuses automatically. When a
work item exists, Allye remains the source of truth for scope, decisions, and
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
tells the agent to run `allye_herdr collect` when a managed work item exists and
inspect Allye `work_children`, Review memories, and Implementation memories
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
