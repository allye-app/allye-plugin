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
