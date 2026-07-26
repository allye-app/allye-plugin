# Foundation and Defect Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the skill-doctrine rewrite of seven skills, remove two `memory_save` parameters that no layer of the stack accepts, correct an architecture-doc inaccuracy, and teach the session hook to detect an agent runtime — so the three feature plans that follow start from a clean, honest base.

**Architecture:** Four independent changes, ordered only by file collision. The doctrine branch lands first because it rewrites files that later tasks edit. The runtime probe is additive and touches one shell script. Nothing here changes workflow behaviour; it is groundwork.

**Tech Stack:** Markdown skills, Bash (`hooks/session-start.sh`), `jq`, git worktrees. No build step, no package manager.

## Global Constraints

- **Conventional Commits are enforced in CI.** Every commit message must use a valid type (`feat`, `fix`, `docs`, `refactor`, `chore`).
- **Never add a `Co-Authored-By` trailer** to any commit.
- **Tool names, action names, and parameter names are an API contract** verified against `allye-mcp` source. Never rename or "improve" them.
- **Skill files stay in English.** They are the source; the plugin translates at conversation time.
- **Frontmatter keys are `name`, `description`, `version`, `category`.** Bump `version` by a minor increment on any skill file you change.
- **Adapted content carries an inline credit comment**, e.g. `<!-- adapted from mattpocock/skills writing-great-skills (MIT) -->`.
- **Do not push and do not merge to `main`.** All work stays on the feature branch.
- **This repo has no test framework.** It is Markdown and shell. Verification for Markdown changes is grep-based assertion; verification for shell changes is executing the script against controlled input. Do not invent a test runner.

---

### Task 1: Land the skill-doctrine rewrite

The branch `refactor/pocock-skill-doctrine` holds seven commits rewriting seven skills against `mattpocock/skills`' authoring doctrine (−242 lines, no functional or API content dropped). It was produced in an isolated worktree specifically so it would not collide with the files this spec's later plans rewrite.

**Files:**
- Modify (via merge): `skills/memory-protocol/SKILL.md`, `skills/tdd-workflow/SKILL.md`, `skills/board-progression/SKILL.md`, `skills/tools-quickref/SKILL.md`, `skills/product-planning/SKILL.md`, `skills/sandbox/SKILL.md`, `skills/delivery/SKILL.md`

**Interfaces:**
- Consumes: nothing
- Produces: the seven rewritten skill files, which Task 2 then edits. No symbol or signature changes — this is prose only.

- [x] **Step 1: Confirm the branch is clean and contains only the expected files**

```bash
cd /home/bfernandes/dev/allye/allye-plugin
git -C /home/bfernandes/dev/allye/.worktrees/pocock-doctrine status --porcelain
git diff --stat main..refactor/pocock-skill-doctrine
```

Expected: the `status --porcelain` output is **empty**, and the diffstat lists **exactly seven files**, all under `skills/`. If any other path appears, stop — that is a collision with a later plan and must be resolved before merging.

- [x] **Step 2: Verify no MCP tool or parameter name was altered**

```bash
git diff main..refactor/pocock-skill-doctrine -- skills/ \
  | grep -E '^[-+].*\b(memory_save|memory_search|work_create|work_update|work_status_next|work_status_done|work_children|work_bulk_create|doc_create|skill_list|skill_get|todo_create)\b' \
  | sort | uniq -c | sort -rn | head -40
```

Expected: every removed line (`-`) that mentions a tool name has a matching added line (`+`) with the **same** tool name, or is a genuine deduplication where the same call already appears elsewhere in the file. A tool name that appears only on a `-` line and nowhere on a `+` line means a call was dropped — investigate before merging.

- [x] **Step 3: Merge the branch**

