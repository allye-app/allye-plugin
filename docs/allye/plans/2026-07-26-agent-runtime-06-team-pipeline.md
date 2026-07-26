# Team Pipeline Awareness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop assuming a status pipeline. Teach the Orchestrator to discover the team's actual one, drive every gate that is verification, and stop — naming it — at the first gate that changes the world outside the repository.

**Architecture:** No status name is hard-coded anywhere. `board-progression` stops documenting a convention and starts teaching discovery. The Orchestrator advances one status at a time, reading the result rather than predicting it, and consults a pipeline table in the delivery configuration for anything it does not recognize. Two existing mechanisms do the work at two of the gates: the story verification loop satisfies QA, and a security command — same four criteria — satisfies the security scan.

**Tech Stack:** Markdown skills. No build step, no test framework — verification is grep assertion.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract.** Never rename one.
- **Attribution comments stay.** Twenty-two exist across `skills/` and `agents/`; this plan removes none.
- **Preserve every `opencode-exclude` marker.** `skills/orchestrator/SKILL.md` carries sixteen, `skills/handover-protocol/SKILL.md` three. Count before and after any edit to either.
- **Skill files stay in English.** Bump `version` minor on any skill changed.
- **Do not push. Do not merge to `main`.**

<HARD-GATE>
**No status key may be hard-coded as a rule.** Allye is multi-tenant; every team configures its own statuses, and a rule naming one is wrong for the next team.

Status keys may appear only in three places: as **examples**, clearly labelled as the seeded preset's names; in the **delivery configuration table**, which is per-team data; and in the **four category values** `proposed` / `in_progress` / `done` / `cancelled`, which are a schema enum and therefore stable.

If you find yourself writing "when the status is `code_review`", stop — that is the mistake this whole plan exists to remove.
</HARD-GATE>

## Prerequisites

Plans 01–05 complete and merged.

```bash
ls skills/verification-loop/SKILL.md skills/agent-runtime/SKILL.md
ls agents/reviewer-standards.md agents/reviewer-spec.md
grep -c 'Allye Delivery Configuration' skills/setup/SKILL.md    # at least 1
grep -c '## Step 4.5' skills/execution/SKILL.md                 # exactly 1
ls docs/allye/                                                   # renamed by Plan 05
```

## Background the executor needs

`allye-api/prisma/seed-workflow.ts:30-51` ships four cumulative presets — **Solo** (5 statuses), **Startup** (9), **Standard** (14), **Enterprise** (18). Teams pick one and then customise. The full seeded set is:

`idea, researching, designing, specifying` (pipeline `product`) · `backlog, todo, in_progress, code_review, security_scan, qa_testing, doc_review, deploy_staging, qa_staging, deploy_preprod, qa_preprod, deploy_prod` (pipeline `engineering`) · `done, cancelled` (pipeline `shared`).

Treat that list as **the seeded example, not the universe.** Read spec §17 before starting.

---

### Task 1: Rewrite `board-progression` from convention to discovery

**Files:**
- Modify: `skills/board-progression/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the discovery procedure and the authority rule, both referenced by name from Task 3.

- [x] **Step 1: Establish the failing assertion**

```bash
grep -n 'testing.*review\|Status name (convention)' skills/board-progression/SKILL.md
grep -c 'discover' skills/board-progression/SKILL.md
```
Expected: the convention table found — it currently orders `testing` before `review`, which matches no preset — and `discover` appearing zero times.

- [x] **Step 2: Replace the convention table with a discovery procedure**

In `skills/board-progression/SKILL.md` §1, the table headed "Status name (convention)" and the paragraph introducing it are replaced by:

```markdown
### The team's pipeline is data. Read it.

Allye is multi-tenant. Four presets ship — Solo, Startup, Standard, Enterprise — and every
team customises from there, so **there is no status list to memorise and no ordering to
assume.** A skill that names a status has guessed about somebody else's board.

Only three things are stable enough to build a rule on:

| Stable | Why |
|---|---|
| The four categories: `proposed`, `in_progress`, `done`, `cancelled` | A schema enum. Every status maps to exactly one. |
| The three pipelines: `product`, `engineering`, `shared` | A schema enum. `product` carries epics and features; `engineering` carries stories and below; `shared` holds the terminal states. |
| The board's own ordering | Whatever it is, it is what `work_status_next` walks. |

