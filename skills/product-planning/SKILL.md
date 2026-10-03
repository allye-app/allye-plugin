---
name: product-planning
description: Workflow for translating business requirements into epics and specs in Allye. Use when the user wants to plan a product, define scope, or create epics and specs.
version: "2.0"
category: methodology
---

# Product Planning Workflow

This skill guides you through translating business requirements into a structured hierarchy in Allye Projects: **Project → Epic → Spec** (tasks come later, in Technical Planning).

Use this when the user talks about: requirements, business needs, product scope, MVP, new features, project kickoff, or wants to create epics and specs.

---

## Workflow Overview

```
Understand intent → Search context when useful → Propose epics/specs when traceability helps → Get approval → Create epics and specs → Save decisions
```

Product Planning is recommended for durable product scope, not a mandatory prerequisite for every local implementation. Never create items without explicit approval.

---

## Step 0: Check for a Discovery Doc

If you arrived via a `discovery-to-planning` handover (see the `handover-protocol` skill), read the Discovery Doc it references before anything else — it already captures the approved direction, rejected alternatives, and any research findings. Treat it as established context, not something to re-derive.

---

## Step 1: Understand the Business Context

Before proposing or creating anything, have a conversation with the user to understand:

1. **What problem are we solving?** — The business need or opportunity
2. **Who is it for?** — Target users or stakeholders
3. **What does success look like?** — Expected outcomes or metrics
4. **What's the scope?** — What's in and what's out (MVP vs future)
5. **Are there constraints?** — Timeline, tech stack, dependencies, compliance

<EXTREMELY_IMPORTANT>
Reach full understanding of the business context before creating any epic or spec — ask questions and clarify ambiguities. The quality of planning depends on the quality of understanding.
</EXTREMELY_IMPORTANT>

<!-- adapted from bmad-code-org/BMAD-METHOD create-epics-and-specs (MIT) -->
Treat this as a collaboration between equal partners, not an intake form — the user knows the business, you know how to structure it. Push back on ambiguity and offer options; don't just transcribe what's said.

**If the user already has clear requirements** (e.g., a PRD, a spec, a detailed description), skip the discovery questions and move to Step 2.

---

## Step 2: Search for Existing Context

Before creating new items, check what already exists:

```
memory_search(query: "{product/project name} requirements")
memory_search(query: "{product/project name} architecture")
```

Also check the existing project, epics, and specs:

```
projects.project_list(query: "{product/project name}")
epics.epic_list(project: "{KEY}")
specs.spec_list(project: "{KEY}", query: "{topic}")
```

**If related items exist:**
- Review them to avoid duplication
- Understand what was already planned or decided
- Build on top of existing structure rather than starting fresh
- When presenting the hierarchy in Step 3, mark each item explicitly as **reused** or **new** — never silently create a duplicate of something that already exists

---

## Step 3: Design the Epics and Specs

Plan the structure before creating anything. Present it to the user for approval.

### Working vocabulary: squares and quadradinhos

When talking through the structure with the user, a "square" is an epic-sized deliverable — a puzzle piece of the overall product; a "quadradinho" is a spec inside it. This is conversational shorthand, not a new formal type — it still resolves to the real Project → Epic → Spec → Task hierarchy.

### Levels and when to use them

| Level | Purpose | Example |
|------|---------|---------|
| **Project** | Groups the team's apps (repositories); its KEY prefixes every epic/spec/task key. | `ALY` |
| **Epic** | Lightweight grouping: goal, scope, out of scope, success metrics. No detailed rules. Status is computed from its specs. | "User Authentication System" |
| **Spec** | The single source of truth for one deliverable: business rules, acceptance criteria, decisions. Type `functional`, `technical`, or `bugfix`. May stand alone without an epic (e.g. a bugfix). | "Log in with Google" |

### Rules

<!-- adapted from github/spec-kit story template language (MIT) -->
- Detail lives **only in the spec** — never in the epic, never repeated in tasks
- Every spec must be **independently testable and deliverable** — it produces a working increment on its own
- Prioritize so that **the highest-priority specs alone are a viable increment**

