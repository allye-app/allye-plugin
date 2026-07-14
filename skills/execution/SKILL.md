---
name: execution
description: Workflow for implementing tasks with TDD discipline, read-first rule, and wave execution. Use when the user wants to write code, implement a task, or develop features.
version: "1.1"
category: methodology
---

# Technical Development Workflow

This skill guides you through implementing a task with discipline: read existing code first, write tests, implement, refactor, and track progress in Allye.

Use this when the user wants to: write code, implement a task, fix a bug, add functionality, or develop features.

**Scope, if you arrived via a `story-execution` or `correction` handover (see `handover-protocol`):** read only the one story and its tasks named in the handover — nothing else. A `correction` handover carries only the failed findings, not the whole story again; fix exactly what it lists.

---

## Workflow Overview

```
Get task → Search context → Move to in_progress → Read code → TDD (Red → Green → Refactor) → Verify → Move to review → Save memory
```

---

## Step 1: Get the Task and Context

Fetch the task you're about to implement:

```
work_get(work_key: "{TASK-KEY}")
```

Read its description carefully — it should contain:
- What to implement
- Acceptance criteria
- Files likely involved
- Dependencies on other tasks
- Decisions from the discussion phase

### Search for relevant memories

```
memory_search(query: "{task key} context")
memory_search(query: "decision {story key}")
memory_search(query: "Technical Plan {story key}")
```

If session state or decision memories are found, optionally traverse the graph for richer context:
```
memory_graph(memory_id: "{id}", depth: 2)
```

**Pay special attention to locked decisions** — these were explicitly chosen by the user during the discussion phase and are non-negotiable.

---

## Step 2: Check Dependencies

If the task has dependencies (noted in its description), verify they're complete:

```
work_children(id: "{story uuid}")
```

Check that prerequisite tasks are in "review" or "done" status — either means their implementation is complete (tasks you finished earlier in this story sit at `review` until the Reviewer approves them). If a prerequisite hasn't reached at least `review`, either:
- Pick a different task from the same wave (if available)
- Inform the user that this task is blocked

### Wave Execution

If there are multiple independent tasks (same wave), they can be done in any order. Tasks with dependencies must follow the sequence defined in the technical plan.

---

## Step 3: Move Task to In Progress

Signal that work has started:

```
work_status_next(id: "{task uuid}")
```

---

## Step 4: Read First

<EXTREMELY_IMPORTANT>
Read existing code BEFORE writing any new code.
The task description lists files likely involved — read them all.
Understand the current state before changing it.

This is not optional. Writing code without reading the context leads to:
- Duplicating existing functionality
- Breaking existing patterns
- Inconsistent code style
- Missed constraints
</EXTREMELY_IMPORTANT>

### What to read

1. **Files listed in the task description** — The planning phase identified these
2. **Related test files** — Understand existing test patterns
3. **Shared utilities and helpers** — Don't reinvent what already exists
4. **Configuration files** — If the task involves config changes

### Analysis Paralysis Guard

<HARD-GATE>
This checkpoint applies to exploratory reads beyond what the task already named — reading every file the task itself points you to (see "What to read" above) is still mandatory, not capped by this count.

If you have read 5+ files *beyond those named/implied by the task* without writing any code, STOP and ask yourself:

1. **Do I have enough context to start?** → If yes, start writing. Perfect understanding is not required.
2. **Am I blocked by missing information?** → If yes, tell the user what's blocking you.

Do not read endlessly in search of additional context. Reading is preparation, not implementation.
</HARD-GATE>

---

## Step 5: TDD — Test-Driven Development

<!-- full discipline lives in the tdd-workflow skill, aligned with superpowers:test-driven-development (MIT) -->

### Should I use TDD for this task?

Apply the **TDD Detection Heuristic**:

> Can I write `expect(fn(input)).toBe(output)` before writing `fn`?

- **Yes** → TDD is mandatory. Follow Red → Green → Refactor.
- **No** (UI, infrastructure, integration, configuration) → Write tests after implementation, but always write tests.

### Red Phase — Write the Failing Test

Write a test that describes the expected behavior:

```
// Test describes WHAT, not HOW
test("should return user by email", () => {
  const user = getUserByEmail("test@example.com");
  expect(user.name).toBe("Test User");
});
```