```bash
git merge --no-ff refactor/pocock-skill-doctrine -m "refactor(skills): apply skill-authoring doctrine to seven skills

Applies mattpocock/skills' writing-great-skills doctrine — no-op test
applied sentence by sentence, collapsed duplication, positive framing
where it does not weaken a gate — to memory-protocol, tdd-workflow,
board-progression, tools-quickref, product-planning, sandbox, and
delivery. Net -242 lines with no functional or API content dropped.

Two doctrine conflicts were resolved conservatively: HARD-GATEs whose
prohibition is itself the actionable content keep their negative
framing, and tools-quickref keeps its flat structure as the
legitimately-flat peer-set case the doctrine carves out."
```

Expected: a clean merge with no conflicts, since no other branch has touched these seven files.

- [x] **Step 4: Verify the frontmatter contract survived**

```bash
for f in memory-protocol tdd-workflow board-progression tools-quickref product-planning sandbox delivery; do
  echo "--- $f"
  sed -n '1,8p' "skills/$f/SKILL.md" | grep -E '^(name|description|version|category):' | sed 's/description:.*/description: [present]/'
done
```

Expected: all four keys present for all seven skills. A missing `version` or `category` is a regression against a fix already made in commit `9b53e33`.

- [x] **Step 5: Confirm the source worktree and pane are already gone**

The `pocock-doctrine` worktree was removed and its pane closed on 2026-07-26, before this plan began executing — worktree first, pane last, per the teardown rule in spec §7.6. The branch was deliberately kept as the record.

```bash
git worktree list
git branch --list 'refactor/pocock-skill-doctrine'
```

Expected: `git worktree list` shows no `pocock-doctrine` entry, and the branch **is** listed. If the worktree still exists, remove it with `git worktree remove <path>` — **without** `--force`. A git refusal there means uncommitted work is present, and that refusal is the safety net, not an obstacle.

---

### Task 2: Remove `memory_save` parameters that no layer accepts

Five skills document `memory_save(..., work_item_id: "...", sprint_id: "...")`. Verified against live source: `IntelligenceRequest` (`allye-mcp/allye_mcp/application/tools/intelligence.py:142`) defines only `title`, `content`, `tags`, `sector`, `scope`; `IntelligenceService.save_memory` (`allye_mcp/domain/intelligence.py:17`) accepts only `title`, `content`, `tags`, `sector`; and `SaveMemoryDto` (`allye-api/src/modules/memories/dto/save-memory.dto.ts:28`) declares only `title`, `content`, `tags`, `sector`.

**No memory has ever been linked to a work item.** The parameters are silently discarded. The fix is removal, not addition — adding linkage would require a schema change, a migration, and API work across three repositories, which is a feature and out of scope here.

**Files:**
- Modify: `skills/technical-planning/SKILL.md`, `skills/execution/SKILL.md`, `skills/review/SKILL.md`, `skills/delivery/SKILL.md`, `skills/product-planning/SKILL.md`

**Interfaces:**
- Consumes: the seven files landed by Task 1 (two of them — `delivery`, `product-planning` — are edited again here)
- Produces: `memory_save` call sites documenting only the four accepted parameters. Later plans rewriting `technical-planning`, `execution`, and `review` inherit these corrected call sites.

- [x] **Step 1: Establish the failing assertion**

```bash
cd /home/bfernandes/dev/allye/allye-plugin
echo "--- parameter-assignment form (this is the defect):"
grep -rnE '^[[:space:]]*(work_item_id|sprint_id):' skills/
```

Expected: **non-empty** — one hit per `memory_save` call site carrying either parameter. Record the line numbers; Step 4 asserts this returns nothing.

The pattern matches the assignment form only. Prose that *mentions* `work_item_id` — such as the gotcha entry Step 3 adds — is not an instance of the defect and must not be caught here, and `sprint_id` as a legitimate parameter of `sprint_get` and `sprint_work_items` appears in a table cell, never as an indented assignment.

- [x] **Step 2: Remove the two parameters from every `memory_save` block**

In each of the five files, delete the `work_item_id:` and `sprint_id:` argument lines from every `memory_save(...)` example. Delete the whole line, including its trailing comma handling — the preceding line must not be left with a dangling comma.