### Present the plan

Show the user the proposed structure before creating anything:

```
Epic: User Authentication System
├── Spec: Register with email and password
├── Spec: Log in with email and password
├── Spec: Reset password via email
├── Spec: Log in with Google
└── Spec: Log out from all devices
```

Wait for the user to approve, modify, or add to this structure before proceeding. If the user explicitly chooses a no-spec path for a small or local change, do not create anything; keep the scope and verification visible instead.

---

## Step 4: Create the Epic and Specs

There are no configurable statuses: a new spec always starts in `draft`, and an epic's status is computed.

### Epic (if it doesn't exist yet)

```
epics.epic_create(
  project: "ALY",
  title: "User Authentication System",
  description: "## Goal\n{business goal}\n\n## Scope\n{what's included}\n\n## Out of scope\n{what's excluded}\n\n## Success metrics\n{how we know it's done}"
)
```

### Specs

```
specs.spec_create(
  project: "ALY",
  epic: "ALY-1",
  title: "Log in with Google",
  type: "functional",
  priority: "high",
  content: "..."
)
```

### Spec content and anchors

Rules and criteria are **anchored lines** — a list item or heading that starts with `[KIND-NN]`. The server parses them; tasks reference them later. Never renumber an anchor; to drop one, remove the line (it becomes deprecated).

<!-- adapted from github/spec-kit story template language (MIT) -->
```markdown
## Context
As a {role}, I can {action} so that {benefit}.

## Business rules
- [BR-01] {rule}

## Acceptance criteria
- [AC-01] WHEN {context/action} THE SYSTEM SHALL {outcome}
- [AC-02] WHEN {context/action} THE SYSTEM SHALL {outcome}

## Decisions
- [D-01] {decision and why}

## Non-functional
- [NFR-01] {performance/security/etc.}

## Open questions
- [Q-01] {question}
```

Open `[Q-NN]` items and `[NEEDS CLARIFICATION]` markers block `spec_submit` — resolve them (`[Q-01] (resolved) question → answer`) or remove them before submitting. As detailed as possible beats terse — a mermaid diagram is welcome in the spec when it clarifies a flow. If the spec involves a screen, offer to mock it up with the Artifact tool and carry the reference into the eventual handover — don't force it when there's no screen involved.

### Review and approval

When the user is happy with a spec, `specs.spec_submit` moves it `draft → in_review`. **Approval is the user's call:** run `specs.spec_approve` only when the user explicitly asks you to approve that spec in this conversation.

---

## Step 5: Save Planning Decisions

Save key decisions as memories for future reference:

```
memory_save(
  title: "Planning — {Epic name} scope and decisions",
  content: "## Scope\n{what was included/excluded and why}\n\n## Key decisions\n- {decision 1}: {rationale}\n- {decision 2}: {rationale}\n\n## Hierarchy\n{the approved structure}\n\n## Open questions\n{anything deferred}",
  tags: ["planning", "decision", "{epic-key}"],
  sector: "decisions"
)
```

---

## Workflow Checklist

Before considering product planning complete, verify:

- [ ] Business context is understood (problem, users, scope, constraints)
- [ ] Existing epics, specs, and memories were checked
- [ ] Hierarchy was presented to and approved by the user
- [ ] Epics and specs are created in Allye (specs linked to their epic)
- [ ] Specs have anchored acceptance criteria (`[AC-NN]`) and no open `[Q-NN]` before submit
- [ ] Priority is set (if applicable)
- [ ] Planning decisions are saved as memories

---

## What Comes Next

After the epics and specs are approved and created, ask the user whether to generate a **`planning-to-technical`** handover (see the `handover-protocol` skill) for Technical Planning. Fill the template's `Doc:` line with the Discovery Doc reference if one exists upstream (or "Nenhum doc adicional" if not), and list every created **and** reused epic/spec key — Technical Planning has no other way to know which are which.