Discover the rest:

```
work_statuses()    → every status the team has, grouped by category, in position order
board_columns()    → the columns of a specific board
```

**Two things `work_statuses()` does not tell you today**, and planning around them is the
difference between a working transition and a surprised one:

- **`position`, `pipeline`, and `description` are not returned.** They exist on the record —
  the seed writes all three — but the MCP formatter emits only name, key, id, and colour.
- **`board_columns()` returns names and ids only** — no status-to-column mapping and no
  ordering. The visible subset a given board shows cannot be reconstructed from it.

Together these mean **you cannot reliably predict the next status.** So do not:

<HARD-GATE>
Move one status at a time, then **read back** the status you actually landed on. Never
assume a transition took you where you expected, and never chain several moves on a
prediction. One extra read per transition costs nothing next to a cascade that silently
skipped four gates.
</HARD-GATE>

For reference only, these are the eighteen statuses the presets seed — **an example of one
tenant's configuration, not a list to code against**: `idea`, `researching`, `designing`,
`specifying`, `backlog`, `todo`, `in_progress`, `code_review`, `security_scan`, `qa_testing`,
`doc_review`, `deploy_staging`, `qa_staging`, `deploy_preprod`, `qa_preprod`, `deploy_prod`,
`done`, `cancelled`.
```

- [x] **Step 3: Add the authority rule**

Add a new section after §3 ("How `work_status_done` Works"):

```markdown
## 3.1 Where an agent's authority ends

> **An agent drives everything that is verification. It stops at the first gate that changes
> the world outside the repository.**

Deploying does that. Verifying does not. The rule survives renaming because it describes what
a gate *is*, not what it is called — which is the only kind of rule that works when every
team configures its own statuses.

In practice, on the seeded presets: reviewing, scanning, testing, and updating docs are all
verification and all satisfiable by an agent. Every deploy stage, and any validation
performed in a deployed environment, is not.

<HARD-GATE>
`work_status_done` is **not** the exit from a pipeline an agent cannot finish. Calling it
from four statuses away records "done" for work that never passed the gates in between.

Use it only when the item's next status **is** the done status. Otherwise stop at the last
gate you satisfied and say plainly which gate is next and who owns it.
</HARD-GATE>

An unrecognised status is treated as a stop, not a pass. Ask once who satisfies it, record
the answer in the team's delivery configuration, and never ask again.
```

- [x] **Step 4: Fix the per-type progression section**

§5 gives progressions per item type using invented status names. Replace its four blocks with:

```markdown
Progression differs by pipeline, not only by type. **Epics and features live on the `product`
pipeline; stories, bugs, hotfixes, tasks, spikes, and subtasks live on `engineering`.** A
cascade from task to epic therefore crosses pipelines, and the statuses available on each side
are different sets.

What holds regardless of the team's configuration:

- **Parents move because children moved.** A story advances when its tasks do; a feature when
  its stories do; an epic when its features do. Never the other way round.
- **A parent never reaches the done category while any child is outside it.** This is the one
  rule that failed in practice: a story closed with seven of fifteen tasks still mid-pipeline,
  because closing it was the only exit the flow offered. Stopping is the exit.
- **The Executor advances a task only to the first review gate.** The move past that is the
  Orchestrator's, after review clears — see `orchestrator` §6.
```

- [x] **Step 5: Apply the authoring doctrine and bump the version**

Run the no-op test sentence by sentence; collapse duplicated meaning. Preserve the four category names, the `work_status_next` resolution logic, and the `work_status_done` mechanics — those are behaviour of the real API.

- [x] **Step 6: Verify**

```bash
grep -c 'Status name (convention)' skills/board-progression/SKILL.md
grep -n 'The team.s pipeline is data' skills/board-progression/SKILL.md
grep -n 'Where an agent.s authority ends' skills/board-progression/SKILL.md
grep -n 'read back' skills/board-progression/SKILL.md
grep -n 'an example of one' skills/board-progression/SKILL.md
grep -c 'proposed' skills/board-progression/SKILL.md
```
Expected: the old convention table gone; all four new passages present; the four categories still documented. The seeded status names may appear **only** in the labelled example paragraph — check that by eye, since a grep cannot tell an example from a rule.

- [x] **Step 7: Commit**

```bash
git add skills/board-progression/
git commit -m "refactor(board-progression): teach discovery, not a convention

