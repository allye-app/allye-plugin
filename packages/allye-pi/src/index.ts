import { dirname, resolve } from "node:path";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Allye extension for Pi and OMP (oh-my-pi reads the same `pi` manifest).
 *
 * - Exposes the repository's skills/ directory (Bridge) through resources_discover.
 * - Adds the shared bootstrap (bootstrap/allye.md) to the system prompt.
 * - Preloads Allye context through the configured MCP bridge when one is
 *   available, and gates team-scoped work until an active team is set.
 */

const MCP_SERVER = "allye";
const MAX_CONTEXT_CHARS = 12_000;

type McpResult = { content?: Array<{ type?: string; text?: string }> };
export type StartupContext = {
  text: string;
  teamSelectionRequired: boolean;
  allyeUnavailable: boolean;
  teams: Array<{ id: string; name: string; prefix?: string }>;
};
type ActiveMcpToolCaller = (
  serverName: string,
  toolName: string,
  args?: Record<string, unknown>,
  signal?: AbortSignal,
) => Promise<unknown>;
type McpBridgeRuntime = typeof globalThis & {
  __piMcpAdapterActiveToolCaller?: ActiveMcpToolCaller | null;
};

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");

export function skillsPath(): string {
  return resolve(packageRoot, "skills");
}

export function loadBootstrap(): string {
  try {
    return readFileSync(resolve(packageRoot, "bootstrap", "allye.md"), "utf8");
  } catch {
    return "";
  }
}

function resultText(result: unknown): string {
  const content = (result as McpResult | null)?.content;
  if (!Array.isArray(content)) return String(result ?? "");
  return content
    .filter((part) => part.type === "text" && typeof part.text === "string")
    .map((part) => part.text as string)
    .join("\n");
}

function limitText(text: string, maxChars: number): string {
  return text.length <= maxChars ? text : `${text.slice(0, maxChars)}\n[context truncated]`;
}

export function mcpBridgeAvailable(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.ALLYE_PI_MCP !== "0" && Boolean((globalThis as McpBridgeRuntime).__piMcpAdapterActiveToolCaller);
}

async function callAllye(toolName: string, args: Record<string, unknown>): Promise<string> {
  // pi-mcp-adapter may expose an in-process bridge for cooperating extensions.
  // Without it, the agent still reaches Allye through its own MCP tools.
  const bridge = (globalThis as McpBridgeRuntime).__piMcpAdapterActiveToolCaller;
  if (!bridge) throw new Error("no in-process MCP bridge is available to preload Allye context");
  return resultText(await bridge(MCP_SERVER, toolName, args));
}

