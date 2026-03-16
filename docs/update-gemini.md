# Fenix Plugin — Gemini CLI Update Guide

You are an AI agent helping the user update the Fenix plugin for Gemini CLI. Follow these steps exactly.

## Step 1: Update GEMINI.md

Download the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/manifests/gemini/GEMINI.md > ~/.gemini/GEMINI.md.new
```

Check if the user has custom content in their GEMINI.md. If so, merge — don't overwrite:

```bash
diff ~/.gemini/GEMINI.md ~/.gemini/GEMINI.md.new 2>/dev/null
```

If no custom content, replace:

```bash
mv ~/.gemini/GEMINI.md.new ~/.gemini/GEMINI.md
```

If custom content exists, append only the Fenix section.

## Step 2: Verify MCP server

Check that the Fenix MCP server is still configured:

```bash
cat ~/.gemini/settings.json | jq '.mcpServers["fenix-mcp"]'
```

If it's missing, re-configure it (ask the user for their PAT if needed).

## Step 3: Confirm

Tell the user:

> Fenix plugin updated for Gemini CLI!
>
> **Start a new Gemini session** to use the updated instructions.