The skill documented a fixed eight-status convention that matches none of
the four shipped presets, ordering testing before review — inverted
relative to all of them. It now teaches how to discover the team's actual
pipeline and states where an agent's authority ends: it drives what is
verification and stops at the first gate that changes the world outside
the repository.

Records that work_statuses omits position, pipeline and description and
that board_columns exposes no status mapping, so the next status cannot be
predicted — move one step and read back what you landed on."
```

---

### Task 2: Add the pipeline table to the delivery configuration

**Files:**
- Modify: `skills/setup/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a `## Pipeline handoff` section in the `Allye Delivery Configuration` Core Document. Task 3 reads it.

- [x] **Step 1: Establish the failing assertion**

```bash
grep -c 'Pipeline handoff' skills/setup/SKILL.md
```
Expected: `0`.

- [x] **Step 2: Add the fourth setup question**

In the delivery-configuration section, after the third question:

```markdown
**Question 4 — who satisfies each stage after review?** Only ask this when the team's pipeline
has stages between the review gate and done: run `work_statuses()` and look. A Solo or Startup
board goes straight from review to done and needs nothing here — **skip the question entirely
rather than asking it and recording an empty table.**

Where there are stages, offer three answers per stage:

- **`agent`** — the Orchestrator satisfies it and advances. Needs a command, the same way a task
  needs one (`verification-loop` §1): red-capable, deterministic, fast, agent-runnable.
- **`ci`** — an external system satisfies it. Record how to read the result; the Orchestrator
  waits rather than acting.
- **`human`** — the Orchestrator stops and hands over.

Lead with a recommendation so accepting takes one word: scans and automated test suites are
usually `agent` or `ci`; anything that deploys, or that validates in a deployed environment, is
`human` unless the team says otherwise.
```

- [x] **Step 3: Extend the document format**

Add to the document template in the same section:

```markdown
## Pipeline handoff

| Status | Satisfied by | Command or signal |
|---|---|---|
| security_scan | agent | just security-scan |
| qa_testing | agent | just test:e2e |
| deploy_staging | ci | GitHub Actions `deploy-staging` |
| deploy_prod | human | |

An unmapped status means **`human`**. Stopping is the safe default: an agent that advances
past a gate nobody told it about has claimed work passed a check that never ran.

Omit this section entirely when the pipeline runs straight from review to done.
```

- [x] **Step 4: Verify**

```bash
grep -c 'Pipeline handoff' skills/setup/SKILL.md
grep -n 'skip the question entirely' skills/setup/SKILL.md
grep -n 'An unmapped status means' skills/setup/SKILL.md
grep -c 'Allye Delivery Configuration' skills/setup/SKILL.md
```
Expected: the section present in both the question and the template; the skip instruction and the unmapped-default rule present; the document name still referenced from Plan 04.

- [x] **Step 5: Bump version and commit**

```bash
git add skills/setup/
git commit -m "feat(setup): record who satisfies each post-review pipeline stage

Adds a pipeline handoff table to the delivery configuration, asked only
when the team's pipeline actually has stages between review and done — a
Solo board is asked nothing.

An unmapped status defaults to human, because an agent that advances past
a gate nobody described has claimed work passed a check that never ran."
```

---

### Task 3: Teach the Orchestrator to walk the team's pipeline

**Files:**
- Modify: `skills/orchestrator/SKILL.md`

**Interfaces:**
- Consumes: Task 1's authority rule; Task 2's pipeline table; the story verification loop from Plan 02.
- Produces: the advancement procedure. Task 4 relies on it stopping rather than closing.

- [x] **Step 1: Establish the failing assertion and record the marker count**

