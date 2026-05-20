/**
 * Allye — Orchestrator agent.
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
| Define requirements, plan features, create epics/stories, break stories into tasks | **allye-plan** |
| Implement code, write tests, fix bugs, develop features | **allye-build** |
| Review code, check quality, validate implementation | **allye-review** |
| Finalize delivery, close story, update docs, clean up | **allye-deliver** |

### How to detect the phase

- **Planning** — User talks about: requirements, business needs, features, epics, user stories, scope, MVP, tasks, approach, options, trade-offs
- **Building** — User wants to: write code, implement a task, fix a bug, add functionality, write tests
- **Reviewing** — User wants to: review code, check quality, validate, get feedback
- **Delivering** — User wants to: finish a story, merge, deploy, update documentation, close items

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
    "Allye orchestrator — initializes context, detects workflow phase, and delegates to specialized Allye agents (Plan, Build, Review, Deliver)",
  prompt: buildPrompt("Allye — Orchestrator", [
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
