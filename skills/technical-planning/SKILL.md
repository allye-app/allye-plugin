---
name: technical-planning
description: Workflow for breaking a story into tasks through a structured discussion phase. Use when the user has a story and wants to plan the technical implementation.
version: "1.4"
category: methodology
---

# Technical Planning Workflow

Turns an approved, meaningful story into actionable tasks through a **Discussion Phase** — surfacing gray areas, capturing decisions, and writing tasks with verifiable acceptance criteria and a runnable verification command. It is recommended for durable, multi-step, shared, or review-heavy work, not mandatory for every local change.

**Never assume — always ask.** The user knows the direction they want, sometimes only after researching further. Your job is to surface the gray areas and present real options, not to quietly pick one and present it as the plan.

---

## Workflow Overview

```
Get story → Search context → Discussion Phase → Create tasks → Move story to in_progress → Save decisions
```

---

## 0. Scope: one feature, story by story

If the user explicitly chooses a no-task path, do not enter this workflow or create tasks. State the local scope, assumptions, and verification plan instead.

The steps below plan **one story at a time** — but the unit Technical Planning hands to the Orchestrator is the **feature**. When the target feature has multiple stories (a `planning-to-technical` handover usually lists several), work through every story under that feature in sequence, one at a time, running the full workflow (Steps 1–6) for each before starting the next.

**Emit only ONE `technical-to-orchestration` handover, at the very end — after the last story in the feature is planned, never after each individual story.** That handover must cover every story and every task, grouped by wave, which is only honest once all of the feature's stories have actually been planned. If the session ends before all stories are planned, save session state (Step 6) and resume in a fresh chat — don't emit a partial feature-level handover.

---

## Step 1: Get the Story

Fetch the story the user wants to plan:

```
work_get(id: "{story uuid}" or work_key: "{PROJ-123}")
```

Read the story's description, acceptance criteria, and parent context. If the story is part of a feature/epic, understand the broader scope:

```
work_get(work_key: "{parent feature key}")
```

---

## Step 2: Search for Context

Before planning, gather all relevant context:

```
memory_search(query: "Session State {story key}")
memory_search(query: "decision {feature/epic key}")
memory_search(query: "{technical domain} architecture")
```

If a relevant memory ID is found and context feels sparse, traverse its neighborhood:
```
memory_graph(memory_id: "{id}", depth: 2)  → surfaces connected decisions and blockers
```

Also check if tasks already exist for this story:

```
work_children(id: "{story uuid}")
```

If tasks already exist, review them instead of creating new ones. The user may want to adjust the plan, not start over.

---

## Step 3: Discussion Phase

<EXTREMELY_IMPORTANT>
For tracked work, complete the discussion phase — surfacing ambiguity before committing
to a plan — before creating any task. A user-approved no-task path may skip task creation,
but must still surface scope-changing ambiguity and define proportional verification.
</EXTREMELY_IMPORTANT>

### 3.1 Identify Gray Areas

Read the story and identify points where there are **multiple valid approaches**. These are gray areas — questions that don't have an obvious single answer.

Examples of gray areas:
- Which library/framework to use for X?
- Should this be a separate service or part of the monolith?
- How should we handle error case Y?
- What's the data model for Z?
- Should we optimize for read speed or write speed?
- How much backward compatibility do we need?

Whenever tracked work implies infrastructure, stack, or architecture choices, raise them explicitly as gray areas. For a small no-task change, use established defaults only when the choice is low-risk and reversible; otherwise ask before acting.

**Need more than a hunch to evaluate an option?** Dispatch the `deep-search` agent (web research) or the `code-analyzer` agent (analyze a public repo), both via the `Agent` tool — research is available here, not only in Sandbox. Bring findings back into the discussion before locking a decision.

### 3.2 Present Options with Trade-offs

For each gray area, present the user with **concrete options and trade-offs**:

```markdown
### Gray Area: How to handle file storage

**Option A: Local filesystem**
- ✅ Simple, no external dependency
- ❌ Doesn't scale, no redundancy

**Option B: S3-compatible object storage**
- ✅ Scalable, redundant, CDN-ready
- ❌ More complex setup, network dependency

**Option C: Database BLOBs**
- ✅ Transactional consistency with other data
- ❌ Database bloat, slower queries

**My recommendation:** Option B — best balance of scalability and maintainability for this use case.
```

