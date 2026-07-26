# Allye Guided Delivery Workflow — Plan 1: Foundational Restructure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename every skill/agent to the bare, role-aligned names approved in the design spec, delete dead legacy copies and non-interactive subagent definitions, and fix every downstream reference — with **zero behavior change**. This is plan 1 of a sequence; it clears the ground for the content-heavy plans that follow (handover catalog, sandbox, orchestrator, new subagents), which are written as their own plans once this one lands.

**Architecture:** Pure rename/cleanup pass across the repo: `git mv` for tracked renames, `git rm` for confirmed-dead files, targeted edits everywhere a path or name is referenced (hooks, seed manifest, release automation, the OpenCode prompt generator, top-level docs). No new skill content is authored in this plan.

**Tech Stack:** Bash, `git`, `jq` (JSON validation), `bun` (OpenCode package, best-effort if installed).

**Source spec:** `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md` §9 (Repository restructure & change map).

## Global Constraints

- API slugs in `seed/seed-skills.json` stay `allye-*` (per spec §9.2 naming decision) even though directory and agent names drop the prefix — do **not** rename the `"slug"` field values in this plan.
- `skills/using-allye/` and `skills/allye-setup/` → `skills/setup/` are the only two "bootstrap-adjacent" skills; `using-allye` was already bare and is not renamed, only referenced.
- Every file this plan deletes has been diff-verified against its replacement — the canonical `skills/allye-*/SKILL.md` files are a strict superset of their legacy `skills/{workflows,methodology,reference,bootstrap}/*.md` twins (verified: canonical has extra `memory_graph` sections in technical-planning and technical-development, and a fuller MCP tools table in tools-quickref — nothing legacy-only exists).
- `CHANGELOG.md` is historical record — never edit it to rewrite old names.
- `agents/allye-reviewer.md` is the only subagent kept as a Claude Code dispatched agent; the other three (`allye-planner`, `allye-builder`, `allye-deliverer`) are deleted outright in this plan (they become skills in a later plan, not here).

## File Structure

| File / dir | Action | Why |
|---|---|---|
| `skills/workflows/*.md` (5), `skills/methodology/*.md` (3), `skills/reference/fenix-tools-quickref.md`, `skills/bootstrap/using-allye.md` | **Delete** | Dead — nothing reads them except one hook fallback (also being removed); diff-confirmed strict subset of canonical |
| `agents/allye-planner.md`, `agents/allye-builder.md`, `agents/allye-deliverer.md` | **Delete** | Dispatched via `Agent` tool, which can't pause for human input — incompatible with the interactive roles they represent |
| `skills/allye-{product-planning,technical-planning,technical-development,technical-review,technical-delivery,memory-protocol,tdd-workflow,board-progression,tools-quickref,setup}/` | **Rename** (`git mv`) | Drop redundant prefix — Claude Code already namespaces plugin skills as `allye:<skill>` |
| `agents/allye-reviewer.md` | **Rename** (`git mv`) | Same reasoning, one file |
| `hooks/session-start.sh`, `manifests/claude/hooks/session-start.sh` | **Edit** | Both reference the now-deleted `skills/bootstrap/using-allye.md` fallback path; the two copies have also drifted (manifest copy is missing the tenant-slug block) |
| `seed/seed-skills.json` | **Edit** | Every `source_file` points at a path this plan deletes; also fixes a pre-existing bug where `allye-tools-quickref`'s `source_file` points at a file that has never existed (`skills/reference/allye-tools-quickref.md` — the real file was `fenix-tools-quickref.md`) |
| `.releaserc.json`, `release.sh` | **Edit** | Both sync `skills/using-allye/SKILL.md` → `skills/bootstrap/using-allye.md`, a path this plan deletes |
| `packages/allye-opencode/scripts/generate-prompts.ts` | **Edit** | `SKILL_SOURCES` table paths point at pre-rename directory names |
| `CLAUDE.md`, `README.md` | **Edit** | Both document the old 4-subagent architecture and old skill names |
| `manifests/{codex,cursor,gemini}/*` | **No change** | They route by API slug (`allye-product-planning`, etc.), which this plan does not touch — confirmed by reading `install.sh`'s manifest-configuration logic, which never writes skill-routing tables, only MCP connection config |

## Task 1: Delete superseded legacy skill copies

