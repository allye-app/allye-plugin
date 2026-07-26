---
name: verification-loop
description: Bounded test-fix-test loop that proves a task or story actually works. Use when implementing a task, before reporting anything as done, or when a verification command fails and needs another pass.
version: "1.0"
category: methodology
---

# Verification Loop

<!-- adapted from mattpocock/skills diagnosing-bugs (MIT) — the tight-loop completion criterion and the loop-construction ladder -->

A task passes its own tests and still does not do what the story asked. Tasks all go green and the feature is broken. Both happen because "done" is asserted from reading code rather than observed from running it.

This skill defines the loop that observes it. A loop goes **red** on the failure, or it does not — and if it cannot go red, it is not verification, whatever else it is.

## 1. What counts as a loop

A verification command must satisfy all four:

- [ ] **red-capable** — it catches *this specific failure*. "Runs without erroring" is not the same thing. A command that passes whether or not the acceptance criterion is met verifies nothing.
- [ ] **deterministic** — same verdict every run. A command that depends on wall-clock time, network, or unseeded randomness reports noise.
- [ ] **fast** — seconds. A four-minute command is a build; you will not iterate on it, so it will not function as a loop.
- [ ] **agent-runnable** — runs to a verdict with no human clicking. If a human must act, see §4.

## 2. Building one

Take the first option on this ladder that works. Reach further down only when the ones above genuinely do not apply.

1. **An existing test, narrowed** — a single test case naming the criterion. Cheapest and usually correct.
2. **A new test at an existing seam** — prefer a seam the codebase already tests at over introducing one.
3. **A CLI invocation with an observable exit code** — a build, a typecheck, a lint, a migration.
4. **An HTTP call with an asserted response** — `curl` piped through `jq` to an assertion.
5. **A script that exercises the flow and prints a verdict** — when several of the above must combine.
6. **A human-verified procedure** — the escape hatch. See §4; it is not a loop, and declaring it changes how the story is dispatched.

## 3. Running one

The cycle is: run → read the actual output → fix → run again.

**Read the output, do not infer it.** A command whose result you predicted rather than read has told you nothing. This is the same evidence-before-assertions rule the `execution` skill applies before advancing a task, applied per iteration.

### The bound

<HARD-GATE>
Stop on whichever of these comes first:

1. **Three attempts on the same failure.**
2. **Two byte-identical outputs in a row.** Identical output is the previous attempt repeated, not a new one — this ends the loop immediately, before the third attempt.

On stopping, report `❌ blocked` carrying the command, its literal output, and what is missing. Never a summary of the output — the exact text. The reader decides what it means.
</HARD-GATE>

Three attempts is the budget for *one* failure, not for the task. A loop that fixes one criterion and then goes red on a different one starts a fresh budget: that is progress, and progress earns another three.

## 4. When no loop exists

Some work admits no command that is red-capable, deterministic, fast, and agent-runnable at once — visual layout, infrastructure provisioning, a one-off migration against production data. Forcing one produces a command that passes unconditionally, which is worse than none: it reports green while verifying nothing.

Such a task declares, in its description:

```
## Verification
verification: manual
{the exact procedure a human follows, and what they should observe}
```

That declaration carries a consequence beyond the task:

<HARD-GATE>
A task declaring `verification: manual` makes its whole story **HITL** — human in the loop. The Orchestrator does not dispatch a HITL story to an unattended runtime pane. A story whose every task has an automatable command is **AFK** and may be dispatched unattended.

The label is derived here, at planning time. It is never the Orchestrator's guess.
</HARD-GATE>

## 5. Two granularities

**Per task**, during implementation: run that task's command after each change until it is green. Cheap and local — this is what stops a trivial failure from consuming one of the two correction rounds the Orchestrator allows.

**Per story**, before reporting anything: run the command that exercises the story's own acceptance criteria end to end. Every task green does not mean the story works; nothing else checks this.

A red story loop is reported as such even when every task is green. "All tasks passed but the story does not work" is a finding, and a valuable one — it usually means the task breakdown missed an integration.

## 6. Relationship to TDD

Distinct disciplines, easily confused into one:

| | TDD | Verification loop |
|---|---|---|
| When | During implementation | After, before reporting |
| Unit | One behaviour | One acceptance criterion |
| Shape | Red → Green → Refactor | Run → read → fix → run |

Where TDD applies, the loop confirms the assembled whole. Where it does not — the "test after, but always test" branch of the detection heuristic in `tdd-workflow` — the loop is the only mechanism that observes the criterion at all, and that is where it earns the most.
