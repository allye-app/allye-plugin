# Handover: technical-to-orchestration

**Emitted by:** `technical-planning`
**Received by:** `orchestrator`
**Objective:** Drive delivery of the planned scope — a feature, or a whole epic when the user chooses to group the handover by epic. This is the most "loaded" handover: the Orchestrator has no business or architecture context beyond what's here.

## Before emitting, confirm

- The full reading list is spelled out — doc, epic, feature(s), every story, every task, grouped by wave. "Read the feature" is not acceptable; list the actual keys.
- **The read instruction is explicit, not implied.** The handover must tell the receiver to read the entire subtree under the parent item (`work_get` + recursive `work_children`, descriptions included) and to open every referenced doc — a list of keys without that instruction invites skimming.
- Every locked architecture/stack decision is restated — the Orchestrator must never re-open these while dispatching Executor.
- Wave structure matches what Technical Planning actually produced (don't invent an ordering here — copy it).

## Template

```markdown
## 🔄 Allye Handover — technical-to-orchestration
**Skill to load:** orchestrator

### Objective
Drive delivery of {PARENT-KEY} — {feature or epic title}

### Required reading
Read ALL work items under {PARENT-KEY} via `work_get` + `work_children` (recursively, down to the tasks), including descriptions — the list below is a checklist to verify against, not a substitute for reading. Also open every referenced doc before dispatching any story.

- Doc: {title and reference, or "No additional doc"}
- Epic: {EPIC-KEY}
- Feature(s): {FEATURE-KEY}
- Stories and tasks by wave:
  - {STORY-KEY} — {title}
    - Wave 1: {TASK-KEY}, {TASK-KEY}
    - Wave 2: {TASK-KEY}
  - {STORY-KEY} — {title}
    - Wave 1: {TASK-KEY}

### Locked architecture decisions
- {decision} — {rationale}
- {decision} — {rationale}

### Additional context
{}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
