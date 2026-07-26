# Agent Runtime, Verification Loop, and Skill Doctrine

**Status:** Approved — 2026-07-26 (all sections approved section-by-section during the brainstorm)
**Author:** Bruno Fernandes (via brainstorming session with Claude)
**Extends:** `2026-07-12-guided-delivery-workflow-design.md` — that spec built the six-phase guided delivery workflow; this one makes delivery parallel, makes "done" verifiable, and makes the phases agent-agnostic.

## 1. Problem

The guided delivery workflow shipped and works, but three things it assumed are no longer true, and one thing it never addressed.

1. **Delivery is strictly serial.** The Orchestrator dispatches one story at a time and waits. There is no mechanism for running several stories concurrently, even when they are mutually independent. Bruno has already run parallel delivery by hand — Épico 10 (BEAC-1610, 5 stories / 22 tasks, 2026-07-23) — using Herdr panes and git worktrees, and it worked. That pattern lives in two personal memory files and nowhere in the plugin.

2. **"Done" is asserted, not proven.** A task carries acceptance criteria and a `## How to Verify` section, both prose. The Executor runs tests once and reports; the Reviewer reads and judges. Nothing loops. A trivial test failure costs a full correction round through the Orchestrator, and the Orchestrator only allows two before escalating. Worse: **nothing verifies a story end-to-end.** All tasks green does not mean the story works, and no phase checks.

3. **Every phase assumes one agent.** The plugin ships to five platforms, but a single delivery runs entirely inside whichever agent the user launched. There is no way to plan in Claude Code and execute in OpenCode, even though the handover format was deliberately designed to be portable across tools (see `2026-07-12` spec §5.3).

4. **The skills have no authoring doctrine.** The `2026-07-12` spec §7 listed `anthropics/skills` skill-creator as a source for "QA our own skills." That never shipped. There is no shared standard for what makes an Allye skill good, and the corpus has accumulated duplication and stale layers accordingly.

Two defects surfaced while designing this and are fixed as part of it — see §12.

## 2. Goals

- Parallel delivery at the **story** level, using whatever agent runtime the user actually has, with git worktrees as a non-negotiable isolation boundary and a merge-and-teardown flow that cannot lose work.
- A **verification loop** that proves the planned thing works, at two granularities, bounded so it cannot spin.
- **Phase-to-agent routing** configured once, so planning, execution, and correction can each run on a different agent CLI.
- Adopt the parts of `mattpocock/skills` that make the above concrete, and apply its authoring doctrine across the whole skill corpus.
- **Cost nothing in context to users who have none of this.** A user without a runtime must not pay a single token for the runtime skill.

## 3. Non-goals

- **Not task-level parallelism.** Sibling panes sharing one worktree for independent tasks inside a story is a real pattern Bruno has used, but it is out of scope here. Story-level only.
- **Not a new planning artifact.** No RFC document. The acceptance criteria that already exist on stories and tasks are the source of truth; the gap is that they are not executable, not that they are missing.
- **Not replacing Claude Code's native parallelism.** `claude --worktree`, `/batch`, and agent teams exist and are good. They are Claude-only. This design targets heterogeneous agent fleets, which native parallelism cannot address. The two are complementary.
- **Not a runtime dependency on Herdr.** Herdr is the reference implementation of a contract, not a requirement. Absent any runtime, the existing manual/automatic dispatch modes remain fully functional.

## 4. Decisions taken (Bruno, 2026-07-26)

| # | Decision | Rationale |
|---|---|---|
| D1 | One spec covering all three workstreams | Chosen over decomposing into separate specs |
| D2 | Story-level parallelism only | Task-level deferred; story is the expensive unit |
| D3 | A detected runtime is the **default** dispatch path, not a third option offered | "If there's a runtime, use it; if not, then ask manual vs automatic" |
| D4 | Contract of five primitives, Herdr as the sole implementation in this spec | Research showed very few tools are drivable at all — see §6.5 |
| D5 | Verification loop at **task and story** granularity | Closes both the wasted-correction-round hole and the green-tasks-broken-feature hole |
| D6 | Phase→agent map lives in an Allye Core Document, created during `setup` | Auto-loaded by `initialize`; configuration, not per-dispatch interrogation |
| D7 | Full Pocock doctrine adoption, including rewriting all 14 existing skills | Split across two workstreams to avoid concurrent edits — see §10.2 |
| D8 | **Panes replace dispatched subagents** for Executor and Reviewer | Real, watchable processes; own context window; no parent-context cost |
| D9 | **Except** `deep-search` and `code-analyzer`, which stay Agent-tool subagents | Short, read-only, no durable artifact — they lose on pane cold start |
| D10 | **Worktrees are mandatory for parallel work** | No two concurrent stories ever share a checkout |

