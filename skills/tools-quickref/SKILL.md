---
name: tools-quickref
description: Complete quick reference for all Allye MCP tools and their actions with parameters. Use when you need to know how to call a specific Allye tool.
version: "1.0"
category: reference
---

# Allye Tools Quick Reference

Complete reference for all 12 Allye MCP tools and their actions.

---

## work_items

Manage work items: epics, features, stories, tasks, and bugs.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `work_create` | Create a single work item | `title`*, `item_type`*, `work_category`, `description`, `parent_key`, `priority`, `story_points` |
| `work_list` | List/search work items | `query`, `item_type`, `status_category`, `limit`, `offset` |
| `work_get` | Get a work item by ID or key | `id` or `key`* |
| `work_update` | Update a work item | `id`*, `title`, `description`, `priority`, `story_points` |
| `work_children` | List child items of a parent | `id`* |
| `work_assign_to_me` | Assign a work item to yourself | `id`* |
| `work_status_next` | Move to next status in board progression | `id`* |
| `work_status_done` | Move directly to done status | `id`* |
| `work_mine` | List items assigned to you | `status_category`, `item_type`, `limit` |
| `work_bulk_create` | Create multiple items at once (max 50) | `items`* (array with `temp_id`, `title`, `item_type`, `work_category`, `parent_temp_id` or `parent_key`) |
| `work_statuses` | List all available statuses | — |

**Item types:** `epic`, `feature`, `story`, `task`, `bug`
**Priority values:** `critical`, `high`, `medium`, `low`
**Status categories:** `backlog`, `todo`, `in_progress`, `testing`, `review`, `deploying`, `done`, `cancelled`

---

## boards

