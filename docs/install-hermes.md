# Allye Plugin — Hermes Agent Installation Guide

You are an AI agent helping the user install the Allye plugin for Hermes Agent. Follow these steps exactly.

## Step 1: Clone the plugin and run the installer

```bash
git clone https://github.com/allye-app/allye-plugin.git
cd allye-plugin
./install.sh install hermes
```

This writes the Allye MCP block to `~/.hermes/config.yaml`, exports the 16 Allye skills to `~/.hermes/skills/allye/`, and installs the `allye-bootstrap` plugin to `~/.hermes/plugins/allye-bootstrap/` (enabling it in `plugins.enabled` alongside any plugins already there).

## Step 2: Authenticate (interactive — cannot be automated)

Hermes MCP OAuth needs a TTY, so the installer writes the config block but cannot complete login for you. Run this yourself in a terminal:

```bash
hermes mcp add allye --url https://mcp.allye.app/mcp --auth oauth
```

Your browser opens for login — sign in with your Allye account, select a team, and approve.

## Step 3: Confirm

Tell the user:

> Allye is configured for Hermes Agent!
>
> **What was set up:**
> - Allye MCP block written to `~/.hermes/config.yaml` (needs the interactive OAuth step above)
> - 16 workflow skills exported to `~/.hermes/skills/allye/`
> - `allye-bootstrap` plugin installed and enabled — injects the `using-allye` skill at session start
>
> **Run the OAuth command above in a terminal**, then start a new Hermes session to begin using Allye workflows.

## What the installer turns off, and why

Installing Allye disables two Hermes features, because Allye provides both and two
sources of truth is worse than either alone.

**`memory`** — Hermes stores memories in `~/.hermes/memories/` on this machine. Allye's
`intelligence` has seven sectors, conflict resolution, team scope, and semantic search, and
it is reachable from every agent on every machine. A memory only Hermes can see is worse
than none: it gives the feeling of continuity without the thing.

**`kanban`** — despite the name this is an orchestration engine: atomic task claiming,
dependencies, isolated workspaces per task, and a swarm mode. Allye's work items plus the
Orchestrator do the same job, and know Epic→Feature→Story→Task, acceptance criteria, and
your team's configured pipeline.

**`todo` stays.** It is turn-scratch and that is legitimate. Anything that outlives the
session is promoted to Allye at session end — see the `memory-protocol` skill.

To keep either, remove it from `toolsets_remove` in `install/adapters.json` before
installing, or re-add it to `platform_toolsets` afterwards.

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
