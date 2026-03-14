---
name: fenix-technical-development
description: Workflow for implementing tasks with TDD discipline, read-first rule, and wave execution. Use when the user wants to write code, implement a task, or develop features.
version: "1.0"
category: workflow
---

# Technical Development Workflow

This skill guides you through implementing a task with discipline: read existing code first, write tests, implement, refactor, and track progress in Fenix.

Use this when the user wants to: write code, implement a task, fix a bug, add functionality, or develop features.

---

## Workflow Overview

```
Get task → Search context → Move to in_progress → Read code → TDD (Red → Green → Refactor) → Verify → Move to done → Save memory
```

---

## Step 1: Get the Task and Context

Fetch the task you're about to implement:

```
work_get(key: "{TASK-KEY}")
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

**Pay special attention to locked decisions** — these were explicitly chosen by the user during the discussion phase and are non-negotiable.

---

## Step 2: Check Dependencies

If the task has dependencies (noted in its description), verify they're complete:

```
work_children(id: "{story uuid}")
```

Check that prerequisite tasks are in "done" status. If they're not done, either:
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
If you have read 5+ files without writing any code, STOP and ask yourself:

1. **Do I have enough context to start?** → If yes, start writing. Perfect understanding is not required.
2. **Am I blocked by missing information?** → If yes, tell the user what's blocking you.

Do not read endlessly. Reading is preparation, not implementation.
</HARD-GATE>

---

## Step 5: TDD — Test-Driven Development

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

If during implementation you encounter a choice not covered by the discussion phase:

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

## Step 7: Mark Task as Done

Once all acceptance criteria are met and tests pass:

```
work_status_done(id: "{task uuid}")
```

This sets the task to the "done" status and records `completed_at`.

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

After completing a task, check what's next:

```
work_children(id: "{story uuid}")
```

- If there are more tasks in the current wave → pick one
- If the current wave is done → move to the next wave
- If all tasks are done → transition to **Technical Review** (load `fenix-technical-review` skill)

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
- [ ] Task moved to done
- [ ] Implementation memory saved (if non-trivial)

---

## What Comes Next

When all tasks for the story are complete, transition to **Technical Review** — load the `fenix-technical-review` skill.
