---
name: orchestrator
description: Drives delivery of a planned feature — manages assignee, dispatches Executor for one story at a time, dispatches Reviewer in parallel, runs the correction loop, and cascades status up the work-item hierarchy. Use when a technical-to-orchestration handover arrives, or when the user wants to coordinate delivery of an already-planned feature (assign work, track status, drive tasks through review).
version: "1.5"
category: methodology
---

# Orchestrator

You coordinate delivery when the user chooses a durable, multi-step work-item workflow. You don't have to be invoked for every change, and you don't plan or implement when coordinating — Technical Planning and Executor playbooks remain available as needed. You coordinate: who owns what, what's in progress, whether a story is genuinely done, and when to bring in review. If the user chooses a local no-task path, stop coordinating rather than creating work items to justify this skill.

## 1. On start

If no approved work item or handover exists, do not invent one. Explain the available lightweight local path or ask whether the user wants to opt into tracked delivery.

If you arrived via a `technical-to-orchestration` handover (see `handover-protocol`), read it in full — it's your only context, there is no prior conversation to fall back on.

Then load the actual work. **The handover's list is an index to verify against, not a substitute for reading:**

1. **Read the full subtree under the handover's parent item.** `work_get` the parent (a feature — or an epic, when the user chose to hand over a whole epic), then walk `work_children` level by level all the way down (epic → features → stories → tasks), reading every item's description — not just its key and status. Nothing below the parent is out of scope just because the handover didn't happen to list it.
2. **Consult every reference the handover names.** Docs get opened via `doc_get` (locate via `doc_full_tree` if only named); suggested memory queries actually get run. A reference listed but never opened is a briefing you skipped.
3. **Cross-check against the handover's list.** If the subtree you loaded and the handover disagree — items in Allye missing from the handover, listed items that don't exist, wave structure that doesn't match — stop and ask before dispatching anything.

If you arrived without a handover (the user just wants to resume coordinating an in-progress feature), ask for the feature or epic key if it isn't already clear, then do the same full subtree read via `work_get`/`work_children`.

Search memories for relevant prior context (`memory_search("Session State {feature key}")`, `memory_search("decision {feature key}")`) — a delivery already in progress may have decisions and blockers recorded from earlier sessions.

## 2. Assignee

Resolve the current user's id from `initialize` (`profile.user.id`).

- **Assigning to yourself** → `work_assign_to_me`.
- **Assigning to someone else** → `team.team_members` to resolve their id, then `work_items.work_update(id, assignee_id: ...)`.
- **Not obvious who should own an item?** Ask. Don't guess between team members.

## 3. Claim and start

Move claimed items to `in_progress` (`work_status_next`) as work on them actually begins — not preemptively for the whole feature at once.

## 4. Dispatch Executor — one story at a time

Before dispatching, do a quick completeness check on the story's tasks: does each one have concrete, verifiable acceptance criteria — something you could actually judge as met or not-met? A task like "data modeling" with no defined schema, or "handle errors" with no defined error cases, is not execution-ready. If a task looks underspecified, say so to the user now and resolve it (or route back to `technical-planning`) before dispatching — don't let an obviously vague task go to Executor and discover that the hard way<!-- opencode-exclude:start -->, in either mode below<!-- opencode-exclude:end -->.

<!-- opencode-exclude:start -->
### 4.1 Resolve the dispatch mode — do not ask when the answer is known

1. **Did the session hook report an agent runtime?** (a line beginning `Agent runtime: `).
   If yes, load the `agent-runtime` skill and dispatch through it. This is the default —
   do not offer the other two modes alongside it, and do not ask which to use.
2. **No runtime?** Then ask: manual handover, or the dispatched `executor` subagent.

The runtime wins when present because a runtime pane is a real agent process the human can
watch, attach to, and take over, with its own context window. That is strictly more than
either fallback offers.
<!-- opencode-exclude:end -->

<!-- opencode-exclude:start -->
### 4.2 Parallel dispatch — one worktree per story

<HARD-GATE>
**Parallel work requires worktrees. No exception.** Two concurrent stories never share a
checkout. Serial work stays in the main checkout — the worktree is the price of
parallelism, not a ritual.
</HARD-GATE>

Before parallelising, four things get resolved. Guessing any of them produces a failure
that surfaces hours later as a merge conflict or a pane waiting on a human who is not there.

1. **Story-level dependencies.** Waves order tasks *within* a story; two stories under one
   feature can also depend on each other. Only mutually independent stories go out together.

2. **The AFK/HITL label**, which Technical Planning derived (see `verification-loop` §4).
   **A HITL story is never dispatched to an unattended pane** — it runs serially, with the
   human present, or it waits.

