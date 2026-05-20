# Allye Plugin — Codex CLI Update Guide

You are an AI agent helping the user update the Allye plugin for Codex CLI. Follow these steps exactly.

## Step 1: Update AGENTS.md

Download the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/allye-assistant/allye-plugin/main/manifests/codex/AGENTS.md > ~/.codex/AGENTS.md
```

## Step 2: Verify MCP server

Check that the Allye MCP server is configured with OAuth (no PAT headers):

```bash
grep "allye-mcp" ~/.codex/config.toml 2>/dev/null
```

If it has `http_headers` with a PAT, update the config to remove them:

```bash
sed -i '/http_headers.*Authorization.*Bearer/d' ~/.codex/config.toml
sed -i 's|allye-mcp.devshire.app/jsonrpc|allye-mcp.devshire.app/mcp|g' ~/.codex/config.toml
```

If it's missing entirely, add it:

```bash
cat >> ~/.codex/config.toml << TOML

[mcp_servers.allye-mcp]
url = "https://allye-mcp.devshire.app/mcp"
enabled = true
TOML
```

## Step 3: Confirm

Tell the user:

> Allye plugin updated for Codex CLI!
>
> **Start a new Codex session** to use the updated instructions. Authentication is now via OAuth — your browser will open on first use.
