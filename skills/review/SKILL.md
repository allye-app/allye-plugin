---
name: review
description: Workflow for reviewing implemented code with decision context from planning. Use when the user wants to review code quality, validate implementation, or check tasks before delivery.
version: "1.2"
category: methodology
---

# Technical Review Workflow

This skill guides you through reviewing implemented code with full context — the decisions made during planning, the acceptance criteria defined for each task, and the architectural constraints captured in memories.

---

## Workflow Overview

```
Get spec context → Load decisions → Review each task → Document findings → Approve or request changes
```

---

## Step 1: Gather Context

### Get the spec and its tasks

```
specs.spec_context(spec: "{SPEC-KEY}")   // spec content, anchors, and every task with refs/status
```

### Load planning decisions

```
memory_search(query: "Technical Plan {spec key}")
memory_search(query: "decision {spec key}")
memory_search(query: "implementation {spec key}")
```

This gives you:
- The original plan and wave structure
- Locked decisions (non-negotiable choices by the user)
- Agent-discretion decisions (choices the agent made)
- Implementation notes from the development phase

---

## Step 2: Review Each Task — Two Axes

<!-- adapted from mattpocock/skills code-review (MIT) -->

Review runs as two independent passes. Keep them separate on the page and separate in
your head, and **do not reconcile them**: a change can pass one and fail the other, and
reporting them together is what lets one hide the other.

> Code that follows every standard but implements the wrong thing → **Standards pass,
> Spec fail.**
> Code that does exactly what was asked but breaks the project's conventions → **Spec
> pass, Standards fail.**

### Axis 1 — Standards: how it is written

Load team standards first (`skill_list` → `skill_get`); they override everything below.
Then: consistency with existing patterns, security, error handling, naming, and test
quality — do the tests assert behaviour rather than implementation, cover edge cases,
and break for the right reasons?

Full checklist and the baseline smells: `agents/reviewer-standards.md`.

### Axis 2 — Spec: whether it is what was asked for

Every acceptance criterion, one at a time, against the verification evidence the
execution report carried. A criterion reported met with no command output or observed
procedure behind it is **unverified**, and gets reported as unverified rather than met.
Then locked-decision compliance — any deviation is a defect — and unrequested scope.

Full checklist: `agents/reviewer-spec.md`.

### Reporting

Two reports, never merged, never reranked. The decision that combines them belongs to
the Orchestrator — see `orchestrator` §6.

---

## Step 3: Document Findings

### If everything looks good

```
memory_save(
  title: "Review — {SPEC-KEY} approved",
  content: "## Review Summary\nAll tasks reviewed and approved.\n\n## Tasks Reviewed\n- {TASK-1}: ✅ Criteria met, tests pass\n- {TASK-2}: ✅ Criteria met, tests pass\n\n## Notes\n{any observations for future reference}",
  tags: ["review", "approved", "{spec-key}"],
  sector: "knowledge"
)
```

### If changes are needed

Present findings to the user clearly:

```markdown
## Review Findings for {SPEC-KEY}

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
  title: "Review — {SPEC-KEY} changes requested",
  content: "## Findings\n{detailed findings per task}\n\n## Required Changes\n- {change 1}\n- {change 2}\n\n## Approved Tasks\n- {list of tasks that passed}",
  tags: ["review", "changes-requested", "{spec-key}"],
  sector: "knowledge"
)
```

If tasks need rework, send them back explicitly (`in_review → in_progress`), with the findings as the comment:

```
tasks.task_request_changes(task: "{TASK-KEY}", comment: "{findings summary}")
```

---

## Step 4: Run Tests

If you can run the test suite, do it:

- Run all tests related to the changed code
- Run the full test suite if the changes could have side effects
- Report any failures

---

## Workflow Checklist

- [ ] Spec and all tasks loaded
- [ ] Planning decisions and implementation memories retrieved
- [ ] Axis 2: each task's acceptance criteria checked against its verification evidence
- [ ] Axis 2: locked decisions verified as respected
- [ ] Axis 1: consistency, security, error handling, and naming checked
- [ ] Axis 1: tests reviewed for quality and coverage
- [ ] Findings documented and saved as memory, two axes kept separate
- [ ] Tests run and passing

---

## What Comes Next

If the review passes, transition to **Delivery** — load the `delivery` skill (backend slug: `allye-technical-delivery`).

If changes are needed, the developer addresses the findings (back to **Technical Development**), then returns here for re-review.
