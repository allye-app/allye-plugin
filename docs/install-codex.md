# Allye — Codex CLI installation guide

You are an AI agent helping the user install Allye for OpenAI Codex CLI: the Allye MCP server, the Bridge skill and the Allye bootstrap in `AGENTS.md`. Preserve unrelated MCP servers, credentials, skills and instructions.

## Step 1: Configure the MCP server

Add one server named `allye` through Codex's native MCP command:

```bash
codex mcp add allye --url https://mcp.allye.app/mcp
codex mcp get allye
```

If `allye` already exists with a different URL, fixed headers or fixed OAuth client metadata, replace that entry alone:

```bash
codex mcp logout allye
codex mcp remove allye
codex mcp add allye --url https://mcp.allye.app/mcp
```

Do not edit the credential store or remove unrelated MCP servers.

## Step 2: Install the Bridge skill

Copy the Bridge skill (and any `bridge-*` crew skills) into Codex's user skills directory:

```bash
TMP=$(mktemp -d)
curl -fsSL https://github.com/allye-app/allye-plugin/archive/refs/heads/main.tar.gz | tar -xz -C "$TMP"
mkdir -p ~/.codex/skills
for dir in "$TMP"/allye-plugin-main/skills/bridge*; do
  rm -rf ~/.codex/skills/"$(basename "$dir")"
  cp -R "$dir" ~/.codex/skills/
done
rm -rf "$TMP"
```

Before replacing an existing `~/.codex/skills/bridge`, check that it is the Allye Bridge (`name: bridge` in its `SKILL.md`); otherwise ask the user.

## Step 3: Install the bootstrap in AGENTS.md

```bash
curl -fsSL https://raw.githubusercontent.com/allye-app/allye-plugin/main/manifests/codex/AGENTS.md > /tmp/allye-AGENTS.md
```

If `~/.codex/AGENTS.md` already has user instructions, merge the Allye section without overwriting them (replace a previous Allye section if one exists). Otherwise move the file into place.

## Step 4: Authenticate

```bash
codex mcp login allye
```

The browser opens for consent. Codex owns client registration, token storage and refresh; no bearer header or client ID belongs in `config.toml`.

## Step 5: Confirm

Tell the user:

> Allye is configured for Codex: the `allye` MCP server, the Bridge skill and the Allye bootstrap in `~/.codex/AGENTS.md`.
>
> Start a new Codex session and run `/bridge survey` (or another mode) to begin. The agent identifies the repository's project with `project_resolve`; it asks for a team only when it needs to create a project and you have no default team.

## Organization skills and CODEX_HOME

`./install.sh install codex <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `$CODEX_HOME/skills` when `CODEX_HOME` is set, otherwise `~/.codex/skills`. `CODEX_HOME` must be an absolute path; only the empty string means unset, a trailing `/` is stripped (`/` itself stays `/`, so skills go to `/skills`), and a relative value stops the Codex install before any request. Detection also checks `$CODEX_HOME`.

Setting or changing `CODEX_HOME` re-keys the install target, because the target includes the skills directory. Skills installed earlier under `~/.codex/skills` are not migrated or touched; a copy found under the new directory is treated as missing or "other-target".

- Edited copies: `./install.sh install codex <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/codex/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/codex/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
