# Agent Runtime and Phase Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Orchestrator deliver several independent stories at once — each in its own git worktree, each driven by a real agent process the human can watch and take over — and let each workflow phase run on whichever agent CLI the user chose for it.

**Architecture:** A five-primitive contract defines what any runtime must do; a reference file holds the Herdr commands that satisfy it. The Orchestrator resolves its dispatch mode from what the session hook detected, and owns the worktree lifecycle. Results never come from a terminal — they come from Allye, which is what makes the harvesting problem disappear.

**Tech Stack:** Markdown skills with a `references/` subdirectory, git worktrees, the `herdr` CLI, `jq`. No build step, no test framework.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract.** Never rename one.
- **Skill files stay in English.**
- **Frontmatter keys are `name`, `description`, `version`, `category`.** Bump `version` minor on any skill changed.
- **Adapted content carries an inline credit comment.**
- **Do not push. Do not merge to `main`.**
- **Apply the authoring doctrine to `orchestrator`, `setup`, `handover-protocol`, and `using-allye`** — all four were excluded from the earlier pass because this plan rewrites them.
- **Never widen Herdr's own safety rules.** Do not close a pane, tab, workspace, or session the plugin did not create. Never run `herdr server stop`. Every wait carries a `--timeout`.

## Prerequisites

Plans 01, 02, and 03 complete and merged into this plan's base branch.

Note the shape of the first check. `work_item_id` **does** still appear in `skills/tools-quickref/SKILL.md`, in the gotcha entry Plan 01 added explaining that the parameter does not exist. That is the documentation of the fix, not the defect. Assert on the parameter-assignment form, which matches a call site and never prose.

```bash
grep -rnE '^[[:space:]]*(work_item_id|sprint_id):' skills/   # expect: no output   (Plan 01)
grep -c 'Agent runtime:' hooks/session-start.sh       # expect: at least 1     (Plan 01)
ls skills/verification-loop/SKILL.md                  # expect: exists         (Plan 02)
ls agents/reviewer-standards.md agents/reviewer-spec.md  # expect: both exist  (Plan 03)
```

---

### Task 1: Create the `agent-runtime` skill

**Files:**
- Create: `skills/agent-runtime/SKILL.md`
- Create: `skills/agent-runtime/references/herdr.md`

**Interfaces:**
- Consumes: the `Agent runtime: ` line the session hook emits (Plan 01 Task 4). That prefix is the contract.
- Produces: five primitive names — `detect`, `spawn`, `dispatch`, `wait`, `collect` — referenced by Task 2. Do not rename them there.

- [x] **Step 1: Write the contract**

Create `skills/agent-runtime/SKILL.md`:

```markdown
---
name: agent-runtime
description: Contract for driving an external agent runtime — spawning real agent processes in panes, dispatching work to them, and collecting results. Use when the session hook reported a runtime and work is about to be dispatched in parallel.
version: "1.0"
category: methodology
---

# Agent Runtime

An **agent runtime** owns real agent processes the human can watch, attach to, and take
over. This skill defines what the plugin needs from one, so the Orchestrator can drive
any runtime that satisfies the contract rather than one specific tool.

Load this only when the session hook reported a runtime. Without one, dispatch falls back
to the manual handover and the dispatched-subagent modes, both of which work unchanged.

Concrete commands for the runtimes we implement live in `references/`. This file is the
contract; the reference is the implementation.

<!-- adapted from ogulcancelik/herdr SKILL.md (Apache-2.0) — the primitive vocabulary and the safety rules -->

## The five primitives

### 1. detect

Answer two questions, not one: does the tool exist, and **is this session running inside
it**. A binary on `PATH` says nothing about the second.

A runtime that fails any part of detection is **absent**, never **broken**. A version
mismatch, an unreachable server, a missing environment variable — each means fall back to
asking the user manual-or-automatic. A degraded runtime must never block delivery.

### 2. spawn

Produce an isolated execution location and return a **stable identifier** for it. The
location must be a shell at an interactive prompt with nothing running in the foreground,
and creating it must not steal the human's focus.

<HARD-GATE>
**Wait for the shell; do not merely inspect it.** A pane created a moment ago is often
still running the shell's startup — a banner, a version manager, a greeting. Dispatching
into it fails. Poll for a bare shell with a bound, and treat a pane still busy after the
bound as a problem to report rather than one to keep waiting on.
</HARD-GATE>

### 3. dispatch

Deliver the briefing and **confirm it was accepted**.

<HARD-GATE>
Confirmation is part of the primitive, not an optional check. Sending text to an agent
that is idle can leave it sitting in the input box unsubmitted — the agent looks dispatched
and is not. After dispatching, read the agent's state back. If it has not moved to a
working state, submit explicitly and read it again.
</HARD-GATE>

### 4. wait

Block until the agent's lifecycle state settles. **Always with a timeout** — an unbounded
wait on a stalled agent hangs the whole delivery.

<HARD-GATE>
A settled state does not prove completion. "Idle" can mean finished, or an API error
mid-turn, or a question sitting unanswered on screen. An "unknown" state proves nothing at
all.

Runtime state is **evidence**. The verdict comes from `collect`.
</HARD-GATE>

**`wait` is not how the Orchestrator blocks — it is how the runtime's lifecycle becomes an
event in whatever system the Orchestrator actually lives in.** Run it as a background job
of the host harness so its completion arrives as a notification. Polling the agent's state
by hand works and is wrong: it makes every check an arbitrary interruption, and a finished
agent sits unnoticed until the next one. **A dispatch without a wait registered is a story
nobody is listening for**, so registering it is the closing step of `dispatch`, not a
separate thing to remember.

A future runtime satisfies this primitive only if its wait can be bridged that way.

### 5. collect

Read the result **from Allye**:

- `work_children(id: "{story uuid}")` — the real status of every task
- `memory_search("Review {STORY-KEY}")` — the review findings
- `memory_search("Implementation {TASK-KEY}")` — what was done and why

The terminal is for human observation and for diagnosing a stuck agent. It is never the
source of the result, for three reasons that hold regardless of what the terminal can show:

- A record in Allye is structured and machine-readable; a transcript is prose to be parsed.
- The Orchestrator can read it from a pane it never created, and after that pane is closed.
- It works identically for every runtime, including those with no output-read primitive at
  all — which is most of the category.

There is also a documented failure mode where full-screen agents render on the terminal's
alternate screen and those rows never reach scrollback, making a long report unrecoverable.
**Treat that as a caveat, not the reason.** It did not reproduce in testing on 2026-07-26,
and a design justified by a failure that does not reproduce is one experiment away from
being abandoned for the wrong reason.

An agent that has settled but left no trace in Allye has produced an **incomplete report**.
Treat it the way §5 of `orchestrator` already treats one: ask for more, do not wave it
through.

## The obligation on the dispatched side

The contract closes only because the dispatched agent carries the other half:

> **Before settling, leave a durable trace in Allye.** Executor: task statuses advanced,
> plus an implementation memory. Reviewer: a memory holding the findings.

This is already what `execution` and `review` do. Here it becomes load-bearing rather than
good practice — it is the entire result channel.

## Teardown

Destroy only what you created, and only after the work it held is merged and verified.
Never close a pane, tab, workspace, or session the plugin did not create. Never stop the
runtime's server.

## Implementations

- Herdr — `references/herdr.md`
```

- [x] **Step 2: Write the Herdr reference**

Create `skills/agent-runtime/references/herdr.md`:

