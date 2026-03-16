# Fenix Plugin — Codex CLI Update Guide

You are an AI agent helping the user update the Fenix plugin for Codex CLI. Follow these steps exactly.

## Step 1: Update AGENTS.md

Download the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/codex/AGENTS.md > ~/.codex/AGENTS.md
```

## Step 2: Verify MCP server

Check that the Fenix MCP server is still configured:

```bash
grep "fenix-mcp" ~/.codex/config.toml 2>/dev/null
```

If it's missing, re-configure it (ask the user for their PAT if needed).

## Step 3: Confirm

Tell the user:

> Fenix plugin updated for Codex CLI!
>
> **Start a new Codex session** to use the updated instructions.
