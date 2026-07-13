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

**[Create a free Allye account →](https://allye.app/)**

**Authentication is handled via OAuth 2.1 on Claude Code** — your browser opens once for login, and tokens are managed automatically. No API keys or PATs to configure. Other platforms (OpenCode, Cursor, Codex, Gemini CLI) authenticate with a Personal Access Token — see Prerequisites below.

## What you get

| | Feature | Description |
|---|---------|-------------|
| **Workflow** | Guided delivery | Sandbox → Product Planning → Technical Planning → Orchestrator → Executor → Reviewer, connected by handovers between fresh, lean-context chats |
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
- **4 dispatched subagents** — reviewer, deep-search, code-analyzer, executor, delegated via the Agent tool for phases that don't need to pause and ask you anything (executor only runs this way if you opt into automatic mode — manual is the default)
- **14 skills** — Sandbox, Planning, Technical Planning, Orchestrator, and Delivery run as skills loaded directly into your conversation, loaded on-demand by the bootstrap, so they can ask you questions when something's ambiguous

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
- **6 agents in the picker** — Allye, Allye Plan, Allye Orchestrator, Allye Build, Allye Review, Allye Deliver (Ctrl+T to switch)
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

How multi-phase workflow support is implemented differs by platform, because not every platform lets a dispatched agent pause mid-task to ask you a question:

- **Claude Code** ships four dispatched subagents — **Reviewer**, **Deep Search**, **Code Analyzer**, and **Executor** — for phases that never need to interrupt you (Executor only runs this way if the Orchestrator's automatic mode is chosen for a story; its default is manual). Sandbox, Product Planning, Technical Planning, Orchestrator, and manual-mode Executor run as skills loaded directly into your conversation instead, precisely so they *can* stop and ask when something's ambiguous.
- **OpenCode** ships 6 agent-picker personas (Ctrl+T to switch) — Allye, Allye Plan, Allye Orchestrator, Allye Build, Allye Review, Allye Deliver — OpenCode's agent model supports switching personas interactively within a session, so all 6 can be full agents. The automatic-Executor dispatch mode is Claude-Code-only for now; OpenCode always runs Executor (Allye Build) as an interactive agent.
- **Cursor, Codex, Gemini CLI** — a single agent handles all phases with the same workflow knowledge (no multi-agent picker on these platforms).

Every phase, on every platform:
- Responds in **your language** (detected from profile or messages)
- Calls `initialize` to load your profile and team context
- **Discovers team skills** before starting — coding standards, templates, checklists
- If no standards found → **suggests creating them** with your chosen scope (personal/team/org/marketplace)
- Searches memories for past decisions and session state
- Saves session state before ending

---

## Workflow

Each phase runs in its own fresh, lean-context chat. When one finishes, it emits a **handover** — a block of chat text you review and paste as the first message of the next chat, which auto-detects it and loads the right skill.

```
Sandbox → Product Planning → Technical Planning → Orchestrator ⇄ Executor → Reviewer
                                                        ↑                       |
                                                        └──── next story ───────┘
```

### Sandbox
Explore ideas, research before committing to scope, think out loud — no work items created here. Dispatches Deep Search / Code Analyzer subagents for research. Exits with a Discovery Doc once a direction is approved.

### Product Planning
Understand business context → discover team templates → define hierarchy (Epic → Feature → Story) → create work items with acceptance criteria.

### Technical Planning
Get story → **discussion phase** (identify gray areas, present options with trade-offs, capture locked decisions) → create tasks with dependency waves.

### Orchestrator
Coordinates delivery of an already-planned feature: manages assignee and status, dispatches **Executor** one story at a time (manual handover, or automatic subagent dispatch — your choice per story), dispatches **Reviewer** in parallel once a report comes back, runs the correction loop, and cascades status up the work-item hierarchy.

### Executor
Implements exactly one story's tasks with TDD (Red → Green → Refactor). Runs either as an interactive skill (manual mode, can ask you questions) or as a dispatched subagent (automatic mode — halts and reports back instead of guessing when a task is underspecified).

### Reviewer
Reviews each task against acceptance criteria — code quality, security, test coverage — always dispatched automatically in parallel, since review never needs to pause and ask anyone anything.

### Delivery
Once an epic's whole status cascade completes, the Orchestrator offers — never forces — a close-out: verify all tasks done, update documentation, clean up TODOs, save a delivery memory. A deliberate step, not an automatic one.

---

## Skills

Skills are the knowledge base that powers the agents. 13 workflow skills are published in the **Allye marketplace** — available to all users without setup (`setup` itself is Claude Code's local install-time skill and isn't marketplace-published).

| Skill | What it teaches |
|-------|----------------|
| `using-allye` | Bootstrap — memory protocol, skill routing, handover detection, workflow gates |
| `sandbox` | Explore ideas, research a direction, exit with a Discovery Doc — no work items created |
| `product-planning` | Business requirements → Epics → Features → Stories |
| `technical-planning` | Story → Discussion Phase → Tasks with acceptance criteria |
| `orchestrator` | Coordinate delivery — assignee, dispatch Executor/Reviewer, correction loop, status cascade |
| `execution` | Task → TDD → Implementation with wave execution |
| `review` | Code review with decision context from planning |
| `delivery` | Verify → Close story → Update docs → Save memory |
| `handover-protocol` | The shared contract for handing off context between phases as chat text |
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

- An [Allye](https://allye.app/) account
  - **Claude Code** — OAuth 2.1, handled entirely through the plugin's connect flow. No PAT needed.
  - **OpenCode, Cursor, Codex, Gemini CLI** — a Personal Access Token (PAT), generated from your Allye account settings.
- At least one supported AI coding agent installed
- `jq` and `curl` (used by the installer and Claude Code hook)

## Contributing

Issues and PRs are welcome. Open an issue first for anything beyond a small fix, so the approach can be agreed on before you write code. PRs are reviewed before merge — expect feedback, and please keep unrelated changes out of a single PR.

## Roadmap

Today, Allye Agent Plugin is built around the Allye workspace. The long-term direction is to make the workflow layer (planning, orchestration, TDD, memory) work with other backends too — issue trackers like Jira and Linear, and memory stores like Obsidian or other local options — so teams can keep their existing tools and still get the methodology layer on top. Nothing here is scheduled yet; treat it as direction, not a commitment.

## License

MIT