```markdown
# Runtime implementation: Herdr

Herdr is a terminal multiplexer that recognizes coding agents inside panes and exposes
them over a CLI. Its mental model: `workspace (w1) → tab (w1:t1) → pane (w1:p1)`, with an
**agent** being a recognized process inside a pane. A pane exists whether or not it holds
an agent, and starting an agent never creates or moves layout — topology is the caller's job.

Agent names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents. Use
`story-beac-1716`, never `BEAC-1716`.

## detect

```bash
[ "${HERDR_ENV:-}" = "1" ] || exit 1        # not inside a pane
command -v herdr >/dev/null || exit 1
herdr status | grep -q 'compatible: yes' || exit 1
```

The session hook already runs this and reports the result. Re-run it only if a dispatch
fails in a way that suggests the server went away.

Caller context is injected into every managed pane: `$HERDR_PANE_ID`, `$HERDR_TAB_ID`,
`$HERDR_WORKSPACE_ID`.

## spawn

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
```

Read the pane's dimensions from `.result.layout.area`. **Split a wide pane to the right and
a narrow or tall one down.** Repeated splits in one direction produce columns too narrow to
read.

```bash
herdr pane split --current --direction right --cwd "$CWD" --no-focus
# new pane id: .result.pane.pane_id
```

`--no-focus` keeps the human where they were. **Wait** for the pane to reach a bare shell —
a pane created a second ago is usually still running the shell's startup, and `agent start`
fails with `agent_pane_busy`:

```bash
for _ in $(seq 1 10); do
  FG=$(herdr pane process-info --pane "$PANE" | jq -r '.result.process_info.foreground_processes[0].name')
  case "$FG" in zsh|bash|sh|fish) break;; esac
  sleep 3
done
```

Bounded, not infinite. A pane still busy after thirty seconds is a problem to report.

## dispatch

```bash
herdr agent start {name} --kind {kind} --pane {pane_id} --timeout 120000 -- {native args}
herdr agent prompt {name} "$(cat {briefing file})"
herdr agent get {name} | jq -r '.result.agent.agent_status'
```

The third command is mandatory, not diagnostic — and **expect to need the fourth.**
Prompting an idle agent left the text unsubmitted in every observed dispatch, so treat this
as a two-step operation rather than a rare branch. When the status does not read `working`:

```bash
herdr agent send-keys {name} enter
herdr agent get {name} | jq -r '.result.agent.agent_status'
```

`--kind` accepts, among others: `claude`, `codex`, `opencode`, `pi`, `gemini`, `cursor`,
`copilot`, `amp`, `droid`. Native arguments pass verbatim after `--`.

Named failure: `agent_prompt_stalled`, returned when no lifecycle change is observed within
five seconds of prompting a non-working agent.

## wait

```bash
herdr agent wait {name} --timeout 3600000
```

**Run it as a background job of your own harness**, so its exit arrives as a notification
rather than something you have to remember to check. That bridge is the point of the
primitive — see the contract's §4. Do not poll `agent get` in a loop: the wait is
server-side and event-driven, and polling turns every check into an arbitrary interruption
while leaving a finished agent unnoticed between them.

Across all panes at once:

```bash
herdr agent list | jq -r '.result.agents[] | "\(.pane_id)\t\(.agent)\t\(.agent_status)\t\(.cwd)"'
```

`herdr agent read` returns **plain text, not JSON** — piping it to `jq` fails.

To understand why a pane was classified as it was:

```bash
herdr agent explain {name} --json --verbose
```

## collect

Read from Allye — see the contract. The terminal is diagnostic only:

```bash
herdr agent read {name} --source recent-unwrapped --lines 200
```

Sources are `visible`, `recent`, `recent-unwrapped`, and `detection`. Prefer
`recent-unwrapped` for transcripts. If raising `--lines` reveals nothing more, the agent is
rendering on the alternate screen and the rows are gone — this is expected, and is why the
result channel is Allye.

## answering a blocked agent

A `blocked` state means Herdr recognized an approval or question UI. Read the pane before
answering — the question may be one whose options are all wrong:

```bash
herdr agent read {name} --source recent-unwrapped --lines 120
```

If a selection UI is open and your answer is not one of its options, **dismiss it first**.
Sending a prompt into an open menu risks the text being read as menu navigation:

```bash
herdr agent send-keys {name} esc
```

