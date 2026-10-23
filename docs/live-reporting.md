# Live session reporting (Claude Code)

Part of the [Allye plugin](../README.md).

When this install is paired (see "Pinned preferences" in the [README](../README.md)), the plugin also tells Allye what your Claude Code sessions are doing, so a run shows up live next to its spec: the session state, which tool is in use, which subagents run and how they ended. It is metadata only, sent by asynchronous hooks that never block or print anything, and it does nothing when the install is not paired. It needs `curl`, `jq` and a SHA-256 tool (`sha256sum` or `shasum`).

```
/allye:hooks live status   # on or off, local sessions, spooled events, last result; no network call
/allye:hooks live off      # ends the open runs on Allye, deletes the local spools, sends nothing more
/allye:hooks live on       # resumes with the next hook event of each session
```

## Events

`hooks/hooks.json` registers `hooks/live-report.sh` for 12 events. Every line it sends also carries `seq` (an increasing number) and `at` (UTC time); every request carries the client kind (`claude-code`) and the session as a SHA-256 hash, never the session id.

| Hook event | Sends |
|---|---|
| `SessionStart` | `state` `started` (source `startup`, `resume`, `clear`, `compact` or `fork`); `bind` from `ALLYE_SPEC` / `ALLYE_TASK` or from the branch name |
| `UserPromptSubmit` | `state` `working` |
| `UserPromptExpansion` | nothing but a `bind` when the command is `/bridge <mode> [KEY]` |
| `PreToolUse` | `tool` (tool name), or `sub_tool` (tool name plus `sub` id and type) inside a subagent; `state` `waiting_input` with code `asked_question` for AskUserQuestion; `bind` from the Bridge skill or an Allye MCP call |
| `PostToolUse` | no tool line; `state` `working` after a wait; `gates` after the Bridge journal was written |
| `PermissionRequest` | `state` `waiting_input`, code `permission_prompt` |
| `Notification` | `waiting_input` / `permission_prompt` for a permission prompt, `state` `idle` for an idle prompt; any other type is dropped |
| `SubagentStart` | `sub_start` with `sub` id and type |
| `SubagentStop` | `sub_stop` with `sub` id, type, `outcome` (`pass`, `fail`, `blocked`, `unknown`), the task key when present and code `advisory` or `returned` |
| `Stop` | `state` `idle`, code `turn_ended` |
| `StopFailure` | `state` `error`, code `cli_error_<rate_limit, authentication_failed, billing_error, invalid_request, server_error, max_output_tokens>` or `cli_error_unknown` |
| `SessionEnd` | `state` `ended`, code `end_<clear, resume, logout, prompt_input_exit>` or `end_other` |

A value that does not match its allowed pattern or list is dropped, never shortened or sent.

## What never leaves your machine

Prompts, commands, tool inputs and outputs, file paths, notification messages, assistant messages, transcripts, the working directory, branch names, the repository path and any credential. The hooks read those only to derive the fields above and never copy them.

## What does leave it

Be aware of these labels: the type and id of a subagent (for example `allye:bridge-pilot`), the name of each tool in use (`Bash`, `Edit`, ...; an Allye MCP call is reduced to `allye:<action>`, any other MCP tool to `mcp`), and spec and task keys such as `ALY-203` or `ALY-203.5` taken from `/bridge`, Allye MCP calls, `ALLYE_SPEC` / `ALLYE_TASK` or a branch name that starts with a key (only the key leaves, not the branch). Allye keeps ended runs for 7 days.

## Binding a session to a spec

The session is linked to a spec or task by the strongest of four sources: the Bridge skill (`/bridge <mode> [KEY]` or the Skill tool) over an Allye MCP call whose arguments name a spec or task, over `ALLYE_SPEC` / `ALLYE_TASK` at session start, over a branch name at session start such as `bridge/aly-203-...`. A new bind is sent only when it is stronger than the last one, or equal with different content. Calls made inside a subagent never bind.

## Self-reported, informational

The `outcome` of a subagent comes from the `status:` line at the start of its final message (`passed`, `approved` and `ready` count as pass) and the gates come from the `- Gates:` line of the Bridge journal `.allye/missions/<slug>/log.md` (`SHIELD_CLEAR`, `WATCHER_APPROVED`, `MISSION_COMPLETE`, `CI_PENDING`). Both are what the agent wrote, not something Allye verified; treat them as information, not proof.

## Local files

Everything lives in `${CLAUDE_PLUGIN_DATA}/live` (directory 0700, files 0600), keyed by the session hash: `<hash>.spool` (events waiting to be sent), `.seq`, `.state`, `.bind`, `.gates`, `.cred` (a fingerprint of the credential last used), `.flushed` (time of the last send) and `.lock`, with short-lived `.flush.lock`, `.batch`, `.hdr` and `.resp` files while a send runs; plus `off` (set by `live off`), `disabled` (set after a rejected credential) and `backoff`. The spool keeps at most 500 lines and 256 KB (the oldest go first), and lines older than 23 hours are dropped instead of sent.

## Sending

Events are sent in batches of at most 50 events and 16 KB by a detached background process, at once for a state change, a subagent start or stop, a bind or gates, and otherwise at most every 5 seconds. At `SessionEnd` the final event goes out in one request limited to 1 second. The credential is passed to `curl` only through a configuration on its standard input, never as an argument, and never printed. Allye's answers are handled so a problem never loops:

| Answer | What the reporter does |
|---|---|
| 2xx | batch sent, removed from the spool |
| 400, 413 | batch discarded, the next one is tried |
| 401 (credential invalid or account inactive) | reporting disabled and the spool discarded until you pair again; any other 401 backs off 10 minutes |
| 403 | backs off 1 hour |
| 422 | backs off 10 minutes |
| 429 | backs off for `Retry-After`, clamped to 1 s to 1 h (60 s when absent) |
| 5xx, network error | spool kept, tried again at a later hook |

## Turning it off

`/allye:hooks live off` sets the `off` flag first, then sends a final `state` `ended` with code `end_live_off` for each session known locally, deletes the spools and sends nothing afterwards. It reports how many sessions it ended and how many it could not (a busy session or a failed request); Allye ends those by itself after a period of silence. `live on` removes the flag, and reporting resumes with the next hook event. `live status` makes no network call. Unpairing, or uninstalling the plugin, also stops it.