## 5. Architecture

```
                        hooks/session-start.sh
                    (probes; injects one line if a runtime exists)
                                 │
                          skills/using-allye
                       (routes; already detects handovers)
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
  technical-planning        orchestrator              execution
  requires a verify     resolves dispatch mode:     runs the
  command per task       runtime > ask              verification loop
        │                        │                        │
        │              ┌─────────┴─────────┐              │
        │              │                   │              │
        │      skills/agent-runtime   agents/executor      │
        │      (contract + Herdr)     (no-runtime fallback)│
        │              │                                   │
        └──────────────┴────────► skills/verification-loop ◄┘
                                          │
                    ┌─────────────────────┴──────────────────┐
              reviewer-standards                      reviewer-spec
              (conventions, quality)          (is this what was asked for?)
                    └──────────► NEVER merged or reranked ◄──┘
```

**Two new skills, both loaded on demand:**

- `skills/agent-runtime/` — the five-primitive contract, plus `references/herdr.md` with the concrete implementation. Loaded only when a runtime was detected.
- `skills/verification-loop/` — the loop criteria, the bound, the escape hatch. Reached from `execution` and from `agents/executor.md`.

**Seven skills edited:** `orchestrator`, `execution`, `technical-planning`, `review`, `setup`, `using-allye`, `handover-protocol`.

**One agent becomes two:** `agents/reviewer.md` splits into `agents/reviewer-standards.md` and `agents/reviewer-spec.md`. The split is at the Orchestrator level, not inside the Reviewer, because a dispatched agent cannot dispatch further — the Agent tool belongs to the Orchestrator.

### 5.1 The context-load answer

This is the load-bearing constraint, and the hook is the answer. `hooks/session-start.sh` already injects `additionalContext` and is proven to work on this platform. It gains a cheap probe and emits one line:

```
Agent runtime: herdr 0.7.5 (pane w2:p1, workspace w2)
```

or nothing at all. Cost to a user without a runtime: **zero**. Cost to a user with one: roughly 15 tokens, with the full skill loading only when the Orchestrator is actually about to dispatch.

## 6. The agent-runtime contract

Five operations and two obligations. The contract is deliberately thin: **the heavy lifting of results happens in Allye, not in the runtime.**

### 6.1 `detect`

Must answer two distinct questions: does the tool exist, and *is this session running inside it*. A binary on `PATH` is not sufficient.

```bash
[ "${HERDR_ENV:-}" = 1 ] || exit 0
command -v herdr >/dev/null || exit 0
herdr status        # require compatible: yes, restart_needed: no
```

**Failure mode:** client/server protocol mismatch after an update. Treated as *runtime absent*, never as *runtime broken* — a degraded runtime must not block delivery.

### 6.2 `spawn`

Must return a stable identifier and a shell sitting at an interactive prompt, without stealing focus.

```bash
herdr pane layout --pane "$HERDR_PANE_ID"     # wide → right; narrow or tall → down
herdr pane split --current --direction right --cwd "$CWD" --no-focus
# → .result.pane.pane_id
```

**Failure mode:** repeated same-direction splits producing unusably narrow columns. `pane layout` before every split is what prevents it.

### 6.3 `dispatch`

Delivers the briefing and **confirms it was accepted**.

```bash
herdr agent start {name} --kind {kind} --pane {id} -- {native args}
herdr agent prompt {name} "$(cat handover.md)"
herdr agent get {name} | jq -r '.result.agent.agent_status'   # MUST read "working"
```

The confirmation is not ceremony. A prompt sent to an `idle` agent can land in the input box without submitting. If the status has not flipped, send `herdr agent send-keys {name} enter` and re-check.