Then dispatch normally, including the submit confirmation — a freshly dismissed menu leaves
the agent idle, which is exactly the state where a prompt lands unsubmitted.

## teardown

```bash
herdr pane close {pane_id}
```

Only panes the plugin created, and only after §7.6's merge gates have passed.

## Safety rules — never widened

- Never run bare `herdr` for discovery; it launches or attaches the TUI. Discover with
  `herdr agent`, `herdr pane`, `herdr workspace` — a group name with no subcommand prints
  its help.
- Never probe a mutating command by omitting its arguments. `herdr workspace create` is
  valid with defaults and will execute.
- Never run `herdr server stop`. Never kill the main Herdr process.
- Never close a workspace, tab, pane, or session the plugin did not create.
- Always pass `--timeout`. Omitting it allows an indefinite wait.
- Parse identifiers out of JSON responses. Never derive them from sidebar order or from
  the examples above.
```

- [x] **Step 3: Verify**

```bash
sed -n '1,7p' skills/agent-runtime/SKILL.md
for p in detect spawn dispatch wait collect; do
  printf '%-10s SKILL=%s ref=%s\n' "$p" \
    "$(grep -c "$p" skills/agent-runtime/SKILL.md)" \
    "$(grep -c "^## $p" skills/agent-runtime/references/herdr.md)"
done
```
Expected: frontmatter complete; every primitive appears in the contract and has its own `##` section in the reference.

- [x] **Step 4: Commit**

```bash
git add skills/agent-runtime/
git commit -m "feat(skills): add the agent-runtime contract and Herdr reference

Five primitives — detect, spawn, dispatch, wait, collect — with the
contract in SKILL.md and Herdr's concrete commands in references/. The
result channel is Allye, not the terminal, which is what makes a
full-screen agent's unreadable scrollback stop mattering.

Detection failure means the runtime is absent, never broken, so a stale
install falls back to the existing dispatch modes instead of blocking."
```

---

### Task 2: Resolve dispatch mode and own the worktree lifecycle

**Files:**
- Modify: `skills/orchestrator/SKILL.md`

**Interfaces:**
- Consumes: Task 1's primitives; the AFK/HITL label from Plan 02; the two review axes from Plan 03.
- Produces: the dispatch-mode rule and the worktree lifecycle. Nothing later consumes it.

- [x] **Step 1: Establish the failing assertion**

```bash
grep -c 'agent-runtime' skills/orchestrator/SKILL.md
grep -c 'worktree' skills/orchestrator/SKILL.md
```
Expected: `0` for both.

- [x] **Step 2: Replace §4's mode question with mode resolution**

<HARD-GATE>
**The text you are replacing is fenced, and your replacement must be too.**

`skills/orchestrator/SKILL.md` carries twelve `<!-- opencode-exclude:start --> / <!-- opencode-exclude:end -->` pairs. The mode question at §4 sits inside one, and each Manual/Automatic bullet carries its own. They strip Claude-Code-only text from the prompt generated for OpenCode.

This is not cosmetic. **OpenCode has no `Agent` tool, no automatic-Executor mode, and no runtime integration** — its adapter lives in `packages/allye-opencode` and this spec does not extend it. An unfenced replacement would instruct an OpenCode agent to dispatch through mechanisms it does not have.

Fence accordingly: **the entire dispatch-mode resolution below is Claude-Code-only.** What OpenCode must keep seeing is the manual `story-execution` handover path and nothing else. Read the surrounding lines before editing so you fence at the right boundaries, and run `grep -c 'opencode-exclude' skills/orchestrator/SKILL.md` before and after — the count must not drop. If a marker genuinely goes because the text it fenced also went, say so in your report rather than letting it be a side effect.
</HARD-GATE>

§4 currently asks the user automatic-or-manual. Replace that question with:

```markdown
### 4.1 Resolve the dispatch mode — do not ask when the answer is known

1. **Did the session hook report an agent runtime?** (a line beginning `Agent runtime: `).
   If yes, load the `agent-runtime` skill and dispatch through it. This is the default —
   do not offer the other two modes alongside it, and do not ask which to use.
2. **No runtime?** Then ask: manual handover, or the dispatched `executor` subagent.

The runtime wins when present because a runtime pane is a real agent process the human can
watch, attach to, and take over, with its own context window. That is strictly more than
either fallback offers.
```

- [x] **Step 3: Add the parallel-dispatch section**

Insert a new §4.2 after it:

```markdown
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

3. **Sequential shared resources, allocated here and written into each briefing.** Migration
   numbers, ports, any self-incrementing id. Never instruct a pane to "check what is free":
   two panes both checking before either writes is a race, and it has already produced two
   stories claiming the same migration number.

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
```

- [x] **Step 4: Add the merge and teardown section**

Insert a new §7.1 immediately after the existing status cascade:

```markdown
### 7.1 Merge and teardown — one story at a time

Every step is a gate. Do not batch these across stories.

1. Both review axes clear (§6) → tasks to `done`, story to `done`.
2. **Gate:** `git -C <worktree> status --porcelain` must be empty. Dirty means stop —
   do not merge, do not remove, escalate to the human.
3. `git push -u origin feature/{story-key}-{slug}`.
4. In the main checkout, on `$BASE`: `git merge --no-ff feature/{story-key}-{slug}`.
5. Conflicts in shared wiring files are expected when parallel stories touch the same
   composition root. **Resolve by consolidating into one instance, never by picking a side** —
   picking a side silently deletes the other story's work while leaving its tests green.
6. Rebuild, typecheck, and run tests **before** committing the merge.
7. `git worktree remove <path>` — **without** `--force`.
8. `herdr pane close <pane_id>` — only after step 7.

Three properties make "no work lost" structural rather than careful:

| Step | What it guarantees |
|---|---|
| 3, push first | The branch exists on the remote before anything is destroyed. |
| 7, no `--force` | Git refuses a dirty worktree. That refusal is the last safety net — bypassing it by reflex is how work disappears. |
| 8, pane last | While the pane lives, the session's reasoning is still inspectable. Close it before a validated merge and the *why* is gone. |

**An abandoned or failed story gets no cleanup.** Worktree, branch, and pane all stay.
Visible litter costs far less than deleted work.
```

- [x] **Step 5: Apply the authoring doctrine to the whole file**

Run the no-op test sentence by sentence; collapse duplicated meaning. Do not touch: the two-correction maximum, the status cascade order, the assignee resolution mechanics, the epic-completion-is-manual rule, or the two-axis combination table from Plan 03.

- [x] **Step 6: Verify**

```bash
grep -c 'agent-runtime' skills/orchestrator/SKILL.md
grep -n 'Parallel work requires worktrees' skills/orchestrator/SKILL.md
grep -n 'allocated by the Orchestrator, in the dispatch briefing' skills/orchestrator/SKILL.md
grep -n 'Default to \*\*three\*\*' skills/orchestrator/SKILL.md
grep -n 'status --porcelain' skills/orchestrator/SKILL.md
grep -n 'without\*\* `--force`' skills/orchestrator/SKILL.md
grep -c 'reviewer-standards' skills/orchestrator/SKILL.md
grep -c 'opencode-exclude' skills/orchestrator/SKILL.md
```

Expected: `agent-runtime` present; each of the five distinctive sentences found exactly once — the worktree gate, the upfront-allocation rule, the concurrency default, the clean-tree gate, and the no-`--force` rule; Plan 03's `reviewer-standards` still present; and `opencode-exclude` **unchanged from what you measured before editing**.

These check the sentences each edit introduces rather than counting how often a word appears. A `worktree` count would pass just as happily if the word were sprinkled through prose that gates nothing.

- [x] **Step 7: Bump version and commit**