View boards and understand status progression.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `board_list` | List all boards | `limit` |
| `board_favorites` | List favorite boards | — |
| `board_get` | Get board details | `id`* |
| `board_columns` | Get board columns with statuses | `id` (optional — defaults to team's primary board) |

---

## sprints

Manage sprint cycles.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `sprint_list` | List all sprints | `limit`, `status` |
| `sprint_active` | Get the currently active sprint | — |
| `sprint_get` | Get sprint details | `id`* |
| `sprint_work_items` | List work items in a sprint | `id`*, `limit` |

---

## docs

Documentation pages and folders with tree navigation.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `doc_create` | Create a document | `doc_title`*, `doc_type`* (`folder`/`page`/`api_doc`/`guide`), `doc_emoji`*, `doc_content`, `doc_parent_id` |
| `doc_list` | List documents | `limit`, `offset` |
| `doc_get` | Get document by ID | `id`*, `return_content` |
| `doc_update` | Update a document | `id`*, `doc_title`, `doc_content`, `doc_description` |
| `doc_delete` | Delete a document | `id`* |
| `doc_roots` | List root-level documents | — |
| `doc_recent` | List recently modified documents | `limit` |
| `doc_analytics` | Get document analytics | `id`* |
| `doc_children` | List children of a document | `id`* |
| `doc_tree` | Get document tree from a root | `id`* |
| `doc_full_tree` | Get the entire document tree | — |
| `doc_move` | Move a document | `id`*, `doc_parent_id`, `doc_position` |
| `doc_publish` | Publish a document | `id`* |
| `doc_version` | Create a version snapshot | `id`*, `doc_version` |
| `doc_duplicate` | Duplicate a document | `id`* |

**Doc types:** `folder`, `page`, `api_doc`, `guide`

---

## intelligence

Semantic memory system for cross-session continuity.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `memory_save` | Save a memory (auto-deduplicates via graph) | `title`*, `content`* (markdown), `tags`* (array), `work_item_id`, `sprint_id`, `documentation_item_id`, `team_id` |
| `memory_search` | Semantic search for memories | `query`* (natural language), `limit` (1-20), `tags`, `include_graph` (bool), `graph_depth` (1-5), `return_content` (bool), `team_id` |
| `memory_graph` | BFS graph traversal from a memory node | `memory_id`* (UUID), `depth` (1-5, default 1), `relation_types` (filter), `include_invalidated` (bool), `graph_limit` (1-200) |
| `memory_relations` | 1-hop direct relations of a memory | `memory_id`* (UUID), `direction` (outgoing\|incoming\|both), `relation_types`, `include_invalidated` (bool) |

**Memory save behavior (F3):**
- `action: "created"` — saved (new or superseded an existing)
- `action: "rejected"` — exact duplicate (≥95% similarity), not saved; response includes the existing `memoryId`
- `links[]` — graph edges auto-created on save (targetId, relationType, strength)
- Auto-consolidation at version ≥5 or content ≥8000 chars

**Search behavior:**
- Uses AI embeddings, NOT keyword matching
- Write queries like natural language, not keyword lists
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

Personal TODO management.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `todo_create` | Create a TODO | `todo_title`*, `todo_description`, `todo_priority`, `todo_due_date`, `todo_category`, `todo_tags` |
| `todo_list` | List TODOs | `todo_status`, `todo_category`, `todo_priority`, `limit` |
| `todo_get` | Get TODO by ID | `id`* |
| `todo_update` | Update a TODO | `id`*, `todo_title`, `todo_completed`, `todo_priority` |
| `todo_delete` | Delete a TODO | `id`* |
| `todo_stats` | Get TODO statistics | — |
| `todo_search` | Search TODOs | `query`* |
| `todo_overdue` | List overdue TODOs | — |
| `todo_upcoming` | List upcoming TODOs | — |
| `todo_categories` | List available categories | — |
| `todo_tags` | List used tags | — |
| `todo_help` | Show TODO help | — |

---

## skills

Manage and export workflow skills.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `skill_create` | Create a skill | `skill_name`*, `skill_category`*, `skill_content`, `skill_description`, `skill_scope` |
| `skill_list` | List/search skills | `query`, `skill_category`, `limit` |
| `skill_get` | Get skill by ID | `id`* |
| `skill_update` | Update a skill | `id`*, `skill_name`, `skill_content`, `skill_description` |
| `skill_delete` | Delete a skill | `id`* |
| `skill_marketplace` | Browse marketplace skills | `query`, `skill_category` |
| `skill_fork` | Fork a marketplace skill | `skill_id`* |
| `skill_export` | Export a skill in agent format | `id`*, `skill_export_format`* |
| `skill_import_github` | Import skill from GitHub | `repo_url`* |
| `skill_install` | Install a skill | `skill_id`* |
| `skill_export_merged` | Export multiple skills merged | `skill_ids`*, `skill_export_format`* |

**Export formats:** `cursor`, `claude`, `copilot`, `windsurf`
**Skill categories:** `frontend`, `backend`, `mobile`, `fullstack`, `devops`, `infrastructure`, `architecture`, `code_review`, `testing`, `security`, `documentation`, `performance`, `other`

---

## team

Team management and switching.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `team_help` | Show team management help | — |
| `team_switch` | Switch active team | `team_query`* (team name) |
| `team_list` | List available teams | — |
| `team_current` | Show current active team | — |

---

## user_config

Personal configuration documents.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `create` | Create a config document | `title`*, `content`* |
| `list` | List config documents | — |
| `get` | Get config document | `id`* |
| `update` | Update config document | `id`*, `title`, `content` |
| `delete` | Delete config document | `id`* |
| `help` | Show help | — |

---

## api_catalog

Browse API endpoint documentation.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `api_catalog_search` | Search API endpoints | `query`* |
| `api_catalog_list` | List all endpoints | `limit`, `offset` |
| `api_catalog_get` | Get endpoint details | `id`* |

---

## initialize

Bootstrap Allye environment.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `init` | Initialize/reload Allye environment and documents | — |

---

## health

Service monitoring.

| Action | Description |
|--------|-------------|
| `health_check` | Check Allye backend health status |

---

## Common Patterns

### Create a full work item hierarchy

```
1. work_create(title: "Epic", item_type: "epic")       → get epic key
2. work_bulk_create(items: [features + stories])         → parent_key: epic key
```

### Track progress on a task

```
1. work_get(key: "TASK-123")                            → read task details
2. work_status_next(id: "...")                           → move to in_progress
3. ... do the work ...
4. work_status_done(id: "...")                           → mark complete
```

### Find and resume previous work

```
1. memory_search(query: "Session State")                → find last session
2. work_mine(status_category: "in_progress")            → find active items
3. work_get(id: "...")                                   → load item details
```

### Create documentation for a feature

```
1. doc_full_tree()                                       → find where to place it
2. doc_create(doc_title: "...", doc_type: "page", doc_emoji: "📄", doc_parent_id: "...")
```
