# Live session reporting (Claude Code)

Part of the [Allye plugin](../README.md).

When this install is paired (see "Pinned preferences" in the [README](../README.md)), the plugin also tells Allye what your Claude Code sessions are doing, so a run shows up live next to its spec: the session state, which tool is in use, which subagents run and how they ended. It sends labels and keys, plus short agent-written texts, each at most 140 characters (60 for the session label) and cleaned on your machine (the dispatch description of a subagent, an activity phrase for each tool call, the `summary:` line of a crew report and the session label; see "Agent texts"), never your prompts, commands or files. It is sent by asynchronous hooks that never block or print anything (the one blocking hook, the answer hook of "Answering from Allye", is separate), and it does nothing when the install is not paired. It needs `curl`, `jq` and a SHA-256 tool (`sha256sum` or `shasum`).

```
/allye:hooks live status   # on or off, local sessions, spooled events, last result; no network call
/allye:hooks live off      # ends the open runs on Allye, deletes the local spools and the text-bearing state files, sends nothing more
/allye:hooks live on       # resumes with the next hook event of each session
/allye:hooks live activity off   # stops all the texts (on | status too); no network call
```

## Events

`hooks/hooks.json` registers `hooks/live-report.sh` for 13 events (all asynchronous except `SessionEnd`) and, besides it, the blocking `hooks/live-answer.sh` on `PermissionRequest` (see "Answering from Allye"). Every line it sends also carries `seq` (an increasing number) and `at` (UTC time); every request carries the client kind (`claude-code`) and the session as a SHA-256 hash, never the session id.

| Hook event | Sends |
|---|---|
| `SessionStart` | `state` `started` (source `startup`, `resume`, `clear`, `compact` or `fork`); `bind` from `ALLYE_SPEC` / `ALLYE_TASK` or from the branch name; `label` (see "Session label") |
| `UserPromptSubmit` | `state` `working` |
| `UserPromptExpansion` | nothing but a `bind` when the command is `/bridge <mode> [KEY]` |
| `PreToolUse` | `tool` (tool name), or `sub_tool` (tool name plus `sub` id and type) inside a subagent, each with an `activity` phrase (at most 140 characters) by the grammar of "Activity phrases" (one event per tool call of the main session or of a subagent, never several phrases collapsed into the latest); the first `sub_tool` of an agent id may also carry `sub.task` (see "Task key") and, after a stop, `sub.resumed` (see "Resumed agents"); `state` `waiting_input` with code `asked_question` for AskUserQuestion; `bind` from the Bridge skill, an Allye MCP call or a spec read (see "Binding a session to a spec"); `label` at most once a minute when the title changed |
| `PostToolUse` | no tool line; `cmd_end` with `ok` true (see "Answering from Allye"); `state` `working` after a wait; `gates` (the set of gate markers and, when the log has one, the integer `pr`) after the Bridge journal was written |
| `PostToolUseFailure` | `cmd_end` with `ok` false (the response is never read); nothing else |
| `PermissionRequest` | `state` `waiting_input`, code `permission_prompt` |
| `Notification` | `waiting_input` / `permission_prompt` for a permission prompt, `state` `idle` for an idle prompt; any other type is dropped |
| `SubagentStart` | `sub_start` with `sub` id and type, plus `sub.desc` (the cleaned dispatch description) and `sub.task` (the task key found in it) when exactly one stashed Agent/Task call of that type matches (see "Agent texts"); there is no separate `sub_tool` event for the Agent call |
| `SubagentStop` | `sub_stop` with `sub` id, type, `outcome` (`pass`, `fail`, `blocked`, `unknown`), the task key when present, code `advisory` or `returned`, `desc` read from the subagent metadata file when it is readable, `sub.phase` (`stage` or `publish`), the code `ready` or `approved`, `sub.resumed` for an agent that was stopped before, and what the report lines carry (see "Crew report lines"): `summary`, `attempt`, `next`, `gate`, `checks` and `findings`; the report comes from the final message, else from the subagent transcript (see "Result from the transcript") |
| `Stop` | `state` `idle`, code `turn_ended` |
| `StopFailure` | `state` `error`, code `cli_error_<rate_limit, authentication_failed, billing_error, invalid_request, server_error, max_output_tokens>` or `cli_error_unknown` |
| `SessionEnd` | `state` `ended`, code `end_<clear, resume, logout, prompt_input_exit>` or `end_other` |
| none (the watcher) | `state` `ended`, code `end_process_gone`, when Claude Code is gone without a `SessionEnd` (see "Closed sessions") |

