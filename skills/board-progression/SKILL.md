---
name: board-progression
description: Rules for moving work items between statuses in Allye boards. Covers work_status_next, work_status_done, and status categories.
version: "1.1"
category: methodology
---

# Board Progression

How to move work items between statuses on Allye boards, correctly.

---

## 1. Status Categories vs. Status Names

The MCP client can only **confirm** 4 status categories — `work_statuses()` (`work_items.py`) groups every status under a hardcoded `category_order`:

| Category (confirmed) | Meaning |
|----------|---------|
| `proposed` | Not yet started (backlog/todo-like) |
| `in_progress` | Actively being worked on |
| `done` | Completed and verified |
| `cancelled` | Will not be done |

That's the only taxonomy the MCP client source guarantees. Specific status **names** (e.g. "Backlog", "Todo", "In Progress", "Testing", "Review", "Deploying", "Done") are team-configurable `WorkflowStatus` records mapped onto those 4 categories via board columns — not enumerable or guaranteed from the client code alone, and a given team's board may use different names or skip some of them.

The finer-grained progression below is a common, practical convention — not something the client confirms, but the default working model most teams end up configuring something like:

| Status name (convention) | Meaning |
|----------|---------|
| `backlog` | Not yet planned — sitting in the backlog |
| `todo` | Planned and ready to start |
| `in_progress` | Actively being worked on |
| `testing` | Implementation done, being tested |
| `review` | Code review in progress |
| `deploying` | Being deployed to an environment |
| `done` | Completed and verified |
| `cancelled` | Will not be done |

Each team can customize their board with different columns and map statuses to columns as they see fit. Before relying on any specific status name, check `work_statuses()` (categories + actual names for the team) and `board_columns()` (which columns exist on the board in question).

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

Use it for **forward progression**, one status at a time, as each step's work actually finishes — the concrete sequence per item type is in §5.

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

Returns the board's columns for the given `board_id` — each rendered as `- {column name} (ID: {column id})`. Note: this tool's text output does not surface which statuses map to which column, nor an explicit ordering field (`boards.py`'s `board_columns` action only formats `name` and `id` per column) — that richer structure may exist in the underlying API but isn't exposed here. Use it to confirm which columns exist on a board; pair it with `work_statuses()` for status names/categories.

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
todo → in_progress → review → done
```
- `in_progress`: actively being implemented
- `review`: acceptance criteria met, tests pass — the Executor advances the task here (`work_status_next`) and no further; the task now awaits the Reviewer
- `done`: Reviewer returned ✅ — the **Orchestrator** makes this final move (`work_status_done`), never the Executor. If the Reviewer returns ❌, the task simply stays at `review` while a correction round runs (no backward move exists or is needed)

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
| Marking a task done as soon as its own tests pass | Done requires Reviewer approval, not just green tests | `work_status_next` to `review`; the Orchestrator moves it to done after Reviewer ✅ |
| Skipping statuses with repeated `work_status_next` | Loses tracking fidelity | Only advance when the work for that status is actually complete |
| Moving to in_progress without planning | No tasks = no accountability | Run Technical Planning first, create tasks, then advance |
| Forgetting to check board structure | Different teams may have different progressions | Always check `board_columns` if unsure about available statuses |
| Moving a cancelled item to done | Contradictory | Cancelled items stay cancelled |
