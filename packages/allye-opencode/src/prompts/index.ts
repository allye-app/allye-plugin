/**
 * Prompt builder — composes agent prompts from fragments and skill content.
 */

export function buildPrompt(agentName: string, sections: string[]): string {
  const header = `# ${agentName}\n\nYou are a specialized Allye agent. You have access to the Allye platform via MCP tools.\n`
  return header + "\n---\n\n" + sections.join("\n\n---\n\n")
}