**Files:**
- Delete: `skills/workflows/product-planning.md`, `skills/workflows/technical-planning.md`, `skills/workflows/technical-development.md`, `skills/workflows/technical-review.md`, `skills/workflows/technical-delivery.md`
- Delete: `skills/methodology/memory-protocol.md`, `skills/methodology/tdd-workflow.md`, `skills/methodology/board-progression.md`
- Delete: `skills/reference/fenix-tools-quickref.md`
- Delete: `skills/bootstrap/using-allye.md`

- [ ] **Step 1: Remove the files**

```bash
git rm skills/workflows/product-planning.md skills/workflows/technical-planning.md \
  skills/workflows/technical-development.md skills/workflows/technical-review.md \
  skills/workflows/technical-delivery.md skills/methodology/memory-protocol.md \
  skills/methodology/tdd-workflow.md skills/methodology/board-progression.md \
  skills/reference/fenix-tools-quickref.md skills/bootstrap/using-allye.md
```

- [ ] **Step 2: Remove the now-empty parent directories**

```bash
rmdir skills/workflows skills/methodology skills/reference skills/bootstrap
```

- [ ] **Step 3: Verify no legacy directories remain**

Run: `find skills -maxdepth 1 -mindepth 1 -type d | sort`
Expected output (exactly these 11 — the 10 `allye-*` dirs untouched so far plus `using-allye`):
```
skills/allye-board-progression
skills/allye-memory-protocol
skills/allye-product-planning
skills/allye-setup
skills/allye-tdd-workflow
skills/allye-technical-delivery
skills/allye-technical-development
skills/allye-technical-planning
skills/allye-technical-review
skills/allye-tools-quickref
skills/using-allye
```

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove dead legacy skill copies (workflows/methodology/reference/bootstrap)"
```

## Task 2: Delete non-interactive subagent definitions

**Files:**
- Delete: `agents/allye-planner.md`, `agents/allye-builder.md`, `agents/allye-deliverer.md`

- [ ] **Step 1: Remove the files**

```bash
git rm agents/allye-planner.md agents/allye-builder.md agents/allye-deliverer.md
```

- [ ] **Step 2: Verify only the reviewer agent remains**

Run: `ls agents/`
Expected: `allye-reviewer.md`

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: remove agents/{planner,builder,deliverer} — interactive roles can't be dispatched subagents"
```

## Task 3: Rename skill directories to bare names

**Files:**
- Rename (via `git mv`), 10 directories under `skills/`

**Interfaces:**
- Produces: `skills/product-planning/`, `skills/technical-planning/`, `skills/execution/`, `skills/review/`, `skills/delivery/`, `skills/memory-protocol/`, `skills/tdd-workflow/`, `skills/board-progression/`, `skills/tools-quickref/`, `skills/setup/` — each still containing its `SKILL.md` (and `skills/execution/`'s content is `allye-technical-development`'s, `skills/review/`'s is `allye-technical-review`'s, `skills/delivery/`'s is `allye-technical-delivery`'s — role-aligned renames per spec §9.2/§10)

- [ ] **Step 1: Rename the directories**

```bash
git mv skills/allye-product-planning skills/product-planning
git mv skills/allye-technical-planning skills/technical-planning
git mv skills/allye-technical-development skills/execution
git mv skills/allye-technical-review skills/review
git mv skills/allye-technical-delivery skills/delivery
git mv skills/allye-memory-protocol skills/memory-protocol
git mv skills/allye-tdd-workflow skills/tdd-workflow
git mv skills/allye-board-progression skills/board-progression
git mv skills/allye-tools-quickref skills/tools-quickref
git mv skills/allye-setup skills/setup
```

- [ ] **Step 2: Update each SKILL.md's frontmatter `name:` field to match its new directory**

Edit the `name:` line in each of these files (leave every other frontmatter field and all body content untouched):

| File | Old `name:` | New `name:` |
|---|---|---|
| `skills/product-planning/SKILL.md` | `allye-product-planning` | `product-planning` |
| `skills/technical-planning/SKILL.md` | `allye-technical-planning` | `technical-planning` |
| `skills/execution/SKILL.md` | `allye-technical-development` | `execution` |
| `skills/review/SKILL.md` | `allye-technical-review` | `review` |
| `skills/delivery/SKILL.md` | `allye-technical-delivery` | `delivery` |
| `skills/memory-protocol/SKILL.md` | `allye-memory-protocol` | `memory-protocol` |
| `skills/tdd-workflow/SKILL.md` | `allye-tdd-workflow` | `tdd-workflow` |
| `skills/board-progression/SKILL.md` | `allye-board-progression` | `board-progression` |
| `skills/tools-quickref/SKILL.md` | `allye-tools-quickref` | `tools-quickref` |
| `skills/setup/SKILL.md` | `allye-setup` | `setup` |

