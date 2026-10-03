<p align="center">
  <strong>Allye Agent Plugin</strong><br>
  <em>Structured workflows and specialized agents for AI coding tools</em>
</p>

<p align="center">
  <a href="https://github.com/allye-app/allye-plugin/releases"><img src="https://img.shields.io/github/v/release/allye-app/allye-plugin" alt="Release"></a>
  <a href="https://github.com/allye-app/allye-plugin/blob/main/LICENSE"><img src="https://img.shields.io/github/license/allye-app/allye-plugin" alt="License"></a>
  <a href="https://www.npmjs.com/package/allye-opencode"><img src="https://img.shields.io/npm/v/allye-opencode" alt="npm"></a>
  <a href="https://www.npmjs.com/package/allye-pi"><img src="https://img.shields.io/npm/v/allye-pi" alt="npm"></a>
  <img src="https://img.shields.io/badge/Claude_Code-supported-blue" alt="Claude Code">
  <img src="https://img.shields.io/badge/OpenCode-supported-green" alt="OpenCode">
  <img src="https://img.shields.io/badge/Cursor-supported-purple" alt="Cursor">
  <img src="https://img.shields.io/badge/Codex-supported-orange" alt="Codex">
  <img src="https://img.shields.io/badge/Gemini_CLI-supported-red" alt="Gemini CLI">
  <img src="https://img.shields.io/badge/Hermes_Agent-supported-yellow" alt="Hermes Agent">
  <img src="https://img.shields.io/badge/Pi-supported-cyan" alt="Pi">
</p>

---

Your AI agent has **68+ tools** but no idea when to use them. Allye adds the methodology layer — structured workflows, specialized agents, cross-session memory, and team-specific skills — so your agent plans before coding, tests before shipping, and remembers what happened yesterday.

