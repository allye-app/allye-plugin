# Execution Retrospective

**Status:** reopened 2026-07-26 after Plans 06–09 — closing at thirteen was premature. Seventeen findings.
**Scope:** what actually broke, surprised, or worked better than expected while building and running the nine plans from `2026-07-26-agent-runtime-and-verification-design.md`.

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

**RESOLVED 2026-07-26 by experiment. The constraint holds, and for a worse reason than anyone had written down.**

A throwaway pane, `--cwd` at `/home/bfernandes/dev/allye/.worktrees/f7-probe` — a worktree sitting **inside** the plugin-enabled directory — on Claude Code 2.1.220:

| Probe | Result |
|---|---|
| `Skill("allye:tools-quickref")` | `Unknown skill: allye:tools-quickref` |
| `mcp__plugin_allye_allye__*` tools | absent from the tool list *and* the deferred-tool index |
| `allye:*` in the available-skills listing | absent |
| `using-allye` in SessionStart context | absent |
| `Agent runtime:` line | absent |

**The plugin is not failing on first use — it is entirely absent from the session.** Being a descendant of the enabled directory buys nothing: Claude Code resolves the project root through git, and a worktree is its own git root, so the ancestor's `.claude/` is never consulted. That explains a constraint that had been recorded as a symptom without a mechanism.

**The finding nobody was looking for:** `hooks/session-start.sh` is a plugin hook, so it never fires either. The runtime-detection line from spec §5.1 is not merely unread in a worktree-cwd session — **the whole mechanism does not exist there.** Any future attempt to relax this rule has to verify the hook fires, not just that a skill loads. Checking only the skill would have produced a confident false positive.

**Also settled:** v2.1.200's "project-scope plugins shared across worktrees" applies to **Claude-managed** worktrees under `.claude/worktrees/`, not to anything `git worktree add` produces. That was the hypothesis recorded in the spec; it is now evidence.

**Cost/benefit:** twenty minutes, one throwaway pane, torn down completely. The rule it validates was already being followed — what changed is that it is now permanent and explained, instead of provisional and superstitious. A rule nobody can justify is a rule someone eventually removes.

**One honest limit of the experiment:** it tested a worktree *inside* the enabled directory, which is the configuration this design actually uses. It says nothing about a worktree elsewhere on disk — but since the inside case already fails, the outside case cannot do better.

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

## F12 — Recording a finding and applying it are different acts, and the second does not happen on its own

**Observed:** this document recorded five fixes phrased as *"Fix (Plan 04, Task 1, `references/herdr.md` §spawn)"* — F1, F2, F4, F5, F10. Every one was written carefully, with the exact file and section. **None had been applied to Plan 04.** They were caught only because I re-read the plan before dispatching it, for an unrelated reason.

**What would have shipped:** the runtime contract, permanently, with `spawn` inspecting the shell instead of waiting for it; `collect` justified by an alternate-screen failure that had already been shown not to reproduce; no section on answering a blocked agent; and `wait` with no notification bridge — the very lesson that came from Bruno asking why he had not been told a pane finished.

**Why it happens:** writing the finding feels like completing it. The document fills up, each entry names its own remedy, and the sense of having handled it is indistinguishable from having handled it. Nothing in the loop closes.

**Fix:** a retrospective needs an **application gate**, not just an author. Two mechanisms, both cheap:

1. Every finding whose fix targets a plan is not closed until that plan is edited. Grep the retrospective for `Fix (Plan` before dispatching any plan, and confirm each one naming that plan has landed.
2. Plan 05 carries this as an explicit task — see §16.7 of the spec — rather than trusting it to diligence.

**The general shape, which is the part worth keeping:** any document that records "someone should do X" and is not itself checked before X's deadline will accumulate undone Xs at exactly the rate it accumulates insight. The failure is structural, not personal — the same trap the `orchestrator`'s two-correction rule and the `verification-loop`'s bound both exist to close elsewhere.

---

## F13 — A skill referenced by name but not seeded is a dangling reference, not a wrong count

**Observed:** `plan04` flagged, as an out-of-scope note, that it had updated README's "workflow skills published in the Allye marketplace" from 13 to 15 **on the assumption** that the two new skills would be published — and said plainly it was an assumption. `seed/seed-skills.json` still held 13.

**Why it mattered more than a count:** skills reference each other by name. `execution` says *"see the `verification-loop` skill"*; `orchestrator` says *"load the `agent-runtime` skill"*. A user whose Allye database lacks them does not get a slightly wrong number — they get a reference that fails at the exact moment the skill is needed, in the middle of execution.

**Fix, applied:** both seeded. `verification-loop` for all five agents; `agent-runtime` claude-only, because the session hook that detects a runtime and makes the skill reachable exists only there. `setup` remains deliberately unseeded — it is Claude Code's local install-time skill.

