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
