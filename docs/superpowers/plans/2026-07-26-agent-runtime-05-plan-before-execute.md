# Plan-Before-Execute and Allye Self-Sufficiency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is the last plan that will name an external suite — Task 5 removes the dependency from the repository's own vocabulary.

**Goal:** Make the Executor state *how* it will build before it builds, and check that statement against what was asked for while a mistake still costs a paragraph. Then close the four structural gaps that sent this project's own development to an external plan format, so nothing needs to leave Allye again.

**Architecture:** One new step between reading and writing, mirrored in the interactive skill and the dispatched agent. Three mechanical checks that always run; the judgement call bound to the AFK/HITL label Plan 02 derives. The four gaps are filled inside the structures that already exist — no parallel artifact, because a plan that drifts from its work items is worse than no plan.

**Tech Stack:** Markdown skills. No build step, no test framework — verification is grep assertion.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract.** Never rename one.
- **Skill files stay in English.**
- **Frontmatter keys are `name`, `description`, `version`, `category`.** Bump `version` minor on any skill changed.
- **Attribution comments stay.** MIT and Apache-2.0 require retaining attribution in derivative work. Task 5 renames a directory; it does not remove a single `<!-- adapted from ... -->` comment. Self-sufficiency means never *needing* another suite installed, which is already true — it does not mean erasing where ideas came from, which is not achievable by deleting a comment.
- **Preserve every `opencode-exclude` marker.** `skills/orchestrator/SKILL.md` carries sixteen and `skills/handover-protocol/SKILL.md` three. Count before and after any edit to those files.
- **Do not push. Do not merge to `main`.**

## Prerequisites

Plans 01–04 complete and merged.

```bash
ls skills/verification-loop/SKILL.md skills/agent-runtime/SKILL.md   # both exist
ls agents/reviewer-standards.md agents/reviewer-spec.md              # both exist
grep -c 'Dispatch label' skills/handover-protocol/references/story-execution.md   # at least 1
```

---

### Task 1: Add Step 4.5 to the interactive Executor

**Files:**
- Modify: `skills/execution/SKILL.md`

**Interfaces:**
- Consumes: the `## Verification` block and the AFK/HITL label from Plan 02; the `plans` memory sector.
- Produces: an implementation-plan memory, `sector: "plans"`, tagged with the story key. Task 2 mirrors it for the dispatched agent; `reviewer-spec` may read it.

- [x] **Step 1: Establish the failing assertion**

```bash
grep -n 'Step 4.5\|Plan the implementation' skills/execution/SKILL.md
grep -n 'sector: "plans"' skills/execution/SKILL.md
```
Expected: **no output from either.** The skill currently goes from Step 4 (Read First) straight to Step 5 (TDD).

- [x] **Step 2: Insert the step between reading and writing**

In `skills/execution/SKILL.md`, after Step 4's "Analysis Paralysis Guard" and before "## Step 5: TDD", insert:

```markdown
---

## Step 4.5: Plan the Implementation

You have read the code and written none. This is where you state *how* you will build it,
and check that statement against what was asked for — while being wrong still costs a
paragraph rather than a branch.

### Write the plan

Per task in this story:

- **Approach** — the shape of the change, in a sentence or two.
- **Files** — what you will create or modify. Names, never line numbers; the tree moves.
- **Interfaces produced** — the names, types, and signatures other tasks in this story will
  call. Whoever implements a neighbouring task sees only their own task description, so
  this is the only place they learn what to call.
- **How each criterion goes green** — for every acceptance criterion, which step makes its
  `## Verification` command pass. A criterion with no step against it is the finding this
  whole exercise exists to produce.

Save it:

```
memory_save(
  title: "Implementation Plan — {STORY-KEY} {story title}",
  content: "## Per task\n{approach, files, interfaces produced, criterion → step}\n\n## Order\n{which task first, and why}\n\n## Open questions\n{anything planning did not settle, or 'None'}",
  tags: ["plan", "implementation", "{story-key}"],
  sector: "plans"
)
```

It outlives the session. A resumed Executor reads what was intended rather than inferring
it from half-written code, and `reviewer-spec` can compare the implementation against the
plan and not only against the criteria.

### Validate it

<HARD-GATE>
Three checks, run every time, before writing any code:

1. **Coverage** — every acceptance criterion, in every task, has a step that produces it.
2. **Decisions** — every locked decision from planning is respected. A locked decision was
   chosen by the human. A plan that quietly departs from one is a defect whether or not the
   resulting code works.
