# Allye — Codex CLI update guide

You are an AI agent helping the user update Allye for Codex CLI. Preserve unrelated MCP servers, credentials, skills and instructions.

## Step 1: Update the Bridge skill

Repeat Step 2 of [install-codex.md](install-codex.md): download the latest repository archive and replace `~/.codex/skills/bridge*` with the `skills/bridge*` directories it contains.

## Step 2: Update AGENTS.md

```bash
curl -fsSL https://raw.githubusercontent.com/allye-app/allye-plugin/main/manifests/codex/AGENTS.md > /tmp/allye-AGENTS.md
```

Replace the previous Allye section of `~/.codex/AGENTS.md` with this file, keeping the user's own instructions. Older versions installed an Allye workflow section (handovers, workflow skills such as `sandbox` or `allye-product-planning`); remove that section entirely.

## Step 3: Verify the MCP entry

```bash
codex mcp get allye
```

The entry must be named `allye`, point to `https://mcp.allye.app/mcp`, and have no fixed headers or OAuth client metadata. If it is stale, replace only it (see Step 1 of the install guide) and run `codex mcp login allye`.

## Step 4: Confirm

> Allye updated for Codex. Start a new Codex session to use the new bootstrap and Bridge.
