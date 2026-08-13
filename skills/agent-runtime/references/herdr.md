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

## workspace and tab ownership

The Pi adapter can create a workspace or a tab without focusing it:

```text
allye_herdr(operation="workspace", cwd="/absolute/repo", label="feature-runtime")
allye_herdr(operation="tab", workspaceId="w...", cwd="/absolute/repo", label="story-1")
```

The returned IDs are registered as owned resources. Never infer IDs from layout
order and never use these operations to adopt an existing user resource.

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

## execution status, intervention, and teardown

Each dispatch returns an `executionId`. Retain it for the whole lifecycle:

```text
allye_herdr(operation="status", executionId="...")
allye_herdr(operation="wait", name="story-agent", timeoutMs=3600000)
allye_herdr(operation="mark_intervened", executionId="...")
allye_herdr(operation="cleanup", executionId="...")
```

Use `mark_intervened` when the user takes over or modifies the managed pane. A
manual intervention, `blocked`, `unknown`, timeout, or missing collection must
keep the resource open. Cleanup is valid only after wait settlement, Allye/result
collection, and verification.

The adapter rejects cleanup for resources it did not create and for executions
that are still working, blocked, unknown, or manually intervened.

```bash
herdr pane close {pane_id}
```

Only panes/tabs/workspaces the plugin created, and only after §7.1's merge gates
have passed.

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
