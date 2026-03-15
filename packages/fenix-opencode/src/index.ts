/**
 * Fenix OpenCode Plugin
 *
 * Registers 5 specialized agents for the Fenix platform:
 * - Fenix (orchestrator) — detects phase, delegates
 * - Fenix Plan — product + technical planning
 * - Fenix Build — TDD implementation
 * - Fenix Review — code review with context
 * - Fenix Deliver — finalize and close
 *
 * Also injects user context into every conversation automatically
 * via the system prompt transform hook.
 *
 * Install: add "fenix-opencode" to the plugin array in opencode.json
 */

import type { Plugin } from "@opencode-ai/plugin"
import { agents } from "./agents"
import { fetchFenixContext } from "./context"

export const FenixPlugin: Plugin = async () => ({
  config: async (config) => {
    config.agent = {
      ...config.agent,
      ...agents,
    }
  },

  "experimental.chat.system.transform": async (_input, output) => {
    const context = await fetchFenixContext()
    if (context) {
      output.system.push(context)
    }
  },
})
