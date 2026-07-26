# Hermes as an Allye Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Allye the single source of truth on a machine running Hermes — its competing memory and orchestration engine turned off, its session scratch promoted into Allye rather than mirrored, and its scheduler pointed at the Allye Orchestrator instead of a parallel daemon.

**Architecture:** Configuration, not code. Two toolsets come off in the Hermes adapter Plan 08 built; the todo-promotion step joins the mining protocol `memory-protocol` already runs; and the cron recipe is documented rather than automated. No tool overrides, no fork.

**Tech Stack:** Markdown skills, `install/adapters.json`, `install/lib.sh` (bash + `jq`). No new dependency.

## Global Constraints

- **Conventional Commits are enforced in CI.** Valid types: `feat`, `fix`, `docs`, `refactor`, `chore`.
- **Never add a `Co-Authored-By` trailer.**
- **Tool names, action names, and parameter names are an API contract.** Never rename one.
- **Attribution comments stay.** Twenty-two exist across `skills/` and `agents/`; this plan removes none.
- **No `allow_tool_override`.** This plan disables toolsets; it never registers a tool with `override=True`. That trust gate exists to stop a plugin silently replacing something privileged, and nothing here needs to cross it. See §20.3.
- **Never overwrite a config you did not write.** Every write to `~/.hermes/config.yaml` is a merge.
- **Skill files stay in English.** Bump `version` minor on any skill changed.
- **Do not push. Do not merge to `main`.**

<HARD-GATE>
**Every verification runs against a sandboxed `HOME`.**

```bash
export ALLYE_TEST_HOME=/tmp/allye-hermes-test
rm -rf "$ALLYE_TEST_HOME" && mkdir -p "$ALLYE_TEST_HOME"
HOME="$ALLYE_TEST_HOME" ./install.sh status
```

`~/.hermes/config.yaml` belongs to a live agent the human is using right now and holds API keys. `~/.claude.json` is your own configuration. Plan 08's executor observed this gate correctly; observe it too.

**Never run an install verb without `HOME` overridden.**
</HARD-GATE>

## Prerequisites

Plans 01–08 complete and merged.

```bash
jq -e '.agents | map(select(.id=="hermes")) | length == 1' install/adapters.json
ls install/lib.sh manifests/hermes/plugin.yaml manifests/hermes/__init__.py
ls docs/install-hermes.md
grep -c 'Step 2 — Mine the consolidation' skills/memory-protocol/SKILL.md   # the pattern this plan extends
```

Read **§20 of the spec** before Task 1.

## Facts verified against the live install — do not re-derive these

- **Memory registration** requires `memory_enabled` **or** `user_profile_enabled` (`agent/agent_init.py:1618`). Both must go, not one.
- **`conversation_compression.py:160` reads `_memory_enabled`.** Context compression may behave differently once it is off. That is an observation to record, not a reason to skip.
- **Kanban is a toolset** re-added by force when `HERMES_KANBAN_TASK` is in the environment (`model_tools.py:379`), because dispatcher-spawned workers need its lifecycle tools. Disabling it for chat does not disable that path, and should not try to.
- **`platform_toolsets`** maps a platform to the toolsets it may use. Today: `cli: [hermes-cli]`, `telegram: [hermes-telegram]`, and so on. `hermes-cli` is a preset bundle whose contents include `memory` and `todo`.
- **`mcp-<server>`** is the toolset name an MCP server's tools land in (`tools/mcp_tool.py:5506`), so Allye's are `mcp-allye`.

---

### Task 1: Turn off the competing engines in the Hermes adapter

**Files:**
- Modify: `install/adapters.json`
- Modify: `install/lib.sh`

**Interfaces:**
- Consumes: Plan 08's adapter schema and `write_mcp_yaml_block`.
- Produces: a `config` block on the Hermes adapter that later agents can copy the shape of.

- [ ] **Step 1: Establish the failing assertion**

