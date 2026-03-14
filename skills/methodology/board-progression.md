---
name: fenix-board-progression
description: Rules for moving work items between statuses in Fenix boards. Covers work_status_next, work_status_done, and status categories.
version: "1.0"
category: methodology
---

# Board Progression

This skill defines how to correctly move work items between statuses using Fenix boards. Understanding board progression prevents incorrect status transitions and ensures accurate project tracking.

---

## 1. Status Categories

Fenix uses these status categories, in typical progression order:

| Category | Meaning |
|----------|---------|
| `backlog` | Not yet planned — sitting in the backlog |
| `todo` | Planned and ready to start |
| `in_progress` | Actively being worked on |
| `testing` | Implementation done, being tested |
| `review` | Code review in progress |
| `deploying` | Being deployed to an environment |
| `done` | Completed and verified |
| `cancelled` | Will not be done |

Each team can customize their board with different columns and map statuses to columns as they see fit. The categories above are the semantic meaning — the actual status names may vary.

---

## 2. How `work_status_next` Works

`work_status_next` moves a work item to the **next logical status** in the board progression.

### Resolution logic

1. Collects all visible statuses from non-archived boards
2. Orders them by: `board.position → column.position → BoardColumnStatus.position`
3. Deduplicates: first occurrence wins
4. Finds the current status in this ordered list
5. Moves to the next status in the list

### Edge cases

| Situation | Behavior |
|-----------|----------|
| Current status is NOT in any visible board | Moves to the **first** status in the list |
| Current status is the **last** in the list | Returns an **error** — cannot move forward |
| Item has no status set | Moves to the **first** status in the list |

### When to use

```
work_status_next(id: "{work item uuid}")
```

Use this for **forward progression** through the workflow:
- Backlog → Todo (item is planned)
- Todo → In Progress (work starts)
- In Progress → Testing (implementation done)
- Testing → Review (tests pass)
- Review → Done (review approved)

### When NOT to use

- Don't use to skip statuses (e.g., backlog → done)
- Don't use to go backward — there is no `work_status_prev`
- Don't call repeatedly to "fast forward" through multiple statuses without doing the actual work

---

## 3. How `work_status_done` Works

`work_status_done` moves a work item directly to the "done" status, regardless of its current position.

### Resolution logic

1. Looks for a status mapped to a column with `is_done_column = true`
2. Fallback: picks the first status with `category === "done"`
3. Sets `completed_at = now()` on the work item

### When to use

```
work_status_done(id: "{work item uuid}")
```

Use this when work is **fully complete and verified**:
- All acceptance criteria are met
- Tests pass
- Review is approved (if applicable)

<HARD-GATE>
Do NOT call work_status_done unless the work is genuinely complete.
"Almost done" is not done. "Tests are mostly passing" is not done.
Verify all acceptance criteria before marking an item as done.
</HARD-GATE>

---

## 4. Checking Available Statuses

Before moving items, understand what statuses exist:

### List all statuses

```
work_statuses()
```

Returns all available statuses with their categories and names.

### View board columns

```
board_columns()
```

Returns the board structure showing which statuses are in which columns and their order. This is the source of truth for `work_status_next` progression.

---

## 5. Progression Patterns by Item Type

### Epic

Epics typically move through few statuses:
```
backlog → in_progress → done
```
- Move to `in_progress` when the first feature starts
- Move to `done` when ALL features are complete

### Feature

Features follow the epic pattern:
```
backlog → in_progress → done
```
- Move to `in_progress` when the first story starts
- Move to `done` when ALL stories are complete

### Story

Stories follow the full progression:
```
backlog → todo → in_progress → review → done
```
- `todo`: planned and ready to start (tasks created)
- `in_progress`: at least one task is being worked on
- `review`: all tasks done, story-level review in progress
- `done`: review passed, delivered

### Task

Tasks are the most granular:
```
todo → in_progress → done
```
- `in_progress`: actively being implemented
- `done`: acceptance criteria met, tests pass

### Bug

Bugs follow a similar path to tasks:
```
todo → in_progress → testing → done
```
- `testing`: fix implemented, verifying it resolves the issue

---

## 6. Common Mistakes

| Mistake | Why it's wrong | Do this instead |
|---------|---------------|-----------------|
| Moving story to done before all tasks are done | Misrepresents progress | Check `work_children` first — all tasks must be done |
| Skipping statuses with repeated `work_status_next` | Loses tracking fidelity | Only advance when the work for that status is actually complete |
| Moving to in_progress without planning | No tasks = no accountability | Run Technical Planning first, create tasks, then advance |
| Forgetting to check board structure | Different teams may have different progressions | Always check `board_columns` if unsure about available statuses |
| Moving a cancelled item to done | Contradictory | Cancelled items stay cancelled |
