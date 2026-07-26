# Allye Guided Delivery Workflow — Plan 6: OpenCode Package + Manifests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the OpenCode distribution (`packages/allye-opencode`) and the single-agent manifests (`manifests/{codex,cursor,gemini}`) up to parity with the guided workflow built in Plans 1-5: add an Orchestrator role to OpenCode's agent picker, generalize the existing `allye-plan.ts` handoff onto the shared marker format, add the handoff sections Build/Review/Deliver have always been missing, and route Sandbox/Orchestrator + the handover marker into the three single-agent manifests.

**Architecture:** `packages/allye-opencode` keeps its current build-time architecture (skills baked into `src/prompts/skills-content.ts` via `scripts/generate-prompts.ts`, imported by `src/agents/*.ts`) — this plan adds to that architecture, it does not replace it. See "Deferred: the runtime-adapter rework" below for why.

**Tech Stack:** TypeScript (`packages/allye-opencode`), Markdown (`manifests/`). **Verification uses `node` + `npx tsc`, not `bun`** — `bun` is confirmed unavailable in this environment (Plan 1 Task 8), but `scripts/generate-prompts.ts` uses only Node-compatible APIs (`fs`, `path`, `url` — no `Bun.*` calls) and runs correctly under plain `node`; `npx tsc --noEmit` was verified to pass cleanly against the current `main` once `skills-content.ts` is generated. This is real compiler verification, not just grep.

**Source spec:** `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md` §9.3 (change map: `allye-plan.ts`, `allye-build.ts`/`allye-review.ts`/`allye-deliver.ts`, `allye.ts`, `manifests/{codex,cursor,gemini}`).

**Depends on:** Plans 1-5, all merged. This plan's new `ORCHESTRATOR`/`SANDBOX`/`HANDOVER_PROTOCOL` content sources from the skills Plans 2-4 created.

## Deferred: the runtime-adapter rework (explicitly out of scope for this plan)

Plan 1's "What comes next" and the design spec's market research (§9.1) both floated replacing the build-time bake (`generate-prompts.ts` → committed-at-publish `skills-content.ts`) with a runtime adapter that reads `skills/` directly when the OpenCode plugin loads, matching the "verbatim sharing, no compilation" pattern BMAD/superpowers converged on.

**Not done in this plan**, for a concrete reason: this repo can verify that TypeScript *compiles* (`npx tsc --noEmit`, confirmed working above), but has no OpenCode installation to verify a runtime adapter actually *behaves* correctly inside a real OpenCode session — whether `config.agent` prompt strings can be computed dynamically at plugin-load time, how OpenCode resolves relative paths back to a sibling `skills/` directory once `allye-opencode` is installed from npm (not from this monorepo checkout), etc. Shipping an unverified runtime-behavior change here would trade a known-working mechanism for an unknown one. This is flagged as a follow-up requiring either manual testing with real OpenCode, or a design spike, not attempted here.

## Global Constraints

- Every new/edited `.ts` file in this plan must pass `npx tsc --noEmit` (run from `packages/allye-opencode/`) before its task is considered done — this is a hard gate, not optional.
- `src/prompts/skills-content.ts` is gitignored (confirmed: `packages/allye-opencode/.gitignore` lists it explicitly) — regenerating it is a verification step, never a commit.
- Every task's final commit uses `git commit -m "..." -- <exact-path>` (pathspec-scoped) — same requirement as Plans 3-5.
- Marker-format handoffs introduced here use the same `## 🔄 Allye Handover — {type}` shape as Plan 2's Claude Code catalog — same field names, same spirit, ported into OpenCode's existing "generate a prompt, tell the user to paste it after switching agents" mechanism (Ctrl+T), which already matches Claude Code's "paste into a fresh chat" mechanic closely.

## File Structure