```bash
sed -i '0,/^name: allye-product-planning$/s//name: product-planning/' skills/product-planning/SKILL.md
sed -i '0,/^name: allye-technical-planning$/s//name: technical-planning/' skills/technical-planning/SKILL.md
sed -i '0,/^name: allye-technical-development$/s//name: execution/' skills/execution/SKILL.md
sed -i '0,/^name: allye-technical-review$/s//name: review/' skills/review/SKILL.md
sed -i '0,/^name: allye-technical-delivery$/s//name: delivery/' skills/delivery/SKILL.md
sed -i '0,/^name: allye-memory-protocol$/s//name: memory-protocol/' skills/memory-protocol/SKILL.md
sed -i '0,/^name: allye-tdd-workflow$/s//name: tdd-workflow/' skills/tdd-workflow/SKILL.md
sed -i '0,/^name: allye-board-progression$/s//name: board-progression/' skills/board-progression/SKILL.md
sed -i '0,/^name: allye-tools-quickref$/s//name: tools-quickref/' skills/tools-quickref/SKILL.md
sed -i '0,/^name: allye-setup$/s//name: setup/' skills/setup/SKILL.md
```

- [ ] **Step 3: Verify every renamed SKILL.md's frontmatter matches its directory, and no old names remain in frontmatter**

Run:
```bash
for f in skills/{product-planning,technical-planning,execution,review,delivery,memory-protocol,tdd-workflow,board-progression,tools-quickref,setup}/SKILL.md; do
  echo "$f: $(head -3 "$f" | grep '^name:')"
done
grep -rn "^name: allye-" skills/{product-planning,technical-planning,execution,review,delivery,memory-protocol,tdd-workflow,board-progression,tools-quickref,setup}/SKILL.md
```
Expected: the first loop prints each file's new bare name; the `grep` finds **nothing** (exit status 1, no output).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename skills/allye-* to bare, role-aligned names (execution/review/delivery)"
```

## Task 4: Rename the reviewer agent

**Files:**
- Rename: `agents/allye-reviewer.md` → `agents/reviewer.md`

- [ ] **Step 1: Rename**

```bash
git mv agents/allye-reviewer.md agents/reviewer.md
```

- [ ] **Step 2: Update its frontmatter `name:` field**

```bash
sed -i '0,/^name: allye-reviewer$/s//name: reviewer/' agents/reviewer.md
```

- [ ] **Step 3: Verify**

Run: `head -3 agents/reviewer.md | grep '^name:'`
Expected: `name: reviewer`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename agents/allye-reviewer.md to agents/reviewer.md"
```

## Task 5: Fix the session-start hooks

**Files:**
- Modify: `hooks/session-start.sh`
- Modify: `manifests/claude/hooks/session-start.sh`

**Interfaces:**
- Consumes: nothing new
- Produces: both scripts must still emit the same `hookSpecificOutput.additionalContext` JSON shape as before; only the legacy-path fallback and the drift between the two copies change

- [ ] **Step 1: Remove the dead bootstrap fallback in `hooks/session-start.sh`**

Find and delete these lines (currently around line 27-30):
```bash
# Fallback to legacy path if new structure doesn't exist yet
if [ ! -f "$LOCAL_SKILL" ]; then
  LOCAL_SKILL="$PLUGIN_ROOT/skills/bootstrap/using-allye.md"
fi
```
Leave the line above it (`LOCAL_SKILL="$PLUGIN_ROOT/skills/using-allye/SKILL.md"`) as the sole assignment — `skills/bootstrap/` no longer exists, so the fallback is now unreachable dead code.

- [ ] **Step 2: Sync `manifests/claude/hooks/session-start.sh` to match**

This file already lacks the tenant-slug auto-generation block that `hooks/session-start.sh` has (confirmed by diff — 8 missing lines) and still contains the same dead fallback as Step 1. Replace it entirely with the post-Step-1 content of `hooks/session-start.sh`, since the two are meant to be identical copies (one is the plugin-native hook, the other is what `install.sh` wires up for manual/non-marketplace installs):

