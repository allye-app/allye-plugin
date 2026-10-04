# Discovery interview

One protocol for every mode that has to learn intent from the user: `blueprint` runs it fully, `dispatch` runs it with at most 3 questions. `blueprint --auto` skips the questions but keeps the same bookkeeping.

## Who does what

- **The Mothership asks**, in the main thread. Subagents cannot talk to the user.
- **Recon and Architect investigate in the background** while the interview runs: Recon gathers facts from code, docs, the Allye server (via the Mothership's MCP reads) and logs; Architect drafts options. Their findings feed the next round.
- **Facts are researched, never asked.** If a question can be answered from the code, the server, docs, logs or telemetry, find the answer. A fact still under investigation is an open prerequisite: ask the independent questions now, hold the dependent ones.
- **Decisions belong to the user.** Present alternatives, implications and a recommendation; wait for the answer before assuming a choice.

## The decision tree

Model the work as a tree of decisions: each decision unlocks the ones that depend on it. The **frontier** is every decision whose prerequisites are already resolved — the questions that can be asked now without guessing an answer not yet given.

Work in rounds:

1. Compute the frontier.
2. Ask the **whole frontier** in one round, numbered, each with your recommendation. Where Architect has options, frame them as **A — minimal** and **B — complete**, with trade-offs.
3. Wait for the answers.
4. Fold them into the tree: resolved decisions push the frontier outward and unlock dependent questions. A question that depends on another one still open in the current round belongs to a later round.
5. Repeat until the frontier is empty — every branch visited and no relevant decision silently assumed — and the user confirms that you share the same understanding.

`dispatch`: ask only the ≤3 questions that most change scope or risk; take recommended defaults for the rest and record them as decisions the user can override in the summary.

## Asking format

**Native question tool first.** When the harness has one, use it.

Claude Code `AskUserQuestion`:
- at most 4 questions per call — split a larger round into consecutive batches, keeping numbering continuous across them;
- 2–4 options per question; the recommended option comes first and its label ends with `(Recommended)`;
- put trade-offs in option descriptions, keep labels short;
- free text is available through the tool's built-in "Other" — do not add your own "Other" option.

**Fallback: numbered markdown**, one block per question:

```markdown
❓ **Q1 — <short title>**

<question body: context, options and their implications>

💡 **My recommendation:** <answer and why>

---
```

## Multi-app features

When Recon or the answers show the feature spans several apps, settle in the same interview: which apps are involved, the contract between them (API shape, events, shared types) and which side goes first. Plan one spec per app under one epic. Record the cross-app contract as one decision and copy it, with the same `[D-NN]` number and text, into every spec that shares it; keep `[D]` numbering aligned so the shared ids do not collide with app-specific ones.

## Recording the outcome

As answers arrive, keep a running ledger that will become spec anchors:

- a decision the user made (or accepted from your recommendation) → `[D-NN] <decision> — <rationale>`;
- a question that was asked and answered → `[Q-NN] <question> (resolved) — <answer>`;
- a question still open → `[Q-NN] <question>` (blocks `spec_submit` until resolved);
- business rules and acceptance criteria surfaced → `[BR-NN]`, `[AC-NN]` (EARS or Given/When/Then), quality constraints → `[NFR-NN]`.

`blueprint --auto`: Architect picks the recommended option at each branch; record each as `[D-NN] … (auto) — <rationale>`. A decision that is high-impact and genuinely the user's (product, cost, irreversible data change) stays an open `[Q-NN]` instead of being guessed.

## Closing

When the frontier is empty:

1. Present **one consolidated summary**: the problem, the chosen design, the anchor ledger, the epic/spec/task breakdown (Strategist's DAG; one spec per app with the dependency order between specs), and what will be created on the server.
2. Ask **one confirmation**. Without a yes, create nothing; stay in the interview or stop.
3. On yes, create directly via MCP, in this order: epic when needed — always for a multi-app feature (`epics.epic_create`); one spec per app (`specs.spec_create` with anchors in content, `type`, `apps` set to that single app, `epic`); tasks per spec (`tasks.task_bulk_create`, thin: refs, files, verify, notes); then the cross-app links (`specs.spec_dependency_add`, e.g. Web spec depends on API spec). For each spec with no open `[Q-NN]`, `specs.spec_submit` (draft → in_review).
4. Do not approve. `specs.spec_approve` happens only when the user explicitly asks for it.
5. If a creation fails midway, stop, read what exists, and propose how to reconcile; never recreate blindly.