### 3.3 Capture Decisions

As the user responds, classify each decision:

| Classification | Meaning | Rule |
|---------------|---------|------|
| **Locked decision** | The user explicitly chose this | Non-negotiable. Do not change without user approval. |
| **Agent discretion** | The user deferred to you | You decide, but document your rationale. Can be revisited. |

### 3.4 Save Decisions as Memories

Save each significant decision immediately — don't wait until the end:

```
memory_save(
  title: "Decision — {short description}",
  content: "## Decision\n{what was decided}\n\n## Classification\n{locked | agent-discretion}\n\n## Why\n{rationale}\n\n## Context\nStory: {story key}\nGray area: {what was ambiguous}",
  tags: ["decision", "{story-key}", "{topic}"],
  sector: "decisions"
)
```

### 3.5 Confirm All Gray Areas Are Resolved

Before moving to task creation, confirm with the user:

> "Here's a summary of what we decided:
> 1. {decision 1} — **locked**
> 2. {decision 2} — **agent discretion**
> 3. {decision 3} — **locked**
>
> Are we good to proceed with task creation?"

Also state the story's derived dispatch label: **AFK** if every task got a runnable
verification command, **HITL** if any task declared `verification: manual`. The
Orchestrator reads this rather than guessing, so a wrong label here becomes a story
dispatched to an unattended pane that then sits waiting for a human who is not watching.

---

## Step 4: Create Tasks

### 4.1 Plan the Task Breakdown

Design tasks that are:

- **Atomic** — Each task produces a single, verifiable outcome
- **Concrete** — No vague tasks like "set up the project" or "implement the feature"

**Split by concern when a story spans them.** A story touching frontend, backend, and data modeling is usually 3+ tasks, not one — the Wave mechanic below (4.4) handles the ordering (e.g., data modeling before frontend when the payload shape is a hard dependency). These are illustrative categories, not a fixed taxonomy: decide the actual split with the user, scenario by scenario.

<!-- adapted from superpowers:writing-plans task right-sizing (MIT) -->
**Right-size each task**: the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate. Fold setup/config into the task whose deliverable needs it; split only where a reviewer could reject one task while approving its neighbor.

### 4.2 Deep Work Rule

<HARD-GATE>
Every task carries verifiable acceptance criteria in its description — a task
without them is not a task, it's a wish.
</HARD-GATE>

### 4.2.1 Verification Rule

<HARD-GATE>
Every task carries a `## Verification` block: either a command that runs as
written, or `verification: manual` with the procedure. A task with neither
is not a task — a criterion nobody can check is a criterion nobody will.

Write the command while you still have the design in your head. Deferring it
to the Executor means it gets written by someone reconstructing your intent
from a description.

`verification: manual` is a legitimate answer for visual, infrastructure, and
one-off work — see `verification-loop` §4. It is not a shortcut for "I did not
want to think of a command": declaring it makes the whole story HITL, which
costs the Orchestrator its ability to dispatch that story unattended.
</HARD-GATE>

### 4.2.2 No Placeholders

<HARD-GATE>
A task description contains what someone needs to do the work, not a promise to supply it
later. These are defects in a task, not shorthand:

- "TBD", "TODO", "details to follow"
- "Add appropriate error handling" — which errors, handled how?
- "Handle edge cases" — which ones? An edge case nobody named is an edge case nobody covers.
- "Similar to {other task}" — say it again here. Tasks are read in isolation and out of order.
- A criterion naming a type, function, or file that no task defines and no `Interfaces`
  block produces.

Each of these reads as complete and defers the actual decision to whoever implements — who
has less context than you do right now, and no way to ask you.
</HARD-GATE>

### 4.3 Task Description Template

