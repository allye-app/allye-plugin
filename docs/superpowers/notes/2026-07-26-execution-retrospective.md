# Execution Retrospective — running log

**Status:** open, appended as things happen. Closes as Plan 05 when Plans 02–04 are done.
**Scope:** what actually broke, surprised, or worked better than expected while building and running the four plans from `2026-07-26-agent-runtime-and-verification-design.md`.

Written during execution rather than reconstructed afterwards, because the detail that makes a finding actionable is the first thing lost. "The spawn had a hiccup" is not fixable; `agent_pane_busy` because `fastfetch` held the foreground is.

Each finding records what happened, what it costs, and what would fix it. A finding with no proposed change is still worth recording — several here exist to correct a claim in the spec.

---

## F1 — `spawn` must wait for the shell, not merely inspect it

**Observed:** `herdr agent start` failed with `agent_pane_busy` on the first attempt for `plan02`. The pane had been created a second earlier, and the shell's startup was still running `fastfetch` in the foreground. Retrying after a poll for a bare shell succeeded immediately.

**Why it happened:** `references/herdr.md` §spawn (Plan 04, Task 1) shows `herdr pane process-info` as an informative step — "confirm the new pane holds a bare shell" — with no loop and no gate. Any shell with a startup banner, a version manager, or a greeting will lose this race.

**Cost:** one failed dispatch. Cheap here because a human was watching; in an unattended parallel dispatch of three stories it would surface as one story silently never starting.

**Fix (Plan 04, Task 1, `references/herdr.md` §spawn):** replace the informative check with a bounded wait.

```bash
for _ in $(seq 1 10); do
  FG=$(herdr pane process-info --pane "$PANE" | jq -r '.result.process_info.foreground_processes[0].name')
  case "$FG" in zsh|bash|sh|fish) break;; esac
  sleep 3
done
```

Bounded, not infinite: a pane still busy after 30 seconds is a problem to report, not to keep waiting on.

---

## F2 — The unsubmitted-prompt gotcha is the norm, not an edge case

**Observed:** dispatching to an idle agent left the text in the input box without submitting. **Twice out of two dispatches** (`plan01`, `plan02`). Both needed `agent send-keys <name> enter` before the status moved to `working`.

**Why it matters:** the spec (§6.3) and the reference already require confirming the state and submitting explicitly. This validates that rule as load-bearing — but both documents phrase it as a contingency ("if it has not moved to a working state"), which reads as an unlikely branch. It is the expected path.

**Fix (spec §6.3 and `references/herdr.md` §dispatch):** reword from conditional to sequential. Prompting an idle agent is a two-step operation — send, then submit — and the state read is how you know the second step landed. Same commands, honest framing.

---

## F3 — Grep assertions must match syntactic form, not substring

**Observed:** Plan 01, Task 2 contained a genuine contradiction. Step 3 added a gotcha entry to `tools-quickref` explaining that `work_item_id` and `sprint_id` are not accepted parameters — prose that necessarily contains both literal strings. Step 4 then asserted those strings appear nowhere. Both could not pass.

The executing agent found it, explained precisely why the two steps were incompatible, offered three options, and picked none. That was correct, and it is the behaviour the briefing asked for.

**The root cause was not the gotcha.** All three offered options treated the symptom — exclude the line, or reword the prose. The real error was the assertion's granularity: the defect is the parameter *inside a call*, and the assertion searched for the *word anywhere in the file*. Documentation of a fix will always look like the defect to a substring grep.

**Fix, applied:** assert on the parameter-assignment form, `^[[:space:]]*(work_item_id|sprint_id):`, which matches a call site and never prose in backticks. No exclusion needed, and the assertion got *stronger* rather than weaker.

**Generalization for Plans 02–04:** every grep assertion in a plan is a claim about syntax. Before executing a plan, run its Step 1 assertions against the real files — a Step 1 that does not return what the plan predicts means the plan was written against a tree that has since moved. This pre-flight caught nothing for Plan 02, which is the outcome you want and still worth the two minutes.

---

## F4 — Correcting the spec: reading results off the terminal worked

**Observed:** spec §6.5 argues the result channel must be Allye because full-screen agents render on the terminal's alternate screen, whose rows never reach scrollback, so a long report cannot be read back. **This did not happen.** `herdr agent read <name> --source recent-unwrapped --lines 200` returned both agents' full final reports, cleanly, including a 45-line structured report from `plan01`.

**What this means:** the justification in §6.5 is overstated for Claude Code as configured here. Either it is not using the alternate screen, or `recent-unwrapped` recovers more than the warning implies. The warning is real in Herdr's own documentation; it simply did not bite in this configuration.

**What does *not* change:** the design decision. Allye stays the result channel, and the reasons that survive are better than the one that did not hold:

- A structured artifact in Allye is machine-readable; a terminal transcript is prose to be parsed.
- The Orchestrator can read a result from a pane it did not create, and after the pane is closed.
- It works identically for every runtime, including ones with no output-read primitive at all — which is most of the category.

**Fix (spec §6.5):** demote the alternate-screen argument from load-bearing to a caveat, and lead with the three reasons above. A design justified by a failure mode that does not reproduce is a design one experiment away from being abandoned for the wrong reason.

**Also (`references/herdr.md` §collect):** `herdr agent read` returns **plain text, not JSON**. My first attempt piped it to `jq` and failed. Document the output format.

---

## F5 — Answering a blocked agent: dismiss the menu first

**Observed:** `plan01` went `blocked` showing an interactive multiple-choice menu, and none of its four options was the right answer. Sending a prompt directly into an open select menu risks the text being interpreted as menu navigation. `herdr agent send-keys <name> esc` dismissed it cleanly, after which a normal `agent prompt` was accepted.

**Fix (`references/herdr.md`, new §"answering a blocked agent"):** read the pane first to see what is actually being asked; if a selection UI is open and the answer is not one of its options, dismiss with `esc` before prompting. Then follow the normal dispatch sequence, including the submit confirmation from F2.

---

## F6 — "Stop and report a wrong plan" belongs in the briefing template

**Observed:** `plan01`'s executor stopped on a contradictory step instead of improvising, which is what made F3 recoverable. That behaviour came from one paragraph in the hand-written briefing, not from any skill or template.

**Why it matters:** the same instruction is missing from `references/story-execution.md`, so a story dispatched through the real handover flow has no equivalent. The handover currently says "if anything is unclear, STOP and ask" — which covers *ambiguity*, not *contradiction*. A step that is perfectly clear and impossible is a different failure, and the more dangerous one, because an agent can satisfy it by quietly weakening an assertion.

**Fix (Plan 04, Task 4, `references/story-execution.md`):** add to the closing reminder — a task whose acceptance criteria contradict each other, or contradict another task, is reported as `❌ blocked` with both halves quoted. Never resolved by choosing one.

---

## F7 — `--cwd` at the plugin root: still unverified, still being paid for

**Observed:** both dispatches used the conservative rule from spec §13 — pane cwd at the plugin-enabled root, absolute worktree paths in the briefing. It works, and it costs a `<HARD-GATE>` paragraph in every briefing explaining why the cwd is not where the code is.

**Still unknown:** whether Claude Code 2.1.220's project-scope plugin sharing across worktrees removes the need. Two dispatches gave no evidence either way, because neither tested the other configuration.

**Fix:** a five-minute experiment, worth running before Plan 04 since Plan 04 is what codifies the rule. Spawn a pane with `--cwd` inside a worktree, ask the agent to invoke `Skill("allye:tools-quickref")`, and observe. If it resolves, the constraint is stale and every briefing gets shorter.

---

## F8 — Counts in assertions must be derived, never chosen defensively

**Observed:** Plan 02, Task 3 Step 7 asserted that `verification-loop` appears **at least twice** in `skills/execution/SKILL.md`. The plan's own verbatim insertions produce exactly **one**. The executor inserted the text correctly, hit the assertion, and stopped.

**Why the number was wrong:** I picked "2" as a safety margin, not by counting what the prescribed text produces. A count nobody computed will eventually disagree with the text it is meant to check.

**Why the offered fixes were all wrong:** the executor proposed adding a second reference, and it would have been factually accurate — the story loop does share the task loop's bound. But the existing phrasing, "under the same bound as the task loop," is *better writing* than repeating the skill name in an adjacent paragraph. Padding prose to satisfy an assertion inverts which one serves the other, and here it would have introduced exactly the duplication the doctrine this plan applies names as a failure mode.

**The deeper error, shared with F3:** the assertion used a skill name as a **proxy** for "the edit happened." It should check the distinctive text each insertion actually introduces — `Verification Phase` for the task loop, `story loop` for the story loop. Then it proves the thing it claims to prove, and no count needs guessing.

**Fix, applied:** Step 7 now asserts exact counts derived from the prescribed text, and checks insertion-specific phrases rather than a reference tally.

**Generalization:** F3 and F8 are the same mistake in two costumes — an assertion checking something *adjacent* to what it means. Before executing a plan, read each assertion and ask what would have to be true for it to pass *without* the change having happened correctly. If there is such a case, the assertion is checking a proxy.

---

## F9 — The plugin has no plan-then-validate step before implementation

**Observed:** raised by Bruno rather than by an execution failure. `skills/execution/SKILL.md` goes from Step 4 (read the existing code) directly to Step 5 (TDD, write). Nothing between them produces a statement of *how* the work will be done, and nothing checks it before code exists.

