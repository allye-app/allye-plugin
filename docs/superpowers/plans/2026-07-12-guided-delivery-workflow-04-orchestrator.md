# Allye Guided Delivery Workflow — Plan 4: Orchestrator

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `orchestrator` skill — the busiest consumer of the Handover Catalog and the only phase that actively dispatches another subagent (Reviewer) as part of its normal operation. It manages assignee, drives the Executor/Reviewer loop one story at a time, runs the correction loop with a 3-strike human-escalation rule, and cascades status continuously up the work-item hierarchy.

**Architecture:** One skill, `skills/orchestrator/`, loaded into the main thread (it must be able to ask the user about ambiguous assignee/sprint/status situations). It reuses the existing `reviewer` subagent (Plan 1) and the `review` skill's unchanged ✅/⚠️/❌ output format — no new subagent is created in this plan.

**Tech Stack:** Markdown only.

**Source spec:** `docs/superpowers/specs/2026-07-12-guided-delivery-workflow-design.md` §6.4 (Orchestrator), §6.6 (Status cascade + delivery close-out), §10 (resolved decisions: manual epic close-out, 3-strike correction threshold), §7 (adaptation sources — compound-engineering `lfg`, BMAD `correct-course`).

**Depends on:** Plan 1 (restructure — `execution`, `review`, `delivery` skill names; `reviewer` agent), Plan 2 (Handover Catalog — `technical-to-orchestration`, `story-execution`, `execution-report`, `correction` templates), Plan 3 (Sandbox — establishes the using-allye routing-table edit pattern this plan follows for its own row).

## Global Constraints

- Orchestrator **never** auto-runs `delivery` at epic completion — it announces and asks, per the decision resolved in spec review (§10). This is not a suggestion to revisit; it's a settled decision.
- Escalate to the user after the **3rd** failed review round on the same task — not the 2nd, not the 4th. Settled in spec review (§10).
- Reviewer is dispatched via the `Agent` tool, in parallel, automatically — it is the **only** dispatch-appropriate step in this whole skill. Every other action in this skill either does direct MCP tool calls or asks the user; nothing else gets dispatched as a subagent.
- Every task's final commit uses `git commit -m "..." -- <exact-path>` (pathspec-scoped) — the lesson from Plans 1-3, now a hard requirement, not a suggestion.
- Every adapted section carries a one-line credit comment, per spec §7's rule of thumb.

## File Structure

| File | Responsibility |
|---|---|
| `skills/orchestrator/SKILL.md` | The full Orchestrator phase: on-start, assignee, claim, dispatch Executor, dispatch Reviewer, react to review (cascade or correction + 3-strike escalation), status cascade, manual epic close-out, memory |
| `skills/using-allye/SKILL.md` | Modified: new Orchestrator row in the routing table, between Technical Planning and Technical Development |
| `seed/seed-skills.json` | Modified: new `orchestrator` entry |

## Task 1: Create `skills/orchestrator/SKILL.md`

**Files:**
- Create: `skills/orchestrator/SKILL.md`

**Interfaces:**
- Consumes: `handover-protocol`'s `technical-to-orchestration` and `execution-report` templates (received); `story-execution` and `correction` templates (emitted) — all from Plan 2
- Consumes: the `reviewer` subagent (Plan 1) and its unchanged ✅/⚠️/❌ output format
- Produces: status changes via `work_status_next`/`work_status_done`, assignee changes via `work_assign_to_me`/`work_update`, and (eventually, once triggered by the user) a handoff into the `delivery` skill

- [ ] **Step 1: Write the file**

