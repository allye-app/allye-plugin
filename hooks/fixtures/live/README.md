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
