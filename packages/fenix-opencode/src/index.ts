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
 * Install: add "fenix-opencode" to the plugin array in opencode.json
 */

import type { Plugin } from "@opencode-ai/plugin"
import { agents } from "./agents"

export const FenixPlugin: Plugin = async () => ({
  config: async (config) => {
    config.agent = {
      ...config.agent,
      ...agents,
    }
  },
})
