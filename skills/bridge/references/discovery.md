# Discovery interview

One protocol for every mode that has to learn intent from the user: `blueprint` runs it fully, `dispatch` runs it with at most 3 questions. `blueprint --auto` skips the questions but keeps the same bookkeeping.

## Who does what

- **The Mothership asks**, in the main thread. Subagents cannot talk to the user.
- **Recon and Architect investigate in the background** while the interview runs. Each independent factual question gets its own Recon (at most 3 in parallel; sequential without subagents), which answers from code, docs and logs. Recon reads related specs and tasks through Allye MCP itself (or gets them embedded when subagents have no MCP access). For a multi-app feature, the Mothership passes the local path of each sibling app's clone so Recon can check the contract; an app not cloned locally is reported as a gap. Architect (`options` mode) drafts A/B options for frontier decisions and may ask for more Recon through you; in `dispatch`, the Dispatcher plays this role. Their findings feed the next round.
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

`dispatch`: ask only the Dispatcher's ≤3 questions (behavior and trigger, scope and failure limits, contract or done criterion), skipping any already answered or verifiable; take recommended defaults for the rest and record them as `[D-NN] (proposed)` the user can override in the summary. If the Dispatcher escalates (multi-app, systemic), switch to `blueprint`.

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

- a decision, tagged with its origin → `[D-NN] (user) <decision> — <rationale>` (the user decided or accepted it), `[D-NN] (source: <path or doc>) …` (established by evidence), `[D-NN] (proposed) …` (the author's recommendation, not yet confirmed);
- a question that was asked and answered → `[Q-NN] (resolved) <question> → <answer>` (the server's resolved form);
- a question still open → `[Q-NN] <question>` (blocks `spec_submit` until resolved);
- business rules and acceptance criteria surfaced → `[BR-NN]`, `[AC-NN]` (EARS or Given/When/Then), quality constraints → `[NFR-NN]`.

`blueprint --auto`: Architect (`auto` mode) picks the recommended option at each branch; record each as `[D-NN] (proposed) … — <rationale>`. A decision that is high-impact and genuinely the user's (product, cost, irreversible data change) stays an open `[Q-NN]` instead of being guessed.

## Authoring and challenge

When the frontier is empty, the author writes the proposal: Architect (`author` mode, full template, one spec per app, thin tasks) for `blueprint`; Dispatcher (`spec` mode, minimal template, thin tasks) for `dispatch`. Gaps the author still finds come back as one numbered round.

`blueprint` and `blueprint --auto` then run the **challenge round**: Strategist, Medic, Optimizer and Shield in `challenge` mode, in parallel, on the draft spec(s) and decisions. The Architect folds the findings in; only affected challenges rerun, at most 2 rounds. A CRITICAL/HIGH finding still unresolved becomes an open `[Q-NN]` (so the spec stays `draft`); MEDIUM/LOW are incorporated or listed, never dropped silently. `dispatch` skips the round. The result is shown in the closing summary and, once the spec key exists, logged as `spec-challenge` in the mission log.

## Closing

When the frontier is empty and the proposal is ready, follow `publish.md`: resolve project/app, search overlaps, present **one consolidated summary** (problem, chosen design, anchor ledger, epic/spec/task breakdown with spec order, challenge result, exactly what will be created) and ask **one confirmation**. Without a yes, create nothing. On yes, the author creates the confirmed items, you re-read them and `spec_submit` each spec with no open `[Q-NN]`. Never approve unless the user explicitly asks. A failure midway stops, re-reads and reconciles; never recreate blindly.
