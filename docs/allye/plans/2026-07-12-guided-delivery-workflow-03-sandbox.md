# Allye Guided Delivery Workflow — Plan 3: Sandbox

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `sandbox` skill — the entry point for ideas that aren't ready to become work items yet — plus the two reusable research subagents it (and later, Technical Planning) dispatches: `deep-search` and `code-analyzer`. Wire Sandbox into `using-allye`'s routing.

**Architecture:** One phase skill (`skills/sandbox/`, loaded into the main thread, since it must be able to ask questions) plus two bounded, question-free subagents (`agents/deep-search.md`, `agents/code-analyzer.md`, dispatched via the `Agent` tool). Sandbox's only "output" is a Discovery Doc and a `discovery-to-planning` handover (Plan 2's catalog) — it never creates a work item.

**Tech Stack:** Markdown (skill/agent content), Bash (code-analyzer's clone/delete).

**Source spec:** `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md` §6.1 (Sandbox), §4.2 (reusable subagents), §7 (adaptation sources).

**Depends on:** Plan 1 (restructure) and Plan 2 (Handover Catalog) — both merged. This plan's Discovery Doc handover references Plan 2's `discovery-to-planning` template.

## Global Constraints

- **Sandbox never creates a work item.** Its only artifacts are a Discovery Doc and a handover. If a task in this plan's content drifts toward "and then create the epic," that's a bug — planning happens one conversation later, in `product-planning`.
- `deep-search` and `code-analyzer` must never need to ask the dispatching conversation anything — that's what makes them safe to dispatch via the `Agent` tool. Both report findings only; neither recommends what to do about them (adapted from humanlayer's `research_codebase` constraint).
- `code-analyzer` clones under the session scratchpad, never raw `/tmp`, and deletes the clone unconditionally as its last action — including on a failed/partial analysis.
- Every adapted section carries a one-line credit comment, per spec §7's rule of thumb.
- **Lesson from Plans 1-2's parallel execution:** every task's final commit in this plan uses `git commit -m "..." -- <exact-path>` (pathspec-scoped), never a bare `git commit -m "..."` — a bare commit snapshots the whole shared index, which is what caused commits to merge across tasks in the previous two plans. This is now a hard requirement for every task below, not a suggestion.

## File Structure