Run the test. Confirm it **fails**. If it passes, either:
- The functionality already exists (check before implementing)
- The test is wrong (it's not testing what you think)

### Green Phase — Make It Pass

Write the **minimum code** to make the test pass. No more, no less.

Rules:
- Don't add features the test doesn't require
- Don't optimize prematurely
- Don't handle edge cases not covered by tests (write more tests first)

Run the test. Confirm it **passes**.

### Refactor Phase — Clean Up

With green tests as your safety net, improve the code:

- Remove duplication
- Improve naming
- Simplify logic
- Extract functions if needed

Run tests after every change. If a test fails, you broke something — fix it before continuing.

### Repeat

Write the next test for the next behavior. Continue the cycle until all acceptance criteria are met.

---

## Step 6: Checkpoints

### `human-verify` Checkpoint

After completing the task, if it has **visual or behavioral impact** that the user should see:

> "I've completed {task description}. Here's what changed:
> - {change 1}
> - {change 2}
>
> Would you like to verify this before I move on?"

### `decision` Checkpoint

**If uncertain which path to take, STOP and ask — never proceed on assumption.** If during implementation you encounter a choice not covered by the discussion phase:

> "I found a decision point not covered in planning:
> {describe the options}
>
> Which approach do you prefer?"

Save the decision as a memory once resolved.

### Automation-First Rule

<HARD-GATE>
If you CAN automate something, you MUST automate it.
Only ask for human intervention when it's genuinely impossible to proceed without it.

Examples of things to automate (don't ask):
- Running tests
- Formatting code
- Installing dependencies
- Creating files and directories
- Applying migrations

Examples of things that need human action:
- Approving a deployment to production
- Providing API keys or credentials
- Verifying visual design matches expectations
- Confirming business logic interpretation
</HARD-GATE>

---

## Step 7: Move Task to Review

<!-- adapted from superpowers:verification-before-completion (MIT) — evidence before assertions -->
**Evidence before assertions.** Don't advance a task because it looks right — run the tests, read the actual output, and confirm each acceptance criterion against that output before proceeding. "Should work" is not the same as "ran and passed."

Once all acceptance criteria are verifiably met and tests pass:

```
work_status_next(id: "{task uuid}")
```

This advances the task forward to the "review" status. **Do NOT call `work_status_done` here** — passing its own tests makes a task ready for review, not done. "Done" only happens after the Reviewer returns ✅, and that final move (`review` → `done`) is the Orchestrator's, not yours (see the `orchestrator` skill §7).

---

## Step 8: Save Implementation Memory

Save context that would be useful for future tasks or sessions:

```
memory_save(
  title: "Implementation — {TASK-KEY} {short description}",
  content: "## What was done\n{summary of changes}\n\n## Key decisions during implementation\n{any new decisions made}\n\n## Files changed\n- {file 1}\n- {file 2}\n\n## Gotchas\n{anything surprising or non-obvious encountered}\n\n## Tests\n{what was tested, any notable test patterns}",
  tags: ["development", "implementation", "{story-key}", "{task-key}"],
  work_item_id: "{task uuid}",
  sprint_id: "{sprint uuid if applicable}"
)
```

Only save if there's genuinely useful context. Don't save trivial implementations — the code is its own documentation.

---

## Step 9: Pick Next Task

After completing a task, pick the next one from the **handover's own wave-ordered task list** — not from a live API call. The `story-execution` handover already contains every task across every wave for the whole story, so it's the authoritative scope; going back to the API for *new* tasks would risk pulling in tasks added to the story after the handover was dispatched, which are out of scope (see line ~14).

- If there are more tasks in the current wave (per the handover's list) → pick one
- If the current wave is done → move to the next wave (per the handover's list)
- If every task in the story has reached `review` (implementation complete, awaiting Reviewer) → emit an **`execution-report`** handover (see the `handover-protocol` skill) back to the Orchestrator

Use `work_children(id: "{story uuid}")` only to **verify/check the status** of tasks already in the handover's list (e.g. confirming a dependency reached `review`) — never to discover new tasks to work on. If `work_children` reveals a task under this story that is **not** in the handover's task list, do not execute it — it wasn't in scope when the handover was dispatched. Instead, note it as an open question ("Open questions") in the `execution-report` handover so the Orchestrator can decide whether to bring it into scope.

---

## Workflow Checklist

For each task, verify:

- [ ] Task was read and understood (description, acceptance criteria, dependencies)
- [ ] Relevant memories and decisions were searched
- [ ] Dependencies are complete
- [ ] Task moved to in_progress
- [ ] Existing code was read before writing new code
- [ ] TDD cycle completed (or tests written after for non-TDD-suitable tasks)
- [ ] All acceptance criteria are met
- [ ] Tests pass
- [ ] Task moved to review (never directly to done — that's the Orchestrator's move after Reviewer ✅)
- [ ] Implementation memory saved (if non-trivial)

---

## What Comes Next

Emit the `execution-report` handover: files changed, tests added, status per acceptance criterion (not a blanket "done"), any new decisions made along the way, and any open questions. The Orchestrator decides from there whether to dispatch Reviewer or, if this is a `correction` round, loop back with more specific findings.