A subagent whose first line seen is a `sub_tool` or `sub_stop` (its `SubagentStart` was missed) gets a `sub_start` added before it, so Allye always sees the start first; this is tracked per session in `subs`. A value that does not match its allowed pattern or list is dropped, never shortened or sent (the three texts are cleaned and shortened as described in "Agent texts").

## What never leaves your machine

Prompts, commands, tool inputs and outputs (apart from the agent-written texts and the fixed phrases below), file paths, notification messages, transcripts, the full working directory path, branch names, the repository path and any credential. Assistant messages and transcripts never leave either, with one exact exception: from the final message of a subagent, or from its transcript when the final message has no report, the cleaned text of its `summary:` line (at most 140 code points) leaves, plus the integers, enums and keys of the report grammar (`task`, `attempt`, `next`, `gate`, `checks`, `severity_counts`, `phase`, the codes `ready` and `approved`; see "Crew report lines"), and nothing else. Every other line is read only to find those lines and is never copied. The hooks read the rest only to derive the fields above. A transcript can never produce a gate marker: gates come only from the verified mission log.

## What does leave it

Be aware of these labels: the type and id of a subagent (for example `allye:bridge-pilot`), the name of each tool in use (`Bash`, `Edit`, ...; an Allye MCP call is reduced to `allye:<action>`, any other MCP tool to `mcp`), and spec and task keys such as `ALY-203` or `ALY-203.5` taken from `/bridge`, Allye MCP calls (`task_start`, `task_submit`, `spec_context`, `spec_get`), `ALLYE_SPEC` / `ALLYE_TASK`, a branch name that starts with a key (only the key leaves, not the branch) or a subagent's dispatch description (`sub.task`, a display hint). Also the pull request number of the mission log (`pr`, an integer from the `- PR: #N` line, only on the `gates` event), the flags `sub.resumed` and `sub.phase`, and the codes `ready` and `approved`.

Agent-written texts, each one line: the dispatch description of a subagent (`desc`, at most 140 characters), an activity phrase per tool call (`activity`, at most 140), the `summary:` line of a crew report (`summary`, at most 140) and the session label (`label.text`, at most 60, with its source `explicit` or `ai`) together with the basename of the working folder (`label.cwd`, one path component, never the path; dropped when it matches the secret-name denylist of "Session label"). They are stripped of paths, URLs, emails, IP addresses, secrets and backticked code on your machine, on a best-effort basis with no guarantee, so agents must not put secrets in them; Allye scrubs them again on its side and that scrub is the authoritative one. Activity phrases are either the agent's own call description (cleaned) or one of a fixed set of phrases with at most one file name or Allye key (see "Activity phrases"): nothing from a command's arguments or any other tool input is ever sent.

Who sees them and for how long (decided by the Allye API, not by this plugin): the texts are visible to the owner of the run only, a teammate's token receives none of them. Allye stores them for 30 days with the run: the three texts, the session labels, the per-step history of up to 50 activity phrases and the working folder name. Turning Detailed Live off in the app purges them. The plugin's own cleaner is best-effort; the Allye scrub is authoritative.

## Binding a session to a spec

The session is linked to a spec or task by the strongest of four sources: the Bridge skill (`/bridge <mode> [KEY]` or the Skill tool) over an Allye MCP call whose arguments name a spec or task (the `task_start` and `task_submit` actions), over `ALLYE_SPEC` / `ALLYE_TASK` at session start, over a branch name at session start such as `bridge/aly-203-...`. A new bind is sent only when it is stronger than the last one, or equal with different content. Calls made inside a subagent never bind.

**Bind touches.** A `spec_context` or `spec_get` call of the main session with a key matching `^[A-Z][A-Z0-9]{1,9}-\d+$`, and a `/bridge` launch with a key, are also sent as a bind when they are weaker than the held binding or identical to it, so Allye can tell which spec the session touched last (its "working on"). Such a touch is limited to one per key per minute (`<hash>.touch`, up to 16 `KEY ms` lines) and never changes the held binding stored locally. `spec_list`, validations and anything inside a subagent never touch. Reading an old spec for reference does move "working on", which is intended; the Allye API decides whether the key is readable.

