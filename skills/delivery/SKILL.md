---
name: delivery
description: Workflow for finalizing a story after all tasks pass review. Verifies completeness, closes the story, updates documentation, and cleans up. Use when all tasks are done and reviewed.
version: "1.0"
category: workflow
---

# Technical Delivery Workflow

This skill guides you through the final steps of delivering a story: verifying all tasks are complete, closing the story, updating documentation, and saving a final delivery memory.

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
Do NOT close the story if any task is not in "done" status.
Every task must be completed and verified before the story can be delivered.
If tasks are incomplete, go back to Technical Development or Technical Review.
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
- If it's done → mark as complete: `todo_update(id: "{todo uuid}", todo_completed: true)`
- If it's no longer relevant → delete: `todo_delete(id: "{todo uuid}")`
- If it's a future task → leave it, but make sure it's not blocking delivery

---

## Step 5: Save Delivery Memory

Save a final summary of what was delivered:

```
memory_save(
  title: "Delivered — {STORY-KEY} {story title}",
  content: "## What was delivered\n{summary of the feature/change}\n\n## Tasks completed\n- {TASK-1}: {title}\n- {TASK-2}: {title}\n- {TASK-3}: {title}\n\n## Key decisions\n{important decisions from planning and implementation}\n\n## Documentation\n{what was documented, or 'No documentation needed'}\n\n## Lessons learned\n{anything worth remembering for similar work in the future}",
  tags: ["delivery", "completed", "{story-key}", "{feature-key}"],
  work_item_id: "{story uuid}",
  sprint_id: "{sprint uuid if applicable}"
)
```

---

## Workflow Checklist

- [ ] All tasks verified as done
- [ ] Story moved to done
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