```bash
jq -r '.agents[] | select(.id=="hermes") | keys | join(" ")' install/adapters.json
grep -c 'memory_enabled' install/lib.sh
```
Expected: the Hermes entry has no `config` key, and `memory_enabled` appears zero times.

- [ ] **Step 2: Add a `config` block to the Hermes adapter**

Extend the Hermes entry with the settings the installer must merge:

```json
"config": {
  "set": {
    "memory.memory_enabled": false,
    "memory.user_profile_enabled": false
  },
  "toolsets_remove": ["memory", "kanban"],
  "toolsets_add": ["mcp-allye"]
}
```

`set` writes scalar keys. `toolsets_remove` and `toolsets_add` operate on every platform's list in `platform_toolsets`, since the choice of engine is not per-platform: a Telegram session and a CLI session must agree on where memories live.

- [ ] **Step 3: Implement the merge**

Add `apply_agent_config <agent-id>` to `install/lib.sh`, called from `allye_install` after the MCP block is written.

<HARD-GATE>
**Merge, never replace.** `platform_toolsets` holds the user's own choices, and `plugins.enabled` already contains `herdr-agent-state` on this machine. Removing a toolset means removing that one entry from each list, not rewriting the list.

If a platform's list does not exist, **leave it absent** — an absent list means the platform's default preset applies, and materialising it would silently freeze a default the user never chose.
</HARD-GATE>

Record what was changed so `uninstall` can reverse it: write the previous value beside each change under an `allye_previous` key in the config, or a sibling file. An uninstall that cannot restore what it turned off is not an uninstall.

- [ ] **Step 4: Verify against the sandbox, with a pre-existing config**

Seed a config that already has user content, so the merge is genuinely tested:

```bash
export ALLYE_TEST_HOME=/tmp/allye-hermes-test
rm -rf "$ALLYE_TEST_HOME" && mkdir -p "$ALLYE_TEST_HOME/.hermes"
cat > "$ALLYE_TEST_HOME/.hermes/config.yaml" <<'YAML'
memory:
  memory_enabled: true
  user_profile_enabled: true
  nudge_interval: 10
platform_toolsets:
  cli:
    - hermes-cli
    - memory
    - todo
  telegram:
    - hermes-telegram
    - memory
plugins:
  enabled:
    - herdr-agent-state
YAML
HOME="$ALLYE_TEST_HOME" ./install.sh install hermes </dev/null >/dev/null 2>&1
cat "$ALLYE_TEST_HOME/.hermes/config.yaml"
```

Expected, by eye and then by assertion:

```bash
grep -c 'memory_enabled: false' "$ALLYE_TEST_HOME/.hermes/config.yaml"      # 1
grep -c 'user_profile_enabled: false' "$ALLYE_TEST_HOME/.hermes/config.yaml" # 1
grep -c 'nudge_interval: 10' "$ALLYE_TEST_HOME/.hermes/config.yaml"          # 1 — untouched
grep -c 'herdr-agent-state' "$ALLYE_TEST_HOME/.hermes/config.yaml"           # 1 — survived
grep -c '^    - todo' "$ALLYE_TEST_HOME/.hermes/config.yaml"                 # 1 — kept deliberately
grep -c '^    - memory$' "$ALLYE_TEST_HOME/.hermes/config.yaml"              # 0 — removed from both platforms
grep -c 'mcp-allye' "$ALLYE_TEST_HOME/.hermes/config.yaml"                   # 2 — added to both
```

`todo` surviving is the point of this plan's §20.4 and the easiest thing to remove by accident while removing its neighbours.

- [ ] **Step 5: Commit**

```bash
git add install/adapters.json install/lib.sh
git commit -m "feat(install): turn off Hermes's competing memory and kanban

Allye drives. Hermes's kanban is an orchestration engine, not a board —
dispatch, isolated workspaces, dependencies, a swarm verifier — and two
engines means two answers to what the plan is.

Disabling the toolsets is enough; no tool override and no trust gate. The
override would only keep Hermes's memory nudge writing into Allye, and
memory-protocol already says when to save.

todo stays: it is turn-scratch, a different granularity from durable
TODOs, and it is promoted rather than mirrored."
```

