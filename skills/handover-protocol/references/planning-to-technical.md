# Handover: planning-to-technical

**Emitted by:** `product-planning`
**Received by:** `technical-planning`
**Objective:** Technically detail the squares (Features) and sub-squares (Stories) approved in the business phase.

## Before emitting, confirm

- Every Epic/Feature/Story key is real (created via `work_create`/`work_bulk_create` or found via `work_list`) — never a placeholder key.
- Reused items and newly created items are explicitly distinguished — the next chat should never have to guess which is which.
- The `Doc:` line is filled in: if a Discovery Doc exists upstream (from a `discovery-to-planning` handover), carry its reference here; if none, write "Nenhum doc adicional" explicitly — don't leave the line out.
- Any key business decision made during Product Planning (scope cuts, explicit user choices, priorities — the ones saved as planning memories) is restated here, not just implied by the work item descriptions. This section is best-effort and often short or empty: most locked decisions come later, from Technical Planning's own Discussion Phase — don't pad it.

## Template

```markdown
## 🔄 Allye Handover — planning-to-technical
**Skill to load:** technical-planning

### Objective
{which story or set of stories will be technically detailed now}

### Required reading
- Doc: {title and reference of the Discovery Doc, or "No additional doc"}
- Epic: {KEY} — {title} ({reused | created})
- Feature(s): {KEY} — {title} ({reused | created})
- Story(ies) to plan now: {KEY} — {title} ({reused | created})

### Locked business decisions
- {decision 1} — {rationale}
- {decision 2} — {rationale}
{or "No locked business decision beyond the item descriptions"}

### Prototypes
{reference, or "No prototype was made"}

### Additional context
{}

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```