Worked example, from `skills/execution/SKILL.md`. Before:

```
memory_save(
  title: "Implementation — {TASK-KEY} {short description}",
  content: "## What was done\n{summary of changes}\n\n## Key decisions during implementation\n{any new decisions made}\n\n## Files changed\n- {file 1}\n- {file 2}\n\n## Gotchas\n{anything surprising or non-obvious encountered}\n\n## Tests\n{what was tested, any notable test patterns}",
  tags: ["development", "implementation", "{story-key}", "{task-key}"],
  work_item_id: "{task uuid}",
  sprint_id: "{sprint uuid if applicable}"
)
```

After — note `tags` loses its trailing comma and `sector` is added, because every save must pass a sector explicitly (omitting it silently defaults to `knowledge`):

```
memory_save(
  title: "Implementation — {TASK-KEY} {short description}",
  content: "## What was done\n{summary of changes}\n\n## Key decisions during implementation\n{any new decisions made}\n\n## Files changed\n- {file 1}\n- {file 2}\n\n## Gotchas\n{anything surprising or non-obvious encountered}\n\n## Tests\n{what was tested, any notable test patterns}",
  tags: ["development", "implementation", "{story-key}", "{task-key}"],
  sector: "knowledge"
)
```

Apply the correct sector per call site, following `skills/memory-protocol/SKILL.md` §1:

| File | Call site | Sector |
|---|---|---|
| `technical-planning` | "Decision — …" in Step 3.4 | `decisions` |
| `technical-planning` | "Technical Plan — …" in Step 6 | `plans` |
| `execution` | "Implementation — …" in Step 8 | `knowledge` |
| `review` | "Review — … approved" and "Review — … changes requested" | `knowledge` |
| `delivery` | "Delivered — …" | `knowledge` |
| `product-planning` | "Planning — … scope and decisions" | `decisions` |

- [x] **Step 3: Add a gotcha entry to the quickref so this cannot silently return**

In `skills/tools-quickref/SKILL.md`, add to the "Gotchas" list, keeping the existing style:

```markdown
- **`memory_save` does not link a memory to a work item.** There is no `work_item_id` or `sprint_id` parameter — not on the MCP tool (`IntelligenceRequest`), not in its domain layer, and not on the backend's `SaveMemoryDto`. Passing them is silently discarded, not an error. To make a memory findable from a work item, put the key in `tags` and in the `title`.
```

- [x] **Step 4: Verify the parameters are gone and no `memory_save` lost its sector**

```bash
grep -rnE '^[[:space:]]*(work_item_id|sprint_id):' skills/
```
Expected: **no output.** Then confirm the two legitimate `sprint_id` table rows and the new gotcha entry all survived:

```bash
grep -c 'sprint_id' skills/tools-quickref/SKILL.md
```
Expected: `3` — the `sprint_get` row, the `sprint_work_items` row, and the gotcha entry. A count of `2` means the gotcha entry from Step 3 is missing.

```bash
grep -rn -A 6 'memory_save(' skills/ | grep -c 'sector:'
grep -rc 'memory_save(' skills/*/SKILL.md | grep -v ':0'
```
Expected: the count of `sector:` occurrences is greater than or equal to the count of `memory_save(` call sites. A call site without a sector silently defaults to `knowledge`, which is rarely correct.

- [x] **Step 5: Bump the versions of every skill touched**

Increment the `version` frontmatter minor value on all six modified files (`technical-planning`, `execution`, `review`, `delivery`, `product-planning`, `tools-quickref`).

- [x] **Step 6: Commit**

```bash
git add skills/
git commit -m "fix: memory_save never accepted work_item_id or sprint_id

Five skills documented memory_save calls passing work_item_id and
sprint_id. Neither parameter exists on IntelligenceRequest, on the MCP
domain service, or on the backend SaveMemoryDto — they were silently
discarded, so no memory has ever been linked to a work item.

Removes both from every call site, adds the explicit sector each call
should have been passing, and records the constraint in tools-quickref's
gotchas so it cannot silently return."
```

