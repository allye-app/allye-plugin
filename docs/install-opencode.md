# Allye — OpenCode installation guide

You are an AI agent helping the user install Allye for OpenCode: the Allye MCP server and the `allye-opencode` plugin, which adds the Allye bootstrap and the Bridge skill. Preserve unrelated MCP servers, plugins and credentials.

## Step 1: Configure the MCP server and the plugin

Merge the Allye entries into the user's OpenCode config. If the config still has the legacy `allye-mcp` entry, first run `opencode mcp logout allye-mcp` (this clears only that obsolete registration).

```bash
CONFIG=$(cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{"$schema": "https://opencode.ai/config.json"}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcp = (.mcp // {})
  | del(.mcp["allye-mcp"])
  | .mcp.allye = { "type": "remote", "url": "https://mcp.allye.app/mcp", "enabled": true }
  | .plugin = (.plugin // [])
  | if (.plugin | index("allye-opencode")) then . else .plugin += ["allye-opencode"] end
')

mkdir -p ~/.config/opencode
echo "$CONFIG" | jq '.' > ~/.config/opencode/opencode.json
```

The `allye` entry intentionally has no headers or fixed OAuth client metadata.

## Step 2: Authenticate

Restart OpenCode, then:

```bash
opencode mcp auth allye
opencode mcp list
```

OpenCode owns discovery, client registration, token storage and refresh.

## Step 3: Confirm

Tell the user:

> Allye is configured for OpenCode:
> - the `allye` MCP server at `https://mcp.allye.app/mcp`, using native OAuth;
> - the `allye-opencode` plugin, which adds the Allye bootstrap and the Bridge skill (`/bridge <mode>`).
>
> Restart OpenCode to load the plugin. The agent identifies the repository's project with `project_resolve`; it asks for a team only when it needs to create a project and you have no default team.

## Organization skills

`./install.sh install opencode <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `${XDG_CONFIG_HOME:-~/.config}/opencode/allye-skills`. An empty or relative `XDG_CONFIG_HOME` counts as unset. OpenCode does not discover this directory natively: the `allye-opencode` plugin adds it to `skills.paths` when it is a real directory (not a symlink) owned by you and not group- or world-writable. The installer refuses to install into a symlinked or group/world-writable one (fix with `chmod go-w <dir>`); it does not check ownership, so the plugin additionally ignores a directory that is not owned by you. When the install creates the directory, the installer prints a notice: restart OpenCode to load it.

- Edited copies: `./install.sh install opencode <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/opencode/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/opencode/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
