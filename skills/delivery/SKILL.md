---
name: delivery
description: Workflow for finalizing a spec after all tasks pass review. Verifies completeness, confirms the spec is done, updates documentation, and cleans up. Use when all tasks are done and reviewed.
version: "1.4"
category: methodology
---

# Technical Delivery Workflow

This skill finalizes a spec after every task has passed review — confirming it is done, documenting what shipped, and clearing loose ends.

Use this when: all tasks for a spec are implemented and reviewed, and the user is ready to finalize delivery.

---

## Workflow Overview

```
Verify all tasks done → Confirm spec done → Update documentation → Clean up TODOs → Save delivery memory
```

---

## Step 1: Verify All Tasks Are Complete

Check that every task under the spec is done:

```
specs.spec_context(spec: "{SPEC-KEY}")
```

<HARD-GATE>
Finish the spec only once every non-cancelled task is completed, verified, and `done`.
If any task is incomplete, route back to Technical Development or Technical Review instead of closing.

A task in `in_review` is not done — it moves to `done` only through `tasks.task_complete`
after its review passed. A task waiting on something the team satisfies by hand (QA, a
deploy) is waiting, and the spec waits with it.

If tasks are still open, close-out is not blocked by an oversight. It is **not yet due**. Say
what they are waiting on and stop; never complete or cancel tasks just to finish the spec.
</HARD-GATE>

### Verification checklist

For each task, confirm:
- [ ] Status is `done` (or deliberately `cancelled`, with the reason recorded)
- [ ] Acceptance criteria are met
- [ ] Tests pass
- [ ] Review is approved (no outstanding change requests)

---

## Step 2: Confirm the Spec Is Done

There is no manual "close" action. The spec moves `in_progress → done` **automatically** when
all its non-cancelled tasks are `done`, and the epic's status is computed from its specs.
Read the spec back (`specs.spec_get`) and confirm it is `done`. Also check
`specs.spec_coverage`: any uncovered `[AC-NN]` is worth reporting to the user before
calling the work delivered.

---

## Step 2.5: Land the Code

The spec is done in Allye. The code is still on a branch.

Load the `branch-landing` skill and follow it. It asks how the work should land — pull
request, local merge, or left alone — and carries the sequence that gets it there without
losing anything.

<HARD-GATE>
Do not skip this because the spec is already done. Finishing the spec and landing the code
are different acts, and doing the first without the second produces the worst available
state: a spec that says delivered and a base branch that does not have the work.

If the spec reached this skill with tasks still open, it should not have —
see Step 1. The branch stays where it is.
</HARD-GATE>

---

## Step 3: Update Documentation

If the delivered work introduced or changed functionality that should be documented:

### Check existing docs

```
memory_search(query: "documentation {epic/spec key}")
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

For each TODO related to this spec:
- If it's done → mark as complete: `todo_update(id: "{todo uuid}", status: "completed")`
- If it's no longer relevant → delete: `todo_delete(id: "{todo uuid}")`
- If it's a future task → leave it, but make sure it's not blocking delivery

---

## Step 5: Save Delivery Memory

Save a final summary of what was delivered:

```
memory_save(
  title: "Delivered — {SPEC-KEY} {spec title}",
  content: "## What was delivered\n{summary of the change}\n\n## Tasks completed\n- {TASK-1}: {title}\n- {TASK-2}: {title}\n- {TASK-3}: {title}\n\n## Key decisions\n{important decisions from planning and implementation}\n\n## Documentation\n{what was documented, or 'No documentation needed'}\n\n## Where the code landed\n{branch name, and the merge commit or PR reference, and the base it landed on — or \"not yet landed: {reason}\"}\n\n## Lessons learned\n{anything worth remembering for similar work in the future}",
  tags: ["delivery", "completed", "{spec-key}", "{epic-key}"],
  sector: "knowledge"
)
```

---

## Workflow Checklist

- [ ] All tasks verified as done
- [ ] Spec is `done` (automatic once all tasks are done)
- [ ] The code landed, or the reason it has not is recorded
- [ ] Documentation created or updated (if applicable)
- [ ] Related TODOs cleaned up
- [ ] Delivery memory saved

---

## What Comes Next

The spec is delivered. The user can:
- **Pick another spec** → Back to Technical Planning (`allye-technical-planning`)
- **Plan more specs or epics** → Back to Product Planning (`allye-product-planning`)
- **Start a new initiative** → Back to Product Planning from scratch
