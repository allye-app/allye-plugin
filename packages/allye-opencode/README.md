# allye-opencode

An [OpenCode](https://opencode.ai) plugin for [Allye](https://allye.app). It:

- registers the **Bridge** skill (`/bridge <mode>`) bundled in this package as an extra OpenCode skill path;
- adds the shared Allye bootstrap to the system prompt, so the agent knows the Allye MCP (`projects`, `epics`, `specs`, `tasks`, `team`) and Bridge are available.

The Allye MCP server is configured separately in `opencode.json`; OpenCode owns its OAuth credentials and refresh. The plugin never reads tokens.

## Installation

Follow the main repository's guide: [docs/install-opencode.md](https://github.com/allye-app/allye-plugin/blob/main/docs/install-opencode.md). Manually, add the plugin and the server to your OpenCode config:

```json
{
  "mcp": { "allye": { "type": "remote", "url": "https://mcp.allye.app/mcp", "enabled": true } },
  "plugin": ["allye-opencode"]
}
```

## Development

The package is built from the repository's single sources: `bootstrap/allye.md` and `skills/bridge*`. `bun run build` copies them in (`scripts/prepare.ts`) and bundles `dist/index.js`; `bun run typecheck` runs the same preparation and `tsc --noEmit`.