```markdown
---
name: orchestrator
description: Drives delivery of a planned feature — manages assignee, dispatches Executor for one story at a time, dispatches Reviewer in parallel, runs the correction loop, and cascades status up the work-item hierarchy. Use when a technical-to-orchestration handover arrives, or when the user wants to coordinate delivery of an already-planned feature (assign work, track status, drive tasks through review).
version: "1.0"
category: methodology
---

# Orchestrator

You drive delivery. You don't plan — that already happened in Technical Planning — and you don't implement — that's Executor's job, one fresh chat at a time. You coordinate: who owns what, what's in progress, whether a story is genuinely done, and when to bring in review.

## 1. On start

If you arrived via a `technical-to-orchestration` handover (see `handover-protocol`), read it in full — it's your only context, there is no prior conversation to fall back on. Load everything it points at: the doc, the epic, the feature, every story, every task, grouped by wave.

If you arrived without a handover (the user just wants to resume coordinating an in-progress feature), ask for the feature key if it isn't already clear, then load the same hierarchy via `work_get`/`work_children`.

Search memories for relevant prior context (`memory_search("Session State {feature key}")`, `memory_search("decision {feature key}")`) — a delivery already in progress may have decisions and blockers recorded from earlier sessions.

## 2. Assignee

Resolve the current user's id from `initialize` (`profile.user.id`).

- **Assigning to yourself** → `work_assign_to_me`.
- **Assigning to someone else** → `team.team_members` to resolve their id, then `work_items.work_update(id, assignee_id: ...)`.
- **Not obvious who should own an item?** Ask. Don't guess between team members.

## 3. Claim and start

Move claimed items to `in_progress` (`work_status_next`) as work on them actually begins — not preemptively for the whole feature at once.

## 4. Dispatch Executor — one story at a time

Emit a `story-execution` handover (`handover-protocol` → `references/story-execution.md`) scoped to **exactly one story and its tasks** — never a whole feature in one handover. This is the scoping rule the entire loop depends on: a fresh Executor chat with too much scope starts making its own planning decisions, which isn't its job.

## 5. Dispatch Reviewer — the one automatic, parallel step

<!-- adapted from EveryInc/compound-engineering-plugin lfg (MIT) — verify the previous step's artifact before proceeding -->
When the Executor's `execution-report` handover comes back, don't take "done" at face value — check the report actually contains what it should before acting on it: files changed listed, tasks reported per acceptance criterion, not just a blanket "finished." An incomplete report is itself a signal to ask the user or the Executor chat for more detail, not something to wave through.

Once the report is genuinely complete, dispatch the `reviewer` subagent via the `Agent` tool — in parallel, automatically, no need to ask the user first. This is the one dispatch-appropriate step in the whole pipeline, because review doesn't need to pause and ask anyone anything. Pass it: the story key, the task keys, and the files changed from the execution report.

## 6. React to review

Reviewer returns its standard ✅/⚠️/❌-per-task output (unchanged from the `review` skill — no new format to learn).

- **All ✅** → proceed to the status cascade (§7).
- **Any ❌** → emit a `correction` handover (`handover-protocol` → `references/correction.md`) back to the same Executor, containing only the failed findings — not a full re-brief of the story. Loop back to §5 once the Executor's next `execution-report` arrives.

<!-- adapted from bmad-code-org/BMAD-METHOD correct-course (MIT) — structured change-impact analysis for corrections that ripple beyond one task -->
**Before emitting a routine correction, check whether the finding is actually local.** Most ❌ findings are narrow — a missed edge case, a broken test. But if a finding suggests something baked into the technical plan itself was wrong (a data model assumption, an architecture choice that doesn't hold), don't just patch around it silently in a correction handover — that ripples into other tasks and stories that assumed the same thing. Surface it to the user explicitly before continuing; a silent local patch over a wrong foundational assumption just relocates the bug.

**Decided (spec review, 2026-07-12): escalate after 3 failed review rounds on the same task.** Track how many correction handovers this task has already received. On the 3rd ❌ for the same task, do not emit a 4th correction handover — stop and tell the user. Two rounds of the same task failing review for different specific reasons is normal; three rounds usually means something deeper is being missed, and it's worth a human look before burning a fourth round.

## 7. Status cascade — continuous, not just at the end

Apply this at every level, as work actually completes — not once at the tail end of the whole feature:

1. Task reaches done (criteria met, tests pass, Reviewer ✅) → `work_children` on the parent story → all done? → `work_status_done` the story.
2. Story done → `work_children` on the parent feature → all done? → `work_status_done` the feature.
3. Feature done → `work_children` on the parent epic → all done? → `work_status_done` the epic.

## 8. Epic completion is manual

<!-- Decided, spec review 2026-07-12: epic close-out stays a deliberate step, not automatic -->
When an epic's cascade completes (step 3 above just fired), **do not automatically load the `delivery` skill.** Announce the completion to the user and ask whether to run delivery close-out now, in this same chat, or later, in a fresh chat (which `using-allye` routes to `delivery` normally). Either way, the choice is the user's — this skill only ever proposes it.

## 9. Never resolve ambiguity alone

Unclear assignee, no active sprint to assign into, conflicting or unexpected status on an item you didn't touch — any of these gets asked about, not guessed through. The Orchestrator's whole job is keeping the delivery state trustworthy; a guessed-through ambiguity undermines exactly that.

## 10. Memory

Search at start (§1). Save session state before ending — current position in the feature (which story/wave), what's been dispatched, what's pending review, any escalations raised. If a correction round revealed something worth remembering beyond this session (a wrong assumption, a pattern), save it as its own memory in the appropriate sector, per the `memory-protocol` skill — don't let it live only in this session's state snapshot.
```

