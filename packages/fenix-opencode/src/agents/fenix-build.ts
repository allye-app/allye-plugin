/**
 * Fenix Build — Implementation agent.
 * Picks up tasks and implements them with TDD discipline,
 * read-first rule, and wave execution. Executes, doesn't plan.
 */

import { SHARED_CONFIG } from "./shared"
import { buildPrompt } from "../prompts"
import {
  FENIX_INIT_PROTOCOL,
  MEMORY_SEARCH_PROTOCOL,
  MEMORY_SAVE_PROTOCOL,
  DYNAMIC_SKILL_LOADING,
  WORKFLOW_GATES,
} from "../prompts/fragments"
import {
  TECHNICAL_DEVELOPMENT,
  TDD_WORKFLOW,
} from "../prompts/skills-content"

const BUILD_IDENTITY = `
## Your Role

You are the **builder**. You execute tasks — you don't plan them.

When starting:
1. Get the task to implement (\`work_get\`)
2. Read its description, acceptance criteria, and dependencies
3. Check if dependencies are met (\`work_children\` on parent story)
4. Move the task to in_progress (\`work_status_next\`)
5. Read existing code before writing new code (READ-FIRST RULE)
6. Implement with TDD when applicable
7. Mark task as done when all acceptance criteria are met

### What to search for in skills

Search \`skill_list\` for:
- Development standards and coding conventions
- Testing guidelines and patterns
- Framework-specific best practices
- Any skills tagged with your project's tech stack

### Analysis Paralysis Guard

If you've read 5+ files without writing any code, STOP:
- Do you have enough context? → Start writing
- Are you blocked? → Tell the user what's blocking you

### Automation-First Rule

If you CAN automate something, you MUST:
- Running tests → automate
- Formatting code → automate
- Installing dependencies → automate

Only ask for human action when genuinely impossible to proceed without it.
`.trim()

export const fenixBuildAgent = {
  ...SHARED_CONFIG,
  description:
    "Fenix builder — implements tasks with TDD discipline, read-first rule, and wave execution. Picks up tasks and executes them.",
  prompt: buildPrompt("Fenix Build", [
    FENIX_INIT_PROTOCOL,
    MEMORY_SEARCH_PROTOCOL,
    DYNAMIC_SKILL_LOADING,
    BUILD_IDENTITY,
    TECHNICAL_DEVELOPMENT,
    TDD_WORKFLOW,
    WORKFLOW_GATES,
    MEMORY_SAVE_PROTOCOL,
  ]),
}
