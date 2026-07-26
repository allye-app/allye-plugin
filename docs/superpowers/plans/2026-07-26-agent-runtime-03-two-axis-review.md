# Two-Axis Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split review into two independent axes — does this follow the rules, and is this what was asked for — dispatched in parallel and never merged, so that code which satisfies every convention while implementing the wrong thing stops passing review.

**Architecture:** One reviewer agent becomes two, each with its own brief and its own report. The Orchestrator dispatches both in parallel and records both verbatim; only the go/no-go decision combines them. The split lives at the Orchestrator because a dispatched agent cannot dispatch further.

**Tech Stack:** Markdown skills and agent definitions. No build step, no test framework — verification is grep assertion.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract.** Never rename one.
- **Skill files stay in English.**
- **Frontmatter keys are `name`, `description`, `version`, `category`** for skills; `name`, `description`, and optionally `tools` for agents. Bump `version` minor on any skill changed.
- **Adapted content carries an inline credit comment.**
- **Do not push. Do not merge to `main`.**
- **Apply the authoring doctrine to `skills/review/SKILL.md`** — it was excluded from the earlier pass because this plan rewrites it.

## Prerequisites

**Plans 01 and 02 must be complete and merged into this plan's base branch.** Plan 02 produces the story's AFK/HITL label and the per-criterion verification evidence that the spec-axis reviewer reads.

```bash
grep -rn 'work_item_id' skills/            # expect: no output (Plan 01)
ls skills/verification-loop/SKILL.md       # expect: exists (Plan 02)
```

## What this plan does not change

**How the reviewers are dispatched.** Both are Agent-tool subagents here, exactly as `agents/reviewer.md` is today. Plan 04 changes the *transport* to runtime panes when one is available. Keeping those separate means this plan is testable on its own, and Plan 04 changes one dispatch mechanism rather than inventing two agents at the same time.

---

### Task 1: Create the standards-axis reviewer

**Files:**
- Create: `agents/reviewer-standards.md`

**Interfaces:**
- Consumes: a dispatch prompt carrying team context, the story key, the task keys, and the files-changed list — the same fields `agents/reviewer.md` receives today.
- Produces: findings in `✅ / ⚠️ / ❌` per task. Task 4 reads this shape. Do not change the symbols.

- [x] **Step 1: Write the agent**

Create `agents/reviewer-standards.md`:

```markdown
---
name: reviewer-standards
description: Reviews one story's completed tasks against coding standards, conventions, security, and test quality — the "does this follow the rules" axis. Dispatched in parallel with reviewer-spec, never merged with it.
tools: Bash, Read, Grep, Glob, mcp__allye
---

# Allye Reviewer — Standards Axis

<!-- adapted from mattpocock/skills code-review (MIT) — two-axis separation and the Fowler smell baseline -->

You review **how** the code is written. Whether it implements the right thing is a
different question, reviewed independently by `reviewer-spec` — do not answer it here,
even when the answer seems obvious. Your blindness to that axis is deliberate: it is
what stops one axis from masking the other.

You read and analyse. You never write code, and you never ask the dispatching
conversation anything — you run once, to completion, and return. If something you need
is missing from your dispatch prompt, say so in your report.

## Scope

Your dispatch prompt gives you the team context, the story key, the task keys, and the
files changed. Review exactly those files. If a change you would expect from a task is
absent from that list, that is a finding for `reviewer-spec`, not a reason to go hunting.

## Initialization

1. Call `initialize` (action: `init`).
2. Call `team_switch` if the active team differs from your dispatch prompt's.
3. Call `skill_list` for code standards, security checklists, and quality guidelines, then
   `skill_get(id: ...)` on each relevant one. **A team standard always overrides the
   baseline below.**

## What you check

1. **Team standards** — the skills you loaded. These outrank everything else here.
2. **Consistency** — does it follow the patterns already in this codebase?
3. **Security** — injection, exposed secrets, missing authorization checks.
4. **Error handling** — are failure paths handled, and are the errors informative?
5. **Naming** — do names say what the thing is?
6. **Test quality** — do tests assert behaviour rather than implementation? Do they cover
   edge cases? Would they break for the right reason? A test asserting that a mock returns
   what it was told to return asserts nothing.

### Baseline smells

Apply these only where no team standard covers the ground, and skip anything tooling
already enforces. Each is a labelled heuristic — "possible Feature Envy" — never a
hard violation.

| Smell | What it looks like | Fix |
|---|---|---|
| Long Function | one function doing several jobs | extract the jobs |
| Large Class | one type accumulating unrelated responsibilities | split by responsibility |
| Long Parameter List | many positional arguments | pass one object, or split the function |
| Data Clumps | the same fields travelling together everywhere | a type wanting to be born — bundle them |
| Primitive Obsession | strings and ints standing in for domain concepts | name the concept as a type |
| Duplicated Code | the same logic in more than one place | extract, or remove the accidental copy |
| Feature Envy | a method reaching mostly into another object | move it to the object it envies |
| Shotgun Surgery | one change forcing edits across many files | the responsibility is scattered — gather it |
| Divergent Change | one file changing for unrelated reasons | it holds more than one responsibility |
| Message Chains | `a.b().c().d()` | ask the first object for what you actually want |
| Speculative Generality | abstraction with one caller and no second in sight | inline it until a second arrives |
| Comments | comments explaining what the code does | let the code say it; keep the *why* |

## What you return

Per task, under 400 words total:

- ✅ passed — standards met
- ⚠️ minor — the issue, its severity, the suggested fix
- ❌ failed — the issue, the standard it violates, the required action

Never comment on whether the task did the right thing. If you find yourself writing
"but this does not match the acceptance criterion," stop — that is the other axis.

## Memory

Save your findings with `memory_save`, `sector: "knowledge"`, tags including the story
key and `review-standards`. The Orchestrator reads results from Allye, not from your
terminal, so a report you did not save is a report that did not arrive.
```