function parseJsonBlock(text: string): Record<string, unknown> | null {
  const block = text.match(/```json\s*([\s\S]*?)\s*```/)?.[1];
  if (!block) return null;
  try {
    const parsed: unknown = JSON.parse(block);
    return parsed && typeof parsed === "object" ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

export function unavailableStartupContext(reason: string): StartupContext {
  return {
    text: `## Allye context not preloaded\n${reason}\nUse the Allye MCP tools directly when the task needs them: call \`initialize\` first and, if no team is active, ask the user which team to use before any team-scoped call.`,
    teamSelectionRequired: false,
    allyeUnavailable: true,
    teams: [],
  };
}

export function inspectTeamSelection(initText: string): StartupContext {
  const payload = parseJsonBlock(initText);
  const profile = payload?.profile as Record<string, unknown> | undefined;
  if (!payload || !profile || !Array.isArray(profile.teams)) {
    return unavailableStartupContext("Allye `initialize` returned a payload this extension could not interpret.");
  }
  const teams = profile.teams.flatMap((team) => {
    if (!team || typeof team !== "object") return [];
    const value = team as Record<string, unknown>;
    return typeof value.id === "string" && typeof value.name === "string"
      ? [{ id: value.id, name: value.name, ...(typeof value.prefix === "string" ? { prefix: value.prefix } : {}) }]
      : [];
  });
  const activeTeam = profile.team;
  const hasActiveTeam = Boolean(activeTeam && typeof activeTeam === "object" && typeof (activeTeam as Record<string, unknown>).id === "string");
  const teamSelectionRequired = teams.length > 1 && !hasActiveTeam;
  const text = teamSelectionRequired
    ? `## Allye team selection required\nThis account has several teams and none is active. Do not call team-scoped projects, epics, specs, tasks or intelligence operations yet. Ask the user to choose one of: ${teams.map((team) => `${team.name}${team.prefix ? ` [${team.prefix}]` : ""} (${team.id})`).join(", ")}. Then call the \`team\` tool with action \`team_switch\` and the chosen \`team_query\`. Never choose a team silently.`
    : "";
  return { text, teamSelectionRequired, allyeUnavailable: false, teams };
}

async function loadStartupContext(): Promise<StartupContext> {
  if (!mcpBridgeAvailable()) return unavailableStartupContext("No in-process MCP bridge is available in this session.");
  try {
    const initialization = await callAllye("initialize", { action: "init", include_user_docs: true });
    const teamState = inspectTeamSelection(initialization);
    if (teamState.allyeUnavailable) return teamState;
    const sections = [initialization, teamState.text];
    sections.push(await callAllye("intelligence", { action: "memory_preferences" }));
    return {
      text: sections.filter(Boolean).map((section) => limitText(section, MAX_CONTEXT_CHARS)).join("\n\n"),
      teamSelectionRequired: teamState.teamSelectionRequired,
      allyeUnavailable: false,
      teams: teamState.teams,
    };
  } catch (error) {
    return unavailableStartupContext(`Allye context could not be preloaded: ${error instanceof Error ? error.message : String(error)}`);
  }
}

async function loadPromptContext(prompt: string): Promise<string> {
  try {
    return limitText(await callAllye("intelligence", {
      action: "memory_search",
      query: prompt,
      limit: 5,
      return_content: true,
    }), MAX_CONTEXT_CHARS);
  } catch {
    return "";
  }
}

export function buildSystemSections(bootstrap: string, startup: StartupContext, firstPrompt: boolean, nativeBootstrap = true): string[] {
  const sections: string[] = [];
  if (bootstrap) sections.push(`<allye-bootstrap>\n${bootstrap.trim()}\n</allye-bootstrap>`);
  if (startup.teamSelectionRequired) sections.push(`<allye-team-gate>\n${startup.text}\n</allye-team-gate>`);
  else if (firstPrompt && nativeBootstrap && startup.text) sections.push(`<allye-startup-context>\n${startup.text}\n</allye-startup-context>`);
  return sections;
}

export default function allyePiExtension(pi: ExtensionAPI): void {
  const nativeBootstrap = process.env.ALLYE_PI_NATIVE_BOOTSTRAP !== "0";
  let startupContext = unavailableStartupContext("Allye context has not been loaded yet.");
  let bootstrap = "";
  let firstPrompt = true;

  pi.on("resources_discover", () => ({ skillPaths: [skillsPath()] }));

  pi.on("session_start", async (_event, ctx) => {
    firstPrompt = true;
    bootstrap = loadBootstrap();
    if (nativeBootstrap) {
      if (ctx.hasUI) ctx.ui.setStatus("allye", "loading Allye context…");
      startupContext = await loadStartupContext();
      if (ctx.hasUI) ctx.ui.setStatus("allye", startupContext.allyeUnavailable ? "Allye: context not preloaded" : "Allye ready");
    }
    if (startupContext.teamSelectionRequired && ctx.hasUI) {
      ctx.ui.notify("Allye has several teams and none is active. Use /allye-team <name|prefix|id> before team-scoped work.", "warning");
    }
  });

  pi.on("before_agent_start", async (event) => {
    const sections = buildSystemSections(bootstrap, startupContext, firstPrompt, nativeBootstrap);
    if (firstPrompt) {
      firstPrompt = false;
      if (nativeBootstrap && !startupContext.teamSelectionRequired && !startupContext.allyeUnavailable) {
        const relevant = await loadPromptContext(event.prompt);
        if (relevant) sections.push(`<allye-relevant-memory>\n${relevant}\n</allye-relevant-memory>`);
      }
    }
    return sections.length ? { systemPrompt: `${event.systemPrompt}\n\n${sections.join("\n\n")}` } : undefined;
  });

  pi.registerCommand("allye-team", {
    description: "Select the active Allye team (never chosen silently)",
    handler: async (args, ctx) => {
      const teamQuery = args?.trim();
      if (!teamQuery) {
        ctx.ui.notify("Usage: /allye-team <name|prefix|id>", "error");
        return;
      }
      try {
        const result = await callAllye("team", { action: "team_switch", team_query: teamQuery });
        startupContext = await loadStartupContext();
        ctx.ui.notify(`Allye team selection: ${result}`, "info");
      } catch (error) {
        ctx.ui.notify(`Allye team selection failed: ${error instanceof Error ? error.message : String(error)}. Ask the agent to call the \`team\` tool with action team_switch instead.`, "error");
      }
    },
  });
}