---

### Task 3: Correct the `delivery` scope description in CLAUDE.md

`CLAUDE.md` describes `skills/delivery/` as epic close-out. The skill closes a **story**, and conditionally its parent feature; it never mentions epics. Epic close-out belongs to the Orchestrator (`skills/orchestrator/SKILL.md` §8). An architecture doc that misstates a skill's scope sends a reader to the wrong file.

**Files:**
- Modify: `/home/bfernandes/dev/allye/allye-plugin/CLAUDE.md`

**Interfaces:**
- Consumes: nothing
- Produces: nothing consumed by later tasks. Documentation only.

- [x] **Step 1: Locate the inaccurate sentence**

```bash
grep -n 'delivery' CLAUDE.md
```

Expected: a line in the "Guided delivery workflow" section reading `Epic close-out (\`skills/delivery/\`) is always a deliberate, manual step — the Orchestrator announces completion and asks, never auto-runs it.`

- [x] **Step 2: Replace it with the accurate description**

```markdown
Story close-out (`skills/delivery/`) verifies every task is done, closes the story, and closes the parent feature when all its stories are complete. Epic close-out is the Orchestrator's (`skills/orchestrator/` §8) and is always a deliberate, manual step — it announces completion and asks, never auto-runs `delivery`.
```

- [x] **Step 3: Verify the claim against the skill**

```bash
grep -in 'epic' skills/delivery/SKILL.md
```
Expected: **no output**, or only a "What Comes Next" mention that routes elsewhere — confirming `delivery` genuinely does not close epics.

- [x] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: correct the delivery skill's scope in CLAUDE.md

CLAUDE.md described skills/delivery/ as epic close-out. It closes a
story and conditionally its parent feature, and never mentions epics —
epic close-out is the Orchestrator's, per its section 8."
```

---

### Task 4: Detect an agent runtime in the session hook

The hook injects one line of context when a runtime is present, and nothing at all when it is not. This is the whole context-load answer for the runtime feature: a user without a runtime pays zero tokens.

**Files:**
- Modify: `hooks/session-start.sh`
- Create: `hooks/test-session-start.sh`

**Interfaces:**
- Consumes: nothing
- Produces: a line of the exact form `Agent runtime: herdr <version> (pane <pane_id>, workspace <workspace_id>)` appended to the hook's `additionalContext`. Plan 4 (`agent-runtime`) reads this line to decide whether to load `skills/agent-runtime/`. The prefix `Agent runtime: ` is the contract — do not change it without updating Plan 4.

- [x] **Step 1: Write the failing test**

Create `hooks/test-session-start.sh`:

```bash
#!/bin/bash
# Assertions for hooks/session-start.sh runtime detection.
# No test framework in this repo — this script IS the harness.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-start.sh"
PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1))
  fi
}

echo "test: no runtime when HERDR_ENV is unset"
OUT=$(echo '{"source":"startup"}' | env -u HERDR_ENV -u HERDR_PANE_ID bash "$HOOK" 2>/dev/null)
HAS=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -c '^Agent runtime:' || true)
check "absent runtime emits no runtime line" "0" "$HAS"

echo "test: no runtime when HERDR_ENV set but herdr binary missing"
OUT=$(echo '{"source":"startup"}' | env HERDR_ENV=1 PATH=/nonexistent bash "$HOOK" 2>/dev/null)
HAS=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -c '^Agent runtime:' || true)
check "missing binary emits no runtime line" "0" "$HAS"

echo "test: output is always valid JSON"
OUT=$(echo '{"source":"startup"}' | env -u HERDR_ENV bash "$HOOK" 2>/dev/null)
echo "$OUT" | jq -e . >/dev/null 2>&1 && VALID=0 || VALID=1
check "hook emits parseable JSON without a runtime" "0" "$VALID"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

