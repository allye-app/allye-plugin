# Verification Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "done" provable instead of asserted — a bounded loop that runs a task's verification command until it goes green, a story-level loop that proves the whole story works before anything is reported, and a planning gate that refuses a task with no way to verify it.

**Architecture:** One new skill holds the discipline; three existing files consume it. `technical-planning` produces the verification command, `execution` and `agents/executor.md` run it. The loop sits strictly *below* the Orchestrator's correction loop — it catches the trivial so a correction round is spent only on what needs judgement.

**Tech Stack:** Markdown skills. No build step, no test framework — verification is grep assertion.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract** verified against `allye-mcp` source. Never rename one.
- **Skill files stay in English.**
- **Frontmatter keys are `name`, `description`, `version`, `category`.** Bump `version` minor on any skill changed.
- **Adapted content carries an inline credit comment.**
- **Do not push. Do not merge to `main`.**
- **Apply the authoring doctrine to every file you rewrite here** — the no-op test sentence by sentence, collapse duplication, checkable completion criteria. These three files are exempt from the earlier doctrine pass precisely because this plan rewrites them.

## Prerequisite

**Plan 01 must be complete and merged into this plan's base branch.** Plan 01 removes `work_item_id` and `sprint_id` from the `memory_save` blocks in `technical-planning` and `execution` and adds an explicit `sector`. The snippets in this plan show the **post-Plan-01** state of those files. Verify before starting:

```bash
grep -rn 'work_item_id' skills/
```
Expected: no output. If this returns results, Plan 01 has not landed — stop.

---

### Task 1: Create the `verification-loop` skill

**Files:**
- Create: `skills/verification-loop/SKILL.md`

**Interfaces:**
- Consumes: nothing
- Produces: a skill reachable by name from `execution` and `agents/executor.md`. The four criteria (`red-capable`, `deterministic`, `fast`, `agent-runnable`) and the two stop conditions (three attempts on one failure; two byte-identical outputs) are referenced by name in Tasks 3 and 4 — do not reword them there.

- [ ] **Step 1: Write the skill**

Create `skills/verification-loop/SKILL.md`:

```markdown
---
name: verification-loop
description: Bounded test-fix-test loop that proves a task or story actually works. Use when implementing a task, before reporting anything as done, or when a verification command fails and needs another pass.
version: "1.0"
category: methodology
---

# Verification Loop

<!-- adapted from mattpocock/skills diagnosing-bugs (MIT) — the tight-loop completion criterion and the loop-construction ladder -->

A task passes its own tests and still does not do what the story asked. Tasks all go green and the feature is broken. Both happen because "done" is asserted from reading code rather than observed from running it.

This skill defines the loop that observes it. A loop goes **red** on the failure, or it does not — and if it cannot go red, it is not verification, whatever else it is.

## 1. What counts as a loop

A verification command must satisfy all four:

- [ ] **red-capable** — it catches *this specific failure*. "Runs without erroring" is not the same thing. A command that passes whether or not the acceptance criterion is met verifies nothing.
- [ ] **deterministic** — same verdict every run. A command that depends on wall-clock time, network, or unseeded randomness reports noise.
- [ ] **fast** — seconds. A four-minute command is a build; you will not iterate on it, so it will not function as a loop.
- [ ] **agent-runnable** — runs to a verdict with no human clicking. If a human must act, see §4.

## 2. Building one

Take the first option on this ladder that works. Reach further down only when the ones above genuinely do not apply.

1. **An existing test, narrowed** — a single test case naming the criterion. Cheapest and usually correct.
2. **A new test at an existing seam** — prefer a seam the codebase already tests at over introducing one.
3. **A CLI invocation with an observable exit code** — a build, a typecheck, a lint, a migration.
4. **An HTTP call with an asserted response** — `curl` piped through `jq` to an assertion.
5. **A script that exercises the flow and prints a verdict** — when several of the above must combine.
6. **A human-verified procedure** — the escape hatch. See §4; it is not a loop, and declaring it changes how the story is dispatched.

## 3. Running one

The cycle is: run → read the actual output → fix → run again.

**Read the output, do not infer it.** A command whose result you predicted rather than read has told you nothing. This is the same evidence-before-assertions rule the `execution` skill applies before advancing a task, applied per iteration.

### The bound

<HARD-GATE>
Stop on whichever of these comes first:

1. **Three attempts on the same failure.**
2. **Two byte-identical outputs in a row.** Identical output is the previous attempt repeated, not a new one — this ends the loop immediately, before the third attempt.

On stopping, report `❌ blocked` carrying the command, its literal output, and what is missing. Never a summary of the output — the exact text. The reader decides what it means.
</HARD-GATE>

Three attempts is the budget for *one* failure, not for the task. A loop that fixes one criterion and then goes red on a different one starts a fresh budget: that is progress, and progress earns another three.

## 4. When no loop exists

Some work admits no command that is red-capable, deterministic, fast, and agent-runnable at once — visual layout, infrastructure provisioning, a one-off migration against production data. Forcing one produces a command that passes unconditionally, which is worse than none: it reports green while verifying nothing.

Such a task declares, in its description:

```
## Verification
verification: manual
{the exact procedure a human follows, and what they should observe}
```

That declaration carries a consequence beyond the task:

<HARD-GATE>
A task declaring `verification: manual` makes its whole story **HITL** — human in the loop. The Orchestrator does not dispatch a HITL story to an unattended runtime pane. A story whose every task has an automatable command is **AFK** and may be dispatched unattended.

The label is derived here, at planning time. It is never the Orchestrator's guess.
</HARD-GATE>

## 5. Two granularities

**Per task**, during implementation: run that task's command after each change until it is green. Cheap and local — this is what stops a trivial failure from consuming one of the two correction rounds the Orchestrator allows.

**Per story**, before reporting anything: run the command that exercises the story's own acceptance criteria end to end. Every task green does not mean the story works; nothing else checks this.

A red story loop is reported as such even when every task is green. "All tasks passed but the story does not work" is a finding, and a valuable one — it usually means the task breakdown missed an integration.

## 6. Relationship to TDD

Distinct disciplines, easily confused into one:

| | TDD | Verification loop |
|---|---|---|
| When | During implementation | After, before reporting |
| Unit | One behaviour | One acceptance criterion |
| Shape | Red → Green → Refactor | Run → read → fix → run |

Where TDD applies, the loop confirms the assembled whole. Where it does not — the "test after, but always test" branch of the detection heuristic in `tdd-workflow` — the loop is the only mechanism that observes the criterion at all, and that is where it earns the most.
```

