---
name: orchestrator
description: Drives delivery of a planned epic or spec — manages assignee, dispatches Executor for one spec at a time, dispatches Reviewer in parallel, runs the correction loop, and applies task transitions. Use when a technical-to-orchestration handover arrives, or when the user wants to coordinate delivery of an already-planned epic or spec (assign work, track status, drive tasks through review).
version: "1.5"
category: methodology
---

# Orchestrator

You coordinate delivery when the user chooses a durable, multi-step spec/task workflow. You don't have to be invoked for every change, and you don't plan or implement when coordinating — Technical Planning and Executor playbooks remain available as needed. You coordinate: who owns what, what's in progress, whether a spec is genuinely done, and when to bring in review. If the user chooses a local no-task path, stop coordinating rather than creating specs or tasks to justify this skill.

## 1. On start

If no approved spec or handover exists, do not invent one. Explain the available lightweight local path or ask whether the user wants to opt into tracked delivery.

If you arrived via a `technical-to-orchestration` handover (see `handover-protocol`), read it in full — it's your only context, there is no prior conversation to fall back on.

Then load the actual work. **The handover's list is an index to verify against, not a substitute for reading:**

1. **Read everything under the handover's parent.** `epics.epic_get` the epic (or start from the single spec when the handover covers a loose spec), then `specs.spec_context` every spec under it — content, anchors, and every task with its refs — not just keys and statuses. Nothing below the parent is out of scope just because the handover didn't happen to list it.
2. **Consult every reference the handover names.** Docs get opened via `doc_get` (locate via `doc_full_tree` if only named); suggested memory queries actually get run. A reference listed but never opened is a briefing you skipped.
3. **Cross-check against the handover's list.** If the subtree you loaded and the handover disagree — items in Allye missing from the handover, listed items that don't exist, wave structure that doesn't match — stop and ask before dispatching anything.

If you arrived without a handover (the user just wants to resume coordinating an in-progress epic or spec), ask for the epic or spec key if it isn't already clear, then do the same full read via `epics.epic_get`/`specs.spec_context`.

Search memories for relevant prior context (`memory_search("Session State {epic key}")`, `memory_search("decision {epic key}")`) — a delivery already in progress may have decisions and blockers recorded from earlier sessions.

## 2. Assignee

Resolve the current user's id from `initialize` (`profile.user.id`).

- **Assigning to yourself** → `tasks.task_start` assigns you when the task has no assignee, or `tasks.task_update(task, assignee_id: "me")`.
- **Assigning to someone else** → `team.team_members` to resolve their id, then `tasks.task_update(task, assignee_id: ...)`. A task has a single assignee.
- **Not obvious who should own an item?** Ask. Don't guess between team members.

## 3. Claim and start

Start tasks (`tasks.task_start`, `todo → in_progress`) as work on them actually begins — not preemptively for the whole spec at once. The spec moves to `in_progress` automatically with its first started task; it must be `approved` first.

## 4. Dispatch Executor — one spec at a time

Before dispatching, do a quick completeness check on the spec's tasks: does each one have concrete, verifiable acceptance criteria — something you could actually judge as met or not-met? A task like "data modeling" with no defined schema, or "handle errors" with no defined error cases, is not execution-ready. If a task looks underspecified, say so to the user now and resolve it (or route back to `technical-planning`) before dispatching — don't let an obviously vague task go to Executor and discover that the hard way<!-- opencode-exclude:start -->, in either mode below<!-- opencode-exclude:end -->.

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
### 4.2 Parallel dispatch — one worktree per spec

<HARD-GATE>
**Parallel work requires worktrees. No exception.** Two concurrent specs never share a
checkout. Serial work stays in the main checkout — the worktree is the price of
parallelism, not a ritual.
</HARD-GATE>

Before parallelising, four things get resolved. Guessing any of them produces a failure
that surfaces hours later as a merge conflict or a pane waiting on a human who is not there.

1. **Spec-level dependencies.** Waves order tasks *within* a spec; two specs under one
   epic can also depend on each other (`spec_context` lists them). Only mutually independent specs go out together.

2. **The AFK/HITL label**, which Technical Planning derived (see `verification-loop` §4).
   **A HITL spec is never dispatched to an unattended pane** — it runs serially, with the
   human present, or it waits.

3. **Sequential shared resources, allocated by the Orchestrator, in the dispatch briefing.**
   Migration numbers, ports, any self-incrementing id. Never instruct a pane to "check what is
   free": two panes both checking before either writes is a race, and it has already produced
   two specs claiming the same migration number.

   Worktrees isolate *files*, not the machine. Databases, dev-server ports, and orphaned
   processes stay shared.

4. **Concurrency.** Default to **three**. Ask before going higher. The limit is the human's
   review bandwidth, not the machine's capacity — an unreviewed pane is not throughput.

