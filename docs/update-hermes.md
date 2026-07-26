# Allye Plugin — Hermes Agent Update Guide

You are an AI agent helping the user update the Allye plugin for Hermes Agent. Follow these steps exactly.

## Step 1: Pull the latest plugin and re-run the installer

```bash
cd allye-plugin
git pull
./install.sh install hermes
```

`install` is additive and idempotent — it re-exports the 16 skills, refreshes the MCP block and the `allye-bootstrap` plugin's version marker, and leaves any other plugins already enabled in `~/.hermes/config.yaml` untouched.

## Step 2: Verify

```bash
./install.sh status
```

Confirm the Hermes Agent line reports `current (v1)` — an `outdated (vN)` reading means an older marker survived and the install step above needs a re-run.

## Step 3: Confirm

Tell the user:

> Allye plugin updated for Hermes Agent!
>
> **Start a new Hermes session** to use the updated skills and bootstrap. If the MCP server was never authenticated, run `hermes mcp add allye --url https://mcp.allye.app/mcp --auth oauth` in a terminal — that step still needs a TTY and can't be automated.
