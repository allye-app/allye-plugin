---
name: product-planning
description: Workflow for translating business requirements into epics, features, and stories in Allye. Use when the user wants to plan a product, define scope, or create work item hierarchies.
version: "1.0"
category: workflow
---

# Product Planning Workflow

This skill guides you through translating business requirements into a structured work item hierarchy in Allye: **Epics → Features → Stories**.

Use this when the user talks about: requirements, business needs, product scope, MVP, new features, project kickoff, or wants to create epics/features/stories.

---

## Workflow Overview

```
Understand context → Search memories → Define hierarchy → Create items → Save decisions
```

---

## Step 1: Understand the Business Context

Before creating anything, have a conversation with the user to understand:

1. **What problem are we solving?** — The business need or opportunity
2. **Who is it for?** — Target users or stakeholders
3. **What does success look like?** — Expected outcomes or metrics
4. **What's the scope?** — What's in and what's out (MVP vs future)
5. **Are there constraints?** — Timeline, tech stack, dependencies, compliance

<EXTREMELY_IMPORTANT>
Do NOT jump to creating work items before you understand the business context.
Ask questions. Clarify ambiguities. The quality of planning depends on the quality of understanding.
</EXTREMELY_IMPORTANT>

**If the user already has clear requirements** (e.g., a PRD, a spec, a detailed description), skip the discovery questions and move to Step 2.

---

## Step 2: Search for Existing Context

Before creating new items, check what already exists:

```
memory_search(query: "{product/project name} requirements")
memory_search(query: "{product/project name} architecture")
```

Also check existing work items:

```
work_list(query: "{product/project name}")
```

**If related items exist:**
- Review them to avoid duplication
- Understand what was already planned or decided
- Build on top of existing structure rather than starting fresh

---

## Step 3: Design the Work Item Hierarchy

Plan the hierarchy before creating items. Present it to the user for approval.

### Item types and when to use them

| Type | Purpose | Example |
|------|---------|---------|
| **Epic** | Large initiative spanning multiple features. Weeks to months of work. | "User Authentication System" |
| **Feature** | A distinct capability within an epic. Days to weeks. | "Social Login (Google, GitHub)" |
| **Story** | A user-facing outcome within a feature. Hours to days. Can be implemented in one session. | "As a user, I can log in with my Google account" |

### Hierarchy rules

- An **Epic** contains **Features**
- A **Feature** contains **Stories**
- Every Story must be **independently deliverable** — it produces a working increment
- Stories should follow the format: "As a {role}, I can {action} so that {benefit}" (when applicable)

### Present the plan

Show the user the proposed hierarchy before creating anything:

```
Epic: User Authentication System
├── Feature: Email/Password Auth
│   ├── Story: User can register with email and password
│   ├── Story: User can log in with email and password
│   └── Story: User can reset password via email
├── Feature: Social Login
│   ├── Story: User can log in with Google
│   └── Story: User can log in with GitHub
└── Feature: Session Management
    ├── Story: User session persists across browser restarts
    └── Story: User can log out from all devices
```

Wait for the user to approve, modify, or add to this structure before proceeding.

---

## Step 4: Check Board and Statuses

Before creating items, understand the available statuses:

```
work_statuses()
board_columns()
```

This ensures you know:
- What status categories exist (backlog, todo, in_progress, etc.)
- Which board columns are available
- The correct status to assign to new items

New items should typically be created in **backlog** or **todo** status.

---

## Step 5: Create Work Items

### For the Epic (if it doesn't exist yet)

Create the top-level epic first:

```
work_create(
  title: "User Authentication System",
  item_type: "epic",
  description: "## Goal\n{business goal}\n\n## Scope\n{what's included}\n\n## Out of scope\n{what's excluded}\n\n## Success criteria\n{how we know it's done}"
)
```

### For Features and Stories

Use `work_bulk_create` to create the full hierarchy in one call:

```
work_bulk_create(items: [
  {
    "temp_id": "feat-1",
    "title": "Email/Password Auth",
    "item_type": "feature",
    "work_category": "feature",
    "parent_key": "PROJ-100",          // existing epic key
    "description": "..."
  },
  {
    "temp_id": "story-1",
    "title": "User can register with email and password",
    "item_type": "story",
    "work_category": "story",
    "parent_temp_id": "feat-1",        // references the feature above
    "description": "..."
  },
  {
    "temp_id": "story-2",
    "title": "User can log in with email and password",
    "item_type": "story",
    "work_category": "story",
    "parent_temp_id": "feat-1",
    "description": "..."
  }
])
```

### `work_bulk_create` rules

- Each item needs: `temp_id`, `title`, `item_type`, `work_category`
- Use `parent_key` to reference an existing item (e.g., an epic already in Allye)
- Use `parent_temp_id` to reference another item in the same batch
- **Maximum 50 items** per call — split into multiple calls if needed
- The server handles ordering and key generation automatically

### Story descriptions

Every story should have a clear description:

```markdown
## User Story
As a {role}, I can {action} so that {benefit}.

## Acceptance Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}
- [ ] {criterion 3}

## Notes
{any additional context, constraints, or dependencies}
```

---

## Step 6: Set Priority and Estimates

For each story, consider setting:

- **Priority** — How urgent/important is this? (critical, high, medium, low)
- **Story points** — Relative complexity estimate
- **Sprint assignment** — If there's an active sprint, assign relevant stories

Check the active sprint:
```
sprint_active()
```

---

## Step 7: Save Planning Decisions

Save key decisions as memories for future reference:

```
memory_save(
  title: "Planning — {Epic name} scope and decisions",
  content: "## Scope\n{what was included/excluded and why}\n\n## Key decisions\n- {decision 1}: {rationale}\n- {decision 2}: {rationale}\n\n## Hierarchy\n{the approved structure}\n\n## Open questions\n{anything deferred}",
  tags: ["planning", "decision", "{epic-key}"],
  work_item_id: "{epic uuid}"
)
```

---

## Workflow Checklist

Before considering product planning complete, verify:

- [ ] Business context is understood (problem, users, scope, constraints)
- [ ] Existing work items and memories were checked
- [ ] Hierarchy was presented to and approved by the user
- [ ] All items are created in Allye with proper parent relationships
- [ ] Stories have acceptance criteria in their descriptions
- [ ] Priority and estimates are set (if applicable)
- [ ] Planning decisions are saved as memories

---

## What Comes Next

After product planning is complete, the user will pick a story to work on. That transitions to **Technical Planning** — load the `allye-technical-planning` skill.
