---
name: fenix-memory-protocol
description: Complete memory protocol for AI agents using Fenix. Defines when and how to search, save, and link memories for cross-session continuity.
version: "1.0"
category: methodology
---

# Fenix Memory Protocol

Memories are how context survives between conversations. Without them, every session starts from zero — decisions get repeated, context gets lost, and work gets duplicated.

This skill defines the complete protocol for using Fenix's intelligent memory system (`memory_save` and `memory_search`).

---

## 1. How the Memory System Works

Fenix uses **semantic search powered by AI embeddings** — not keyword matching. This means:

- `"what did we decide about auth?"` finds memories about authentication even if the word "auth" doesn't appear
- Queries should be natural language, not keyword lists
- Results are ranked by semantic similarity with scores

### Auto-deduplication

When you save a memory, Fenix automatically checks for similar existing memories:

- **≥80% similarity** → Updates the existing memory (appends new content with a dated separator)
- **<80% similarity** → Creates a new memory

This means you don't need to worry about creating duplicates. Save freely — the system handles dedup.

### Memory consolidation

When a memory reaches version ≥5 or content ≥8000 characters, Fenix automatically summarizes it to keep it concise. You don't need to manage this.

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
  tags: ["trade-off", "{work-item-key}", "{topic}"]
)
```

### Blockers (save when identified)

When something blocks progress:

```
memory_save(
  title: "Blocker — {short description}",
  content: "## Blocker\n{what's blocking}\n\n## Impact\n{what can't proceed}\n\n## Possible resolutions\n{ideas to unblock}",
  tags: ["blocker", "{work-item-key}"]
)
```

### Implementation context (save when non-obvious)

When you discover something during implementation that would be lost between sessions:

```
memory_save(
  title: "Context — {short description}",
  content: "## What\n{the insight or finding}\n\n## Why it matters\n{how this affects future work}",
  tags: ["context", "{work-item-key}", "{topic}"]
)
```

### Session state (save at conversation end — mandatory)

<EXTREMELY_IMPORTANT>
Before the conversation ends, you MUST save a session state memory. This is the single most important memory you create — it's how the next session picks up where this one left off.
</EXTREMELY_IMPORTANT>

```
memory_save(
  title: "Session State — {WORK-KEY} {short description}",
  content: "## Current position\n{phase: planning/development/review/delivery}\n{current task/story}\n\n## Work completed\n- {item 1}\n- {item 2}\n\n## Decisions made\n- {decision 1} [locked|agent-discretion]\n- {decision 2} [locked|agent-discretion]\n\n## Blockers\n- {blocker or 'None'}\n\n## Next concrete step\n{exactly what to do when resuming — be specific}",
  tags: ["session-state", "{work-item-key}", "{current-phase}"],
  work_item_id: "{uuid}",
  sprint_id: "{uuid if in active sprint}"
)
```

---

## 4. Tag Conventions

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

## 5. Entity Linking

Always link memories to relevant Fenix entities when available:

| Parameter | When to set |
|-----------|-------------|
| `work_item_id` | Working on a specific epic, feature, story, task, or bug |
| `sprint_id` | Working within an active sprint |
| `documentation_item_id` | Memory relates to a documentation page |
| `team_id` | Memory is team-specific (required for multi-team users) |

Entity links enable Fenix to build a knowledge graph — memories connected to work items, sprints, and docs create navigable context across the project.

---

## 6. Search Strategies

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

## 8. Graph Traversal Strategies

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

## 7. Anti-Patterns

| Anti-pattern | Problem | Do this instead |
|-------------|---------|-----------------|
| Saving every small change | Noise drowns out signal | Save decisions, trade-offs, blockers, and session state — not trivial details |
| Using vague titles | Hard to find later | Be specific: "Decision — use PostgreSQL JSONB for dynamic fields" not "Database decision" |
| Skipping entity links | Memories float disconnected | Always link to the work item you're working on |
| Saving implementation details | Code is the source of truth for code | Save the *why*, not the *what*. The code shows what changed; the memory explains why |
| Not searching before saving | Creates duplicates (even with auto-dedup, scattered partial memories are worse than one good one) | Search first, then save or update |
| Giant memory dumps | Hard to search, triggers early consolidation | Keep memories focused. One topic per memory. |
