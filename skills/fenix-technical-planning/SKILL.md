---
name: fenix-technical-planning
description: Workflow for breaking a story into tasks through a structured discussion phase. Use when the user has a story and wants to plan the technical implementation.
version: "1.0"
category: workflow
---

# Technical Planning Workflow

This skill guides you through taking a story and turning it into actionable tasks through a **Discussion Phase** — identifying gray areas, capturing decisions, and creating tasks with verifiable acceptance criteria.

Use this when the user has a story and wants to: plan tasks, discuss approach, evaluate technical options, or break down implementation work.

---

## Workflow Overview

```
Get story → Search context → Discussion Phase → Create tasks → Move story to in_progress → Save decisions
```

---

## Step 1: Get the Story

Fetch the story the user wants to plan:

```
work_get(id: "{story uuid}" or key: "{PROJ-123}")
```

Read the story's description, acceptance criteria, and parent context. If the story is part of a feature/epic, understand the broader scope:

```
work_get(key: "{parent feature key}")
```

---

## Step 2: Search for Context

Before planning, gather all relevant context:

```
memory_search(query: "Session State {story key}")
memory_search(query: "decision {feature/epic key}")
memory_search(query: "{technical domain} architecture")
```

Also check if tasks already exist for this story:

```
work_children(id: "{story uuid}")
```

If tasks already exist, review them instead of creating new ones. The user may want to adjust the plan, not start over.

---

## Step 3: Discussion Phase

<EXTREMELY_IMPORTANT>
Do NOT create tasks before completing the discussion phase.
The purpose of discussion is to surface ambiguity BEFORE committing to a plan.
Skipping this leads to rework, wrong assumptions, and wasted effort.
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
  work_item_id: "{story uuid}"
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

---

## Step 4: Create Tasks

### 4.1 Plan the Task Breakdown

Design tasks that are:

- **Atomic** — Each task produces a single, verifiable outcome
- **Ordered by dependency** — Independent tasks first, dependent tasks after
- **Concrete** — No vague tasks like "set up the project" or "implement the feature"

### 4.2 Deep Work Rule

<HARD-GATE>
Every task MUST have verifiable acceptance criteria in its description.
A task without acceptance criteria is not a task — it's a wish.
Do not create tasks that cannot be objectively verified as complete.
</HARD-GATE>

### 4.3 Task Description Template

```markdown
## What
{Concrete description of what to implement}

## Acceptance Criteria
- [ ] {Criterion 1 — observable and testable}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## How to Verify
{How to confirm this task is done — e.g., run tests, check endpoint, verify UI}

## Files Likely Involved
- {file/path/1}
- {file/path/2}

## Dependencies
- {Depends on TASK-XX} or "None — can be done independently"

## Decisions Applied
- {Reference locked/agent-discretion decisions from discussion phase}
```

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
work_bulk_create(items: [
  {
    "temp_id": "task-1",
    "title": "Set up database schema for {feature}",
    "item_type": "task",
    "work_category": "task",
    "parent_key": "{STORY-KEY}",
    "description": "{full description with acceptance criteria}"
  },
  {
    "temp_id": "task-2",
    "title": "Create API route structure for {feature}",
    "item_type": "task",
    "work_category": "task",
    "parent_key": "{STORY-KEY}",
    "description": "{full description with acceptance criteria}"
  }
])
```

**Reminder:** Maximum 50 items per `work_bulk_create` call.

---

## Step 5: Move Story to In Progress

Once tasks are created and the plan is approved:

```
work_status_next(id: "{story uuid}")
```

This moves the story forward in the board progression (typically from backlog/todo to in_progress).

---

## Step 6: Save Planning Summary

Save a comprehensive planning memory:

```
memory_save(
  title: "Technical Plan — {STORY-KEY} {story title}",
  content: "## Story\n{story key and title}\n\n## Decisions\n{list of locked and agent-discretion decisions}\n\n## Task Breakdown\n{wave structure with task keys}\n\n## Execution Order\n{which tasks first, which depend on what}\n\n## Risks\n{identified risks or uncertainties}",
  tags: ["planning", "technical-plan", "{story-key}"],
  work_item_id: "{story uuid}",
  sprint_id: "{sprint uuid if applicable}"
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
- [ ] Dependencies are mapped and wave structure is defined
- [ ] Tasks are created in Fenix with proper parent relationship
- [ ] Story is moved to in_progress
- [ ] Planning summary is saved as memory

---

## What Comes Next

The user picks a task (or the first task in Wave 1) and starts implementing. That transitions to **Technical Development** — load the `fenix-technical-development` skill.
