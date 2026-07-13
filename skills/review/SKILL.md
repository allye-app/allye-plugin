---
name: review
description: Workflow for reviewing implemented code with decision context from planning. Use when the user wants to review code quality, validate implementation, or check tasks before delivery.
version: "1.0"
category: methodology
---

# Technical Review Workflow

This skill guides you through reviewing implemented code with full context — the decisions made during planning, the acceptance criteria defined for each task, and the architectural constraints captured in memories.

Use this when the user wants to: review code, check implementation quality, validate against requirements, or prepare for delivery.

---

## Workflow Overview

```
Get story context → Load decisions → Review each task → Document findings → Approve or request changes
```

---

## Step 1: Gather Context

### Get the story and its tasks

```
work_get(work_key: "{STORY-KEY}")
work_children(id: "{story uuid}")
```

### Load planning decisions

```
memory_search(query: "Technical Plan {story key}")
memory_search(query: "decision {story key}")
memory_search(query: "implementation {story key}")
```

This gives you:
- The original plan and wave structure
- Locked decisions (non-negotiable choices by the user)
- Agent-discretion decisions (choices the agent made)
- Implementation notes from the development phase

---

## Step 2: Review Each Task

For each completed task, verify:

### 2.1 Acceptance Criteria

Check the task description's acceptance criteria one by one:

- [ ] Is each criterion met?
- [ ] Can each criterion be verified (test, endpoint, UI)?
- [ ] Are there criteria that were silently skipped?

### 2.2 Code Quality

Review the actual code changes against these standards:

| Check | What to look for |
|-------|-----------------|
| **Correctness** | Does it do what the acceptance criteria say? |
| **Consistency** | Does it follow existing patterns in the codebase? |
| **Simplicity** | Is it the simplest solution that works? No over-engineering? |
| **Test coverage** | Are there tests? Do they test behavior, not implementation details? |
| **Security** | No injection vulnerabilities, no exposed secrets, proper auth checks? |
| **Error handling** | Are failure cases handled? Are errors informative? |
| **Naming** | Are variables, functions, and files named clearly? |

### 2.3 Decision Compliance

Check that the implementation respects the decisions from the planning phase:

- **Locked decisions** — Were they followed exactly? Any deviation is a defect.
- **Agent-discretion decisions** — Were they reasonable? Is the rationale documented?

### 2.4 Test Quality

Review the tests themselves:

- Do tests describe behavior (what), not implementation (how)?
- Are edge cases covered?
- Can tests break for the right reasons (behavior changed) and not for the wrong ones (refactoring)?
- Are there tests that test nothing meaningful (e.g., testing that a mock returns what you told it to)?

---

## Step 3: Document Findings

### If everything looks good

```
memory_save(
  title: "Review — {STORY-KEY} approved",
  content: "## Review Summary\nAll tasks reviewed and approved.\n\n## Tasks Reviewed\n- {TASK-1}: ✅ Criteria met, tests pass\n- {TASK-2}: ✅ Criteria met, tests pass\n\n## Notes\n{any observations for future reference}",
  tags: ["review", "approved", "{story-key}"],
  work_item_id: "{story uuid}"
)
```

### If changes are needed

Present findings to the user clearly:

```markdown
## Review Findings for {STORY-KEY}

### TASK-1: {title} ✅
All criteria met. No issues.

### TASK-2: {title} ⚠️
- **Issue:** {description of the problem}
- **Severity:** {critical | minor | suggestion}
- **Suggestion:** {how to fix it}

### TASK-3: {title} ❌
- **Issue:** Acceptance criterion #2 not met — {details}
- **Required action:** {what needs to change}
```

Save the review findings:

```
memory_save(
  title: "Review — {STORY-KEY} changes requested",
  content: "## Findings\n{detailed findings per task}\n\n## Required Changes\n- {change 1}\n- {change 2}\n\n## Approved Tasks\n- {list of tasks that passed}",
  tags: ["review", "changes-requested", "{story-key}"],
  work_item_id: "{story uuid}"
)
```

If tasks need rework, set their status back explicitly. `work_status_next` only moves **forward** (there is no `work_status_prev`), so a backward move goes through `work_update` with an explicit status id:

```
work_statuses()                                        // find the id of the target status (e.g. "In Progress")
work_update(id: "{task uuid}", work_status: "{status uuid}")
```

---

## Step 4: Run Tests

If you can run the test suite, do it:

- Run all tests related to the changed code
- Run the full test suite if the changes could have side effects
- Report any failures

---

## Workflow Checklist

- [ ] Story and all tasks loaded
- [ ] Planning decisions and implementation memories retrieved
- [ ] Each task reviewed against acceptance criteria
- [ ] Code quality checked (correctness, consistency, simplicity, security)
- [ ] Locked decisions verified as respected
- [ ] Tests reviewed for quality and coverage
- [ ] Findings documented and saved as memory
- [ ] Tests run and passing

---

## What Comes Next

If the review passes, transition to **Delivery** — load the `delivery` skill (backend slug: `allye-technical-delivery`).

If changes are needed, the developer addresses the findings (back to **Technical Development**), then returns here for re-review.