**What actually surfaced it:** the briefing's closing instruction — *"anything wrong but out of scope: report it, do not fix it."* The executor had no mandate to touch the seed and correctly did not. Without that line it would either have silently fixed it, hiding a design question about what ships to users, or said nothing at all.

**Generalization:** a new skill is not complete when its file exists. It is complete when everything that names it can resolve it — the seed manifest, the routing table, and the counts in the documentation. Plan 05 should carry that as a checklist item, since two of the three were missed here.

---

## Process observations

Not defects — things about *how* this was built that are worth keeping or dropping.

- **Section-by-section design approval worked.** Four sections, each approved before the next was written, and no section was rewritten afterwards. The alternative — one large design dump — would have surfaced the pane-vs-subagent decision far too late, and it reshaped three sections.

- **The HITL/AFK derivation was not in the spec until it was discovered mid-conversation.** It emerged from asking what happens to a task with no automatable verification. The best mechanism in the design came from following a loose end rather than from planning.

- **Delegating the doctrine rewrite to a parallel pane paid for itself** — 7 skills, −242 lines, two honestly-reported doctrine conflicts, while the design conversation continued. It also produced both defects recorded in spec §12, which no one was looking for.

- **The false alarm cost real time, twice.** `git diff spec..feat` showed files as deleted because they were added on the target branch after the merge base — once for Plans 02–04, once for this retrospective. Not a defect either time, but a reminder to check `--name-status` and the merge base before raising an alarm about missing work.

- **Defects moved from being found late to being found early, and not by luck.**

  | Plan | Defects found by the executor, mid-run | Defects found by pre-flight, before dispatch |
  |---|---|---|
  | 01 | 1 | — (no pre-flight yet) |
  | 02 | 1 | 0 |
  | 03 | 0 | 3 |
  | 04 | 0 | 2 assertion defects + 5 unapplied findings |

  Plans 03 and 04 ran without stopping because their defects had already been removed, not because they were better written. The pre-flight — reading each assertion and asking *what would have to be true for this to pass without the change having happened correctly* — is the cheapest thing in this whole session, at roughly ten minutes per plan.

- **The briefing template did more work than any skill.** Three separate behaviours came from paragraphs written by hand into the dispatch briefings, not from any skill or handover template: stopping on a contradictory step rather than improvising; reporting out-of-scope findings without fixing them (which surfaced F13, the two defects in spec §12, and the `delivery` scope error); and refusing to say "no conflicts" to be agreeable, which produced the two honest doctrine conflicts in the first workstream. **All three belong in `references/story-execution.md`, and only the first is currently scoped for Plan 05.** The other two are the strongest candidates for whatever comes after it.

- **Every executor's most useful output was the thing it was told not to fix.** Four dispatches, four out-of-scope sections, and between them: two API defects, one architecture-doc error, and one dangling skill reference. None was in any plan. The instruction that produced them costs one sentence.

---

## The application gate

This document records fixes. Recording is not applying, and the two feel identical while
writing — F12 exists because five fixes sat here fully specified and entirely undone.

**Before dispatching any plan:**

```bash
grep -n 'Fix (Plan N' docs/allye/notes/*-retrospective.md
```

Every result naming that plan is confirmed landed, or the plan is not ready.

**Before closing any retrospective:** every `Fix (...)` is either applied, or restated as an
open item with a named owner and destination. A finding with no destination is an
observation, and observations belong under Process, not under a numbered finding.

## A new skill is not done when its file exists

It is done when everything that names it can resolve it:

- [ ] `skills/<name>/SKILL.md` exists with all four frontmatter keys
- [ ] Added to `seed/seed-skills.json`, with `supported_agents` reflecting where it is
      actually reachable — not every skill is reachable on every platform
- [ ] Referenced from whatever loads it, by the exact name the seed uses
- [ ] Counts updated in `README.md` and `CLAUDE.md`
- [ ] If it is deliberately **not** seeded, that is stated where the count is, the way
      `setup` is

Two of these five were missed for `verification-loop` and `agent-runtime`, and the failure
mode was not a wrong number — it was a skill referenced by name that a user's database could
not resolve at the moment it was needed.

---

# Second half — Plans 06 to 09

Closing this document at thirteen findings was itself a finding: four more plans produced four more, and one of them is the most reusable thing in here.

## F14 — Rewriting a section leaves its neighbours contradicting it, and pre-flight does not catch that

**Observed across three consecutive plans**, every one of which had been pre-flighted:

| Plan | What contradicted what |
|---|---|
| 06 | `board-progression`'s Common Mistakes table still named a status as a rule — violating the multi-tenancy gate the same plan introduced two sections above. And `orchestrator` §6's decision table still said to move an approved task "the rest of the way to `done`", which the rewritten §7 no longer does. |
| 08 | Steps 1–3 still prompted for a PAT before the verb dispatch the plan had just added, so `status` aborted under closed stdin. |
| 09 | `using-allye` still described `/save` as "a 3-step process" after `memory-protocol` gained a fourth. |

