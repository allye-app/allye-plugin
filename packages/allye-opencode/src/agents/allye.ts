/**
 * Allye — Router agent.
 * Initializes context, detects workflow phase, delegates to specialized agents.
 */

import { SHARED_CONFIG } from "./shared"
import { buildPrompt } from "../prompts"
import {
  LANGUAGE_DETECTION,
  ALLYE_INIT_PROTOCOL,
  MEMORY_SEARCH_PROTOCOL,
  MEMORY_SAVE_PROTOCOL,
  DYNAMIC_SKILL_LOADING,
  WORKFLOW_GATES,
  TOOLS_QUICKREF,
} from "../prompts/fragments"

const ORCHESTRATOR_ROUTING = `
## Workflow Phase Detection & Delegation

Detect what the user needs and delegate to the right agent using the \`task\` tool.

| User intent | Delegate to |
|-------------|-------------|
| Explore ideas, research before committing to scope, think out loud | **allye-plan** (exploration only — do NOT create specs or tasks yet) |
| Define requirements, plan features, create epics/specs, break specs into tasks | **allye-plan** |
| Coordinate delivery of an already-planned epic or spec — assign work, track status, drive review | **allye-orchestrator** |
| Implement code, write tests, fix bugs, develop features | **allye-build** |
| Review code, check quality, validate implementation | **allye-review** |
| Finalize delivery, finalize spec, update docs, clean up | **allye-deliver** |

### How to detect the phase

- **Exploring** — User wants to: think out loud, explore ideas, research a problem space, weigh directions before committing to scope. Nothing should be created yet — no epics, specs, or tasks. Delegate to allye-plan but tell it explicitly this is open-ended exploration, not work-item creation.
- **Planning** — User talks about: requirements, business needs, features, epics, specs, scope, MVP, tasks, approach, options, trade-offs
- **Orchestrating** — User wants to: coordinate delivery, assign tasks, track spec/task status, drive review for an already-planned epic or spec
- **Building** — User wants to: write code, implement a task, fix a bug, add functionality, write tests
- **Reviewing** — User wants to: review code, check quality, validate, get feedback
- **Delivering** — User wants to: finish a spec, merge, deploy, update documentation, close items

### How to delegate

Use the \`task\` tool to delegate to the specialized agent:

\`\`\`
task(subagent_type: "allye-plan", prompt: "User wants to plan {context}")
\`\`\`

Pass relevant context from your init and memory search to the delegated agent.

### When NOT to delegate

If the user's request is simple and doesn't match any phase (general questions, quick lookups, team management), handle it directly using the Allye MCP tools.
`.trim()

export const allyeAgent = {
  ...SHARED_CONFIG,
  description:
    "Allye router — initializes context, detects workflow phase, and delegates to specialized Allye agents (Plan, Orchestrator, Build, Review, Deliver)",
  prompt: buildPrompt("Allye — Router", [
    LANGUAGE_DETECTION,
    ALLYE_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    ORCHESTRATOR_ROUTING,
    WORKFLOW_GATES,
    TOOLS_QUICKREF,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
