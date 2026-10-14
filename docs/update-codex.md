# Allye — Codex CLI update guide

You are an AI agent helping the user update Allye for Codex CLI. Preserve unrelated MCP servers, credentials, skills and instructions.

## Step 1: Resolve the version

Repeat Step 0 of [install-codex.md](install-codex.md): the version the user named, else the latest release, validated and shown to the user before any change. Run Steps 1 to 3 in one shell session (they share `VERSION`, `ALLYE_TMP` and `TS`).

## Step 2: Update the Bridge skill

Repeat Step 2 of [install-codex.md](install-codex.md): download the release archive of that version and replace `~/.codex/skills/bridge*` with the `skills/bridge*` directories it contains. The git docs templates and the docs-check script are updated the same way, and a copy that is not Allye's (a foreign skill, templates or script, or any symbolic link) is skipped with a message and left alone. Existing copies are backed up under `~/.allye/backups/codex/` first (a failed backup stops the step before anything is replaced); report the paths.

## Step 3: Update AGENTS.md

Repeat Step 3 of [install-codex.md](install-codex.md): it replaces only the Allye section between `<!-- allye:begin -->` and `<!-- allye:end -->` in `~/.codex/AGENTS.md`, keeping the user's own instructions, after backing the file up. Older versions installed an unmarked Allye section, including an Allye workflow section (handovers, workflow skills such as `sandbox` or `allye-product-planning`); the script shows it and changes nothing until the user confirms its removal. Malformed or duplicated markers are refused the same way as in the install guide, with the file unchanged.

## Step 4: Verify the MCP entry

```bash
codex mcp get allye
```

The entry must be named `allye`, point to `https://mcp.allye.app/mcp`, and have no fixed headers or OAuth client metadata. If it is stale, replace only it (see Step 1 of the install guide) and run `codex mcp login allye`.

## Step 5: Confirm

> Allye updated for Codex. Start a new Codex session to use the new bootstrap and Bridge.
