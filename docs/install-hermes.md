# Allye Plugin — Hermes Agent Installation Guide

You are an AI agent helping the user install the Allye plugin for Hermes Agent. Follow these steps exactly.

## Step 1: Configure and authenticate the canonical MCP entry

Use Hermes's native MCP command in a terminal:

```bash
hermes mcp add allye --url https://mcp.allye.app/mcp --auth oauth
```

The browser opens for login. Sign in with your Allye account, select a tenant,
and approve. Hermes owns OAuth registration, credential storage, and refresh;
do not add a bearer header or fixed client ID.

## Step 2: Understand the repository installer boundary

`./install.sh install hermes` is fail-closed unless an API-backed ownership
operation authorizes canonical skill distribution. A normal local invocation
returns `CONFLICT_UNMANAGED` before changing shared configuration. Physical
uninstall is also blocked. Use `./install.sh status` only for inspection, and
never report a blocked invocation as successful installation or cleanup.

When an authorized distribution operation is available, it verifies the
immutable release artifact before publishing skills. It does not replace the
native OAuth command above.

## Step 3: Confirm

Tell the user only what was observed:

> The `allye` MCP server is configured at `https://mcp.allye.app/mcp`.
>
> Hermes manages its OAuth session natively. Workflow skills are installed only if the separate API-authorized distribution operation completed successfully.

## What the installer turns off, and why

Installing Allye disables two Hermes features, because Allye provides both and two
sources of truth is worse than either alone.

**`memory`** — Hermes stores memories in `~/.hermes/memories/` on this machine.

*How it is turned off, precisely:* the installer sets `memory.memory_enabled` and
`memory.user_profile_enabled` to `false`, which disables the memory **store**. The tool itself
stays registered — it lives inside the `hermes-cli` preset as a tool name, not as a separable
toolset, and removing it would mean materialising an explicit toolset list per platform and
thereby freezing a default you never chose. Called without a store it returns
`{"error":"Memory is not available…","success":false}`, so an agent that reaches for it is told
plainly and falls back to Allye's. That is a better failure than the tool silently not existing.

The `toolsets_remove` entry in the adapter only bites if your `platform_toolsets` lists
individual toolsets rather than presets — which is what `hermes tools` writes. On a preset-based
config it is a no-op, and the flags do the work. Allye's
`intelligence` has seven sectors, conflict resolution, team scope, and semantic search, and
it is reachable from every agent on every machine. A memory only Hermes can see is worse
than none: it gives the feeling of continuity without the thing.

**`kanban`** — despite the name this is an orchestration engine: atomic task claiming,
dependencies, isolated workspaces per task, and a swarm mode. Allye's work items plus the
Orchestrator do the same job, and know Epic→Feature→Story→Task, acceptance criteria, and
your team's configured pipeline.

**`todo` stays.** It is turn-scratch and that is legitimate. Anything that outlives the
session is promoted to Allye at session end — see the `memory-protocol` skill.

Changing the memory or toolset policy requires a separately reviewed adapter
change; it is not an installation-time toggle.

**One thing to watch.** Hermes's memory is woven into its turn loop, and context compression
reads the same flag. If long conversations start behaving differently after installing, that
is the first place to look.

## Working while you are away

Hermes's own scheduler still runs; it just drives Allye rather than a second board.

```bash
hermes cron create "allye-morning" \
  --schedule "0 9 * * 1-5" \
  --prompt "Load the orchestrator skill and report where each in-flight story stands. Do not dispatch anything without asking."
```

The gateway runs on your machine and answers from Telegram, Discord, Slack, or whichever
platform you connected — so a story parked at a gate reaches you wherever you are, and you
answer from there.

**Start read-only.** A schedule that reports is useful on day one and cannot surprise you.
Give it dispatch authority once you have watched what it reports for a week.
