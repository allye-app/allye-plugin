# Handover: story-execution

**Emitted by:** `orchestrator`
**Received by:** `execution`
**Objective:** Implement exactly **one** story — never a whole feature, and always the **entire** story: all of its tasks, across all waves, in a single dispatch. This is the scoping rule the whole Orchestrator/Executor loop depends on: one dispatch = one whole story. There is no per-wave handover and no follow-up "next wave" handover — the Executor works through the waves in order and reports back once, when the story is done.

## Before emitting, confirm

- Exactly one story is named — if the Orchestrator is tempted to hand off two stories "to save a round trip," it must not; that's a feature-level handover in disguise.
- **Every** task under that story is listed — all of them, across all waves, not just the first wave — with its acceptance criteria copied in **full** (not summarized, not just linked). The Executor's chat has no other context and will never receive a second handover for the rest of the story.
- Tasks are grouped by wave so the Executor knows the execution order, but the wave grouping is ordering information only — it never shrinks the scope of the dispatch.
- Applicable code standards were discovered (`skill_list` to find the relevant skill, then `skill_get(id: ...)` to fetch its actual content) and are named here, not left for the Executor to rediscover.

## Template

```markdown
## 🔄 Allye Handover — story-execution
**Skill to load:** execution

### Objective
Implement {STORY-KEY} — {story title}

### Story
- Key: {STORY-KEY}
- Acceptance criteria: {copied from the story description}

### Tasks (every task in the story, grouped by wave)
- Wave 1:
  - {TASK-KEY} — {title}
    - Acceptance criteria: {copied in full from the task description}
  - {TASK-KEY} — {title}
    - Acceptance criteria: {copied in full from the task description}
- Wave 2:
  - {TASK-KEY} — {title}
    - Acceptance criteria: {copied in full from the task description}

### Applicable locked decisions
- {decision} — {rationale}

### Applicable code standards
{conventions discovered via skill_list and fetched via skill_get that must be followed, or "No team standard found — follow existing conventions in the code"}

### TDD expectation
{whether Red-Green-Refactor applies and why, or why it doesn't}

---
Read ONLY this story and these tasks — nothing more. Execute the waves in the listed order. If anything is unclear, STOP and ask — don't proceed on a guess.
```