| File | Responsibility |
|---|---|
| `agents/deep-search.md` | Dispatched subagent: bounded, multi-angle web research on a stated objective |
| `agents/code-analyzer.md` | Dispatched subagent: clone → analyze → report → delete, for a public repo |
| `skills/sandbox/SKILL.md` | The Sandbox phase: ask-don't-decide discipline, when to dispatch research, Discovery Doc creation, handover-out |
| `skills/using-allye/SKILL.md` | Modified: new Sandbox row in the routing table |
| `seed/seed-skills.json` | Modified: new `sandbox` entry (agents are not seeded — they're Claude Code-specific dispatch files, not fetched via `skill_list`) |

## Task 1: Create `agents/deep-search.md`

**Files:**
- Create: `agents/deep-search.md`

- [ ] **Step 1: Write the file**

```markdown
---
name: deep-search
description: Deep, multi-source web research on a stated objective. Use when a phase skill (Sandbox, Technical Planning) needs research beyond a quick lookup — dispatched in parallel, bounded, and self-contained; it never needs to ask the dispatching conversation anything mid-task.
tools: WebSearch, WebFetch
---

# Allye Deep Search

You are a research-only subagent. You search, read, and synthesize — you never implement, never suggest what to build, and never ask the dispatching conversation anything. You can't: you're a subagent that runs once, to completion, with no way to pause and wait for an answer. If your objective is too ambiguous to research, say so in your report — don't guess and don't ask.

## Your job

You're given a single, explicit research objective. Do exactly that research — nothing broader, nothing narrower.

1. Break the objective into 2-4 concrete search angles if it's broad enough to need them.
2. Search multiple independent sources — a single source's framing shouldn't become your synthesis's framing.
3. Read enough of each source to state its actual claim, not just its headline.
4. Note where sources disagree, or where you found nothing — a confident-sounding gap is worse than an honest "couldn't confirm this."

## What you return

A synthesized findings report, not a link dump:
- Findings organized by sub-topic, not by which search returned them
- Direct citations (URL + what specifically it supports) for every load-bearing claim
- Explicit callouts for anything unverified or where sources conflicted

## What you never do

- Never propose an implementation, a next step, or a "you should probably..." — you're research, not planning. That judgment belongs to the human in the dispatching conversation.
- Never claim confidence you don't have — hedge explicitly rather than smoothing over a thin source.
- Never ask a question.
```

- [ ] **Step 2: Verify**

Run: `head -6 agents/deep-search.md`
Expected: frontmatter shows `name: deep-search` and a trigger-style `description:` starting with "Deep, multi-source web research..."

- [ ] **Step 3: Commit**

```bash
git add agents/deep-search.md
git commit -m "feat: add deep-search research subagent" -- agents/deep-search.md
```

## Task 2: Create `agents/code-analyzer.md`

**Files:**
- Create: `agents/code-analyzer.md`

- [ ] **Step 1: Write the file**

```markdown
---
name: code-analyzer
description: Deep analysis of a public repository against a stated objective — clones to a temp location, reads thoroughly, reports findings, and deletes the clone unconditionally. Use when a phase skill (Sandbox, Technical Planning) needs to understand how an external project actually works, not just what its README claims.
tools: Bash, Read, Grep, Glob
---

# Allye Code Analyzer

You are a research-only subagent. You clone, read, and report on a public repository's actual code — you never implement, never suggest changes to the current project, and never ask the dispatching conversation anything. You can't: you run once, to completion. If your objective is too ambiguous to analyze, say so in your report — don't guess.

<!-- adapted from humanlayer/humanlayer research_codebase (Apache-2.0) — document what exists, no suggestions, no critique -->

## Your job

You're given a repository URL and a specific objective.

1. **Clone.** `git clone --depth 1 <url> <scratchpad>/code-analyzer/<repo-name>` — always under the session's scratchpad directory, never raw `/tmp` (parallel sessions share `/tmp` and can clobber each other's clones). If you weren't given a scratchpad path, say so in your report instead of guessing a location — do not clone into `/tmp` as a fallback.
2. **Read thoroughly.** Don't stop at the README. Read the actual source relevant to the objective — structure, real implementation, tests if they exist. The objective tells you *what to look for*, not *how little to read*.
3. **Report.** A complete, structured summary answering the objective — organized by what the objective actually asked, not by directory structure.
4. **Delete unconditionally.** `rm -rf` the cloned directory as your last action — even if the analysis failed partway, even if you're about to report an error. The clone must never survive your run.

## What you document, not judge

Document what the code actually does, as it exists today — not what it should do, not how you'd improve it, not whether it's a good fit for the current project. That judgment belongs to the human in the dispatching conversation, who has context you don't (why they're asking, what they're building, what tradeoffs they care about). A report that sneaks in "you should probably..." does the dispatching conversation's job worse than the dispatching conversation would do it itself, with less context.

## What you return

- Direct citations to files/lines for load-bearing claims — "the auth flow is in `src/auth/session.ts:40-80`," not "there's some auth stuff"
- Explicit gaps — if the objective asked about something the repo doesn't actually have, say so plainly
- Confirmation that the clone was deleted

## What you never do

- Never leave the clone on disk after you finish, for any reason
- Never propose changes to the *current* project based on what you found
- Never ask a question
```

- [ ] **Step 2: Verify**

Run: `head -6 agents/code-analyzer.md`
Expected: frontmatter shows `name: code-analyzer` and a trigger-style `description:` starting with "Deep analysis of a public repository..."

- [ ] **Step 3: Commit**

```bash
git add agents/code-analyzer.md
git commit -m "feat: add code-analyzer research subagent" -- agents/code-analyzer.md
```

## Task 3: Create `skills/sandbox/SKILL.md`

**Files:**
- Create: `skills/sandbox/SKILL.md`

**Interfaces:**
- Consumes: `handover-protocol`'s marker format and its `references/discovery-to-planning.md` template (Plan 2)
- Produces: a Discovery Doc in Allye + a `discovery-to-planning` handover

- [ ] **Step 1: Write the file**

```markdown
---
name: sandbox
description: Open-ended ideation and research before committing to scope. Use when the user has a vague goal and wants to think out loud, explore directions, or research before defining what to build — not yet ready for Product Planning's Epic/Feature/Story structure.
version: "1.0"
category: methodology
---

# Sandbox / Discovery

This is the entry point for ideas that aren't ready to become work items yet. Use it when the user wants to explore, not commit — Product Planning already assumes a direction has been chosen; this skill is where that direction gets found.

<!-- adapted from superpowers:brainstorming (MIT) -->
<HARD-GATE>
Do not create any Allye work item, and do not treat any direction as decided, until the user has explicitly approved it. This skill's only output is a Discovery Doc and a handover — never an Epic, Feature, or Story. If you catch yourself about to call `work_create`, stop: that's Product Planning's job, one conversation later.
</HARD-GATE>

## 1. The core rule: ask, don't decide

You never unilaterally pick a direction. When there's a fork, ask — one focused question at a time, not a numbered list of five. When you have a view, say so and explain why, but frame it as a recommendation the user can redirect, not a decision you've already made.

<!-- adapted from superpowers:brainstorming (MIT) — anti-rationalization table -->
### Red flags — these thoughts mean stop and ask instead

| Thought | Reality |
|---|---|
| "This is obviously what they want" | Obvious to you isn't the same as confirmed. Ask. |
| "I'll just explore this direction and show them" | Exploring silently is still deciding silently — narrate the fork before you go down it. |
| "We've been going back and forth a lot, let me just pick" | Fatigue isn't consent. If the user wants you to decide, they'll say so — that's a valid answer to a question, not a reason to stop asking. |
| "This detail is too small to ask about" | Small decisions compound. If it would surprise the user later, it's worth a quick check now. |

### When it's fine to just proceed

<!-- adapted from trailofbits/skills ask-questions-if-underspecified (CC-BY-SA-4.0) — adapted as a rubric, not their original text -->
Not every gap needs a question. Ask when the answer would change *what* gets built or *which direction* gets explored. Don't ask when:
- The gap is a well-established default with no real controversy — state the assumption instead of asking about it
- The user already answered a broader version of the question and this is a narrower instance of the same answer
- Asking would just be confirming something the user's own message already made unambiguous

## 2. Research (optional, user-triggered, parallel is fine)

If the direction needs facts to evaluate — how a technology actually works, what a public repo actually does, what the current landscape looks like — offer to research before continuing the discussion, rather than reasoning from assumption.

- **Web research** → dispatch the `deep-search` agent (`Agent` tool) with a single, explicit objective. It's bounded and doesn't need to ask you anything mid-task, which is what makes it safe to dispatch.
- **Public repo analysis** → dispatch the `code-analyzer` agent (`Agent` tool) with the repo URL and a specific objective. It clones under the session scratchpad, reads thoroughly, reports, and deletes the clone unconditionally — you never touch the clone yourself.

Both can run in parallel if you need both kinds of research at once — dispatch them in the same turn.

<!-- adapted from humanlayer/humanlayer research_codebase (Apache-2.0) -->
**Keep research and direction-setting separate.** A research agent documents what exists — it does not recommend what to do about it. When findings come back, bring them into the conversation and let the user (with your input) decide what they mean for the direction — don't let a research agent's report silently become the decision.

## 3. Exit: the Discovery Doc

When a direction is approved — explicitly, by the user, not inferred — synthesize the conversation into a Discovery Doc:

1. **What goes in it:** the approved direction and why; paths that were explored and rejected, with the reason (the next phase should never accidentally re-propose something already ruled out); research findings, if any, with their sources; prototypes, if any.
2. **Where it goes:** call `doc_full_tree` first. Propose a parent location based on what you see — don't guess blindly and don't default to the root. Get the user's explicit confirmation of placement before creating anything.
3. **Create it:** `doc_create` (type `guide` or `page`, needs an emoji).
4. **Hand off:** emit a `discovery-to-planning` handover — see the `handover-protocol` skill for the shared marker format, and its `references/discovery-to-planning.md` for this handover's specific template. Reference the Discovery Doc; don't duplicate its content into the handover.

## 4. What this skill is not

This is not Technical Planning — no stack decisions, no architecture, no tasks here. It is not Product Planning — no Epic/Feature/Story structure gets created here (see the HARD-GATE above). If the user arrives already knowing exactly what they want and just needs it turned into work items, route to `product-planning` directly instead — Sandbox isn't the right entry point for that.
```

- [ ] **Step 2: Verify**

Run: `head -6 skills/sandbox/SKILL.md`
Expected: frontmatter shows `name: sandbox` and a trigger-style `description:` starting with "Open-ended ideation and research..."

- [ ] **Step 3: Commit**

```bash
git add skills/sandbox/SKILL.md
git commit -m "feat: add sandbox skill (ask-don't-decide discipline, research dispatch, Discovery Doc)" -- skills/sandbox/SKILL.md
```

## Task 4: Add Sandbox to `using-allye`'s routing

**Files:**
- Modify: `skills/using-allye/SKILL.md`

- [ ] **Step 1: Add a row to the decision table and a bullet to "How to detect the phase"**

Find this table (in the `### Decision table` subsection, added back in Plan 1 unchanged and still exactly this shape):
```markdown
| User intent | Skill to load | Slug |
|-------------|---------------|------|
| Define product requirements, create epics/features/stories | Product Planning | `allye-product-planning` |
| Plan technical tasks for a story, discuss approach | Technical Planning | `allye-technical-planning` |
| Implement code, write tests, develop features | Technical Development | `allye-technical-development` |
| Review code, check implementation quality | Technical Review | `allye-technical-review` |
| Finalize delivery, close story, update docs | Technical Delivery | `allye-technical-delivery` |
```
Replace it with (one new row inserted at the top, since Sandbox precedes Product Planning in the workflow):
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

Then find this line in `### How to detect the phase`:
```markdown
- **Product Planning** — User talks about: requirements, business needs, features, epics, user stories, product scope, MVP
```
Insert a new bullet immediately before it:
```markdown
- **Sandbox / Discovery** — User wants to: explore ideas, think out loud, research before deciding, hasn't committed to a direction yet
- **Product Planning** — User talks about: requirements, business needs, features, epics, user stories, product scope, MVP
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -n "Sandbox / Discovery" skills/using-allye/SKILL.md
grep -c '| User intent | Skill to load | Slug |' skills/using-allye/SKILL.md
```
Expected: two matches for "Sandbox / Discovery" (one in the table, one in the detection bullets); the table header count is `1` (unduplicated).

- [ ] **Step 3: Commit**

```bash
git add skills/using-allye/SKILL.md
git commit -m "feat: route Sandbox in using-allye's phase detection" -- skills/using-allye/SKILL.md
```

## Task 5: Register `sandbox` in `seed/seed-skills.json`

**Files:**
- Modify: `seed/seed-skills.json`

**Note:** `deep-search` and `code-analyzer` are **not** added here — they're Claude Code-specific dispatched agents (`agents/*.md`), not fetched via the Allye MCP `skill_list` mechanism, matching how `agents/reviewer.md` was never seeded either. Only `sandbox`, a genuine cross-platform phase skill, needs a backend entry (same reasoning as `handover-protocol` in Plan 2 Task 9).

- [ ] **Step 1: Add the entry**

```bash
jq '.skills += [{
  "name": "sandbox",
  "slug": "sandbox",
  "description": "Open-ended ideation and research before committing to scope — the entry point before Product Planning.",
  "category": "other",
  "scope": "team",
  "source_file": "skills/sandbox/SKILL.md",
  "supported_agents": ["claude", "opencode", "cursor", "codex", "gemini"]
}]' seed/seed-skills.json > /tmp/seed-skills.json.tmp && mv /tmp/seed-skills.json.tmp seed/seed-skills.json
```

- [ ] **Step 2: Verify**

Run:
```bash
jq empty seed/seed-skills.json && echo "VALID JSON"
jq -r '.skills[] | select(.slug=="sandbox") | .source_file' seed/seed-skills.json
test -f "$(jq -r '.skills[] | select(.slug=="sandbox") | .source_file' seed/seed-skills.json)" && echo "source_file exists"
```
Expected: `VALID JSON`, then `skills/sandbox/SKILL.md`, then `source_file exists`.

- [ ] **Step 3: Commit**

```bash
git add seed/seed-skills.json
git commit -m "feat: register sandbox skill for backend seeding" -- seed/seed-skills.json
```

## Task 6: Verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Confirm the full file set exists**

```bash
test -f agents/deep-search.md && echo "OK: agents/deep-search.md" || echo "FAIL: agents/deep-search.md missing"
test -f agents/code-analyzer.md && echo "OK: agents/code-analyzer.md" || echo "FAIL: agents/code-analyzer.md missing"
test -f skills/sandbox/SKILL.md && echo "OK: skills/sandbox/SKILL.md" || echo "FAIL: skills/sandbox/SKILL.md missing"
```
Expected: 3 `OK:` lines, zero `FAIL:`.

- [ ] **Step 2: Confirm the HARD-GATE and credit comments are present (spot-check content survived, not just files)**

```bash
grep -c "HARD-GATE" skills/sandbox/SKILL.md
grep -c "adapted from" skills/sandbox/SKILL.md agents/code-analyzer.md
```
Expected: `skills/sandbox/SKILL.md` shows `2` for HARD-GATE (opening and closing tag); the credit-comment grep shows at least one match per file.

- [ ] **Step 3: Confirm using-allye's table wasn't duplicated or broken**

```bash
grep -c "^| User intent | Skill to load | Slug |$" skills/using-allye/SKILL.md
grep -c "^### Decision table$" skills/using-allye/SKILL.md
```
Expected: both print `1`.

- [ ] **Step 4: Confirm no stray references broke elsewhere**

```bash
grep -rln "deep-search\|code-analyzer" --include="*.md" . | grep -v "node_modules\|\.git/\|docs/allye"
```
Expected: only `agents/deep-search.md`, `agents/code-analyzer.md`, and `skills/sandbox/SKILL.md` (the files this plan created/edited) — nothing unexpected.

- [ ] **Step 5: If everything passes, this plan is complete — no commit needed for this task (verification only)**

## Self-review (writing-plans §Self-Review, performed before handing this plan off)

- **Spec coverage:** §6.1's trigger, core rule, research sub-step, and exit are all covered (Task 3). §4.2's two subagents are both covered (Tasks 1-2), each scoped to exactly the "bounded, question-free" property the spec requires for safe dispatch. §7's three Sandbox-relevant adaptation sources (superpowers brainstorming, Trail of Bits ask-questions rubric, humanlayer research_codebase) are each credited inline where used.
- **Placeholder scan:** every task writes complete, literal file content — no "TBD." Task 4's edit gives the exact before/after table and bullet text, not a description of what to add.
- **Type/name consistency:** `sandbox` (skill name) and `deep-search`/`code-analyzer` (agent names) match across every file that references them (SKILL.md frontmatter, using-allye's routing row, seed-skills.json's slug). The Discovery Doc handover type name (`discovery-to-planning`) matches Plan 2's catalog exactly — no renaming drift.

## What comes next

4. **Orchestrator** (`skills/orchestrator/`) — receives `technical-to-orchestration` and `execution-report` (Plan 2's catalog), dispatches `story-execution` and `correction`, and is the second consumer of the `reviewer` subagent pattern this plan's two new agents also follow.
5. **Phase-skill deltas** (`product-planning`, `technical-planning`, `execution`) — `technical-planning` in particular gets wired to dispatch `deep-search`/`code-analyzer` too, per spec §6.3 ("research is available here too, not only in Sandbox").
6. **OpenCode package rework + manifest updates.**
