# Live session reporting (Claude Code)

Part of the [Allye plugin](../README.md).

When this install is paired (see "Pinned preferences" in the [README](../README.md)), the plugin also tells Allye what your Claude Code sessions are doing, so a run shows up live next to its spec: the session state, which tool is in use, which subagents run and how they ended. It sends labels and keys, plus three short agent-written texts, each at most 140 characters and cleaned on your machine (the dispatch description of a subagent, an activity phrase and the `summary:` line of a crew report; see "Agent texts"), never your prompts, commands or files. It is sent by asynchronous hooks that never block or print anything, and it does nothing when the install is not paired. It needs `curl`, `jq` and a SHA-256 tool (`sha256sum` or `shasum`).

```
/allye:hooks live status   # on or off, local sessions, spooled events, last result; no network call
/allye:hooks live off      # ends the open runs on Allye, deletes the local spools, sends nothing more
/allye:hooks live on       # resumes with the next hook event of each session
/allye:hooks live activity off   # stops all three texts (on | status too); no network call
```

## Events

`hooks/hooks.json` registers `hooks/live-report.sh` for 12 events. Every line it sends also carries `seq` (an increasing number) and `at` (UTC time); every request carries the client kind (`claude-code`) and the session as a SHA-256 hash, never the session id.

| Hook event | Sends |
|---|---|
| `SessionStart` | `state` `started` (source `startup`, `resume`, `clear`, `compact` or `fork`); `bind` from `ALLYE_SPEC` / `ALLYE_TASK` or from the branch name |
| `UserPromptSubmit` | `state` `working` |
| `UserPromptExpansion` | nothing but a `bind` when the command is `/bridge <mode> [KEY]` |
| `PreToolUse` | `tool` (tool name), or `sub_tool` (tool name plus `sub` id and type) inside a subagent, each with an `activity` phrase (at most 140 characters) when the call has a usable one (the `description` of a Bash or Agent call, the `activeForm` of the todo in progress); `state` `waiting_input` with code `asked_question` for AskUserQuestion; `bind` from the Bridge skill or an Allye MCP call |
| `PostToolUse` | no tool line; `state` `working` after a wait; `gates` after the Bridge journal was written |
| `PermissionRequest` | `state` `waiting_input`, code `permission_prompt` |
| `Notification` | `waiting_input` / `permission_prompt` for a permission prompt, `state` `idle` for an idle prompt; any other type is dropped |
| `SubagentStart` | `sub_start` with `sub` id and type, plus `sub.desc` (the cleaned dispatch description) and `sub.task` (the task key found in it) when exactly one stashed Agent/Task call of that type matches (see "Agent texts"); there is no separate `sub_tool` event for the Agent call |
| `SubagentStop` | `sub_stop` with `sub` id, type, `outcome` (`pass`, `fail`, `blocked`, `unknown`), the task key when present, code `advisory` or `returned`, and what the report lines carry (see "Crew report lines"): `summary`, `attempt`, `next`, `gate`, `checks` and `findings` |
| `Stop` | `state` `idle`, code `turn_ended` |
| `StopFailure` | `state` `error`, code `cli_error_<rate_limit, authentication_failed, billing_error, invalid_request, server_error, max_output_tokens>` or `cli_error_unknown` |
| `SessionEnd` | `state` `ended`, code `end_<clear, resume, logout, prompt_input_exit>` or `end_other` |
| none (the watcher) | `state` `ended`, code `end_process_gone`, when Claude Code is gone without a `SessionEnd` (see "Closed sessions") |

A subagent whose first line seen is a `sub_tool` or `sub_stop` (its `SubagentStart` was missed) gets a `sub_start` added before it, so Allye always sees the start first; this is tracked per session in `subs`. A value that does not match its allowed pattern or list is dropped, never shortened or sent (the three texts are cleaned and shortened as described in "Agent texts").

## What never leaves your machine

Prompts, commands, tool inputs and outputs (apart from the agent-written texts below), file paths, notification messages, transcripts, the working directory, branch names, the repository path and any credential. Assistant messages never leave either, with one exact exception: from the final message of a subagent, the cleaned text of its `summary:` line (at most 140 code points) leaves, plus the integers, enums and keys of the report grammar (`task`, `attempt`, `next`, `gate`, `checks`, `severity_counts`; see "Crew report lines"), and nothing else. Every other line of the message is read only to find those lines and is never copied. The hooks read the rest only to derive the fields above.

## What does leave it

Be aware of these labels: the type and id of a subagent (for example `allye:bridge-pilot`), the name of each tool in use (`Bash`, `Edit`, ...; an Allye MCP call is reduced to `allye:<action>`, any other MCP tool to `mcp`), and spec and task keys such as `ALY-203` or `ALY-203.5` taken from `/bridge`, Allye MCP calls, `ALLYE_SPEC` / `ALLYE_TASK` or a branch name that starts with a key (only the key leaves, not the branch). Three agent-written texts, each one line of at most 140 characters: the dispatch description of a subagent (`desc`), an activity phrase (`activity`) and the `summary:` line of a crew report (`summary`). They are stripped of paths, URLs, emails, IP addresses, secrets and backticked code on your machine, on a best-effort basis with no guarantee, so agents must not put secrets in them; Allye cleans them again on its side. Allye's retention of runs and their events is the API's (30 days at the time of writing); see the Allye documentation.