- [ ] **Step 2: Verify the frontmatter and the named constants**

```bash
sed -n '1,7p' skills/verification-loop/SKILL.md
grep -c 'red-capable\|deterministic\|agent-runnable' skills/verification-loop/SKILL.md
```
Expected: all four frontmatter keys present; the criteria appear in the file. Tasks 3 and 4 reference these names literally.

- [ ] **Step 3: Commit**

```bash
git add skills/verification-loop/
git commit -m "feat(skills): add the verification-loop skill

A bounded run-read-fix-run loop with four criteria for what counts as a
verification command, a ladder for building one, and an escape hatch for
work that admits none. The escape hatch derives the story's HITL/AFK
label rather than leaving it to the Orchestrator to guess."
```

---

### Task 2: Gate task creation on a verification command

**Files:**
- Modify: `skills/technical-planning/SKILL.md`

**Interfaces:**
- Consumes: `skills/verification-loop/SKILL.md` from Task 1, referenced by name.
- Produces: every task description carries either a `## Verification` block with a runnable command, or `verification: manual` with a procedure. Tasks 3 and 4 read that block.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -n 'How to Verify' skills/technical-planning/SKILL.md
grep -c 'verification-loop' skills/technical-planning/SKILL.md
```
Expected: the `## How to Verify` line exists in the task template (prose, no command required), and `verification-loop` appears **zero** times. That is the gap.

- [ ] **Step 2: Replace the template's verification section**

In `skills/technical-planning/SKILL.md`, section 4.3 "Task Description Template", replace this line:

```markdown
## How to Verify
{How to confirm this task is done — e.g., run tests, check endpoint, verify UI}
```

with:

```markdown
## Verification
{The exact command, runnable as written. It must be red-capable, deterministic,
fast, and agent-runnable — see the `verification-loop` skill §1.}

{or, when no such command exists:}
verification: manual
{the exact procedure a human follows, and what they should observe}
```

- [ ] **Step 3: Add the gate**

Immediately after the existing "Deep Work Rule" HARD-GATE in section 4.2, add:

```markdown
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
```

- [ ] **Step 4: Add the derived label to the story summary**

