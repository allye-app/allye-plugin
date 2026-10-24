# Live session reporting (Claude Code)

Part of the [Allye plugin](../README.md).

When this install is paired (see "Pinned preferences" in the [README](../README.md)), the plugin also tells Allye what your Claude Code sessions are doing, so a run shows up live next to its spec: the session state, which tool is in use, which subagents run and how they ended. It sends labels and keys, plus at most a short redacted activity phrase (see "Activity phrases"), never your prompts, commands or files. It is sent by asynchronous hooks that never block or print anything, and it does nothing when the install is not paired. It needs `curl`, `jq` and a SHA-256 tool (`sha256sum` or `shasum`).

```
/allye:hooks live status   # on or off, local sessions, spooled events, last result; no network call
/allye:hooks live off      # ends the open runs on Allye, deletes the local spools, sends nothing more
/allye:hooks live on       # resumes with the next hook event of each session
/allye:hooks live activity off   # stops only the activity phrases (on | status too)
```

## Events

`hooks/hooks.json` registers `hooks/live-report.sh` for 12 events. Every line it sends also carries `seq` (an increasing number) and `at` (UTC time); every request carries the client kind (`claude-code`) and the session as a SHA-256 hash, never the session id.

| Hook event | Sends |
|---|---|
| `SessionStart` | `state` `started` (source `startup`, `resume`, `clear`, `compact` or `fork`); `bind` from `ALLYE_SPEC` / `ALLYE_TASK` or from the branch name |
| `UserPromptSubmit` | `state` `working` |
| `UserPromptExpansion` | nothing but a `bind` when the command is `/bridge <mode> [KEY]` |
| `PreToolUse` | `tool` (tool name), or `sub_tool` (tool name plus `sub` id and type) inside a subagent, each with an `activity` phrase when the call has a usable one; `state` `waiting_input` with code `asked_question` for AskUserQuestion; `bind` from the Bridge skill or an Allye MCP call |
| `PostToolUse` | no tool line; `state` `working` after a wait; `gates` after the Bridge journal was written |
| `PermissionRequest` | `state` `waiting_input`, code `permission_prompt` |
| `Notification` | `waiting_input` / `permission_prompt` for a permission prompt, `state` `idle` for an idle prompt; any other type is dropped |
| `SubagentStart` | `sub_start` with `sub` id and type; the description of the matching Agent call, when it has a usable phrase, goes as a `sub_tool` `Agent` event with the `activity` |
| `SubagentStop` | `sub_stop` with `sub` id, type, `outcome` (`pass`, `fail`, `blocked`, `unknown`), the task key when present and code `advisory` or `returned` |
| `Stop` | `state` `idle`, code `turn_ended` |
| `StopFailure` | `state` `error`, code `cli_error_<rate_limit, authentication_failed, billing_error, invalid_request, server_error, max_output_tokens>` or `cli_error_unknown` |
| `SessionEnd` | `state` `ended`, code `end_<clear, resume, logout, prompt_input_exit>` or `end_other` |
| none (the watcher) | `state` `ended`, code `end_process_gone`, when Claude Code is gone without a `SessionEnd` (see "Closed sessions") |

A subagent whose first line seen is a `sub_tool` or `sub_stop` (its `SubagentStart` was missed) gets a `sub_start` added before it, so Allye always sees the start first; this is tracked per session in `subs`. A value that does not match its allowed pattern or list is dropped, never shortened or sent (the activity phrase is cleaned and shortened as described below).

## What never leaves your machine

Prompts, commands, tool inputs and outputs (apart from the activity phrase), file paths, notification messages, assistant messages, transcripts, the working directory, branch names, the repository path and any credential. The hooks read those only to derive the fields above and never copy them.

## What does leave it

Be aware of these labels: the type and id of a subagent (for example `allye:bridge-pilot`), the name of each tool in use (`Bash`, `Edit`, ...; an Allye MCP call is reduced to `allye:<action>`, any other MCP tool to `mcp`), and spec and task keys such as `ALY-203` or `ALY-203.5` taken from `/bridge`, Allye MCP calls, `ALLYE_SPEC` / `ALLYE_TASK` or a branch name that starts with a key (only the key leaves, not the branch). An agent-written activity phrase (at most 48 characters, see "Activity phrases"). Allye keeps ended runs for 7 days.

