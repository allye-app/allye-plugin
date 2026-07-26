---
name: delivery
description: Workflow for finalizing a story after all tasks pass review. Verifies completeness, closes the story, updates documentation, and cleans up. Use when all tasks are done and reviewed.
version: "1.4"
category: methodology
---

# Technical Delivery Workflow

This skill finalizes a story after every task has passed review — closing it out, documenting what shipped, and clearing loose ends.

Use this when: all tasks for a story are implemented and reviewed, and the user is ready to finalize delivery.

---

## Workflow Overview

```
Verify all tasks done → Close story → Update documentation → Clean up TODOs → Save delivery memory
```

---

## Step 1: Verify All Tasks Are Complete

Check that every task under the story is done:

```
work_children(id: "{story uuid}")
```

<HARD-GATE>
Close the story only once every task is completed, verified, and in "done" status.
If any task is incomplete, route back to Technical Development or Technical Review instead of closing.

"Done" means the **done category**, not the last status an agent could reach. On a pipeline
with stages after review, a task parked at a gate the team satisfies by hand is not done — it
is waiting, and the story waits with it.

If tasks are parked, close-out is not blocked by an oversight. It is **not yet due**. Say which
gate they are waiting at and stop; do not close the story to tidy the board.
</HARD-GATE>

### Verification checklist

For each task, confirm:
- [ ] Status is "done"
- [ ] Acceptance criteria are met
- [ ] Tests pass
- [ ] Review is approved (no outstanding change requests)

---

## Step 2: Close the Story

Move the story to done:

```
work_status_done(id: "{story uuid}")
```

This sets the story's status to the "done" category and records `completed_at`.

If the story is part of a feature, check if the feature is now complete:

```
work_children(id: "{feature uuid}")
```

If all stories under the feature are done, close the feature too:

```
work_status_done(id: "{feature uuid}")
```

---

## Step 2.5: Land the Code

The story is closed in Allye. The code is still on a branch.

Load the `branch-landing` skill and follow it. It asks how the work should land — pull
request, local merge, or left alone — and carries the sequence that gets it there without
losing anything.

<HARD-GATE>
Do not skip this because the story is already closed. Closing the item and landing the code
are different acts, and doing the first without the second produces the worst available
state: a board that says delivered and a base branch that does not have the work.

If the story reached this skill while still parked at a pipeline gate, it should not have —
see Step 1. The branch stays where it is.
</HARD-GATE>

---

## Step 3: Update Documentation

If the delivered work introduced or changed functionality that should be documented:

### Check existing docs

```
memory_search(query: "documentation {feature/story key}")
doc_full_tree()
```

### Create or update documentation

**For new functionality:**

```
doc_create(
  doc_title: "{Feature Name}",
  doc_type: "page",
  doc_emoji: "📄",
  doc_content: "## Overview\n{what this feature does}\n\n## Usage\n{how to use it}\n\n## Technical Details\n{relevant implementation details}\n\n## API Reference\n{endpoints, parameters, responses — if applicable}",
  doc_parent_id: "{parent folder uuid if applicable}"
)
```

**For updates to existing functionality:**

```
doc_update(
  id: "{doc uuid}",
  doc_content: "{updated content}"
)
```

### When to skip documentation

Not everything needs docs. Skip if:
- The change is purely internal (refactoring, performance, tests)
- The change is self-evident from the code
- Documentation would duplicate what's in the code

---

## Step 4: Clean Up TODOs

Check for any TODOs that were created during development:

```
todo_list()
```

For each TODO related to this story:
- If it's done → mark as complete: `todo_update(id: "{todo uuid}", status: "completed")`
- If it's no longer relevant → delete: `todo_delete(id: "{todo uuid}")`
- If it's a future task → leave it, but make sure it's not blocking delivery

---

## Step 5: Save Delivery Memory

Save a final summary of what was delivered:

```
memory_save(
  title: "Delivered — {STORY-KEY} {story title}",
  content: "## What was delivered\n{summary of the feature/change}\n\n## Tasks completed\n- {TASK-1}: {title}\n- {TASK-2}: {title}\n- {TASK-3}: {title}\n\n## Key decisions\n{important decisions from planning and implementation}\n\n## Documentation\n{what was documented, or 'No documentation needed'}\n\n## Where the code landed\n{branch name, and the merge commit or PR reference, and the base it landed on — or \"not yet landed: {reason}\"}\n\n## Lessons learned\n{anything worth remembering for similar work in the future}",
  tags: ["delivery", "completed", "{story-key}", "{feature-key}"],
  sector: "knowledge"
)
```

---

## Workflow Checklist

- [ ] All tasks verified as done
- [ ] Story moved to done
- [ ] The code landed, or the reason it has not is recorded
- [ ] Feature moved to done (if all stories complete)
- [ ] Documentation created or updated (if applicable)
- [ ] Related TODOs cleaned up
- [ ] Delivery memory saved

---

## What Comes Next

The story is delivered. The user can:
- **Pick another story** → Back to Technical Planning (`allye-technical-planning`)
- **Plan more features** → Back to Product Planning (`allye-product-planning`)
- **Start a new initiative** → Back to Product Planning from scratch