Agent names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents — so `story-beac-1716`, never `BEAC-1716`.

**Named failure:** `agent_prompt_stalled`, returned when no lifecycle change is observed within five seconds.

### 6.4 `wait`

```bash
herdr agent wait {name} --timeout 3600000      # NEVER omit the timeout
```

Runs in the background; never polled. And the most important rule in the contract:

> `idle` / `done` **does not prove completion.** It can mean genuinely finished, an API connection error mid-turn, or a legitimate interactive question waiting on screen. `unknown` explicitly proves nothing. Runtime state is **evidence, never a verdict.**

The verdict comes from `collect`.

### 6.5 `collect`

The result is read **from Allye**, not from the terminal:

```
memory_search("Review {STORY-KEY}")        → reviewer findings
work_children(id: "{story uuid}")          → real task statuses
memory_search("Implementation {TASK-KEY}") → implementation notes
```

The terminal is a human observation and diagnostic channel (`herdr agent read {name} --source recent-unwrapped`), never the source of truth. Full-screen agents such as Claude Code render on the terminal's alternate screen; those rows never enter the host scrollback, so a larger `--lines` cannot recover them. Reading a long report off a pane is unreliable by construction.

If the agent is `idle` but the expected trace is absent from Allye, that is an **incomplete report** — which the Orchestrator already knows how to handle, since it verifies report completeness before acting on it.

### 6.6 Obligation on the dispatched side

The contract only closes because the pane agent carries a symmetric duty:

> **Before going idle, leave a durable trace in Allye.** Executor: task statuses at `review` plus an implementation memory. Reviewer: a memory holding the findings.

This is already the behaviour of the `execution` and `review` skills. This spec makes it **load-bearing** rather than good practice.

### 6.7 Obligation to tear down

Whoever created it destroys it, and nothing else. Herdr's own hard rule: *"Do not close workspaces, tabs, panes, or sessions you did not create."*

### 6.8 Why this contract, and what else could satisfy it

Research (2026-07-26) verified 20+ tools in the agent-multiplexer category. Very few expose all of spawn / dispatch / wait / collect:

| Tool | spawn | dispatch | wait | collect | detect |
|---|:--:|:--:|:--:|:--:|---|
| **Herdr** | ✅ | ✅ | ✅ | ✅ | `HERDR_ENV=1` |
| Conductor | ✅ | ✅ | ✅ | ✅ | none — cloud REST + API key |
| HumanLayer `hld` | ✅ | ✅ | ✅ SSE | ✅ | partial; Claude-only |
| zjctl (Zellij) | ✅ | ✅ | ✅ | ✅ | 13 stars; linux-x86_64 binaries only |
| cmux | ✅ | ✅ | ❌ | ❌ | `CMUX_WORKSPACE_ID`; macOS only |
| uzi | ✅ | ✅ | ❌ | scrape | — |
| Sculptor, Nimbalyst, Crystal, superset, coder/mux, Termdock, dmux, claude-squad, Maestri | — | — | — | — | **human UI only, no API** |

Two findings worth recording because they justify D4:

- **Herdr is genuinely best-in-class for this contract.** It was not chosen for convenience.
- **Allye-as-result-bus widens the field.** `collect` stops being the runtime's problem, so cmux would fail only on `wait` — which could be emulated by polling `agent_status`.

Also recorded: there is **no standard** for agent lifecycle state. Herdr's own published proposal (`working`/`blocked`/`idle`) has no other implementers. The nearest real standard is Zed's **ACP** (Agent Client Protocol) — JSON-RPC over stdio, with a live registry and JetBrains/Zed integration, Gemini CLI native, Claude Code and Codex via adapters — but it is an editor↔agent protocol expressing permission requests and turn-end reasons, not named operational states. A detection environment variable is likewise **not a convention**: only Herdr and cmux publish one.

## 7. Orchestration policy

### 7.1 The gate

> **Parallel work requires worktrees. No exception.** Two concurrent stories never share a checkout. Serial work stays in the main checkout — the worktree is the price of parallelism, not a ritual.

Before parallelising, the Orchestrator checks **story-level dependencies**, not only task-level ones. Technical Planning's waves order tasks *within* a story; two stories under the same feature can also depend on each other. Only mutually independent stories go to simultaneous panes.