```bash
cp hooks/session-start.sh manifests/claude/hooks/session-start.sh
chmod +x manifests/claude/hooks/session-start.sh
```

- [ ] **Step 3: Verify both scripts are syntactically valid and identical**

Run:
```bash
bash -n hooks/session-start.sh && echo "hooks/session-start.sh: OK"
bash -n manifests/claude/hooks/session-start.sh && echo "manifests copy: OK"
diff hooks/session-start.sh manifests/claude/hooks/session-start.sh && echo "IDENTICAL"
grep -c "skills/bootstrap" hooks/session-start.sh manifests/claude/hooks/session-start.sh
```
Expected: both print `OK`, `diff` prints `IDENTICAL` with no other output, and the final `grep -c` prints `0` for both files.

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start.sh manifests/claude/hooks/session-start.sh
git commit -m "fix: remove dead bootstrap fallback, sync session-start hook copies"
```

## Task 6: Fix `seed/seed-skills.json` source paths

**Files:**
- Modify: `seed/seed-skills.json`

**Interfaces:**
- Consumes: nothing new
- Produces: every `source_file` value resolves to an existing file after Task 1/3's deletes/renames

- [ ] **Step 1: Update every `source_file` value**

| `slug` (unchanged) | Old `source_file` | New `source_file` |
|---|---|---|
| `using-allye` | `skills/bootstrap/using-allye.md` | `skills/using-allye/SKILL.md` |
| `allye-memory-protocol` | `skills/methodology/memory-protocol.md` | `skills/memory-protocol/SKILL.md` |
| `allye-product-planning` | `skills/workflows/product-planning.md` | `skills/product-planning/SKILL.md` |
| `allye-technical-planning` | `skills/workflows/technical-planning.md` | `skills/technical-planning/SKILL.md` |
| `allye-technical-development` | `skills/workflows/technical-development.md` | `skills/execution/SKILL.md` |
| `allye-technical-review` | `skills/workflows/technical-review.md` | `skills/review/SKILL.md` |
| `allye-technical-delivery` | `skills/workflows/technical-delivery.md` | `skills/delivery/SKILL.md` |
| `allye-tdd-workflow` | `skills/methodology/tdd-workflow.md` | `skills/tdd-workflow/SKILL.md` |
| `allye-board-progression` | `skills/methodology/board-progression.md` | `skills/board-progression/SKILL.md` |
| `allye-tools-quickref` | `skills/reference/allye-tools-quickref.md` **(bug — never existed)** | `skills/tools-quickref/SKILL.md` |

Apply with `jq`:
```bash
jq '
  (.skills[] | select(.slug=="using-allye") | .source_file) |= "skills/using-allye/SKILL.md" |
  (.skills[] | select(.slug=="allye-memory-protocol") | .source_file) |= "skills/memory-protocol/SKILL.md" |
  (.skills[] | select(.slug=="allye-product-planning") | .source_file) |= "skills/product-planning/SKILL.md" |
  (.skills[] | select(.slug=="allye-technical-planning") | .source_file) |= "skills/technical-planning/SKILL.md" |
  (.skills[] | select(.slug=="allye-technical-development") | .source_file) |= "skills/execution/SKILL.md" |
  (.skills[] | select(.slug=="allye-technical-review") | .source_file) |= "skills/review/SKILL.md" |
  (.skills[] | select(.slug=="allye-technical-delivery") | .source_file) |= "skills/delivery/SKILL.md" |
  (.skills[] | select(.slug=="allye-tdd-workflow") | .source_file) |= "skills/tdd-workflow/SKILL.md" |
  (.skills[] | select(.slug=="allye-board-progression") | .source_file) |= "skills/board-progression/SKILL.md" |
  (.skills[] | select(.slug=="allye-tools-quickref") | .source_file) |= "skills/tools-quickref/SKILL.md"
' seed/seed-skills.json > /tmp/seed-skills.json.tmp && mv /tmp/seed-skills.json.tmp seed/seed-skills.json
```

- [ ] **Step 2: Verify the file is valid JSON and every path resolves**

Run:
```bash
jq empty seed/seed-skills.json && echo "VALID JSON"
jq -r '.skills[].source_file' seed/seed-skills.json | while read -r f; do
  test -f "$f" && echo "OK: $f" || echo "MISSING: $f"