3. **Closure** — no step depends on something the plan never defines. If a type, function,
   file, or value appears as a dependency and never as an output, the plan has a hole in it.

A failure is reported as `❌ blocked` **before any code exists**, naming which criterion or
decision has nothing behind it. This is the same halt-and-report contract you already carry,
fired at the cheapest possible moment.
</HARD-GATE>

### Whether the approach is right

The three checks above are mechanical. Whether the approach is a *good* one is judgement,
and who supplies it follows the story's dispatch label (see `verification-loop` §4):

- **AFK** — self-validation is enough. Run the three checks and proceed.
- **HITL** — put the plan in front of the user and wait before writing anything.
- **Either label**, if planning surfaced a decision the discussion phase never covered —
  stop and raise it regardless. A decision discovered while planning is precisely the case
  the label could not have anticipated.
```

- [x] **Step 3: Add the checklist items**

In the "Workflow Checklist", after the read-first item:

```markdown
- [ ] An implementation plan was written and saved to the `plans` sector before any code
- [ ] Coverage, decisions, and closure all checked against that plan
```

- [x] **Step 4: Verify**

```bash
grep -n '## Step 4.5: Plan the Implementation' skills/execution/SKILL.md
grep -c 'sector: "plans"' skills/execution/SKILL.md
grep -n 'before any code exists' skills/execution/SKILL.md
grep -n 'Interfaces produced' skills/execution/SKILL.md
grep -c 'Step 5' skills/execution/SKILL.md
```
Expected: the heading found; the `plans` sector used exactly once; the before-any-code phrasing present; the interfaces bullet present; and Step 5 still there — the new step is inserted, not substituted.

- [x] **Step 5: Bump version and commit**

```bash
git add skills/execution/
git commit -m "feat(execution): plan the implementation before writing any code

Adds Step 4.5 between reading and writing: state the approach, the files,
the interfaces produced, and which step makes each criterion go green;
save it to the plans sector; then check coverage, locked decisions, and
closure before any code exists.

The Executor's halt-and-report already fires when a task turns out
underspecified — it fired mid-implementation, with code written. This
fires it while being wrong still costs a paragraph."
```

---

### Task 2: Mirror Step 4.5 in the dispatched Executor

The dispatched agent cannot ask. That makes the HITL branch different and the three checks more load-bearing — hitting one is the only signal a human gets before code exists.

**Files:**
- Modify: `agents/executor.md`

**Interfaces:**
- Consumes: Task 1's three checks, by name.
- Produces: a `❌ blocked` report shape that names the failed check.

- [x] **Step 1: Establish the failing assertion**

```bash
grep -c 'Implementation Plan\|plan the implementation' agents/executor.md
```
Expected: `0`.

- [x] **Step 2: Add the discipline bullet**

In the "Discipline" list, **before** the read-first bullet — it comes first in time and the list is read in order:

```markdown
- **Plan before you write, and validate the plan.** After reading and before any code: state per task the approach, the files, the interfaces the task produces, and which step makes each acceptance criterion's `## Verification` command go green. Save it with `memory_save`, `sector: "plans"`, tagged with the story key. Then run three checks — **coverage** (every criterion has a step), **decisions** (every locked decision respected), **closure** (nothing depended on that the plan never defines). See the `execution` skill's Step 4.5 for the full shape.
```

- [x] **Step 3: Extend the halt-and-report contract**

Add a paragraph inside the existing HARD-GATE:

```markdown
A failed plan check is the same kind of stop, and the cheapest one available to you. Report
`❌ blocked` naming which check failed and what has nothing behind it — the criterion with no
step, the locked decision the approach would violate, the undefined thing a step depends on.

You cannot ask, so the plan check is where your inability to ask costs least. A gap found
here is a paragraph; the same gap found in Step 5 is a branch.
```

- [x] **Step 4: Handle the HITL branch, which you cannot serve**

Add to the same gate:

```markdown
**A HITL story should not have reached you.** The Orchestrator does not dispatch one to an
unattended pane. If your dispatch prompt carries a HITL label anyway, do not attempt the
human's half of the judgement: write the plan, run the three checks, and return it as
`❌ blocked` with the reason "HITL story dispatched unattended — plan attached, approach not
validated by a human." The plan is still useful; the missing validation is not something you
can supply.
```

- [x] **Step 5: Verify**

```bash
grep -c 'sector: "plans"' agents/executor.md
grep -n 'coverage' agents/executor.md
grep -n 'HITL story dispatched unattended' agents/executor.md
grep -n 'a paragraph; the same gap found in Step 5 is a branch' agents/executor.md
```
Expected: all four found.

- [x] **Step 6: Commit**

```bash
git add agents/executor.md
git commit -m "feat(executor): plan and validate before writing, and report the gap

