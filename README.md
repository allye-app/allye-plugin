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

### 1. Get a Fenix PAT

Sign in to [Fenix](https://fenix.devshire.app), go to **Settings → API → Generate Token**.

### 2. Run the installer

```bash
git clone https://github.com/fenix-assistant/fenix-plugin.git
cd fenix-plugin
./install.sh
```

The installer will:
- Validate your PAT
- Seed 10 workflow skills into your Fenix database
- Auto-detect installed agents and configure their MCP server
- Set up the Claude Code SessionStart hook (if applicable)

### 3. Start a new session

Open your AI agent and start working. The plugin will guide the agent through Fenix workflows automatically.

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
├── skills/
│   ├── bootstrap/
│   │   └── using-fenix.md           # Entry point meta-skill
│   ├── workflows/
│   │   ├── product-planning.md      # Requirements → work items
│   │   ├── technical-planning.md    # Story → tasks (discussion phase)
│   │   ├── technical-development.md # TDD implementation
│   │   ├── technical-review.md      # Code review with context
│   │   └── technical-delivery.md    # Finalize and deliver
│   ├── methodology/
│   │   ├── memory-protocol.md       # Cross-session continuity
│   │   ├── tdd-workflow.md          # Red-Green-Refactor
│   │   └── board-progression.md     # Status transitions
│   └── reference/
│       └── fenix-tools-quickref.md  # Tools cheat sheet
├── manifests/
│   ├── claude/hooks/session-start.sh
│   ├── cursor/.cursorrules
│   ├── opencode/opencode.json
│   ├── codex/AGENTS.md
│   └── gemini/GEMINI.md
├── seed/seed-skills.json            # Skill definitions for DB seeding
└── install.sh                       # One-command installer
```

## Requirements

- A [Fenix](https://fenix.devshire.app) account with a Personal Access Token
- At least one supported AI coding agent installed
- `jq` and `curl` (used by the installer and Claude Code hook)

## License

MIT