### 7.2 Creation

```bash
git -C "$REPO" worktree add "$WT_ROOT/{STORY-KEY}/{repo}" -b feature/{story-key}-{slug} "$BASE"
```

A story can span multiple repos — one worktree per repo, same branch name.

**`$BASE` is per-repo and must be resolved, never assumed.** Repos with a git-flow layout branch from `develop` (`rallye-api`, `rallye-app`); repos releasing straight from trunk branch from `main` (`allye-plugin`, which runs semantic-release on push to `main`). Resolve it once per repo — `git symbolic-ref refs/remotes/origin/HEAD` gives the default branch, and the presence of a `develop` branch overrides it — and record the answer in the dispatch briefing so the executor never has to guess. The same value is the merge target in §7.6 step 4.

Two things a fresh worktree does not inherit, both of which break execution silently:

- **Gitignored files** (`.env`, `.env.local`, local config). Claude Code solves this with `.worktreeinclude`, but only for worktrees it creates itself. These are created by hand, so the Orchestrator copies them explicitly from a declared list.
- **Dependencies.** A fresh checkout has no `node_modules`. `bun install` / `go mod download` runs as part of creation, not as a surprise for the executor.

### 7.3 Sequential shared resources

> **A shared sequential resource is allocated by the Orchestrator, in the dispatch briefing.** Migration numbers, ports, any self-incrementing id. Never "check what's free" — that is a race written out in full.

This is not hypothetical: during Épico 10, two panes each picked migration `000067` despite both being told to check for conflicts. They both checked before either wrote.

Worktrees isolate **files**, not the machine. Dev-server ports, databases, and orphaned processes remain shared, so port allocation uses the same upfront mechanism.

### 7.4 HITL / AFK

Every story carries the label before dispatch:

- **AFK** — may go to an unattended pane. The common case.
- **HITL** — requires the human present. Never dispatched in parallel; runs serially or waits.

The label is **derived, not guessed** — see §8.4.

### 7.5 Concurrency

**Default 3; ask above that.** Anthropic's own agent-teams documentation recommends 3–5 and states that *"three focused teammates often outperform five scattered ones."* Research converges that the real bottleneck is human review bandwidth, not machine capacity. Épico 10 ran 5 successfully, so 3 is a conservative default rather than a ceiling.

### 7.6 Merge and teardown

Sequential, one story at a time, every step a gate:

```
1. Both review axes clear (see §10.1) → Orchestrator moves tasks review → done, then the story → done
2. GATE:  git -C <worktree> status --porcelain   MUST be empty
          dirty → STOP. Do not merge, do not remove. Escalate to the human.
3. git push -u origin feature/{story-key}-{slug}      ← backup that outlives everything
4. In the MAIN checkout, on $BASE:  git merge --no-ff feature/{story-key}-{slug}
5. Conflicts in shared wiring files are expected.
   Resolve by CONSOLIDATING into one instance — never by picking a side.
6. Rebuild + typecheck + tests BEFORE committing the merge
7. git worktree remove <path>          ← without --force
8. herdr pane close <pane_id>          ← only after step 7
```

Three locks make "no data loss" structural rather than aspirational:

| Lock | What it prevents |
|---|---|
| **Push before removal** (step 3) | The branch exists on origin before any destruction. Even an accidental `rm -rf` afterwards loses nothing. |
| **`worktree remove` without `--force`** (step 7) | Git *refuses* a dirty worktree. That refusal is the last safety net, which is exactly why it must not be bypassed by reflex. If git refuses, that is information, not an obstacle. |
| **Pane closes last** (step 8) | While the pane lives, the session history is inspectable. Closing before a validated merge destroys the only remaining record of *why* a change was made. |

**Abandoned or failed stories get no automatic cleanup.** Worktree stays, branch stays, pane stays. Visible litter is far cheaper than deleted work.

## 8. The verification loop

### 8.1 What counts as a loop

<!-- adapted from mattpocock/skills diagnosing-bugs (MIT) — the tight-loop completion criterion -->