In section 3.5 "Confirm All Gray Areas Are Resolved", the confirmation summary already lists decisions. Append one line to what gets confirmed with the user:

```markdown
Also state the story's derived dispatch label: **AFK** if every task got a runnable
verification command, **HITL** if any task declared `verification: manual`. The
Orchestrator reads this rather than guessing, so a wrong label here becomes a story
dispatched to an unattended pane that then sits waiting for a human who is not watching.
```

- [ ] **Step 5: Add the checklist item**

In the "Workflow Checklist" near the end of the file, add after the acceptance-criteria item:

```markdown
- [ ] Every task has a `## Verification` block — a runnable command, or `verification: manual` with a procedure
- [ ] The story's AFK/HITL label is derived and stated
```

- [ ] **Step 6: Apply the authoring doctrine to the whole file**

This file was excluded from the earlier doctrine pass because this plan rewrites it. Apply it now: run the no-op test sentence by sentence and delete whole sentences that fail; collapse any meaning stated in more than one place; confirm each step ends on a criterion an agent can check.

Do not touch: any MCP tool name, action name, or parameter; the Epic/Feature/Story vocabulary; the wave mechanic; the locked-vs-agent-discretion classification.

- [ ] **Step 7: Verify**

```bash
grep -c 'How to Verify' skills/technical-planning/SKILL.md
grep -c 'verification-loop' skills/technical-planning/SKILL.md
grep -c 'verification: manual' skills/technical-planning/SKILL.md
```
Expected: `0` for the old heading; at least `2` for `verification-loop`; at least `2` for `verification: manual`.

- [ ] **Step 8: Bump version and commit**

```bash
git add skills/technical-planning/
git commit -m "feat(technical-planning): require a verification command per task

Replaces the prose 'How to Verify' section with a Verification block that
must hold a runnable command or an explicit verification: manual
declaration, and gates task creation on it. The manual declaration
derives the story's HITL label, so the Orchestrator reads the dispatch
mode rather than guessing it.

Also applies the skill-authoring doctrine to this file, which the earlier
doctrine pass deliberately skipped."
```

---

### Task 3: Run both loops in the `execution` skill

**Files:**
- Modify: `skills/execution/SKILL.md`

**Interfaces:**
- Consumes: the `## Verification` block from Task 2; the four criteria and the bound from Task 1.
- Produces: an `execution-report` whose per-criterion status is backed by observed command output. Task 4 mirrors this for the non-interactive executor.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -c 'verification-loop' skills/execution/SKILL.md
```
Expected: `0`.

- [ ] **Step 2: Add the task loop to Step 5**

In `skills/execution/SKILL.md`, after the "Refactor Phase" subsection and before "Repeat", insert:

```markdown
### Verification Phase — run the task's loop

TDD proved each behaviour as you built it. This proves the **task's acceptance
criteria**, which is a different claim.

Run the command from the task's `## Verification` block. Read its actual output.
If it is red, fix and run it again, under the bound in `verification-loop` §3:
three attempts on one failure, or two byte-identical outputs, whichever comes
first. On hitting the bound, stop and carry the command and its literal output
into your report — do not summarise the output.

If the task declares `verification: manual`, follow its procedure and record what
you observed. You have not run a loop; say so plainly in the report rather than
implying one passed.
```

- [ ] **Step 3: Add the story loop before the report**

Replace Step 9's final bullet. Current text:

```markdown
- If every task in the story has reached `review` (implementation complete, awaiting Reviewer) → emit an **`execution-report`** handover (see the `handover-protocol` skill) back to the Orchestrator
```

with:

```markdown
- If every task in the story has reached `review` (implementation complete, awaiting Reviewer) → **run the story loop, then** emit an **`execution-report`** handover (see the `handover-protocol` skill) back to the Orchestrator.

  The story loop runs the story's own acceptance criteria end to end, under the same
  bound as the task loop. Every task green does not mean the story works — nothing
  else checks this, which is exactly why it runs here.

  A red story loop is reported as red **even when every task is green**. That
  combination is a finding, not a contradiction to resolve: it usually means the task
  breakdown missed an integration, and the Orchestrator needs to see it rather than
  receive a clean report.
