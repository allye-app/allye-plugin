---
name: using-fenix
description: Bootstrap meta-skill for AI agents using the Fenix platform. Teaches when and how to use Fenix MCP tools with structured workflows. Injected at session start.
version: "1.0"
category: bootstrap
---

# Using Fenix

You have access to the **Fenix platform** — a project management and knowledge system with 12 MCP tools covering work items, documentation, sprints, boards, memories, skills, and more.

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

**Step 1: Initialize Fenix** — Call `initialize` (action: `init`) to load user context, team info, and core documents. This is mandatory and must happen before anything else.

**Step 2: Search for memories** using `memory_search`:

1. `"Session State"` — find where the user left off last time
2. `"decision {topic}"` — find previous decisions about the current topic
3. `"{work item key}"` — find context for the specific item being discussed (e.g., "PROJ-123")

**Step 3: Greet the user** — Summarize what you know (from init + memories) before proceeding. If no memories are found, proceed normally with the context from init.

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

### Decision table

| User intent | Skill to load | Slug |
|-------------|---------------|------|
| Define product requirements, create epics/features/stories | Product Planning | `fenix-product-planning` |
| Plan technical tasks for a story, discuss approach | Technical Planning | `fenix-technical-planning` |
| Implement code, write tests, develop features | Technical Development | `fenix-technical-development` |
| Review code, check implementation quality | Technical Review | `fenix-technical-review` |
| Finalize delivery, close story, update docs | Technical Delivery | `fenix-technical-delivery` |

### How to detect the phase

- **Product Planning** — User talks about: requirements, business needs, features, epics, user stories, product scope, MVP
- **Technical Planning** — User has a story and wants to: break it into tasks, discuss approach, evaluate options, plan implementation
- **Technical Development** — User wants to: write code, implement a task, fix a bug, add functionality, write tests
- **Technical Review** — User wants to: review code, check quality, validate implementation, get feedback
- **Technical Delivery** — User wants to: finish a story, merge, deploy, update documentation, close items

### How to load a skill

Use the Fenix MCP `skills` tool to load the skill content:

```
Action: skill_list
Query: {skill-slug}
```

Then read the skill content and follow its instructions. The loaded skill takes priority over this bootstrap for the duration of that workflow.

### When no skill matches

If the user's request doesn't match any workflow phase (e.g., general questions, quick lookups, team management), use the Fenix tools directly without loading a specific skill. The tools reference in section 4 gives you a quick overview.

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

## 4. Fenix Tools Quick Reference

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
| `initialize` | Re-initialize Fenix environment and reload documents. |
| `health` | Check Fenix backend health status. |

For detailed parameter reference, load the `fenix-tools-quickref` skill.

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

This enables the Fenix intelligence system to build a knowledge graph across your project.