The dispatched executor runs the same plan-then-validate step as the
interactive skill. A failed check is halt-and-report at its cheapest
point, since it cannot ask and a gap found while planning costs a
paragraph where the same gap in implementation costs a branch.

Also handles a HITL story reaching it anyway: write the plan, run the
checks, return blocked rather than supplying the human's half of the
judgement."
```

---

### Task 3: Close two of the four structural gaps in `technical-planning`

**Files:**
- Modify: `skills/technical-planning/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: an `## Interfaces` section in every task description, which Task 1's plan step reads and Task 4's handover carries.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -n '## Interfaces' skills/technical-planning/SKILL.md
grep -n -i 'placeholder' skills/technical-planning/SKILL.md
```
Expected: **no output from either.**

- [ ] **Step 2: Add `Interfaces` to the task template**

In section 4.3 "Task Description Template", after the `## Dependencies` block:

```markdown
## Interfaces
**Consumes:** {names, types, and signatures this task calls that another task in this story
produces — or "Nothing from other tasks"}
**Produces:** {names, types, and signatures other tasks will call. Exact, not descriptive:
`createSession(userId: string): Session`, not "a session creator".}
```

And immediately below the template:

```markdown
The `Interfaces` block exists because whoever implements a task sees **only that task**.
Dependencies tell them what must finish first; interfaces tell them what to call when it
has. Writing "a session creator" instead of the signature moves the naming decision to
whoever implements second, and they will name it something else.
```

- [ ] **Step 3: Add the no-placeholders gate**

After the existing Verification Rule gate in 4.2.1:

```markdown
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
```

- [ ] **Step 4: Add the checklist items**

```markdown
- [ ] Every task's `Interfaces` block names exact signatures, not descriptions
- [ ] No task description contains a placeholder or an unnamed edge case
```

- [ ] **Step 5: Verify**

```bash
grep -c '## Interfaces' skills/technical-planning/SKILL.md
grep -n 'No Placeholders' skills/technical-planning/SKILL.md
grep -n 'not "a session creator"' skills/technical-planning/SKILL.md
grep -n 'read in isolation and out of order' skills/technical-planning/SKILL.md
grep -c 'Verification Rule' skills/technical-planning/SKILL.md
```
Expected: all found, and Plan 02's Verification Rule still present — this task adds a sibling gate, it does not replace one.

- [ ] **Step 6: Bump version and commit**

```bash
git add skills/technical-planning/
git commit -m "feat(technical-planning): Interfaces block and a no-placeholders gate

Whoever implements a task sees only that task. Dependencies say what must
finish first; interfaces say what to call when it has, with exact
signatures — a description moves the naming decision to whoever
implements second, and they name it differently.

The placeholder gate names the five shapes that read as complete while
deferring the decision to someone with less context and no way to ask."
```

---

### Task 4: Constraints stated once, and three briefing behaviours the templates never had

Two things, one file pair, because both are about what a handover carries.

**Files:**
- Modify: `skills/handover-protocol/SKILL.md`
- Modify: `skills/handover-protocol/references/story-execution.md`

**Interfaces:**
- Consumes: Task 3's `Interfaces` block.
- Produces: the final shape of the `story-execution` handover.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -n -i 'delivery constraints' skills/handover-protocol/SKILL.md
grep -n 'contradict' skills/handover-protocol/references/story-execution.md
grep -c 'opencode-exclude' skills/handover-protocol/SKILL.md
```
Expected: no output from the first two; record the third — it must not drop.

- [ ] **Step 2: Reference feature constraints instead of recopying them**

`Applicable code standards` appears **twice** in this file — once in the "Before emitting, confirm" list and once as a template heading. Both go; leaving the first turns it into an instruction to fill a field that no longer exists.

First, in the "Before emitting, confirm" list, replace the bullet beginning *"Applicable code standards were discovered"* with the constraints bullet given in the next sub-step. Then, in the template body, replace the `### Applicable code standards` heading and its placeholder line with:

