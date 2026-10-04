# Full spec template

One Allye spec per app. The content below is the spec's markdown body (`specs.spec_create content`). Anchors start a list item or heading: `[BR-NN]` rule, `[AC-NN]` acceptance criterion, `[D-NN]` decision, `[NFR-NN]` non-functional, `[Q-NN]` question. Number from `01`, never renumber; drop an anchor by removing it. Every anchor id is **defined exactly once per spec** — one list item or heading starting with it; everywhere else it is referenced inline ("see [D-01]"), never at the start of a list item or heading. A shared cross-spec contract is defined once, under Contracts and compatibility, and is not repeated as an anchor under Decisions (the server rejects a repeated anchor with `SPEC_DUPLICATE_ANCHOR`). Before returning, run `../../bridge/references/spec-lint.md`. Omit a section that genuinely does not apply by writing `n/a — <why>`; never leave a heading empty. Compact Mermaid diagrams are welcome when they clarify a flow or state; avoid fragile file inventories.

```markdown
# <Outcome-oriented title>

## Functional

### Context, problem and outcome
<Who is affected, what hurts today (with evidence), and the verifiable end state.>

### Actors and flows
- Actors: <roles and systems>
- Main flow: <numbered steps>
- Alternative flows: <steps>

### Scope and non-goals
- In scope: <items>
- Non-goals: <items deliberately excluded>

### Business rules
- [BR-01] <rule, including precedence when rules conflict>

### States and invariants
<Lifecycle states and transitions; what must always hold.>

### Edge cases and errors
<Each case: trigger, what the user/caller sees, how they recover.>

### Acceptance criteria
- [AC-01] WHEN <trigger> THE SYSTEM SHALL <observable response>
- [AC-02] Given <state> When <action> Then <observable outcome>

### Success signals
<Metric or observation that shows the outcome was reached; done condition.>

## Technical

### Current state and change
<How it works now (cite paths) and what changes.>

### Components and ownership
<Components touched in this app; what belongs to other apps' specs.>

### Contracts and compatibility
<API, event or data contracts; versioning; backward compatibility; order relative to dependent specs.>
- [D-01] (user) <cross-app contract> — <rationale>     ← defined here only; same number and text in every spec that shares it

### Data and migration
<Schema/data changes, migration, backfill, consistency. n/a when none.>

### Authentication, authorization, privacy and abuse
<Who may do what; trust boundaries; personal data; abuse and rate limits.>

### Concurrency, idempotency and failures
<Races, retries, timeouts, partial failure and recovery.>

### Observability
<Logs, metrics, alerts tied to the failure modes above.>

### Rollout and rollback
<Flag/canary/order; how to back out; cleanup.>

### Validation strategy
<Public seams and test levels per AC; regression checks; commands from the repo's scripts.>

### Alternatives and trade-offs
<Options considered and why the chosen one wins.>

## Decisions
Shared contracts are defined under Contracts and compatibility (see [D-01]); do not define them again here.
- [D-02] (user) <decision> — <rationale>
- [D-03] (source: <path or doc>) <decision confirmed by evidence> — <rationale>
- [D-04] (proposed) <architect's recommendation, not yet contested> — <rationale>

## Non-functional requirements
- [NFR-01] <measurable constraint: latency, size, availability, accessibility…>

## Questions
- [Q-01] (resolved) <question> → <answer>
- [Q-02] <open question — owner and impact>      ← any open [Q-NN] blocks spec_submit
```

## Rules

- Decision origin: `(user)` — the user decided or accepted it; `(source: …)` — established by code, docs or a primary source; `(proposed)` — the Architect's recommendation (all choices in `blueprint --auto`).
- Every `[BR-NN]` is covered by at least one `[AC-NN]`; every `[AC-NN]` is observable and testable as written.
- One definition per anchor id per spec; every other mention is inline. The anchor lint (`../../bridge/references/spec-lint.md`) must pass before the spec is returned and again before it is published.
- English throughout, even when the interview ran in another language.
- No secrets, tokens, internal URLs with credentials, or unnecessary personal data.
- The epic (multi-app only) is a short description: shared outcome, the specs and their order, compatibility notes, done condition.