- [ ] **Step 2: Verify**

Run: `head -6 skills/orchestrator/SKILL.md`
Expected: frontmatter shows `name: orchestrator` and a trigger-style `description:` starting with "Drives delivery of a planned feature..."

- [ ] **Step 3: Commit**

```bash
git add skills/orchestrator/SKILL.md
git commit -m "feat: add orchestrator skill (assignee, dispatch loop, correction escalation, cascade)" -- skills/orchestrator/SKILL.md
```

## Task 2: Add Orchestrator to `using-allye`'s routing

**Files:**
- Modify: `skills/using-allye/SKILL.md`

- [ ] **Step 1: Insert a row and a detection bullet**

Find this table (as it stands after Plan 3's edit):
```markdown
| User intent | Skill to load | Slug |
|-------------|---------------|------|
| Explore ideas, research before committing to scope, think out loud, no direction chosen yet | Sandbox / Discovery | `sandbox` |
| Define product requirements, create epics/features/stories | Product Planning | `allye-product-planning` |
| Plan technical tasks for a story, discuss approach | Technical Planning | `allye-technical-planning` |
| Implement code, write tests, develop features | Technical Development | `allye-technical-development` |
| Review code, check implementation quality | Technical Review | `allye-technical-review` |
| Finalize delivery, close story, update docs | Technical Delivery | `allye-technical-delivery` |
```
Replace it with (one new row inserted between Technical Planning and Technical Development, matching the Orchestrator's position in the flow):
```markdown
| User intent | Skill to load | Slug |
|-------------|---------------|------|
| Explore ideas, research before committing to scope, think out loud, no direction chosen yet | Sandbox / Discovery | `sandbox` |
| Define product requirements, create epics/features/stories | Product Planning | `allye-product-planning` |
| Plan technical tasks for a story, discuss approach | Technical Planning | `allye-technical-planning` |
| Coordinate delivery of an already-planned feature — assign work, track status, drive tasks through review | Orchestrator | `orchestrator` |
| Implement code, write tests, develop features | Technical Development | `allye-technical-development` |
| Review code, check implementation quality | Technical Review | `allye-technical-review` |
| Finalize delivery, close story, update docs | Technical Delivery | `allye-technical-delivery` |
```

Then find this line in `### How to detect the phase` (as it stands after Plan 3's edit):
```markdown
- **Technical Planning** — User has a story and wants to: break it into tasks, discuss approach, evaluate options, plan implementation
```
Insert a new bullet immediately after it:
```markdown
- **Technical Planning** — User has a story and wants to: break it into tasks, discuss approach, evaluate options, plan implementation
- **Orchestrator** — User wants to: coordinate delivery, assign work items, track story/task status, drive review for an already-planned feature
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -n "^| Coordinate delivery" skills/using-allye/SKILL.md
grep -n "^- \*\*Orchestrator\*\*" skills/using-allye/SKILL.md
grep -c '| User intent | Skill to load | Slug |' skills/using-allye/SKILL.md
```
Expected: one match each for the first two commands; the third prints `1` (table header still unduplicated).

- [ ] **Step 3: Commit**

```bash
git add skills/using-allye/SKILL.md
git commit -m "feat: route Orchestrator in using-allye's phase detection" -- skills/using-allye/SKILL.md
```

## Task 3: Register `orchestrator` in `seed/seed-skills.json`

**Files:**
- Modify: `seed/seed-skills.json`

- [ ] **Step 1: Add the entry**

```bash
jq '.skills += [{
  "name": "orchestrator",
  "slug": "orchestrator",
  "description": "Drives delivery of a planned feature — assignee, dispatch loop, correction escalation, status cascade.",
  "category": "other",
  "scope": "team",
  "source_file": "skills/orchestrator/SKILL.md",
  "supported_agents": ["claude", "opencode", "cursor", "codex", "gemini"]
}]' seed/seed-skills.json > /tmp/seed-skills.json.tmp && mv /tmp/seed-skills.json.tmp seed/seed-skills.json
```

- [ ] **Step 2: Verify**

Run:
```bash
jq empty seed/seed-skills.json && echo "VALID JSON"
jq -r '.skills[] | select(.slug=="orchestrator") | .source_file' seed/seed-skills.json
test -f "$(jq -r '.skills[] | select(.slug=="orchestrator") | .source_file' seed/seed-skills.json)" && echo "source_file exists"
```
Expected: `VALID JSON`, then `skills/orchestrator/SKILL.md`, then `source_file exists`.

- [ ] **Step 3: Commit**

```bash
git add seed/seed-skills.json
git commit -m "feat: register orchestrator skill for backend seeding" -- seed/seed-skills.json
```

## Task 4: Verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Confirm the file exists and the credit comments survived**

```bash
test -f skills/orchestrator/SKILL.md && echo "OK: skills/orchestrator/SKILL.md" || echo "FAIL"
grep -c "adapted from" skills/orchestrator/SKILL.md
grep -c "Decided" skills/orchestrator/SKILL.md
```
Expected: `OK:` line; the "adapted from" count is at least `2` (compound-engineering + BMAD); the "Decided" count is at least `2` (3-strike threshold + manual epic close-out).

- [ ] **Step 2: Confirm the 3-strike rule and manual-delivery decisions are both literally present, not paraphrased away**

```bash
grep -n "3rd\|3ª" skills/orchestrator/SKILL.md
grep -n "do not automatically load the .delivery. skill" skills/orchestrator/SKILL.md
```
Expected: both produce a match.

- [ ] **Step 3: Confirm using-allye's table and bullets weren't duplicated or broken**

```bash
grep -c "^| User intent | Skill to load | Slug |$" skills/using-allye/SKILL.md
grep -c "^### Decision table$" skills/using-allye/SKILL.md
grep -c "^### How to detect the phase$" skills/using-allye/SKILL.md
```
Expected: all three print `1`.

- [ ] **Step 4: Confirm the Orchestrator correctly references Plan 2's catalog types by their real names, not invented ones**

```bash
grep -o "story-execution\|execution-report\|correction\|technical-to-orchestration" skills/orchestrator/SKILL.md | sort -u
```
Expected: all four type names appear (technical-to-orchestration is received on start; story-execution and correction are emitted; execution-report is received in §5) — matching Plan 2's catalog exactly, no fifth/invented type name.

- [ ] **Step 5: If everything passes, this plan is complete — no commit needed for this task (verification only)**

## Self-review (writing-plans §Self-Review, performed before handing this plan off)

- **Spec coverage:** §6.4's on-start, assignee, claim, dispatch Executor, dispatch Reviewer, react-to-review (including both resolved decisions), and never-resolve-ambiguity-alone are all covered in Task 1's §1-6 and §9. §6.6's continuous cascade and manual epic close-out are covered in §7-8. Nothing in spec §6.4/§6.6 is uncovered.
- **Placeholder scan:** Task 1 writes complete, literal file content — no "TBD." Task 2's edit gives the exact before/after table and bullet text.
- **Type/name consistency:** every handover type name (`technical-to-orchestration`, `story-execution`, `execution-report`, `correction`) matches Plan 2's catalog exactly. The `reviewer` agent name matches Plan 1's rename. The `execution`/`review`/`delivery` skill names referenced match Plan 1's rename, not the pre-restructure `allye-technical-*` names.

## What comes next

5. **Phase-skill deltas** (`product-planning`, `technical-planning`, `execution`) — each gets a handover-out step wired to its specific catalog entry (`discovery-to-planning` consumed by `product-planning`; `planning-to-technical` emitted by it; `technical-to-orchestration` emitted by `technical-planning`; `story-execution`/`correction` consumed and `execution-report` emitted by `execution`). `technical-planning` also gets wired to dispatch `deep-search`/`code-analyzer`, per spec §6.3.
6. **OpenCode package rework + manifest updates** — including an Orchestrator role for OpenCode's agent-picker model, and the deferred handover-marker-detection paragraph for `manifests/{codex,cursor,gemini}`.