**Why pre-flight misses it.** The pre-flight from F11 reads each *assertion* and asks what could make it pass wrongly. That is a good question and it caught real defects. But it only looks at what the plan **names**. A section the plan never mentions cannot fail an assertion the plan never wrote.

**The distinct class:** an edit is not scoped to the lines it changes. It is scoped to **everything that describes those lines** — a count elsewhere, a summary in another file, a table restating the rule. Plan 09's case is the sharpest: `using-allye` is injected into *every session*, so the stale sentence was the most-read wrong thing in the plugin, sitting in a file the plan had no reason to open.

**Fix — a second pre-flight question, asked of the change rather than the assertions:** *what else in this repository describes what I am about to change?* Grep for the rule's distinctive phrasing, the number, the old name — across all of `skills/`, `agents/`, `README.md`, and `CLAUDE.md`, not only the files in the plan's Files list.

All three were caught by executors reporting out of scope. That worked, but it is the expensive path: it costs a full execution and a merge-time fix.

---

## F15 — A verb unusable in exactly the case it exists for

**Observed:** Plan 08 added `install` / `uninstall` / `status`. Steps 1–3, which prompt for a PAT, ran unconditionally before the dispatch — so `./install.sh status`, the verb most likely to be called from a script or CI, aborted before printing anything.

**The root cause was one level down.** Under `set -e`, `read` returns non-zero on EOF, so *any* non-interactive invocation died at that line. It predates the plan — the old `install.sh` had the same `read` in the same place — but it had never mattered, because the old script had no verb anyone would want to call unattended.

**The general shape:** adding an interface can turn a dormant defect into a live one without touching the defective code. The `read` did not change; what changed is that something now needs to run past it.

**Fix, applied:** the prompt is TTY-conditional, and Steps 1–3 are guarded behind the `install` verb.

---

## F16 — An uninstall that restores content but not order

**Observed:** Plan 09's `uninstall hermes` genuinely reverses what `install` turned off — the flags return to `true`, the removed toolsets return to their lists. But restored list entries are **appended at the end** rather than reinserted at their original position.

**Reported by the executor unprompted**, as a caveat to an otherwise clean "yes it reverses". Semantically identical, and for a toolset list order does not appear to matter — but "does not appear to" is doing work in that sentence, and nobody has checked whether any consumer is order-sensitive.

**Left as-is deliberately.** Recording it is the point: a future ordering bug in this area has its explanation already written down.

---

## F17 — The same trap caught two consecutive executors

**Observed:** Plan 08's and Plan 09's executors both ran a compound command containing `cd <worktree>`, leaving their shell's cwd inside the worktree. Both caught it on the next turn, returned, and reported it unprompted. Neither caused damage.

**Two for two is not carelessness.** The brief warned about it explicitly both times, and both executors were otherwise careful enough to self-report. The cause is a property of the tool: **cwd persists across Bash calls**, so a single compound command silently changes the meaning of everything after it — and the failure is invisible until a relative path resolves somewhere unexpected.

**A warning is the wrong instrument for this.** "Do not `cd`" asks someone to remember a rule at the moment they are thinking about something else. The instruction that would actually work names the mechanism and the alternative: *never put `cd` in a compound command; use absolute paths and `git -C <path>`.*

**Fix:** that phrasing belongs in `references/story-execution.md`, alongside the three reporting behaviours Plan 05 moved there — for the same reason. It is currently living in hand-written briefings, which is where things go to be forgotten.

---

## Second-half process observations

- **Pre-flight kept earning its ten minutes.** Plans 06–09 hit zero *assertion* defects mid-run, against two in Plans 01–02 before pre-flight existed. What it does not cover is F14's class, which is a different question asked of a different thing.

- **Every out-of-scope report was worth more than the task that produced it.** Across nine plans: two API defects, an architecture-doc error, a dangling skill reference, a broken `status` verb, and three cross-file contradictions. **None was in any plan.** The instruction that produces them is one sentence, and Plan 05 moved it into the template so it stops depending on whoever writes the briefing.

- **Two designs were corrected by the human asking a question, not by review.** "Pane instead of subagent" reshaped three sections and forced the discovery that Allye is the result bus. "The visualization won't work, will it?" exposed that the Hermes kanban is an orchestration engine and not a board — a mischaracterisation that would otherwise have shipped inside a plan telling someone to disable it as though it were a table.

- **Nine plans, zero exercised.** Everything here was validated by grep assertion and sandboxed installs. No story has been planned, executed, verified, reviewed, and landed using the flow these plans built. That is the largest untested claim in the repository, and it is not a finding — it is the next thing to do.