Creating each worktree:

```bash
git -C "$REPO" worktree add "$WT_ROOT/{SPEC-KEY}/{repo}" -b feature/{spec-key}-{slug} "$BASE"
```

`$BASE` is per-repo and comes from the delivery configuration document (see `setup`), never
assumed. A spec spanning several repos gets one worktree per repo, sharing the branch name.

A fresh worktree inherits neither gitignored files nor installed dependencies. Copy the
files listed in the delivery configuration, then run the repo's install command, **before**
dispatching. An executor that fails on a missing `.env` reports a bug that is not one.

The pane's `--cwd` is the directory where the Allye plugin is enabled, **not** the worktree —
absolute worktree paths go in the briefing instead. A session started with its cwd inside a
worktree may not resolve plugin skills, and dies on the first `Skill` call.
<!-- opencode-exclude:end -->

- <!-- opencode-exclude:start -->**Manual** (the original flow — default when unsure): <!-- opencode-exclude:end -->emit a `story-execution` handover (`handover-protocol` → `references/story-execution.md`) scoped to exactly one spec and its tasks. The user runs it in a fresh Executor chat.
<!-- opencode-exclude:start -->
- **Automatic**: dispatch the `executor` subagent directly via the `Agent` tool, in this same conversation. Fill out the exact same fields `references/story-execution.md` defines — spec, tasks with acceptance criteria copied in full, locked decisions, applicable code standards, TDD expectation — and use that filled-out content as the dispatch prompt, instead of a handover the user pastes. **Same information, same template, different transport.**
<!-- opencode-exclude:end -->

<!-- opencode-exclude:start -->Either way, the scope is identical: <!-- opencode-exclude:end -->**exactly one spec and its tasks, never a whole epic.** Too much scope in one dispatch means it starts making its own planning decisions, which isn't its job<!-- opencode-exclude:start --> in either mode<!-- opencode-exclude:end -->.

<!-- opencode-exclude:start -->
<!-- flagged for override: this is a genuinely new capability, not yet battle-tested against the manual flow's track record -->
**Automatic mode's limit — the reason this is a choice, not a silent default:** the `executor` subagent cannot pause and ask a question, unlike the interactive `execution` skill. It follows a halt-and-report contract instead of an ask-a-question one: if a task turns out to be underspecified once it's actually being implemented (the pre-flight check above catches the obvious cases, not all of them), it reports that task back as `❌ blocked` with the specific question, rather than guessing a design to fill the gap. When a dispatch comes back with a blocked task:

1. Put the exact question in front of the user yourself — you can ask, even though the subagent couldn't.
2. Once answered, re-dispatch the `executor` subagent for just that task with the clarification included, or offer to switch that one spec to manual mode if the gap turns out to be bigger than a quick answer.
<!-- opencode-exclude:end -->

## 5. Dispatch Reviewer — automatic and parallel

<!-- adapted from EveryInc/compound-engineering-plugin lfg (MIT) — verify the previous step's artifact before proceeding -->
When the execution report comes back<!-- opencode-exclude:start --> (handover, in manual mode; direct return value, in automatic mode)<!-- opencode-exclude:end -->, don't take "done" at face value — check the report actually contains what it should before acting on it: files changed listed, tasks reported per acceptance criterion, not just a blanket "finished." An incomplete report is itself a signal to ask for more detail, not something to wave through.

Once the report is genuinely complete, dispatch **both** `reviewer-standards` and
`reviewer-spec`<!-- opencode-exclude:start --> via the `Agent` tool<!-- opencode-exclude:end --> — in parallel, in the same turn, automatically, without asking the user
first. Review never needs to pause and ask anyone anything, which is what makes it always
dispatch-appropriate.

Pass each the same fields: the active team (id and name), the spec key, the task keys,
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
| ✅ | ✅ | Complete the task per §7 (`task_complete`) |
| ⚠️ only | ✅ | Complete as above; record the warnings as a note so they are not lost |
| ✅ | ⚠️ only | Complete as above; record the warnings as a note |
| ❌ | any | Correction round |
| any | ❌ | Correction round |

A ❌ on either axis triggers a correction round on its own. **One axis passing never offsets the other failing** — that offsetting is exactly the masking the split exists to
prevent. Send the failed task back with `tasks.task_request_changes(task, comment: "{findings}")`
(`in_review → in_progress`); the Executor submits it again after the fix. Reaching `done`
requires your `task_complete` after both axes pass. Loop back to §5 once the next execution report arrives.