```markdown
### Constraints
Reference to the feature's constraints doc in Allye — read it, do not expect it summarised here.
{doc title and id, or "No constraints doc — follow existing conventions in the code"}
```

The bullet that replaces the old code-standards one:

```markdown
- **Constraints are referenced, not recopied.** Anything true of every story under this
  feature — the base branch, the test command, naming rules, the definition of done — belongs
  in one feature-level doc that each handover points at. Recopying it into every handover
  creates as many places to drift as there are stories, and the drift is silent because each
  copy looks authoritative.
```

- [ ] **Step 3: Add the three briefing behaviours to the closing reminder**

The template currently closes with a "stop and ask" line. Replace that closing block with:

```markdown
---
Read ONLY this story and these tasks. Execute the waves in the listed order.

**If anything is unclear, STOP and ask — don't proceed on a guess.**

**If anything is contradictory, STOP and report it.** A step that is perfectly clear and
impossible is a different failure from an ambiguous one, and the more dangerous: it can be
satisfied by quietly weakening whatever it conflicts with. Two criteria that cannot both
hold, a task requiring what another forbids — report both halves, quoted, and resolve
neither.

**Report what is wrong but out of scope — do not fix it.** A defect you notice while working
on something else is worth more reported than silently repaired, because a silent repair
hides a decision that was never made.

**Do not report "no issues" to be agreeable.** A conflict named is worth more than a clean
report. If two rules genuinely disagreed and you chose one, say which and why.
```

- [ ] **Step 4: Verify**

```bash
grep -c 'opencode-exclude' skills/handover-protocol/SKILL.md
grep -n 'contradictory, STOP and report' skills/handover-protocol/references/story-execution.md
grep -n 'out of scope — do not fix' skills/handover-protocol/references/story-execution.md
grep -n 'to be agreeable' skills/handover-protocol/references/story-execution.md
grep -n 'Constraints are referenced, not recopied' skills/handover-protocol/references/story-execution.md
grep -c '🔄 Allye Handover' skills/handover-protocol/references/story-execution.md
```
Expected: the marker count unchanged from Step 1; all four new passages found; the handover marker still present and unmodified.

- [ ] **Step 5: Bump version and commit**

```bash
git add skills/handover-protocol/
git commit -m "feat(handover-protocol): reference constraints, and three reporting rules

Feature-wide constraints live in one doc the handover points at. Recopied
into every story handover they create one drift site per story, each copy
looking authoritative.

Adds three behaviours that produced every genuinely useful finding across
four dispatched executions and existed only in hand-written briefings:
stop on a contradiction rather than an ambiguity, report out-of-scope
defects without fixing them, and never report clean to be agreeable."
```

---

### Task 5: Rename `docs/superpowers/` to `docs/allye/`

Cosmetic, and correct. These are the plugin's own development artifacts, which is a separate thing from what the plugin instructs a user's agent to do — only the second ever mattered for self-sufficiency, and it was never in question.

**Files:**
- Rename: `docs/superpowers/` → `docs/allye/`
- Modify: every file referencing the old path

- [ ] **Step 1: Find every reference**

```bash
grep -rn 'docs/superpowers' . --exclude-dir=.git --exclude-dir=node_modules -l
```
Expected: `CLAUDE.md`, both 2026-07-12 and 2026-07-26 specs, all eleven plan files, and the retrospective.

- [ ] **Step 2: Rename, preserving history**

```bash
git mv docs/superpowers docs/allye
```

- [ ] **Step 3: Update every reference**

```bash
grep -rl 'docs/superpowers' . --exclude-dir=.git --exclude-dir=node_modules \
  | xargs sed -i 's|docs/superpowers|docs/allye|g'
```

- [ ] **Step 4: Verify nothing was missed and nothing else changed**

```bash
grep -rn 'docs/superpowers' . --exclude-dir=.git --exclude-dir=node_modules || echo "no stale references"
ls docs/
grep -rc 'adapted from' skills/ agents/ | grep -v ':0'
```
Expected: no stale references; `docs/` contains `allye`; and the `adapted from` attribution comments are **still present and unchanged** — this task renames a directory and touches no credit.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: rename docs/superpowers to docs/allye

These are the plugin's own development artifacts, and the directory name
was the last place an external suite appeared in this repository's
vocabulary. The plugin never had a runtime dependency on it.

