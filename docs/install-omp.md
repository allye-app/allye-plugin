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

Because OMP's MCP client is not the in-process `pi-mcp-adapter` bridge, the extension does not preload Allye context in OMP. It injects only the git remote and any unverified `.allye/project.json` claim; the bootstrap tells the agent to call `projects.project_resolve` itself. The team follows the project, so no team selection is needed.

## Confirm

Tell the user:

> Allye is installed for OMP: the `allye-pi` extension (bootstrap and Bridge) and the `allye` MCP server. Start a new OMP session and run `/bridge survey` (or another mode).