```bash
grep -c 'opencode-exclude' skills/orchestrator/SKILL.md
grep -n 'work_status_done' skills/orchestrator/SKILL.md
grep -c 'Pipeline handoff\|pipeline' skills/orchestrator/SKILL.md
```
Expected: sixteen markers — record the exact number; the `work_status_done` calls in §6 and §7; and `pipeline` appearing zero times.

- [x] **Step 2: Replace §7's cascade with pipeline-aware advancement**

§7 currently moves an approved task to `done` and cascades. Replace its numbered list with:

```markdown
Both review axes clear (§6) → the task is ready to leave the review gate. **Where it goes next
depends on the team's pipeline, not on a status this skill can name.**

1. **Advance one status.** `work_status_next(id)`. Then **read the item back** — `work_get` —
   and see where you actually landed. Do not predict: `work_statuses()` does not return
   position or pipeline, and `board_columns()` does not map statuses to columns, so the next
   status is not computable from the MCP surface (see `board-progression` §1).

2. **Did you land on a done-category status?** Then the task is finished; go to step 5.

3. **Otherwise, consult the pipeline handoff table** in the `Allye Delivery Configuration`
   Core Document (`user_config`, loaded by `initialize`).

   - **`agent`** — satisfy it, then return to step 1. Satisfying means running the command the
     table names and reading its output, under the bound in `verification-loop` §3. Red at the
     bound is a correction round, not a pass.
   - **`ci`** — you do not act. Report that the task is waiting on the named external signal
     and move to the next story; revisit when the signal arrives.
   - **`human`**, or **any status not in the table** — stop. Name the status, say who owns it,
     and leave the task exactly where it is.

4. **A status you do not recognise and the table does not cover** is a stop, and also a
   question: ask the user once who satisfies it, record the answer in the delivery
   configuration, and continue. Never ask twice.

5. **Cascade upward, and only upward.** `work_children` the parent; if **every** child is in
   the done category, advance the parent the same way — one step, read back, consult the table.
   A parent stops for the same reasons a child does.

<HARD-GATE>
**Never call `work_status_done` to leave a pipeline you cannot finish.** From four statuses
away it records "done" for work that never passed the gates between — which is exactly how a
story came to be closed with seven of its fifteen tasks still at the review gate.

Use it only when the item's next status **is** the done status. When you cannot finish, stopping
is the correct outcome, not a failure to report.
</HARD-GATE>
```

- [x] **Step 3: Add the stop announcement to §8**

§8 covers epic completion. Add before it:

```markdown
## 7.2 Announce where delivery stopped

When a story's tasks are all parked at the same gate, say so once, plainly: which gate, who
owns it, and what unblocks it. Repeat it in the session-state memory (§10) so a resumed
Orchestrator does not rediscover the boundary by trying to cross it.

A story left open at a gate is **not** an incomplete delivery. It is delivery reporting its
true position. The failure mode this replaces — closing the story to make the board look
finished — cost a real board seven tasks' worth of untracked work.
```

- [x] **Step 4: Verify**

```bash
grep -c 'opencode-exclude' skills/orchestrator/SKILL.md
grep -n 'read the item back' skills/orchestrator/SKILL.md
grep -n 'Pipeline handoff table\|pipeline handoff' skills/orchestrator/SKILL.md
grep -n 'Never call .work_status_done. to leave' skills/orchestrator/SKILL.md
grep -n 'Announce where delivery stopped' skills/orchestrator/SKILL.md
grep -c 'reviewer-standards' skills/orchestrator/SKILL.md
```
Expected: marker count **unchanged from Step 1**; all four new passages found; Plan 03's two-axis dispatch still present.

- [x] **Step 5: Bump version and commit**

```bash
git add skills/orchestrator/
git commit -m "feat(orchestrator): walk the team's pipeline instead of assuming one

Advances one status at a time and reads back where it landed, because
neither work_statuses nor board_columns exposes enough to predict the
next one. Consults the delivery configuration for who satisfies each
post-review gate, and stops — naming the gate and its owner — at the
first it cannot.

work_status_done is now forbidden except when the next status is done.
Calling it from four gates away is how a story was closed with seven of
fifteen tasks still in review."
```

---

### Task 4: A story closes when the pipeline says so