## Answering from Allye (return channel)

Besides the reporter, `hooks/hooks.json` registers a blocking `PermissionRequest` hook, `hooks/live-answer.sh` (timeout 120 s). It lets the owner of the session answer a question (`AskUserQuestion`) or allow once / deny a normal-risk permission from Allye. It is the opposite of the rest of this page: it waits, and it can print a decision, but only a strictly validated one. The terminal keeps the last word: the dialog stays usable while the hook waits, and the hook exits 0 with no output on any doubt. Nothing is ever "always allow", and the tool input is never edited except by adding the answers to a question.

What it sends to open a request: the session hash, the kind (`permission` or `question`), the hash of the call, the risk class (`normal` or `high`), the tool name (another server's MCP tools as `mcp`), the activity phrase of "Activity phrases" (left out when texts are off), for a question the cleaned header, question, option label and description texts (at most 4 questions with 4 options; nothing is sent and nothing is opened when Detailed Live or activity is off) and, when readable, the `after` number (the reporter's last `seq`). Never the command, path, prompt or tool input. The hash is the SHA-256 of `jq -S -c` over `[tool_name, tool_input]` (for `AskUserQuestion`, over `tool_input.questions`). The reporter adds `tu` (the hook call id) to `tool` and `sub_tool` events and a `cmd_end` event `{tu, h, seq, at, ok}` on `PostToolUse` and `PostToolUseFailure`, where `h` is the same hash; this is how Allye learns that you answered in the terminal.

Risk is raised only by the plugin, never lowered. High: `Bash`, unknown tools, every MCP tool other than the Allye plugin server, any Allye action that writes, and any path tool whose path is outside the project or protected. The project root is `CLAUDE_PROJECT_DIR`; when it is unset, every path tool is high. Protected paths are dotfiles and dot-directories, `scripts/` directories, manifests, lockfiles and build or CI files. Only Allye's read-only actions are normal. High requests can only be denied from Allye (or answered in the terminal). Accepted limitation: a repository `.mcp.json` server named `plugin_allye_allye` cannot be told from the plugin's server by name, so its read-looking actions count as normal; the API recomputes the risk and keeps any higher one.

The wait: up to 110 s (the hook timeout is 120 s), polling the API in chunks of at most 30 s. It ends at once on `terminal`, `expired`, `no_audience` or `answerable` false, and cancels the request on exit while it is still pending. A Yes or an answer in the terminal does not stop the hook: it ends when Allye ends the request (from `cmd_end`) or at the deadline. A decision or a question answer is printed once, after checks (decision texts are stripped of control and invisible characters and capped at 200 code points for a message and 500 for an `other` answer; NFC only when `uconv` is installed).

It does nothing, with no network call, when reporting is off (`/allye:hooks live off`), disabled, unpaired or the credential is missing. The API origin comes only from the pairing file. After an open fails the hook backs off without calling the network: 60 s after a connect failure, timeout, 5xx or other error, 10 minutes after a 404 (other than `run_not_found`) or a 405, none after a 429 or `run_not_found`. When an ingest answers 400 to a batch with `tu` or `cmd_end`, the reporter leaves them out for 10 minutes.

## Self-reported, informational

The `outcome` of a subagent comes from the `status:` line at the start of its final message (`passed`, `approved` and `ready` count as pass) and the gates come from the `- Gates:` line of the Bridge journal `.allye/missions/<slug>/log.md` (`SHIELD_CLEAR`, `WATCHER_APPROVED`, `MISSION_COMPLETE`, `CI_PENDING`). Both are what the agent wrote, not something Allye verified; treat them as information, not proof.

## Local files

