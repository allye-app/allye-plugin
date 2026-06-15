# Allye Plugin — Codex CLI Installation Guide

You are an AI agent helping the user install the Allye plugin for OpenAI Codex CLI. Follow these steps exactly.

## Step 1: Configure MCP Server

Add the Allye MCP server to Codex config (OAuth — no PAT needed):

```bash
mkdir -p ~/.codex

# Check if allye-mcp already exists in config
if grep -q "allye-mcp" ~/.codex/config.toml 2>/dev/null; then
  echo "Allye MCP already configured in ~/.codex/config.toml"
else
  cat >> ~/.codex/config.toml << TOML

[mcp_servers.allye-mcp]
url = "https://allye-mcp.devshire.app/mcp"
enabled = true
TOML
fi
```

## Step 2: Install AGENTS.md

Download the Allye AGENTS.md:

```bash
curl -fsSL https://raw.githubusercontent.com/allye-app/allye-plugin/main/manifests/codex/AGENTS.md > ~/.codex/AGENTS.md
```

This gives Codex the Allye workflow instructions globally.

## Step 3: Authenticate

After starting a new Codex session, the first time you use a Allye tool, your browser will open automatically for OAuth login. Sign in with your Allye account, select a team, and approve.

## Step 4: Confirm

Tell the user:

> Allye is configured for Codex CLI!
>
> **What was set up:**
> - Allye MCP server connected via OAuth (~/.codex/config.toml)
> - AGENTS.md installed with Allye workflow instructions
>
> **Start a new Codex session** to begin using Allye workflows. Your browser will open for login on first use.
