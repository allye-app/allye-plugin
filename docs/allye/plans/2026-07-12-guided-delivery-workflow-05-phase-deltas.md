# Allye Guided Delivery Workflow — Plan 5: Phase-Skill Deltas

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `product-planning`, `technical-planning`, and `execution` into the Handover Catalog (Plan 2) and Orchestrator (Plan 4), and layer in the deltas the design spec calls for on each: squares/quadradinhos vocabulary and reuse-or-create discipline on Planning; mandatory architecture gray areas and concern-based task granularity on Technical Planning; single-story scope and stricter ask-don't-assume on Execution.

**Architecture:** No new files — every task in this plan **edits** an existing, already-solid skill (each has the right bones per spec §3's non-goals: "not a rewrite... this design extends them"). Every edit is a targeted insertion or replacement with an exact anchor, not a rewrite of the file.

**Tech Stack:** Markdown only.

**Source spec:** `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md` §6.2 (Planning), §6.3 (Technical Planning), §6.5 (Executor), §7 (adaptation sources — spec-kit story templates, BMAD `create-epics-and-stories`, superpowers `writing-plans`/`verification-before-completion`).

**Depends on:** Plan 1 (renamed skill files this plan edits), Plan 2 (handover types this plan's exit sections reference: `planning-to-technical`, `technical-to-orchestration`, `execution-report`), Plan 3 (`deep-search`/`code-analyzer` agents this plan's Technical Planning delta dispatches), Plan 4 (`orchestrator` skill this plan's Technical Planning and Execution exits hand off to).

## Global Constraints

- These are **edits**, not rewrites. Every existing section (Steps, Workflow Checklists, memory-save templates) stays exactly as it is except where a task below explicitly changes it. Do not "clean up" or restructure anything not called out.
- Every adapted section carries a one-line credit comment, per spec §7's rule of thumb.
- Every task's final commit uses `git commit -m "..." -- <exact-path>` (pathspec-scoped) — same requirement as Plans 3-4.
- The three files this plan touches (`skills/product-planning/SKILL.md`, `skills/technical-planning/SKILL.md`, `skills/execution/SKILL.md`) are fully disjoint — no coordination needed between this plan's tasks.

## File Structure

| File | Responsibility |
|---|---|
| `skills/product-planning/SKILL.md` | Add: Step 0 (Discovery Doc check), squares/quadradinhos vocabulary, explicit reused-vs-new marking, spec-kit story-quality language, mermaid/prototype notes, BMAD collaboration framing, `planning-to-technical` handover exit |
| `skills/technical-planning/SKILL.md` | Add: never-assume framing, mandatory architecture gray area + research dispatch, concern-based granularity + superpowers task right-sizing, `technical-to-orchestration` handover exit |
| `skills/execution/SKILL.md` | Add: single-story/handover scope note, TDD credit pointer, strengthened decision checkpoint, verification-before-completion gate, `execution-report` handover exit |

## Task 1: Edit `skills/product-planning/SKILL.md`

**Files:**
- Modify: `skills/product-planning/SKILL.md`

**Interfaces:**
- Consumes: `handover-protocol`'s `discovery-to-planning` template (received, Step 0) and `planning-to-technical` template (emitted, exit)

- [ ] **Step 1: Add collaboration framing to the existing EXTREMELY_IMPORTANT block**

Find:
```markdown
<EXTREMELY_IMPORTANT>
Do NOT jump to creating work items before you understand the business context.
Ask questions. Clarify ambiguities. The quality of planning depends on the quality of understanding.
</EXTREMELY_IMPORTANT>
```
Replace with:
```markdown
<EXTREMELY_IMPORTANT>
Do NOT jump to creating work items before you understand the business context.
Ask questions. Clarify ambiguities. The quality of planning depends on the quality of understanding.
</EXTREMELY_IMPORTANT>

<!-- adapted from bmad-code-org/BMAD-METHOD create-epics-and-stories (MIT) -->
Treat this as a collaboration between equal partners, not an intake form — the user knows the business, you know how to structure it. Push back on ambiguity and offer options; don't just transcribe what's said.
```

- [ ] **Step 2: Add Step 0 (Discovery Doc check) before Step 1**

Find:
```markdown
## Step 1: Understand the Business Context

Before creating anything, have a conversation with the user to understand:
```
Replace with:
```markdown
## Step 0: Check for a Discovery Doc

If you arrived via a `discovery-to-planning` handover (see the `handover-protocol` skill), read the Discovery Doc it references before anything else — it already captures the approved direction, rejected alternatives, and any research findings. Treat it as established context, not something to re-derive.

---

## Step 1: Understand the Business Context

Before creating anything, have a conversation with the user to understand:
```

- [ ] **Step 3: Strengthen the reuse-or-create instruction in Step 2**

Find:
```markdown
**If related items exist:**
- Review them to avoid duplication
- Understand what was already planned or decided
- Build on top of existing structure rather than starting fresh
```
Replace with:
```markdown
**If related items exist:**
- Review them to avoid duplication
- Understand what was already planned or decided
- Build on top of existing structure rather than starting fresh
- When presenting the hierarchy in Step 3, mark each item explicitly as **reused** or **new** — never silently create a duplicate of something that already exists
```

- [ ] **Step 4: Add the squares/quadradinhos vocabulary note to Step 3**

Find:
```markdown
## Step 3: Design the Work Item Hierarchy

Plan the hierarchy before creating items. Present it to the user for approval.

### Item types and when to use them
```
Replace with:
```markdown
## Step 3: Design the Work Item Hierarchy

Plan the hierarchy before creating items. Present it to the user for approval.

### Working vocabulary: squares and quadradinhos

When talking through the structure with the user, a "square" is a Feature-sized deliverable — a puzzle piece of the overall product; a "quadradinho" is a Story inside it. This is conversational shorthand, not a new formal type — it still resolves to the real Epic → Feature → Story hierarchy below.

### Item types and when to use them
```

- [ ] **Step 5: Strengthen hierarchy rules with spec-kit's story-quality language**

Find:
```markdown
### Hierarchy rules

- An **Epic** contains **Features**
- A **Feature** contains **Stories**
- Every Story must be **independently deliverable** — it produces a working increment
- Stories should follow the format: "As a {role}, I can {action} so that {benefit}" (when applicable)
```
Replace with:
```markdown
### Hierarchy rules

<!-- adapted from github/spec-kit story template language (MIT) -->
- An **Epic** contains **Features**
- A **Feature** contains **Stories**
- Every Story must be **independently testable and deliverable** — it produces a working increment on its own, not just alongside its siblings
- Stories should follow the format: "As a {role}, I can {action} so that {benefit}" (when applicable)
- Prioritize so that **P1 alone is a viable increment** — if only the highest-priority stories shipped, there should still be something real to show
```

- [ ] **Step 6: Add Given/When/Then + mermaid + prototype guidance to Story descriptions**

Find:
```markdown
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
```
Replace with:
```markdown
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
```

- [ ] **Step 7: Replace "What Comes Next" with the handover exit**

Find:
```markdown
## What Comes Next

After product planning is complete, the user will pick a story to work on. That transitions to **Technical Planning** — load the `allye-technical-planning` skill.
```
Replace with:
```markdown
## What Comes Next

After items are approved and created, ask the user whether to generate a **`planning-to-technical`** handover (see the `handover-protocol` skill) for Technical Planning. Include the doc reference (if any) and every created **and** reused key — Technical Planning has no other way to know which items are which.
```

- [ ] **Step 8: Verify all 7 edits landed and nothing else changed**

Run:
```bash
grep -c "^## Step 0: Check for a Discovery Doc$" skills/product-planning/SKILL.md
grep -c "squares and quadradinhos" skills/product-planning/SKILL.md
grep -c "planning-to-technical" skills/product-planning/SKILL.md
grep -c "adapted from" skills/product-planning/SKILL.md
grep -c "^## Step 1: Understand the Business Context$" skills/product-planning/SKILL.md
grep -c "^## Workflow Checklist$" skills/product-planning/SKILL.md
```
Expected: each of the first four prints at least `1`; the last two (pre-existing, untouched section headers) each print exactly `1` — confirming the surrounding structure wasn't duplicated or damaged.

- [ ] **Step 9: Commit**

```bash
git add skills/product-planning/SKILL.md
git commit -m "feat: wire product-planning into handover catalog, add squares vocabulary and story-quality guidance" -- skills/product-planning/SKILL.md
```

## Task 2: Edit `skills/technical-planning/SKILL.md`

**Files:**
- Modify: `skills/technical-planning/SKILL.md`

**Interfaces:**
- Consumes: `handover-protocol`'s `planning-to-technical` template (received) and `technical-to-orchestration` template (emitted, exit); the `deep-search`/`code-analyzer` agents (Plan 3)

- [ ] **Step 1: Add the never-assume framing to the intro**

Find:
```markdown
This skill guides you through taking a story and turning it into actionable tasks through a **Discussion Phase** — identifying gray areas, capturing decisions, and creating tasks with verifiable acceptance criteria.

Use this when the user has a story and wants to: plan tasks, discuss approach, evaluate technical options, or break down implementation work.
```
Replace with:
```markdown
This skill guides you through taking a story and turning it into actionable tasks through a **Discussion Phase** — identifying gray areas, capturing decisions, and creating tasks with verifiable acceptance criteria.

Use this when the user has a story and wants to: plan tasks, discuss approach, evaluate technical options, or break down implementation work.

**Never assume — always ask.** The user knows the direction they want, sometimes only after researching further. Your job is to surface the gray areas and present real options, not to quietly pick one and present it as the plan.
```

- [ ] **Step 2: Add the mandatory architecture gray area and research-dispatch note**

Find:
```markdown
Examples of gray areas:
- Which library/framework to use for X?
- Should this be a separate service or part of the monolith?
- How should we handle error case Y?
- What's the data model for Z?
- Should we optimize for read speed or write speed?
- How much backward compatibility do we need?
```
Replace with:
```markdown
Examples of gray areas:
- Which library/framework to use for X?
- Should this be a separate service or part of the monolith?
- How should we handle error case Y?
- What's the data model for Z?
- Should we optimize for read speed or write speed?
- How much backward compatibility do we need?

**Mandatory:** whenever a story implies infrastructure, stack, or architecture choices, that is always a gray area to raise explicitly — never left to chance or agent discretion by default.

**Need more than a hunch to evaluate an option?** Dispatch the `deep-search` agent (web research) or the `code-analyzer` agent (analyze a public repo), both via the `Agent` tool — research is available here, not only in Sandbox. Bring findings back into the discussion before locking a decision.
```

- [ ] **Step 3: Add concern-based granularity and task right-sizing to 4.1**

Find:
```markdown
### 4.1 Plan the Task Breakdown

Design tasks that are:

- **Atomic** — Each task produces a single, verifiable outcome
- **Ordered by dependency** — Independent tasks first, dependent tasks after
- **Concrete** — No vague tasks like "set up the project" or "implement the feature"
```
Replace with:
```markdown
### 4.1 Plan the Task Breakdown

Design tasks that are:

- **Atomic** — Each task produces a single, verifiable outcome
- **Ordered by dependency** — Independent tasks first, dependent tasks after
- **Concrete** — No vague tasks like "set up the project" or "implement the feature"

**Split by concern when a story spans them.** A story touching frontend, backend, and data modeling is usually 3+ tasks, not one — the Wave mechanic below (4.4) handles the ordering (e.g., data modeling before frontend when the payload shape is a hard dependency). These are illustrative categories, not a fixed taxonomy: decide the actual split with the user, scenario by scenario.

<!-- adapted from superpowers:writing-plans task right-sizing (MIT) -->
**Right-size each task**: the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate. Fold setup/config into the task whose deliverable needs it; split only where a reviewer could reject one task while approving its neighbor.
```

- [ ] **Step 4: Replace "What Comes Next" with the handover exit**

Find:
```markdown
## What Comes Next

The user picks a task (or the first task in Wave 1) and starts implementing. That transitions to **Technical Development** — load the `allye-technical-development` skill.
```
Replace with:
```markdown
## What Comes Next

Emit a **`technical-to-orchestration`** handover (see the `handover-protocol` skill) for the Orchestrator. Spell out the full reading list — doc, epic, feature, every story, every task, grouped by wave — and every locked architecture decision. The Orchestrator has no other context; a vague pointer here becomes its problem later.
```

- [ ] **Step 5: Verify all 4 edits landed and nothing else changed**

Run:
```bash
grep -c "Never assume — always ask" skills/technical-planning/SKILL.md
grep -c "Mandatory:.*infrastructure, stack, or architecture" skills/technical-planning/SKILL.md
grep -c "Right-size each task" skills/technical-planning/SKILL.md
grep -c "technical-to-orchestration" skills/technical-planning/SKILL.md
grep -c "^### 3.1 Identify Gray Areas$" skills/technical-planning/SKILL.md
grep -c "^## Workflow Checklist$" skills/technical-planning/SKILL.md
```
Expected: each of the first four prints at least `1`; the last two each print exactly `1`.

- [ ] **Step 6: Commit**

```bash
git add skills/technical-planning/SKILL.md
git commit -m "feat: wire technical-planning into handover catalog and orchestrator, add mandatory architecture gray area and task right-sizing" -- skills/technical-planning/SKILL.md
```

## Task 3: Edit `skills/execution/SKILL.md`

**Files:**
- Modify: `skills/execution/SKILL.md`

**Interfaces:**
- Consumes: `handover-protocol`'s `story-execution` and `correction` templates (received); `execution-report` template (emitted, exit)

- [ ] **Step 1: Add the single-story/handover scope note to the intro**

Find:
```markdown
This skill guides you through implementing a task with discipline: read existing code first, write tests, implement, refactor, and track progress in Allye.

Use this when the user wants to: write code, implement a task, fix a bug, add functionality, or develop features.
```
Replace with:
```markdown
This skill guides you through implementing a task with discipline: read existing code first, write tests, implement, refactor, and track progress in Allye.

Use this when the user wants to: write code, implement a task, fix a bug, add functionality, or develop features.

**Scope, if you arrived via a `story-execution` or `correction` handover (see `handover-protocol`):** read only the one story and its tasks named in the handover — nothing else. A `correction` handover carries only the failed findings, not the whole story again; fix exactly what it lists.
```

- [ ] **Step 2: Add the TDD credit pointer**

Find:
```markdown
## Step 5: TDD — Test-Driven Development

### Should I use TDD for this task?

Apply the **TDD Detection Heuristic**:
```
Replace with:
```markdown
## Step 5: TDD — Test-Driven Development

<!-- full discipline lives in the tdd-workflow skill, aligned with superpowers:test-driven-development (MIT) -->

### Should I use TDD for this task?

Apply the **TDD Detection Heuristic**:
```

- [ ] **Step 3: Strengthen the decision checkpoint**

Find:
```markdown
### `decision` Checkpoint

If during implementation you encounter a choice not covered by the discussion phase:

> "I found a decision point not covered in planning:
> {describe the options}
>
> Which approach do you prefer?"

Save the decision as a memory once resolved.
```
Replace with:
```markdown
### `decision` Checkpoint

**If uncertain which path to take, STOP and ask — never proceed on assumption.** If during implementation you encounter a choice not covered by the discussion phase:

> "I found a decision point not covered in planning:
> {describe the options}
>
> Which approach do you prefer?"

Save the decision as a memory once resolved.
```

- [ ] **Step 4: Add the verification-before-completion gate before marking done**

Find:
```markdown
## Step 7: Mark Task as Done

Once all acceptance criteria are met and tests pass:

```
work_status_done(id: "{task uuid}")
```

This sets the task to the "done" status and records `completed_at`.
```
Replace with:
```markdown
## Step 7: Mark Task as Done

<!-- adapted from superpowers:verification-before-completion (MIT) — evidence before assertions -->
**Evidence before assertions.** Don't mark a task done because it looks right — run the tests, read the actual output, and confirm each acceptance criterion against that output before proceeding. "Should work" is not the same as "ran and passed."

Once all acceptance criteria are verifiably met and tests pass:

```
work_status_done(id: "{task uuid}")
```

This sets the task to the "done" status and records `completed_at`.
```

- [ ] **Step 5: Replace the Step 9 exit bullet and "What Comes Next" with the handover exit**

Find:
```markdown
- If there are more tasks in the current wave → pick one
- If the current wave is done → move to the next wave
- If all tasks are done → transition to **Technical Review** (load `allye-technical-review` skill)
```
Replace with:
```markdown
- If there are more tasks in the current wave → pick one
- If the current wave is done → move to the next wave
- If all tasks in the story are done → emit an **`execution-report`** handover (see the `handover-protocol` skill) back to the Orchestrator
```

Find:
```markdown
## What Comes Next

When all tasks for the story are complete, transition to **Technical Review** — load the `allye-technical-review` skill.
```
Replace with:
```markdown
## What Comes Next

Emit the `execution-report` handover: files changed, tests added, status per acceptance criterion (not a blanket "done"), any new decisions made along the way, and any open questions. The Orchestrator decides from there whether to dispatch Reviewer or, if this is a `correction` round, loop back with more specific findings.
```

- [ ] **Step 6: Verify all 5 edits landed and nothing else changed**

Run:
```bash
grep -c "Scope, if you arrived via a .story-execution. or .correction. handover" skills/execution/SKILL.md
grep -c "STOP and ask — never proceed on assumption" skills/execution/SKILL.md
grep -c "Evidence before assertions" skills/execution/SKILL.md
grep -c "execution-report" skills/execution/SKILL.md
grep -c "^## Step 5: TDD — Test-Driven Development$" skills/execution/SKILL.md
grep -c "^## Workflow Checklist$" skills/execution/SKILL.md
```
Expected: each of the first four prints at least `1`; the last two each print exactly `1`.

- [ ] **Step 7: Commit**

```bash
git add skills/execution/SKILL.md
git commit -m "feat: wire execution into handover catalog, scope to single story, strengthen ask-don't-assume and verification-before-completion" -- skills/execution/SKILL.md
```

## Task 4: Verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Confirm the "What Comes Next" exit chains form a coherent loop with no stale skill-name transitions left**

```bash
grep -A2 "^## What Comes Next$" skills/product-planning/SKILL.md skills/technical-planning/SKILL.md skills/execution/SKILL.md
```
Expected: `product-planning` points to a `planning-to-technical` handover; `technical-planning` points to a `technical-to-orchestration` handover; `execution` points to an `execution-report` handover. None say "load the `allye-technical-*` skill" anymore.

- [ ] **Step 2: Confirm all credit comments across the three files are present**

```bash
grep -c "adapted from" skills/product-planning/SKILL.md skills/technical-planning/SKILL.md skills/execution/SKILL.md
```
Expected: each file prints at least `1`.

- [ ] **Step 3: Confirm none of the pre-existing HARD-GATE/EXTREMELY_IMPORTANT blocks were damaged**

```bash
grep -c "HARD-GATE" skills/technical-planning/SKILL.md skills/execution/SKILL.md
grep -c "EXTREMELY_IMPORTANT" skills/product-planning/SKILL.md skills/technical-planning/SKILL.md skills/execution/SKILL.md
```
Expected: `technical-planning/SKILL.md` shows `2` (one HARD-GATE pair, unchanged from before this plan); `execution/SKILL.md` shows `4` (two HARD-GATE pairs — Read First and Automation-First — unchanged); the EXTREMELY_IMPORTANT counts match what existed before this plan (`product-planning`: `2`, `technical-planning`: `2`, `execution`: `2`).

- [ ] **Step 4: If everything passes, this plan is complete — no commit needed for this task (verification only)**

## Self-review (writing-plans §Self-Review, performed before handing this plan off)

- **Spec coverage:** §6.2's Step 0, squares vocabulary, reuse-or-create, story quality, mermaid/prototypes, and handover exit are all covered (Task 1). §6.3's never-assume framing, mandatory architecture gray area, research dispatch, concern-based granularity, task right-sizing, and handover exit are all covered (Task 2). §6.5's scope, TDD credit, decision checkpoint, verification gate, and handover exit are all covered (Task 3). Nothing in spec §6.2/§6.3/§6.5 is uncovered.
- **Placeholder scan:** every edit gives the exact find/replace text — no "add appropriate guidance here" or similar. Every inserted block is complete, final prose.
- **Type/name consistency:** handover type names (`discovery-to-planning`, `planning-to-technical`, `technical-to-orchestration`, `story-execution`, `correction`, `execution-report`) all match Plan 2's catalog exactly. `deep-search`/`code-analyzer` match Plan 3's agent names. `orchestrator` matches Plan 4's skill name.

## What comes next

6. **OpenCode package rework + manifest updates** — the last plan in this sequence: delete `packages/allye-opencode/scripts/generate-prompts.ts`'s generation step in favor of a runtime skill-reading adapter, add an Orchestrator role to the OpenCode agent-picker, generalize `allye-plan.ts`'s existing `PLAN_HANDOFF_FLOW` onto the shared marker format from Plan 2, and add the deferred handover-marker-detection paragraph to `manifests/{codex,cursor,gemini}`.