**Why it matters:** the Executor's halt-and-report contract fires when a task turns out underspecified — but it fires **mid-implementation**, with code already written. The Orchestrator's pre-flight completeness check exists to catch this earlier and its own text concedes it catches "the obvious cases, not all."

**Also the honest origin:** building this spec needed `brainstorming` and `writing-plans` from an external suite, because Allye has no counterpart. The plugin has never had a runtime dependency on that suite, but its own development leaned on it, which is its own kind of gap.

**Fix:** recorded as spec §16 and scoped to Plan 05 — a plan-then-validate step between reading and writing, with three mechanical checks that always run and approach review bound to the AFK/HITL label. Sequenced after Plans 03 and 04 because the label those plans produce and consume is what the validation binds to.

---

## F10 — The runtime's lifecycle must be bridged into the orchestrator's own notification channel

**Observed:** Bruno asked why I had not been notified that `plan02` finished. I had not, and the reason is that I never asked to be — I had been polling `herdr agent get` by hand after every few actions.

**Why:** a runtime pane is a separate process outside the orchestrating session's harness. Nothing wires its completion back. The harness notifies about background shell commands and about its own dispatched subagents; a pane is neither.

**The mechanism existed and the spec already prescribed it.** §6.4 says of `agent wait`: *"Run it in the background. Do not poll."* Running `herdr agent wait <name> --timeout N` **as a background shell command** is the bridge — when the agent settles, the wait exits, and the harness's own completion notification fires. I wrote the rule and then polled anyway for two full plan executions.

**Cost:** none to correctness, real to attention. Every check was a deliberate action taken at an arbitrary moment, which means the orchestrator is either interrupting itself to poll or leaving a finished agent idle.

**Fix (Plan 04, Task 2, `orchestrator` §4.2):** dispatching to a pane is not complete until the wait is running in the background. Make it the closing step of dispatch rather than a separate thing the Orchestrator remembers to do — a dispatch without a wait registered is a story nobody is listening for. Applied from `plan03` onward.

**The generalization worth keeping:** `wait` in the contract (§6.4) is not "how the orchestrator blocks." It is "how the runtime's lifecycle becomes an event in whatever system the orchestrator actually lives in." Any future runtime satisfies `wait` only if it can be bridged that way.

---

## F11 — Pre-flighting a plan's assertions found three defects before execution

**Observed:** before dispatching Plan 03, I read its assertions against the live tree instead of trusting them. Three were wrong, and none would have been caught by the plan's own steps:

1. **Tasks 1 and 2** counted how often the sibling agent's name appears as a proxy for "the agent was written correctly" — F8's mistake, repeated in a plan written before F8 was recorded.
2. **Task 3 Step 1's** grep missed `README.md` and `handover-protocol`, which write "Reviewer" capitalized and unbackticked, **and** matched the July spec and plans. The plan then instructed that every match be updated — which would have rewritten historical records to match later reality.
3. **Task 4** replaced text containing `<!-- opencode-exclude -->` markers without preserving them. The orchestrator carries twelve. Dropping one raises no error; it silently leaks Claude-Code-only instructions into the OpenCode-generated prompt, which is the defect commit `394dc20` already fixed once.

**What made this work:** asking of each assertion, *what would have to be true for this to pass without the change having happened correctly?* Every one of the three had such a case.

**Cost of the pre-flight:** roughly ten minutes. Cost of the third defect reaching production: a cross-platform bug that no assertion in the plan would ever have caught, because none of them looked at the markers.

**Fix:** make the pre-flight a step, not a habit — before dispatching any plan, run its Step 1 assertions against the real tree and read every other assertion for proxy-checking. Both `plan01` and `plan02` proved an executor will catch a *contradiction*; neither would have caught an assertion that passes for the wrong reason.

---

## Process observations

Not defects — things about *how* this was built that are worth keeping or dropping.

- **Section-by-section design approval worked.** Four sections, each approved before the next was written, and no section was rewritten afterwards. The alternative — one large design dump — would have surfaced the pane-vs-subagent decision far too late, and it reshaped three sections.

- **The HITL/AFK derivation was not in the spec until it was discovered mid-conversation.** It emerged from asking what happens to a task with no automatable verification. The best mechanism in the design came from following a loose end rather than from planning.

- **Delegating the doctrine rewrite to a parallel pane paid for itself** — 7 skills, −242 lines, two honestly-reported doctrine conflicts, while the design conversation continued. It also produced both defects recorded in spec §12, which no one was looking for.

- **The false alarm cost real time.** `git diff spec..feat` showed Plans 02–04 as deleted, because they were added on the target branch after the merge base. Not a defect, but a reminder to check `--name-status` and the merge base before raising an alarm about missing work.
