# Handover: correction

**Emitted by:** `orchestrator`
**Received by:** `execution` (the same Executor chat/session that produced the original implementation, when possible)
**Objective:** Fix specific review findings — this handover is deliberately narrow. It never re-briefs the whole story; that would defeat the point of a lean, targeted correction pass.

## Before emitting, confirm

- Only the ❌ findings are included — ✅ and ⚠️ items are not corrections, don't pad this handover with them.
- The correction round number is tracked — per spec §6.4, at most **2** correction handovers are ever emitted for the same task. If the 2nd correction round's review also comes back ❌ (i.e., the 3rd review failure on that task), the Orchestrator does not emit a 3rd correction handover — it stops and escalates to the human instead.
- Each finding is quoted from the Reviewer's actual output, not paraphrased — paraphrasing risks losing precision about what exactly needs to change.

## Template

```markdown
## 🔄 Allye Handover — correction
**Skill to load:** execution

### Objective
Fix the review findings below in {STORY-KEY} — nothing more.

### Findings to fix (❌ only)
- {TASK-KEY}: "{reviewer finding, quoted literally}"
- {TASK-KEY}: "{reviewer finding, quoted literally}"

### Correction round
This is correction attempt {N} for this story.
{If N is greater than 2, the Orchestrator shouldn't be emitting this handover — the max is 2 correction handovers per task; a 3rd review failure escalates to the user instead of producing a 3rd handover. See skills/orchestrator.}

---
Fix ONLY what's listed above — don't redo the whole story. If anything is unclear, STOP and ask — don't proceed on a guess.
```
