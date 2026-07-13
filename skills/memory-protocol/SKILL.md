---
name: memory-protocol
description: Complete memory protocol for AI agents using Allye. Defines when and how to search, save, and link memories for cross-session continuity.
version: "2.1"
category: methodology
---

# Allye Memory Protocol

Memories are how context survives between conversations. Without them, every session starts from zero — decisions get repeated, context gets lost, and work gets duplicated.

This skill defines the complete protocol for using Allye's intelligent memory system (`memory_save` and `memory_search`).

---

## 1. How the Memory System Works

Allye uses **semantic search powered by AI embeddings** — not keyword matching. This means:

- `"what did we decide about auth?"` finds memories about authentication even if the word "auth" doesn't appear
- Queries should be natural language, not keyword lists
- Results are ranked by semantic similarity with scores

### Memory sectors

Every memory belongs to one of 7 sectors. **Always pass `sector` when saving.** If you omit it, the server infers the sector from the tags (fallback: `knowledge`).

| Sector | What it holds | Use it for |
|--------|---------------|------------|
| `decisions` | Technical/product decisions and trade-offs, with rationale | "We chose X over Y because..." |
| `sessions` | Session state and handovers | End-of-session continuity snapshots |
| `patterns` | Reusable patterns and conventions | "Services in this codebase follow..." |
| `incidents` | Bugs, blockers, regressions | "Deploy broke because..." |
| `plans` | Plans and roadmaps | Action plans, milestones, next steps |
| `knowledge` | Reusable learnings and background context (**default**) | Insights, findings, non-obvious constraints |
| `preferences` | Personal preferences | "User prefers conventional commits" — auto-pinned, exempt from decay |

**Scope is derived from the sector — you never pass a scope:**

- **Personal** (visible only to you): `sessions`, `preferences`
- **Team** (shared with the active team): `decisions`, `incidents`, `plans`, `patterns`, `knowledge`

Search always covers the union of your personal memories and the active team's memories — not all teams.

> **Note:** if a team-sector memory is saved without a usable active team, the API gracefully falls back to personal scope — the save never fails because of scope. You don't need to worry about scope at all; just pick the right sector.

`sessions` being personal-only is what makes it the landing zone for raw session consolidation (§4) — nothing durable or team-relevant should stay parked there. Anything worth remembering beyond "what happened in this conversation" belongs in one of the six team sectors instead, which is exactly what the mining step of the /save protocol (§4, Step 2) exists to do: read a `sessions` memory and decide, sector by sector, what graduates to team knowledge.

### Conflict resolution (not auto-dedup)

Every `memory_save` passes through conflict resolution — Allye checks for similar existing memories (similarity ≥60%, including near-identical ≥95%) and a resolver decides the outcome. There is no blind "too similar → reject" rule: even near-identical content can update, supersede, or merge into an existing memory instead of just bouncing.

Four possible outcomes: `ADD`, `UPDATE`, `SUPERSEDE`, `NOOP`. `rejected` can still appear, but only as a residual case for schema validation failures (e.g. missing required fields) — never as an automatic consequence of similarity scoring.

**What to do with each outcome** is covered in Step 3 of the /save protocol (§4) — that guidance applies to every `memory_save` call, not only ones made during /save.

---

## 2. When to Search

### Conversation start (mandatory)

<EXTREMELY_IMPORTANT>
At the start of EVERY conversation, run at least these searches before doing anything else:

1. `memory_search(query: "Session State")` — find where the user left off
2. `memory_search(query: "{topic of user's request}")` — find relevant context
3. `memory_search(query: "{work item key}")` — if a specific item is mentioned (e.g., "PROJ-123")
</EXTREMELY_IMPORTANT>

**What to do with results:**
- If session state is found → summarize it for the user: "Last time we were working on X, you completed Y, and the next step was Z."
- If decisions are found → keep them in mind and respect locked decisions
- If no results → proceed normally, but note this is a fresh context

### Before making technical decisions

Before choosing an approach, search for prior decisions:

```
memory_search(query: "decision {topic}")
memory_search(query: "architecture {component}")
```

Previous decisions may be **locked** (explicitly chosen by the user) — these are non-negotiable. If you need to deviate from a locked decision, you MUST discuss it with the user first.

### Before implementing

Before writing code for a task, search for implementation context:

```
memory_search(query: "{task key} implementation")
memory_search(query: "{feature name} context")
```

This surfaces constraints, dependencies, and past learnings that affect the current work.

---

## 3. When to Save

### Decisions (save immediately)

When a technical decision is made, save it right away:

