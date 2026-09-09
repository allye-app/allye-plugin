# allye-opencode

An [OpenCode](https://opencode.ai) plugin that registers 6 specialized Allye agents for the guided delivery workflow:

- **Allye — Router** — initializes context, detects the workflow phase, and delegates to the agent below
- **Allye Plan** — product planning (epics/features/stories) and technical planning (discussion phase, trade-offs, tasks)
- **Allye Orchestrator** — coordinates delivery of an already-planned feature: assigns work, tracks status, drives review
- **Allye Build** — TDD implementation of tasks
- **Allye Review** — code review with full context
- **Allye Deliver** — finalizes delivery, closes stories, updates docs

Account context is loaded through the configured `allye` MCP server, so OpenCode owns OAuth credentials and refresh.

## Installation

This package is not typically installed standalone. Add it with the Allye MCP server by following the main plugin's OpenCode installation guide. The repository installer intentionally leaves shared runtime configuration unchanged unless an API-backed ownership operation authorizes the write.

If you do need to add it manually, add it to the `plugin` array in your OpenCode config:

```json
{
  "plugin": ["allye-opencode"]
}
```

## Documentation

For full workflow documentation — the guided delivery methodology, the phase skills, and the handover protocol this plugin implements — see the main repo: [github.com/allye-app/allye-plugin](https://github.com/allye-app/allye-plugin).