```

- [ ] **Step 4: Strengthen Step 7's evidence rule**

Step 7 currently opens with an "Evidence before assertions" paragraph. Append to it:

```markdown
The task's verification command is what supplies that evidence. Advancing a task to
`review` without having run it green — or without having recorded a `verification:
manual` observation — is the assertion this rule exists to forbid.
```

- [ ] **Step 5: Add the checklist items**

In the "Workflow Checklist", replace `- [ ] Tests pass` with:

```markdown
- [ ] Tests pass
- [ ] The task's verification command ran green, or its manual procedure was observed and recorded
- [ ] The story loop ran green before the report was emitted
```

- [ ] **Step 6: Apply the authoring doctrine to the whole file**

Same instruction as Task 2 Step 6. Do not touch tool names, the TDD detection heuristic, the read-first rule, the analysis-paralysis guard's numbers, or the `review`-not-`done` status rule.

- [ ] **Step 7: Verify**

```bash
grep -c 'verification-loop' skills/execution/SKILL.md
grep -c 'story loop' skills/execution/SKILL.md
grep -n 'work_status_done' skills/execution/SKILL.md
```
Expected: at least `2` for `verification-loop`; at least `2` for `story loop`; and `work_status_done` still appears only in its existing prohibition ("Do NOT call `work_status_done` here"), never as an instruction.

- [ ] **Step 8: Bump version and commit**

```bash
git add skills/execution/
git commit -m "feat(execution): run the task and story verification loops

Adds a verification phase after TDD that runs the task's command under a
bound, and a story-level loop before the execution report. A red story
loop is reported even when every task is green — that combination is the
integration gap nothing else catches.

Also applies the skill-authoring doctrine to this file."
```

---

### Task 4: Run both loops in the dispatched executor

`agents/executor.md` is the non-interactive counterpart to `execution`. It cannot ask a question, so its loop bound matters more: hitting it is the only signal a human gets.

**Files:**
- Modify: `agents/executor.md`

**Interfaces:**
- Consumes: Task 1's criteria and bound; Task 3's loop placement.
- Produces: a report whose `❌ blocked` entries carry a command and its literal output.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -c 'verification-loop' agents/executor.md
```
Expected: `0`.

- [ ] **Step 2: Add the loops to the Discipline section**

In `agents/executor.md`, in the "Discipline" list, after the "Evidence before assertions" bullet, add:

```markdown
- **Run the verification loop, both levels.** Per task: run the command from its `## Verification` block, read the actual output, fix and re-run under the bound in `verification-loop` §3 — three attempts on one failure, or two byte-identical outputs, whichever comes first. Per story: run the story's acceptance criteria end to end before returning. A task declaring `verification: manual` gets its procedure followed and observed, and the report says plainly that no loop ran.
```

- [ ] **Step 3: Extend the halt-and-report contract**

The HARD-GATE currently covers underspecified tasks. Add a second paragraph inside it:

```markdown
A verification loop that hits its bound is the same kind of stop. Report that task as
`❌ blocked` carrying the command, its **literal** output, and what you tried — never a
summary. You cannot ask what to do about a failure you could not fix, so the exact text
is what lets the Orchestrator put a real question in front of the human.
```

- [ ] **Step 4: Require evidence in the returned report**

In "What you return", replace the per-criterion evidence phrase `(what you ran, what it showed, or what's missing and why)` with:

```markdown
(the verification command you ran and its actual output, the manual procedure you followed and what you observed, or what is missing and why — never "verified" without the thing that verified it)
```

- [ ] **Step 5: Verify**

```bash
grep -c 'verification-loop' agents/executor.md
grep -c 'literal' agents/executor.md
```
Expected: at least `1` each.

- [ ] **Step 6: Commit**

```bash
git add agents/executor.md
git commit -m "feat(executor): run the verification loops and report literal output

The dispatched executor runs the same task and story loops as the
interactive skill. Hitting the loop bound is a halt-and-report condition,
and the report carries the command's literal output rather than a
summary — it cannot ask, so the exact text is what lets the Orchestrator
form the question."
```

---

## What this plan deliberately does not do

- **No changes to the Orchestrator.** It does not yet read the AFK/HITL label — that is Plan 04, where dispatch mode is resolved. Until then the label is produced and recorded, and nothing consumes it. That is intentional: producing it first means Plan 04 has real data to test against.
- **No changes to the Reviewer.** The two-axis split is Plan 03.
- **No retrofitting of existing tasks.** Tasks already created in Allye without a `## Verification` block stay as they are. The gate applies to newly planned tasks; back-filling would be a data migration, not a plugin change.
