<p align="center">
  <strong>Fenix Agent Plugin</strong><br>
  <em>Structured workflows and specialized agents for AI coding tools</em>
</p>

<p align="center">
  <a href="https://github.com/fenix-assistant/fenix-plugin/releases"><img src="https://img.shields.io/github/v/release/fenix-assistant/fenix-plugin" alt="Release"></a>
  <a href="https://github.com/fenix-assistant/fenix-plugin/blob/main/LICENSE"><img src="https://img.shields.io/github/license/fenix-assistant/fenix-plugin" alt="License"></a>
  <img src="https://img.shields.io/badge/Claude_Code-supported-blue" alt="Claude Code">
  <img src="https://img.shields.io/badge/OpenCode-supported-green" alt="OpenCode">
  <img src="https://img.shields.io/badge/Cursor-supported-purple" alt="Cursor">
  <img src="https://img.shields.io/badge/Codex-supported-orange" alt="Codex">
  <img src="https://img.shields.io/badge/Gemini_CLI-supported-red" alt="Gemini CLI">
</p>

---

Your AI agent has **68+ tools** but no idea when to use them. Fenix adds the methodology layer — structured workflows, specialized agents, cross-session memory, and team-specific skills — so your agent plans before coding, tests before shipping, and remembers what happened yesterday.

## What you get

| | Feature | Description |
|---|---------|-------------|
| **Agents** | Specialized agents | Fenix Plan, Build, Review, Deliver — each focused on one workflow phase |
| **Planning** | Discussion phase | Gray areas identified, options presented with trade-offs, decisions captured |
| **Memory** | Cross-session continuity | Agent searches past context at start, saves session state at end |
| **TDD** | Test-driven development | Red-Green-Refactor with automatic detection of when TDD applies |
| **Skills** | Dynamic loading | Agents discover and follow your team's custom skills (any language) |
| **Boards** | Status progression | Correct transitions: backlog → todo → in_progress → review → done |
| **Context** | Auto-loaded profile | User context, team info, and preferences injected before first message |

---

## Installation

### Claude Code

```
/plugin marketplace add fenix-assistant/fenix-plugin
/plugin install fenix
/fenix-setup
```

The plugin auto-configures MCP server, SessionStart hook, and 11 workflow skills. `/fenix-setup` asks for your PAT once and saves it. Done.

After installing, you get:
- **Bootstrap hook** — injects workflow methodology at session start
- **4 subagents** — planner, builder, reviewer, deliverer (delegated via Agent tool)
- **11 skills** — loaded on-demand by the orchestrator

### OpenCode

Paste this into your agent:

```
Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-opencode.md
```

The agent will ask for your PAT, configure the MCP server, install the `fenix-opencode` plugin, and seed skills.

After installing, you get:
- **5 agents in the picker** — Fenix, Fenix Plan, Fenix Build, Fenix Review, Fenix Deliver (Ctrl+T to switch)
- **Auto-loaded context** — your profile and team info injected before every conversation
- **Dynamic skill loading** — agents search for your team's custom skills via MCP

### Cursor

Paste this into Cursor's agent chat:

```
Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-cursor.md
```

After installing:
- **MCP server** configured in `~/.cursor/mcp.json`
- **`.cursorrules`** installed with workflow routing and non-negotiable rules
- **Skills seeded** into your Fenix database

### Codex (OpenAI)

Paste this into Codex:

```
Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-codex.md
```

After installing:
- **MCP server** configured in `~/.codex/config.toml`
- **`AGENTS.md`** installed with workflow instructions
- **Skills seeded** into your Fenix database

### Gemini CLI

Paste this into Gemini:

```
Install fenix-plugin following: https://raw.githubusercontent.com/fenix-assistant/fenix-plugin/main/docs/install-gemini.md
```

After installing:
- **MCP server** configured in `~/.gemini/settings.json`
- **`GEMINI.md`** installed with workflow instructions
- **Skills seeded** into your Fenix database

### Manual (all agents)

```bash
git clone https://github.com/fenix-assistant/fenix-plugin.git
cd fenix-plugin
./install.sh
```

Auto-detects installed agents and configures MCP + skills for each one.

---

## Agents

On platforms that support multi-agent (OpenCode, Claude Code), you get 5 specialized agents:

| Agent | Who uses it | What it does |
|-------|------------|-------------|
| **Fenix** | Everyone | Orchestrator — initializes context, detects workflow phase, delegates to the right agent |
| **Fenix Plan** | PO, tech lead, dev | All planning — from business requirements (epics/features/stories) to technical breakdown (discussion phase → tasks). Adapts level to who's talking. |
| **Fenix Build** | Dev | Picks up tasks and implements them. TDD discipline, read-first rule, wave execution. Doesn't plan — executes. |
| **Fenix Review** | Dev, tech lead | Reviews code with full context from planning decisions. Validates acceptance criteria one by one. |
| **Fenix Deliver** | Dev | Closes the story. Verifies all tasks done, updates documentation, cleans up TODOs, saves delivery summary. |

Every agent:
- Calls `initialize` to load your profile and team context
- Searches memories for past decisions and session state
- Loads team-specific skills dynamically via `skill_list`
- Saves session state before ending

On platforms without multi-agent (Cursor, Codex, Gemini CLI), a single agent handles all phases with the same workflow knowledge.

---

## Workflow

```
Product Planning → Technical Planning → Development → Review → Delivery
       ↑                                                          |
       └──────────────────── next story ──────────────────────────┘
```

### Product Planning
Understand business context → define hierarchy (Epic → Feature → Story) → create work items with acceptance criteria.

### Technical Planning
Get story → **discussion phase** (identify gray areas, present options with trade-offs, capture locked decisions) → create tasks with dependency waves.

### Development
Pick task → read existing code first → TDD (Red → Green → Refactor) → mark done → next task.

### Review
Load planning decisions → review each task against acceptance criteria → check code quality, security, test coverage → approve or request changes.

### Delivery
Verify all tasks done → close story → update documentation → clean up TODOs → save delivery memory.

---

## Skills

Skills are the knowledge base that powers the agents. They're loaded on-demand — not all at once.

| Skill | What it teaches |
|-------|----------------|
| `using-fenix` | Bootstrap — memory protocol, skill routing, workflow gates |
| `fenix-product-planning` | Business requirements → Epics → Features → Stories |
| `fenix-technical-planning` | Story → Discussion Phase → Tasks with acceptance criteria |
| `fenix-technical-development` | Task → TDD → Implementation with wave execution |
| `fenix-technical-review` | Code review with decision context from planning |
| `fenix-technical-delivery` | Verify → Close story → Update docs → Save memory |
| `fenix-memory-protocol` | When and how to search/save memories across sessions |
| `fenix-tdd-workflow` | Red-Green-Refactor cycle with detection heuristic |
| `fenix-board-progression` | Status transitions and board mechanics |
| `fenix-tools-quickref` | Complete reference for all 12 MCP tools and 68+ actions |

Your team can also create **custom skills** in Fenix (code review standards, dev guidelines, etc.) — agents discover and follow them automatically.

---

## Prerequisites

- A [Fenix](https://fenix.devshire.app) account with a Personal Access Token (PAT)
- At least one supported AI coding agent installed
- `jq` and `curl` (used by the installer and Claude Code hook)

## License

MIT
