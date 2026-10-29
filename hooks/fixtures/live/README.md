# Live reporter fixtures (ALY-203.2)

One `<name>.json` per hook payload (stdin of `hooks/live-report.sh`) and a `<name>.expect` listing, one compact JSON
object per line, the contract events (without `at`) that must be spooled for it: an empty file means "nothing".
Every payload carries hostile `MARKER_*` strings and the raw session id `RAWSESSION-...`; the suite asserts that none of
them reaches any file, name, log or output, and that files are keyed by the SHA-256 of the session id.

## Hook events and enumerations, checked against the installed Claude Code (D-08, BR-15)

Installed: Claude Code 2.1.306 (`claude --version`), binary `~/.local/share/mise/installs/claude/latest/claude`.
Evidence: `strings` on that binary (bundled hook input schemas). No network, no credential file read, claude not run.

| Event / enumeration | Status | Evidence literal in the binary |
|---|---|---|
| hook event list | confirmed | `["PreToolUse","PostToolUse","PostToolUseFailure","PostToolBatch","Notification","UserPromptSubmit","UserPromptExpansion","SessionStart","SessionEnd","Stop","StopFailure","SubagentStart","SubagentStop",...,"PermissionRequest","PermissionDenied",...]` |
| SessionStart | confirmed | `hook_event_name:A("SessionStart"),source:F(["startup","resume","clear","compact","fork"])` |
| SessionStart source values startup, resume, clear, compact | confirmed (also `fork`, accepted) | same literal |
| UserPromptSubmit | confirmed | `hook_event_name:A("UserPromptSubmit"),prompt:o(),source:F(["user","sdk",...` |
| UserPromptExpansion | confirmed; emits no state, only a `bind` for `/bridge <mode> [KEY]` (ALY-203.3) | `hook_event_name:A("UserPromptExpansion"),expansion_type:F(["slash_command","mcp_prompt"]),command_name:o(),command_args:o()` |
| PreToolUse | confirmed | `hook_event_name:A("PreToolUse"),tool_name:o(),tool_input:oe(),tool_use_id:o()` |
| PostToolUse | confirmed | `hook_event_name:A("PostToolUse"),tool_name:o(),tool_input:oe(),tool_response:oe()` |
| PermissionRequest | confirmed | `hook_event_name:A("PermissionRequest"),tool_name:o(),tool_input:oe(),permission_suggestions:` |
| Notification | confirmed | `hook_event_name:A("Notification"),message:o(),title:o().optional(),notification_type:o()` |
| notification_type permission_prompt, idle_prompt | confirmed (a free string in the schema; both appear in the known list) | `"permission_prompt","idle_prompt","auth_success","elicitation_dialog","agent_needs_input","agent_completed",...` |
| any other notification_type | dropped | |
| SubagentStart | confirmed | `hook_event_name:A("SubagentStart"),agent_id:o(),agent_type:o()` |
| SubagentStop | confirmed | `hook_event_name:A("SubagentStop"),stop_hook_active:M(),agent_id:o(),agent_transcript_path:o(),agent_type:o(),last_assistant_message:` |
| Stop | confirmed | `hook_event_name:A("Stop"),stop_hook_active:M(),last_assistant_message:` |
| StopFailure | confirmed | `hook_event_name:A("StopFailure"),error:go(),error_details:o().optional(),last_assistant_message:o().optional()` |
| StopFailure error values | confirmed list: `authentication_failed, oauth_org_not_allowed, account_on_hold, verification_required, billing_error, rate_limit, overloaded, invalid_request, model_not_found, server_error, unknown, max_output_tokens, cloud_credential_error`; only `rate_limit, authentication_failed, billing_error, invalid_request, server_error, max_output_tokens` have a contract code, every other value (and a missing or hostile one) becomes `cli_error_unknown` | `["authentication_failed","oauth_org_not_allowed","account_on_hold","verification_required","billing_error","rate_limit","overloaded","invalid_request","model_not_found","server_error","unknown","max_output_tokens","cloud_credential_error"]` |
| SessionEnd | confirmed | `hook_event_name:A("SessionEnd"),reason:R0()` |
| SessionEnd reason values | confirmed: `clear, resume, logout, prompt_input_exit, other` (the list starts earlier in the binary; the first four have a contract code, anything else is `end_other`) | `"clear","resume","logout","prompt_input_exit","other"]` |
| subagent context on tool hooks | confirmed: base input has optional `agent_id` and `agent_type`, present only inside a subagent; tool events carrying a valid pair become `sub_tool` | `agent_id:o().optional().describe("Subagent identifier. Present only when the hook fires from within a subagent ...` |
| async command hooks | confirmed | `async:M().optional().describe("If true, hook runs in background without blocking")` (hook config schema) |
| common input fields | confirmed | `session_id:o(),transcript_path:o(),cwd:o(),prompt_id:...,permission_mode:...,agent_id:...,agent_type:...` |