Then make it executable:

```bash
chmod +x hooks/test-session-start.sh
```

- [x] **Step 2: Run the test to see the current state**

Run: `bash hooks/test-session-start.sh`
Expected: all three PASS. The hook does not emit a runtime line today, so the two negative assertions already hold, and the JSON assertion guards against breaking the existing behaviour in Step 3. **This is the regression net, not a red test** — the positive case cannot be asserted portably, because it requires a live Herdr server. Verify it manually in Step 5.

- [x] **Step 3: Add the probe to `hooks/session-start.sh`**

Insert immediately before the final `jq -n` block, after `SKILL_CONTENT` is assigned:

```bash
# Agent runtime detection — emits one line, or nothing at all.
# A user without a runtime pays zero context for this feature.
detect_runtime() {
  [ "${HERDR_ENV:-}" = "1" ] || return 1
  command -v herdr >/dev/null 2>&1 || return 1

  local status version
  status=$(herdr status 2>/dev/null) || return 1
  echo "$status" | grep -q 'compatible: yes' || return 1

  version=$(echo "$status" | awk '/^client:/{f=1} f&&/version:/{print $2; exit}')
  [ -n "$version" ] || version="unknown"

  echo "Agent runtime: herdr ${version} (pane ${HERDR_PANE_ID:-unknown}, workspace ${HERDR_WORKSPACE_ID:-unknown})"
}

if RUNTIME_LINE=$(detect_runtime); then
  SKILL_CONTENT="${SKILL_CONTENT}

---

${RUNTIME_LINE}
A story-parallel dispatch runtime is available. Load the \`agent-runtime\` skill before dispatching work in parallel."
fi
```

Two details that matter. `detect_runtime` returns non-zero on every failure path so the `if` guard suppresses the line entirely — no empty section, no stray separator. And the `compatible: yes` check means a protocol-mismatched server is treated as *runtime absent*, never as *runtime broken*, so a stale Herdr install cannot block delivery.

- [x] **Step 4: Run the test to verify nothing regressed**

Run: `bash hooks/test-session-start.sh`
Expected: all three still PASS. In particular the JSON assertion must still hold — a runtime line containing an unescaped quote or newline would break `jq -n`.

- [x] **Step 5: Verify the positive case manually against the live server**

```bash
echo '{"source":"startup"}' | bash hooks/session-start.sh | jq -r '.hookSpecificOutput.additionalContext' | tail -5
```

Expected, when run inside a Herdr pane: the last lines show `Agent runtime: herdr 0.7.5 (pane wN:pM, workspace wN)` followed by the load instruction. Outside a pane, no such line appears.

- [x] **Step 6: Commit**

```bash
git add hooks/session-start.sh hooks/test-session-start.sh
git commit -m "feat(hooks): detect an agent runtime at session start

Probes for a compatible Herdr server and, when present, appends one
line naming the runtime and the calling pane to the session's
additionalContext. Emits nothing when absent, so a user without a
runtime pays no context for the feature.

A protocol-mismatched server is reported as runtime-absent rather than
runtime-broken, so a stale install cannot block delivery. Adds
hooks/test-session-start.sh as the assertion harness — this repo has no
test framework, so the script is the harness."
```

---

## What this plan deliberately does not do

- **No doctrine pass on the seven skills this spec's later plans rewrite** (`using-allye`, `handover-protocol`, `orchestrator`, `technical-planning`, `execution`, `review`, `setup`). Those files are rewritten for functional reasons in Plans 2–4; the doctrine is applied there, in the same edit. Doing a separate pass first would be work thrown away, and it is the same file-collision problem the isolated worktree existed to avoid.
- **No `skills/agent-runtime/`.** The hook only detects and announces. The skill that consumes the announcement is Plan 4.
- **No behaviour change.** After this plan, every workflow behaves exactly as it did before, on a corrected and tightened base.
