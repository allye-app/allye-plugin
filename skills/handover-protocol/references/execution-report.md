# Handover: execution-report

**Emitted by:** `execution`
**Received by:** `orchestrator`
**Objective:** Return the implementation result — what the Orchestrator uses to decide whether to dispatch the Reviewer or cascade status right away.

## Before emitting, confirm

- Every task's status is reported per acceptance criterion, not as a blanket "done" — the Orchestrator and the eventual Reviewer both need this granularity.
- Files changed are listed explicitly (not "various files") — the Reviewer dispatch depends on this list.
- Open questions are surfaced here rather than silently assumed away — this is the Executor's last chance to flag uncertainty before the chat ends.

## Template

```markdown
## 🔄 Allye Handover — execution-report
**Skill to load:** orchestrator

### Story implemented
{STORY-KEY} — {title}

### Tasks and status per acceptance criterion
- {TASK-KEY}: {✅ done | ⚠️ partial | ❌ blocked}
  - {criterion 1}: {met | not met — why}
  - {criterion 2}: {met | not met — why}

### Files changed
- {path} — {what changed}
- {path} — {what changed}

### Tests added
{which, what they cover, or "No test was needed — reason"}

### New decisions made during implementation
- {decision} — {rationale}, or "No new decision"

### Open questions
{anything that stayed unanswered and needs a human decision, or "None"}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
