---
name: using-allye
description: Bootstrap meta-skill for AI agents using the Allye platform. Teaches when and how to use Allye MCP tools with structured workflows. Injected at session start.
version: "1.0"
category: bootstrap
---

# Using Allye

You have access to the **Allye platform** — a project management and knowledge system with 12 MCP tools covering work items, documentation, sprints, boards, memories, skills, and more.

This skill teaches you **when and how** to use those tools effectively. It does NOT replace the tools — it gives you methodology and workflow discipline on top of them.

**What you must do:**
1. Search for relevant memories at the start of every conversation
2. Detect which workflow phase applies to the user's request
3. Load the appropriate skill for that phase
4. Save memories before the conversation ends

---

## 1. Memory First Protocol

<EXTREMELY_IMPORTANT>
At the START of every conversation, you MUST search for relevant memories before doing anything else.
At the END of every conversation, you MUST save a session state memory.
This is not optional. Memories are how context survives between conversations.
</EXTREMELY_IMPORTANT>

### On conversation start

**Step 1: Initialize Allye** — Call `initialize` (action: `init`) to load user context, team info, and core documents. This is mandatory and must happen before anything else.

**Step 2: Check active team** — If the init response shows the user belongs to multiple teams and no team is active, ask the user which team they want to work with and call `team_switch` with the team name. Do not proceed until a team is selected — most tools require a team context.

**Step 3: Search for memories** using `memory_search`:

1. `"Session State"` — find where the user left off last time
2. `"decision {topic}"` — find previous decisions about the current topic
3. `"{work item key}"` — find context for the specific item being discussed (e.g., "PROJ-123")

**Step 4: Greet the user** — Summarize what you know (from init + memories) before proceeding. If no memories are found, proceed normally with the context from init.

### On conversation end

Save a session state memory using `memory_save`:

```
title: "Session State — [KEY] short description"
content:
  - Current position: which phase (planning/development/review/delivery), which task
  - Work completed: what was done this session
  - Decisions made: locked decisions + trade-offs evaluated
  - Blockers: impediments found
  - Next concrete step: exactly what to do when resuming
tags: [session-state, {work-item-key}, {current-phase}]
work_item_id: {uuid if applicable}
sprint_id: {uuid if applicable}
```

### When to save mid-conversation

- A technical decision was made (save the "why", not the "what")
- A trade-off was evaluated
- A blocker was identified
- Context that would be lost between conversations

### Tag conventions

| Category | Tags |
|----------|------|
| Phase | `planning`, `development`, `review`, `delivery` |
| Work item | `PROJ-123`, `epic:PROJ-100`, `feature:PROJ-110` |
| Topic | `architecture`, `api-design`, `database`, `testing`, `performance`, `security`, `deployment` |
| Content type | `decision`, `trade-off`, `blocker`, `context`, `session-state` |

---

## 2. Skill Routing

Detect what the user needs and load the right skill. Skills are loaded on-demand — do NOT load all skills at once.

### Handover detection (check this FIRST)

Before running the phase-detection heuristic below, check whether the user's first message contains a `## 🔄 Allye Handover` block (see the `handover-protocol` skill for the full format). If it does:

1. Parse the `{tipo}` from the marker line and the `Skill a carregar` value.
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
| Implement code, write tests, develop features | Technical Development | `allye-technical-development` |
| Review code, check implementation quality | Technical Review | `allye-technical-review` |
| Finalize delivery, close story, update docs | Technical Delivery | `allye-technical-delivery` |

### How to detect the phase

- **Sandbox / Discovery** — User wants to: explore ideas, think out loud, research before deciding, hasn't committed to a direction yet
- **Product Planning** — User talks about: requirements, business needs, features, epics, user stories, product scope, MVP
- **Technical Planning** — User has a story and wants to: break it into tasks, discuss approach, evaluate options, plan implementation
- **Orchestrator** — User wants to: coordinate delivery, assign work items, track story/task status, drive review for an already-planned feature
- **Technical Development** — User wants to: write code, implement a task, fix a bug, add functionality, write tests
- **Technical Review** — User wants to: review code, check quality, validate implementation, get feedback
- **Technical Delivery** — User wants to: finish a story, merge, deploy, update documentation, close items

### How to load a skill

Use the Allye MCP `skills` tool to load the skill content:

```
Action: skill_list
Query: {skill-slug}
```

Then read the skill content and follow its instructions. The loaded skill takes priority over this bootstrap for the duration of that workflow.

### When no skill matches

If the user's request doesn't match any workflow phase (e.g., general questions, quick lookups, team management), use the Allye tools directly without loading a specific skill. The tools reference in section 4 gives you a quick overview.

---

## 3. Workflow Gates

<HARD-GATE>
These rules are non-negotiable. Do not proceed past a gate without meeting its condition.

1. **No implementation without tasks.** Do not write code for a story that has no tasks created. Run Technical Planning first.

2. **No skipping the discussion phase.** When planning tasks for a story, always identify gray areas and present options to the user before creating tasks. Locked decisions must be captured as memories.

3. **No status changes without work.** Do not move a work item to "done" (`work_status_done`) unless the actual work is completed and verified.

4. **TDD when applicable.** If you can write `expect(fn(input)).toBe(output)` before writing `fn`, you MUST write the test first (Red → Green → Refactor). If not (UI, infra, integration), test after implementation — but always test.
</HARD-GATE>

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
| "I don't need to search memories, this is a fresh conversation." | The user may have worked on this topic before. Context from past sessions prevents rework and contradictions. Always search. |
| "I'll just start coding, tasks aren't necessary for something this small." | Tasks create accountability, enable progress tracking, and force you to think before acting. Planning first, always. |
| "I'll skip the tests, the implementation is straightforward." | Straightforward code still breaks. TDD catches assumptions. Write the test. |
| "I'll move the story to done, the tasks are mostly complete." | "Mostly" is not "done". Verify all tasks are complete first. |
| "I don't need to save memories, I covered everything in the conversation." | Conversations are ephemeral. The next session starts from zero without memories. Always save state. |
| "I'll load all skills at once to be prepared." | Skills are loaded on-demand for a reason — loading everything bloats context and degrades quality. Load only what's needed. |

---

## 6. Subagent Instructions

<SUBAGENT-STOP>
If you are a subagent (launched via the Agent tool), do NOT load this bootstrap skill.
The parent agent has already loaded it. You should focus on your specific task.
Do NOT search for memories or save session state — the parent agent handles that.
</SUBAGENT-STOP>

---

## 7. Entity Linking

When saving memories, always link to relevant entities:

- **`work_item_id`** — when working on a specific work item
- **`sprint_id`** — when working within an active sprint
- **`documentation_item_id`** — when the memory relates to documentation

This enables the Allye intelligence system to build a knowledge graph across your project.