- [x] **Step 2: Verify**

```bash
sed -n '1,6p' agents/reviewer-standards.md
grep -c 'Never comment on whether the task did the right thing' agents/reviewer-standards.md
grep -c 'Feature Envy' agents/reviewer-standards.md
```
Expected: frontmatter carries `name`, `description`, `tools`; the boundary sentence present exactly once; the smell table present. These check the two things that make this agent an axis rather than a generic reviewer — its refusal to answer the other axis, and the baseline it applies when a repo documents nothing.

- [x] **Step 3: Commit**

```bash
git add agents/reviewer-standards.md
git commit -m "feat(agents): add the standards-axis reviewer

Reviews how code is written — team standards first, then consistency,
security, error handling, naming, and test quality, with a Fowler smell
baseline for repos that document nothing. Deliberately blind to whether
the code implements the right thing; that is reviewer-spec's axis."
```

---

### Task 2: Create the spec-axis reviewer

**Files:**
- Create: `agents/reviewer-spec.md`

**Interfaces:**
- Consumes: the same dispatch prompt as Task 1, plus the per-criterion verification evidence produced by Plan 02.
- Produces: findings in the same `✅ / ⚠️ / ❌` shape. Task 4 reads both.

- [x] **Step 1: Write the agent**

Create `agents/reviewer-spec.md`:

