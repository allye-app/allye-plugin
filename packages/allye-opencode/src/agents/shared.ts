/**
 * Shared agent configuration used by all Allye agents.
 */

export const SHARED_CONFIG = {
  model: "anthropic/claude-sonnet-4-5",
  temperature: 0.3,
  mode: "primary" as const,
  permission: {
    task: "allow" as const,
    edit: "allow" as const,
    bash: "ask" as const,
  },
}

export const READ_ONLY_TOOLS = {
  write: false,
  edit: false,
  bash: false,
}
