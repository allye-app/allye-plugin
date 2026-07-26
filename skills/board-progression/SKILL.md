---
name: board-progression
description: Rules for moving work items between statuses in Allye boards. Covers work_status_next, work_status_done, and status categories.
version: "1.2"
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

That's the only taxonomy the MCP client source guarantees. Specific status **names** are team-configurable `WorkflowStatus` records mapped onto those 4 categories via board columns — not enumerable or guaranteed from the client code alone, and a given team's board may use different names or skip some of them.

### The team's pipeline is data. Read it.

Allye is multi-tenant. Four presets ship — Solo, Startup, Standard, Enterprise — and every
team customises from there, so **there is no status list to memorise and no ordering to
assume.** A skill that names a status has guessed about somebody else's board.

Only three things are stable enough to build a rule on:

| Stable | Why |
|---|---|
| The four categories: `proposed`, `in_progress`, `done`, `cancelled` | A schema enum. Every status maps to exactly one. |
| The three pipelines: `product`, `engineering`, `shared` | A schema enum. `product` carries epics and features; `engineering` carries stories and below; `shared` holds the terminal states. |
| The board's own ordering | Whatever it is, it is what `work_status_next` walks. |

Discover the rest:

```
work_statuses()    → every status the team has, grouped by category, in position order
board_columns()    → the columns of a specific board
```

**Two things `work_statuses()` does not tell you today**, and planning around them is the
difference between a working transition and a surprised one:

- **`position`, `pipeline`, and `description` are not returned.** They exist on the record —
  the seed writes all three — but the MCP formatter emits only name, key, id, and colour.
- **`board_columns()` returns names and ids only** — no status-to-column mapping and no
  ordering. The visible subset a given board shows cannot be reconstructed from it.

Together these mean **you cannot reliably predict the next status.** So do not:

<HARD-GATE>
Move one status at a time, then **read back** the status you actually landed on. Never
assume a transition took you where you expected, and never chain several moves on a
prediction. One extra read per transition costs nothing next to a cascade that silently
skipped four gates.
</HARD-GATE>

For reference only, these are the eighteen statuses the presets seed — **an example of one
tenant's configuration, not a list to code against**: `idea`, `researching`, `designing`,
`specifying`, `backlog`, `todo`, `in_progress`, `code_review`, `security_scan`, `qa_testing`,
`doc_review`, `deploy_staging`, `qa_staging`, `deploy_preprod`, `qa_preprod`, `deploy_prod`,
`done`, `cancelled`.

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

Use it for **forward progression**, one status at a time, as each step's work actually finishes — how progression differs by pipeline and item type is in §5.

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

## 3.1 Where an agent's authority ends

> **An agent drives everything that is verification. It stops at the first gate that changes
> the world outside the repository.**

Deploying does that. Verifying does not. The rule survives renaming because it describes what
a gate *is*, not what it is called — which is the only kind of rule that works when every
team configures its own statuses.

In practice, on the seeded presets: reviewing, scanning, testing, and updating docs are all
verification and all satisfiable by an agent. Every deploy stage, and any validation
performed in a deployed environment, is not.

<HARD-GATE>
`work_status_done` is **not** the exit from a pipeline an agent cannot finish. Calling it
from four statuses away records "done" for work that never passed the gates in between.

Use it only when the item's next status **is** the done status. Otherwise stop at the last
gate you satisfied and say plainly which gate is next and who owns it.
</HARD-GATE>

An unrecognised status is treated as a stop, not a pass. Ask once who satisfies it, record
the answer in the team's delivery configuration, and never ask again.

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

Progression differs by pipeline, not only by type. **Epics and features live on the `product`
pipeline; stories, bugs, hotfixes, tasks, spikes, and subtasks live on `engineering`.** A
cascade from task to epic therefore crosses pipelines, and the statuses available on each side
are different sets.

What holds regardless of the team's configuration:

- **Parents move because children moved.** A story advances when its tasks do; a feature when
  its stories do; an epic when its features do. Never the other way round.
- **A parent never reaches the done category while any child is outside it.** This is the one
  rule that failed in practice: a story closed with seven of fifteen tasks still mid-pipeline,
  because closing it was the only exit the flow offered. Stopping is the exit.
- **The Executor advances a task only to the first review gate.** The move past that is the
  Orchestrator's, after review clears — see `orchestrator` §6.

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
