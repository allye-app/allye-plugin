---
name: memory-protocol
description: Complete memory protocol for AI agents using Allye. Defines when and how to search, save, and link memories for cross-session continuity.
version: "2.3"
category: methodology
---

# Allye Memory Protocol

Memories are how context survives between conversations. Without them, every session starts from zero — decisions get repeated, context gets lost, and work gets duplicated.

This skill defines the complete protocol for using Allye's memory system (`memory_save`, `memory_search`, and the graph/relocation tools built on top of them).

---

## 1. How the memory system works

Allye ranks results by **semantic similarity**, not keyword matching — write queries like you're asking a colleague ("what approach did we choose for handling file uploads"), not searching a database ("file upload decision PROJ-123 architecture storage").

### Memory sectors

Every memory belongs to one of 7 sectors. **Always pass `sector` when saving** — omit it and the server defaults to `knowledge`.

| Sector | Holds | Use it for |
|--------|---------------|------------|
| `decisions` | Technical/product decisions and trade-offs, with rationale | "We chose X over Y because..." |
| `sessions` | Session state and handovers | End-of-session continuity snapshots |
| `patterns` | Reusable patterns and conventions | "Services in this codebase follow..." |
| `incidents` | Bugs, blockers, regressions | "Deploy broke because..." |
| `plans` | Plans and roadmaps | Action plans, milestones, next steps |
| `knowledge` | Reusable learnings and background context (**default**) | Insights, findings, non-obvious constraints |
| `preferences` | Personal preferences | "User prefers conventional commits" — auto-pinned, exempt from decay |

**Scope follows the sector — never pass one explicitly:**

- **Personal** (visible only to you): `sessions`, `preferences`
- **Team** (shared with the active team): `decisions`, `incidents`, `plans`, `patterns`, `knowledge`

Search covers the union of your personal memories and the active team's — never all teams. A team-sector save without a usable active team falls back to personal scope automatically; the save never fails on scope.

`sessions` being personal-only is what makes it the landing zone for raw session consolidation (§4) — nothing durable or team-relevant should stay parked there. The mining step of the /save protocol (§4, Step 2) exists to read a `sessions` memory and decide, sector by sector, what graduates to team knowledge.

### Conflict resolution — not auto-dedup

Every `memory_save` passes through conflict resolution: Allye checks for similar existing memories and a resolver decides the outcome, never a blind "too similar → reject." Every save resolves to exactly one of four outcomes — `created`, `updated`, `superseded`, `noop` — and §4 Step 3 covers how to react to each.

---

## 2. When to search

### Conversation start (mandatory)

<EXTREMELY_IMPORTANT>
At the start of EVERY conversation, run at least these searches before doing anything else:

1. `memory_search(query: "Session State")` — find where the user left off
2. `memory_search(query: "{topic of user's request}")` — find relevant context
3. `memory_search(query: "{work item key}")` — if a specific item is mentioned (e.g., "PROJ-123")
</EXTREMELY_IMPORTANT>

React to what you find: session state → summarize it for the user ("Last time we were working on X, you completed Y, and the next step was Z"); decisions → keep them in mind and respect locked ones; nothing → proceed, noting this is a fresh context.

### Before decisions and implementation

| Moment | Search | Why |
|---|---|---|
| Before choosing an approach | `memory_search(query: "decision {topic}")`, `memory_search(query: "architecture {component}")` | Surfaces prior decisions — some are **locked** (explicitly chosen by the user); deviating from a locked decision **must** be discussed with the user first |
| Before writing code for a task | `memory_search(query: "{task key} implementation")`, `memory_search(query: "{feature name} context")` | Surfaces constraints, dependencies, and past learnings that affect the current work |

---

## 3. When to save

### Save shapes

Every save follows the same call, varying only sector, title prefix, content headers, and tags:

```
memory_save(
  title: "{prefix} — {short description}",
  content: "## {header 1}\n{...}\n\n## {header 2}\n{...}",
  tags: [...],
  sector: "{sector}"
)
```