Other events exist in the binary (PostToolUseFailure, PostToolBatch, PermissionDenied, PreCompact, ...) but the spec maps
none of them: they are neither mapped, fixtured (except as `unmapped-event-*` negative controls) nor to be registered.

## Mapping implemented in this slice

SessionStart -> `state started`; UserPromptSubmit -> `state working`; PreToolUse -> `tool` (tool name only, pattern
`^[A-Za-z][A-Za-z0-9_]{0,31}$`; `sub_tool` with `sub {id,type}` when `agent_id` is present); PreToolUse AskUserQuestion ->
`state waiting_input` `asked_question`; PermissionRequest and Notification permission_prompt -> `waiting_input`
`permission_prompt`; Notification idle_prompt -> `state idle`; SubagentStart/Stop -> `sub_start`/`sub_stop` with `sub {id,type}`
(no outcome or task until ALY-203.4); Stop -> `idle` `turn_ended`; StopFailure -> `error` `cli_error_<error>` or
`cli_error_unknown`; SessionEnd -> `ended` `end_<reason>` or `end_other`. A `state working` is inserted before the first
tool, sub_tool or sub_start after `waiting_input` (BR-14). 

## Decisions of correction round 1

- PostToolUse emits no `tool` or `sub_tool` event (D-01 maps only PreToolUse to `tool`; a Post event would double traffic). It only
  triggers BR-14: when the last state is `waiting_input`, `state working` is spooled; otherwise nothing is spooled.
- BR-14 fires even when the tool name, or the sub id/type, fails its pattern and the event itself is dropped (PreToolUse,
  PostToolUse, SubagentStart): the session is demonstrably active again.
- Carry-forward: the lock around read-state/append/write-state (SHD-02) goes to ALY-203.5; the spool cap (SHD-03) to .5/.7.

## ALY-203.3: tool reduction and binding

- Tool reduction runs before the 32-character name rule. `mcp__<server>__<tool>` (server `allye` or ending `_allye`, e.g. the
  plugin server `plugin_allye_allye`) -> `allye:<action>` when `tool_input.action` matches `^[a-z_]{1,40}$`, else `mcp`; any
  other MCP tool -> `mcp`; an MCP name with characters outside `[A-Za-z0-9_-]` is dropped. Same for `sub_tool`. Naming rule
  inferred from the `mcp__plugin_allye_allye__*` tools of this Claude Code; a third-party plugin shipping a server named `allye`
  would also be classed as Allye (only a tool-name label leaves, so nothing sensitive).
