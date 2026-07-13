<p align="center">
  <strong>Allye Agent Plugin</strong><br>
  <em>Structured workflows and specialized agents for AI coding tools</em>
</p>

<p align="center">
  <a href="https://github.com/allye-app/allye-plugin/releases"><img src="https://img.shields.io/github/v/release/allye-app/allye-plugin" alt="Release"></a>
  <a href="https://github.com/allye-app/allye-plugin/blob/main/LICENSE"><img src="https://img.shields.io/github/license/allye-app/allye-plugin" alt="License"></a>
  <a href="https://www.npmjs.com/package/allye-opencode"><img src="https://img.shields.io/npm/v/allye-opencode" alt="npm"></a>
  <img src="https://img.shields.io/badge/Claude_Code-supported-blue" alt="Claude Code">
  <img src="https://img.shields.io/badge/OpenCode-supported-green" alt="OpenCode">
  <img src="https://img.shields.io/badge/Cursor-supported-purple" alt="Cursor">
  <img src="https://img.shields.io/badge/Codex-supported-orange" alt="Codex">
  <img src="https://img.shields.io/badge/Gemini_CLI-supported-red" alt="Gemini CLI">
</p>

---

Your AI agent has **68+ tools** but no idea when to use them. Allye adds the methodology layer — structured workflows, specialized agents, cross-session memory, and team-specific skills — so your agent plans before coding, tests before shipping, and remembers what happened yesterday.

**Authentication is handled via OAuth 2.1** — your browser opens once for login, and tokens are managed automatically. No API keys or PATs to configure.

## What you get

| | Feature | Description |
|---|---------|-------------|
| **Agents** | Specialized agents | Allye Plan, Build, Review, Deliver — each focused on one workflow phase |
| **Planning** | Discussion phase | Gray areas identified, options presented with trade-offs, decisions captured |
| **Memory** | Cross-session continuity | Agent searches past context at start, saves session state at end |
| **TDD** | Test-driven development | Red-Green-Refactor with automatic detection of when TDD applies |
| **Skills** | Dynamic discovery | Agents find and follow your team's standards automatically — no manual config |
| **Standards** | Guided creation | No team standards? Agent suggests creating them with your chosen scope |
| **Boards** | Status progression | Correct transitions: backlog → todo → in_progress → review → done |
| **Context** | Auto-loaded profile | User context, team info, and preferences injected before first message |
| **Language** | Multi-language | Agent responds in your language — configs are English, conversations are yours |

---

## Installation

### Claude Code

**Step 1 — Install the plugin:**
```
/plugin marketplace add allye-app/allye-plugin
/plugin install allye
/reload-plugins
```

**Step 2 — Authenticate:**
1. Run `/plugin` to open the plugin panel
2. Find **Allye MCP Server** and click **Connect**
3. Your browser opens for OAuth login — sign in with your Allye account, select a team, and approve
4. Done! The MCP server connects automatically

> **No PAT needed.** Authentication is handled via OAuth 2.1 — your browser opens once, and tokens are cached automatically.

After installing, you get:
- **OAuth authentication** — browser-based login, no tokens to manage
- **Bootstrap hook** — injects workflow methodology at session start
- **4 subagents** — planner, builder, reviewer, deliverer (delegated via Agent tool)
- **11 skills** — loaded on-demand by the orchestrator

#### Multiple Allye accounts (multi-tenant)

If you use different Allye accounts in different projects (e.g., personal account in `~/dev/myproject` and work account in `~/dev/company`), install the plugin with the **"local" scope** (per-project). Each project directory automatically gets its own OAuth session — no extra configuration needed.

1. Open Claude Code in each project directory
2. Install with local scope: `/plugin install allye` (select "local" when prompted)
3. Run `/reload-plugins`
4. Go to `/plugin` → **Connect** on the Allye MCP Server
5. Log in with the Allye account you want for that project

The plugin automatically generates a unique identifier per project directory, so each project authenticates independently. You can use a different Allye account in each project without conflicts.

> **Single account users don't need this.** If you only use one Allye account, just install and authenticate — it works out of the box.

**To update:** `/plugin update allye` then `/reload-plugins`

### OpenCode

Paste this into your agent:

```
Install allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-opencode.md
```

The agent will ask for your PAT, configure the MCP server, and install the `allye-opencode` plugin.

After installing, you get:
- **5 agents in the picker** — Allye, Allye Plan, Allye Build, Allye Review, Allye Deliver (Ctrl+T to switch)
- **Auto-loaded context** — your profile and team info injected before every conversation
- **Dynamic skill discovery** — agents search for your team's standards via MCP

**To update:** Paste this into your agent:
```
Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-opencode.md
```

### Cursor

Paste this into Cursor's agent chat:

```
Install allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-cursor.md
```

