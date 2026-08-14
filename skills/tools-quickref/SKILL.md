---
name: tools-quickref
description: Complete quick reference for all Allye MCP tools and their actions with parameters, plus the concrete gotchas that cause silent failures or confusing errors. Use when you need to know how to call a specific Allye tool, or you hit an unexpected error/behavior from one.
version: "2.3"
category: reference
---

# Allye Tools Quick Reference

---

## Gotchas (read this first if something didn't work as expected)

<!-- mined directly from the allye-mcp source, not guessed — see allye_mcp/application/tools/*.py -->

- **`work_create`/`work_bulk_create` require `work_category`**, even though it looks optional next to `item_type`. Omit it and the call fails, listing the full valid-category enum back to you (see below).
- **Item types include more than the obvious five**: `epic`, `feature`, `story`, `bug`, `hotfix`, `task`, `spike`, `subtask` — not just epic/feature/story/task/bug.
- **Assigning to someone else is two calls, not one.** `work_assign_to_me` only covers yourself. For anyone else: `team_members` (via `team`) to resolve their user id, then `work_update(id, assignee_id: "<their id>")`.
- **`work_update(id, work_status: "<status uuid>")` jumps directly to any status in one call** — not limited to one step forward. Fixed in allye-mcp commit `b9b6281` (2026-06-15, `develop`) after being a silent no-op; if a memory or doc claims status/assignee can't be set via `work_update`, that's stale. `work_status_next`/`work_status_done` remain valid for stepwise or done-jump flows; `work_update` is the direct alternative when you already know the target status id.
- **`work_update` still does NOT accept `parent_key`/`parent_id`.** Re-parenting is create-time only (`work_create`, `work_bulk_create`) — the `work_update` action in `work_items.py` never reads `payload.parent_key`, so passing it is silently ignored, not an error. Don't assume the 2026-06-15 status/assignee fix extended to parent.
- **`work_status_next` moves forward only.** It errors if the item is already at the last status in the board's progression, and there's no `work_status_prev`. Use `work_status_done` to jump straight to done regardless of current position, or `work_update(work_status: ...)` to jump to any specific status. See the `allye-board-progression` skill for the full resolution logic.
- **`work_bulk_create` caps at 50 items per call**, and each item takes `parent_temp_id` (reference another item in the same batch) **or** `parent_key` (reference an existing item) — never both on the same item.
- **`doc_create` needs `doc_emoji`** for every type except `folder` — check `doc_full_tree` for placement before creating, always; don't guess a parent location.
- **`memory_save` never silently fails or duplicates.** Every save resolves to one of four outcomes (`created`/`updated`/`superseded`/`noop` — see §intelligence). Treat `noop` as "already known," not an error to reword-and-retry past.
- **`memory_save` does not link a memory to a work item.** There is no `work_item_id` or `sprint_id` parameter — not on the MCP tool (`IntelligenceRequest`), not in its domain layer, and not on the backend's `SaveMemoryDto`. Passing them is silently discarded, not an error. To make a memory findable from a work item, put the key in `tags` and in the `title`.
- **Memory `sector` determines scope automatically — you never set scope directly** (mapping in §intelligence). Passing it wrong is the #1 way a memory ends up invisible to the rest of the team.
- **The memory relocation flow is one-time per user, ever** — always check `alreadyPrompted` on `memory_relocation_candidates` before offering it; offering it twice is exactly the nagging behavior the guard exists to prevent.
- **`initialize` returns `profile.user.id`** — the reliable way to know "who's currently logged in" when deciding self-assignment vs. assigning to someone else.
- **`work_statuses` omits `position`, `pipeline`, and `description`.** All three exist on the
  record — `allye-api/prisma/seed-workflow.ts` writes them — but the MCP formatter
  (`allye_mcp/application/tools/work_items.py:590-597`) emits only name, key, id, and colour.
  You therefore cannot compute a status's place in the pipeline, nor tell a `product` status
  from an `engineering` one, from this call.
- **`board_columns` gives no status mapping and no ordering.** Names and ids only. Since
  `work_status_next` walks the board's visible ordered statuses, the transition it will make
  cannot be predicted from the MCP surface. **Move one status, then read the item back.**
- **`team_switch` does not stick for every tool.** It reports that subsequent calls will use
  the chosen team, but `work_children` still errors with "Team selection required", and
  `work_list` returns items across teams. Pass `team_id` explicitly on any call whose result
  must be team-scoped.

For the full memory methodology (when to search, when to save, sector selection, the `/save` protocol, graph traversal), see the `allye-memory-protocol` skill — this file only covers the action-level API surface.

---

## work_items

Manage work items: epics, features, stories, tasks, bugs, hotfixes, spikes, subtasks.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `work_create` | Create a single work item | `work_title`*, `work_type`*, `work_category`*, `work_description`, `parent_key`, `work_priority`, `story_points` |
| `work_list` | List/search work items | `query`, `work_type`, `work_status` (status UUID — look up via `work_statuses()` first), `limit`, `offset` |
| `work_get` | Get a work item by ID or key | `id` or `work_key`* |
| `work_update` | Update a work item | `id`*, `work_title`, `work_description`, `work_priority`, `story_points`, `assignee_id`, `work_status` (status UUID — jumps straight to that status, any distance, not just one step), `work_due_date`, `work_tags`. **Not accepted:** `parent_key`/`parent_id` — re-parenting is create-time only |
| `work_children` | List child items of a parent | `id`* |
| `work_assign_to_me` | Assign a work item to yourself | `id`* |
| `work_status_next` | Move to next status in board progression (forward-only, errors at the last status) | `id`* |
| `work_status_done` | Move directly to done status | `id`* |
| `work_mine` | List items assigned to you | `limit`, `offset` (no status or item-type filter — not exposed by this action) |
| `work_bulk_create` | Create multiple items at once (max 50) | `work_items`* (array with `temp_id`, `title`, `item_type`, `work_category`, `parent_temp_id` **or** `parent_key`) |
| `work_statuses` | List all available statuses | — |

**Item types:** `epic`, `feature`, `story`, `bug`, `hotfix`, `task`, `spike`, `subtask`
**Priority values:** `critical`, `high`, `medium`, `low`
**Status categories:** `backlog`, `todo`, `in_progress`, `testing`, `review`, `deploying`, `done`, `cancelled`
**`work_category` is required on every create call** — values: `backend`, `frontend`, `mobile`, `fullstack`, `devops`, `infra`, `platform`, `sre`, `database`, `security`, `data`, `analytics`, `ai_ml`, `qa`, `automation`, `design`, `research`, `product`, `project`, `agile`, `support`, `operations`, `documentation`, `training`, `architecture`, `planning`, `development`

---

## boards

View boards and understand status progression.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `board_list` | List all boards | `limit`, `offset` |
| `board_favorites` | List favorite boards | — |
| `board_get` | Get board details | `board_id`* |
| `board_columns` | Get board columns with statuses | `board_id`* |

---

## sprints

Manage sprint cycles.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `sprint_list` | List all sprints | `limit`, `offset` (no `status` filter — not exposed by this action) |
| `sprint_active` | Get the currently active sprint | — |
| `sprint_get` | Get sprint details | `sprint_id`* |
| `sprint_work_items` | List work items in a sprint | `sprint_id`* |

---

## docs

Documentation pages and folders with tree navigation.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `doc_create` | Create a document | `doc_title`*, `doc_emoji`* (required unless `doc_type` is `folder`), `doc_type` (`folder`/`page`/`api_doc`/`guide`, defaults to `page` if omitted), `doc_content`, `doc_parent_id` |
| `doc_list` | List documents | `limit`, `offset` |
| `doc_get` | Get document by ID | `id`* (always returns full content — `return_content` has no effect on this action) |
| `doc_update` | Update a document | `id`*, `doc_title`, `doc_content`, `doc_description` |
| `doc_delete` | Delete a document | `id`* |
| `doc_roots` | List root-level documents | — |
| `doc_recent` | List recently modified documents | `limit` |
| `doc_analytics` | Get document analytics (team-wide only, not per-document) | `team_id` (optional) |
| `doc_children` | List children of a document | `id`* |
| `doc_tree` | Get document tree from a root | `id`* |
| `doc_full_tree` | Get the entire document tree | — |
| `doc_move` | Move a document | `id`*, `doc_parent_id`, `doc_position` |
| `doc_publish` | Publish a document | `id`* |
| `doc_version` | Create a version snapshot | `id`*, `doc_version`* |
| `doc_duplicate` | Duplicate a document | `id`*, `doc_title`* |

**Doc types:** `folder`, `page`, `api_doc`, `guide`

---

## intelligence

Semantic memory system for cross-session continuity. **Full methodology (when/what to save, sector selection, the `/save` protocol) lives in the `allye-memory-protocol` skill — this is the action-level reference only.**

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `memory_save` | Save a memory (conflict-resolved, never a blind duplicate) | `title`*, `content`* (markdown), `tags`* (array), `sector` (default `knowledge`) |
| `memory_search` | Semantic search for memories | `query`* (natural language), `limit` (1-20), `tags`, `sector`, `scope` (`personal`\|`team`), `include_graph` (bool), `graph_depth` (1-5), `return_content` (bool) |
| `memory_graph` | BFS graph traversal from a memory node | `memory_id`* (UUID), `depth` (1-5, default 1), `relation_types` (filter), `include_invalidated` (bool), `graph_limit` (1-200) |
| `memory_relations` | 1-hop direct relations of a memory | `memory_id`* (UUID), `direction` (outgoing\|incoming\|both), `relation_types`, `include_invalidated` (bool) |
| `memory_preferences` | Load the user's pinned `preferences`-sector memories (not a search — fixed budget, no query needed) | — |
| `memory_relocation_candidates` | Step 1 of the one-time personal→team relocation flow — lists pre-sector-system memories with suggestions | `limit`, `offset` |
| `memory_relocation_apply` | Step 2 — apply the user-approved subset of relocation candidates | `relocations`* (array of `{memoryId, sector, teamId?}`) |
| `memory_relocation_dismiss` | "Not now" path for the relocation flow — sets the one-time marker without moving anything | — |

**Sectors** (pass `sector` on every save — omitting it defaults to `knowledge`, which is rarely what you want): `decisions`, `sessions`, `patterns`, `incidents`, `plans`, `knowledge`, `preferences`. Scope is derived automatically: `sessions`/`preferences` are always personal; the other five are always team — there is no separate `scope` parameter on save.

**`memory_save` outcomes** — every save resolves to exactly one of these (no blind-reject-by-similarity):
- `created` — new, independent memory
- `updated` — non-destructive merge into an existing memory
- `superseded` — new memory created, old one invalidated (kept for audit)
- `noop` — already fully captured; nothing written, response points at the existing memory

**Search behavior:**
- Uses AI embeddings, NOT keyword matching — write queries like natural language, not keyword lists
- Results ranked by semantic similarity
- `include_graph=true` returns `relatedMemories[]` alongside each result (1-hop neighbors)
- `return_content=false` by default (2-phase retrieval — metadata only, faster)

**Graph traversal tips:**
- After `memory_search`, use `memory_graph(memory_id, depth: 2)` to explore connected context
- Use `memory_relations` for a quick 1-hop check (faster than BFS)
- If timeout (408): reduce `depth`, add `relation_types` filter, or add `graph_limit`
- Relation types: `similar | extends | caused_by | supersedes | contradicts | depends_on`

---

## productivity

Personal TODO management. **The `todo_` prefix is only on action names — the fields themselves are NOT prefixed** (it's `title`/`content`, not `todo_title`/`todo_description`).

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `todo_create` | Create a TODO | `title`*, `content`* (markdown, required — not optional), `status`, `priority`, `category`, `tags`, `due_date` |
| `todo_list` | List TODOs (no status filter → returns pending + in_progress merged, not everything) | `status`, `category`, `priority`, `limit`, `offset` |
| `todo_get` | Get TODO by ID | `id`* |
| `todo_update` | Update a TODO | `id`*, `title`, `content`, `status`, `priority`, `category`, `tags`, `due_date` |
| `todo_delete` | Delete a TODO | `id`* |
| `todo_stats` | Get TODO statistics | — |
| `todo_search` | Search TODOs | `query`* |
| `todo_overdue` | List overdue TODOs | — |
| `todo_upcoming` | List upcoming TODOs | `days` (1-30) |
| `todo_categories` | List available categories | — |
| `todo_tags` | List used tags | — |
| `todo_help` | Show TODO help | — |

**`status` values:** `pending` (shown as "backlog" in the UI), `in_progress`, `completed`, `cancelled` — there is no separate boolean "completed" flag, status IS the completion state.
**`priority` values:** `low`, `medium`, `high`, `urgent`.

---

## skills

Manage and export workflow skills.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `skill_create` | Create a skill | `skill_name`*, `skill_content`*, `skill_scope`*, `skill_category`*, `skill_description`, `skill_slug` (auto-generated if omitted), `skill_team_id` (required when `skill_scope: "team"`) |
| `skill_list` | List/search skills | `query`, `skill_scope`, `limit`, `offset` |
| `skill_get` | Get skill by ID | `skill_id`* or `id`* |
| `skill_update` | Update a skill | `skill_id`* or `id`*, `skill_name`, `skill_content`, `skill_description`, `skill_category`, `skill_is_active` |
| `skill_delete` | Delete a skill | `skill_id`* or `id`* |
| `skill_marketplace` | Browse marketplace skills | `query`, `limit`, `offset` |
| `skill_fork` | Fork a readable source skill into an independent internal draft | `skill_id`* or `id`*, `skill_scope`*, `skill_slug` (explicit namespace key; required to retry a collision), `skill_name`, `skill_category` (scope only `personal`/`team`/`organization` — no `marketplace`) |
| `skill_export` | Export a skill in agent format | `skill_id`* or `id`*, `skill_export_format`* |
| `skill_import_github` | Import skill from GitHub | `repo_url`* |
| `skill_install` | Install a skill | `skill_id`* or `id`* |
| `skill_export_merged` | Export multiple skills merged | `skill_ids`*, `skill_export_format`* |

**`skill_create` requires all three of `skill_content`, `skill_scope`, and `skill_category`** — easy to miss since only `skill_name` reads as obviously required. Write scopes are only `personal`, `team`, and `organization`; `marketplace` is legacy read-only browsing/source material and must never be sent as a create, import, update, fork target, publication, or rating destination.

For shared writes, the API is authoritative: the authenticated actor must be the container owner/admin, have tenant-scoped `skills:manage`, or hold an active maintainer grant. Membership gives read access, not write access. Team writes require the selected active team (`team_id`/request context); personal and organization writes do not. Use `skill_resolve` for canonical `team > organization > personal` resolution and honor its `candidates`, `selected`, `owner`, `rule`, `reason`, and `conflict` fields.

Forks are independent drafts with `forked_from_id`, a new author, no copied grants, and preserved source provenance when available. If a fork returns `409 Conflict`, choose a different explicit `skill_slug` and retry; never silently suffix or overwrite a namespace. Marketplace can be browsed and used as readable source material for an internal fork, but it is never an internal write scope.

**Export formats:** `cursor`, `claude`, `copilot`, `windsurf`, `opencode`, `codex`, `gemini`
**Skill scopes (create/import/fork):** `personal`, `team`, `organization` (never `marketplace`)
**Skill categories:** `frontend`, `backend`, `mobile`, `fullstack`, `devops`, `infrastructure`, `architecture`, `code_review`, `testing`, `security`, `documentation`, `performance`, `other`

---

## team

Team management, switching, and member lookup.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `team_help` | Show team management help | — |
| `team_switch` | Switch active team | `team_query`* (name, prefix, or ID — partial match supported) |
| `team_list` | List available teams | — |
| `team_current` | Show current active team | — |
| `team_members` | List active members of a team — **the way to resolve a user id for `work_update(assignee_id: ...)`** | `team_query` (optional — defaults to the active team) |

---

## user_config

Personal configuration documents ("Core Documents"). **The title field is `name`, not `title`** — a common mix-up since every other tool in this reference uses `title`.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `create` | Create a config document | `name`*, `content`*, `mode_id`, `is_default`, `metadata` |
| `list` | List config documents | `limit`, `offset`, `return_content` |
| `get` | Get config document | `id`* |
| `update` | Update config document | `id`*, `name`, `content`, `mode_id`, `is_default`, `metadata` |
| `delete` | Delete config document | `id`* |
| `help` | Show help | — |

---

## api_catalog

Browse API endpoint documentation.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `api_catalog_search` | Search API endpoints | `query`* |
| `api_catalog_list` | List all endpoints | `limit`, `offset` |
| `api_catalog_get` | Get endpoint details | `api_spec_id`* or `id`* |

---

## initialize

Bootstrap Allye environment.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `init` | Initialize/reload Allye environment, profile, and core documents. Returns `profile.user.id` — the way to resolve "who's logged in" | `include_user_docs` (bool, default `true` — set `false` for a lighter payload when you don't need personal documents) |

---

## health

**Not an action-based tool** — unlike everything else in this reference, there's no `action` parameter and no sub-actions. The tool itself is the check.

| Tool name | Description | Parameters |
|-----------|-------------|------------|
| `allye_health_check` | Check Allye backend health status | none |

---

## Common Patterns

### Create a full work item hierarchy

```
1. work_create(work_title: "Epic", work_type: "epic")   → get epic key
2. work_bulk_create(work_items: [features + stories])    → parent_key: epic key
```

### Track progress on a task

```
1. work_get(work_key: "TASK-123")                        → read task details
2. work_status_next(id: "...")                           → move to in_progress
3. ... do the work ...
4. work_status_done(id: "...")                           → mark complete
```

Stepwise `work_status_next` is still the right default while work is actually progressing through each stage. To jump straight to a known target instead — correcting a status that's out of sync, for example — use `work_update(id: "...", work_status: "<target status uuid>")` from `work_statuses()` (see the Gotchas entry above).

### Find and resume previous work

```
1. memory_search(query: "Session State")                → find last session
2. work_mine()                                           → find active items (no status/type filter available)
3. work_get(id: "...")                                   → load item details
```

### Create documentation for a feature

```
1. doc_full_tree()                                       → find where to place it
2. doc_create(doc_title: "...", doc_type: "page", doc_emoji: "📄", doc_parent_id: "...")
```