- Bind (`bind` event, after the event's own lines): strength skill > mcp > env > branch, persisted as `<hash>.bind`
  (`<rank>|<bind json>`, 0600). Sent when stronger than the stored one, or equal with different content; never weaker or
  identical. Calls inside a subagent never bind. A task key does not supply a spec part.
- skill: `Skill` tool call (`bridge`/`allye:bridge`) or `UserPromptExpansion` (`command_name` bridge/allye:bridge) with
  `<mode> [KEY]`. Invalid mode: no bind. Invalid key: the key only is dropped. A key with a dot is `task`, else `spec`.
- mcp: main-session Allye MCP call (server `allye` or `*_allye`) whose `tool_input.action` is exactly `task_start` or
  `task_submit` (ALY-217.4, D-22); `tool_input.spec` / `tool_input.task` each kept only when it matches the key pattern, no
  bind when neither does. Every other action (reads such as `spec_get`, `spec_list`, `task_get`, approvals such as
  `spec_approve`, other transitions, a missing or invalid action, `TASK_START`) spools only its tool event, no bind.
  Key-validation fixtures: `mcp-allye-task-start-*`; the rank and tie cases use `mcp-allye-task-start-half-bad-key`.
- env: `ALLYE_SPEC`/`ALLYE_TASK`, read through jq `$ENV` (never argv), at SessionStart, role `session`.
- branch: SessionStart only, no bind of rank above branch stored, cwd absolute + existing directory + no control characters,
  `git -c core.fsmonitor= -c core.hooksPath=/dev/null -C <cwd> branch --show-current`, 1 s (`timeout` if present, else a
  background watchdog). The git shim wraps the real git, so branch tests use throwaway repositories in the sandbox.
- New fixtures: `skill-*`, `expansion-*`, `mcp-*` (the `.expect` lists the tool and bind lines; the environment and
  branch sources are covered by generated payloads in `hooks/test-live-report.sh`).

## ALY-217.6: activity phrases

- Sources (D-24), PreToolUse only: Bash and Agent/Task `tool_input.description`; TodoWrite the `activeForm` of the first
  `tool_input.todos` item whose `status` is `in_progress`. No other field (command, prompt, todo `content`, other
  `activeForm` values) is read. The phrase goes on the event's own `tool` / `sub_tool` line as `activity`.
- Cleanup and redaction (D-23) run in the reporter's jq program: whitespace (tabs, line breaks, Unicode spaces) to one
  space; C0/C1 controls, DEL, bidi controls, zero-width and every other format character, U+034F, variation selectors and
  tag characters stripped; backticked spans removed; tokens dropped when they look like a path, URL, email, IP address,
  long base64/hex string, any `[A-Za-z0-9_-]{24,}` run, a known token prefix (`sk-`, `pk-`, `rk-`, `ghp_`, `gho_`, `ghs_`,
  `github_pat_`, `xox[abprs]-`, `AKIA`, `ASIA`, `eyJ`, `glpat-`) or a secret: `key=value` / `key:value`, a bare `key:`,
  `key = value` / `key : value`, `password|passwd|secret|token|apikey|api_key|... [is|as] value`, `Authorization[:]
  Basic|Bearer|Token|Digest value` and `Bearer value` (key, separator, scheme and value all dropped, chained; Shield
  SHD-01/SHD-03 of ALY-217.6); fewer than 3 words or 8 characters: no `activity`; above 48 code points: cut at the last
  space plus U+2026. The Agent stash reaches jq through `--rawfile`, never argv (SHD-02).
- Fixtures: `activity-bash*`, `activity-todowrite*` and the redaction table `activity-redact-*` (one dropped kind per
  file; the parts that are dropped hold markers). Invisible characters are written as JSON `\uXXXX` escapes only.
- `pre-tool-use.json` keeps the one-word description `MARKER_MSG`: too short, so its `.expect` has no `activity`.
- `mcp-allye-subagent` is a `task_start` with valid keys (a call that binds in the main session), so "calls inside a
  subagent never bind" is not vacuous; the harness also runs it without `agent_id` and expects the bind.
- The Agent/Task stash (`<hash>.agents`, FIFO by subagent type within 60 s), the cap and the `activity-off` switch are
  covered by generated payloads in `hooks/test-live-report.sh`.

## ALY-217.7: synthetic sub_start and the SessionEnd send

- Background agents: the schema above gives `SubagentStart` its `agent_id` and `agent_type`, but nothing in this repository
  (schema literals, fixtures) says whether it fires for `run_in_background` agents, and PROD spools showed `sub_tool` events
  of background agents with no `sub_start`. So, whatever the CLI does (D-26): before the first `sub_tool` or `sub_stop` of a
  sub id not yet seen in the session, the reporter spools a `sub_start` with the same `sub {id, type}` and `at` (seq just
  below). The seen ids live in `<hash>.subs` (one id per line, ids checked by the sub id pattern, at most 64, oldest
  dropped, 0600, written under the state lock by temp + mv). A real `SubagentStart` adds its id; a `SubagentStart` of an id
  already in the set spools nothing. A set that is a symlink or not a private file is neither used nor written (no
  synthetic `sub_start` then). The first `sub_start` of an id, real or synthetic, takes the Agent stash entry (D-24).
- The fixtures of tool events inside a subagent (`*-subagent`, `subagent-stop`) are run alone in a fresh sandbox, so their
  `.expect` now starts with the synthetic `sub_start`. New: `sub-tool-unseen` (sub_start + sub_tool),
  `sub-tool-unseen-stop` (sub_start + sub_stop), `sub-tool-unseen-post` (a PostToolUse spools nothing, so no sub_start)
  and `sub-tool-unseen-bad-id` (an id failing the pattern: nothing).
- SessionEnd (D-27): the `state ended` line is sent by the hook itself, in the foreground, within 1.5 s: `flush.lock` is
  tried every 100 ms for up to 400 ms, the spool goes out in order with 1 s curl limits cut to the budget. When the lock
  stayed busy, the send failed or an ended line is still in the spool, a detached final flusher (`live-report.sh final`,
  stdio on `/dev/null`, SIGHUP ignored, `setsid` when present, one per session through the pid lock `<hash>.final.lock`)
  tries again at once and after 2, 5, 15, 30 and 60 s (test knob `ALLYE_LIVE_FINAL_DELAYS`), waiting up to 10 s for
  `flush.lock` each time, honouring off, disabled, a changed credential and the back-off; it exits when no ended line is
  left or after its last attempt, removing `final.lock`. The API idle expiry stays the backstop.

## ALY-258.1: desc and task on sub_start, the 140-code-point cleaner

- One cleaner (`actphrase($cap)` in the reporter's jq program), cap 140 for `activity`, `desc` (and `summary`, ALY-258.2); it is
  a documented subset of the API scrubber (ALY-257 D-20), which stays authoritative. Beyond the ALY-217.6 table it drops: the
  distinctive secret prefixes anywhere in a token (`sk-`, `sk_`, `pk-`, `rk-` only at a token start or after a non-alphanumeric),
  `arn:`, bare dotted hostnames (3+ labels, or 2 with a common TLD), separator-joined hex pairs, 11+ digits with separators
  (account ids, CPF/CNPJ, phones, cards) and the whole-word names `pwd`, `pw`, `cookie`, `session`, `sid`, `passphrase` as `k=v`,
  `k: v`, `k = v` or `<word> is <value>`. It is stricter than D-20 where noted in the vector table.
- `vectors/agent-run-text-vectors.json`: plugin-owned vector table derived from D-20 (kept in a subdirectory so the fixture loop
  does not take it for a hook payload). Swap it for the API shared file when that exists. `plugin: exact` = output equals
  `output`; `safe` = the plugin is stricter (forbidden tokens absent, `plugin_output` is its result); `skip` = a D-20 rule the
  plugin does not implement (`reason` says why). `input_gen`/`output_gen` build long strings. The suite replays every vector
  through the cleaner cut out of `live-report.sh` and checks the forbidden tokens, the 140 limit, one line and idempotence.
- Stash correlation (D-32): the Agent/Task stash entry gains `id` (the PreToolUse `tool_use_id`). `SubagentStart` and
  `SubagentStop` carry no `tool_use_id`, so a start is matched by subagent type within the 60 s TTL: exactly one unexpired
  entry of the type gives `sub.desc` (and `sub.task`, the first dotted task key of the cleaned description) to the `sub_start`
  (real or synthetic) and is consumed; none gives nothing; several (parallel launches of one type) give nothing and the other
  entries of the type become tombstones (empty text, expiring by TTL) so a later start of the type never pairs with them. There is no separate Agent `sub_tool` event any more. Covered by generated payloads in the test.
- `batch_build` keeps only `id`, `type`, `outcome`, `task` and `desc` inside `sub` (the nested allowlist; ALY-258.2 extends it).
- `LIVE_TEST_SECTIONS` (regex over the section names) runs a subset of `hooks/test-live-report.sh`; unset runs everything.

## ALY-258.2: summary and chips on sub_stop

- The strict parser (`newfields` in the reporter's jq program) reads the first 65536 characters of `last_assistant_message`. A line
  counts for a key only when it starts at column 0 with the exact lowercase key (`summary:`, `attempt:`, `next:`, `gate:`,
  `checks:`, `severity_counts:`; LF or CRLF), and the key must be on exactly one such line of the slice; zero or several omit the
  field. Indented, list-marker, bold or different-case lines are not counted. `status:` and `task:` keep their lenient first-match rule
  (previous events are unchanged when none of the new lines exist). A lone `summary:` at column 0 inside a code fence matches.
- `summary` goes through `actphrase(140)` and is sent only when the cleaner keeps it and texts are on (`$txt == "1"`); it is the only
  message text that leaves. `attempt` 0-2; `next` lowercased, `-` to `_`, one of reviewers|pilot_correction|mothership|watcher|done;
  `gate` only for type shield (SHIELD_CLEAR) or watcher (WATCHER_APPROVED), `null` ignored; `checks {ok,run}` and
  `findings {critical,high,medium,low,info}` (all five keys, once, in that order). Integers 0-99 with no sign, decimal point or
  leading zero; any deviation or trailing junk omits the field (checks/findings all or nothing).
- `batch_build` allows `summary`, `attempt`, `next`, `gate`, `checks`, `findings` inside `sub` and checks their type and range
  (a bad value drops the field, never the event; nested objects keep only their keys).
- Cases are generated in `hooks/test-live-report.sh` (sections `report lines` and `batches with the longer texts`; they use the
  `stopped` helper of `subagent outcome`, select both). Existing fixtures are untouched and still pass (AC-12).

## ALY-258.3: Detailed Live ack flag, texts stripped at flush, consent text

- Ack flag (D-36, AC-14): on a 2xx answer of the ingest route `flush_run` reads the same bounded body it already reads for the error
  code. A VALID ack is `.data.accepted` a number. In a valid ack only the strict boolean `.data.detailed == false` writes
  `$CLAUDE_PLUGIN_DATA/live/detailed-off` (empty, temp 0600 + mv under the state lock, so a symlink at that name is replaced and
  never followed) and deletes the Agent stashes; a valid ack with anything else (true, field absent, null, another type) removes the
  flag (absent = true). A 2xx whose body is not a valid ack (204, empty, truncated, not JSON, a captive-portal page), a non-2xx and a
  failed send (a 200 KB ack exceeds curl's `max-filesize`) leave the flag exactly as it is: fail closed, never set, never cleared
  (Shield SHD-01). No extra network call.
- Texts off (BR-03, AC-08): `activity-off` (the user's opt-out) or `detailed-off` exists (any entry, symlinks included: fail safe).
  The hook then attaches no `desc`, `activity` or `summary`, writes no stash and deletes an existing `<hash>.agents`; `batch_build`
  (the only place a spooled line becomes a request: hook send, delayed flush, SessionEnd and the final flusher) removes `activity`,
  `sub.desc` and `sub.summary` from every event at each flush, so events spooled before the flag are cleaned. Structured fields
  (`task`, `attempt`, `next`, `checks`, `findings`, `gate`, `outcome`) and tool events go on.
- On a 400 the batch is discarded (existing behaviour, now commented in `flush_run`): a plugin newer than the API therefore loses
  its batches, which is why the API ships first and rolls back only together with the plugin (D-37; the docs are task .5).
- `hooks/test/fake-hooks-api.mjs`: the data-dir file `ingest-detailed` (`false`, `true`, `junk`, `null`, `nobody`, `notjson`; absent =
  no `detailed` field in a valid ack) shapes the 2xx ack. The tests are the section `activity: Detailed Live ack flag...` of `test-live-report.sh`
  (select it with the other `activity` sections, it uses their helpers) and the `texts` cases of `test-allye-hooks.sh`.
- `commands/hooks.md` discloses the three texts (140 characters, best effort without guarantee, only the `summary:` line of a crew
  report) and both ways to turn them off; `live activity off|on|status` and `live status` say "texts" and why they are off.

- `vectors/api-agent-run-text-vectors.json`: byte-for-byte copy of `src/modules/agent-runs/agent-run-text-vectors.json` of allye-api
  `origin/develop` at commit e8c361ee9f8970253dcd7c99c8f569f64237e7b5 (ALY-257). The suite checks that no token the API drops
  survives in the plugin output (the plugin may be stricter, never looser). Refresh it by copying the file again and updating this commit.