```markdown
---
name: reviewer-spec
description: Reviews one story's completed tasks against its acceptance criteria and the locked decisions from planning — the "is this what was asked for" axis. Dispatched in parallel with reviewer-standards, never merged with it.
tools: Bash, Read, Grep, Glob, mcp__allye
---

# Allye Reviewer — Spec Axis

<!-- adapted from mattpocock/skills code-review (MIT) — two-axis separation -->

You review **what** the code does, against what was asked for. Whether it is written
well is a different question, reviewed independently by `reviewer-standards` — do not
answer it here. Beautiful code implementing the wrong thing must fail your axis, and
your silence on style is what makes that failure visible.

You read and analyse. You never write code, and you never ask the dispatching
conversation anything.

## Scope

Your dispatch prompt gives you the team context, the story key, the task keys, and the
files changed.

## Initialization

1. Call `initialize` (action: `init`).
2. Call `team_switch` if the active team differs from your dispatch prompt's.
3. `work_get` the story and each task. **Read the acceptance criteria as written** — they
   are the specification you are reviewing against, not a summary of it.
4. Search memories for the decisions the implementation had to respect:
   `memory_search("decision {story key}")`, `memory_search("Technical Plan {story key}")`.

## What you check

1. **Every acceptance criterion, one at a time.** Met, or not met and why. A criterion
   nobody mentioned is a criterion silently skipped — those are the ones worth finding.
2. **The verification evidence.** Each criterion should carry the command that was run
   and its actual output, or an observed manual procedure. A criterion reported met with
   no evidence behind it is unverified, and you report it as such — not as met.
3. **Locked decisions.** A locked decision was explicitly chosen by the human. **Any
   deviation is a defect**, however reasonable the deviation looks. If the implementation
   suggests the decision itself was wrong, that is a finding to surface, never a licence
   to have quietly departed from it.
4. **Agent-discretion decisions.** Reasonable, and is the rationale recorded?
5. **Scope.** Did anything get built that no criterion asked for? Unrequested work is a
   finding — it was not reviewed by anyone, because nobody planned it.

## What you return

Per task, under 400 words total, criterion by criterion:

- ✅ passed — every criterion met with evidence
- ⚠️ minor — met, but with a caveat worth recording
- ❌ failed — the criterion, why it is not met, the required action

Never comment on code style, naming, or structure. If you find yourself writing "this
would be cleaner as," stop — that is the other axis.

## Memory

Save your findings with `memory_save`, `sector: "knowledge"`, tags including the story
key and `review-spec`. The Orchestrator reads results from Allye, not from your terminal.
```

- [x] **Step 2: Verify**

```bash
sed -n '1,6p' agents/reviewer-spec.md
grep -c 'Never comment on code style' agents/reviewer-spec.md
grep -c 'Any deviation is a defect' agents/reviewer-spec.md
```
Expected: frontmatter complete; the boundary sentence present exactly once; the locked-decision rule present. Again the assertion checks the sentences that define the axis, not how often the sibling is named.

- [x] **Step 3: Commit**

```bash
git add agents/reviewer-spec.md
git commit -m "feat(agents): add the spec-axis reviewer

Reviews acceptance criteria one at a time against the verification
evidence, plus locked-decision compliance and unrequested scope.
Deliberately silent on style — that silence is what makes 'well-written
but wrong' visible instead of averaged away."
```

---

### Task 3: Retire the single reviewer and rewrite the review skill

**Files:**
- Delete: `agents/reviewer.md`
- Modify: `skills/review/SKILL.md`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: a `review` skill describing both axes, for the interactive case where a human runs review by hand.

- [ ] **Step 1: Find every reference to the old agent**

The obvious pattern misses half of them: `README.md` and `handover-protocol` write "Reviewer" capitalized and without backticks. Search case-insensitively, and scope to living files:

```bash
grep -rn -i 'reviewer' skills/ agents/ CLAUDE.md README.md packages/allye-opencode/src/ manifests/ 2>/dev/null
```

Expected: hits in `skills/orchestrator/SKILL.md`, `skills/review/SKILL.md`, `skills/handover-protocol/SKILL.md`, `agents/reviewer.md`, `CLAUDE.md`, and `README.md` (lines 29, 63, 199, 218, 233, 238, 256 — six prose mentions plus a table row). Record them; every one is updated in this task or Task 4.

<HARD-GATE>
**Do not search or edit under `docs/`.** `docs/superpowers/specs/2026-07-12-*` and `docs/superpowers/plans/2026-07-12-*` mention the single reviewer because that is what was decided and shipped in July. They are the record of a decision, not a description of the current tree. Rewriting a delivered spec so it matches later reality destroys the only account of why the thing was built the way it was.

The current spec (`2026-07-26-*`) already describes the split — it is the document that decided it.
</HARD-GATE>

- [ ] **Step 2: Delete the old agent**

```bash
git rm agents/reviewer.md
```

- [ ] **Step 3: Rewrite the review skill's checks into two axes**

In `skills/review/SKILL.md`, replace section 2's single flat list of checks. Section 2.2 "Code Quality" and 2.3 "Decision Compliance" and 2.4 "Test Quality" become two clearly separated subsections:

```markdown
## Step 2: Review Each Task — Two Axes

<!-- adapted from mattpocock/skills code-review (MIT) -->

Review runs as two independent passes. Keep them separate on the page and separate in
your head, and **do not reconcile them**: a change can pass one and fail the other, and
reporting them together is what lets one hide the other.

> Code that follows every standard but implements the wrong thing → **Standards pass,
> Spec fail.**
> Code that does exactly what was asked but breaks the project's conventions → **Spec
> pass, Standards fail.**

### Axis 1 — Standards: how it is written

Load team standards first (`skill_list` → `skill_get`); they override everything below.
Then: consistency with existing patterns, security, error handling, naming, and test
quality — do the tests assert behaviour rather than implementation, cover edge cases,
and break for the right reasons?

Full checklist and the baseline smells: `agents/reviewer-standards.md`.

### Axis 2 — Spec: whether it is what was asked for

Every acceptance criterion, one at a time, against the verification evidence the
execution report carried. A criterion reported met with no command output or observed
procedure behind it is **unverified**, and gets reported as unverified rather than met.
Then locked-decision compliance — any deviation is a defect — and unrequested scope.

Full checklist: `agents/reviewer-spec.md`.

### Reporting

Two reports, never merged, never reranked. The decision that combines them belongs to
the Orchestrator — see `orchestrator` §6.
```

- [ ] **Step 4: Apply the authoring doctrine to the whole file**

Run the no-op test sentence by sentence and delete whole sentences that fail; collapse duplicated meaning; confirm every step ends on a checkable criterion. Do not touch tool names, the `work_statuses()` / `work_update` backward-move mechanic, or the ✅/⚠️/❌ symbols.

- [ ] **Step 5: Update the stale references**

In `CLAUDE.md` and `README.md`, replace every mention of four subagents with five, and every mention of `reviewer` with the two axis agents. Specifically, `CLAUDE.md`'s runtime-flow section 3 lists the shipped subagents; `README.md`'s "What you get" and "Agents" sections both give counts.

- [ ] **Step 6: Verify**

```bash
test ! -f agents/reviewer.md && echo "old agent removed"
ls agents/
grep -rn 'agents/reviewer\.md' . --exclude-dir=.git --exclude-dir=node_modules || echo "no stale path references"
grep -c 'Axis 1\|Axis 2' skills/review/SKILL.md
```
Expected: `agents/` lists `code-analyzer.md`, `deep-search.md`, `executor.md`, `reviewer-spec.md`, `reviewer-standards.md`; no stale path references; both axes present in the skill.

- [ ] **Step 7: Bump version and commit**

```bash
git add -A skills/review/ agents/ CLAUDE.md README.md
git commit -m "refactor(review): split review into standards and spec axes

Retires the single reviewer agent for two that are each deliberately
blind to the other's concern. The skill documents both passes and states
that they are never reconciled — reconciling them is how 'well-written
but wrong' gets averaged into a pass.

Also applies the skill-authoring doctrine to the review skill."
```

---

### Task 4: Teach the Orchestrator to dispatch both and combine the verdicts

**Files:**
- Modify: `skills/orchestrator/SKILL.md`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: the combination rule. Plan 04 modifies this same file for dispatch-mode resolution and must preserve this section.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -c 'reviewer-standards\|reviewer-spec' skills/orchestrator/SKILL.md
```
Expected: `0`.

- [ ] **Step 2: Replace section 5's dispatch instruction**

<HARD-GATE>
**Preserve every `<!-- opencode-exclude:start -->` / `<!-- opencode-exclude:end -->` marker.** `skills/orchestrator/SKILL.md` carries twelve of them and `skills/handover-protocol/SKILL.md` three. They fence off Claude-Code-only text so it is stripped from the prompt generated for OpenCode, which has no `Agent` tool and no automatic-Executor mode.

The text you are replacing contains them. Dropping a marker does not raise an error — it silently leaks Claude-specific instructions into another platform's prompt, which is the exact defect commit `394dc20` was written to fix.

Before editing, read the surrounding lines and note which spans are fenced. After editing, run `grep -c 'opencode-exclude' skills/orchestrator/SKILL.md` and confirm the count has not dropped. If your replacement genuinely removes the Claude-only phrasing a marker was fencing, the marker can go with it — but that is a decision to state in your report, never a side effect.
</HARD-GATE>

In `skills/orchestrator/SKILL.md` §5, the sentence currently dispatching `reviewer` becomes:

```markdown
Once the report is genuinely complete, dispatch **both** `reviewer-standards` and
`reviewer-spec` — in parallel, in the same turn, automatically, without asking the user
first. Review never needs to pause and ask anyone anything, which is what makes it always
dispatch-appropriate.