```bash
git add skills/orchestrator/
git commit -m "feat(orchestrator): dispatch through a runtime and own worktrees

Resolves dispatch mode from what the session hook detected rather than
asking, and adds the parallel-dispatch policy: one worktree per story,
dependencies and the HITL label checked first, sequential resources
allocated upfront, three concurrent by default.

Adds the merge and teardown gates, where pushing before removal,
refusing --force, and closing the pane last are what make 'no work lost'
structural instead of careful.

Also applies the skill-authoring doctrine to this file."
```

---

### Task 3: Create the delivery configuration document in `setup`

**Files:**
- Modify: `skills/setup/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a Core Document named `Allye Delivery Configuration`, loaded automatically by `initialize`. Task 2 reads `$BASE` and the copy-list from it.

- [x] **Step 1: Add the configuration step**

Append a new section to `skills/setup/SKILL.md`, after the platform-specific setup:

```markdown
## Step 3: Delivery configuration

Ask once, here, rather than at every dispatch. Five parallel stories would otherwise mean
ten identical questions whose answer never varies.

Check whether it already exists before asking anything:

```
user_config(action: "list")
```

If a document named `Allye Delivery Configuration` is present, show it and ask whether to
change it. Otherwise, ask the three questions below — one at a time — and create it.

**Question 1 — which agent runs which phase?** Offer the phases that can differ (planning,
technical planning, execution, review, correction) and let the user assign an agent kind to
each. The default is the agent they are running now, for every phase; accepting that default
is a completely reasonable answer and should take one word.

**Question 2 — what arguments does each agent need?** Model selection is not uniform: what
is `--model sonnet --permission-mode auto` for one agent is different syntax for the next.
Store the argument string verbatim; it is passed through unchanged.

**Question 3 — per repo, what is the base branch, and which gitignored files must a fresh
worktree receive?** A worktree inherits neither, and an executor that fails on a missing
`.env` reports a bug that is not one.

Create it:

```
user_config(
  action: "create",
  name: "Allye Delivery Configuration",
  content: "{the document below}"
)
```

Note the field is `name`, not `title` — this is the one tool in the suite that differs.

### Document format

```markdown
# Allye Delivery Configuration

## Phase routing

| Phase | Agent kind | Native args |
|---|---|---|
| product-planning | claude | --model sonnet --permission-mode auto |
| technical-planning | claude | --model sonnet --permission-mode auto |
| execution | opencode | |
| review | claude | --model sonnet --permission-mode auto |
| correction | opencode | |

## Repositories

| Repo | Base branch | Install command | Copy into a fresh worktree |
|---|---|---|---|
| allye-plugin | main | | |
| allye-api | develop | bun install | .env |

## Concurrency

Default parallel stories: 3
```

An empty cell means "nothing required" — leave it empty rather than writing "none", so the
table stays scannable.

### Preflight before routing a phase to a non-Claude agent

A dispatched agent that cannot reach Allye cannot read the story, move a status, or save the
memory the Orchestrator collects its result from — the dispatch will appear to succeed and
produce nothing. Before recording a non-Claude agent for any phase, confirm that agent has
Allye configured: the MCP connection, and for OpenCode the `allye-opencode` package. If it
does not, say so and point at the matching guide in `docs/install-*.md` rather than recording
a route that will fail on first use.

Platform capability also constrains the map. OpenCode has six agent personas; Cursor, Codex,
and Gemini CLI have one agent and no picker — routing a specific persona to them silently
does nothing.
```

- [x] **Step 2: Apply the authoring doctrine to the whole file**

Do not touch the OAuth-only rule or its `<EXTREMELY_IMPORTANT>` framing — "never ask for a PAT" is exactly the kind of prohibition that carries its own content.

- [x] **Step 3: Verify**

```bash
grep -n 'Allye Delivery Configuration' skills/setup/SKILL.md
grep -n 'action: "list"' skills/setup/SKILL.md
grep -n 'the field is `name`, not `title`' skills/setup/SKILL.md
grep -n 'Phase routing' skills/setup/SKILL.md
grep -n 'Base branch' skills/setup/SKILL.md
grep -n 'cannot reach Allye' skills/setup/SKILL.md
```

Expected: every one found. In order they prove the document is named, that setup checks for it before asking anything, that the `name`-not-`title` gotcha is stated, that the routing table and the per-repo base-branch column exist, and that the non-Claude preflight is present. A count of the document's name would prove none of these.

- [x] **Step 4: Bump version and commit**

```bash
git add skills/setup/
git commit -m "feat(setup): create the delivery configuration Core Document

