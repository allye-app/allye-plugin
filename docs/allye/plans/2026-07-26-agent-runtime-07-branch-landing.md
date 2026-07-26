# Branch Landing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Allye the step it never had — deciding and executing what happens to a branch once its work is done. Two executors reached outside the suite for this; the merge-and-teardown flow was run by hand six times from prose. Both stop after this plan.

**Architecture:** One new skill holds the discipline, reached by the three callers that need it. `orchestrator` §7.1's procedure **moves** there rather than being copied, leaving a reference. The rule that makes it Allye's rather than generic: a branch does not land ahead of its story.

**Tech Stack:** Markdown skills. No build step, no test framework — verification is grep assertion.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract.** Never rename one.
- **Attribution comments stay.** Twenty-two exist across `skills/` and `agents/`; this plan removes none.
- **Preserve every `opencode-exclude` marker.** `skills/orchestrator/SKILL.md` carries sixteen, `skills/handover-protocol/SKILL.md` three. Count before and after any edit to either.
- **No status key may be hard-coded as a rule** — the multi-tenancy gate from Plan 06 applies here too. Status names appear only as labelled examples or as the four category values.
- **Skill files stay in English.** Bump `version` minor on any skill changed.
- **Do not push. Do not merge to `main`.**

## Prerequisites

Plans 01–06 complete and merged.

```bash
grep -c '7.1 Merge and teardown' skills/orchestrator/SKILL.md    # exactly 1
grep -ci 'branch' skills/delivery/SKILL.md                        # exactly 0 — the gap
grep -c 'opencode-exclude' skills/orchestrator/SKILL.md           # record it; must not drop
ls docs/allye/specs/2026-07-26-agent-runtime-and-verification-design.md
```

Read **§18 of the spec** before Task 1. It records why this exists and what makes it Allye's rather than a generic branch skill.

---

### Task 1: Create the `branch-landing` skill

**Files:**
- Create: `skills/branch-landing/SKILL.md`

**Interfaces:**
- Consumes: the story's pipeline position, per `board-progression` §3.1.
- Produces: a skill reachable by name from `delivery`, `orchestrator`, and `execution`. The three locks and the teardown order are referenced by section from Task 2 — do not renumber them there.

- [ ] **Step 1: Write the skill**

Create `skills/branch-landing/SKILL.md`:

```markdown
---
name: branch-landing
description: Decide and execute what happens to a branch once its work is done — merge, open a pull request, or leave it — then tear down the worktree and pane without losing anything. Use when a story's implementation is complete, or when another skill needs the teardown sequence.
version: "1.0"
category: methodology
---

# Branch Landing

Code that is written and reviewed is not yet delivered. It sits on a branch, and something has to decide what happens to it. This skill is that decision and the sequence that carries it out.

## 1. A branch does not land ahead of its story

<HARD-GATE>
Before anything else, check where the story actually is.

If the story is parked at a pipeline gate — waiting on QA, a scan, a deploy, anything the team satisfies outside this session (see `board-progression` §3.1) — **the branch waits with it.** Do not merge, do not open a pull request, do not remove the worktree.

Landing code whose story never passed its gates is the same defect as closing a story to tidy the board, one layer down. Say which gate the story waits at, and stop.
</HARD-GATE>

The work item is the authority on whether the work is done. The branch follows it; it never leads.

## 2. Ask how the work should land

Teams integrate differently and the plugin has no basis to guess. Ask once, with a recommendation so accepting takes a word:

| Option | What happens | When it fits |
|---|---|---|
| **Pull request** | Push the branch, open a PR against the base, leave everything standing | Any team that reviews before merging, or where CI runs on the PR |
| **Merge locally** | Merge into the base in the main checkout, then tear down | Solo work, or a change already reviewed by the two axes |
| **Leave it** | Push for safety, change nothing else | The human wants to look first, or the work is paused |

The base branch is per-repo and comes from the `Allye Delivery Configuration` Core Document — **never assumed.** Repos with a git-flow layout branch from `develop`; repos releasing from trunk branch from `main`.

**Nothing merges into the base branch without the human choosing it in this conversation.** A merge is not reversible in the way an unmerged branch is, and no amount of green review substitutes for being asked.

## 3. The sequence, when merging locally

Every step is a gate. One story at a time; do not batch.

```
1. GATE:  git -C <worktree> status --porcelain   must be EMPTY
          dirty → STOP, escalate. Do not merge, do not remove.
2. git push -u origin <branch>
3. In the MAIN checkout, on the base:  git merge --no-ff <branch>
4. Conflicts in shared wiring files are expected when parallel work
   touched the same composition root. Resolve by CONSOLIDATING into one
   instance — never by picking a side.
