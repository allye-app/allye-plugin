# Fenix Agent Plugin

A methodology and workflow layer that teaches AI coding agents how to use the [Fenix](https://fenix.devshire.app) platform effectively.

## What it does

The Fenix MCP server gives your AI agent **12 tools with 68+ actions** for managing work items, documentation, sprints, memories, and more. But tools alone aren't enough — agents need to know **when and how** to use them.

This plugin adds:

- **Specialized agents** — Fenix Plan, Build, Review, Deliver — each focused on a workflow phase
- **Structured workflows** — Product Planning → Technical Planning → Development → Review → Delivery
- **Memory protocol** — Cross-session continuity so context is never lost
- **TDD discipline** — Red-Green-Refactor with detection heuristics
- **Board progression** — Correct status transitions for work items
- **Discussion phase** — Gray area identification, trade-off analysis, and decision capture
- **Dynamic skill loading** — Agents discover and follow team-specific skills automatically

## Agents

| Agent | What it does | Available on |
|-------|-------------|-------------|
| **Fenix** | Orchestrator — init, memory, detect phase, delegate | OpenCode, Claude Code |
| **Fenix Plan** | Product + technical planning, discussion phase, trade-offs | OpenCode, Claude Code |
| **Fenix Build** | TDD implementation, read-first, wave execution | OpenCode, Claude Code |
| **Fenix Review** | Code review with decision context, acceptance criteria | OpenCode, Claude Code |
| **Fenix Deliver** | Close story, update docs, clean TODOs | OpenCode, Claude Code |

Other agents (Cursor, Codex, Gemini CLI) use a single-agent mode with the same workflow knowledge.

## Quick start

### Claude Code (recommended)

```
/plugin marketplace add fenix-assistant/fenix-plugin
/plugin install fenix
/fenix-setup
```

That's it. The plugin auto-configures the MCP server, SessionStart hook, and all workflow skills. The `/fenix-setup` command asks for your PAT once and saves it.

### OpenCode, Cursor, Codex, Gemini CLI (agent-assisted)

Paste this into your agent's chat:

| Agent | Paste this |
|-------|-----------|
| OpenCode | `Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-opencode.md` |
| Cursor | `Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-cursor.md` |
| Codex | `Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-codex.md` |
| Gemini CLI | `Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-gemini.md` |

The agent will fetch the guide, ask for your PAT, and configure everything automatically.

### Manual (all agents)

```bash
git clone https://github.com/fenix-assistant/fenix-plugin.git
cd fenix-plugin
./install.sh
```

The installer auto-detects installed agents and configures MCP + skills for each one.

## Skills included

### Bootstrap
| Skill | Description |
|-------|-------------|
| `using-fenix` | Entry point — memory protocol, skill routing, workflow gates |

### Workflows
| Skill | Description |
|-------|-------------|
| `fenix-product-planning` | Business requirements → Epics → Features → Stories |
| `fenix-technical-planning` | Story → Discussion Phase → Tasks with acceptance criteria |
| `fenix-technical-development` | Task → TDD → Implementation with wave execution |
| `fenix-technical-review` | Code review with decision context from planning |
| `fenix-technical-delivery` | Verify → Close story → Update docs → Save memory |

### Methodology
| Skill | Description |
|-------|-------------|
| `fenix-memory-protocol` | When and how to search/save memories for cross-session continuity |
| `fenix-tdd-workflow` | Red-Green-Refactor cycle, detection heuristic, test quality |
| `fenix-board-progression` | Status transitions, work_status_next/done mechanics |

### Reference
| Skill | Description |
|-------|-------------|
| `fenix-tools-quickref` | Complete cheat sheet for all 12 MCP tools and 68+ actions |

## How it works

```
Session starts
    ↓
Bootstrap skill loads (using-fenix)
    ↓
Agent searches memories for context
    ↓
Agent detects workflow phase from user intent
    ↓
Agent loads the appropriate skill on-demand
    ↓
Agent follows the skill's structured workflow
    ↓
Agent saves session state before ending
```

### Workflow flow

```
Product Planning → Technical Planning → Development → Review → Delivery
       ↑                                                          |
       └──────────────────── next story ──────────────────────────┘
```

## Project structure

```
fenix-plugin/
├── .claude-plugin/                    # Claude Code plugin manifest
├── .mcp.json                          # MCP server config
├── hooks/                             # Claude Code SessionStart hook
├── agents/                            # Claude Code subagents
│   ├── fenix-planner.md
│   ├── fenix-builder.md
│   ├── fenix-reviewer.md
│   └── fenix-deliverer.md
├── skills/                            # Shared skills (source of truth)
│   ├── using-fenix/                   # Bootstrap meta-skill
│   ├── fenix-setup/                   # /fenix-setup slash command
│   ├── fenix-product-planning/        # Product planning workflow
│   ├── fenix-technical-planning/      # Technical planning (discussion phase)
│   ├── fenix-technical-development/   # TDD implementation
│   ├── fenix-technical-review/        # Code review
│   ├── fenix-technical-delivery/      # Delivery
│   ├── fenix-memory-protocol/         # Memory protocol
│   ├── fenix-tdd-workflow/            # TDD discipline
│   ├── fenix-board-progression/       # Status transitions
│   └── fenix-tools-quickref/          # Tools reference
├── packages/
│   └── fenix-opencode/               # OpenCode multi-agent plugin (npm)
│       ├── src/agents/                # 5 TypeScript agent definitions
│       ├── src/prompts/               # Prompt builder + shared fragments
│       ├── src/context.ts             # Auto-injects user context
│       └── src/index.ts               # Plugin entry point
├── manifests/                         # Other agents (Cursor, Codex, Gemini)
├── seed/seed-skills.json              # Skill definitions for DB seeding
├── install.sh                         # Multi-agent installer
└── release.sh                         # Automated release script
```

## Requirements

- A [Fenix](https://fenix.devshire.app) account with a Personal Access Token
- At least one supported AI coding agent installed
- `jq` and `curl` (used by the installer and Claude Code hook)

## License

MIT
