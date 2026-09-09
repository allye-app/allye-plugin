# Allye Plugin — Codex CLI Update Guide

You are an AI agent helping the user update the Allye plugin for Codex CLI. Preserve unrelated MCP servers, credentials, and instructions.

## Step 1: Update AGENTS.md

Download the latest Allye instructions to a temporary file:

```bash
curl -fsSL https://raw.githubusercontent.com/allye-app/allye-plugin/main/manifests/codex/AGENTS.md > /tmp/allye-AGENTS.md
```

Merge the Allye content into `~/.codex/AGENTS.md` without overwriting user
instructions.

## Step 2: Verify the canonical MCP entry

```bash
codex mcp get allye
```

The entry must be named `allye`, point to `https://mcp.allye.app/mcp`, and have
no fixed headers or OAuth client metadata. If that Allye entry is stale, replace
only it:

```bash
codex mcp logout allye
codex mcp remove allye
codex mcp add allye --url https://mcp.allye.app/mcp
codex mcp login allye
```

If the legacy server is registered under another name, run logout/remove with
that exact old name before adding `allye`. Never delete Codex's global credential
store or unrelated MCP entries.

## Step 3: Confirm

Tell the user:

> Allye plugin updated for Codex CLI.
>
> Start a new Codex session to use the updated instructions. Codex manages Allye OAuth and refresh natively.
