# Handover: story-execution

**Emitted by:** `orchestrator`
**Received by:** `execution`
**Objective:** Implement exactly **one** story — never a whole feature, and always the **entire** story: all of its tasks, across all waves, in a single dispatch. This is the scoping rule the whole Orchestrator/Executor loop depends on: one dispatch = one whole story. There is no per-wave handover and no follow-up "next wave" handover — the Executor works through the waves in order and reports back once, when the story is done.

## Before emitting, confirm

- Exactly one story is named — if the Orchestrator is tempted to hand off two stories "to save a round trip," it must not; that's a feature-level handover in disguise.
- **Every** task under that story is listed — all of them, across all waves, not just the first wave — with its acceptance criteria copied in **full** (not summarized, not just linked). The Executor's chat has no other context and will never receive a second handover for the rest of the story.
- Tasks are grouped by wave so the Executor knows the execution order, but the wave grouping is ordering information only — it never shrinks the scope of the dispatch.
- **Constraints are referenced, not recopied.** Anything true of every story under this
  feature — the base branch, the test command, naming rules, the definition of done — belongs
  in one feature-level doc that each handover points at. Recopying it into every handover
  creates as many places to drift as there are stories, and the drift is silent because each
  copy looks authoritative.
- The story's **AFK/HITL label** is stated. It was derived at planning time from whether every
  task carries a runnable verification command (see `verification-loop` §4). The Orchestrator
  reads it to decide whether this story can go to an unattended pane — omitting it forces a
  guess about whether a human needs to be watching.

## Template

```markdown
## 🔄 Allye Handover — story-execution
**Skill to load:** execution

### Objective
Implement {STORY-KEY} — {story title}

### Story
### Dispatch label
{AFK — every task has a runnable verification command | HITL — {TASK-KEY} declares verification: manual}
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

### Constraints
Reference to the feature's constraints doc in Allye — read it, do not expect it summarised here.
{doc title and id, or "No constraints doc — follow existing conventions in the code"}

### TDD expectation
{whether Red-Green-Refactor applies and why, or why it doesn't}

---
Read ONLY this story and these tasks. Execute the waves in the listed order.

**If anything is unclear, STOP and ask — don't proceed on a guess.**

**If anything is contradictory, STOP and report it.** A step that is perfectly clear and
impossible is a different failure from an ambiguous one, and the more dangerous: it can be
satisfied by quietly weakening whatever it conflicts with. Two criteria that cannot both
hold, a task requiring what another forbids — report both halves, quoted, and resolve
neither.

**Report what is wrong but out of scope — do not fix it.** A defect you notice while working
on something else is worth more reported than silently repaired, because a silent repair
hides a decision that was never made.

**Do not report "no issues" to be agreeable.** A conflict named is worth more than a clean
report. If two rules genuinely disagreed and you chose one, say which and why.
```
