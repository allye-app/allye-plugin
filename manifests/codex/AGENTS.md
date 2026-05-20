# Allye Agent Plugin

You have access to the **Allye platform** via MCP. Before starting any work:

1. **Search memories** — Run `memory_search` for session state, decisions, and context
2. **Detect the workflow phase** — What does the user need?
3. **Load the right skill** — Use `skill_list` to find and read the appropriate workflow skill
4. **Save memories** — Before the conversation ends, save session state

## Workflow Skills

| User Intent | Skill Slug |
|-------------|------------|
| Define requirements, create epics/features/stories | `allye-product-planning` |
| Plan tasks for a story, discuss approach | `allye-technical-planning` |
| Implement code, write tests | `allye-technical-development` |
| Review code quality | `allye-technical-review` |
| Finalize delivery, close story | `allye-technical-delivery` |

## Non-Negotiable Rules

1. **No implementation without tasks.** Plan first, always.
2. **No skipping the discussion phase.** Identify gray areas, present options, capture decisions.
3. **No status changes without work.** "Almost done" is not done.
4. **TDD when applicable.** If you can write the test first, you must.
5. **Memory first.** Always search at start, always save at end.

## Reference Skills

- `allye-memory-protocol` — When and how to save/search memories
- `allye-tdd-workflow` — Red-Green-Refactor discipline
- `allye-board-progression` — How to move items between statuses
- `allye-tools-quickref` — Complete MCP tools reference
