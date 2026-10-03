# Handover: technical-to-orchestration

**Emitted by:** `technical-planning`
**Received by:** `orchestrator`
**Objective:** Drive delivery of the planned scope — a single spec, or a whole epic when the user chooses to group the handover by epic. This is the most "loaded" handover: the Orchestrator has no business or architecture context beyond what's here.

## Before emitting, confirm

- The full reading list is spelled out — doc, epic, every spec, every task, grouped by wave. "Read the epic" is not acceptable; list the actual keys.
- **The read instruction is explicit, not implied.** The handover must tell the receiver to read every spec under the parent (`epics.epic_get`, then `specs.spec_context` per spec, content and tasks included) and to open every referenced doc — a list of keys without that instruction invites skimming.
- Every locked architecture/stack decision is restated — the Orchestrator must never re-open these while dispatching Executor.
- Wave structure matches what Technical Planning actually produced (don't invent an ordering here — copy it).

## Template

```markdown
## 🔄 Allye Handover — technical-to-orchestration
**Skill to load:** orchestrator

### Objective
Drive delivery of {PARENT-KEY} — {spec or epic title}

### Required reading
Read ALL specs and tasks under {PARENT-KEY} via `epics.epic_get` + `specs.spec_context` for each spec, including content — the list below is a checklist to verify against, not a substitute for reading. Also open every referenced doc before dispatching any spec.

- Doc: {title and reference, or "No additional doc"}
- Epic: {EPIC-KEY}
- Specs and tasks by wave:
  - {SPEC-KEY} — {title}
    - Wave 1: {TASK-KEY}, {TASK-KEY}
    - Wave 2: {TASK-KEY}
  - {SPEC-KEY} — {title}
    - Wave 1: {TASK-KEY}

### Locked architecture decisions
- {decision} — {rationale}
- {decision} — {rationale}

### Additional context
{}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
