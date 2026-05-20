/**
 * Allye OpenCode Plugin
 *
 * Registers 5 specialized agents for the Allye platform:
 * - Allye (orchestrator) — detects phase, delegates
 * - Allye Plan — product + technical planning
 * - Allye Build — TDD implementation
 * - Allye Review — code review with context
 * - Allye Deliver — finalize and close
 *
 * Also injects user context into every conversation automatically
 * via the system prompt transform hook.
 *
 * Install: add "allye-opencode" to the plugin array in opencode.json
 */

import type { Plugin } from "@opencode-ai/plugin"
import { agents } from "./agents"
import { fetchAllyeContext } from "./context"

export const AllyePlugin: Plugin = async () => ({
  config: async (config) => {
    config.agent = {
      ...config.agent,
      ...agents,
    }
  },

  "experimental.chat.system.transform": async (_input, output) => {
    const context = await fetchAllyeContext()
    if (context) {
      output.system.push(context)
    }
  },
})