---

### Task 2: Promote surviving todos into Allye

The pattern already exists. `memory-protocol` §4 consolidates a session and then mines it — *"is any of this still true and useful outside this conversation?"* Session todos answer the same question.

**Files:**
- Modify: `skills/memory-protocol/SKILL.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: a fourth step in the /save protocol.

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -c 'todo' skills/memory-protocol/SKILL.md
grep -n '^### Step 3 — React to the outcome' skills/memory-protocol/SKILL.md
grep -n '3-step protocol' skills/memory-protocol/SKILL.md
```
Expected: `todo` absent; **Step 3 is titled "React to the outcome"** — Plan 01's doctrine pass shortened it, so do not search for older wording; and §4's opening calls it a "3-step protocol", which Step 3 of this task corrects.

- [ ] **Step 2: Add Step 4 to the /save protocol**

After Step 3:

```markdown
### Step 4 — Promote surviving todos (`productivity`, personal)

Some agents keep a scratch task list for the turn — read the file, run the test, commit.
It is the right tool for that and it dies with the session, which is also right.

Ask the same question Step 2 asks of the session: **would this still matter tomorrow?**

**Promote when the item is:**
- A follow-up nobody has scheduled — "the migration needs a rollback path before it ships"
- A discovery that costs time every time it is rediscovered — "the app build fails without an
  explicit install because the runtime is at a non-default path"
- Work the session surfaced but deliberately did not do

**Do NOT promote:**
- Any step of the work just completed. "Run the tests" is not a TODO, it is a thing that happened.
- Anything already captured as a work item — `productivity` is personal follow-up, not a
  second work tracker. If it belongs to a story, it belongs in the story.

```
todo_create(
  title: "{the follow-up, stated as an outcome}",
  content: "## What\n{what needs doing}\n\n## Why it surfaced\n{the session context that produced it}",
  priority: "{low|medium|high|urgent}"
)
```

Zero promotions is the normal outcome. A session whose every scratch item was a step of the
work it just finished has nothing to promote, and forcing one turns a personal list of real
commitments into a log of completed steps — which is what makes such lists get ignored.
```

- [ ] **Step 3: Reference it from the protocol's opening**

Two places say three, and both are one edit each:

- **§4's opening line** reads *"`/save` is a 3-step protocol… Run all three steps, in order"*. Both numbers change.
- **§3's "Session state — handled by the /save protocol"** describes the same protocol; check its wording and update if it names a count.

A protocol that announces three steps and then lists four is the kind of small wrongness that makes a reader stop trusting the rest of the file.

- [ ] **Step 4: Verify**

```bash
grep -c 'Step 4 — Promote surviving todos' skills/memory-protocol/SKILL.md
grep -c 'todo_create' skills/memory-protocol/SKILL.md
grep -cE '3-step|three steps|three-step' skills/memory-protocol/SKILL.md
grep -cE '4-step|four steps' skills/memory-protocol/SKILL.md
grep -c 'sector: "sessions"' skills/memory-protocol/SKILL.md
grep -c '^### Step ' skills/memory-protocol/SKILL.md
```
Expected: the step present; `todo_create` used once; **zero** surviving three-step phrasings and at least one four-step; Step 1's `sessions` consolidation untouched; and exactly **four** `### Step` headings.

- [ ] **Step 5: Bump version and commit**

```bash
git add skills/memory-protocol/
git commit -m "feat(memory-protocol): promote surviving todos, do not mirror them

Session scratch and durable personal TODOs are different granularities.
Mirroring degrades both — the durable list fills with 'run the test', or
real commitments vanish at session end.

The relation is candidacy, and Step 2 already mines a session for what
outlives it. Todos get the same question."
```

---

### Task 3: Document what changed and how autonomy works without the daemon