Asks once, at install time, which agent runs which phase, what arguments
each needs, and per repo the base branch and the gitignored files a
fresh worktree must receive. Core Documents load automatically at
initialize, so the map arrives in context without anyone fetching it.

Includes a preflight: a non-Claude agent without Allye configured cannot
save the memory the Orchestrator collects results from, so the dispatch
would appear to succeed and produce nothing."
```

---

### Task 4: Carry the label and the durability doctrine in handovers

**Files:**
- Modify: `skills/handover-protocol/SKILL.md`
- Modify: `skills/handover-protocol/references/story-execution.md`

**Interfaces:**
- Consumes: the AFK/HITL label from Plan 02.
- Produces: handovers that survive being read by a different agent than the one that wrote them.

- [x] **Step 1: Add the durability rule to the mandatory checklist**

In `skills/handover-protocol/SKILL.md` §3, add a bullet:

```markdown
<!-- adapted from mattpocock/skills triage AGENT-BRIEF (MIT) — durability of handoff artifacts -->
- **Name interfaces and contracts, not file paths and line numbers.** Write "the `SkillConfig`
  type gains an optional `schedule` field", never "open `src/types/skill.ts` and edit line 42."
  A handover can be read hours later, by a different agent, in a worktree where the tree has
  already moved — a line number is wrong by then and a contract is not. The one exception is a
  snippet that encodes a decision more precisely than prose can (a schema, a state machine, a
  type shape); include it, trimmed to the decision.
```

- [x] **Step 2: Add the label to the story-execution template**

In `references/story-execution.md`, add to the "Before emitting, confirm" list:

```markdown
- The story's **AFK/HITL label** is stated. It was derived at planning time from whether every
  task carries a runnable verification command (see `verification-loop` §4). The Orchestrator
  reads it to decide whether this story can go to an unattended pane — omitting it forces a
  guess about whether a human needs to be watching.
```

And add a line to the template body, immediately after `### Story`:

```markdown
### Dispatch label
{AFK — every task has a runnable verification command | HITL — {TASK-KEY} declares verification: manual}
```

- [x] **Step 3: Apply the authoring doctrine to `SKILL.md`**

Do not touch the marker line format or the `**Skill to load:**` field name — both are parsed literally and translating or restyling either breaks auto-detection.

- [x] **Step 4: Verify**

```bash
grep -c 'Dispatch label' skills/handover-protocol/references/story-execution.md
grep -c 'line numbers\|line 42' skills/handover-protocol/SKILL.md
grep -c '🔄 Allye Handover' skills/handover-protocol/SKILL.md
```
Expected: the label present; the durability rule present; the marker still present and unchanged.

- [x] **Step 5: Bump version and commit**

```bash
git add skills/handover-protocol/
git commit -m "feat(handover-protocol): durability rule and the dispatch label

Handovers name interfaces and contracts rather than file paths and line
numbers — a handover read later, by another agent, in a worktree whose
tree has moved, needs a contract that is still true and not a line
number that is not.

story-execution now carries the AFK/HITL label so the Orchestrator reads
whether a human must be watching instead of guessing."
```

---

### Task 5: Route to the new skills from the bootstrap

**Files:**
- Modify: `skills/using-allye/SKILL.md`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: nothing downstream. This is the last task.

- [ ] **Step 1: Add the runtime line to the start-of-conversation steps**

In §1, after "Step 4: Greet the user", add:

```markdown
**Step 5: Note the runtime, if one was reported.** The session hook may have injected a line
beginning `Agent runtime: `. If it did, the `agent-runtime` skill is available and the
Orchestrator will dispatch through it. Do not load that skill now — it loads when work is
about to be dispatched, which is the whole point of it being a separate skill.
```