5. Rebuild, typecheck, run tests BEFORE committing the merge
6. git worktree remove <path>          ← without --force
7. Close the runtime pane              ← only after step 6
```

### The three locks

Each exists because it prevents one specific way work disappears. They look skippable right up until they are not.

| Lock | What it prevents |
|---|---|
| **Push before removal** (2) | The branch exists on the remote before anything is destroyed. After this, no local accident loses the work. |
| **`worktree remove` without `--force`** (6) | Git refuses a dirty worktree. That refusal is the last safety net; bypassing it by reflex is how uncommitted work vanishes. |
| **Pane closes last** (7) | While the pane lives, the session's reasoning is inspectable. Close it before a validated merge and the *why* is gone, even though the *what* survives in the diff. |

### When merging is not the choice

**Pull request:** push, open the PR against the base, and stop. Worktree and pane stay — review feedback arrives there. Record the PR reference on the story so the next session finds it.

**Leave it:** push, and change nothing else. Say plainly what is standing: branch, worktree, pane.

## 4. Never

- **Never merge into the base branch unasked.** §2.
- **Never force-push.** A force-push rewrites what step 2 exists to protect.
- **Never delete a branch.** Merged branches are cheap and are the record of how something was built. Removing a worktree is not deleting its branch, and should not become it.
- **Never destroy what you did not create.** A worktree or pane that predates this session belongs to someone else.

## 5. Abandoned work

A story that failed, was cancelled, or stalled gets **no cleanup at all**. Worktree, branch, and pane all stay.

Visible litter costs far less than deleted work, and an abandoned branch is often the only record of an approach that was tried and rejected — which is worth more than the disk it occupies.

## 6. Record where it landed

Once the work has landed, the branch may be the only durable trace outside the diff. Carry the reference into the delivery memory (`memory_save`, `sector: "knowledge"`): the branch name, the merge commit or PR reference, and the base it landed on.

A memory that says a story was delivered, without saying where the code went, is a memory that sends the next reader searching.
```

- [ ] **Step 2: Verify**

```bash
sed -n '1,7p' skills/branch-landing/SKILL.md
grep -c 'does not land ahead of its story' skills/branch-landing/SKILL.md
grep -c 'three locks' skills/branch-landing/SKILL.md
grep -n 'Never force-push' skills/branch-landing/SKILL.md
grep -n 'no cleanup at all' skills/branch-landing/SKILL.md
grep -cE '`code_review`|`qa_testing`|`deploy_' skills/branch-landing/SKILL.md
```
Expected: four frontmatter keys; the story gate present; the locks section present; the force-push and abandoned-work rules present; and **zero** hard-coded status keys — the multi-tenancy gate applies here too.

- [ ] **Step 3: Commit**

```bash
git add skills/branch-landing/
git commit -m "feat(skills): add branch-landing

Decides and executes what happens to a branch once its work is done, and
carries the teardown sequence that was previously prose in a spec and run
by hand six times.

The rule a generic branch skill cannot have: a branch does not land ahead
of its story. If the story is parked at a pipeline gate, the branch waits
with it — landing code whose story never passed QA is the same defect as
closing the story to tidy the board, one layer down."
```

---

### Task 2: Move the Orchestrator's teardown into the skill

The procedure exists in `orchestrator` §7.1, written by Plan 04. It **moves**; it is not copied. Two copies of a seven-step sequence with three safety locks is two places for it to drift.

**Files:**
- Modify: `skills/orchestrator/SKILL.md`

**Interfaces:**
- Consumes: Task 1.
- Produces: a reference in place of the procedure.

- [ ] **Step 1: Record the marker count and locate the section**

```bash
grep -c 'opencode-exclude' skills/orchestrator/SKILL.md
grep -n '### 7.1 Merge and teardown' skills/orchestrator/SKILL.md
```
Record the count. It must be identical at Step 4.

- [ ] **Step 2: Replace §7.1's body with a reference**

`### 7.1` is followed by `## 7.2 Announce where delivery stopped` — note the heading levels differ, `###` then `##`. Keep the `### 7.1` heading and replace everything between it and the `## 7.2` line with:

```markdown
Load the `branch-landing` skill and follow it. It holds the integration decision, the
seven-step sequence, and the three locks that keep the sequence from losing work.

Two things specific to parallel dispatch, which that skill does not know about:

- **One story at a time, never batched.** Several stories finishing together is exactly when
  batching is tempting and exactly when a conflict in shared wiring is most likely. Land them
  in sequence, rebuilding between.
- **The pane you close is the one you created for that story.** With several open, closing the
  wrong one destroys a running agent's session. Take the pane id from your own dispatch record,
  never from the sidebar.
```