**Files:**
- Modify: `docs/install-hermes.md`

- [ ] **Step 1: Establish the failing assertion**

```bash
grep -ci 'kanban\|cron' docs/install-hermes.md
```
Expected: `0`.

- [ ] **Step 2: Say plainly what the installer turns off, and why**

Add a section. A user who finds their memory tool gone deserves to know it was deliberate:

```markdown
## What the installer turns off, and why

Installing Allye disables two Hermes features, because Allye provides both and two
sources of truth is worse than either alone.

**`memory`** — Hermes stores memories in `~/.hermes/memories/` on this machine. Allye's
`intelligence` has seven sectors, conflict resolution, team scope, and semantic search, and
it is reachable from every agent on every machine. A memory only Hermes can see is worse
than none: it gives the feeling of continuity without the thing.

**`kanban`** — despite the name this is an orchestration engine: atomic task claiming,
dependencies, isolated workspaces per task, and a swarm mode. Allye's work items plus the
Orchestrator do the same job, and know Epic→Feature→Story→Task, acceptance criteria, and
your team's configured pipeline.

**`todo` stays.** It is turn-scratch and that is legitimate. Anything that outlives the
session is promoted to Allye at session end — see the `memory-protocol` skill.

To keep either, remove it from `toolsets_remove` in `install/adapters.json` before
installing, or re-add it to `platform_toolsets` afterwards.

**One thing to watch.** Hermes's memory is woven into its turn loop, and context compression
reads the same flag. If long conversations start behaving differently after installing, that
is the first place to look.
```

- [ ] **Step 3: Document autonomy via cron**

```markdown
## Working while you are away

Hermes's own scheduler still runs; it just drives Allye rather than a second board.

```bash
hermes cron create "allye-morning" \
  --schedule "0 9 * * 1-5" \
  --prompt "Load the orchestrator skill and report where each in-flight story stands. Do not dispatch anything without asking."
```

The gateway runs on your machine and answers from Telegram, Discord, Slack, or whichever
platform you connected — so a story parked at a gate reaches you wherever you are, and you
answer from there.

**Start read-only.** A schedule that reports is useful on day one and cannot surprise you.
Give it dispatch authority once you have watched what it reports for a week.
```

- [ ] **Step 4: Verify**

```bash
grep -c 'What the installer turns off' docs/install-hermes.md
grep -c 'hermes cron create' docs/install-hermes.md
grep -c 'todo. stays' docs/install-hermes.md
grep -c 'Start read-only' docs/install-hermes.md
```
Expected: all four present.

- [ ] **Step 5: Commit**

```bash
git add docs/install-hermes.md
git commit -m "docs: what installing Allye turns off in Hermes, and cron autonomy

A user whose memory tool disappears deserves to know it was deliberate,
what replaced it, and how to keep it. Documents the context-compression
behaviour worth watching after disabling memory.

Autonomy survives without the kanban daemon: hermes cron drives the Allye
Orchestrator, and the gateway answers from whichever chat platform is
connected. Recommends starting read-only."
```

---

## What this plan deliberately does not do

- **No tool override, and no `allow_tool_override`.** Disabling suffices. The gate exists to stop a plugin silently replacing something privileged, and crossing it to gain a memory nudge we do not need would be a bad trade. It remains available if the nudge later proves to matter.
- **No fork.** Rejected on the numbers in §20.5 — 1.8M lines against a plugin that survives every upstream release.
- **No fix for `hermes -z` missing MCP tools.** The one-shot path backgrounds discovery and never waits, where the chat path calls `wait_for_mcp_discovery()`. Upstream's to fix, and it does not affect the gateway, which is the path that matters here.
- **No migration of existing Hermes state.** A populated `kanban.db` stays on disk untouched. Turning the toolset off does not delete anyone's data, and deciding what to do with it is the owner's call.
- **No two-way sync of anything.** Not memory, not todos, not work items. Every sync is a place where two truths diverge quietly, which is the problem this plan exists to remove.