## Binding a session to a spec

The session is linked to a spec or task by the strongest of four sources: the Bridge skill (`/bridge <mode> [KEY]` or the Skill tool) over an Allye MCP call whose arguments name a spec or task (only the `task_start` and `task_submit` actions bind; reads such as `spec_get`, `spec_context` or `task_list`, approvals and other transitions never do), over `ALLYE_SPEC` / `ALLYE_TASK` at session start, over a branch name at session start such as `bridge/aly-203-...`. A new bind is sent only when it is stronger than the last one, or equal with different content. Calls made inside a subagent never bind.

## Self-reported, informational

The `outcome` of a subagent comes from the `status:` line at the start of its final message (`passed`, `approved` and `ready` count as pass) and the gates come from the `- Gates:` line of the Bridge journal `.allye/missions/<slug>/log.md` (`SHIELD_CLEAR`, `WATCHER_APPROVED`, `MISSION_COMPLETE`, `CI_PENDING`). Both are what the agent wrote, not something Allye verified; treat them as information, not proof.

## Local files

Everything lives in `${CLAUDE_PLUGIN_DATA}/live` (directory 0700, files 0600), keyed by the session hash: `<hash>.spool` (events waiting to be sent), `.seq`, `.state`, `.bind`, `.gates`, `.cred` (a fingerprint of the credential last used), `.flushed` (time in milliseconds of the last send) and `.lock`; `.watch` (the Claude Code process the session belongs to, as pid and start time), `.watch.lock` (held by the running watcher) and `.watch.gone` (marker of a first missed check); `.flush.wait` (held by the one delayed flush of the session), `.final.lock` (held by the final flusher), `.subs` (subagent ids already started) and `.agents` (descriptions of recent Agent calls, kept at most 60 seconds), with short-lived `.flush.lock`, `.batch`, `.hdr` and `.resp` files while a send runs; plus `off` (set by `live off`), `activity-off` (set by `live activity off`), `disabled` (set after a rejected credential) and `backoff`. A watcher removes `.watch`, `.watch.gone`, its lock and a `.flush.wait` left by a dead process when it exits; the final flusher removes `.final.lock`. All of them are private files or directories (0600/0700) and anything else in their place is ignored. The spool keeps at most 500 lines and 256 KB (the oldest go first), and lines older than 23 hours are dropped instead of sent.

## Sending

Events are sent in batches of at most 50 events and 16 KB by a detached background process, at once for a state change, a subagent start or stop, a bind or gates, and otherwise at most every 2 seconds: a tool line that arrives sooner is sent by one delayed flush per session (a detached sleeper holding `.flush.wait`, at most 2 seconds), so tool activity reaches Allye within about 2 seconds. At `SessionEnd` the hook itself sends what is pending, the `ended` event last, within about 1.3 seconds in total (1 second per request). If that fails, the lock stays busy or the time runs out, a detached final flusher (`.final.lock`, one per session) tries again at once and after 2, 5, 15, 30 and 60 seconds, and stops when the ended event is delivered, Live is off or disabled or the credential is gone or changed. The `end_process_gone` event of the watcher is sent alone in one request of at most 1 second and never retried. The credential is passed to `curl` only through a configuration on its standard input, never as an argument, and never printed. Allye's answers are handled so a problem never loops:

| Answer | What the reporter does |
|---|---|
| 2xx | batch sent, removed from the spool |
| 400, 413 | batch discarded, the next one is tried |
| 401 (credential invalid or account inactive) | reporting disabled and the spool discarded until you pair again; any other 401 backs off 10 minutes |
| 403 | backs off 1 hour |
| 422 | backs off 10 minutes |
| 429 | backs off for `Retry-After`, clamped to 1 s to 1 h (60 s when absent) |
| 5xx, network error | spool kept, tried again at a later hook |

## Closed sessions

If Claude Code is closed without a `SessionEnd` (terminal closed, `kill`, crash, power loss), a small background watcher ends the run on Allye. The first hook of a session (`SessionStart`, or `UserPromptSubmit` when none is running) records the owner process and starts at most one watcher per session; it runs detached, with no output, in a session of its own when `setsid` exists and ignoring SIGHUP otherwise, so closing the terminal does not stop it.