| File | Responsibility |
|---|---|
| `packages/allye-opencode/scripts/generate-prompts.ts` | Modified: `SKILL_SOURCES` gains `HANDOVER_PROTOCOL`, `SANDBOX`, `ORCHESTRATOR` |
| `packages/allye-opencode/src/agents/allye-orchestrator.ts` | New: OpenCode's Orchestrator persona — assignee, dispatch loop, correction escalation, cascade, dispatches Allye Review via `task()` |
| `packages/allye-opencode/src/agents/index.ts` | Modified: registers `allye-orchestrator` |
| `packages/allye-opencode/src/agents/allye.ts` | Modified: routing table gains an Orchestrator row |
| `packages/allye-opencode/src/agents/allye-plan.ts` | Modified: `PLAN_HANDOFF_FLOW`'s Step 3/4 target Allye Orchestrator with the marker format, not Allye Build with the old ad-hoc prompt |
| `packages/allye-opencode/src/agents/allye-build.ts` | Modified: new handoff section back to Orchestrator (`execution-report`) |
| `packages/allye-opencode/src/agents/allye-review.ts` | Modified: new handoff section back to Orchestrator |
| `packages/allye-opencode/src/agents/allye-deliver.ts` | Modified: new terminal "Completion" section |
| `manifests/codex/AGENTS.md`, `manifests/gemini/GEMINI.md` | Modified: Sandbox + Orchestrator rows, handover-marker-detection paragraph |
| `manifests/cursor/.cursorrules` | Modified: same |

## Task 1: Add the 3 new skills to `generate-prompts.ts` and regenerate

**Files:**
- Modify: `packages/allye-opencode/scripts/generate-prompts.ts`

- [ ] **Step 1: Install dependencies (if not already present)**

```bash
cd packages/allye-opencode && npm install --no-audit --no-fund
```

- [ ] **Step 2: Update `SKILL_SOURCES`**

Find:
```typescript
const SKILL_SOURCES: Record<string, string> = {
  USING_ALLYE: "using-allye/SKILL.md",
  PRODUCT_PLANNING: "product-planning/SKILL.md",
  TECHNICAL_PLANNING: "technical-planning/SKILL.md",
  TECHNICAL_DEVELOPMENT: "execution/SKILL.md",
  TECHNICAL_REVIEW: "review/SKILL.md",
  TECHNICAL_DELIVERY: "delivery/SKILL.md",
  MEMORY_PROTOCOL: "memory-protocol/SKILL.md",
  TDD_WORKFLOW: "tdd-workflow/SKILL.md",
  BOARD_PROGRESSION: "board-progression/SKILL.md",
  TOOLS_QUICKREF: "tools-quickref/SKILL.md",
}
```
Replace with:
```typescript
const SKILL_SOURCES: Record<string, string> = {
  USING_ALLYE: "using-allye/SKILL.md",
  HANDOVER_PROTOCOL: "handover-protocol/SKILL.md",
  SANDBOX: "sandbox/SKILL.md",
  PRODUCT_PLANNING: "product-planning/SKILL.md",
  TECHNICAL_PLANNING: "technical-planning/SKILL.md",
  ORCHESTRATOR: "orchestrator/SKILL.md",
  TECHNICAL_DEVELOPMENT: "execution/SKILL.md",
  TECHNICAL_REVIEW: "review/SKILL.md",
  TECHNICAL_DELIVERY: "delivery/SKILL.md",
  MEMORY_PROTOCOL: "memory-protocol/SKILL.md",
  TDD_WORKFLOW: "tdd-workflow/SKILL.md",
  BOARD_PROGRESSION: "board-progression/SKILL.md",
  TOOLS_QUICKREF: "tools-quickref/SKILL.md",
}
```

