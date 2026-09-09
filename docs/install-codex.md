# Allye Plugin — Codex CLI Installation Guide

You are an AI agent helping the user install the Allye plugin for OpenAI Codex CLI. Preserve unrelated MCP servers, credentials, and instructions.

## Step 1: Configure the canonical MCP server

Add one server named `allye` through Codex's native MCP command:

```bash
codex mcp add allye --url https://mcp.allye.app/mcp
codex mcp get allye
```

If Codex reports that `allye` already exists, inspect it with `codex mcp get allye`.
Only when that Allye entry has a different URL, fixed headers, or fixed OAuth client
metadata, replace that entry alone:

```bash
codex mcp logout allye
codex mcp remove allye
codex mcp add allye --url https://mcp.allye.app/mcp
```

If an older Allye entry is loaded under another name, use `codex mcp logout
<old-name>` and `codex mcp remove <old-name>` for that entry only. Do not edit
the credential store or remove unrelated MCP servers.

## Step 2: Install AGENTS.md

Download the current Allye instructions to a temporary file:

```bash
curl -fsSL https://raw.githubusercontent.com/allye-app/allye-plugin/main/manifests/codex/AGENTS.md > /tmp/allye-AGENTS.md
```

If `~/.codex/AGENTS.md` already contains user instructions, merge the Allye
content without overwriting them. Otherwise move the downloaded file into place.

## Step 3: Authenticate

Use Codex's native OAuth flow:

```bash
codex mcp login allye
```

The browser opens for consent. Codex owns client registration, token storage,
and refresh; no bearer header or fixed client ID belongs in `config.toml`.

## Step 4: Confirm

Tell the user:

> Allye is configured for Codex CLI under the server name `allye`.
>
> Start a new Codex session to use the workflow instructions. Authentication and refresh are managed by Codex.
