# Fenix Agent Plugin

A methodology and workflow layer that teaches AI coding agents how to use the [Fenix](https://fenix.devshire.app) platform effectively.

## What it does

The Fenix MCP server gives your AI agent **12 tools with 68+ actions** for managing work items, documentation, sprints, memories, and more. But tools alone aren't enough — agents need to know **when and how** to use them.

This plugin adds:

- **Structured workflows** — Product Planning → Technical Planning → Development → Review → Delivery
- **Memory protocol** — Cross-session continuity so context is never lost
- **TDD discipline** — Red-Green-Refactor with detection heuristics
- **Board progression** — Correct status transitions for work items
- **Discussion phase** — Gray area identification, trade-off analysis, and decision capture

## Supported agents

| Agent | MCP Config | Manifest |
|-------|-----------|----------|
| Claude Code | `~/.claude.json` | SessionStart hook |
| Cursor | `~/.cursor/mcp.json` | `.cursorrules` |
| OpenCode | `~/.config/opencode/opencode.json` | `opencode.json` |
| Codex (OpenAI) | `~/.codex/config.toml` | `AGENTS.md` |
| Gemini CLI | `~/.gemini/settings.json` | `GEMINI.md` |

## Quick start

### Claude Code (recommended)

```
/plugin marketplace add fenix-assistant/fenix-plugin
/plugin install fenix
/fenix-setup
```

That's it. The plugin auto-configures the MCP server, SessionStart hook, and all workflow skills. The `/fenix-setup` command asks for your PAT once and saves it.

### Other agents (Cursor, OpenCode, Codex, Gemini CLI)

```bash
git clone https://github.com/fenix-assistant/fenix-plugin.git
cd fenix-plugin
./install.sh
```

The installer will:
- Ask for your Fenix PAT
- Validate credentials
- Seed 10 workflow skills into your Fenix database
- Auto-detect installed agents and configure their MCP server

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
├── .claude-plugin/
│   ├── plugin.json                  # Claude Code plugin manifest
│   └── marketplace.json             # Self-hosted marketplace
├── .mcp.json                        # MCP server config (uses $FENIX_PAT)
├── hooks/
│   ├── hooks.json                   # Claude Code hook definitions
│   └── session-start.sh             # Injects bootstrap skill at session start
├── skills/                          # Claude Code plugin skills (SKILL.md format)
│   ├── using-fenix/                 # Bootstrap meta-skill
│   ├── fenix-setup/                 # /fenix-setup slash command
│   ├── fenix-product-planning/      # Requirements → work items
│   ├── fenix-technical-planning/    # Story → tasks (discussion phase)
│   ├── fenix-technical-development/ # TDD implementation
│   ├── fenix-technical-review/      # Code review with context
│   ├── fenix-technical-delivery/    # Finalize and deliver
│   ├── fenix-memory-protocol/       # Cross-session continuity
│   ├── fenix-tdd-workflow/          # Red-Green-Refactor
│   ├── fenix-board-progression/     # Status transitions
│   └── fenix-tools-quickref/        # Tools cheat sheet
├── manifests/                       # Other agents (non-Claude Code)
│   ├── cursor/.cursorrules
│   ├── opencode/opencode.json
│   ├── codex/AGENTS.md
│   └── gemini/GEMINI.md
├── seed/seed-skills.json            # Skill definitions for DB seeding
└── install.sh                       # Multi-agent installer (non-Claude Code)
```

## Requirements

- A [Fenix](https://fenix.devshire.app) account with a Personal Access Token
- At least one supported AI coding agent installed
- `jq` and `curl` (used by the installer and Claude Code hook)

## License

MIT
