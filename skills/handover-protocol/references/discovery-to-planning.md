# Handover: discovery-to-planning

**Emitted by:** `sandbox` (once approved by the user)
**Received by:** `product-planning`
**Objective:** Turn the direction approved during Sandbox into a deliverable structure (squares/sub-squares → Epic/Feature/Story).

## Before emitting, confirm

- A Discovery Doc was created in Allye (`doc_create`, location confirmed with the user against `doc_full_tree`) — this handover references it, it does not duplicate its content.
- Every path that was explored and abandoned is listed with *why* — the next chat should never accidentally re-propose a rejected direction.
- Research findings (if any) are summarized with enough detail to act on, not just "found some stuff."

## Template

```markdown
## 🔄 Allye Handover — discovery-to-planning
**Skill to load:** product-planning

### Objective
{one sentence: which product/objective is being planned}

### Discovery Doc
- Title: {doc title}
- Reference in Allye: {doc id or path in the tree}

### Approved direction
{synthesis of what was decided in Sandbox — what and why}

### Paths explored and rejected
- {path A} — rejected because {reason}
- {path B} — rejected because {reason}

### Research findings
{summary of what deep-search / code-analyzer brought back, with source — "No research was done" if none}

### Prototypes
{reference to generated artifacts, or "No prototype was made"}

### Additional context
{anything else the next chat needs to know}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