- **Owner.** The process the hook is running under is walked upwards. Shells (`sh`, `bash`, `dash`, `zsh`, `ksh`, `fish`) and wrappers (`env`, `timeout`, `nohup`, `stdbuf`, `setsid`, `flock`, `script`) are skipped. The first other process is the owner only if its name is exactly `claude`, `node`, `bun` or `node-MainThread`; `tmux`, `sshd` or `systemd` are never owners. The walk stops, and nothing is watched, at a process of another user, at PID 1 or after 8 levels. A later `SessionStart` (for example a resume) under another owner is followed.
- **Polling.** Every 15 seconds the watcher checks that the owner still exists (same pid and start time, not a zombie). While it exists the watcher uses no `curl` or `jq`.
- **Two misses.** The first miss only leaves the `.watch.gone` marker. On the next poll, if the owner is still gone and no hook ran in between, the watcher sends `state` `ended` with code `end_process_gone`. If a hook ran, the count starts over, so a slow restart is never taken for a death, and polling continues.
- **Exit without sending.** The watcher stops quietly when the session is already `ended`, Live is off or disabled, the credential is gone or changed, another watcher holds the lock, the live directory fails its owner and mode checks, or it has run for 24 hours. It honours a back-off: while one is active nothing is sent, and the event is not retried. Allye stores this end as an expiry, so if the session was in fact alive its next event reopens the run.
- **Platforms.** On Linux the owner is read from `/proc`; elsewhere from `ps -o ppid=,uid=,state=,comm=` (checked manually on macOS, not by the automated tests).
- **Switch off.** `ALLYE_LIVE_WATCH=0` in the environment of the session starts no watcher; `live off` stops it at its next check.

## Activity phrases

For a Bash or Agent call (its `description`) and for the in-progress item of a todo list (its `activeForm`), the hook may send one short phrase telling what the agent is doing, shown next to the tool. They are on by default; `/allye:hooks live activity off` stops them at once, and `live off` stops everything. Before anything is spooled or sent, on your machine:

- control and invisible characters are removed, whitespace is collapsed, and text between backticks is removed;
- any word that looks like a path (contains `/` or `\`, starts with `~` or a drive letter), a URL or `www.` address, an email address, an IP address, a long hex or base64 string, or a token with a well-known prefix (`sk-`, `ghp_`, `github_pat_`, `xox…-`, `AKIA`, `eyJ`, `glpat-` and similar) is dropped;
- a word that names a secret (`key`, `token`, `secret`, `pass…`, `auth…`, `credential`) used as `name=value`, `name: value`, `password is value`, `Authorization: Bearer value` or `Bearer value` is dropped together with its value;
- a phrase left with fewer than 3 words or 8 characters is not sent; one longer than 48 characters is cut at a word and ends with `…`.

Phrases are not proof of what ran; they are what the agent wrote, minus the above. The prompt, the command itself and the tool's output are never sent.

## Test-only settings

`ALLYE_LIVE_WATCH` (`0` disables the watcher), `ALLYE_LIVE_WATCH_INTERVAL` (poll seconds, 1 to 20), `ALLYE_LIVE_WATCH_CAP` (run limit in seconds) and `ALLYE_LIVE_FINAL_DELAYS` (retry delays of the final flusher) exist for the automated tests only. Do not set them in normal use; the defaults above are the supported behaviour.

## Release note

The activity phrase and the `end_process_gone` code need the Allye API of ALY-216 to be deployed (production included). An older API that strictly validates events rejects those events with a 400, so the batch is discarded; update the plugin only after the API is live.

## Turning it off

`/allye:hooks live off` sets the `off` flag first, then sends a final `state` `ended` with code `end_live_off` for each session known locally, deletes the spools and sends nothing afterwards. It reports how many sessions it ended and how many it could not (a busy session or a failed request); Allye ends those by itself after a period of silence. `live on` removes the flag, and reporting resumes with the next hook event. `live status` makes no network call. Unpairing, or uninstalling the plugin, also stops it.