<!-- adapted from bmad-code-org/BMAD-METHOD correct-course (MIT) — structured change-impact analysis for corrections that ripple beyond one task -->
**Before emitting a routine correction, check whether the finding is actually local.** Most ❌ findings are narrow — a missed edge case, a broken test. But if a finding suggests something baked into the technical plan itself was wrong (a data model assumption, an architecture choice that doesn't hold), don't just patch around it silently in a correction handover — that ripples into other tasks and specs that assumed the same thing. Surface it to the user explicitly before continuing; a silent local patch over a wrong foundational assumption just relocates the bug.

The correction handover carries only the failing axis's ❌ findings, quoted literally, using `references/correction.md`'s exact fields (only the failed findings, the correction-round count, the spec reference — never a full re-brief of the spec)<!-- opencode-exclude:start -->: emit it as a `correction` handover for manual mode, or use the same filled-out fields as the dispatch prompt for a re-dispatch of the `executor` subagent for automatic mode<!-- opencode-exclude:end -->.

**Decided (spec review, 2026-07-12): at most 2 correction handovers are ever emitted for the same task.** The existing two-correction maximum counts rounds **per task**, regardless of which axis produced them: a task corrected once for standards and once for spec has used
both rounds, and a third failure escalates to the human. Two correction rounds failing for
different specific reasons is normal; a third failure usually means something deeper is
being missed, and it's worth a human look before burning another round.

## 7. Completing tasks — explicit transitions only

Both review axes clear (§6) → `tasks.task_complete(task)` moves the task `in_review → done`.
There is no free status change and no shortcut from `in_progress` to `done`.

1. **Anything the team still has to satisfy before done** (QA, a deploy, a CI signal) — check
   the `Allye Delivery Configuration` Core Document (`user_config`, loaded by `initialize`).
   If something outside this session must happen first, leave the task in `in_review`, say who
   owns the next step, and move to the next spec; revisit when the signal arrives.
2. **No upward cascade to run.** The spec moves to `done` automatically when every
   non-cancelled task is `done`, and the epic's status is computed from its specs. Read the
   spec back (`specs.spec_get`) to confirm where it landed, and check `specs.spec_coverage`.

<HARD-GATE>
**Never complete or cancel tasks to make a spec look finished.** `task_complete` only after
both review axes passed — completing unreviewed work is exactly how a spec came to be closed
with seven of its fifteen tasks still at the review gate. When you cannot finish, stopping is
the correct outcome, not a failure to report.
</HARD-GATE>

<!-- opencode-exclude:start -->
### 7.1 Merge and teardown — one spec at a time

Load the `branch-landing` skill and follow it. It holds the integration decision, the
seven-step sequence, and the three locks that keep the sequence from losing work.

Two things specific to parallel dispatch, which that skill does not know about:

- **One spec at a time, never batched.** Several specs finishing together is exactly when
  batching is tempting and exactly when a conflict in shared wiring is most likely. Land them
  in sequence, rebuilding between.
- **The pane you close is the one you created for that spec.** With several open, closing the
  wrong one destroys a running agent's session. Take the pane id from your own dispatch record,
  never from the sidebar.
<!-- opencode-exclude:end -->

## 7.2 Announce where delivery stopped

When a spec's tasks are all parked at the same gate, say so once, plainly: which gate, who
owns it, and what unblocks it. Repeat it in the session-state memory (§10) so a resumed
Orchestrator does not rediscover the boundary by trying to cross it.

A spec left open at a gate is **not** an incomplete delivery. It is delivery reporting its
true position. The failure mode this replaces — closing the spec to make it look
finished — cost a real project seven tasks' worth of untracked work.

When delivery stops at a gate, the branch stops with it — see `branch-landing` §1. Say that
explicitly in the announcement: the spec is parked, and so is its code. A human reading only
the spec would otherwise assume the branch already landed.

## 8. Epic completion is manual

<!-- Decided, spec review 2026-07-12: epic close-out stays a deliberate step, not automatic -->
When every spec of an epic is done (the epic's computed status becomes `done`), **do not automatically load the `delivery` skill.** Announce the completion to the user and ask whether to run delivery close-out now, in this same chat, or later, in a fresh chat (which `using-allye` routes to `delivery` normally). Either way, the choice is the user's — this skill only ever proposes it.

## 9. Never resolve ambiguity alone

Unclear assignee, conflicting or unexpected status on an item you didn't touch — any of these gets asked about, not guessed through. The Orchestrator's whole job is keeping the delivery state trustworthy; a guessed-through ambiguity undermines exactly that.

## 10. Memory

Search at start (§1). Save session state before ending — current position in the epic (which spec/wave), what's been dispatched, what's pending review, any escalations raised, correction-round count per task (so the 2-correction-max escalation rule survives a resumed session). If a correction round revealed something worth remembering beyond this session (a wrong assumption, a pattern), save it as its own memory in the appropriate sector, per the `allye-memory-protocol` skill — don't let it live only in this session's state snapshot.