| Criterion | Meaning |
|---|---|
| **red-capable** | Not "runs without erroring" — it must *catch this specific failure*. If it cannot go red, it is not verification. |
| **deterministic** | Same verdict every run. |
| **fast** | Seconds. A four-minute loop is a build, not a loop. |
| **agent-runnable** | The agent runs it alone, with no human clicking. |

### 8.2 Two granularities

- **Task loop** (inside `execution` and `agents/executor.md`): run the task's verification command → red → fix → run again. Cheap and local. Stops a trivial failure from consuming a full correction round.
- **Story loop** (before emitting `execution-report`): run the command exercising the story's whole Given/When/Then. Closes the green-tasks-broken-feature hole.

### 8.3 The bound

> **Three attempts on the same failure, then stop.** "Same failure" is the real gate: if the error output is byte-identical to the previous attempt, that is not progress — it is the previous attempt repeated. Two identical outputs in a row end the loop immediately, before three.
>
> On stopping: report `❌ blocked` with the command, its literal output, and what is missing — the halt-and-report contract `agents/executor.md` already defines.

This keeps the verification loop strictly *below* the Orchestrator's correction loop rather than competing with it. The verification loop catches the trivial; the correction loop remains for what needs judgement.

### 8.4 The escape hatch, and what it derives

Not every task admits a command that is red-capable, fast, and agent-runnable — UI, infrastructure, one-off migrations. Forcing one would make Technical Planning miserable.

Such a task declares **`verification: manual`** with a written procedure. That declaration then does double duty:

> **The verification command determines AFK vs HITL.** A story where every task has an automatable verification is **AFK** and may go to an unattended pane. Any task with `verification: manual` makes its story **HITL**, and the Orchestrator will not dispatch it in parallel.

The §7.4 label stops being the Orchestrator's guess and becomes derived from planning. One mechanism feeds both.

### 8.5 Relationship to TDD

Stated explicitly so the two do not become the same rule written twice:

- **TDD** acts *during* implementation, per behaviour: Red → Green → Refactor.
- **The verification loop** acts *after*, per acceptance criterion, and iterates.

Where TDD applies, the loop confirms the whole. Where it does not — the "test after, but always test" branch of the existing detection heuristic — the loop is the *only* mechanism, and that is where it earns the most.

### 8.6 The planning gate

`technical-planning` gains: **a task with neither a verification command nor a justified `verification: manual` is not a task.** This mirrors the existing gate there ("a task without acceptance criteria is a wish"), extended from prose to something executable.

## 9. Phase-to-agent routing

### 9.1 The shape

A map resolved once, not asked per dispatch. Dispatching five parallel stories must not mean ten questions whose answers never vary.

```
phase → (agent kind, native argument string)
```

The argument string is raw and passed verbatim after `--`, because model selection is not uniform across agents: `--model sonnet --permission-mode auto` is Claude syntax; OpenCode, Codex, and pi each differ. Storing a normalised "model" field would not survive contact with a second agent.

### 9.2 Where it lives

An Allye **Core Document** (`user_config`). Core Documents are loaded automatically by `initialize` at the start of every session, so the map arrives in context without anyone fetching it. Because `ALLYE_TENANT_SLUG` is derived from the working-directory name, each project directory already has its own OAuth session, which scopes the document per project at no extra cost.

Created by the `setup` skill, asked once at install time. Per-dispatch override remains available conversationally ("run this story on codex").

### 9.3 Preflight

Before dispatching to a non-Claude agent, the Orchestrator verifies that agent has Allye configured — the MCP connection and, for OpenCode, the `allye-opencode` package. Without it the dispatched session cannot read the story, move status, or save memories, which breaks the §6.6 obligation and therefore `collect`.

The pieces already exist (`packages/allye-opencode`, `manifests/`, `docs/install-opencode.md`); nothing checks them today.

### 9.4 Platform capability limits

The map must respect what each platform can actually do. OpenCode ships six agent personas; Cursor, Codex, and Gemini CLI have a single agent and no picker. Routing "Allye Review" to a platform without that concept fails silently.

This works at all because handover portability was a deliberate property from the start (`2026-07-12` spec §5.3): the marker format is identical everywhere, *"so a handover generated on one tool works pasted into another."* This design exercises a capability that was built and never used.

