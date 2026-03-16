# Fenix Plugin — Codex CLI Installation Guide

You are an AI agent helping the user install the Fenix plugin for OpenAI Codex CLI. Follow these steps exactly.

## Step 1: Ask for the Fenix PAT

Say this to the user:

> To connect Fenix, I need your Personal Access Token (PAT).
>
> You can generate one at: **https://fenix.devshire.app** → Settings → API → Generate Token
>
> Paste your PAT here:

Wait for the user to provide the token.

## Step 2: Validate the PAT

Run this command, replacing `{PAT}` with the user's token:

```bash
curl -s -w "\n%{http_code}" -H "Authorization: Bearer {PAT}" https://fenix-api.devshire.app/api/auth/profile
```

- If `200`: Valid. Confirm authentication.
- If `401`/`403`: Invalid. Ask user to retry.

## Step 3: Configure MCP Server

Add the Fenix MCP server to Codex config. Replace `{PAT}` with the actual token:

```bash
mkdir -p ~/.codex

# Check if fenix-mcp already exists in config
if grep -q "fenix-mcp" ~/.codex/config.toml 2>/dev/null; then
  echo "Fenix MCP already configured in ~/.codex/config.toml"
else
  cat >> ~/.codex/config.toml << TOML

[mcp_servers.fenix-mcp]
url = "https://fenix-mcp.devshire.app/jsonrpc"
http_headers = { "Authorization" = "Bearer {PAT}" }
enabled = true
TOML
fi
```

## Step 4: Install AGENTS.md

Download the Fenix AGENTS.md:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/codex/AGENTS.md > ~/.codex/AGENTS.md
```

This gives Codex the Fenix workflow instructions globally.

## Step 5: Confirm

Tell the user:

> Fenix is configured for Codex CLI!
>
> **What was set up:**
> - Fenix MCP server connected (~/.codex/config.toml)
> - AGENTS.md installed with Fenix workflow instructions
> - Workflow skills seeded into your Fenix database
>
> **Start a new Codex session** to begin using Fenix workflows.