- [ ] **Step 3: Point §7.2 at it too**

§7.2 announces where delivery stopped. Append:

```markdown
When delivery stops at a gate, the branch stops with it — see `branch-landing` §1. Say that
explicitly in the announcement: the story is parked, and so is its code. A human reading only
the board would otherwise assume the branch already landed.
```

- [ ] **Step 4: Verify**

```bash
grep -c 'opencode-exclude' skills/orchestrator/SKILL.md
grep -c 'branch-landing' skills/orchestrator/SKILL.md
grep -c 'status --porcelain' skills/orchestrator/SKILL.md
grep -c 'reviewer-standards' skills/orchestrator/SKILL.md
grep -n 'one story at a time, never batched\|One story at a time, never batched' skills/orchestrator/SKILL.md
```
Expected: marker count **unchanged from Step 1**; `branch-landing` referenced at least twice; `status --porcelain` now **zero** — the sequence moved, it was not copied; Plan 03's two-axis dispatch still present; the batching rule found.

- [ ] **Step 5: Bump version and commit**

```bash
git add skills/orchestrator/
git commit -m "refactor(orchestrator): move the teardown sequence into branch-landing

The seven-step merge and teardown, with its three locks, now lives in one
skill that three callers reach. Two copies of a sequence whose whole value
is that no step is skipped is two places for a step to go missing.

What stays here is what only parallel dispatch knows: land one story at a
time, and take the pane id from your own dispatch record rather than the
sidebar, because closing the wrong pane kills a running agent."
```

---

### Task 3: Make `delivery` ask where the code went

`delivery` verifies tasks, closes the story, updates docs, cleans TODOs, and saves a memory — and mentions the branch **zero** times. A story can currently be delivered in Allye while its code sits unmerged.

**Files:**
- Modify: `skills/delivery/SKILL.md`

**Interfaces:**
- Consumes: Task 1.
- Produces: nothing downstream.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -ci 'branch' skills/delivery/SKILL.md
grep -c 'branch-landing' skills/delivery/SKILL.md
```
Expected: **zero from both.** That is the gap.

- [ ] **Step 2: Add the landing step between closing and documenting**

After "## Step 2: Close the Story" and before "## Step 3: Update Documentation", insert:

```markdown
---

## Step 2.5: Land the Code

The story is closed in Allye. The code is still on a branch.

Load the `branch-landing` skill and follow it. It asks how the work should land — pull
request, local merge, or left alone — and carries the sequence that gets it there without
losing anything.

<HARD-GATE>
Do not skip this because the story is already closed. Closing the item and landing the code
are different acts, and doing the first without the second produces the worst available
state: a board that says delivered and a base branch that does not have the work.

If the story reached this skill while still parked at a pipeline gate, it should not have —
see Step 1. The branch stays where it is.
</HARD-GATE>
```

- [ ] **Step 3: Carry the reference into the memory**

Step 5's `memory_save` content template gains a line:

```markdown
## Where the code landed
{branch name, and the merge commit or PR reference, and the base it landed on — or "not yet landed: {reason}"}
```

- [ ] **Step 4: Add the checklist item**

In the "Workflow Checklist", after the story-closed item:

```markdown
- [ ] The code landed, or the reason it has not is recorded
```

- [ ] **Step 5: Verify**

```bash
grep -c 'branch-landing' skills/delivery/SKILL.md
grep -n 'Step 2.5: Land the Code' skills/delivery/SKILL.md
grep -n 'Where the code landed' skills/delivery/SKILL.md
grep -c 'work_status_done' skills/delivery/SKILL.md
```
Expected: the skill referenced; the step and the memory line present; and the existing `work_status_done` usage untouched.

- [ ] **Step 6: Bump version and commit**

```bash
git add skills/delivery/
git commit -m "feat(delivery): ask where the code went

Delivery verified tasks, closed the story, updated docs, cleaned TODOs
and saved a memory — and mentioned the branch zero times. A story could
be delivered in Allye with its code sitting unmerged.

Closing the item and landing the code are different acts. Doing the first
without the second produces the worst available state: a board that says
delivered and a base branch that does not have the work."
```

---

### Task 4: Point the interactive Executor at it

An Executor working in a worktree finishes its story and has nowhere to look.

**Files:**
- Modify: `skills/execution/SKILL.md`

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -c 'branch-landing' skills/execution/SKILL.md
```
Expected: `0`.

- [ ] **Step 2: Add it to "What Comes Next"**

Append to the "What Comes Next" section at the end of the file:

```markdown
**If you are working in a git worktree**, the Orchestrator that dispatched you owns landing
the branch — do not merge, do not remove the worktree, do not close your own pane. Name the
branch in your `execution-report` so it knows what to land.

**If you are working directly in the main checkout** and no Orchestrator is coordinating, the
branch is yours to finish: load the `branch-landing` skill once the story's tasks are through
review.
```

- [ ] **Step 3: Verify**

```bash
grep -c 'branch-landing' skills/execution/SKILL.md
grep -n 'do not close your own pane' skills/execution/SKILL.md
grep -c '## Step 4.5' skills/execution/SKILL.md
```
Expected: the reference present; the prohibition present; Plan 05's Step 4.5 still there.

- [ ] **Step 4: Bump version and commit**

```bash
git add skills/execution/
git commit -m "feat(execution): say who lands the branch

An Executor in a worktree does not land its own work — the dispatching
Orchestrator does, and the executor names the branch in its report so it
can. An Executor working directly in the main checkout with nobody
coordinating owns it, and loads branch-landing."
```

---

### Task 5: Register and route the new skill

A skill whose file exists but which nothing can resolve is a broken reference, not a wrong count. This is the completeness checklist the retrospective closed with.

**Files:**
- Modify: `seed/seed-skills.json`, `skills/using-allye/SKILL.md`, `README.md`, `CLAUDE.md`

- [ ] **Step 1: Seed it**

Add to `seed/seed-skills.json`'s `skills` array, matching the existing entry shape exactly:

```json
{
  "name": "branch-landing",
  "slug": "branch-landing",
  "description": "Decide and execute what happens to a branch once its work is done — merge, open a pull request, or leave it — then tear down the worktree and pane without losing anything. Use when a story's implementation is complete, or when another skill needs the teardown sequence.",
  "category": "devops",
  "scope": "team",
  "source_file": "skills/branch-landing/SKILL.md",
  "supported_agents": ["claude", "opencode", "cursor", "codex", "gemini"]
}
```

Every agent, because git is git everywhere — unlike `agent-runtime`, which is claude-only because only there does a hook detect a runtime.

- [ ] **Step 2: Add it to the bootstrap's on-demand paragraph**

`using-allye` §2 has a one-sentence paragraph naming the skills that sit outside the routing table because no user request routes to them directly. It currently begins **"Two skills sit outside this table"** — that word becomes **"Three"**, and `branch-landing` joins the list as reached from `delivery`, `orchestrator`, and `execution`.

Changing the number is not cosmetic: a sentence that says "two" and lists three is the kind of small wrongness that makes a reader distrust the rest of the file.

**This file is injected into every session** — keep the addition to the existing sentence rather than adding a new one, and check the line count afterwards.

- [ ] **Step 3: Update the counts**

`README.md` and `CLAUDE.md` both state skill counts. **17 skills** after this plan. The README's marketplace-published count rises to **16** — every skill except `setup`.

- [ ] **Step 4: Verify the whole registration, not just the file**

```bash
jq -e '.skills | map(select(.slug=="branch-landing")) | length == 1' seed/seed-skills.json
jq '.skills | length' seed/seed-skills.json
ls -d skills/*/ | wc -l
grep -c 'branch-landing' skills/using-allye/SKILL.md
grep -c 'Two skills sit outside' skills/using-allye/SKILL.md
grep -c 'Three skills sit outside' skills/using-allye/SKILL.md
wc -l < skills/using-allye/SKILL.md
grep -on '1[0-9] skills' README.md CLAUDE.md
```
Expected: the seed entry present and valid JSON; **16** seeded against **17** on disk, the difference being `setup`; the bootstrap references it; **zero** occurrences of "Two skills sit outside" and **one** of "Three skills sit outside"; `using-allye` at most **193** lines — it was 191 after Plan 05 and this adds words to one sentence, not a section; and every written count reading 17.

- [ ] **Step 5: Commit**

```bash
git add seed/ skills/using-allye/ README.md CLAUDE.md
git commit -m "feat: register branch-landing in the seed, the bootstrap and the counts

A skill is not done when its file exists — it is done when everything
naming it can resolve it. Seeded for all five agents, since git is git
everywhere, unlike agent-runtime which is claude-only because only there
does a hook detect a runtime."
```

---

## What this plan deliberately does not do

- **No git automation beyond what the sequence names.** No branch-naming scheme, no rebase policy, no commit-squashing opinion. Teams have these and the plugin has no business overriding them.
- **No PR templates or descriptions.** Opening a PR is in scope; deciding what it says is the team's, and their repository already has an opinion.
- **No CI integration.** Waiting on a pipeline signal is the `ci` row of the delivery configuration's handoff table (Plan 06), not this skill's job.
- **No retroactive cleanup.** The seven branches this project pushed stay exactly as they are.