```markdown
## What
{Concrete description of what to implement}

## Acceptance Criteria
- [ ] {Criterion 1 — observable and testable}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Verification
{The exact command, runnable as written. It must be red-capable, deterministic,
fast, and agent-runnable — see the `verification-loop` skill §1.}

{or, when no such command exists:}
verification: manual
{the exact procedure a human follows, and what they should observe}

## Files Likely Involved
- {file/path/1}
- {file/path/2}

## Dependencies
- {Depends on TASK-XX} or "None — can be done independently"

## Interfaces
**Consumes:** {names, types, and signatures this task calls that another task in this story
produces — or "Nothing from other tasks"}
**Produces:** {names, types, and signatures other tasks will call. Exact, not descriptive:
`createSession(userId: string): Session`, not "a session creator".}

## Decisions Applied
- {Reference locked/agent-discretion decisions from discussion phase}
```

The `Interfaces` block exists because whoever implements a task sees **only that task**.
Dependencies tell them what must finish first; interfaces tell them what to call when it
has. Writing "a session creator" instead of the signature moves the naming decision to
whoever implements second, and they will name it something else.

### 4.4 Analyze Dependencies

Group tasks into **waves** based on dependencies:

```
Wave 1 (independent — can be done in any order):
  - Task A: Set up database schema
  - Task B: Create API route structure

Wave 2 (depends on Wave 1):
  - Task C: Implement CRUD endpoints (depends on A + B)
  - Task D: Add input validation (depends on B)

Wave 3 (depends on Wave 2):
  - Task E: Write integration tests (depends on C + D)
```

Present the wave structure to the user so they understand the execution order.

### 4.5 Create Tasks via Bulk Create

```
work_bulk_create(work_items: [
  {
    "temp_id": "task-1",
    "title": "Set up database schema for {feature}",
    "item_type": "task",
    "work_category": "backend",
    "parent_key": "{STORY-KEY}",
    "description": "{full description with acceptance criteria}"
  },
  {
    "temp_id": "task-2",
    "title": "Create API route structure for {feature}",
    "item_type": "task",
    "work_category": "backend",
    "parent_key": "{STORY-KEY}",
    "description": "{full description with acceptance criteria}"
  }
])
```

**Reminder:** Maximum 50 items per `work_bulk_create` call.

---

## Step 5: Move Story to In Progress

```
work_status_next(id: "{story uuid}")
```

Once tasks are created and the plan is approved, this moves the story forward in the
board progression (typically backlog/todo → in_progress).

---

## Step 6: Save Planning Summary

Save a comprehensive planning memory:

```
memory_save(
  title: "Technical Plan — {STORY-KEY} {story title}",
  content: "## Story\n{story key and title}\n\n## Decisions\n{list of locked and agent-discretion decisions}\n\n## Task Breakdown\n{wave structure with task keys}\n\n## Execution Order\n{which tasks first, which depend on what}\n\n## Risks\n{identified risks or uncertainties}",
  tags: ["planning", "technical-plan", "{story-key}"],
  sector: "plans"
)
```

---

## Workflow Checklist

Before considering technical planning complete, verify:

- [ ] Story was read and understood in its full context
- [ ] Existing memories and decisions were searched
- [ ] Gray areas were identified and discussed with the user
- [ ] All decisions are classified (locked vs agent-discretion) and saved as memories
- [ ] Tasks have verifiable acceptance criteria
- [ ] Every task has a `## Verification` block — a runnable command, or `verification: manual` with a procedure
- [ ] Every task's `Interfaces` block names exact signatures, not descriptions
- [ ] No task description contains a placeholder or an unnamed edge case
- [ ] The story's AFK/HITL label is derived and stated
- [ ] Dependencies are mapped and wave structure is defined
- [ ] Tasks are created in Allye with proper parent relationship
- [ ] Story is moved to in_progress
- [ ] Planning summary is saved as memory
- [ ] All of the feature's stories are planned before the `technical-to-orchestration` handover is emitted (see §0)

---

## What Comes Next

**If the feature has more stories still unplanned, go back to Step 1 for the next story — no handover yet (see §0).**

Once the last story in the feature is planned, emit a **`technical-to-orchestration`** handover (see the `handover-protocol` skill) for the Orchestrator. Spell out the full reading list — doc, epic, feature, every story, every task, grouped by wave — and every locked architecture decision, across all the stories planned in this cycle. The Orchestrator has no other context; a vague pointer here becomes its problem later.
