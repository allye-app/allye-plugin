# Allye Guided Delivery Workflow — Plan 2: Handover Catalog

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `handover-protocol` skill — the shared contract every future phase skill (Sandbox, Planning, Technical Planning, Orchestrator, Executor) will reference when it hands off to the next chat — and wire the auto-detection step into `using-allye` so a pasted handover routes to the right skill without heuristic guessing.

**Architecture:** One skill, `skills/handover-protocol/`, following the progressive-disclosure convention identified in the design spec's market research (lean `SKILL.md` + `references/<type>.md` per type). Six handover types, each with its own objective and field set — not one generic template with a "payload" appendix. `using-allye` gets a new detection step, checked before its existing phase-heuristic table.

**Tech Stack:** Markdown only (no code in this plan).

**Source spec:** `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md` §5 (The Handover Catalog), §7 (Adaptation sources — humanlayer `create_handoff`/`resume_handoff`, compound-engineering artifact contracts).

**Depends on:** Plan 1 (foundational restructure) — merged. This plan targets the renamed skill names (`product-planning`, `technical-planning`, `execution`) that Plan 1 produced.

## Global Constraints

- A handover is **chat text only** — this plan never creates a mechanism that saves handover text as a memory or file. The Allye doc/work items a handover references are the durable record.
- Every handover type gets its **own** field set — no shared generic template beyond the one-line marker + closing reminder in §1 below.
- Reviewer never receives a handover — it's dispatched via the `Agent` tool with a constructed prompt, not by paste. None of the 6 types target it.
- The skills this plan's handovers point at (`sandbox`, `orchestrator`) **do not exist yet** (Plans 3-4). Write the templates now — they're the contract those future skills will honor — but `using-allye`'s routing table is NOT updated with a Sandbox row in this plan (that's Plan 3's job, once the skill exists to route to).
- Every adapted section carries a one-line credit comment, per spec §7's rule of thumb.
- Skill frontmatter `description` must read as an explicit trigger condition ("Use when…"), per the naming principle decided in spec review (§10).

## File Structure

