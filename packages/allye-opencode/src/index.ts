/**
 * Allye OpenCode plugin.
 *
 * - Registers the Bridge skills bundled in this package as an extra OpenCode
 *   skill path, so `/bridge <mode>` is available without copying files.
 * - Adds the shared Allye bootstrap (bootstrap/allye.md) to the system prompt.
 *
 * The Allye MCP server itself is configured in opencode.json; OpenCode owns
 * its OAuth credentials and refresh. This plugin never reads tokens.
 */

import type { Plugin } from "@opencode-ai/plugin"
import { fileURLToPath } from "node:url"
import { BOOTSTRAP } from "./bootstrap.generated"

// dist/index.js -> ../skills (copied by scripts/prepare.ts at build time)
const SKILLS_DIR = fileURLToPath(new URL("../skills", import.meta.url))

type SkillsConfig = { skills?: { paths?: string[]; urls?: string[] } }

export const AllyePlugin: Plugin = async () => ({
  config: async (config) => {
    const target = config as typeof config & SkillsConfig
    const paths = target.skills?.paths ?? []
    if (!paths.includes(SKILLS_DIR)) target.skills = { ...target.skills, paths: [...paths, SKILLS_DIR] }
  },
  "experimental.chat.system.transform": async (_input, output) => {
    if (!output.system.includes(BOOTSTRAP)) output.system.push(BOOTSTRAP)
  },
})