After installing:
- **MCP server** configured in `~/.cursor/mcp.json`
- **`.cursorrules`** installed with workflow routing and non-negotiable rules

**To update:** Paste this into your agent:
```
Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-cursor.md
```

### Codex (OpenAI)

Paste this into Codex:

```
Install allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-codex.md
```

After installing:
- **MCP server** configured in `~/.codex/config.toml`
- **`AGENTS.md`** installed with workflow instructions

**To update:** Paste this into your agent:
```
Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-codex.md
```

### Gemini CLI

Paste this into Gemini:

```
Install allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-gemini.md
```

After installing:
- **MCP server** configured in `~/.gemini/settings.json`
- **`GEMINI.md`** installed with workflow instructions

**To update:** Paste this into your agent:
```
Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-gemini.md
```

### Manual (all agents)

```bash
git clone https://github.com/allye-app/allye-plugin.git
cd allye-plugin
./install.sh
```

Auto-detects installed agents and configures MCP + skills for each one.

**To update:** `cd allye-plugin && git pull && ./install.sh`

---

## Updating

### Claude Code

```
/plugin update allye
/reload-plugins
```

### Other agents (agent-assisted)

Paste this into your agent's chat:

| Agent | Paste this |
|-------|-----------|
| OpenCode | `Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-opencode.md` |
| Cursor | `Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-cursor.md` |
| Codex | `Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-codex.md` |
| Gemini CLI | `Update allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/update-gemini.md` |

### Manual

```bash
cd allye-plugin && git pull && ./install.sh
```

---

## Agents

On platforms that support multi-agent (OpenCode, Claude Code), you get 5 specialized agents:

| Agent | Who uses it | What it does |
|-------|------------|-------------|
| **Allye** | Everyone | Orchestrator — initializes context, detects workflow phase, delegates to the right agent |
| **Allye Plan** | PO, tech lead, dev | All planning — from business requirements (epics/features/stories) to technical breakdown (discussion phase → tasks). Discovers team work item templates. |
| **Allye Build** | Dev | Picks up tasks and implements them. Discovers coding conventions, testing standards. TDD discipline, read-first rule, wave execution. |
| **Allye Review** | Dev, tech lead | Reviews code with planning decision context. Discovers review checklists, security standards, quality gates. |
| **Allye Deliver** | Dev | Closes the story. Discovers documentation templates, deploy checklists. Updates docs, cleans up TODOs. |

Every agent:
- Responds in **your language** (detected from profile or messages)
- Calls `initialize` to load your profile and team context
- **Discovers team skills** before starting — coding standards, templates, checklists
- If no standards found → **suggests creating them** with your chosen scope (personal/team/org/marketplace)
- Searches memories for past decisions and session state
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
Understand business context → discover team templates → define hierarchy (Epic → Feature → Story) → create work items with acceptance criteria.

### Technical Planning
Get story → **discussion phase** (identify gray areas, present options with trade-offs, capture locked decisions) → create tasks with dependency waves.

### Development
Pick task → discover coding standards → read existing code first → TDD (Red → Green → Refactor) → mark done → next task.

### Review
Discover review standards → load planning decisions → review each task against acceptance criteria → check code quality, security, test coverage → approve or request changes.

### Delivery
Discover delivery standards → verify all tasks done → close story → update documentation → clean up TODOs → save delivery memory.

---

## Skills

Skills are the knowledge base that powers the agents. 10 workflow skills are published in the **Allye marketplace** — available to all users without setup.

| Skill | What it teaches |
|-------|----------------|
| `using-allye` | Bootstrap — memory protocol, skill routing, workflow gates |
| `product-planning` | Business requirements → Epics → Features → Stories |
| `technical-planning` | Story → Discussion Phase → Tasks with acceptance criteria |
| `execution` | Task → TDD → Implementation with wave execution |
| `review` | Code review with decision context from planning |
| `delivery` | Verify → Close story → Update docs → Save memory |
| `memory-protocol` | When and how to search/save memories across sessions |
| `tdd-workflow` | Red-Green-Refactor cycle with detection heuristic |
| `board-progression` | Status transitions and board mechanics |
| `tools-quickref` | Complete reference for all 12 MCP tools and 68+ actions |

### Custom team skills

Your team can create custom skills in Allye — agents discover and follow them automatically:

- **Code review checklist** → Allye Review follows it
- **Backend story standard** → Allye Plan uses it as template
- **Deploy checklist** → Allye Deliver follows it
- **Coding conventions** → Allye Build applies them

No team skills yet? Each agent will suggest creating them when it doesn't find standards for its domain.

---

## Prerequisites

- A [Allye](https://allye.app/hq) account with a Personal Access Token (PAT)
- At least one supported AI coding agent installed
- `jq` and `curl` (used by the installer and Claude Code hook)

## License

MIT