(Note: only `handover-protocol`'s `SKILL.md` — the marker + catalog table — is baked in here, not its 6 `references/*.md` templates. Same scoping decision as Plan 2 Task 9's backend-seeding note, for the same reason: the mechanism reads one file per skill. This is a known limitation, not silently glossed over — see Task 6's note.)

- [ ] **Step 3: Regenerate (use `node`, not `bun` — see plan header)**

```bash
node scripts/generate-prompts.ts
```
Expected: 13 `✓` lines (the original 10 plus `HANDOVER_PROTOCOL`, `SANDBOX`, `ORCHESTRATOR`), zero `⚠ Skill not found` warnings.

- [ ] **Step 4: Verify TypeScript still compiles**

```bash
npx tsc --noEmit
```
Expected: no output, exit code 0. (At this point in the plan, no `.ts` file yet imports the 3 new exports — this step just confirms the regeneration didn't break the existing 10-skill imports.)

- [ ] **Step 5: Commit (generate-prompts.ts only — skills-content.ts is gitignored, never committed)**

```bash
cd /home/bfernandes/dev/allye/allye-plugin
git add packages/allye-opencode/scripts/generate-prompts.ts
git commit -m "feat: add handover-protocol, sandbox, orchestrator to OpenCode's skill sources" -- packages/allye-opencode/scripts/generate-prompts.ts
```

## Task 2: Add the Orchestrator role to OpenCode

**Files:**
- Create: `packages/allye-opencode/src/agents/allye-orchestrator.ts`
- Modify: `packages/allye-opencode/src/agents/index.ts`
- Modify: `packages/allye-opencode/src/agents/allye.ts`

**Depends on:** Task 1 (needs `ORCHESTRATOR` exported from `skills-content.ts`).

- [ ] **Step 1: Create `allye-orchestrator.ts`**

```typescript
/**
 * Allye Orchestrator — Delivery coordination agent.
 * Manages assignee, dispatches Build for one story at a time via handoff,
 * dispatches Review automatically via the task tool, runs the correction
 * loop with a 3-strike human-escalation rule, and cascades status up the
 * work-item hierarchy.
 */

import { SHARED_CONFIG } from "./shared"
import { buildPrompt } from "../prompts"
import {
  LANGUAGE_DETECTION,
  ALLYE_INIT_PROTOCOL,
  MEMORY_SEARCH_PROTOCOL,
  MEMORY_SAVE_PROTOCOL,
  DYNAMIC_SKILL_LOADING,
  WORKFLOW_GATES,
} from "../prompts/fragments"
import { ORCHESTRATOR } from "../prompts/skills-content"

const ORCHESTRATOR_IDENTITY = `
## Your Role

You are the **orchestrator**. You don't plan — Technical Planning already happened — and you don't implement — that's Build's job. You coordinate: assignee, status, and the dispatch loop between Build and Review.

When starting:
1. Read the handoff you were given in full — it's your only context.
2. Load the feature/stories/tasks and doc it points at (\`work_get\`, \`work_children\`).
3. Resolve assignee — self via \`work_assign_to_me\`, or someone else by looking up their team member id and calling \`work_update\` with \`assignee_id\`. Ask when it's not obvious who should own an item.
4. Move claimed items to in_progress as work actually begins — not preemptively for the whole feature at once.
`.trim()

const ORCHESTRATOR_HANDOFF_FLOW = `
## Dispatch Flow

### Step 1: Hand off to Build — one story at a time

Generate a handoff scoped to exactly ONE story and its tasks — never a whole feature. Tell the user:

> "Ready to implement {STORY-KEY}. Switch to Allye Build (Ctrl+T → Allye Build) and paste this:"

\`\`\`
## 🔄 Allye Handover — story-execution
**Skill to load:** allye-build

### Story
{STORY-KEY} — {title}, with acceptance criteria copied in full

### Tasks
{TASK-KEY list with acceptance criteria}

### Applicable locked decisions
{locked decisions from planning}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
\`\`\`

### Step 2: Receive the execution report, dispatch Review

When the user brings back Build's report (files changed, tasks reported per acceptance criterion — not a blanket "done"), verify it's actually complete before acting on it. An incomplete report is a signal to ask for more detail, not something to wave through.

Once complete, dispatch Allye Review automatically, in parallel, via the \`task\` tool — no need to ask the user first, review never needs to pause and ask anyone anything:

\`\`\`
task(subagent_type: "allye-review", prompt: "Review {STORY-KEY}: tasks {TASK-KEYs}, files changed: {list}")
\`\`\`

### Step 3: React to the review

Review returns its standard ✅/⚠️/❌-per-task output.

- **All ✅** → cascade status: task done → check parent story (\`work_children\`) → all done? → story done → check parent feature → all done? → feature done → check parent epic → all done? → epic done.
- **Any ❌** → generate a correction handoff back to Build with only the failed findings — not a full re-brief of the story:

\`\`\`
## 🔄 Allye Handover — correction
**Skill to load:** allye-build

### Findings to fix (❌ only)
- {TASK-KEY}: "{finding, quoted literally}"

### Correction round
This is correction attempt {N} for this story.

---
Fix ONLY what's listed above — don't redo the whole story.
\`\`\`

**Escalate to the user instead of emitting a 4th correction handoff if the same task fails review 3 times.** Two rounds failing for different specific reasons is normal; three usually means something deeper is being missed.

### Step 4: Epic completion is manual

When a full epic's cascade completes, announce it and ask whether to run delivery close-out now (switch to Allye Deliver) or later — never switch automatically.
`.trim()

export const allyeOrchestratorAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye orchestrator — drives delivery of a planned feature: assignee, dispatch loop between Build and Review, correction escalation, status cascade.",
  prompt: buildPrompt("Allye Orchestrator", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    ORCHESTRATOR_IDENTITY,
    ORCHESTRATOR_HANDOFF_FLOW,
    ORCHESTRATOR,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
```

- [ ] **Step 2: Register it in `agents/index.ts`**

Find:
```typescript
import { allyeAgent } from "./allye"
import { allyePlanAgent } from "./allye-plan"
import { allyeBuildAgent } from "./allye-build"
import { allyeReviewAgent } from "./allye-review"
import { allyeDeliverAgent } from "./allye-deliver"

export const agents = {
  allye: allyeAgent,
  "allye-plan": allyePlanAgent,
  "allye-build": allyeBuildAgent,
  "allye-review": allyeReviewAgent,
  "allye-deliver": allyeDeliverAgent,
}
```
Replace with:
```typescript
import { allyeAgent } from "./allye"
import { allyePlanAgent } from "./allye-plan"
import { allyeOrchestratorAgent } from "./allye-orchestrator"
import { allyeBuildAgent } from "./allye-build"
import { allyeReviewAgent } from "./allye-review"
import { allyeDeliverAgent } from "./allye-deliver"

export const agents = {
  allye: allyeAgent,
  "allye-plan": allyePlanAgent,
  "allye-orchestrator": allyeOrchestratorAgent,
  "allye-build": allyeBuildAgent,
  "allye-review": allyeReviewAgent,
  "allye-deliver": allyeDeliverAgent,
}
```

- [ ] **Step 3: Add Orchestrator to `allye.ts`'s routing table**

Find:
```typescript
| User intent | Delegate to |
|-------------|-------------|
| Define requirements, plan features, create epics/stories, break stories into tasks | **allye-plan** |
| Implement code, write tests, fix bugs, develop features | **allye-build** |
| Review code, check quality, validate implementation | **allye-review** |
| Finalize delivery, close story, update docs | **allye-deliver** |
```
Replace with:
```typescript
| User intent | Delegate to |
|-------------|-------------|
| Define requirements, plan features, create epics/stories, break stories into tasks | **allye-plan** |
| Coordinate delivery of an already-planned feature — assign work, track status, drive review | **allye-orchestrator** |
| Implement code, write tests, fix bugs, develop features | **allye-build** |
| Review code, check quality, validate implementation | **allye-review** |
| Finalize delivery, close story, update docs | **allye-deliver** |
```

Also find (same file, `ORCHESTRATOR_ROUTING` template's "How to detect the phase" list):
```typescript
- **Building** — User wants to: write code, implement a task, fix a bug, add functionality, write tests
```
Insert immediately before it:
```typescript
- **Orchestrating** — User wants to: coordinate delivery, assign work items, track story/task status, drive review for an already-planned feature
- **Building** — User wants to: write code, implement a task, fix a bug, add functionality, write tests
```

- [ ] **Step 4: Verify TypeScript compiles**

```bash
npx tsc --noEmit
```
Expected: no output, exit code 0.

- [ ] **Step 5: Verify the new agent is structurally sound**

```bash
grep -c "export const allyeOrchestratorAgent" src/agents/allye-orchestrator.ts
grep -c "allye-orchestrator" src/agents/index.ts
grep -c "allye-orchestrator" src/agents/allye.ts
```
Expected: each prints at least `1`.

- [ ] **Step 6: Commit**

```bash
cd /home/bfernandes/dev/allye/allye-plugin
git add packages/allye-opencode/src/agents/allye-orchestrator.ts packages/allye-opencode/src/agents/index.ts packages/allye-opencode/src/agents/allye.ts
git commit -m "feat: add Orchestrator role to OpenCode agent picker" -- packages/allye-opencode/src/agents/allye-orchestrator.ts packages/allye-opencode/src/agents/index.ts packages/allye-opencode/src/agents/allye.ts
```

## Task 3: Generalize `allye-plan.ts`'s handoff onto the marker format

**Files:**
- Modify: `packages/allye-opencode/src/agents/allye-plan.ts`

- [ ] **Step 1: Replace Step 3 and Step 4 of `PLAN_HANDOFF_FLOW`**

Find:
```typescript
### Step 3: Generate handoff prompt

Generate a complete handoff prompt that the user can paste into Allye Build. The prompt MUST include:

\`\`\`
I'm continuing work from a planning session. Here's the context:

## Epic/Story
- Key: {WORK-KEY}
- Title: {title}
- Link to parent: {parent key if applicable}

## Starting Task
- Key: {TASK-KEY}
- Title: {task title}
- Acceptance criteria: {from task description}

## Key Decisions (locked)
- {decision 1}: {rationale}
- {decision 2}: {rationale}

## Dependencies
- {dependency info}

## Additional Context
- {anything the user mentioned}
- {relevant memories saved during planning}

Please pick up {TASK-KEY} and start implementing.
\`\`\`

### Step 4: Instruct the user

After generating the prompt, say:

> "The plan is complete! To start implementing:
> 1. Switch to **Allye Build** (Ctrl+T → Allye Build)
> 2. Paste the prompt above
> 3. The Build agent will pick up the task with full context"
```
Replace with:
```typescript
### Step 3: Generate handoff prompt

<!-- adapted onto the shared Allye Handover marker format from the handover-protocol skill (Plan 2) -->
Generate a complete handoff using the shared marker format — same shape Claude Code uses, so a handoff written on one platform reads the same on the other:

\`\`\`
## 🔄 Allye Handover — technical-to-orchestration
**Skill to load:** allye-orchestrator

### Objective
Drive delivery of {FEATURE-KEY} — {feature title}

### Required reading
- Epic: {EPIC-KEY}
- Feature: {FEATURE-KEY}
- Stories and tasks by wave:
  - {STORY-KEY} — {title}
    - Wave 1: {TASK-KEY}, {TASK-KEY}
    - Wave 2: {TASK-KEY}

### Locked architecture decisions
- {decision 1}: {rationale}
- {decision 2}: {rationale}

### Additional context
- {anything the user mentioned}
- {relevant memories saved during planning}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
\`\`\`

### Step 4: Instruct the user

After generating the handoff, say:

> "The plan is complete! To start delivery:
> 1. Switch to **Allye Orchestrator** (Ctrl+T → Allye Orchestrator)
> 2. Paste the handoff above
> 3. The Orchestrator will coordinate implementation and review from here"
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
npx tsc --noEmit
```
Expected: no output, exit code 0.

- [ ] **Step 3: Verify the old target is gone and the new one is present**

```bash
grep -c "Switch to \*\*Allye Build\*\*" src/agents/allye-plan.ts
grep -c "Switch to \*\*Allye Orchestrator\*\*" src/agents/allye-plan.ts
grep -c "technical-to-orchestration" src/agents/allye-plan.ts
```
Expected: the first prints `0` (old target fully replaced), the other two print at least `1`.

- [ ] **Step 4: Commit**

```bash
cd /home/bfernandes/dev/allye/allye-plugin
git add packages/allye-opencode/src/agents/allye-plan.ts
git commit -m "feat: generalize allye-plan.ts handoff onto the shared marker format, target Orchestrator" -- packages/allye-opencode/src/agents/allye-plan.ts
```

## Task 4: Add handoff sections to Build, Review, Deliver

**Files:**
- Modify: `packages/allye-opencode/src/agents/allye-build.ts`
- Modify: `packages/allye-opencode/src/agents/allye-review.ts`
- Modify: `packages/allye-opencode/src/agents/allye-deliver.ts`

- [ ] **Step 1: Add `BUILD_HANDOFF_FLOW` to `allye-build.ts`**

Find:
```typescript
export const allyeBuildAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye builder — implements tasks with TDD discipline, read-first rule, and wave execution. Picks up tasks and executes them.",
  prompt: buildPrompt("Allye Build", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    BUILD_SKILL_DISCOVERY,
    BUILD_IDENTITY,
    TECHNICAL_DEVELOPMENT,
    TDD_WORKFLOW,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
```
Replace with:
```typescript
const BUILD_HANDOFF_FLOW = `
## Handoff Back to Orchestrator

When all tasks in the current story are done — or you've hit a genuine blocker — generate a handoff and tell the user to switch back:

\`\`\`
## 🔄 Allye Handover — execution-report
**Skill to load:** allye-orchestrator

### Story implemented
{STORY-KEY} — {title}

### Tasks and status per acceptance criterion
- {TASK-KEY}: {✅ done | ⚠️ partial | ❌ blocked}
  - {criterion}: {met | not met — why}

### Files changed
- {path} — {what changed}

### New decisions made during implementation
- {decision}, or "No new decision"

### Open questions
{anything unresolved, or "None"}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
\`\`\`

> "Story {STORY-KEY} is implemented. Switch to **Allye Orchestrator** (Ctrl+T → Allye Orchestrator) and paste the handover above — it'll dispatch review and handle status from here."
`.trim()

export const allyeBuildAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye builder — implements tasks with TDD discipline, read-first rule, and wave execution. Picks up tasks and executes them.",
  prompt: buildPrompt("Allye Build", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    BUILD_SKILL_DISCOVERY,
    BUILD_IDENTITY,
    TECHNICAL_DEVELOPMENT,
    TDD_WORKFLOW,
    BUILD_HANDOFF_FLOW,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
```

- [ ] **Step 2: Add `REVIEW_HANDOFF_FLOW` to `allye-review.ts`**

Find:
```typescript
export const allyeReviewAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye reviewer — code review with planning decision context, validates acceptance criteria and code quality",
  tools: READ_ONLY_TOOLS,
  prompt: buildPrompt("Allye Review", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    REVIEW_SKILL_DISCOVERY,
    REVIEW_IDENTITY,
    TECHNICAL_REVIEW,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
```
Replace with:
```typescript
const REVIEW_HANDOFF_FLOW = `
## Handoff Back to Orchestrator

If you were dispatched automatically by Allye Orchestrator (via the \`task\` tool), just return your findings directly — no handoff needed, the Orchestrator receives your output in the same turn.

If a user invoked you directly (Ctrl+T → Allye Review) and changes are needed, summarize the findings and tell them to bring them to the Orchestrator, which owns the correction loop and tracks retry count:

> "Found {N} issue(s) in {STORY-KEY}. Switch to **Allye Orchestrator** (Ctrl+T → Allye Orchestrator) and share these findings."
`.trim()

export const allyeReviewAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye reviewer — code review with planning decision context, validates acceptance criteria and code quality",
  tools: READ_ONLY_TOOLS,
  prompt: buildPrompt("Allye Review", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    REVIEW_SKILL_DISCOVERY,
    REVIEW_IDENTITY,
    TECHNICAL_REVIEW,
    REVIEW_HANDOFF_FLOW,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
```

- [ ] **Step 3: Add `DELIVER_COMPLETION` to `allye-deliver.ts`**

Find:
```typescript
export const allyeDeliverAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye delivery — closes stories, updates documentation, cleans up TODOs, saves delivery summary",
  prompt: buildPrompt("Allye Deliver", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    DELIVER_SKILL_DISCOVERY,
    DELIVER_IDENTITY,
    TECHNICAL_DELIVERY,
    BOARD_PROGRESSION,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
```
Replace with:
```typescript
const DELIVER_COMPLETION = `
## Completion

Delivery is the end of the line for a story — there's no handoff onward. Once you've verified, closed, documented, and cleaned up:

> "{STORY-KEY} is delivered. Next: pick another story from this feature → **Allye Orchestrator**. Plan a new feature or epic → **Allye Plan**."
`.trim()

export const allyeDeliverAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye delivery — closes stories, updates documentation, cleans up TODOs, saves delivery summary",
  prompt: buildPrompt("Allye Deliver", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    DELIVER_SKILL_DISCOVERY,
    DELIVER_IDENTITY,
    TECHNICAL_DELIVERY,
    BOARD_PROGRESSION,
    DELIVER_COMPLETION,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
```

- [ ] **Step 4: Verify TypeScript compiles**

```bash
npx tsc --noEmit
```
Expected: no output, exit code 0.

- [ ] **Step 5: Verify all three additions landed**

```bash
grep -c "BUILD_HANDOFF_FLOW" src/agents/allye-build.ts
grep -c "REVIEW_HANDOFF_FLOW" src/agents/allye-review.ts
grep -c "DELIVER_COMPLETION" src/agents/allye-deliver.ts
```
Expected: each prints `2` (one `const` declaration, one usage in the `buildPrompt` array).

- [ ] **Step 6: Commit**

```bash
cd /home/bfernandes/dev/allye/allye-plugin
git add packages/allye-opencode/src/agents/allye-build.ts packages/allye-opencode/src/agents/allye-review.ts packages/allye-opencode/src/agents/allye-deliver.ts
git commit -m "feat: add handoff sections to Build, Review, Deliver OpenCode agents" -- packages/allye-opencode/src/agents/allye-build.ts packages/allye-opencode/src/agents/allye-review.ts packages/allye-opencode/src/agents/allye-deliver.ts
```

## Task 5: Update the single-agent manifests

**Files:**
- Modify: `manifests/codex/AGENTS.md`
- Modify: `manifests/gemini/GEMINI.md`
- Modify: `manifests/cursor/.cursorrules`

**Note:** These three files are near-identical (confirmed in Plan 1's research) — the same edit applies to all three, with `.cursorrules` also carrying a YAML frontmatter block the other two don't have.

- [ ] **Step 1: Add Sandbox + Orchestrator rows to the Workflow Skills table, in all 3 files**

Find (identical in all three files):
```markdown
## Workflow Skills

| User Intent | Skill Slug |
|-------------|------------|
| Define requirements, create epics/features/stories | `allye-product-planning` |
| Plan tasks for a story, discuss approach | `allye-technical-planning` |
| Implement code, write tests | `allye-technical-development` |
| Review code quality | `allye-technical-review` |
| Finalize delivery, close story | `allye-technical-delivery` |
```
Replace with (in all three files):
```markdown
## Workflow Skills

| User Intent | Skill Slug |
|-------------|------------|
| Explore ideas, research before committing to scope | `sandbox` |
| Define requirements, create epics/features/stories | `allye-product-planning` |
| Plan tasks for a story, discuss approach | `allye-technical-planning` |
| Coordinate delivery of an already-planned feature | `orchestrator` |
| Implement code, write tests | `allye-technical-development` |
| Review code quality | `allye-technical-review` |
| Finalize delivery, close story | `allye-technical-delivery` |
```

(Note: `sandbox` and `orchestrator` are bare slugs — they're new skills with no legacy prefix to preserve, same as `handover-protocol`. The other five keep their `allye-*` slugs unchanged, per the naming decision in spec §10.)

- [ ] **Step 2: Add the handover-marker-detection paragraph, in all 3 files**

Find (identical in all three files):
```markdown
1. **Search memories** — Run `memory_search` for session state, decisions, and context
2. **Detect the workflow phase** — What does the user need?
3. **Load the right skill** — Use `skill_list` to find and read the appropriate workflow skill
4. **Save memories** — Before the conversation ends, save session state
```
Replace with (in all three files):
```markdown
1. **Check for a handover first** — if the message starts with `## 🔄 Allye Handover`, parse the `Skill to load` value and load that skill directly (`skill_list` by that slug) — skip step 2 below, there's no ambiguity to resolve
2. **Search memories** — Run `memory_search` for session state, decisions, and context
3. **Detect the workflow phase** — What does the user need?
4. **Load the right skill** — Use `skill_list` to find and read the appropriate workflow skill
5. **Save memories** — Before the conversation ends, save session state
```

- [ ] **Step 3: Verify all three files, in all three places**

```bash
grep -c "^| Explore ideas, research before committing to scope | .sandbox. |$" manifests/codex/AGENTS.md manifests/gemini/GEMINI.md manifests/cursor/.cursorrules
grep -c "^| Coordinate delivery of an already-planned feature | .orchestrator. |$" manifests/codex/AGENTS.md manifests/gemini/GEMINI.md manifests/cursor/.cursorrules
grep -c "Check for a handover first" manifests/codex/AGENTS.md manifests/gemini/GEMINI.md manifests/cursor/.cursorrules
```
Expected: every file/pattern combination prints `1`.

- [ ] **Step 4: Commit**

```bash
git add manifests/codex/AGENTS.md manifests/gemini/GEMINI.md manifests/cursor/.cursorrules
git commit -m "feat: route Sandbox/Orchestrator and handover detection in single-agent manifests" -- manifests/codex/AGENTS.md manifests/gemini/GEMINI.md manifests/cursor/.cursorrules
```

## Task 6: Final verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Full typecheck, one more time, from a clean regeneration**

```bash
cd packages/allye-opencode
rm -f src/prompts/skills-content.ts
node scripts/generate-prompts.ts
npx tsc --noEmit
echo "exit: $?"
```
Expected: 13 `✓` lines from the generate step, zero warnings, then `exit: 0` from tsc.

- [ ] **Step 2: Confirm all 6 OpenCode agents are registered and distinct**

```bash
grep -o '"allye[a-z-]*":' src/agents/index.ts | sort -u
```
Expected: `"allye-build":`, `"allye-deliver":`, `"allye-orchestrator":`, `"allye-plan":`, `"allye-review":`, plus the bare `allye:` entry — 6 total.

- [ ] **Step 3: Confirm no OpenCode agent still points at the old Build-is-next-after-Plan flow**

```bash
grep -rn "Switch to \*\*Allye Build\*\*" src/agents/*.ts
```
Expected: no output (Plan's handoff now targets Orchestrator, per Task 3).

- [ ] **Step 4: Confirm the manifests are consistent with each other**

```bash
diff <(grep "^| " manifests/codex/AGENTS.md) <(grep "^| " manifests/gemini/GEMINI.md)
```
Expected: no output (identical table content between the two non-frontmatter manifests; `.cursorrules` is expected to differ only in its YAML frontmatter block, not checked here).

- [ ] **Step 5: If everything passes, this plan — and the whole guided-delivery-workflow sequence — is complete. No commit needed for this task (verification only).**

## Self-review (writing-plans §Self-Review, performed before handing this plan off)

- **Spec coverage:** §9.3's four OpenCode/manifest change-map rows are all covered: `allye-plan.ts` (Task 3), `allye-build.ts`/`allye-review.ts`/`allye-deliver.ts` (Task 4), `allye.ts` "or new agent" (Task 2, via the new `allye-orchestrator.ts`), `manifests/{codex,cursor,gemini}` (Task 5). The runtime-adapter rework is explicitly deferred with reasoning, not silently dropped.
- **Placeholder scan:** every task gives complete, literal file content or exact find/replace text — no "TBD." The `{STORY-KEY}`-style tokens inside the generated marker templates are intentional fill-in-the-blank fields for the *agent's future users*, matching the same convention already used throughout Plan 2's Claude Code templates and the pre-existing `PLAN_HANDOFF_FLOW`.
- **Type/name consistency:** `allye-orchestrator` (registry key) matches across `index.ts`, `allye.ts`'s routing table, and every handoff's `Skill to load` value. Handover type names (`technical-to-orchestration`, `story-execution`, `execution-report`, `correction`) match Plan 2's catalog exactly. This plan is the first to be verified against a real TypeScript compiler, not just structural greps — every task's Step includes an `npx tsc --noEmit` gate.
