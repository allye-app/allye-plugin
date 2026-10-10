# Allye — Pi installation guide

Allye for Pi is the native package `allye-pi`. It:

- exposes the Bridge skill (`/bridge <mode>`) from the package's `skills/` directory;
- adds the Allye bootstrap (`bootstrap/allye.md`) to the system prompt;
- identifies the repository's project (it loads no startup or per-prompt memory context): when an in-process MCP bridge is available it resolves the git remote with `projects.project_resolve` and verifies any `.allye/project.json` claim against it, injecting "this repo = project X / app Y (team Z)", the ambiguous candidates, or the disagreement to ask the user about.

It never edits Pi's MCP configuration or reads credentials.

## Install the package

```text
pi install npm:allye-pi
```

From Git (preferably at a tag): `pi install git:github.com/allye-app/allye-plugin`. From a local checkout, for development: `pi install /absolute/path/to/allye-plugin`.

Update with `pi update npm:allye-pi`; remove with `pi remove npm:allye-pi`. Removing the package does not remove MCP configuration or OAuth credentials.

## Configure the MCP server

Recent Pi releases have a native MCP client (verified on Pi 0.99.1). Add the server and sign in:

```text
pi mcp add allye --url https://mcp.allye.app/mcp
pi mcp login allye
pi mcp list
```

Do not pass headers, bearer tokens or OAuth client ids: Pi discovers the OAuth endpoints and stores the credential.

On older Pi versions without `pi mcp`, install `pi-mcp-adapter` (`pi install npm:pi-mcp-adapter`), define one server named `allye` (`{"type": "http", "url": "https://mcp.allye.app/mcp"}` under `mcpServers`) in the effective source shown by `/mcp` — for example `~/.pi/agent/mcp.json` or `~/.config/mcp/mcp.json` — then run `/mcp-auth allye` and `/mcp reconnect allye`.

The extension resolves the repository's project only when `pi-mcp-adapter` exposes its in-process bridge. Otherwise it injects only the git remote and any unverified link claim, and the bootstrap tells the agent to call `projects.project_resolve` itself.

## Teams

The team follows the project: the extension never blocks work on team selection. A default team is needed only to create projects; `/allye-team <name|prefix|id>` sets it through the `team` tool (`team_set_default`). Set `ALLYE_PI_NATIVE_BOOTSTRAP=0` to skip the repository block (the bootstrap text and the Bridge skill stay available), or `ALLYE_PI_MCP=0` to disable MCP calls from the extension.

## Local development

From the repository root:

```text
npm install
npm run typecheck
npm run test:pi
pi -e ./packages/allye-pi/src/index.ts -p "Which Allye tools and Bridge modes are available?"
```

## Organization skills

`./install.sh install pi <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `$PI_CODING_AGENT_DIR/skills` when `PI_CODING_AGENT_DIR` is set, otherwise `~/.pi/agent/skills`. The value must be an absolute path; only the empty string means unset, a trailing `/` is stripped, and a relative value stops the Pi install before any request. Changing it changes the install target; copies left in the old directory are not migrated. The API sees runtime `pi` and the skill is installed as a plain directory, with no package receipt.

- Edited copies: `./install.sh install pi <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/pi/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/pi/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