## 10. Skill doctrine adoption

### 10.1 The four techniques

| Technique | Where it lands |
|---|---|
| Tight-loop completion criteria | `skills/verification-loop/` — §8.1 |
| Two-axis review (Standards ⊥ Spec) | `agents/reviewer-standards.md` + `agents/reviewer-spec.md`, dispatched as parallel panes, **never merged or reranked** |
| HITL/AFK as a derived attribute | §8.4 → §7.4 |
| Durability doctrine | `handover-protocol` — a cross-agent handover cannot depend on `src/foo.ts:42` |

On the two axes, quoting the source rationale: *"Code that follows every standard but implements the wrong thing → Standards pass, Spec fail."* Today `agents/reviewer.md` collapses ten checks into one list, where exactly that case disappears. The prohibition on merging is the point of the split, not an implementation detail.

**What "never merged" does and does not mean.** The *findings* are never merged, reranked, or reconciled: each axis reports separately, and the Orchestrator records both verbatim. The *decision* is still a single one, and it combines the axes by this rule:

| Standards | Spec | Outcome |
|---|---|---|
| ✅ | ✅ | Cascade status (existing §7 behaviour) |
| ⚠️ only | ✅ | Cascade, record the warnings as a note |
| ✅ | ⚠️ only | Cascade, record the warnings as a note |
| ❌ | any | Correction round |
| any | ❌ | Correction round |

A ❌ on either axis triggers a correction round on its own — one axis passing never offsets the other failing, since that offsetting is precisely the masking the split exists to prevent. The correction handover carries the failing axis's findings only, quoted literally, and the existing two-correction-maximum rule counts rounds per task regardless of which axis produced them.

### 10.2 Doctrine across the corpus

All 14 skills get the doctrine, split across two workstreams to avoid concurrent edits to the same files:

- **Already done** (branch `refactor/pocock-skill-doctrine`, 7 commits, −242 lines): `memory-protocol`, `tdd-workflow`, `board-progression`, `tools-quickref`, `product-planning`, `sandbox`, `delivery`.
- **Done as part of implementing this spec**, since these files are being rewritten anyway: `using-allye`, `handover-protocol`, `orchestrator`, `technical-planning`, `execution`, `review`, `setup`.

The techniques applied: the no-op test sentence by sentence, collapsing duplication, leading words, checkable completion criteria, and positive framing of prohibitions **where a positive rewrite does not weaken the gate**.

Two conflicts between the doctrine and Allye's substance were found and resolved conservatively during the first workstream, and the same resolutions apply to the second:

1. **Negation vs. HARD-GATE.** The doctrine says to phrase prohibitions positively. Several Allye gates are written as "Do NOT X" precisely because they read as an alarm an agent is more likely to obey mid-task. Gates with a clean positive equivalent were rephrased; `tdd-workflow`'s Green-phase rules and `board-progression`'s done-status gate were left alone, because there the prohibition *is* the actionable content.
2. **Sprawl vs. reference density.** `tools-quickref` is dense by design — an agent debugging a bad tool call needs the whole table in one scroll, not a pointer chase. Treated as the "legitimately flat peer-set" case the doctrine explicitly carves out; only genuine duplication was cut, never structure.

**The invariant governing all of it:** tool names, action names, and parameter names are an API contract verified against the `allye-mcp` source. They are never "improved."

## 11. File-level change map

| Change | Detail |
|---|---|
| **New** | `skills/agent-runtime/SKILL.md` + `references/herdr.md` — the five primitives and the Herdr implementation |
| **New** | `skills/verification-loop/SKILL.md` — criteria, bound, escape hatch |
| **New** | `agents/reviewer-standards.md`, `agents/reviewer-spec.md` |
| **Delete** | `agents/reviewer.md` — superseded by the two-axis split |
| **Edit** | `hooks/session-start.sh` — runtime probe, one-line context injection |
| **Edit** | `skills/orchestrator/SKILL.md` — dispatch-mode resolution (runtime first), worktree lifecycle, concurrency default, merge/teardown gates, sequential-resource allocation |
| **Edit** | `skills/execution/SKILL.md` — run the task loop and the story loop before reporting |
| **Edit** | `skills/technical-planning/SKILL.md` — verification-command gate; `verification: manual` escape hatch |
| **Edit** | `skills/review/SKILL.md` — split into the two axes |
| **Edit** | `skills/setup/SKILL.md` — create the phase→agent Core Document |
| **Edit** | `skills/using-allye/SKILL.md` — routing rows for the two new skills |
| **Edit** | `skills/handover-protocol/SKILL.md` — durability doctrine; HITL/AFK field on `story-execution` |
| **Edit** | `agents/executor.md` — run the verification loop; report its output on halt |
| **Edit** | `CLAUDE.md` — architecture section; also fix the `delivery` scope description (see §12) |
| **Merge** | `refactor/pocock-skill-doctrine` into the implementation branch |