```
memory_save(
  title: "Decision — {short description}",
  content: "## Decision\n{what was decided}\n\n## Why\n{rationale and trade-offs considered}\n\n## Alternatives rejected\n{what was not chosen and why}\n\n## Classification\n{locked | agent-discretion}",
  tags: ["decision", "{work-item-key}", "{topic}"],
  sector: "decisions",
  work_item_id: "{uuid if applicable}"
)
```

**Locked vs Agent Discretion:**
- **Locked** — The user explicitly chose this. Do not change without user approval.
- **Agent discretion** — The agent chose this. Can be revisited if circumstances change.

### Trade-offs (save when evaluated)

When you evaluate trade-offs between approaches:

```
memory_save(
  title: "Trade-off — {short description}",
  content: "## Options\n{option A vs B vs C}\n\n## Analysis\n{pros/cons of each}\n\n## Chosen\n{which one and why}",
  tags: ["trade-off", "{work-item-key}", "{topic}"],
  sector: "decisions"
)
```

### Blockers (save when identified)

When something blocks progress:

```
memory_save(
  title: "Blocker — {short description}",
  content: "## Blocker\n{what's blocking}\n\n## Impact\n{what can't proceed}\n\n## Possible resolutions\n{ideas to unblock}",
  tags: ["blocker", "{work-item-key}"],
  sector: "incidents"
)
```

### Implementation context (save when non-obvious)

When you discover something during implementation that would be lost between sessions:

```
memory_save(
  title: "Context — {short description}",
  content: "## What\n{the insight or finding}\n\n## Why it matters\n{how this affects future work}",
  tags: ["context", "{work-item-key}", "{topic}"],
  sector: "knowledge"
)
```

### Session state — handled by the /save protocol

<EXTREMELY_IMPORTANT>
Before the conversation ends (or whenever /save is invoked), you MUST run the full /save protocol described in §4. Session state is no longer a single ad hoc save — it's the first of three coordinated steps that also promote durable knowledge from the session into team sectors.
</EXTREMELY_IMPORTANT>

---

## 4. The /save Protocol

`/save` is not one `memory_save` call — it's a 3-step protocol that turns a session's raw activity into (a) a personal continuity snapshot and (b) correctly-scoped, durable team knowledge. Run the steps in order, every time /save is invoked or a conversation is about to end.

### Step 1 — Consolidate the session (sector: `sessions`, personal)

Save exactly ONE memory that summarizes the whole session, using the same shape as before:

```
memory_save(
  title: "Session State — {WORK-KEY} {short description}",
  content: "## Current position\n{phase: planning/development/review/delivery}\n{current task/story}\n\n## Work completed\n- {item 1}\n- {item 2}\n\n## Decisions made\n- {decision 1} [locked|agent-discretion]\n- {decision 2} [locked|agent-discretion]\n\n## Blockers\n- {blocker or 'None'}\n\n## Next concrete step\n{exactly what to do when resuming — be specific}",
  tags: ["session-state", "{work-item-key}", "{current-phase}"],
  sector: "sessions",
  work_item_id: "{uuid}",
  sprint_id: "{uuid if in active sprint}"
)
```

This memory is the raw material for Step 2 — write it richly enough (real decisions, real blockers, real next steps) that mining it actually produces something. A vague consolidation yields nothing worth promoting.

### Step 2 — Mine the consolidation for promotable knowledge (team sectors, agent discretion)

Re-read the Step 1 content and ask: **is any of this still true and useful outside this conversation?** If yes, save it separately, in the sector it actually belongs to — this is the mechanism that promotes knowledge from personal (`sessions`) to team (`decisions`, `incidents`, `plans`, `patterns`, `knowledge`).

**Promote when the content is:**
- A **decision** with rationale that the next person/session needs to respect → `decisions`
- A **bug, regression, or blocker** with a real cause (not just "task was slow") → `incidents`
- A **plan or roadmap step** that outlives this session → `plans`
- A **reusable convention or pattern** discovered or confirmed while working → `patterns`
- A **non-obvious constraint or insight** that would surprise someone starting fresh → `knowledge`

**Do NOT promote:**
- Anything that's just restating what the code/diff/commit already shows
- Routine progress ("implemented X", "ran tests") with no durable lesson attached
- Anything already covered by an existing team memory — search before promoting, same as any other save
- Content that only makes sense in the context of this specific conversation

Each promoted item is its own `memory_save` call — one topic per memory, sector matched to content type, tags following §5. Do not force a promotion just to have one; a session with zero promotable content is normal, and Step 2 saving nothing is a correct outcome.

### Step 3 — Every save resolves a conflict — react to the outcome

Both the Step 1 consolidation and every Step 2 promotion go through conflict resolution (§1) and come back with one of four outcomes. React accordingly — do not treat any of these as an error to work around:

| Outcome | What happened | What you do |
|---------|---------------|--------------|
| `ADD` | No meaningful overlap found; a new memory was created | Nothing — proceed normally |
| `UPDATE` | Existing memory was close enough to aggregate; it was updated in place, content merged | Nothing — the existing memory now holds both old and new; don't also create a separate memory for the same fact |
| `SUPERSEDE` | New content invalidates the old; a new memory was created and the old one marked superseded (not deleted) | Nothing — this is expected when a decision changes or a plan is revised; don't manually go "fix" the old memory too |
| `NOOP` | Content is already fully covered; nothing was written | Stop — do not reword and retry to force a save. Use the returned existing memory as the source of truth instead |

If you find yourself rephrasing the same content to get past a `NOOP`, that's a signal the content wasn't actually new — trust the resolver.

---

## 5. Tag Conventions

Use consistent tags so memories can be found reliably.

### Phase tags

| Tag | When to use |
|-----|-------------|
| `planning` | During product or technical planning |
| `development` | During implementation |
| `review` | During code review |
| `delivery` | During finalization and delivery |

### Work item tags

Use the work item key as-is: `PROJ-123`, `FEAT-45`, `TASK-67`

For hierarchical context, prefix with type:
- `epic:PROJ-100`
- `feature:PROJ-110`
- `story:PROJ-123`

### Topic tags

| Tag | Domain |
|-----|--------|
| `architecture` | System design, patterns, structure |
| `api-design` | API contracts, endpoints, schemas |
| `database` | Schema, migrations, queries |
| `testing` | Test strategy, coverage, fixtures |
| `performance` | Optimization, benchmarks, profiling |
| `security` | Auth, permissions, vulnerabilities |
| `deployment` | CI/CD, infrastructure, environments |
| `dependencies` | Third-party libraries, version management |
| `breaking-changes` | Changes that affect existing behavior |

### Content type tags

| Tag | What it marks |
|-----|---------------|
| `decision` | A choice that was made with rationale |
| `trade-off` | An evaluated comparison between options |
| `blocker` | Something preventing progress |
| `context` | Background information or insight |
| `session-state` | End-of-session continuity snapshot |

---

## 6. Entity Linking

Always link memories to relevant Allye entities when available:

| Parameter | When to set |
|-----------|-------------|
| `work_item_id` | Working on a specific epic, feature, story, task, or bug |
| `sprint_id` | Working within an active sprint |
| `documentation_item_id` | Memory relates to a documentation page |
| `team_id` | Memory is team-specific (required for multi-team users) |

Entity links enable Allye to build a knowledge graph — memories connected to work items, sprints, and docs create navigable context across the project.

---

## 7. Search Strategies

### Broad discovery

When you're not sure what exists:
```
memory_search(query: "{general topic}", limit: 10)
```

### Targeted retrieval

When you know what you're looking for:
```
memory_search(query: "Decision — authentication middleware for {project}")
```

### Multi-angle search

For complex topics, run multiple searches:
```
memory_search(query: "Session State PROJ-123")    → current position
memory_search(query: "decision PROJ-123")          → past decisions
memory_search(query: "architecture {module name}")  → technical context
```

### Tip: search is semantic, not keyword-based

- **Good query:** `"what approach did we choose for handling file uploads"`
- **Bad query:** `"file upload decision PROJ-123 architecture storage"`

Write queries like you're asking a colleague, not searching a database.

---

## 8. Anti-Patterns

| Anti-pattern | Problem | Do this instead |
|-------------|---------|-----------------|
| Saving every small change | Noise drowns out signal | Save decisions, trade-offs, blockers, and session state — not trivial details |
| Using vague titles | Hard to find later | Be specific: "Decision — use PostgreSQL JSONB for dynamic fields" not "Database decision" |
| Skipping entity links | Memories float disconnected | Always link to the work item you're working on |
| Saving implementation details | Code is the source of truth for code | Save the *why*, not the *what*. The code shows what changed; the memory explains why |
| Not searching before saving | Creates near-duplicates that conflict resolution then has to untangle via `UPDATE`/`SUPERSEDE`/`NOOP` — extra round trips you could've skipped | Search first, then save |
| Giant memory dumps | Hard to search, and content is capped at 10000 characters | Keep memories focused. One topic per memory. |

---

## 9. Graph Traversal Strategies

The memory graph connects memories through explicit relation edges created at save time. Use traversal to discover clusters of related context that semantic search might miss.

### When to use which approach

| Approach | Use when |
|----------|----------|
| `memory_search(query)` | You know *what* you're looking for (semantic query) |
| `memory_graph(memory_id, depth: 2)` | You have an ID and want to explore its neighborhood |
| `memory_relations(memory_id)` | You want a quick 1-hop check of a specific memory |
| `memory_search(query, include_graph: true)` | Search + graph context in one call |

