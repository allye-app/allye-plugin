---
name: product-planning
description: Workflow for translating business requirements into epics, features, and stories in Allye. Use when the user wants to plan a product, define scope, or create work item hierarchies.
version: "1.2"
category: methodology
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

## Step 0: Check for a Discovery Doc

If you arrived via a `discovery-to-planning` handover (see the `handover-protocol` skill), read the Discovery Doc it references before anything else — it already captures the approved direction, rejected alternatives, and any research findings. Treat it as established context, not something to re-derive.

---

## Step 1: Understand the Business Context

Before creating anything, have a conversation with the user to understand:

1. **What problem are we solving?** — The business need or opportunity
2. **Who is it for?** — Target users or stakeholders
3. **What does success look like?** — Expected outcomes or metrics
4. **What's the scope?** — What's in and what's out (MVP vs future)
5. **Are there constraints?** — Timeline, tech stack, dependencies, compliance

<EXTREMELY_IMPORTANT>
Reach full understanding of the business context before creating any work item — ask questions and clarify ambiguities. The quality of planning depends on the quality of understanding.
</EXTREMELY_IMPORTANT>

<!-- adapted from bmad-code-org/BMAD-METHOD create-epics-and-stories (MIT) -->
Treat this as a collaboration between equal partners, not an intake form — the user knows the business, you know how to structure it. Push back on ambiguity and offer options; don't just transcribe what's said.

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
- When presenting the hierarchy in Step 3, mark each item explicitly as **reused** or **new** — never silently create a duplicate of something that already exists

---

## Step 3: Design the Work Item Hierarchy

Plan the hierarchy before creating items. Present it to the user for approval.

### Working vocabulary: squares and quadradinhos

When talking through the structure with the user, a "square" is a Feature-sized deliverable — a puzzle piece of the overall product; a "quadradinho" is a Story inside it. This is conversational shorthand, not a new formal type — it still resolves to the real Epic → Feature → Story hierarchy below.

### Item types and when to use them

| Type | Purpose | Example |
|------|---------|---------|
| **Epic** | Large initiative spanning multiple features. Weeks to months of work. | "User Authentication System" |
| **Feature** | A distinct capability within an epic. Days to weeks. | "Social Login (Google, GitHub)" |
| **Story** | A user-facing outcome within a feature. Hours to days. Can be implemented in one session. | "As a user, I can log in with my Google account" |

### Hierarchy rules

<!-- adapted from github/spec-kit story template language (MIT) -->
- An **Epic** contains **Features**
- A **Feature** contains **Stories**
- Every Story must be **independently testable and deliverable** — it produces a working increment on its own, not just alongside its siblings
- Stories should follow the format: "As a {role}, I can {action} so that {benefit}" (when applicable)
- Prioritize so that **P1 alone is a viable increment** — if only the highest-priority stories shipped, there should still be something real to show

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

```
work_statuses()
board_columns()
```

This surfaces the available status categories and board columns, so you know the correct status for new items — typically **backlog** or **todo**.

---

## Step 5: Create Work Items

### For the Epic (if it doesn't exist yet)

Create the top-level epic first:

```
work_create(
  work_title: "User Authentication System",
  work_type: "epic",
  work_category: "product",
  work_description: "## Goal\n{business goal}\n\n## Scope\n{what's included}\n\n## Out of scope\n{what's excluded}\n\n## Success criteria\n{how we know it's done}"
)
```

### For Features and Stories

Use `work_bulk_create` to create the full hierarchy in one call:

```
work_bulk_create(work_items: [
  {
    "temp_id": "feat-1",
    "title": "Email/Password Auth",
    "item_type": "feature",
    "work_category": "product",
    "parent_key": "PROJ-100",          // existing epic key
    "description": "..."
  },
  {
    "temp_id": "story-1",
    "title": "User can register with email and password",
    "item_type": "story",
    "work_category": "product",
    "parent_temp_id": "feat-1",        // references the feature above
    "description": "..."
  },
  {
    "temp_id": "story-2",
    "title": "User can log in with email and password",
    "item_type": "story",
    "work_category": "product",
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

Every story should have a clear description. Write acceptance criteria as concrete scenarios when the behavior has real branches — Given/When/Then makes each one independently verifiable:

<!-- adapted from github/spec-kit story template language (MIT) -->
```markdown
## User Story
As a {role}, I can {action} so that {benefit}.

## Acceptance Criteria
- [ ] Given {context}, when {action}, then {outcome}
- [ ] Given {context}, when {action}, then {outcome}

## Notes
{any additional context, constraints, or dependencies}
```

As detailed as possible beats terse — a mermaid flowchart or sequence diagram is welcome in the description when it clarifies a flow (`work_description` supports it). If the story involves a screen, offer to mock it up with the Artifact tool and carry the reference into the eventual handover — don't force it when there's no screen involved.

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

After items are approved and created, ask the user whether to generate a **`planning-to-technical`** handover (see the `handover-protocol` skill) for Technical Planning. Fill the template's `Doc:` line with the Discovery Doc reference if one exists upstream (or "Nenhum doc adicional" if not), and list every created **and** reused key — Technical Planning has no other way to know which items are which.