## 12. Defects found during design

Both were surfaced while designing and are fixed as part of implementation, not deferred.

1. **`memory_save` is called with parameters it does not accept.** `skills/technical-planning`, `execution`, `review`, `delivery`, and `product-planning` all document `memory_save(..., work_item_id: ..., sprint_id: ...)`. `IntelligenceRequest` in `allye-mcp/allye_mcp/application/tools/intelligence.py:142` defines only `title`, `content`, `tags`, `sector`, and `scope`. **No memory has ever been linked to a work item**, and nothing failed loudly enough to notice. Either the parameters must be added to the MCP tool or removed from the skills — decide against the live source, do not guess.

2. **`CLAUDE.md` overstates the `delivery` skill's scope.** It describes `skills/delivery/` as epic close-out. The skill closes a *story*, and conditionally its parent feature; it never mentions epics. Epic close-out is the Orchestrator's, per its §8.

## 13. Open items requiring empirical verification

1. **Can a pane's `--cwd` be the worktree, or must it be the plugin-enabled root?** The recorded constraint is that a cwd inside a worktree makes `Skill("allye:execution")` fail with "Unknown skill". Claude Code 2.1.220 is above both v2.1.200 (project-scope plugins shared across worktrees) and v2.1.211 (shared permission approvals), which may have made this stale — but the documentation likely refers to Claude-managed worktrees under `.claude/worktrees/`, not to hand-made ones. **Until tested, the spec keeps the conservative rule:** cwd at the plugin-enabled root, absolute worktree paths in the briefing. Cost of being wrong in this direction is verbosity; the other direction kills the session.

2. **Does the `SessionStart` `additionalContext` injection survive for all install scopes?** A reported Claude Code issue describes plugin `SessionStart` `additionalContext` not surfacing. Allye's hook demonstrably works today, so this is a regression watch rather than a blocker.

## 14. Adaptation sources

Extends the table in `2026-07-12-guided-delivery-workflow-design.md` §7. Same policy: adapt with credit, never a runtime dependency.

| Source | License | What we adapt | Into |
|---|---|---|---|
| mattpocock/skills | MIT | `writing-great-skills` doctrine (no-op test, leading words, two-load model, completion criteria, failure modes); `diagnosing-bugs` tight-loop criteria; `code-review` two-axis separation; `wayfinder` HITL/AFK attribute; agent-brief durability doctrine | all skills; `verification-loop`; the two reviewer agents; `handover-protocol` |
| ogulcancelik/herdr | Apache-2.0 | The runtime contract's shape — pane/agent primitives, lifecycle vocabulary, safety rules | `agent-runtime` |

Each adapted section carries an inline credit comment, per existing repo convention:

```
<!-- adapted from mattpocock/skills writing-great-skills (MIT) -->
```

## 15. Environment recorded at design time

Facts this design was verified against, so a future reader knows what was true:

- Herdr 0.7.5, wire protocol 17, server running on a Unix socket
- Claude Code 2.1.220
- allye-plugin v1.2.6 (one unreleased commit on `main`)
- `allye-mcp` source read directly from `/home/bfernandes/dev/allye/allye-mcp`

## 16. Amendment — Allye self-sufficiency and implementation planning

**Added 2026-07-26, after Plan 01 landed and while Plan 02 was executing.** Recorded as an amendment rather than folded into the sections above, so the reasoning that produced it stays legible.

### 16.1 The policy

**Allye is self-sufficient. No external plugin is ever required, for the user or for the plugin's own development.**