<!-- adapted from mattpocock/skills writing-great-skills (MIT): duplication cure — one template plus a variant table, instead of four repeated call blocks -->

| Save when | Title prefix | Sector | Content headers | Tags |
|---|---|---|---|---|
| A technical decision is made | `Decision` | `decisions` | Decision / Why / Alternatives rejected / Classification (`locked` or `agent-discretion`) | `decision`, `{work-item-key}`, `{topic}` |
| Trade-offs between approaches are evaluated | `Trade-off` | `decisions` | Options / Analysis / Chosen | `trade-off`, `{work-item-key}`, `{topic}` |
| Something blocks progress | `Blocker` | `incidents` | Blocker / Impact / Possible resolutions | `blocker`, `{work-item-key}` |
| A non-obvious discovery would be lost between sessions | `Context` | `knowledge` | What / Why it matters | `context`, `{work-item-key}`, `{topic}` |

Save decisions and blockers immediately — not batched at session end. **Locked** means the user explicitly chose it, and it stands until the user approves a change. **Agent-discretion** means the agent chose it, and it can be revisited if circumstances change.

### Session state — handled by the /save protocol

<EXTREMELY_IMPORTANT>
Before the conversation ends (or whenever /save is invoked), run the full /save protocol in §4. Session state is not a single ad hoc save — it's the first of four coordinated steps that also promote durable knowledge from the session into team sectors.
</EXTREMELY_IMPORTANT>

---

## 4. The /save protocol

`/save` is a 4-step protocol that turns a session's raw activity into (a) a personal continuity snapshot and (b) correctly-scoped, durable team knowledge. Run all four steps, in order, every time /save is invoked or a conversation is about to end.

### Step 1 — Consolidate the session (sector: `sessions`, personal)

Save exactly ONE memory that summarizes the whole session:

```
memory_save(
  title: "Session State — {WORK-KEY} {short description}",
  content: "## Current position\n{phase: planning/development/review/delivery}\n{current task/story}\n\n## Work completed\n- {item 1}\n- {item 2}\n\n## Decisions made\n- {decision 1} [locked|agent-discretion]\n- {decision 2} [locked|agent-discretion]\n\n## Blockers\n- {blocker or 'None'}\n\n## Next concrete step\n{exactly what to do when resuming — be specific}",
  tags: ["session-state", "{work-item-key}", "{current-phase}"],
  sector: "sessions"
)
```

This memory is the raw material for Step 2 — write it richly (real decisions, real blockers, real next steps). A vague consolidation yields nothing worth promoting.

### Step 2 — Mine the consolidation for promotable knowledge (team sectors, agent discretion)

Re-read the Step 1 content and ask: **is any of this still true and useful outside this conversation?**

Promote when the content is:
- A **decision** with rationale the next session needs to respect → `decisions`
- A **bug, regression, or blocker** with a real cause (not just "task was slow") → `incidents`
- A **plan or roadmap step** that outlives this session → `plans`
- A **reusable convention or pattern** discovered or confirmed while working → `patterns`
- A **non-obvious constraint or insight** that would surprise someone starting fresh → `knowledge`

Skip anything that just restates the diff/commit, routine progress with no durable lesson, content an existing team memory already covers (search before promoting, same as any save), or content that only makes sense inside this specific conversation.

Each promoted item is its own `memory_save` call — one topic per memory, sector matched to content type, tags per §5. A session with zero promotable content is normal; don't force a promotion just to have one.

### Step 3 — React to the outcome

Both the Step 1 consolidation and every Step 2 promotion resolve to one of the four outcomes from §1. React accordingly — none of these is an error to work around:

| Outcome | What happened | What you do |
|---------|---------------|--------------|
| `created` | No meaningful overlap found; a new memory was created | Nothing — proceed |
| `updated` | Existing memory was close enough to aggregate; it was updated in place | Nothing — the existing memory now holds both old and new content |
| `superseded` | New content invalidates the old; a new memory was created and the old one marked superseded (not deleted) | Nothing — expected when a decision changes or a plan is revised |
| `noop` | Content is already fully covered; nothing was written | Stop. Use the returned existing memory as the source of truth instead of rewording and retrying |

Rewording the same content to force past a `noop` means the content wasn't new — trust the resolver.

### Step 4 — Promote surviving todos (`productivity`, personal)

Some agents keep a scratch task list for the turn — read the file, run the test, commit.
It is the right tool for that and it dies with the session, which is also right.

Ask the same question Step 2 asks of the session: **would this still matter tomorrow?**

**Promote when the item is:**
- A follow-up nobody has scheduled — "the migration needs a rollback path before it ships"
- A discovery that costs time every time it is rediscovered — "the app build fails without an
  explicit install because the runtime is at a non-default path"
- Work the session surfaced but deliberately did not do

**Do NOT promote:**
- Any step of the work just completed. "Run the tests" is not a TODO, it is a thing that happened.
- Anything already captured as a work item — `productivity` is personal follow-up, not a
  second work tracker. If it belongs to a story, it belongs in the story.

```
todo_create(
  title: "{the follow-up, stated as an outcome}",
  content: "## What\n{what needs doing}\n\n## Why it surfaced\n{the session context that produced it}",
  priority: "{low|medium|high|urgent}"
)
```

Zero promotions is the normal outcome. A session whose every scratch item was a step of the
work it just finished has nothing to promote, and forcing one turns a personal list of real
commitments into a log of completed steps — which is what makes such lists get ignored.

---

## 5. Tag conventions

Consistent tags keep memories findable.

### Phase

| Tag | When |
|-----|-------------|
| `planning` | During product or technical planning |
| `development` | During implementation |
| `review` | During code review |
| `delivery` | During finalization and delivery |

### Work item

Use the key as-is (`PROJ-123`, `FEAT-45`, `TASK-67`); for hierarchical context, prefix with type: `epic:PROJ-100`, `feature:PROJ-110`, `story:PROJ-123`.

### Topic

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

### Content type

| Tag | Marks |
|-----|---------------|
| `decision` | A choice that was made with rationale |
| `trade-off` | An evaluated comparison between options |
| `blocker` | Something preventing progress |
| `context` | Background information or insight |
| `session-state` | End-of-session continuity snapshot |

---

## 6. Search strategies

| Strategy | Use when | Example |
|---|---|---|
| Broad discovery | Not sure what exists | `memory_search(query: "{general topic}", limit: 10)` |
| Targeted retrieval | You know what you're looking for | `memory_search(query: "Decision — authentication middleware for {project}")` |
| Multi-angle | Complex topics — run several searches | `memory_search(query: "Session State PROJ-123")`, then `memory_search(query: "decision PROJ-123")`, then `memory_search(query: "architecture {module name}")` |

---

## 7. Anti-patterns

| Anti-pattern | Problem | Do this instead |
|-------------|---------|-----------------|
| Saving every small change | Noise drowns out signal | Save decisions, trade-offs, blockers, and session state — not trivial details |
| Using vague titles | Hard to find later | Be specific: "Decision — use PostgreSQL JSONB for dynamic fields" not "Database decision" |
| Saving implementation details | Code is the source of truth for code | Save the *why*, not the *what* |
| Not searching before saving | Creates near-duplicates that conflict resolution then has to untangle | Search first, then save |
| Giant memory dumps | Hard to search, and content is capped at 10000 characters | One topic per memory |

---

## 8. Graph traversal

The memory graph connects memories through explicit relation edges created at save time. Use it to find related context semantic search misses.

| Tool | Use when |
|----------|----------|
| `memory_search(query)` | You know *what* you're looking for |
| `memory_graph(memory_id, depth: 2)` | You have an ID and want to explore its neighborhood |
| `memory_relations(memory_id)` | A quick 1-hop check of a specific memory |
| `memory_search(query, include_graph: true)` | Search + graph context in one call |