Everything lives in `${CLAUDE_PLUGIN_DATA}/live` (directory 0700, files 0600), keyed by the session hash: `<hash>.spool` (events waiting to be sent), `.seq`, `.state`, `.bind`, `.gates`, `.cred` (a fingerprint of the credential last used), `.flushed` (time in milliseconds of the last send) and `.lock`; `.watch` (the Claude Code process the session belongs to, as pid and start time), `.watch.lock` (held by the running watcher) and `.watch.gone` (marker of a first missed check); `.flush.wait` (held by the one delayed flush of the session), `.final.lock` (held by the final flusher), `.subs` (subagent ids already started) and `.agents` (the stash of recent Agent/Task calls: subagent type, cleaned description and `tool_use_id`, kept at most 60 seconds), `.acts` (the last phrase of each subagent, at most 16 agents, for the per-agent dedupe; text), `.tkmem` (per agent id: the task key found and whether the metadata file was tried; no text), `.rsm` (the resume state: ids, types, handback counts and identities, markers and times; no text), `.touch` (bind touches: key and time), `.label` (time of the last label check and the last label sent; text) and `.gates` (line 1: the gate set last sent; line 2, when one was sent: the `pr` last sent), with short-lived `.flush.lock`, `.batch`, `.hdr` and `.resp` files while a send runs; plus `off` (set by `live off`), `activity-off` (set by `live activity off`), `detailed-off` (set by the reporter when Allye answers that Detailed Live is off), `disabled` (set after a rejected credential) and `backoff`. A watcher removes `.watch`, `.watch.gone`, its lock and a `.flush.wait` left by a dead process when it exits; the final flusher removes `.final.lock`. All of them are private files or directories (0600/0700) and anything else in their place is ignored. The spool keeps at most 500 lines and 256 KB; when it is full, phrase events go first (the oldest `sub_tool` events and main-session `tool` events that carry an `activity`), and only when none is left do the oldest other lines go, so a start, a stop, a state, a bind, a gates or a label event is never lost to phrases. Lines older than 23 hours are dropped instead of sent. `.acts` and `.label` hold display text, so like the stash they exist only while texts are on and are deleted by the next hook when texts are off. `/allye:hooks live off` deletes the spools, `.subs`, `.agents`, `.acts` and `.label` of every session (the text-bearing files); `.tkmem`, `.rsm`, `.touch` and `.gates` hold no text and are not purged by it.

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

These texts may leave, all one line of at most 140 Unicode code points (60 for the label), on by default:

- `desc`: the `description` of the Agent/Task call that started a subagent, sent on its `sub_start`, and read again at its stop from the subagent metadata file (see below);
- `activity`: one phrase per tool call (see "Activity phrases"), or the in-progress item (`activeForm`) of a todo list;
- `summary`: the `summary:` line of the final message or transcript report of a subagent (see "Crew report lines"), sent on its `sub_stop`;
- `label`: the session label (see "Session label").

One cleaner (the same program for all of them, cap 140, or 60 for the label) runs on your machine before anything is spooled, stashed or sent:

- control and invisible characters are removed, whitespace is collapsed, and text between backticks is removed;
- any word that looks like a path (contains `/` or `\`, starts with `~` or a drive letter), a URL or `www.` address, an email address, an IP address, a long hex or base64 string, or a token with a well-known prefix (`sk-`, `ghp_`, `github_pat_`, `xox…-`, `AKIA`, `eyJ`, `glpat-` and similar) is dropped;
- a word that names a secret (`key`, `token`, `secret`, `pass…`, `auth…`, `credential`) used as `name=value`, `name: value`, `password is value`, `Authorization: Bearer value` or `Bearer value` is dropped together with its value; the same goes for `pwd`, `cookie`, `session` and similar names, `arn:` identifiers, dotted host names, and long digit sequences such as account numbers;
- free text left with fewer than 3 words or 8 characters is not sent (the fixed phrases of "Activity phrases" and the session label skip this minimum); one longer than the cap is cut at a word and ends with `…`.

The cleaner is a documented subset of Allye's own scrubber, which stays authoritative; neither is a guarantee. Texts are what the agent wrote minus the above, not proof of what ran. The prompt, the command itself and the tool's output are never sent.

**Matching `desc` to a subagent.** When the parent calls Agent/Task, the hook stashes the cleaned description with the subagent type and the `tool_use_id`, in `.agents` (at most 16 entries, 60 seconds). `SubagentStart` carries no `tool_use_id`, so the start is matched by subagent type. Exactly one unexpired entry of that type: its description becomes `sub.desc`, its task key (see "Task key") becomes `sub.task`, and the entry is consumed. None: no `desc`. Several (parallel launches of one type): no `desc` and no task, and the other entries of that type are marked so a later start of the type is not matched with them either. The same rule applies to a start the reporter adds itself because the real one was missed. Because that async stash can lose the race with the start, the reporter also reads the dispatch description from the subagent metadata file `agent-<id>.meta.json` at every `SubagentStop`: only its `description` string is taken (cleaned, at most 140 characters, dropped when the file is unreadable, corrupt or names another id) and sent as `desc` on the `sub_stop`; no other field of the file (such as `toolUseId`) is read out or sent. There is no synchronous hook and no read at `SubagentStart`. The file is read with the safe open below.

### Activity phrases

A phrase is (a) the agent's own `description` of a Bash, Agent or Task call, through the cleaner (free text keeps the 3-word minimum), else (b) a constant template of this table with at most one allowlisted slot. Nothing of a command's arguments or of any other tool input is ever emitted, and every other tool sends no phrase:

| Tool | Phrase |
|---|---|
| Read | `Read <basename>`, else `Read a file` |
| Edit, MultiEdit, NotebookEdit | `Edit <basename>`, else `Edit a file` |
| Write | `Write <basename>`, else `Edit a file` |
| Grep, Glob | `Search the code`, `Find files` |
| Skill | `Load the <role> skill` for the twelve Bridge crew roles only |
| Allye MCP (tool suffix `__tasks`, `__specs`, `__kb` plus `action`) | `Start task KEY`, `Submit task KEY`, `Complete task KEY`, `Read spec KEY`, `Read a KB page`, `Update a KB page`; a key that does not match `^[A-Z][A-Z0-9]{1,9}-\d+(\.\d+)?$` gives the keyless form (`Start a task`, ...); any other MCP tool, no phrase |
| Bash without a description | decided on argv0 (plus the git subcommand) after dropping leading `VAR=value` words unread: `Run vitest`, `Run jest`, `Run tests`, `Lint`, `Typecheck`, `Build`, `Read the diff`, `Check git status`, else `Run a command` (also for any command holding a secret) |

The basename is the last component of the file path: one component of `[A-Za-z0-9._-]` (1 to 60 characters, at least one letter), not a secret-shaped name (16 hex characters, long tokens with digits, well-known token prefixes) and not matching the case-insensitive denylist (names starting `.env`, or containing `credential`, `secret`, `token`, `passw`, `private`, `.pem`, `.key`, `id_rsa`, `id_ed25519`, `id_ecdsa`, `.p12`, `.pfx`, `kubeconfig`, `netrc`, `npmrc`, `pairing`, `hook-`, `service-account`, `keystore`, `.tfstate`, `.kdbx`); otherwise the phrase has no file name. The directory never leaves. Both the main session and subagents use this grammar. Rules:

- **One event per call.** Every tool call of a subagent sends its own `sub_tool` event; a batch of several phrases is never collapsed into the latest one.
- **Per-agent dedupe.** A phrase equal to the previous one of the same agent id is not sent again (`.acts`, at most 16 agents).
- **Gates.** A phrase that matches a secret pattern is dropped; nothing is spooled or written to disk while texts are off.

### Result from the transcript

Background crew agents end with a `SubagentHandback` tool call and an empty final message, so the final message often holds no report. At `SubagentStop`, when the message has no non-empty report with a column-0 `status:` line, the reporter reads the tail of the subagent transcript (`agent_transcript_path`, else the path built from the session's transcript path, the session id and the agent id) and takes, in this order, the `input.message` of the last `SubagentHandback` call, then the last assistant text block. The first candidate with exactly one column-0 `status:` line and at most one column-0 `summary:` line wins; blocks are never joined, and the winner goes through the same parser as a final message, so only the whole-line fields of "Crew report lines" leave. If nothing qualifies, or a check fails, the outcome stays `unknown` as before. Only `assistant` lines count (a `status:` inside a tool result or an API blob does not), invalid JSON lines are skipped, and a partial first or last line is dropped.

**Safe open.** Every file the hook reads that a payload names or that is built from ids (the subagent transcript, the subagent metadata file, the session transcript for the label) is read only if all of these hold, and any failure keeps today's behaviour (nothing extra sent, exit 0, no output):

- the path lies under the physical `projects` directory of the user's Claude config (`CLAUDE_CONFIG_DIR`, else `~/.claude`), never one taken from the payload; every directory below it is a real directory (no symlink), with no `..`, `.`, empty or newline component;
- the basename is `agent-<id>.jsonl` or `agent-<id>.meta.json` (the session transcript for the label) with `<id>` in `[A-Za-z0-9_-]` up to 64 characters;
- the file is a regular, non-symlink file owned by the user, opened once and read from that descriptor (a FIFO or another swapped-in file is refused), by a child under `timeout`;
- all reads of one hook run share a 2 second budget; a read takes the last 256 KiB, widened once to 1 MiB when no complete line fits and then failing closed.

### Session label

At `SessionStart` and when the title changes (checked at most once a minute, and only sent when the value changed) the reporter sends `label {text, source, cwd}`: the first available of the `ALLYE_SESSION_LABEL` environment variable (source `explicit`), the last `custom-title` entry of the session transcript (`explicit`) and the last `ai-title` entry (`ai`), cleaned and cut at 60 characters (one word is enough). The transcript is read with the safe open above; Claude Code documents the transcript format as internal, so a read that finds nothing sends nothing. `cwd` is the basename of the working folder, only when it is one component of `[A-Za-z0-9._-]` (1 to 60 characters) that passes the same denylist as file names; it is sent only together with a label text. This is the one place a path component of the working directory leaves your machine. State is `.label` (display text: not written while texts are off, deleted by `live off` and by `detailed: false`).

### Task key

`sub.task` is a display hint, never authority (Allye stores it only when the run owner can read the task). It is taken from the cleaned dispatch description, at `sub_start` (the stash) and once more at the first `sub_tool` of the agent id (the metadata file, read once per id: `.tkmem` records the attempt whether or not it worked, so a failure is final for that id). A full `KEY-N.M` is a candidate (project of 2 to 10 characters, task part `N.M` with 1 to 4 and 1 to 3 digits, not glued to other word characters); when there is no full key, a bare `N.M` is a candidate, completed with the project prefix of the bound spec. Exactly one distinct candidate is taken: two different candidates give nothing, replacing the old rule that the first key wins. The reporter reads the binding strictly: a bare `N.M` is completed only when exactly one project is bound (the held binding plus the keys of the bind touches), no or several projects give nothing, and a full key of another project than that single bound project is dropped. Planning roles (dispatcher, recon, strategist, architect, armorer) never carry a task key, and a spec key alone is no task key. The Bridge skill tells the Mothership to put the full task key in the dispatch description of every Pilot, Copilot, slice Medic or Shield and docs Navigator.

### Resumed agents

A crew agent that is resumed after its stop (a correction round through `SendMessage`) becomes a new step segment of the same agent id in Allye. The reporter marks it: the first `sub_tool` or `sub_stop` it sees for an agent id after it sent that id's `sub_stop` carries `sub.resumed: true`; later events of that segment carry nothing, and the next `sub_stop` re-arms it for the next resume. The state is `.rsm` (at most 64 ids; ids, types, handback counts and an identity, no text, so it is kept with texts off). Whether `SubagentStop` fires on a resume is unproven (the spike of ALY-263.8 could not show it), so the reporter also closes a resumed segment itself: while an entry is resumed and open, at a later hook event (not `SubagentStop`, not `SessionEnd`), at most once a minute per id and for at most 2 ids per event, it reads the transcript tail (safe open) and, when the newest `SubagentHandback` differs in identity from the one recorded at the last stop (a tool_use id, else a hash of the report; never its text) and the handback count did not decrease, sends one `sub_stop` with the whole-line fields of that report. A real `SubagentStop` that fires first records the identity, so no second stop is sent. If the transcript is unreadable or the read had to widen to 1 MiB, the count is unknown and that entry is never closed from the tail (fail closed). Two handbacks with byte-identical reports and no tool_use id look like one handback.

## Crew report lines

The Bridge crew writes these lines in the final message of each subagent, or in its `SubagentHandback` message when the final message has none (their format is defined once in `skills/bridge/references/delegation.md`, "Report lines"). `SubagentStop` reads the first 65536 characters of that message, else the report taken from the transcript (see "Result from the transcript"). A line counts only when it starts at column 0 with the exact lowercase key, so an indented, bulleted, bold or differently-cased line is ignored, and the key must appear on exactly one such line; none or several omit the field. An indented copy of a line next to the column-0 one does not make it repeated: the two count as one match. Nothing is guessed from prose, and `status:` and `task:` keep their older, more lenient first-match rule.

| Line | Sent as |
|---|---|
| `summary: <text>` | `summary`, cleaned, at most 140 code points; the only message text that leaves |
| `attempt: <0\|1\|2>` | `attempt` |
| `next: <value>` | `next`, lowercased with `-` turned into `_`; one of `reviewers`, `pilot_correction`, `mothership`, `watcher`, `done` |
| `gate: SHIELD_CLEAR` / `WATCHER_APPROVED` | `gate`, only from a `shield` (`SHIELD_CLEAR`) or `watcher` (`WATCHER_APPROVED`) subagent; `null` is ignored |
| `checks: ok=<n> run=<n>` | `checks {ok, run}` |
| `severity_counts: critical=<n> high=<n> medium=<n> low=<n> info=<n>` | `findings {critical, high, medium, low, info}`, all five keys once, in that order |
| `phase: stage\|publish` | `sub.phase`; any other value sends nothing |
| `status: ready` / `status: approved` (column 0, once) | the code `ready` or `approved` on the `sub_stop`; the outcome stays `pass` |

Each number is an integer 0 to 99 without sign, decimal point or leading zero. Any deviation (a value out of range, a missing key, trailing text) drops that line; `checks` and `findings` are all or nothing. A report without the new lines produces the same events as before. Like `outcome`, these values are what the agent wrote, not something Allye verified.

## Hot-path latency

The per-event cost of the hook is measured, not asserted: `hooks/test/measure-latency.sh` replays the 28 tool events of an ALY-260-style sequence against the frozen v2.12.0 script and the current one and prints p50 and p95 per tool event (informational, it never fails on a threshold). With `ROUNDS=10` the p95 delta over v2.12.0 was +2 to +4 ms for a subagent tool event and +9 to +10 ms for a main-session one, after the per-session private-file checks were batched into one `find` and clock forks were skipped on the hot path (before that it was +30 to +32 ms). The budget is at most 30 ms p95 over the baseline. Timings depend on the machine; treat the figures as indicative.

## Test-only settings

`ALLYE_LIVE_WATCH` (`0` disables the watcher), `ALLYE_LIVE_WATCH_INTERVAL` (poll seconds, 1 to 20), `ALLYE_LIVE_WATCH_CAP` (run limit in seconds) and `ALLYE_LIVE_FINAL_DELAYS` (retry delays of the final flusher) and `LIVE_ANSWER_BUDGET_S` (lowers the 110 s wait of the answer hook) exist for the automated tests only. Do not set them in normal use; the defaults above are the supported behaviour.

## Release order

The `end_process_gone` code, the longer texts, `sub.desc`, `sub.task` and the chips of `sub_stop`, and the fields of this release (the per-call `activity` phrases, `desc` on `sub_stop`, `sub.resumed`, `sub.phase`, the codes `ready` and `approved`, the `label` event with its folder name and `pr` on the `gates` event) need the Allye API that accepts them to be deployed (production included); the API with these fields is live. An API that does not know a field answers 400, and the reporter discards a 400 batch for good: it is neither kept nor retried, so a plugin newer than the API loses those batches. The release order is therefore API, then plugin, then app. An older plugin works against the newer API (it just sends no new fields). The API rolls back only together with the plugin: rolling the API back alone leaves a newer plugin sending fields it now rejects. Update the plugin only after the API is live.

## Turning it off

`/allye:hooks live off` sets the `off` flag first, then sends a final `state` `ended` with code `end_live_off` for each session known locally, deletes the spools and the text-bearing state files (`.subs`, `.agents`, `.acts`, `.label`) and sends nothing afterwards. It reports how many sessions it ended and how many it could not (a busy session or a failed request); Allye ends those by itself after a period of silence. `live on` removes the flag, and reporting resumes with the next hook event. `live status` makes no network call. Unpairing, or uninstalling the plugin, also stops it.