## Binding a session to a spec

The session is linked to a spec or task by the strongest of four sources: the Bridge skill (`/bridge <mode> [KEY]` or the Skill tool) over an Allye MCP call whose arguments name a spec or task (only the `task_start` and `task_submit` actions bind; reads such as `spec_get`, `spec_context` or `task_list`, approvals and other transitions never do), over `ALLYE_SPEC` / `ALLYE_TASK` at session start, over a branch name at session start such as `bridge/aly-203-...`. A new bind is sent only when it is stronger than the last one, or equal with different content. Calls made inside a subagent never bind.

## Self-reported, informational

The `outcome` of a subagent comes from the `status:` line at the start of its final message (`passed`, `approved` and `ready` count as pass) and the gates come from the `- Gates:` line of the Bridge journal `.allye/missions/<slug>/log.md` (`SHIELD_CLEAR`, `WATCHER_APPROVED`, `MISSION_COMPLETE`, `CI_PENDING`). Both are what the agent wrote, not something Allye verified; treat them as information, not proof.

## Local files

Everything lives in `${CLAUDE_PLUGIN_DATA}/live` (directory 0700, files 0600), keyed by the session hash: `<hash>.spool` (events waiting to be sent), `.seq`, `.state`, `.bind`, `.gates`, `.cred` (a fingerprint of the credential last used), `.flushed` (time in milliseconds of the last send) and `.lock`; `.watch` (the Claude Code process the session belongs to, as pid and start time), `.watch.lock` (held by the running watcher) and `.watch.gone` (marker of a first missed check); `.flush.wait` (held by the one delayed flush of the session), `.final.lock` (held by the final flusher), `.subs` (subagent ids already started) and `.agents` (the stash of recent Agent/Task calls: subagent type, cleaned description and `tool_use_id`, kept at most 60 seconds), with short-lived `.flush.lock`, `.batch`, `.hdr` and `.resp` files while a send runs; plus `off` (set by `live off`), `activity-off` (set by `live activity off`), `detailed-off` (set by the reporter when Allye answers that Detailed Live is off), `disabled` (set after a rejected credential) and `backoff`. A watcher removes `.watch`, `.watch.gone`, its lock and a `.flush.wait` left by a dead process when it exits; the final flusher removes `.final.lock`. All of them are private files or directories (0600/0700) and anything else in their place is ignored. The spool keeps at most 500 lines and 256 KB (the oldest go first), and lines older than 23 hours are dropped instead of sent.

## Sending

Events are sent in batches of at most 50 events and 16 KB by a detached background process, at once for a state change, a subagent start or stop, a bind or gates, and otherwise at most every 2 seconds: a tool line that arrives sooner is sent by one delayed flush per session (a detached sleeper holding `.flush.wait`, at most 2 seconds), so tool activity reaches Allye within about 2 seconds. At `SessionEnd` the hook itself sends what is pending, the `ended` event last, within about 1.3 seconds in total (1 second per request). If that fails, the lock stays busy or the time runs out, a detached final flusher (`.final.lock`, one per session) tries again at once and after 2, 5, 15, 30 and 60 seconds, and stops when the ended event is delivered, Live is off or disabled or the credential is gone or changed. The `end_process_gone` event of the watcher is sent alone in one request of at most 1 second and never retried. The credential is passed to `curl` only through a configuration on its standard input, never as an argument, and never printed. Allye's answers are handled so a problem never loops:

| Answer | What the reporter does |
|---|---|
| 2xx | batch sent, removed from the spool; the `detailed` field of the answer is read (see "Detailed Live") |
| 400, 413 | batch discarded (not kept, not retried), the next one is tried; see "Release order" |
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

## Agent texts

Three texts may leave, all one line of at most 140 Unicode code points, on by default:

- `desc`: the `description` of the Agent/Task call that started a subagent, sent on its `sub_start`;
- `activity`: the `description` of a Bash or Agent call, or the in-progress item (`activeForm`) of a todo list, shown next to the tool;
- `summary`: the `summary:` line of the final message of a subagent (see "Crew report lines"), sent on its `sub_stop`.

One cleaner (the same program for all three, cap 140) runs on your machine before anything is spooled, stashed or sent:

- control and invisible characters are removed, whitespace is collapsed, and text between backticks is removed;
- any word that looks like a path (contains `/` or `\`, starts with `~` or a drive letter), a URL or `www.` address, an email address, an IP address, a long hex or base64 string, or a token with a well-known prefix (`sk-`, `ghp_`, `github_pat_`, `xox…-`, `AKIA`, `eyJ`, `glpat-` and similar) is dropped;
- a word that names a secret (`key`, `token`, `secret`, `pass…`, `auth…`, `credential`) used as `name=value`, `name: value`, `password is value`, `Authorization: Bearer value` or `Bearer value` is dropped together with its value; the same goes for `pwd`, `cookie`, `session` and similar names, `arn:` identifiers, dotted host names, and long digit sequences such as account numbers;
- a text left with fewer than 3 words or 8 characters is not sent; one longer than 140 code points is cut at a word and ends with `…`.

The cleaner is a documented subset of Allye's own scrubber, which stays authoritative; neither is a guarantee. Texts are what the agent wrote minus the above, not proof of what ran. The prompt, the command itself and the tool's output are never sent.

**Matching `desc` to a subagent.** When the parent calls Agent/Task, the hook stashes the cleaned description with the subagent type and the `tool_use_id`, in `.agents` (at most 16 entries, 60 seconds). `SubagentStart` carries no `tool_use_id`, so the start is matched by subagent type. Exactly one unexpired entry of that type: its description becomes `sub.desc`, the first task key it holds (`ALY-258.1` form) becomes `sub.task`, and the entry is consumed. None: no `desc`. Several (parallel launches of one type): no `desc` and no task, and the other entries of that type are marked so a later start of the type is not matched with them either. The same rule applies to a start the reporter adds itself because the real one was missed.

**Switching texts off.** `/allye:hooks live activity off` creates `activity-off`. The same effect follows when Allye's answer to a batch says Detailed Live is off (see below). While either flag exists, no `desc`, `activity` or `summary` is attached, no stash is written and an existing one is deleted, and every flush removes those three fields from events already in the spool. Tool events, subagent events and the structured fields go on. `live activity status` and `live status` print `Live texts: on`, or `Live texts: off (your opt-out)`, `Live texts: off (Detailed Live is off in Allye)` or both reasons; neither makes a network call.

**Detailed Live.** The answer to a successful batch may carry `detailed: false` when you turned "Detailed Live" off in the Allye app (Settings → Devices). The reporter then creates `detailed-off` and stops sending texts. A valid answer without the field, or with `detailed: true`, removes the flag (a missing field means on). An answer that is not a valid acknowledgement (empty, not JSON, an error page) and any failed send leave the flag as it is. `live activity on` removes only your own opt-out; if `detailed-off` exists it says texts stay off until Detailed Live is on in the app.

## Crew report lines

The Bridge crew writes these lines in the final message of each subagent (their format is defined once in `skills/bridge/references/delegation.md`, "Report lines"). `SubagentStop` reads the first 65536 characters of that message. A line counts only when it starts at column 0 with the exact lowercase key, so an indented, bulleted, bold or differently-cased line is ignored, and the key must appear on exactly one such line; none or several omit the field. An indented copy of a line next to the column-0 one does not make it repeated: the two count as one match. Nothing is guessed from prose, and `status:` and `task:` keep their older, more lenient first-match rule.

| Line | Sent as |
|---|---|
| `summary: <text>` | `summary`, cleaned, at most 140 code points; the only message text that leaves |
| `attempt: <0\|1\|2>` | `attempt` |
| `next: <value>` | `next`, lowercased with `-` turned into `_`; one of `reviewers`, `pilot_correction`, `mothership`, `watcher`, `done` |
| `gate: SHIELD_CLEAR` / `WATCHER_APPROVED` | `gate`, only from a `shield` (`SHIELD_CLEAR`) or `watcher` (`WATCHER_APPROVED`) subagent; `null` is ignored |
| `checks: ok=<n> run=<n>` | `checks {ok, run}` |
| `severity_counts: critical=<n> high=<n> medium=<n> low=<n> info=<n>` | `findings {critical, high, medium, low, info}`, all five keys once, in that order |

Each number is an integer 0 to 99 without sign, decimal point or leading zero. Any deviation (a value out of range, a missing key, trailing text) drops that line; `checks` and `findings` are all or nothing. A report without the new lines produces the same events as before. Like `outcome`, these values are what the agent wrote, not something Allye verified.

## Test-only settings

`ALLYE_LIVE_WATCH` (`0` disables the watcher), `ALLYE_LIVE_WATCH_INTERVAL` (poll seconds, 1 to 20), `ALLYE_LIVE_WATCH_CAP` (run limit in seconds) and `ALLYE_LIVE_FINAL_DELAYS` (retry delays of the final flusher) exist for the automated tests only. Do not set them in normal use; the defaults above are the supported behaviour.

## Release order

The `end_process_gone` code, the longer texts, `sub.desc`, `sub.task` and the chips of `sub_stop` need the Allye API that accepts them to be deployed (production included). An API that does not know a field answers 400, and the reporter discards a 400 batch for good: it is neither kept nor retried, so a plugin newer than the API loses those batches. The release order is therefore API, then plugin, then app. An older plugin works against the newer API (it just sends no new fields). The API rolls back only together with the plugin: rolling the API back alone leaves a newer plugin sending fields it now rejects. Update the plugin only after the API is live.

## Turning it off

`/allye:hooks live off` sets the `off` flag first, then sends a final `state` `ended` with code `end_live_off` for each session known locally, deletes the spools and sends nothing afterwards. It reports how many sessions it ended and how many it could not (a busy session or a failed request); Allye ends those by itself after a period of silence. `live on` removes the flag, and reporting resumes with the next hook event. `live status` makes no network call. Unpairing, or uninstalling the plugin, also stops it.