done
```
Expected: `VALID JSON`, then 10 `OK:` lines, zero `MISSING:` lines.

- [ ] **Step 3: Verify slugs are unchanged (global constraint)**

Run: `jq -r '.skills[].slug' seed/seed-skills.json`
Expected: unchanged from before this task — still `using-allye`, `allye-memory-protocol`, `allye-product-planning`, `allye-technical-planning`, `allye-technical-development`, `allye-technical-review`, `allye-technical-delivery`, `allye-tdd-workflow`, `allye-board-progression`, `allye-tools-quickref`.

- [ ] **Step 4: Commit**

```bash
git add seed/seed-skills.json
git commit -m "fix: repoint seed-skills.json source_file paths to renamed dirs, fix tools-quickref path bug"
```

## Task 7: Remove the dead bootstrap-sync step from release automation

**Files:**
- Modify: `.releaserc.json`
- Modify: `release.sh`

- [ ] **Step 1: Edit `.releaserc.json`**

In the `@semantic-release/exec` `prepareCmd` string, remove this trailing segment (including the `&&` that precedes it):
```
 && cp skills/using-allye/SKILL.md skills/bootstrap/using-allye.md 2>/dev/null || true
```

In the `@semantic-release/git` `assets` array, remove this line:
```json
          "skills/bootstrap/using-allye.md",
```

- [ ] **Step 2: Edit `release.sh`**

Remove this block:
```bash
# Sync SKILL.md files (using-allye is the source of truth)
if [ -f "$SCRIPT_DIR/skills/using-allye/SKILL.md" ]; then
  cp "$SCRIPT_DIR/skills/using-allye/SKILL.md" "$SCRIPT_DIR/skills/bootstrap/using-allye.md"