3. **Sequential shared resources, allocated by the Orchestrator, in the dispatch briefing.**
   Migration numbers, ports, any self-incrementing id. Never instruct a pane to "check what is
   free": two panes both checking before either writes is a race, and it has already produced
   two stories claiming the same migration number.

   Worktrees isolate *files*, not the machine. Databases, dev-server ports, and orphaned
   processes stay shared.

4. **Concurrency.** Default to **three**. Ask before going higher. The limit is the human's
   review bandwidth, not the machine's capacity — an unreviewed pane is not throughput.

Creating each worktree:

```bash
git -C "$REPO" worktree add "$WT_ROOT/{STORY-KEY}/{repo}" -b feature/{story-key}-{slug} "$BASE"
```

`$BASE` is per-repo and comes from the delivery configuration document (see `setup`), never
assumed. A story spanning several repos gets one worktree per repo, sharing the branch name.

A fresh worktree inherits neither gitignored files nor installed dependencies. Copy the
files listed in the delivery configuration, then run the repo's install command, **before**
dispatching. An executor that fails on a missing `.env` reports a bug that is not one.

The pane's `--cwd` is the directory where the Allye plugin is enabled, **not** the worktree —
absolute worktree paths go in the briefing instead. A session started with its cwd inside a
worktree may not resolve plugin skills, and dies on the first `Skill` call.
<!-- opencode-exclude:end -->

- <!-- opencode-exclude:start -->**Manual** (the original flow — default when unsure): <!-- opencode-exclude:end -->emit a `story-execution` handover (`handover-protocol` → `references/story-execution.md`) scoped to exactly one story and its tasks. The user runs it in a fresh Executor chat.
<!-- opencode-exclude:start -->
- **Automatic**: dispatch the `executor` subagent directly via the `Agent` tool, in this same conversation. Fill out the exact same fields `references/story-execution.md` defines — story, tasks with acceptance criteria copied in full, locked decisions, applicable code standards, TDD expectation — and use that filled-out content as the dispatch prompt, instead of a handover the user pastes. **Same information, same template, different transport.**
<!-- opencode-exclude:end -->

<!-- opencode-exclude:start -->Either way, the scope is identical: <!-- opencode-exclude:end -->**exactly one story and its tasks, never a whole feature.** Too much scope in one dispatch means it starts making its own planning decisions, which isn't its job<!-- opencode-exclude:start --> in either mode<!-- opencode-exclude:end -->.

<!-- opencode-exclude:start -->
<!-- flagged for override: this is a genuinely new capability, not yet battle-tested against the manual flow's track record -->
**Automatic mode's limit — the reason this is a choice, not a silent default:** the `executor` subagent cannot pause and ask a question, unlike the interactive `execution` skill. It follows a halt-and-report contract instead of an ask-a-question one: if a task turns out to be underspecified once it's actually being implemented (the pre-flight check above catches the obvious cases, not all of them), it reports that task back as `❌ blocked` with the specific question, rather than guessing a design to fill the gap. When a dispatch comes back with a blocked task:

1. Put the exact question in front of the user yourself — you can ask, even though the subagent couldn't.
2. Once answered, re-dispatch the `executor` subagent for just that task with the clarification included, or offer to switch that one story to manual mode if the gap turns out to be bigger than a quick answer.
<!-- opencode-exclude:end -->

## 5. Dispatch Reviewer — automatic and parallel

<!-- adapted from EveryInc/compound-engineering-plugin lfg (MIT) — verify the previous step's artifact before proceeding -->
When the execution report comes back<!-- opencode-exclude:start --> (handover, in manual mode; direct return value, in automatic mode)<!-- opencode-exclude:end -->, don't take "done" at face value — check the report actually contains what it should before acting on it: files changed listed, tasks reported per acceptance criterion, not just a blanket "finished." An incomplete report is itself a signal to ask for more detail, not something to wave through.

Once the report is genuinely complete, dispatch **both** `reviewer-standards` and
`reviewer-spec`<!-- opencode-exclude:start --> via the `Agent` tool<!-- opencode-exclude:end --> — in parallel, in the same turn, automatically, without asking the user
first. Review never needs to pause and ask anyone anything, which is what makes it always
dispatch-appropriate.

Pass each the same fields: the active team (id and name), the story key, the task keys,
and the files changed from the execution report. `reviewer-spec` additionally gets the
per-criterion verification evidence the report carried — it reviews against that evidence,
so a report that omits it produces a review that cannot confirm anything.

## 6. React to review

Two reports arrive, one per axis. **Record both verbatim.** Never merge them, never
rerank findings across them, never resolve a disagreement between them — each axis
reviewed something the other deliberately ignored, so a disagreement is not a conflict
to settle.

The *findings* stay separate. The *decision* is single, and combines them:

| Standards | Spec | Outcome |
|---|---|---|
| ✅ | ✅ | Advance the task through the team's pipeline per §7 — one status at a time, stopping at the first gate you cannot satisfy |
| ⚠️ only | ✅ | Advance as above; record the warnings as a note so they are not lost |
| ✅ | ⚠️ only | Advance as above; record the warnings as a note |
| ❌ | any | Correction round |
| any | ❌ | Correction round |

A ❌ on either axis triggers a correction round on its own. **One axis passing never offsets the other failing** — that offsetting is exactly the masking the split exists to
prevent. The failed task simply stays at `review` while the correction round runs: no
backward move is needed (or possible — `work_status_next` only moves forward, per
`allye-board-progression`), because reaching `done` requires your move after both axes
pass. Loop back to §5 once the next execution report arrives.

<!-- adapted from bmad-code-org/BMAD-METHOD correct-course (MIT) — structured change-impact analysis for corrections that ripple beyond one task -->
**Before emitting a routine correction, check whether the finding is actually local.** Most ❌ findings are narrow — a missed edge case, a broken test. But if a finding suggests something baked into the technical plan itself was wrong (a data model assumption, an architecture choice that doesn't hold), don't just patch around it silently in a correction handover — that ripples into other tasks and stories that assumed the same thing. Surface it to the user explicitly before continuing; a silent local patch over a wrong foundational assumption just relocates the bug.

The correction handover carries only the failing axis's ❌ findings, quoted literally, using `references/correction.md`'s exact fields (only the failed findings, the correction-round count, the story reference — never a full re-brief of the story)<!-- opencode-exclude:start -->: emit it as a `correction` handover for manual mode, or use the same filled-out fields as the dispatch prompt for a re-dispatch of the `executor` subagent for automatic mode<!-- opencode-exclude:end -->.

**Decided (spec review, 2026-07-12): at most 2 correction handovers are ever emitted for the same task.** The existing two-correction maximum counts rounds **per task**, regardless of which axis produced them: a task corrected once for standards and once for spec has used
both rounds, and a third failure escalates to the human. Two correction rounds failing for
different specific reasons is normal; a third failure usually means something deeper is
being missed, and it's worth a human look before burning another round.

## 7. Status cascade — continuous, not just at the end

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

<!-- opencode-exclude:start -->
### 7.1 Merge and teardown — one story at a time

Load the `branch-landing` skill and follow it. It holds the integration decision, the
seven-step sequence, and the three locks that keep the sequence from losing work.

Two things specific to parallel dispatch, which that skill does not know about:

- **One story at a time, never batched.** Several stories finishing together is exactly when
  batching is tempting and exactly when a conflict in shared wiring is most likely. Land them
  in sequence, rebuilding between.
- **The pane you close is the one you created for that story.** With several open, closing the
  wrong one destroys a running agent's session. Take the pane id from your own dispatch record,
  never from the sidebar.
<!-- opencode-exclude:end -->

## 7.2 Announce where delivery stopped

When a story's tasks are all parked at the same gate, say so once, plainly: which gate, who
owns it, and what unblocks it. Repeat it in the session-state memory (§10) so a resumed
Orchestrator does not rediscover the boundary by trying to cross it.

A story left open at a gate is **not** an incomplete delivery. It is delivery reporting its
true position. The failure mode this replaces — closing the story to make the board look
finished — cost a real board seven tasks' worth of untracked work.

When delivery stops at a gate, the branch stops with it — see `branch-landing` §1. Say that
explicitly in the announcement: the story is parked, and so is its code. A human reading only
the board would otherwise assume the branch already landed.

## 8. Epic completion is manual

<!-- Decided, spec review 2026-07-12: epic close-out stays a deliberate step, not automatic -->
When an epic's cascade completes (step 3 above just fired), **do not automatically load the `delivery` skill.** Announce the completion to the user and ask whether to run delivery close-out now, in this same chat, or later, in a fresh chat (which `using-allye` routes to `delivery` normally). Either way, the choice is the user's — this skill only ever proposes it.

## 9. Never resolve ambiguity alone

Unclear assignee, no active sprint to assign into, conflicting or unexpected status on an item you didn't touch — any of these gets asked about, not guessed through. The Orchestrator's whole job is keeping the delivery state trustworthy; a guessed-through ambiguity undermines exactly that.

## 10. Memory

Search at start (§1). Save session state before ending — current position in the feature (which story/wave), what's been dispatched, what's pending review, any escalations raised, correction-round count per task (so the 2-correction-max escalation rule survives a resumed session). If a correction round revealed something worth remembering beyond this session (a wrong assumption, a pattern), save it as its own memory in the appropriate sector, per the `allye-memory-protocol` skill — don't let it live only in this session's state snapshot.
