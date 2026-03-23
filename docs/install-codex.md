# Fenix Plugin — Codex CLI Installation Guide

You are an AI agent helping the user install the Fenix plugin for OpenAI Codex CLI. Follow these steps exactly.

## Step 1: Configure MCP Server

Add the Fenix MCP server to Codex config (OAuth — no PAT needed):

```bash
mkdir -p ~/.codex

# Check if fenix-mcp already exists in config
if grep -q "fenix-mcp" ~/.codex/config.toml 2>/dev/null; then
  echo "Fenix MCP already configured in ~/.codex/config.toml"
else
  cat >> ~/.codex/config.toml << TOML

[mcp_servers.fenix-mcp]
url = "https://fenix-mcp.devshire.app/mcp"
enabled = true
TOML
fi
```

## Step 2: Install AGENTS.md

Download the Fenix AGENTS.md:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/codex/AGENTS.md > ~/.codex/AGENTS.md
```

This gives Codex the Fenix workflow instructions globally.

## Step 3: Authenticate

After starting a new Codex session, the first time you use a Fenix tool, your browser will open automatically for OAuth login. Sign in with your Fenix account, select a team, and approve.

## Step 4: Confirm

Tell the user:

> Fenix is configured for Codex CLI!
>
> **What was set up:**
> - Fenix MCP server connected via OAuth (~/.codex/config.toml)
> - AGENTS.md installed with Fenix workflow instructions
>
> **Start a new Codex session** to begin using Fenix workflows. Your browser will open for login on first use.