**[Create a free Allye account →](https://allye.app/)**

**Authentication is handled via OAuth 2.1** — on every supported platform, since the MCP connection itself is OAuth-gated. Your browser opens once for login, and tokens are managed automatically.

## What you get

| | Feature | Description |
|---|---------|-------------|
| **Workflow** | Adaptive toolkit | Intent-driven use of context, skills, optional planning/tasks, action, verification, and persistence; checkpoints can be skipped or repeated proportionally |
| **Planning** | Discussion phase | Gray areas identified, options presented with trade-offs, decisions captured |
| **Memory** | Cross-session continuity | Agent searches past context at start, saves session state at end |
| **TDD** | Test-driven development | Red-Green-Refactor with automatic detection of when TDD applies |
| **Skills** | Dynamic discovery | Agents find and follow your team's standards automatically — no manual config |
| **Standards** | Guided creation | No team standards? Agent suggests creating them with your chosen scope |
| **Projects** | Epic → Spec → Task | Specs hold the rules and criteria (`[BR-NN]`, `[AC-NN]` anchors); thin tasks reference them; fixed flows with explicit transitions |
| **Context** | On-demand profile | Agents load user context, team info, and preferences through the authenticated `allye` MCP tools |
| **Language** | Multi-language | Agent responds in your language — configs are English, conversations are yours |

---

## Installation

### Repository installer boundary

The repository includes config-shape adapters and distribution verification, but
shared runtime writes are currently fail-closed unless an API-backed ownership
operation authorizes them. Physical uninstall is also blocked. Use the native
platform procedures below; `./install.sh status` is safe for local inspection.

```bash
git clone https://github.com/allye-app/allye-plugin.git
cd allye-plugin
./install.sh status
```

A blocked `./install.sh install ...` or `./install.sh uninstall ...` result means
no shared configuration was changed. It is not installation or cleanup success.

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
3. Your browser opens for OAuth login — sign in with your Allye account, select a tenant, and approve
4. Done! The MCP server connects automatically

> Authentication is handled via OAuth 2.1 — your browser opens once, and tokens are cached automatically.

After installing, you get:
- **OAuth authentication** — browser-based login, no tokens to manage
- **Bootstrap hook** — injects workflow methodology at session start
- **Optional delegation** — bounded research, review, or execution subagents may be used when the runtime supports them and delegation is beneficial; local execution remains valid
- **17 composable skills** — discovery, planning, execution, review, delivery, memory, verification, and delegation playbooks loaded as needed; no universal phase chain is required
- **Parallel delivery, when a runtime is detected** — the Orchestrator can drive several independent specs at once, each in its own git worktree and its own watchable agent process; without a detected runtime, delivery degrades to the existing manual and automatic-subagent modes

#### Tenant selection

Every project uses the same `allye` server URL:
`https://mcp.allye.app/mcp`. Choose the tenant during OAuth consent. Separate
authorizations create independent grants without encoding a tenant or account in
the URL.

**To update:** `/plugin update allye` then `/reload-plugins`

### OpenCode

Paste this into your agent:

```
Install allye-plugin following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-opencode.md
```

The agent will configure the MCP server via OAuth and install the `allye-opencode` plugin.

After installing, you get:
- **6 agents in the picker** — Allye, Allye Plan, Allye Orchestrator, Allye Build, Allye Review, Allye Deliver (Ctrl+T to switch)
- **Adaptive context** — profile, team info, and relevant memories loaded when Allye is available and useful
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
- **`allye` MCP server** at `https://mcp.allye.app/mcp`, authenticated by Codex's native OAuth flow
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

### Pi

Pi uses the published native package `allye-pi`, while keeping
`skills/*/SKILL.md` as the only canonical skill source. Install through Pi's
package manager:

```bash
pi install npm:allye-pi
```

Configure one `allye` server at `https://mcp.allye.app/mcp` in the effective
pi-mcp-adapter source, then run `/mcp-auth allye` and `/mcp reconnect allye`.
The package and repository installer do not edit Pi's MCP configuration. See
[`docs/install-pi.md`](docs/install-pi.md) for source selection, authentication,
and the installer boundary.

### Hermes Agent

Follow [`docs/install-hermes.md`](docs/install-hermes.md) for its native package
and OAuth procedure. The repository installer preserves its fail-closed
ownership boundary and must not be described as a general-purpose config writer
or cleanup command.

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
| Hermes Agent | see [`docs/update-hermes.md`](docs/update-hermes.md) for the native update procedure |

The repository's `install.sh` remains an inspection and API-authorized
distribution boundary; it does not replace these native updates.

---

## Agents

How multi-phase workflow support is implemented differs by platform, because not every platform lets a dispatched agent pause mid-task to ask you a question:

- **Claude Code** ships five dispatched subagents — **Reviewer-Standards**, **Reviewer-Spec**, **Deep Search**, **Code Analyzer**, and **Executor** — for phases that never need to interrupt you (Executor only runs this way if the Orchestrator's automatic mode is chosen for a spec; its default is manual). Sandbox, Product Planning, Technical Planning, Orchestrator, and manual-mode Executor run as skills loaded directly into your conversation instead, precisely so they *can* stop and ask when something's ambiguous.
- **OpenCode** ships 6 agent-picker personas (Ctrl+T to switch) — Allye, Allye Plan, Allye Orchestrator, Allye Build, Allye Review, Allye Deliver — OpenCode's agent model supports switching personas interactively within a session, so all 6 can be full agents. The automatic-Executor dispatch mode is Claude-Code-only for now; OpenCode always runs Executor (Allye Build) as an interactive agent.
- **Cursor, Codex, Gemini CLI** — a single agent handles all phases with the same workflow knowledge (no multi-agent picker on these platforms).
- **Hermes Agent** reads skills from a directory (`~/.hermes/skills/allye/`) rather than fetching them over MCP, and gets the `using-allye` bootstrap injected by a small Python plugin at session start instead of a hook — otherwise the same single-agent, same-workflow-knowledge shape as Cursor/Codex/Gemini CLI.
- **Pi** loads the canonical repository skills through a native Pi package, reads `using-allye` into the first prompt, injects Allye context through the configured MCP adapter, and exposes an adaptive toolkit. Herdr delegation is optional and capability-detected; tasks are recommended rather than mandatory.

Every phase, on every platform:
- Responds in **your language** (detected from your messages, falling back to your profile only before you've said anything)
- Calls `initialize` to load your profile and team context
- **Discovers team skills** before starting — coding standards, templates, checklists
- If no standards found → **suggests creating them** with your chosen scope (personal/team/organization). The internal library is the only Skills source.
- Searches memories for past decisions and session state
- Saves session state before ending

---

## Workflow

Each phase runs in its own fresh, lean-context chat. When one finishes, it emits a **handover** — a block of chat text you review and paste as the first message of the next chat, which auto-detects it and loads the right skill.

```
Sandbox → Product Planning → Technical Planning → Orchestrator ⇄ Executor → Reviewer (Standards + Spec)
                                                        ↑                       |
                                                        └──── next spec ────────┘
```

### Sandbox
Explore ideas, research before committing to scope, think out loud — no epics or specs created here. Dispatches Deep Search / Code Analyzer subagents for research. Exits with a Discovery Doc once a direction is approved.

### Product Planning
Understand business context → discover team templates → define epics and specs → write specs with anchored rules and acceptance criteria.

### Technical Planning
Get spec → **discussion phase** (identify gray areas, present options with trade-offs, capture locked decisions) → create thin tasks that reference spec anchors, in dependency waves.

### Orchestrator
Coordinates delivery of an already-planned epic or spec: manages assignee and task transitions, dispatches **Executor**, dispatches **Reviewer-Standards** and **Reviewer-Spec** in parallel once a report comes back, runs the correction loop, and completes reviewed tasks (spec and epic status follow automatically). With a detected agent runtime (Herdr), it can dispatch several independent specs at once, each in its own git worktree and its own watchable agent process; without one, it falls back to one spec at a time (manual handover, or automatic subagent dispatch — your choice per spec).

### Executor
Implements exactly one spec's tasks with TDD (Red → Green → Refactor). Runs either as an interactive skill (manual mode, can ask you questions) or as a dispatched subagent (automatic mode — halts and reports back instead of guessing when a task is underspecified).

### Reviewer — two axes
Two independent passes, dispatched together and never merged: **reviewer-standards** checks how the code is written (conventions, security, test quality), **reviewer-spec** checks whether it's what was asked for (acceptance criteria against the verification evidence, locked decisions, unrequested scope). Always dispatched automatically in parallel, since review never needs to pause and ask anyone anything. A ❌ on either axis triggers a correction round — one axis passing never offsets the other failing.

### Delivery
Once every spec of an epic is done, the Orchestrator offers — never forces — a close-out: verify all tasks done, update documentation, clean up TODOs, save a delivery memory. A deliberate step, not an automatic one.

---

## Skills

Skills are the internal knowledge base that powers the agents. Workflow skills ship with the installed package and are available through the internal Skills library.

| Skill | What it teaches |
|-------|----------------|
| `using-allye` | Bootstrap — memory protocol, skill routing, handover detection, workflow gates |
| `sandbox` | Explore ideas, research a direction, exit with a Discovery Doc — no specs created |
| `product-planning` | Business requirements → Epics → Specs (anchored rules and criteria) |
| `technical-planning` | Spec → Discussion Phase → Thin tasks referencing spec anchors |
| `orchestrator` | Coordinate delivery — assignee, dispatch Executor/Reviewer (both axes), correction loop, task transitions |
| `execution` | Task → TDD → Implementation with wave execution |
| `review` | Code review with decision context from planning |
| `delivery` | Verify → Confirm spec done → Update docs → Save memory |
| `handover-protocol` | The shared contract for handing off context between phases as chat text |
| `memory-protocol` | When and how to search/save memories across sessions |
| `tdd-workflow` | Red-Green-Refactor cycle with detection heuristic |
| `tools-quickref` | Complete reference for the Allye MCP tools and their actions |
| `verification-loop` | Deriving the AFK/HITL label from whether every task has a runnable verification command |
| `agent-runtime` | The five-primitive contract for driving an external agent runtime (Herdr), for parallel dispatch |
| `branch-landing` | Decide how a finished branch lands — merge, PR, or leave it — and tear down without losing work |

### Custom team skills

Your team can create custom skills in Allye — agents discover and follow them automatically:

- **Code review checklist** → Allye Review follows it
- **Backend spec standard** → Allye Plan uses it as template
- **Deploy checklist** → Allye Deliver follows it
- **Coding conventions** → Allye Build applies them

No team skills yet? Each agent will suggest creating them when it doesn't find standards for its domain.

---

## Prerequisites

- An [Allye](https://allye.app/) account — authentication is OAuth 2.1 on every platform (the MCP connection itself is OAuth-gated)
- At least one supported AI coding agent installed
- `jq` and `curl` (used by the installer and Claude Code hook)

## Contributing

Issues and PRs are welcome. Open an issue first for anything beyond a small fix, so the approach can be agreed on before you write code. PRs are reviewed before merge — expect feedback, and please keep unrelated changes out of a single PR.

## Roadmap

Today, Allye Agent Plugin is built around the Allye workspace. The long-term direction is to make the workflow layer (planning, orchestration, TDD, memory) work with other backends too — issue trackers like Jira and Linear, and memory stores like Obsidian or other local options — so teams can keep their existing tools and still get the methodology layer on top. Nothing here is scheduled yet; treat it as direction, not a commitment.

## License

MIT