At runtime this has always been true — the `2026-07-12` spec §7 established adaptation-with-credit and forbade runtime dependencies, and the adapted text is inline. What was *not* true is that the plugin offered no equivalent of the process skills its own development leaned on. Building this spec required `brainstorming` and `writing-plans` from an external suite, because Allye has no counterpart. That gap is what this amendment closes.

**Attribution comments stay.** MIT and Apache-2.0 both require retaining attribution in derivative work. Removing `<!-- adapted from superpowers:brainstorming (MIT) -->` while keeping the adapted text is a licence violation, not independence. Self-sufficiency means never *needing* the other suite installed; it does not mean erasing that ideas came from it. The two are unrelated, and only one of them is achievable by deleting a comment.

### 16.2 The gap that matters: planning happens, then implementation starts

Technical Planning decides **what** to build and records it as tasks. Nothing decides **how**, by the party that will build it, before code exists.

`skills/execution/SKILL.md` goes from Step 4 (read the existing code) straight to Step 5 (TDD, write). `agents/executor.md` does the same. An Executor that misreads a task discovers it mid-implementation, with code already written.

The Orchestrator's pre-flight completeness check (§4 of `orchestrator`) exists to catch underspecified tasks before dispatch, and its own text concedes it catches "the obvious cases, not all." **An implementation plan produced before writing moves that discovery earlier** — to the point where the cost of being wrong is a paragraph rather than a branch.

### 16.3 Step 4.5 — Plan the implementation

A new step in both `skills/execution/SKILL.md` and `agents/executor.md`, between reading and writing. Per task: the approach, the files to touch, the interfaces the task produces, and how its `## Verification` command will be satisfied.

Saved as a memory in the **`plans`** sector, which exists for exactly this and makes the plan outlive the session — a resumed Executor and the spec-axis Reviewer can both read what was intended, not only what was done.

### 16.4 Validation

Three checks are mechanical and run **always**, in both interactive and dispatched mode:

1. Every acceptance criterion has a step that covers it.
2. Every locked decision is respected by the plan.
3. No step depends on something the plan never defines.

**A failure here is `❌ blocked` before any code is written**, carrying which criterion or decision has no plan behind it. This is the same halt-and-report contract the Executor already has, fired earlier and therefore cheaper.

The fourth question — *is the approach right* — needs judgement, and its answer is bound to the dispatch label already derived in §8.4:

- **AFK story** → self-validation only. The three mechanical checks, then implement. Preserving unattended dispatch is the entire reason §7 exists; a mandatory human gate per story would make three parallel stories mean six interruptions.
- **HITL story** → the plan goes to the human before implementation begins.
- **Either label**, when the plan surfaces a decision the planning phase never covered → stop and surface it, regardless of label. A decision discovered while planning is exactly the case the label could not have anticipated.

### 16.5 Closing the remaining gaps in the existing structure

Four things the external plan format provided that Allye's task structure does not. Each is filled **inside the structure that already exists**, never as a parallel artifact — a second home for the same truth is the duplication failure mode the doctrine names, and a plan document that drifts from its work items is worse than no plan document.

| Gap | Where it lands |
|---|---|
| `Interfaces` — what a task consumes from and produces for its neighbours | a section in the task description template, `technical-planning` §4.3 |
| Global constraints stated once | a feature-level doc in Allye, referenced by every `story-execution` handover instead of recopied into each |
| No-placeholders discipline | a gate in `technical-planning`, sibling to the acceptance-criteria gate |
| Step-level detail | stays in the task's `## What`, proven by the `## Verification` command from §8 |

### 16.6 Deferred

**Renaming `docs/superpowers/` is deferred to Plan 05.** The directory is the plugin's own development artifacts, not anything the plugin instructs users' agents to do — the two are separate and only the second matters for self-sufficiency. Renaming now would collide with Plan 02, which is currently executing and writing checkbox progress into files under that path.

### 16.7 Scope

All of §16 is **Plan 05**, written after Plans 03 and 04 land. Sequencing it last is deliberate: §16.4's validation is bound to the AFK/HITL label, which Plan 02 produces and Plan 04 consumes, so building it before either would be building against a contract that does not exist yet.

---
