---
name: using-allye
description: Bootstrap meta-skill for AI agents using the Allye platform. Teaches when and how to use Allye MCP tools with structured workflows. Injected at session start.
version: "1.4"
category: bootstrap
---

# Using Allye

You have access to the **Allye platform** — a project management and knowledge system with 12 MCP tools covering work items, documentation, sprints, boards, memories, skills, and more.

This skill teaches you **when and how** to use those tools effectively. It does NOT replace the tools — it gives you portable playbooks and proportional guardrails on top of them.

**Default posture:** Allye is an adaptive toolkit, not a mandatory phase chain. Use Allye MCP, filesystem, subagents, Herdr, work items, and memories when available and useful; degrade honestly when a capability is absent. Recommend traceable tasks for meaningful work, but support an explicitly approved no-task path.

---

## Language

These instructions are written in English, but every response, question, suggestion, and confirmation you produce must be in the language the user is actually writing in. **The conversation itself is the primary signal, and it overrides everything else once the user has written anything** — including any `language` field on the user's profile from `initialize`. Only fall back to the profile's `language` field when there's no message yet to go by (e.g. framing your very first proactive line before the user has said anything). If the user switches language mid-conversation, follow them.

---

## Asking Questions

When a fork has a small set of nameable options — ownership, approach, scope, or confirmation — prefer the runtime's native structured-question mechanism when one exists. If the runtime has no such tool, ask one focused question in concise prose and make the options explicit. Never silently choose a consequential option.

**Never bundle an open-ended sub-question with an enumerable one in the same message.** Split them into separate turns. Reserve plain conversational questions for genuinely open-ended forks where enumerating options would require guessing.

## 1. Context and Memory Protocol

Use durable Allye context when the Allye MCP capability is available and the work benefits from continuity. Do not pretend a memory was searched or saved when the capability is unavailable.

### On conversation start

1. Initialize when available. If it fails, state the limitation and continue with local context unless Allye is required.
2. Resolve team context proportionally: ask before a team-scoped operation when multiple teams have no active selection; non-team-scoped work may continue.
3. Search relevant memories when useful, especially for consequential, multi-step, or resumed work.
4. Distinguish confirmed Allye context, local repository context, and assumptions.
5. Use subagents or Herdr only when detected and beneficial; never make them prerequisites.

### On conversation end (and saving in general)

Follow the `memory-protocol` skill when Allye memory is available and the context is worth preserving. Save decisions, trade-offs, blockers, and durable session state; do not save trivial noise. Always pass `sector` explicitly. If persistence is unavailable, report the unsaved state rather than implying continuity.

---

## 2. Skill Routing

Detect what the user needs and load the right skill. Skills are loaded on-demand — do NOT load all skills at once.

### Handover detection (check this FIRST)

Before running the phase-detection heuristic below, check whether the user's first message contains a `## 🔄 Allye Handover` block (see the `handover-protocol` skill for the full format). If it does:

1. Parse the `{type}` from the marker line and the `Skill to load` value.
2. Resolve it to a backend slug if needed — handover templates always use the bare skill name, but three skills kept their original `allye-*` backend slug through the Plan 1 rename (see the "Slug" column below): `product-planning` → `allye-product-planning`, `technical-planning` → `allye-technical-planning`, `execution` → `allye-technical-development`. Every other value (`orchestrator`, `sandbox`, `handover-protocol`) already matches its backend slug directly.
3. Load that skill directly via `skill_list`/`skill_get` with the resolved slug — skip the heuristic decision table entirely, there's no ambiguity to resolve.
4. Treat every field in the handover as authoritative context for this session — locked decisions in particular are non-negotiable unless the user explicitly reopens them.

If no handover marker is present, fall through to the decision table below as before.

### Decision table

| User intent | Skill to load | Slug |
|-------------|---------------|------|
| Explore ideas, research before committing to scope, think out loud, no direction chosen yet | Sandbox / Discovery | `sandbox` |
| Define product requirements, create epics/features/stories | Product Planning | `allye-product-planning` |
| Plan technical tasks for a story, discuss approach | Technical Planning | `allye-technical-planning` |
| Coordinate delivery of an already-planned feature — assign work, track status, drive tasks through review | Orchestrator | `orchestrator` |
| Implement code, write tests, develop features | Technical Development or a lightweight local implementation loop | `allye-technical-development` when a task/work item exists |
| Review code, check implementation quality | Technical Review | `allye-technical-review` |
| Finalize delivery, close story, update docs | Technical Delivery | `allye-technical-delivery` |

Three skills sit outside this table because no user request routes to them directly: `verification-loop` is loaded by `execution` when a task is being verified, `agent-runtime` by `orchestrator` when parallel work is being dispatched, and `branch-landing` by `delivery`, `orchestrator`, and `execution` when a branch's work is done. All three load on demand, from the skill that needs them.

### How to detect the phase

