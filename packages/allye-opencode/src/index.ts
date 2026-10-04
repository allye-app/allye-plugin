/**
 * Allye OpenCode plugin.
 *
 * - Registers the Bridge skills bundled in this package as an extra OpenCode
 *   skill path, so `/bridge <mode>` is available without copying files.
 * - Registers the Bridge crew as subagents (`bridge-<role>`), generated from
 *   the repository's agents/*.md: each loads its crew skill under a
 *   permission set mirroring the role's tool allowlist.
 * - Adds the shared Allye bootstrap (bootstrap/allye.md) to the system prompt.
 *
 * The Allye MCP server itself is configured in opencode.json; OpenCode owns
 * its OAuth credentials and refresh. This plugin never reads tokens.
 */

import type { Plugin } from "@opencode-ai/plugin"
import { fileURLToPath } from "node:url"
import { join } from "node:path"
import { AGENTS } from "./agents.generated"
import { BOOTSTRAP } from "./bootstrap.generated"

// dist/index.js -> ../skills (copied by scripts/prepare.ts at build time)
const SKILLS_DIR = fileURLToPath(new URL("../skills", import.meta.url))

// Only the plugin is exported: OpenCode treats every export of this module as a plugin.
// Claude Code tool names (agents/*.md) -> OpenCode permission keys.
const MCP_PREFIX = "mcp__plugin_allye_allye__"
const TOOL_PERMISSIONS: Record<string, string[]> = {
  Read: ["read", "list"],
  Grep: ["grep"],
  Glob: ["glob"],
  Edit: ["edit"],
  Write: ["edit"],
  Bash: ["bash"],
  WebFetch: ["webfetch"],
  WebSearch: ["websearch"],
  Skill: ["skill"],
}

type Action = "allow" | "ask" | "deny"
type Permission = Record<string, Action | Record<string, Action>>
type AgentEntry = { description: string; mode: "subagent"; prompt: string; permission: Permission }
type SkillsConfig = { skills?: { paths?: string[]; urls?: string[] } }

/**
 * Deny every tool, then allow exactly the role's tools: OpenCode applies the last
 * matching rule, and agent rules come after its defaults. Two defaults the
 * wildcard would otherwise clobber are restored: `.env` files stay unreadable,
 * and paths outside the project ask first, except the bundled skills.
 */
function crewPermission(tools: readonly string[], skillsDir = SKILLS_DIR): Permission {
  const permission: Permission = {
    "*": "deny",
    external_directory: { "*": "ask", [join(skillsDir, "*")]: "allow" },
  }
  for (const tool of tools) {
    if (tool.startsWith(MCP_PREFIX)) {
      permission[`allye_${tool.slice(MCP_PREFIX.length)}`] = "allow"
      continue
    }
    const keys = TOOL_PERMISSIONS[tool]
    if (!keys) throw new Error(`No OpenCode permission mapping for crew tool ${tool}`)
    for (const key of keys) permission[key] = "allow"
  }
  if (permission.read === "allow") permission.read = { "*": "allow", "*.env": "deny", "*.env.*": "deny", "*.env.example": "allow" }
  return permission
}

/** The agent body names Claude Code's Skill tool and plugin-relative path; point it at OpenCode's. */
function crewPrompt(name: string, body: string, skillsDir = SKILLS_DIR): string {
  return body
    .replace(`with the Skill tool (name \`allye:${name}\`)`, `with the skill tool (name \`${name}\`)`)
    .replace(`\`../skills/${name}/SKILL.md\`, relative to this agent file`, `\`${join(skillsDir, name, "SKILL.md")}\``)
}

function crewAgents(skillsDir = SKILLS_DIR): Record<string, AgentEntry> {
  return Object.fromEntries(
    AGENTS.map((agent) => [
      agent.name,
      {
        description: agent.description,
        mode: "subagent" as const,
        prompt: crewPrompt(agent.name, agent.body, skillsDir),
        permission: crewPermission(agent.tools, skillsDir),
      },
    ]),
  )
}

export const AllyePlugin: Plugin = async () => ({
  config: async (config) => {
    const target = config as typeof config & SkillsConfig
    const paths = target.skills?.paths ?? []
    if (!paths.includes(SKILLS_DIR)) target.skills = { ...target.skills, paths: [...paths, SKILLS_DIR] }
    // Fields the user sets on a crew agent in opencode.json win over the bundled defaults.
    const agents: Record<string, object | undefined> = { ...target.agent }
    for (const [name, crew] of Object.entries(crewAgents())) {
      const own = agents[name]
      agents[name] = own && typeof own === "object" ? { ...crew, ...own } : crew
    }
    target.agent = agents as typeof target.agent
  },
  "experimental.chat.system.transform": async (_input, output) => {
    if (!output.system.includes(BOOTSTRAP)) output.system.push(BOOTSTRAP)
  },
})