**Files:**
- Modify: `skills/delivery/SKILL.md`

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -n 'work_status_done' skills/delivery/SKILL.md
grep -c 'pipeline' skills/delivery/SKILL.md
```
Expected: the close-out calls present; `pipeline` absent.

- [ ] **Step 2: Extend the verification gate**

§1's HARD-GATE requires every task done before closing. Add to it:

```markdown
"Done" means the **done category**, not the last status an agent could reach. On a pipeline
with stages after review, a task parked at a gate the team satisfies by hand is not done — it
is waiting, and the story waits with it.

If tasks are parked, close-out is not blocked by an oversight. It is **not yet due**. Say which
gate they are waiting at and stop; do not close the story to tidy the board.
```

- [ ] **Step 3: Verify**

```bash
grep -n 'not yet due' skills/delivery/SKILL.md
grep -n 'done category' skills/delivery/SKILL.md
```
Expected: both found.

- [ ] **Step 4: Bump version and commit**

```bash
git add skills/delivery/
git commit -m "feat(delivery): a parked story is waiting, not incomplete

Done means the done category, not the furthest status an agent could
reach. Where a pipeline has stages after review, close-out is not blocked
— it is not yet due, and saying which gate the tasks wait at beats
closing the story to tidy the board."
```

---

### Task 5: Record the upstream gaps where they will be found

Two of these live in other repositories and cannot be fixed here. Recording them in the skill that hits them is what stops the next reader from rediscovering them.

**Files:**
- Modify: `skills/tools-quickref/SKILL.md`

- [ ] **Step 1: Add three gotchas**

To the "Gotchas" list, keeping the existing style:

```markdown
- **`work_statuses` omits `position`, `pipeline`, and `description`.** All three exist on the
  record — `allye-api/prisma/seed-workflow.ts` writes them — but the MCP formatter
  (`allye_mcp/application/tools/work_items.py:590-597`) emits only name, key, id, and colour.
  You therefore cannot compute a status's place in the pipeline, nor tell a `product` status
  from an `engineering` one, from this call.
- **`board_columns` gives no status mapping and no ordering.** Names and ids only. Since
  `work_status_next` walks the board's visible ordered statuses, the transition it will make
  cannot be predicted from the MCP surface. **Move one status, then read the item back.**
- **`team_switch` does not stick for every tool.** It reports that subsequent calls will use
  the chosen team, but `work_children` still errors with "Team selection required", and
  `work_list` returns items across teams. Pass `team_id` explicitly on any call whose result
  must be team-scoped.
```

- [ ] **Step 2: Verify**

```bash
grep -c 'work_statuses. omits' skills/tools-quickref/SKILL.md
grep -c 'board_columns. gives no status mapping' skills/tools-quickref/SKILL.md
grep -c 'team_switch. does not stick' skills/tools-quickref/SKILL.md
grep -c 'sprint_id' skills/tools-quickref/SKILL.md
```
Expected: the three new gotchas present, and `sprint_id` still at **3** — the two legitimate sprint tool rows plus Plan 01's `memory_save` gotcha.

- [ ] **Step 3: Bump version and commit**

```bash
git add skills/tools-quickref/
git commit -m "docs(tools-quickref): three gotchas found against the live API

work_statuses drops position, pipeline and description; board_columns
exposes no status mapping, so the next transition cannot be predicted;
and team_switch does not stick for work_children or work_list despite
reporting that it will."
```

---

## What this plan deliberately does not do

- **No fix to `allye-api` or `allye-mcp`.** Both defects are recorded — the MCP's dropped fields and the API's dead, wrong `ALLOWED_STATUSES_BY_PIPELINE` — and both belong to their own repositories. The plugin works around them rather than waiting for them.
- **No third review axis for security.** `security_scan` runs a scanner and triages output; `reviewer-standards` reads code. Adding a third axis would blur a split Plan 03 made deliberately, and would not run a scanner anyway.
- **No preset detection.** Nothing infers "this team is on Enterprise". The team's statuses are read directly, which is correct for the customised boards presets exist to be a starting point for.
- **No retroactive repair of existing boards.** `BEAC-1927` and its seven parked tasks stay as they are. Reopening a closed story is a data decision for its owner, not something a plugin change should do on its behalf.