- **Sandbox / Discovery** — User wants to: explore ideas, think out loud, research before deciding, hasn't committed to a direction yet
- **Product Planning** — User talks about: requirements, business needs, features, epics, user stories, product scope, MVP
- **Technical Planning** — User has a story and wants to: break it into tasks, discuss approach, evaluate options, plan implementation
- **Orchestrator** — User wants to: coordinate delivery, assign work items, track story/task status, drive review for an already-planned feature
- **Technical Development** — User wants to: write code, implement a task, fix a bug, add functionality, write tests
- **Technical Review** — User wants to: review code, check quality, validate implementation, get feedback
- **Technical Delivery** — User wants to: finish a story, merge, deploy, update documentation, close items

### How to load a skill

Use the Allye MCP `skills` tool. `skill_list` only *lists* skills (metadata, no content) — use it to resolve the slug to an ID, then fetch the actual content with `skill_get`:

```
1. skill_list(query: "{skill-slug}")   → find the skill and its ID
2. skill_get(id: "{skill id}")         → returns the full skill content
```

(`skill_export` / `skill_export_merged` also return content, formatted for a specific agent — `skill_export_merged` is useful when loading several workflow skills at once.)

Then read the skill content and follow its instructions. The loaded skill takes priority over this bootstrap for the duration of that workflow.

### When no skill matches

If the user's request doesn't match any workflow phase (e.g., general questions, quick lookups, team management), use the Allye tools directly without loading a specific skill. The tools reference in section 4 gives you a quick overview.

### Direct implementation path

When the user asks for a small or low-risk local change and no task exists, recommend the lightweight execution loop: state scope, get explicit approval to bypass task creation, read first, test and verify, then report. Do not create a task merely because the execution skill exists.

---

## 3. Adaptive Checkpoints and Guardrails

There is no universal phase gate. Choose the smallest useful loop for the user's intent:

`intent → context → research (optional) → decision/consent → action → verification → persistence (optional)`

Checkpoints may be skipped or repeated. Use this policy:

- **Low-risk, local, reversible work:** proceed with a concise plan and proportionate verification. Do not create work items merely to satisfy the toolkit.
- **Meaningful, multi-step, delegated, shared, or review-heavy work:** recommend a task or work item for traceability. Explain the benefit and ask for approval before creating it.
- **No-task path:** if the user explicitly approves bypassing task creation, record that choice when useful, keep scope explicit, and verify the result proportionally.
- **Consequential mutations** (external systems, destructive operations, publication, deployment, status changes, or broad scope): obtain explicit consent unless the user already clearly authorized that exact action. Do not create or change work items/statuses without approval.
- **Ambiguity that changes scope, risk, or architecture:** stop and ask. Minor implementation details may use established defaults, stated assumptions, and a reversible change.
- **TDD:** use Red → Green → Refactor when the behavior can be specified as a deterministic example; otherwise test after implementation, but do not skip verification.
- **Done claims:** only claim completion after reading actual verification output and distinguishing implementation evidence from review, deployment, or other pending gates.

---

## 4. Allye Tools Quick Reference

| Tool | What it does |
|------|-------------|
| `work_items` | Create, list, update, bulk-create work items (epics, features, stories, tasks, bugs). Move status. |
| `boards` | View boards and columns. Understand status progression. |
| `sprints` | List sprints, get active sprint, view sprint work items. |
| `docs` | Create, read, update documentation. Tree navigation. Publish and version. |
| `intelligence` | Save and search memories (semantic, embedding-based). Core of cross-session continuity. |
| `productivity` | Personal TODOs — create, list, update, delete. Stats, search, categories. |
| `skills` | List, export, install skills. `skill_export_merged` for loading workflow skills. |
| `team` | Switch active team, list teams, check current team. |
| `user_config` | Manage personal configuration documents. |
| `api_catalog` | Search and browse API endpoints documentation. |
| `initialize` | Re-initialize Allye environment and reload documents. |
| `health` | Check Allye backend health status. |

For detailed parameter reference, load the `allye-tools-quickref` skill.

---

## 5. Red Flags — Rationalizations to Reject

If you catch yourself thinking any of these, STOP:

| Rationalization | Why it's wrong |
|-----------------|---------------|
| "I don't need to search memories, this is a fresh conversation." | For consequential or resumed work, prior context may prevent rework; search when useful and available, but do not pretend an unavailable capability was used. |
| "I'll just start coding, tasks aren't necessary for something this small." | For meaningful work, tasks improve accountability; for small work, use the approved no-task path with explicit scope and verification. |
| "I'll skip the tests, the implementation is straightforward." | Straightforward code still breaks. TDD catches assumptions. Write the test. |
| "I'll move the story to done, the tasks are mostly complete." | "Mostly" is not "done". Verify all tasks are complete first. |
| "I don't need to save memories, I covered everything in the conversation." | Save durable decisions and consequential session state when persistence is available; skip trivial noise and report when persistence is unavailable. |
| "I'll load all skills at once to be prepared." | Skills are loaded on-demand for a reason — loading everything bloats context and degrades quality. Load only what's needed. |

---

## 6. Subagent Instructions

<SUBAGENT-STOP>
If you are a subagent (launched via the Agent tool), do NOT load this bootstrap skill.
The parent agent has already loaded it. You should focus on your specific task.
Do NOT search for memories or save session state — the parent agent handles that.
</SUBAGENT-STOP>