- [ ] **Step 2: Add the two skills to the loading guidance**

The decision table in §2 maps *user intent* to a phase skill, and neither new skill is a
phase — both are reached from other skills. Add a short paragraph beneath the table rather
than rows inside it:

```markdown
Two skills sit outside this table because no user request routes to them directly:
`verification-loop` is loaded by `execution` when a task is being verified, and
`agent-runtime` by `orchestrator` when parallel work is being dispatched. Both load on
demand, from the skill that needs them.
```

- [ ] **Step 3: Apply the authoring doctrine to the whole file**

This file is injected into **every** session by the hook, so it is the one place where a
no-op sentence is paid for by every user on every conversation. Prune hardest here.

Do not touch: the handover marker detection, the slug resolution table, the workflow gates,
the `<SUBAGENT-STOP>` block, or the language rule.

- [ ] **Step 4: Verify**

```bash
grep -c 'agent-runtime' skills/using-allye/SKILL.md
grep -c 'verification-loop' skills/using-allye/SKILL.md
grep -c '🔄 Allye Handover' skills/using-allye/SKILL.md
grep -c 'SUBAGENT-STOP' skills/using-allye/SKILL.md
wc -l skills/using-allye/SKILL.md
```
Expected: both new skills named; handover detection and the subagent stop intact; and the file **at most 192 lines** — its length before this task, measured 2026-07-26. A bootstrap that gained two references and got longer has not been pruned, and this file is injected into every session, so its length is paid by every user on every conversation.

- [ ] **Step 5: Bump version and commit**

```bash
git add skills/using-allye/
git commit -m "feat(using-allye): surface the runtime and the two on-demand skills

Notes a detected runtime at session start without loading the skill, and
explains why verification-loop and agent-runtime are absent from the
routing table — neither is a phase, both load from the skill that needs
them.

Also applies the skill-authoring doctrine. This file is injected into
every session, so a no-op sentence here is paid by every user on every
conversation."
```

---

### Task 6: Update the architecture documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update the counts and the flow**

`CLAUDE.md` §"Runtime flow" and §"Guided delivery workflow", and `README.md`'s "What you get", "Agents", and "Skills" sections all state the number of skills and subagents and describe a serial Orchestrator. After Plans 01–04 the counts are **16 skills** (14 original + `verification-loop` + `agent-runtime`) and **five agents** (`code-analyzer`, `deep-search`, `executor`, `reviewer-spec`, `reviewer-standards`).

Describe delivery as parallel-capable, and say plainly that parallelism requires a detected runtime and that everything degrades to the existing modes without one.

- [ ] **Step 2: Verify the counts against the tree**

```bash
ls -d skills/*/ | wc -l
ls agents/*.md | wc -l
grep -on '1[0-9] skills\|[0-9] agents\|[0-9] subagents' README.md CLAUDE.md
```
Expected: the directory counts are 16 and 5, and every count written in prose matches them.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: describe parallel delivery and the new skill and agent counts

Sixteen skills and five agents after this spec's four plans. Delivery is
now parallel-capable when a runtime is detected, and degrades to the
existing manual and subagent modes without one."
```

---

## What this plan deliberately does not do

- **No second runtime implementation.** The contract documents what a second provider would need; only Herdr is implemented. Research found that most of the category has no programmatic control surface at all, so a second implementation would be speculative rather than validating.
- **No task-level parallelism.** Sibling panes sharing one worktree for independent tasks within a story stays out of scope, per the spec's non-goals.
- **No resolution of the worktree-cwd question.** Spec §13 records it as needing an empirical test. Until that test runs, the conservative rule stands: cwd at the plugin-enabled root, absolute worktree paths in the briefing. Being wrong in this direction costs verbosity; being wrong in the other kills the session.
- **No automatic runtime installation.** If Herdr is absent, the plugin says nothing about it. Suggesting an install for a capability the user never asked for is noise in every session that does not want it.
