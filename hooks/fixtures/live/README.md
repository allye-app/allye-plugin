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
  entry of the type gives `sub.desc` (and `sub.task`, see the task key rule below) to the `sub_start`
  (real or synthetic) and is consumed; none gives nothing; several (parallel launches of one type) give nothing and the other
  entries of the type become tombstones (empty text, expiring by TTL) so a later start of the type never pairs with them. There is no separate Agent `sub_tool` event any more. Covered by generated payloads in the test.
- Task key rule (ALY-263.10, AC-10, D-07, D-14; section `taskkey` of the test): `sub.task` is a display hint taken from the CLEANED dispatch
  description (a key inside a token the cleaner dropped is never sent) at the `sub_start` (stash) and once more on the first `sub_tool` of an
  agent id (the metadata file `agent-<id>.meta.json`, same safe open and 2 s budget as at the stop, built from `transcript_path` and the
  ids). Candidates: every full `KEY-N.M` (project `[A-Z][A-Z0-9]{1,9}`, N of 1 to 4 digits, M of 1 to 3, not glued to a word, `-`, `_` or `.`
  before it nor to a letter, digit or `.digit` after it); only when there is no full key, every bare `N.M` (`^\d{1,4}\.\d{1,3}$`, a `-` or `/`
  before it is a border, so `aly-263.3` and a version like `2.12.0` give nothing). Exactly one distinct candidate is taken; two distinct
  ones are ambiguous and give nothing (this replaces "the first key wins"). A bare key is completed with the project prefix of the strongest
  binding and only when exactly one project is bound (the held binding in `$HASH.bind` plus the keys of `$HASH.touch`): no binding or several
  projects give nothing. A full key of another project than the single bound one gives nothing (prefix mismatch). The dispatcher, recon,
  strategist, architect and armorer roles give nothing, and a spec key alone (no dotted part) is no task key. The metadata file is read ONCE
  per agent id: `$HASH.tkmem` (JSON `[[id, task or "", tried 0|1]]`, newest 64, 0600, private regular file of at most 8192 bytes, no text;
  absent, corrupt or off-shape entries count as empty, so old installs work) records the attempt whether or not it worked, so a failure is
  final for that id ("unreadable then readable" keeps no key). `sub.task` goes on the `sub_tool` only when it differs from the value already
  sent for that agent (the start's). With texts off (`activity-off`, `detailed-off`) nothing is read, sent or written, as for `desc`.
- ALY-263.11 (AC-12, D-05, D-19): `sub.resumed: true`. `$HASH.rsm`: line 1 is the earliest time (ms) a tail check may run (`-` when no segment can be closed),
  line 2 the JSON `[[id, type, SubagentHandback count at the last stop (-1 unknown), "s"|"r"|"c", ms of the last tail check, identity of the newest handback at
  that stop ("" unknown)]]`; newest 64 ids, 0600, private regular file of at most 16384 bytes, ids, integers and an identity only (a tool_use id of at most 40
  characters as `i<id>`, else `h` + 16 hex of the sha256 of the report, never the text), so it is kept with texts off. Absent, corrupt or off-shape entries
  count as empty; the former five-field entries read clean with an unknown identity and never close. Only the FIRST `sub_tool` or `sub_stop` of an id whose
  entry is `s` (or `c`) carries the flag; a flagged tool makes the entry `r` (resumed, open: later events carry nothing), any `sub_stop` re-arms it as `s` with
  the count and identity read at that stop, so the next resume cycle is flagged again. A repeated `sub_start` stays dropped by the seen-set. The batch builder
  keeps `sub.resumed` only as the boolean `true`. Count and identity come from the SubagentHandback tool_use blocks of the transcript tail (safe read of slice .1,
  shared 2 s budget), read at every `SubagentStop` and by the tail close; an unreadable transcript, or a read widened to 1 MB (its window is not comparable),
  records an unknown count and identity, and such an entry can never be closed from the tail (fail closed).
  Tail close (built because SubagentStop on a resume is UNPROVEN, `spike-facts.txt`): while an entry is `r` with a known count and identity, at a later hook
  event of the session that is not a `SubagentStop` or `SessionEnd`, at most once per id per minute (the time is stored even when nothing closed) and for at
  most 2 ids per event, the transcript tail is read. Cost: a non-due event runs zero forks (one builtin `read` of line 1 and arithmetic on `$EPOCHREALTIME`, `date`
  only on a bash without it); a due event first checks the file is private (one `find`), then reads at most 2 ids, once a minute each. An unusable state file
  (not private, symlink, oversized) is never read, so it costs one `find` per event and nothing else. ONE `sub_stop` is spooled when the newest handback
  identity DIFFERS from the recorded one and the count is not lower: same whole-line fields from the newest handback only (the report goes to jq through a
  file, never argv), summary gated by the texts flags, no `desc`, no resumed flag; the entry becomes `c`. A real `SubagentStop` that fires first records its
  identity, so the close never runs; one that fires after a close for the same identity is dropped (no second stop, no spurious segment). Accepted limits:
  two handbacks with byte-identical reports and no tool_use id look like one (no close); a stop whose transcript line was not yet flushed records the previous
  handback, so the next check can report the last handback as a close (a bounded, at most once per handback, late stop; see the Shield finding SHD-04).
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
- ALY-263.12 (AC-14): `phase:` (same whole-line rule; value exactly `stage` or `publish`, anything else omitted) goes on `sub.phase`;
  a column-0 `status: ready` or `status: approved` (once per report, first-match outcome stays `pass`) adds the top-level code
  `ready` or `approved` on the `sub_stop` (indented, repeated or uppercase: no code; `passed`, `needs-input`, `escalate` and the
  other values map as before). Both are enum metadata: sent with texts off, and `phase` is validated at flush as the closed enum. The
  transcript fallback and the tail-close stop use the same parser.
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

## Session label (ALY-263.6)

- `label` event (nested, the ingest DTO of ALY-262): `{type: "label", label: {text, source: "explicit"|"ai", cwd?}}`; `text` is
  required and at most 60 characters (the one cleaner of the reporter with 60 characters and no 3-word minimum, because a title can
  be one word), `cwd` is the working directory basename through the basename rules of D-08. Sources in order: env
  `ALLYE_SESSION_LABEL` (explicit), the last `custom-title` entry (`customTitle`, explicit) and the last `ai-title` entry (`aiTitle`,
  ai) of the session transcript `<session id>.jsonl`, read with the safe open of the subagent files (last 256 KB, shared 2 s budget).
  `cwd` is sent only inside a label and only from a real directory; with no label text nothing is sent. The SessionStart fixtures
  keep `/work/MARKER_CWD`, so they send no label; the section `label` of `test-live-report.sh` builds its payloads.
- `<hash>.label` holds `<ms of the last check> <last value sent as JSON>` (0600, at most 1024 bytes): a check runs at a SessionStart and
  at most once a minute at other main-session events, and a value is sent only when it changed. It holds display text, so it is
  never written while `activity-off` or `detailed-off` exists, is deleted by the next hook then, and by `live off` and the
  `detailed: false` ack. `batch_build` does not send a label event while texts are off. `spooled` in the tests leaves label events out;
  `labels` reads them.

## Tool classifier (ALY-263.9)

The `sub_tool` phrase (`toolphrase` in the reporter's jq program) is (a) the Bash/Agent/Task `description` through the cleaner (free text
keeps the 3-word minimum), else (b) a constant template of this table with at most one allowlisted slot. Nothing else of the tool input
is ever emitted, and templates skip the 3-word minimum. Since ALY-263.13 the main-session `tool` event uses the same grammar and gates.

| Tool | Phrase |
|---|---|
| Read | `Read <basename>`, else `Read a file` |
| Edit, MultiEdit, NotebookEdit | `Edit <basename>`, else `Edit a file` |
| Write | `Write <basename>`, else `Edit a file` |
| Grep / Glob | `Search the code` / `Find files` |
| Skill | `Load the <role> skill` for `allye:bridge-<role>` or `bridge-<role>` with one of the 12 crew roles; else no phrase |
| Allye MCP (server `allye` or `*_allye`), suffix + `action` | `__tasks`: task_start / task_submit / task_complete -> `Start|Submit|Complete task KEY`; `__specs`: spec_get / spec_context -> `Read spec KEY`; `__kb`: kb_read / kb_search / kb_tree -> `Read a KB page`, kb_update / kb_section / kb_create -> `Update a KB page`. KEY must match `^[A-Z][A-Z0-9]{1,9}-\d+(\.\d+)?$`, else `Start a task`, `Submit a task`, `Complete a task`, `Read a spec`. Every other MCP tool and every unknown tool: no phrase |
| Bash without a description | leading `VAR=value` words dropped unread; then by argv0 (its basename) and a fixed word: `vitest` -> `Run vitest`; `jest` -> `Run jest`; `eslint`, `lint` -> `Lint`; `tsc`, `typecheck` -> `Typecheck`; `tsc -b`/`--build`, `build`, `make build` -> `Build`; `git diff` -> `Read the diff`; `git status` -> `Check git status`; `node --test*` -> `Run tests`; `npm|pnpm|yarn|bun [run] test|lint|typecheck|build|vitest|jest|eslint|tsc` (and `npx|bunx|pnpx <tool>`) by the same words; anything else, and any command holding a secret -> `Run a command` |

The basename is the last path component of `file_path` (`notebook_path` for NotebookEdit): `^[A-Za-z0-9._-]{1,60}$`, at least one
letter, not all dots, not matching the case-insensitive denylist (`namedeny`, the one copy, shared with the label's working directory
basename) and not matching the secret-shaped drops (`namedrop`: 16 hex characters, 20+ characters with a digit, 24+ characters, token
prefixes), else the constant. The section `classifier` of `test-live-report.sh` covers the table and 36 hostile paths. The
subagent fixtures use `/x/MARKER_PATH/readme.txt`: the marker stays in a directory, which never leaves.

## The PR number on the gates event (ALY-263.15, AC-18, D-20, D-21)

The existing gates read of the verified mission log (the same main-session Write/Edit path and file checks as the `- Gates:` line,
`mission_log_of`, 64 KB bound, no symlinks) also takes the first column-0 line matching `^- PR: #([1-9][0-9]{0,6})[ \t\r]*$` (a line
that does not match is skipped; the first MATCHING line wins). Only its number leaves, as the JSON integer `pr` of the `gates` event,
and only when it differs from the last pr sent. Any other text on the line, `#0`, `#01`, 8 digits, a sign or a decimal, an indented,
lowercase or tab-separated line, and a PR line in any other file, in a transcript or in a message send nothing.

- State: `$HASH.gates` keeps the set last sent on line 1 and, when one was sent, the pr on line 2. An old file (the array alone) reads
  clean as "no pr yet" and is not resent; a corrupt second line reads as no pr. The same private-file checks apply (wrong mode or a
  symlink: nothing is sent, the pr included). A log that later loses its PR line sends nothing and the stored pr is kept.
- Event: the gates event is sent when the set or the pr changed. It always carries `gates`: the current set when the log has a
  `- Gates:` line, else the last set sent (`[]` at first), because the API requires the array. `pr` is present only when it changed.
- Flush: `pr` is in the allowlist of a `gates` event only; it must be an integer 1..9999999, anything else is dropped and the event
  stays. It is metadata, not display text: it is sent with texts off.
- Cases: the `gates:` sections of `test-live-report.sh` (valid line, first line wins, malformed numbers, indented/lowercase, change
  and no-change, old state file, texts off and flush validation, unverified files, read failures, hostile long lines).
