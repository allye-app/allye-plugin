# Allye — Pi installation guide

Allye for Pi is the native package `allye-pi`. It:

- exposes the Bridge skill (`/bridge <mode>`) from the package's `skills/` directory;
- adds the Allye bootstrap (`bootstrap/allye.md`) to the system prompt;
- preloads Allye context (`initialize`, `intelligence`) when an in-process MCP bridge is available, and identifies the repository's project: it resolves the git remote with `projects.project_resolve` and verifies any `.allye/project.json` claim against it, injecting "this repo = project X / app Y (team Z)", the ambiguous candidates, or the disagreement to ask the user about.

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

The extension preloads Allye context only when `pi-mcp-adapter` exposes its in-process bridge. Otherwise it injects only the git remote and any unverified link claim, and the bootstrap tells the agent to call `initialize` and `projects.project_resolve` itself.

## Teams

The team follows the project: the extension never blocks work on team selection. A default team is needed only to create projects; `/allye-team <name|prefix|id>` sets it through the `team` tool (`team_set_default`). Set `ALLYE_PI_NATIVE_BOOTSTRAP=0` to skip the context preload (the bootstrap text and the Bridge skill stay available), or `ALLYE_PI_MCP=0` to disable MCP calls from the extension.

## Local development

From the repository root:

```text
npm install
npm run typecheck
npm run test:pi
pi -e ./packages/allye-pi/src/index.ts -p "Which Allye tools and Bridge modes are available?"
```
