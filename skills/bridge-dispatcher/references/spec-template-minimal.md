# Minimal spec template

For a known, bounded change in one app. It uses the same anchors as the full template (`[BR]`, `[AC]`, `[D]`, `[NFR]`, `[Q]`, numbered from `01`) so the server can track coverage and block submission on open questions. Drop an optional section only when it truly does not apply.

```markdown
# <Outcome-oriented title>

## Goal
<Problem, actor and end state in two or three sentences.>

## Current context
- <confirmed current behavior — source: path:line>
- <observed limitation>

## Contract
- Trigger / input: <what starts it>
- Behavior / output: <what the caller observes>
- Errors and recovery: <failure cases and what happens>
- Compatibility: <what existing callers keep seeing>

## Rules
- [BR-01] <rule>

## Acceptance criteria
- [AC-01] WHEN <trigger> THE SYSTEM SHALL <observable response>
- [AC-02] Given <state> When <action> Then <outcome>

## Flow                      (optional)
<compact steps or a small Mermaid diagram when it helps>

## Observability             (optional)
<signals tied to the failure modes>

## UX                        (optional, UI only)
<flow, states, accessibility, existing components to reuse>

## Out of scope
- <real exclusion>

## Decisions
- [D-01] (user) <decided by the user> — <rationale>
- [D-02] (source: <path>) <confirmed by evidence>
- [D-03] (proposed) <Dispatcher's recommendation> — <rationale>

## Non-functional requirements   (optional)
- [NFR-01] <measurable constraint>

## Questions
- [Q-01] (resolved) <question> → <answer>
- [Q-02] <open blocker — owner and impact>     ← blocks spec_submit
```

Rules: English throughout; every `[BR-NN]` covered by an `[AC-NN]`; no secrets or unnecessary personal data. If filling this template needs a Technical section of its own (data migration, cross-app contract, security model), the change belongs to the Architect.