Pass each the same fields: the active team (id and name), the story key, the task keys,
and the files changed from the execution report. `reviewer-spec` additionally gets the
per-criterion verification evidence the report carried — it reviews against that evidence,
so a report that omits it produces a review that cannot confirm anything.
```

- [ ] **Step 3: Replace section 6 with the combination rule**

Section 6 currently reacts to one reviewer's output. Replace its opening with:

```markdown
## 6. React to review

Two reports arrive, one per axis. **Record both verbatim.** Never merge them, never
rerank findings across them, never resolve a disagreement between them — each axis
reviewed something the other deliberately ignored, so a disagreement is not a conflict
to settle.

The *findings* stay separate. The *decision* is single, and combines them:

| Standards | Spec | Outcome |
|---|---|---|
| ✅ | ✅ | Move each approved task the rest of the way to `done`, then cascade (§7) |
| ⚠️ only | ✅ | Cascade as above; record the warnings as a note so they are not lost |
| ✅ | ⚠️ only | Cascade as above; record the warnings as a note |
| ❌ | any | Correction round |
| any | ❌ | Correction round |

A ❌ on either axis triggers a correction round on its own. **One axis passing never
offsets the other failing** — that offsetting is exactly the masking the split exists to
prevent.

The correction handover carries only the failing axis's ❌ findings, quoted literally.
The existing two-correction maximum counts rounds **per task**, regardless of which axis
produced them: a task corrected once for standards and once for spec has used both
rounds, and a third failure escalates to the human.
```

- [ ] **Step 4: Verify**

```bash
grep -c 'reviewer-standards' skills/orchestrator/SKILL.md
grep -c 'reviewer-spec' skills/orchestrator/SKILL.md
grep -n 'never offsets' skills/orchestrator/SKILL.md
grep -n 'regardless of which axis' skills/orchestrator/SKILL.md
grep -rn -i 'the `reviewer` subagent\|dispatch the reviewer\b' skills/orchestrator/SKILL.md
grep -c 'opencode-exclude' skills/orchestrator/SKILL.md
```

Expected, in order: both agent names present; the offsetting rule found; the per-task counting rule found; **no output** from the old-agent search; and the `opencode-exclude` count **unchanged from before your edit** (it was 12 at the time this plan was written — record what you actually measured first).

Note what these assert and what they do not. They check the distinctive sentences each edit introduces, not a count of how often an agent name appears — a name count would pass just as happily if you mentioned `reviewer-spec` twice in a comment and never wired it up.

- [ ] **Step 5: Update the handover protocol's note**

`skills/handover-protocol/SKILL.md` §2 states "Reviewer never receives a handover." Update the name to plural — both axis agents are dispatched with a constructed prompt, neither receives a handover.

- [ ] **Step 6: Bump version and commit**

```bash
git add skills/orchestrator/ skills/handover-protocol/
git commit -m "feat(orchestrator): dispatch both review axes and combine verdicts

Dispatches reviewer-standards and reviewer-spec in parallel and records
both reports verbatim. Findings are never merged or reranked; only the
go/no-go combines them, and a failure on either axis triggers a
correction round alone. The two-correction maximum counts per task
regardless of which axis produced the rounds."
```

---

## What this plan deliberately does not do

- **No dispatch-transport change.** Both reviewers are Agent-tool subagents here. Plan 04 switches them to runtime panes where one is available, which changes how they are launched and not what they are.
- **No doctrine pass on `orchestrator` or `handover-protocol`.** Both are rewritten more substantially in Plan 04; the doctrine is applied there, in the same edit.
- **No third axis.** Performance, accessibility, and dependency auditing are all defensible axes and none of them is in scope. Two axes that stay genuinely independent beat four that blur.
