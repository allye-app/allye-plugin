# Install Allye for Pi

The Pi adapter is a thin native Pi package. It does not copy workflow skills or
replace Pi's MCP configuration:

- `skills/*/SKILL.md` in this repository remains the canonical skill source;
- the adapter exposes that directory through Pi's `resources_discover` event;
- Allye context and memory are loaded through the already configured `allye`
  MCP server via `pi-mcp-adapter`;
- Herdr is exposed only in explicit Pi orchestrator mode.

## From a checkout

```text
cd /path/to/allye-plugin
./install.sh install pi
```

This adds the checkout path to `~/.pi/agent/settings.json` under `packages`,
without replacing existing packages or settings. It also runs
`npm install --omit=dev` in the checkout when `node_modules/pi-mcp-adapter` is
missing, because Pi does not install dependencies for local package paths. The
operation is idempotent; restart Pi (or run `/reload`) after installation.

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

For a remote installation instead of a checkout:

```text
pi install git:github.com/allye-app/allye-plugin
```

The Git package uses the root Pi manifest and installs `pi-mcp-adapter` as a
runtime dependency through Pi's package manager. Use a tagged ref when
reproducibility is required. The npm tarball is intentionally limited to the
adapter source, canonical skills, and Pi documentation; it is not the full
plugin checkout and is not the installer input.

## Modes

Pi is an executor by default, which is the safe mode when Hermes is the master.
The mode can be selected before starting a session:

```text
ALLYE_PI_MODE=executor pi
ALLYE_PI_MODE=orchestrator pi
```

`ALLYE_ORCHESTRATOR=hermes` always forces executor mode. Pi orchestrator mode
also requires both `ALLYE_ORCHESTRATION_RUN_ID` and `ALLYE_WORK_ITEM_KEY`; an
explicit local lock is acquired before `allye_runtime` becomes active. The claim
contains run/work-item identity, PID, session identity when available, a nonce,
and a 30-minute lease. Normal `session_shutdown` aborts waits and removes only
the exact claim owned by that instance. If a process crashes, recovery is
disabled by default; after confirming the recorded local PID is gone and the
lease expired, set `ALLYE_PI_RECOVER_STALE_LOCK=1` to quarantine and replace the
lock. Active, unreadable, changed, or inconclusive locks fail closed. In a
session, `/allye-mode executor` and `/allye-mode orchestrator` change the active
mode only when the same guard succeeds. Only orchestrator mode enables the
`allye_runtime` tool.

### Pi orchestrator

With `ALLYE_PI_MODE=orchestrator`, Pi coordinates the canonical workflow and may
use `allye_runtime` for Herdr's `detect`, `spawn`, `dispatch`, `wait`, and
Allye-backed `collect` operations. Parallel stories require separate worktrees;
the pane cwd remains the plugin-enabled repository root and absolute worktree
paths are placed in each briefing. The adapter does not create work items or change statuses automatically.
Status updates by an assigned executor remain allowed through the canonical
`execution` skill; pane/dispatch ownership is separate from status ownership.

### Pi executor / Hermes master

In executor mode, Pi reads the handed-over story/tasks, implements only that
scope, follows the canonical `execution` skill, and may advance its assigned
tasks to `in_progress` and `review` when the work and verification are complete.
It does not create or dispatch panes, assume orchestration, or change scope.
Hermes can remain the master and dispatch Pi or another agent through Herdr; Pi
and Hermes must not orchestrate the same work item simultaneously.

## Existing Pi startup extension

This package includes its own Allye bootstrap. If a user already has a separate
`allye-memory-startup.ts`, both can be loaded without changing global files, but
startup context may be fetched twice. To keep the existing global bootstrap as
the only startup fetcher, set `ALLYE_PI_NATIVE_BOOTSTRAP=0`; canonical skill
loading, mode handling, team-selection guidance, and the Herdr guard remain
available.

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
pi -e ./packages/allye-pi/src/index.ts -p "Report the active Allye mode"
```

When `allye_runtime dispatch` registers a wait, the wait runs inside the Pi
process through managed `pi.exec`. On settlement it persists a durable session
entry, shows a UI notification/message when available, and queues a follow-up
turn to the Pi orchestrator. That message is evidence only and explicitly tells
the orchestrator to run `allye_runtime collect` and inspect Allye
`work_children`, Review memories, and Implementation memories before declaring
completion. Normal completion, timeout, error, and abort are distinguished.
Manual `herdr agent wait` commands started outside this Pi session (for example
with `nohup` or Bash) do not wake Pi and do not generate this notification.

A real Herdr dispatch still requires `HERDR_ENV=1`, a compatible Herdr session,
an existing isolated worktree, explicit orchestrator mode, and an orchestration
run/work-item claim. Pi records workspace/tab/pane/agent ownership in memory for
future safe teardown; it never adopts foreign panes, stops Herdr, closes panes,
merges, pushes, or publishes. The lock is local to the Pi checkout/agent
configuration and is **not** a distributed Allye lock: Hermes and Pi must still
coordinate the run externally when operating on different machines/process
homes. A stale lock can be manually investigated using its PID, lease, and owner
token; automatic recovery is intentionally opt-in.
