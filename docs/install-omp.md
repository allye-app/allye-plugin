# Allye — OMP (oh-my-pi) installation guide

OMP is a fork of Pi and reads the same package manifest (`omp`, falling back to `pi`, in `package.json`), so it uses the same `allye-pi` package: the Allye bootstrap, the Bridge skill (`/bridge <mode>`) and the repository-to-project identification. See [install-pi.md](install-pi.md) for what the extension does.

> Verified against OMP 18.4: plugin install from npm, the `pi` manifest fallback, the `before_agent_start`/`resources_discover` extension events, user skills in `~/.omp/agent/skills`, and the `/mcp add` command. End-to-end runs of the extension inside OMP are not yet covered by tests.

## Install the package

```text
omp plugin install allye-pi
```

Update with `omp plugin upgrade allye-pi`; remove with `omp plugin uninstall allye-pi`.

## Configure the MCP server

OMP has a native MCP client (no `pi-mcp-adapter`). Add the server once, at user scope:

```text
/mcp add allye --scope user --url https://mcp.allye.app/mcp --transport http
```

OMP also loads servers from a project `.mcp.json`. Do not add tokens or OAuth client metadata: OMP discovers the OAuth endpoints and opens the browser on first use.

Because OMP's MCP client is not the in-process `pi-mcp-adapter` bridge (as in OMP today), the extension does not resolve the project. It injects only the git remote and any unverified `.allye/project.json` claim; the bootstrap tells the agent to call `projects.project_resolve` itself. The team follows the project, so no team selection is needed.

## Confirm

Tell the user:

> Allye is installed for OMP: the `allye-pi` extension (bootstrap and Bridge) and the `allye` MCP server. Start a new OMP session and run `/bridge survey` (or another mode).

## Organization skills

`./install.sh install omp <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `~/.omp/agent/skills`. OMP presents itself to the API as runtime `pi`, and the skill is installed as a plain directory, with no package receipt.

- Edited copies: `./install.sh install omp <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/omp/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/omp/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
