/**
 * Allye OpenCode Plugin
 *
 * Registers 5 specialized agents for the Allye platform:
 * - Allye (orchestrator) — detects phase, delegates
 * - Allye Plan — product + technical planning
 * - Allye Build — TDD implementation
 * - Allye Review — code review with context
 * - Allye Deliver — finalize and close
 * Allye account context is loaded through OpenCode's configured MCP server,
 * which owns OAuth credentials and refresh.
 *
 * Install: add "allye-opencode" to the plugin array in opencode.json
 */

import type { Plugin } from "@opencode-ai/plugin"
import { agents } from "./agents"

export const AllyePlugin: Plugin = async () => ({
  config: async (config) => {
    config.agent = {
      ...config.agent,
      ...agents,
    }
  },
})
