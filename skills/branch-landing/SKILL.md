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