fi
```

- [ ] **Step 3: Verify**

Run:
```bash
jq empty .claude-plugin/marketplace.json 2>/dev/null; jq empty .releaserc.json && echo "releaserc VALID JSON"
grep -c "bootstrap" .releaserc.json release.sh
bash -n release.sh && echo "release.sh: OK"
```
Expected: `releaserc VALID JSON`, `grep -c` prints `0` for both files, `release.sh: OK`.

- [ ] **Step 4: Commit**

```bash
git add .releaserc.json release.sh
git commit -m "chore: remove dead skills/bootstrap sync from release automation"
```

## Task 8: Repoint the OpenCode prompt generator

**Files:**
- Modify: `packages/allye-opencode/scripts/generate-prompts.ts`

**Interfaces:**
- Consumes: `skills/<name>/SKILL.md` (renamed paths from Task 3)
- Produces: `packages/allye-opencode/src/prompts/skills-content.ts` (unchanged shape — same exported constant names, only the source paths change)

- [ ] **Step 1: Update the `SKILL_SOURCES` table**

In `generate-prompts.ts`, replace the `SKILL_SOURCES` object:

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

(Left-hand exported constant names — `PRODUCT_PLANNING`, `TECHNICAL_PLANNING`, etc. — are unchanged; only the right-hand file paths change. This keeps every `import { PRODUCT_PLANNING } from "../prompts/skills-content"` in `packages/allye-opencode/src/agents/*.ts` working untouched.)

- [ ] **Step 2: Regenerate and verify (best-effort — skip if `bun` is unavailable in this environment)**

Run:
```bash
command -v bun >/dev/null 2>&1 && (cd packages/allye-opencode && bun run generate) || echo "bun not available — verify manually before next release"
```
Expected (if bun is available): 10 lines like `✓ USING_ALLYE (1234 chars)` with **no** `⚠ Skill not found` warnings, then `→ Generated: .../skills-content.ts`.

- [ ] **Step 3: Commit**

```bash
git add packages/allye-opencode/scripts/generate-prompts.ts
git status --short packages/allye-opencode/src/prompts/skills-content.ts  # include only if Step 2 regenerated it
git commit -m "fix: repoint allye-opencode generate-prompts.ts at renamed skill dirs"
```

## Task 9: Update top-level docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Rewrite `CLAUDE.md`'s runtime-flow paragraph (currently line 35)**

Replace:
```markdown
3. The orchestrator delegates to one of 4 subagents defined in `agents/*.md`: **allye-planner** (product + technical planning, discussion phase), **allye-builder** (TDD implementation), **allye-reviewer**, **allye-deliverer**. Each agent independently calls `initialize`, checks team context, searches memories, discovers team-specific skills via the `skills` MCP tool, and saves session state on exit.
```
With:
```markdown
3. Planning, development, and delivery run as skills loaded directly into the main conversation thread (not dispatched subagents) — `agents/reviewer.md` is the only Claude Code subagent shipped today, because code review is the one role that doesn't need to pause and ask the human mid-task. (A guided, multi-phase workflow — sandbox/discovery, orchestrated delivery — is being layered on top of this; see `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md` for the design in progress.)
```

- [ ] **Step 2: Update `README.md`'s skills table (currently lines 249-257)**

Replace:
```markdown
| `allye-product-planning` | Business requirements → Epics → Features → Stories |
| `allye-technical-planning` | Story → Discussion Phase → Tasks with acceptance criteria |
| `allye-technical-development` | Task → TDD → Implementation with wave execution |
| `allye-technical-review` | Code review with decision context from planning |
| `allye-technical-delivery` | Verify → Close story → Update docs → Save memory |
| `allye-memory-protocol` | When and how to search/save memories across sessions |
| `allye-tdd-workflow` | Red-Green-Refactor cycle with detection heuristic |
| `allye-board-progression` | Status transitions and board mechanics |
| `allye-tools-quickref` | Complete reference for all 12 MCP tools and 68+ actions |
```
With:
```markdown
| `product-planning` | Business requirements → Epics → Features → Stories |
| `technical-planning` | Story → Discussion Phase → Tasks with acceptance criteria |
| `execution` | Task → TDD → Implementation with wave execution |
| `review` | Code review with decision context from planning |
| `delivery` | Verify → Close story → Update docs → Save memory |
| `memory-protocol` | When and how to search/save memories across sessions |
| `tdd-workflow` | Red-Green-Refactor cycle with detection heuristic |
| `board-progression` | Status transitions and board mechanics |
| `tools-quickref` | Complete reference for all 12 MCP tools and 68+ actions |
```

- [ ] **Step 3: Verify no stale names remain in either file**

Run:
```bash
grep -n "allye-product-planning\|allye-technical-planning\|allye-technical-development\|allye-technical-review\|allye-technical-delivery\|allye-memory-protocol\|allye-tdd-workflow\|allye-board-progression\|allye-tools-quickref\|allye-planner\|allye-builder\|allye-deliverer" CLAUDE.md README.md
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: update CLAUDE.md and README.md for renamed skills and reviewer-only subagent"
```

## Task 10: Full-repo verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Confirm no stray references to renamed/deleted paths remain outside expected exceptions**

Run:
```bash
grep -rn "allye-product-planning\|allye-technical-planning\|allye-technical-development\|allye-technical-review\|allye-technical-delivery\|allye-memory-protocol\|allye-tdd-workflow\|allye-board-progression\|allye-tools-quickref\|allye-setup\|allye-planner\|allye-builder\|allye-deliverer" \
  --include="*.md" --include="*.ts" --include="*.json" --include="*.sh" . \
  | grep -v "node_modules\|\.git/\|docs/allye/specs\|docs/allye/plans\|CHANGELOG.md"
```
Expected output: **only** lines from `seed/seed-skills.json` where the match is inside a `"slug": "allye-..."` value (unchanged by design, per Global Constraints) and manifest files (`manifests/{codex,cursor,gemini}/*`, unchanged by design — they route by API slug). Anything else is a bug to fix before proceeding.

Also run (catches stale *path* references, not just slug names — found necessary in practice: `CLAUDE.md` referenced `skills/workflows/`, `skills/methodology/`, and `skills/bootstrap/` in prose even after the slug-name grep above passed clean):
```bash
grep -rn "skills/workflows\|skills/methodology\|skills/reference/fenix\|skills/bootstrap" \
  --include="*.md" --include="*.ts" --include="*.json" --include="*.sh" . \
  | grep -v "node_modules\|\.git/\|docs/allye/specs\|docs/allye/plans\|CHANGELOG.md"
```
Expected output: none.

- [ ] **Step 2: Confirm the legacy directories are gone and the new ones are in place**

Run:
```bash
test -d skills/workflows && echo "FAIL: workflows/ still exists"
test -d skills/methodology && echo "FAIL: methodology/ still exists"
test -d skills/reference && echo "FAIL: reference/ still exists"
test -d skills/bootstrap && echo "FAIL: bootstrap/ still exists"
for d in product-planning technical-planning execution review delivery memory-protocol tdd-workflow board-progression tools-quickref setup using-allye; do
  test -f "skills/$d/SKILL.md" && echo "OK: skills/$d/SKILL.md" || echo "FAIL: skills/$d/SKILL.md missing"
done
test -f agents/reviewer.md && echo "OK: agents/reviewer.md" || echo "FAIL: agents/reviewer.md missing"
test -f agents/allye-planner.md -o -f agents/allye-builder.md -o -f agents/allye-deliverer.md && echo "FAIL: a deleted agent file still exists"
```
Expected: zero `FAIL:` lines; 11 `OK: skills/...` lines and one `OK: agents/reviewer.md` line.

- [ ] **Step 3: If everything passes, this plan is complete — no commit needed for this task (verification only)**

## Execution notes (added after running this plan)

Real findings from executing Tasks 1-10, kept here for accuracy:

- **Parallel dispatch on a shared git working tree causes real index/commit races**, even across genuinely disjoint file sets — observed in both Wave 1 (Tasks 1+2) and Wave 3 (Tasks 7+8, whose commits merged into one because a plain `git commit` snapshots the whole index, not just what that task staged). Content ended up correct in every case; commit *attribution* sometimes didn't match 1:1 with task numbers. Future waves of parallel subagents on this repo should either use `git commit -- <exact paths>` (pathspec-scoped commit, not plain `git commit`) or accept that attribution may merge and verify content instead of commit count.
- **`skills/using-allye/SKILL.md`'s routing table, and every "load the `allye-technical-planning` skill"-style cross-reference inside the other skill files, are correct to leave as `allye-*`** — they're arguments to the Allye MCP `skill_list` tool call (fetching from the backend by its unchanged slug), not local Claude Code path references. Task 10's Step 1 grep flags these as matches; they are **expected**, alongside the `seed/seed-skills.json` and `manifests/{codex,cursor,gemini}` exceptions already noted.
- **One genuine bug found by the sweep that Task 9 didn't anticipate**: `hooks/session-start.sh` (and its `manifests/claude/` copy) told users to run `/allye-setup` to invoke the setup skill. `setup` is never seeded to the Allye backend (it's Claude Code-only, bundled), so unlike the other 9 skills it has no API-slug fallback identity — its slash-invocation needed an actual fix, to `/allye:setup` (also arguably a pre-existing bug even before this rename, since Claude Code's own namespacing rule was never `/allye-setup` to begin with). Fixed in a follow-up commit (`ed1e543`), along with a matching comment in `scripts/oauth-login.sh`.
- **`CLAUDE.md` had more stale content than Task 9 originally scoped** (it only targeted one paragraph) — lines describing `skills/bootstrap/` as a "synced copy," the hook's legacy fallback, and the old `skills/workflows/`/`skills/methodology/` split were all still present. Fixed directly (the file is untracked in this repo, never committed, so no commit was needed for this fix).

## What comes next

With the ground cleared, the remaining spec sections become their own plans, written and executed in this order:

1. **Handover Catalog** (`skills/handover-protocol/` — marker spec + 6 `references/<type>.md` templates)
2. **Sandbox** (`skills/sandbox/` + `agents/deep-search.md` + `agents/code-analyzer.md`)
3. **Orchestrator** (`skills/orchestrator/` — assignee management, dispatch, correction loop, cascade)
4. **Phase-skill deltas** (squares/reuse-or-create in `product-planning`; mandatory architecture gray area + granularity in `technical-planning`; single-story scope in `execution`) — each wired to its Handover Catalog entry; also folds in the `tools-quickref` content cleanup from spec §8 (add `team_members`, `assignee_id`, `subtask`/`spike`/`hotfix` types, `work_category` required-ness — still missing after this plan, since Plan 1 only fixed its *path*, not its *content*)
5. **OpenCode package rework** (delete `generate-prompts.ts`, runtime skill-reading adapter, add the Orchestrator role)
6. **Manifest updates** (`manifests/{codex,cursor,gemini}`) — add the Sandbox/Orchestrator routing rows and the handover-marker detection paragraph once those skills exist (Plan 1 leaves these files untouched, since API slugs are unchanged)

Each gets written as its own plan once the prior one is merged, per writing-plans' own philosophy of not over-planning ahead of execution.