### Pattern: Context recovery with graph

At session start, after finding the session state memory:

```
1. memory_search(query: "Session State {work key}")
   → get session state memory ID

2. memory_graph(memory_id: "{id}", depth: 2)
   → explore connected decisions, trade-offs, blockers from past sessions
```

This surfaces memories that are linked but might not match the semantic query.

### Pattern: Exploring a decision cluster

```
memory_graph(
  memory_id: "{decision memory ID}",
  depth: 2,
  relation_types: ["extends", "caused_by", "supersedes"]
)
```

### Interpreting graph results

- **Depth 0** — the root memory itself
- **Depth 1** — directly connected memories
- **Depth 2+** — transitively connected (can grow fast — use `relation_types` or `graph_limit` to bound)
- **Edge types:** `similar | extends | caused_by | supersedes | contradicts | depends_on`

### Handling timeouts (408)

If `memory_graph` or `memory_relations` returns a timeout:
1. Reduce `depth` (try 1 instead of 2+)
2. Add `relation_types` to narrow traversal
3. Add `graph_limit` to cap total nodes returned

---

## 10. Relocation Flow (Opt-in, One-Time)

Before F1 shipped sector/scope, memories didn't have either concept. The backfill that introduced them had to put every pre-existing memory somewhere, so it landed all of it as `scope: personal, sector: knowledge` — a safe default, not necessarily the right one. Some of that content is genuinely personal (notes, session scratch). Some of it is really team knowledge (a decision, a pattern, an incident) that just predates the sector system and never got the chance to be shared.

The relocation flow lets the agent surface that backlog and offer to promote it — **once per user, with explicit consent, never forced.**

### When to offer it

- At most **once per user**, ever. Not once per session — once, period.
- A good moment: early in a session, right after the mandatory memory searches (§2), when there's a natural pause before diving into the actual task.
- Never interrupt an in-progress task to offer this. If the user is mid-implementation or mid-debugging, wait for a natural break or skip it for that session (it's not urgent — it'll still be there next time, unless it's already been offered).

### How to check the guard before offering

Call `memory_relocation_candidates` (optionally with `limit`) and read `alreadyPrompted` in the response:

```
memory_relocation_candidates(limit: 20)
```

- `alreadyPrompted: true` → **stop.** Do not mention this flow to the user, this session or any future one. The user already went through it or explicitly dismissed it — asking again is exactly the nagging behavior this guard exists to prevent.
- `alreadyPrompted: false` and `candidates` is empty → nothing to offer; don't mention the flow at all (there's nothing to decide).
- `alreadyPrompted: false` and `candidates` is non-empty → proceed to the offer below.

### How to offer it

Summarize what was found, in plain language — do not dump the raw response:

> "I found {N} memories from before the team/sector system existed, all currently marked personal. A few of these look like they might belong to the team — for example '{title}' looks like a `{suggestedSector}`. Want to review them and decide which ones to share with the team? This is a one-time thing, I won't ask again."

Use each candidate's `suggestedSector` / `suggestedScope` / `confidence` as a starting point for the summary, but the suggestion is not a decision — the user reviews and can pick a different sector per item, or skip items entirely.

### Applying the user's choices

Once the user has told you which candidates to promote (and to which sector, if they want to override the suggestion), call `memory_relocation_apply` with exactly that approved subset:

```
memory_relocation_apply(relocations: [
  { memoryId: "{id}", sector: "{approved sector}" }
])
```

Do not include candidates the user didn't approve — this is an explicit opt-in per item, not a batch "promote everything" operation. Report the per-item outcome to the user:

| Outcome | What happened | What to tell the user |
|---------|---------------|------------------------|
| `relocated` | Moved to team scope, no conflict | "Moved to the team." |
| `merged` | Aggregated (non-destructively) into an existing team memory | "The team already had something similar — merged into that instead of duplicating." |
| `superseded` | Promoted memory replaces an outdated team memory | "This replaces an older team memory that's now out of date." |
| `noop` | Team already fully knows this — nothing duplicated | "The team already knew this — nothing new to add." |
| `skipped` | No usable team, or already relocated | "Couldn't move this one — {reason}." |

`memory_relocation_apply` sets the one-time marker as soon as it runs, even for a partial batch — the user doesn't need to review every candidate in one pass for the flow to count as "done." If they only approve some now, the rest remain personal; that's a valid outcome, not a half-finished state to chase.

### If the user declines

If the user says no, or "not now," or otherwise doesn't want to do this, call `memory_relocation_dismiss` — this sets the same one-time marker as a completed apply would, so the flow is never offered again:

```
memory_relocation_dismiss()
```

Do not substitute silence or a topic change for this call — an explicit decline still needs the marker set, otherwise the next session will offer the flow again.