| File | Responsibility |
|---|---|
| `skills/handover-protocol/SKILL.md` | The shared marker format, the 6-type catalog table (links to `references/`), and the general writing discipline (completeness, no vague pointers) |
| `skills/handover-protocol/references/discovery-to-planning.md` | Sandbox → Planning template |
| `skills/handover-protocol/references/planning-to-technical.md` | Planning → Technical Planning template |
| `skills/handover-protocol/references/technical-to-orchestration.md` | Technical Planning → Orchestrator template |
| `skills/handover-protocol/references/story-execution.md` | Orchestrator → Executor template |
| `skills/handover-protocol/references/execution-report.md` | Executor → Orchestrator template |
| `skills/handover-protocol/references/correction.md` | Orchestrator → Executor (correction loop) template |
| `skills/using-allye/SKILL.md` | Modified: new detection step ahead of the existing phase-heuristic table |
| `seed/seed-skills.json` | Modified: new `handover-protocol` entry (see Task 9's scoping note — seeds the marker + catalog only, not the 6 full templates; flagged as an open question) |

## Task 1: Create `skills/handover-protocol/SKILL.md`

**Files:**
- Create: `skills/handover-protocol/SKILL.md`

**Interfaces:**
- Produces: the shared marker format and catalog table every other task in this plan (and every future phase-skill plan) reads

- [ ] **Step 1: Create the directory and write the file**

```bash
mkdir -p skills/handover-protocol/references
```

Write `skills/handover-protocol/SKILL.md`:

```markdown
---
name: handover-protocol
description: The shared contract for handing off context between Allye workflow phases as copy-pasted chat text. Use when a phase skill is ending and needs to brief a fresh chat for the next phase (Planning, Technical Planning, Orchestrator, Executor), or when a fresh chat opens with a pasted handover and needs to detect which skill to load.
version: "1.0"
category: methodology
---

# Handover Protocol

A handover is how context moves between Allye workflow phases without carrying a chat's full history forward. Each phase runs in its own fresh, lean-context conversation; when it finishes, it emits a handover — a block of chat text the user reads, approves, and pastes as the first message of the next chat. The next chat's bootstrap detects the marker and loads the right skill automatically.

**A handover is never saved as a memory or a file.** The Allye doc and work items it references are the durable record — the handover text itself is a disposable transport vehicle, copied by hand in both directions (including Orchestrator ↔ Executor's correction loop).

<!-- adapted from humanlayer/humanlayer create_handoff/resume_handoff (Apache-2.0) — the discipline that a handoff must be complete enough that the receiving chat needs nothing else -->

## 1. The shared marker

Every handover starts with the same one-line marker and ends with the same reminder. Everything between them is specific to the handover's type — see §2.

```markdown
## 🔄 Allye Handover — {type}
**Skill to load:** {skill-slug}

...type-specific body — see references/{type}.md...

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```

The bootstrap skill (`using-allye`) scans the first message of every fresh conversation for the `## 🔄 Allye Handover` line. When found, it parses `{type}` and `Skill to load`, loads that skill directly, and skips its own phase-detection heuristic. See `using-allye`'s "Handover detection" step.

## 2. The catalog

Six types. Each is a distinct handoff with its own objective and field set — not a generic form filled in differently. Full templates live in `references/`.

| Type | Transition | Objective | Template |
|---|---|---|---|
| `discovery-to-planning` | Sandbox → Planning | Turn the approved direction into a deliverable structure | `references/discovery-to-planning.md` |
| `planning-to-technical` | Planning → Tech Planning | Technically detail the approved squares | `references/planning-to-technical.md` |
| `technical-to-orchestration` | Tech Planning → Orchestrator | Drive delivery of the planned feature | `references/technical-to-orchestration.md` |
| `story-execution` | Orchestrator → Executor | Implement exactly one story | `references/story-execution.md` |
| `execution-report` | Executor → Orchestrator | Return the implementation result | `references/execution-report.md` |
| `correction` | Orchestrator → Executor | Fix specific review findings | `references/correction.md` |

**Reviewer never receives a handover.** It's the one role invoked via the `Agent` tool with a constructed prompt (story + tasks + files changed), dispatched by the Orchestrator — not by a pasted handover.

## 3. Writing a good handover (mandatory checklist)

<!-- adapted from humanlayer/humanlayer create_handoff (Apache-2.0) and EveryInc/compound-engineering-plugin artifact_readiness contracts (MIT) -->

Before emitting any handover, confirm:

- **Concrete keys, not vague pointers.** "The story we discussed" is not acceptable — write the actual `STORY-KEY`. The receiving chat has zero memory of this conversation.
- **Locked decisions are carried forward, verbatim.** If a decision was locked in this phase, restate it in the handover — don't make the next chat re-derive or, worse, re-litigate it.
- **Scope matches the type.** `story-execution` carries exactly one story; `correction` carries only the failed findings, not the whole story again. Padding a handover with everything "just in case" defeats the purpose of a lean next chat.
- **The reminder line is never dropped.** Every handover ends with the "stop and ask" line — it's the single most important sentence in this whole protocol.

## 4. Auto-detection (implemented in `using-allye`)

Detection logic lives in `using-allye`'s bootstrap (checked before its phase-detection table), not duplicated here — see `skills/using-allye/SKILL.md` §2. This skill defines the *contract*; `using-allye` implements the *routing*.
```

- [ ] **Step 2: Verify frontmatter and structure**

Run:
```bash
head -6 skills/handover-protocol/SKILL.md
test -d skills/handover-protocol/references && echo "references/ dir exists"
```
Expected: frontmatter shows `name: handover-protocol` and a trigger-style `description:`; `references/ dir exists` printed.

- [ ] **Step 3: Commit**

```bash
git add skills/handover-protocol/SKILL.md
git commit -m "feat: add handover-protocol skill (marker spec + 6-type catalog)"
```

## Task 2: Create `references/discovery-to-planning.md`

**Files:**
- Create: `skills/handover-protocol/references/discovery-to-planning.md`

- [ ] **Step 1: Write the file**

```markdown
# Handover: discovery-to-planning

**Emitted by:** `sandbox` (once approved by the user)
**Received by:** `product-planning`
**Objective:** Turn the direction approved during Sandbox into a deliverable structure (squares/sub-squares → Epic/Feature/Story).

## Before emitting, confirm

- A Discovery Doc was created in Allye (`doc_create`, location confirmed with the user against `doc_full_tree`) — this handover references it, it does not duplicate its content.
- Every path that was explored and abandoned is listed with *why* — the next chat should never accidentally re-propose a rejected direction.
- Research findings (if any) are summarized with enough detail to act on, not just "found some stuff."

## Template

```markdown
## 🔄 Allye Handover — discovery-to-planning
**Skill to load:** product-planning

### Objective
{one sentence: which product/objective is being planned}

### Discovery Doc
- Title: {doc title}
- Reference in Allye: {doc id or path in the tree}

### Approved direction
{synthesis of what was decided in Sandbox — what and why}

### Paths explored and rejected
- {path A} — rejected because {reason}
- {path B} — rejected because {reason}

### Research findings
{summary of what deep-search / code-analyzer brought back, with source — "No research was done" if none}

### Prototypes
{reference to generated artifacts, or "No prototype was made"}

### Additional context
{anything else the next chat needs to know}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
```

- [ ] **Step 2: Verify**

Run: `test -f skills/handover-protocol/references/discovery-to-planning.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/handover-protocol/references/discovery-to-planning.md
git commit -m "feat: add discovery-to-planning handover template"
```

## Task 3: Create `references/planning-to-technical.md`

**Files:**
- Create: `skills/handover-protocol/references/planning-to-technical.md`

- [ ] **Step 1: Write the file**

```markdown
# Handover: planning-to-technical

**Emitted by:** `product-planning`
**Received by:** `technical-planning`
**Objective:** Technically detail the squares (Features) and sub-squares (Stories) approved in the business phase.

## Before emitting, confirm

- Every Epic/Feature/Story key is real (created via `work_create`/`work_bulk_create` or found via `work_list`) — never a placeholder key.
- Reused items and newly created items are explicitly distinguished — the next chat should never have to guess which is which.
- Every locked business decision from the Discussion is restated here, not just implied by the work item descriptions.

## Template

```markdown
## 🔄 Allye Handover — planning-to-technical
**Skill to load:** technical-planning

### Objective
{which story or set of stories will be technically detailed now}

### Required reading
- Epic: {KEY} — {title} ({reused | created})
- Feature(s): {KEY} — {title} ({reused | created})
- Story(ies) to plan now: {KEY} — {title} ({reused | created})

### Locked business decisions
- {decision 1} — {rationale}
- {decision 2} — {rationale}

### Prototypes
{reference, or "No prototype was made"}

### Additional context
{}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
```

- [ ] **Step 2: Verify**

Run: `test -f skills/handover-protocol/references/planning-to-technical.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/handover-protocol/references/planning-to-technical.md
git commit -m "feat: add planning-to-technical handover template"
```

## Task 4: Create `references/technical-to-orchestration.md`

**Files:**
- Create: `skills/handover-protocol/references/technical-to-orchestration.md`

- [ ] **Step 1: Write the file**

```markdown
# Handover: technical-to-orchestration

**Emitted by:** `technical-planning`
**Received by:** `orchestrator`
**Objective:** Drive delivery of the planned feature — this is the most "loaded" handover: the Orchestrator has no business or architecture context beyond what's here.

## Before emitting, confirm

- The full reading list is spelled out — doc, epic, feature, every story, every task, grouped by wave. "Read the feature" is not acceptable; list the actual keys.
- Every locked architecture/stack decision is restated — the Orchestrator must never re-open these while dispatching Executor.
- Wave structure matches what Technical Planning actually produced (don't invent an ordering here — copy it).

## Template

```markdown
## 🔄 Allye Handover — technical-to-orchestration
**Skill to load:** orchestrator

### Objective
Drive delivery of {FEATURE-KEY} — {feature title}

### Required reading
- Doc: {title and reference, or "No additional doc"}
- Epic: {EPIC-KEY}
- Feature: {FEATURE-KEY}
- Stories and tasks by wave:
  - {STORY-KEY} — {title}
    - Wave 1: {TASK-KEY}, {TASK-KEY}
    - Wave 2: {TASK-KEY}
  - {STORY-KEY} — {title}
    - Wave 1: {TASK-KEY}

### Locked architecture decisions
- {decision} — {rationale}
- {decision} — {rationale}

### Additional context
{}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
```

- [ ] **Step 2: Verify**

Run: `test -f skills/handover-protocol/references/technical-to-orchestration.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/handover-protocol/references/technical-to-orchestration.md
git commit -m "feat: add technical-to-orchestration handover template"
```

## Task 5: Create `references/story-execution.md`

**Files:**
- Create: `skills/handover-protocol/references/story-execution.md`

- [ ] **Step 1: Write the file**

```markdown
# Handover: story-execution

**Emitted by:** `orchestrator`
**Received by:** `execution`
**Objective:** Implement exactly **one** story — never a whole feature. This is the scoping rule the whole Orchestrator/Executor loop depends on.

## Before emitting, confirm

- Exactly one story is named — if the Orchestrator is tempted to hand off two stories "to save a round trip," it must not; that's a feature-level handover in disguise.
- Every task under that story is listed with its acceptance criteria copied in (not just linked) — the Executor's chat has no other context.
- Applicable code standards were discovered (`skill_list`) and are named here, not left for the Executor to rediscover.

## Template

```markdown
## 🔄 Allye Handover — story-execution
**Skill to load:** execution

### Objective
Implement {STORY-KEY} — {story title}

### Story
- Key: {STORY-KEY}
- Acceptance criteria: {copied from the story description}

### Tasks (nesta wave)
- {TASK-KEY} — {title} — {summarized acceptance criteria}
- {TASK-KEY} — {title} — {summarized acceptance criteria}

### Applicable locked decisions
- {decision} — {rationale}

### Applicable code standards
{conventions discovered via skill_list that must be followed, or "No team standard found — follow existing conventions in the code"}

### TDD expectation
{whether Red-Green-Refactor applies and why, or why it doesn't}

---
Read ONLY this story and these tasks — nothing more. If anything is unclear, STOP and ask — don't proceed on a guess.
```
```

- [ ] **Step 2: Verify**

Run: `test -f skills/handover-protocol/references/story-execution.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/handover-protocol/references/story-execution.md
git commit -m "feat: add story-execution handover template"
```

## Task 6: Create `references/execution-report.md`

**Files:**
- Create: `skills/handover-protocol/references/execution-report.md`

- [ ] **Step 1: Write the file**

```markdown
# Handover: execution-report

**Emitted by:** `execution`
**Received by:** `orchestrator`
**Objective:** Return the implementation result — what the Orchestrator uses to decide whether to dispatch the Reviewer or cascade status right away.

## Before emitting, confirm

- Every task's status is reported per acceptance criterion, not as a blanket "done" — the Orchestrator and the eventual Reviewer both need this granularity.
- Files changed are listed explicitly (not "various files") — the Reviewer dispatch depends on this list.
- Open questions are surfaced here rather than silently assumed away — this is the Executor's last chance to flag uncertainty before the chat ends.

## Template

```markdown
## 🔄 Allye Handover — execution-report
**Skill to load:** orchestrator

### Story implemented
{STORY-KEY} — {title}

### Tasks and status per acceptance criterion
- {TASK-KEY}: {✅ done | ⚠️ partial | ❌ blocked}
  - {criterion 1}: {met | not met — why}
  - {criterion 2}: {met | not met — why}

### Files changed
- {path} — {what changed}
- {path} — {what changed}

### Tests added
{which, what they cover, or "No test was needed — reason"}

### New decisions made during implementation
- {decision} — {rationale}, or "No new decision"

### Open questions
{anything that stayed unanswered and needs a human decision, or "None"}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
```

- [ ] **Step 2: Verify**

Run: `test -f skills/handover-protocol/references/execution-report.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/handover-protocol/references/execution-report.md
git commit -m "feat: add execution-report handover template"
```

## Task 7: Create `references/correction.md`

**Files:**
- Create: `skills/handover-protocol/references/correction.md`

- [ ] **Step 1: Write the file**

```markdown
# Handover: correction

**Emitted by:** `orchestrator`
**Received by:** `execution` (the same Executor chat/session that produced the original implementation, when possible)
**Objective:** Fix specific review findings — this handover is deliberately narrow. It never re-briefs the whole story; that would defeat the point of a lean, targeted correction pass.

## Before emitting, confirm

- Only the ❌ findings are included — ✅ and ⚠️ items are not corrections, don't pad this handover with them.
- The correction round number is tracked — per spec §6.4, the Orchestrator escalates to the human after the **3rd** failed round on the same task instead of emitting a 4th correction handover.
- Each finding is quoted from the Reviewer's actual output, not paraphrased — paraphrasing risks losing precision about what exactly needs to change.

## Template

```markdown
## 🔄 Allye Handover — correction
**Skill to load:** execution

### Objective
Fix the review findings below in {STORY-KEY} — nothing more.

### Findings to fix (❌ only)
- {TASK-KEY}: "{reviewer finding, quoted literally}"
- {TASK-KEY}: "{reviewer finding, quoted literally}"

### Correction round
This is correction attempt {N} for this story.
{If N equals 3, the Orchestrator shouldn't be emitting this handover — it should have escalated to the user instead. See skills/orchestrator.}

---
Fix ONLY what's listed above — don't redo the whole story. If anything is unclear, STOP and ask — don't proceed on a guess.
```
```

- [ ] **Step 2: Verify**

Run: `test -f skills/handover-protocol/references/correction.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/handover-protocol/references/correction.md
git commit -m "feat: add correction handover template"
```

## Task 8: Wire auto-detection into `using-allye`

**Files:**
- Modify: `skills/using-allye/SKILL.md`

**Interfaces:**
- Consumes: the marker format defined in `skills/handover-protocol/SKILL.md` §1
- Produces: a new "Handover detection" subsection under `## 2. Skill Routing`, checked before the existing "Decision table"

- [ ] **Step 1: Insert the new subsection**

In `skills/using-allye/SKILL.md`, immediately after this existing text (currently lines 79-81):
```markdown
## 2. Skill Routing

Detect what the user needs and load the right skill. Skills are loaded on-demand — do NOT load all skills at once.
```
Insert a new subsection, so it reads:
```markdown
## 2. Skill Routing

Detect what the user needs and load the right skill. Skills are loaded on-demand — do NOT load all skills at once.

### Handover detection (check this FIRST)

Before running the phase-detection heuristic below, check whether the user's first message contains a `## 🔄 Allye Handover` block (see the `handover-protocol` skill for the full format). If it does:

1. Parse the `{type}` from the marker line and the `Skill to load` value.
2. Load that skill directly via `skill_list`/`skill_get` — skip the heuristic decision table entirely, there's no ambiguity to resolve.
3. Treat every field in the handover as authoritative context for this session — locked decisions in particular are non-negotiable unless the user explicitly reopens them.

If no handover marker is present, fall through to the decision table below as before.

### Decision table
```
(The existing `### Decision table` heading and everything below it — the table itself, "How to detect the phase," "How to load a skill," "When no skill matches" — is unchanged. Only the new subsection above is inserted.)

- [ ] **Step 2: Verify**

Run:
```bash
grep -n "Handover detection" skills/using-allye/SKILL.md
grep -c "^### Decision table$" skills/using-allye/SKILL.md
```
Expected: the first command shows the new heading; the second prints `1` (the original table heading still exists, exactly once, unduplicated).

- [ ] **Step 3: Commit**

```bash
git add skills/using-allye/SKILL.md
git commit -m "feat: add handover auto-detection step to using-allye bootstrap"
```

## Task 9: Register `handover-protocol` in `seed/seed-skills.json`

**Files:**
- Modify: `seed/seed-skills.json`

**Scoping note (read before implementing):** `handover-protocol` is the first Allye skill to use the `SKILL.md` + `references/` progressive-disclosure structure. The existing seeding mechanism (`install.sh` reads one `source_file`, pushes its raw content to the Allye backend) only understands single-file skills — non-Claude-Code platforms (OpenCode, Cursor, Codex, Gemini) fetch skill content from the backend by slug, not from the local `references/` files. This plan seeds **only `SKILL.md`'s content** (the marker format + catalog table + writing checklist) — non-Claude-Code platforms will see the catalog and can construct a handover from its field descriptions, but won't get the full literal templates from `references/`. Whether to also flatten/merge the 6 templates into the seeded content (or build a different mechanism) is an **open question for the next spec review**, not resolved in this plan.

- [ ] **Step 1: Add the new entry**

```bash
jq '.skills += [{
  "name": "handover-protocol",
  "slug": "handover-protocol",
  "description": "The shared contract for handing off context between Allye workflow phases as copy-pasted chat text.",
  "category": "other",
  "scope": "team",
  "source_file": "skills/handover-protocol/SKILL.md",
  "supported_agents": ["claude", "opencode", "cursor", "codex", "gemini"]
}]' seed/seed-skills.json > /tmp/seed-skills.json.tmp && mv /tmp/seed-skills.json.tmp seed/seed-skills.json
```

(Note: unlike the 10 renamed skills, `handover-protocol` is new — its slug is bare, `handover-protocol`, no `allye-` prefix, since there's no legacy identifier to preserve for a skill that didn't exist before this plan.)

- [ ] **Step 2: Verify**

Run:
```bash
jq empty seed/seed-skills.json && echo "VALID JSON"
jq -r '.skills[] | select(.slug=="handover-protocol") | .source_file' seed/seed-skills.json
test -f "$(jq -r '.skills[] | select(.slug=="handover-protocol") | .source_file' seed/seed-skills.json)" && echo "source_file exists"
```
Expected: `VALID JSON`, then `skills/handover-protocol/SKILL.md`, then `source_file exists`.

- [ ] **Step 3: Commit**

```bash
git add seed/seed-skills.json
git commit -m "feat: register handover-protocol skill for backend seeding"
```

## Task 10: Verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Confirm the full file set exists**

```bash
for f in SKILL.md references/discovery-to-planning.md references/planning-to-technical.md \
  references/technical-to-orchestration.md references/story-execution.md \
  references/execution-report.md references/correction.md; do
  test -f "skills/handover-protocol/$f" && echo "OK: $f" || echo "FAIL: $f missing"
done
```
Expected: 7 `OK:` lines, zero `FAIL:`.

- [ ] **Step 2: Confirm every template is genuinely distinct (spot-check field names differ per type)**

```bash
for f in discovery-to-planning planning-to-technical technical-to-orchestration story-execution execution-report correction; do
  echo "=== $f ==="
  grep "^### " "skills/handover-protocol/references/$f.md" | tail -n +1
done
```
Expected: each type's field list under "## Template" is visibly different from the others (e.g. `story-execution` has "TDD expectation", `correction` has "Correction round", `discovery-to-planning` has "Paths explored and rejected" — none of these appear in the other types).

- [ ] **Step 3: Confirm no stray references to non-existent skills**

```bash
grep -rn "Skill to load:\*\* sandbox\|Skill to load:\*\* orchestrator" skills/handover-protocol/references/*.md
```
Expected: matches on `orchestrator` (used by `technical-to-orchestration`, `execution-report`) are fine — `orchestrator` doesn't exist as a skill yet (Plan 4), but this plan is explicitly writing the contract those future skills will honor, per Global Constraints. No match on `sandbox` should appear as a `Skill to load` target (Sandbox never *receives* a handover — it's the entry point).

- [ ] **Step 4: If everything passes, this plan is complete — no commit needed for this task (verification only)**

## Self-review (writing-plans §Self-Review, performed before handing this plan off)

- **Spec coverage:** §5.1 (marker) → Task 1. §5.2 (6 types) → Tasks 2-7, one each, all with genuinely distinct fields. §5.3 (auto-detection) → Task 8. Nothing in spec §5 is uncovered.
- **Placeholder scan:** every template task contains complete, literal file content — no "TBD"/"fill in later." The `{curly-brace}` tokens inside templates are intentional fill-in-the-blank fields for the *skill's future users* to complete when they actually emit a handover, not placeholders in *this plan* (the plan itself has zero unresolved placeholders — every file's full content is written out).
- **Type/name consistency:** `Skill to load` values checked against Plan 1's renamed skill set (`product-planning`, `technical-planning`, `execution`) plus the not-yet-built `orchestrator` — consistent throughout. Catalog table in Task 1 matches the per-type objectives used in Tasks 2-7 verbatim.

## What comes next

3. **Sandbox** (`skills/sandbox/` + `agents/deep-search.md` + `agents/code-analyzer.md`) — the first skill to actually *emit* a handover (`discovery-to-planning`), and the first consumer of this catalog.
4. **Orchestrator** (`skills/orchestrator/`) — the busiest consumer: receives `technical-to-orchestration` and `execution-report`, emits `story-execution` and `correction`.
5. **Phase-skill deltas** (`product-planning`, `technical-planning`, `execution` each get a handover-out step wired to their specific catalog entry).
6. **OpenCode package rework + manifest updates** — including the open question flagged in Task 9 about how non-Claude-Code platforms get the full 6-template catalog, not just `SKILL.md`'s summary.
