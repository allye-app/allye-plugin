# Spike: Live return channel (ALY-269)

Question: can a Claude Code hook hold a permission or question dialog open while the Live
service decides remotely, and hand the decision back to Claude? The evidence comes from a
throwaway kit that is not committed: one command hook registered for PreToolUse,
PermissionRequest, PostToolUse, PostToolUseFailure and SubagentStop. It logged which payload
keys arrived, whether `tool_use_id` was present, every heartbeat (every 5 s), every SIGTERM,
and in selectable modes (wait, allow, deny, answer, delay-allow, delay-deny, delay-answer,
pass) printed a decision. A rerun needs an interactive Claude Code session (v2.1.310 was
used), because permission and question dialogs do not appear in headless mode.

Dialog-related lines (A01, A02, A04 "dialog intact", A05 "dialog skipped/closes", A09 and the deny message of A10) are screen observations by the coordinator in the interactive tmux session, not log facts; they are tagged "(observed on screen)".

Answers (one line per question; the id is stable):

A01 PermissionRequest hook waiting: the terminal permission dialog stays shown and usable (yes; observed on screen).
A02 PreToolUse hook on AskUserQuestion waiting: no dialog, only "running PreToolUse hook" (no-go for waiting on this event; observed on screen).
A03 Terminal answered first, SIGTERM behaviour: for a Bash PermissionRequest hook a local Yes left it running with no signal (PostToolUse fired at +23 s and it kept heartbeating to 115 s, then SIGTERM at 120 s, the hook's own timeout); No/Esc delivered SIGTERM (12 s for Bash, 23 s for the PreToolUse question hook). For an AskUserQuestion PermissionRequest hook in wait mode (pid 543853) PostToolUse fired at +11 s, the hook kept heartbeating to 30 s and got SIGTERM at +32 s; the cause is not recorded in the log (a No/Esc answer is the likely one, unconfirmed), so no claim is made about a local question answer.
A04 Timeout default and maximum: not observed; the configured timeout of the 120 s case is not recorded, so the default stays unknown, and the plugin sets 120 s explicitly. A hook timeout of 15 s gave SIGTERM at 15 s with the dialog intact (dialog intact observed on screen).
A05 updatedInput.answers honoured: yes, for PreToolUse (dialog skipped) and for PermissionRequest decision.updatedInput (open dialog closes, Claude receives the answer); the PostToolUse that followed is in the log, the dialog skipped/closing was observed on screen.
A06 tool_use_id: absent from every PermissionRequest payload (main and subagent for Bash, main for AskUserQuestion); present in PreToolUse and PostToolUse.
A07 PostToolUse tool_use_id in subagents: present; PostToolUseFailure exists and carries tool_use_id (mandatory input of ALY-269.2).
A08 PermissionRequest also fires for AskUserQuestion: yes, tool_input carries the questions.
A09 Hook allow vs deny rules: a permissions deny rule wins and PermissionRequest does not fire (observed on screen, not in the log); managed-settings deny/ask not tested.
A10 Hook decisions while the dialog is open (extra, key; 15 s delay only): a hook allow, deny or answer delivered after 15 s closes the open dialog and applies the decision; the PermissionRequest deny message reaches Claude (observed on screen).

Design consequences:

- Questions use the PermissionRequest `decision.updatedInput.answers` path, not PreToolUse (PreToolUse shows no dialog while waiting).
- PermissionRequest has no `tool_use_id`, so correlate the request with its PostToolUse by a hash of tool name and input.
- A hook that lost the race to a local answer is not signalled; the API detects a local answer through `cmd_end h` (D-17), and the hook must stop on its own timeout.
- PostToolUseFailure carries `tool_use_id`, so failures can be correlated like successes.
- Not covered: managed-settings deny/ask rules.

"question=go" means the PermissionRequest path, not PreToolUse.

Fixtures (scrubbed payload shapes): `hooks/fixtures/live/spike-permission-request.json`,
`spike-ask-question.json`, `spike-post-tool-use.json`.

VERDICT: permission=go question=go