**Context recovery.** At session start, after finding the session state memory: `memory_search(query: "Session State {work key}")` to get its ID, then `memory_graph(memory_id: "{id}", depth: 2)` to explore connected decisions, trade-offs, and blockers from past sessions.

**Decision cluster.** `memory_graph(memory_id: "{decision memory ID}", depth: 2, relation_types: ["extends", "depends_on", "supersedes"])`.

**Reading results.** Depth 0 is the root memory; depth 1 is directly connected; depth 2+ is transitive and can grow fast — bound it with `relation_types` or `graph_limit`. `relation_types` is a free-form string, not a fixed enum — `extends`, `depends_on`, and `supersedes` are examples, not the full set.

**On a 408 timeout** from `memory_graph` or `memory_relations`: reduce `depth` (try 1), add `relation_types` to narrow traversal, or add `graph_limit` to cap nodes returned.

---

## 9. Relocation flow (opt-in, one-time)

Before F1 shipped sector/scope, memories had neither concept. The backfill that introduced them landed every pre-existing memory as `scope: personal, sector: knowledge` — a safe default, not necessarily the right one. Some of that content is really team knowledge (a decision, a pattern, an incident) that predates the sector system and never got the chance to be shared.

The relocation flow surfaces that backlog and offers to promote it — **once per user, with explicit consent, never forced.**

### When to offer it

Offer at most once per user, ever — not once per session. A good moment is early in a session, right after the mandatory memory searches (§2), at a natural pause before the actual task. Never interrupt an in-progress task to offer this; if the user is mid-implementation or mid-debugging, wait for a natural break or skip it for that session — it isn't urgent, and it'll still be there next time unless already offered.

### Check the guard first

```
memory_relocation_candidates(limit: 20)
```

Read `alreadyPrompted` in the response:

- `true` → stop. The user already went through this flow or dismissed it — don't mention it, this session or any future one.
- `false` and `candidates` empty → nothing to offer; don't mention the flow.
- `false` and `candidates` non-empty → make the offer below.

### Make the offer

Summarize what was found in plain language, using each candidate's `suggestedSector` / `suggestedScope` / `confidence` as a starting point — the suggestion is not a decision, the user reviews and can pick a different sector per item or skip items entirely:

> "I found {N} memories from before the team/sector system existed, all currently marked personal. A few of these look like they might belong to the team — for example '{title}' looks like a `{suggestedSector}`. Want to review them and decide which ones to share with the team? This is a one-time thing, I won't ask again."

### Apply the user's choices

Once the user has told you which candidates to promote (and to which sector, if overriding the suggestion), call `memory_relocation_apply` with exactly that approved subset — never a batch "promote everything":

```
memory_relocation_apply(relocations: [
  { memoryId: "{id}", sector: "{approved sector}" }
])
```

Report the per-item outcome:

| Outcome | What happened | Tell the user |
|---------|---------------|------------------------|
| `relocated` | Moved to team scope, no conflict | "Moved to the team." |
| `merged` | Aggregated (non-destructively) into an existing team memory | "The team already had something similar — merged into that instead of duplicating." |
| `superseded` | Promoted memory replaces an outdated team memory | "This replaces an older team memory that's now out of date." |
| `noop` | Team already fully knows this — nothing duplicated | "The team already knew this — nothing new to add." |
| `skipped` | No usable team, or already relocated | "Couldn't move this one — {reason}." |

`memory_relocation_apply` sets the one-time marker as soon as it runs, even for a partial batch — the user need not review every candidate in one pass. Unapproved candidates simply remain personal; that's a valid outcome, not a half-finished state to chase.

### If the user declines

Call `memory_relocation_dismiss()` — this sets the same one-time marker a completed apply would, so the flow is never offered again. An explicit decline still needs the marker set; silence or a topic change doesn't substitute for the call.