Attribution comments in the skills are untouched and stay: MIT and
Apache-2.0 require retaining attribution in derivative work, and
self-sufficiency means never needing another suite installed, which was
already true."
```

---

### Task 6: Close the retrospective with an application gate

F12 recorded five fixes targeting Plan 04 and none had been applied — caught only by re-reading the plan for an unrelated reason. This task exists so the same document cannot fail the same way again.

**Files:**
- Modify: `docs/allye/notes/2026-07-26-execution-retrospective.md` (note the post-Task-5 path)

- [ ] **Step 1: Verify every fix targeting a plan actually landed**

```bash
grep -n 'Fix (Plan' docs/allye/notes/2026-07-26-execution-retrospective.md
```

For each result, open the named plan and confirm the change is present. Record the outcome per finding — **applied** or **not applied, and why**. A finding whose plan already executed and which was never applied is not closed; it becomes an item below.

- [ ] **Step 2: Add the standing gate**

Append to the retrospective:

```markdown
---

## The application gate

This document records fixes. Recording is not applying, and the two feel identical while
writing — F12 exists because five fixes sat here fully specified and entirely undone.

**Before dispatching any plan:**

```bash
grep -n 'Fix (Plan N' docs/allye/notes/*-retrospective.md
```

Every result naming that plan is confirmed landed, or the plan is not ready.

**Before closing any retrospective:** every `Fix (...)` is either applied, or restated as an
open item with a named owner and destination. A finding with no destination is an
observation, and observations belong under Process, not under a numbered finding.
```

- [ ] **Step 3: Add the new-skill completeness checklist**

F13 found a skill that existed as a file but could not be resolved by name. Append:

```markdown
## A new skill is not done when its file exists

It is done when everything that names it can resolve it:

- [ ] `skills/<name>/SKILL.md` exists with all four frontmatter keys
- [ ] Added to `seed/seed-skills.json`, with `supported_agents` reflecting where it is
      actually reachable — not every skill is reachable on every platform
- [ ] Referenced from whatever loads it, by the exact name the seed uses
- [ ] Counts updated in `README.md` and `CLAUDE.md`
- [ ] If it is deliberately **not** seeded, that is stated where the count is, the way
      `setup` is

Two of these five were missed for `verification-loop` and `agent-runtime`, and the failure
mode was not a wrong number — it was a skill referenced by name that a user's database could
not resolve at the moment it was needed.
```

- [ ] **Step 4: Mark the document closed**

Change the status line at the top:

```markdown
**Status:** closed 2026-07-26 — thirteen findings, all applied or carried into Plan 05.
**Scope:** what actually broke, surprised, or worked better than expected while building and running the five plans from `2026-07-26-agent-runtime-and-verification-design.md`.
```

- [ ] **Step 5: Verify**

```bash
grep -n 'Status:' docs/allye/notes/2026-07-26-execution-retrospective.md
grep -n 'The application gate' docs/allye/notes/2026-07-26-execution-retrospective.md
grep -n 'A new skill is not done' docs/allye/notes/2026-07-26-execution-retrospective.md
grep -c '^## F' docs/allye/notes/2026-07-26-execution-retrospective.md
```
Expected: status reads closed; both appended sections present; thirteen findings.

- [ ] **Step 6: Commit**

```bash
git add docs/allye/notes/
git commit -m "docs: close the execution retrospective with an application gate

Thirteen findings, each applied or carried into Plan 05. Adds the gate
F12 exists for — before dispatching a plan, confirm every fix naming it
has landed — and the completeness checklist F13 produced, since a skill
whose file exists but which nothing can resolve is not a wrong count but
a broken reference."
```

---

## What this plan deliberately does not do

- **No `implementation-planning` skill.** The plan step lives inside `execution`, where the work happens. A separate skill would create a second place the same truth lives, and a plan artifact that drifts from its work items is worse than no plan artifact — the duplication failure mode the doctrine this suite adopted names by hand.
- **No removal of any attribution comment.** See the constraint above. This is worth stating twice because it is the one instruction in this plan that could be "helpfully" over-applied.
- **No retrofitting of existing tasks or stories.** Work items already in Allye without an `Interfaces` block stay as they are. The gates apply to newly planned work; back-filling is a data migration, not a plugin change.
- **No sixth plan.** The three briefing behaviours in Task 4 were the last thing living only in hand-written prose. After this, what the executors do comes from the templates.
