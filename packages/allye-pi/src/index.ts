import { dirname, join, resolve } from "node:path";
import { execFile } from "node:child_process";
import { closeSync, constants, fstatSync, lstatSync, openSync, readFileSync, readSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Allye extension for Pi and OMP (oh-my-pi reads the same `pi` manifest).
 *
 * - Exposes the repository's skills/ directory (Bridge) through resources_discover.
 * - Adds the shared bootstrap (bootstrap/allye.md) to the system prompt.
 * - Identifies the repo's project with `projects.project_resolve` (through the
 *   configured MCP bridge when one is available), verifying any
 *   `.allye/project.json` claim against the git remote. It loads no startup or
 *   per-prompt memory context.
 *   The team follows the project: nothing is gated on team selection.
 */

const MCP_SERVER = "allye";
const LINK_FILE = ".allye/project.json";
const PROJECT_KEY = /^[A-Z][A-Z0-9]{1,9}$/;
const APP_NAME = /^[A-Za-z0-9._-]{1,120}$/;
const MAX_LINK_BYTES = 4096;
const MAX_CANDIDATES = 10;
const MAX_REPO_CHARS = 4_000;

type McpResult = { content?: Array<{ type?: string; text?: string }> };
type ActiveMcpToolCaller = (
  serverName: string,
  toolName: string,
  args?: Record<string, unknown>,
  signal?: AbortSignal,
) => Promise<unknown>;
type McpBridgeRuntime = typeof globalThis & {
  __piMcpAdapterActiveToolCaller?: ActiveMcpToolCaller | null;
};
type LinkClaim = { project: string; app?: string };
type LinkState = { claim: LinkClaim | null; warnings: string[] };
type ResolveEntry = {
  project: { key: string };
  app: { name: string } | null;
  team: { name: string; prefix?: string };
};
type Resolution = { status: "resolved" | "ambiguous" | "not_found"; match: ResolveEntry | null; candidates: ResolveEntry[] };

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
  if (!bridge) throw new Error("no in-process MCP bridge is available");
  return resultText(await bridge(MCP_SERVER, toolName, args));
}

function parseJson(text: string): Record<string, unknown> | null {
  const source = text.match(/```json\s*([\s\S]*?)\s*```/)?.[1] ?? text.trim();
  try {
    const parsed: unknown = JSON.parse(source);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

/** Server-provided names are data: one line, no control characters, nothing that can close a tag or inline code. */
function clean(value: unknown): string {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f<>`]+/g, " ").trim().slice(0, 200);
}

/**
 * Drops a remote containing whitespace, control characters or tag/code delimiters. Strips the userinfo
 * first, so an unencoded '?' or '#' in a password cannot survive: for scheme URLs everything up to the
 * last '@' before the first '/' after '://'; for scp remotes up to the last '@' before the first '/',
 * only when that userinfo carries a password (a ':'), so `git@host:path` is kept. Then drops the query
 * and fragment.
 */
function sanitizeRemote(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed || /[\s\u0000-\u001f\u007f<>`]/.test(trimmed)) return null;
  const scheme = /^[a-z][a-z0-9+.-]*:\/\//i.exec(trimmed)?.[0] ?? "";
  const rest = trimmed.slice(scheme.length);
  const head = rest.split("/")[0];
  const at = head.lastIndexOf("@");
  const strip = at >= 0 && (scheme !== "" || (!rest.includes("://") && head.slice(0, at).includes(":")));
  const remote = (scheme + (strip ? rest.slice(at + 1) : rest)).replace(/[?#].*$/, "");
  return remote || null;
}

function git(cwd: string, args: string[]): Promise<string> {
  return new Promise((resolvePromise, reject) => {
    execFile("git", ["-C", cwd, ...args], {
      timeout: 5_000,
      env: { ...process.env, GIT_CONFIG_NOSYSTEM: "1" },
    }, (error, stdout) => (error ? reject(error) : resolvePromise(String(stdout))));
  });
}

/** `origin`, else the first configured remote; null outside a repo or on any git failure. */
async function readRemote(cwd: string): Promise<string | null> {
  try {
    return sanitizeRemote(await git(cwd, ["config", "--local", "--get", "remote.origin.url"]));
  } catch {
    try {
      const first = (await git(cwd, ["config", "--local", "--get-regexp", "^remote\\..*\\.url$"])).split("\n")[0] ?? "";
      return sanitizeRemote(first.replace(/^\S+\s+/, ""));
    } catch {
      return null;
    }
  }
}

/** Reads at most MAX_LINK_BYTES from a regular file, refusing symlinks and FIFOs even if swapped in after lstat. */
function readSmallRegularFile(path: string): string {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size > MAX_LINK_BYTES) throw new Error("not a small regular file");
    const buffer = Buffer.alloc(MAX_LINK_BYTES + 1);
    const length = readSync(fd, buffer, 0, buffer.length, 0);
    if (length > MAX_LINK_BYTES) throw new Error("file too large");
    return buffer.subarray(0, length).toString("utf8");
  } finally {
    closeSync(fd);
  }
}

/** Reads `.allye/project.json`; warnings never echo the file's values. */
function readLinkFile(cwd: string): LinkState {
  const path = join(cwd, LINK_FILE);
  const invalid = { claim: null, warnings: [`Warning: ${LINK_FILE} is invalid and was ignored; only the git remote is used.`] };
  try {
    const entry = lstatSync(path);
    if (!entry.isFile() || entry.size > MAX_LINK_BYTES) return invalid;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "ENOENT" ? { claim: null, warnings: [] } : invalid;
  }
  let raw: string;
  try {
    raw = readSmallRegularFile(path);
  } catch {
    return invalid;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return invalid;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return invalid;
  const value = parsed as Record<string, unknown>;
  if (typeof value.project !== "string" || !PROJECT_KEY.test(value.project)) return invalid;
  if (value.app !== undefined && (typeof value.app !== "string" || !APP_NAME.test(value.app))) return invalid;
  const warnings = Object.keys(value).some((key) => key !== "project" && key !== "app")
    ? [`Warning: ${LINK_FILE} has unknown keys; they were ignored.`]
    : [];
  return { claim: { project: value.project, ...(typeof value.app === "string" ? { app: value.app } : {}) }, warnings };
}

function parseEntry(value: unknown): ResolveEntry | null {
  if (!value || typeof value !== "object") return null;
  const { project, app, team } = value as Record<string, Record<string, unknown> | null>;
  if (!project || typeof project.key !== "string" || !team || typeof team.name !== "string") return null;
  return {
    project: { key: project.key },
    app: app && typeof app.name === "string" ? { name: app.name } : null,
    team: { name: team.name, ...(typeof team.prefix === "string" ? { prefix: team.prefix } : {}) },
  };
}

function parseResolution(text: string): Resolution | null {
  const payload = parseJson(text);
  const status = payload?.status;
  if (status !== "resolved" && status !== "ambiguous" && status !== "not_found") return null;
  const match = parseEntry(payload?.match);
  if (status === "resolved" && !match) return null;
  const candidates = Array.isArray(payload?.candidates) ? payload.candidates.flatMap((item) => parseEntry(item) ?? []) : [];
  return { status, match, candidates };
}

function describeEntry(entry: ResolveEntry): string {
  const app = entry.app ? ` / app ${clean(entry.app.name)}` : " (several apps share this remote)";
  const prefix = entry.team.prefix ? ` [${clean(entry.team.prefix)}]` : "";
  return `project ${clean(entry.project.key)}${app} (team ${clean(entry.team.name)}${prefix})`;
}

function describeEntries(entries: ResolveEntry[]): string {
  const shown = entries.slice(0, MAX_CANDIDATES).map(describeEntry).join("; ");
  return entries.length > MAX_CANDIDATES ? `${shown}; and ${entries.length - MAX_CANDIDATES} more` : shown;
}

/** Several agreeing apps of one project: state the project and list the apps, never pick one. */
function describeProject(entries: ResolveEntry[]): string {
  const [first] = entries;
  const prefix = first.team.prefix ? ` [${clean(first.team.prefix)}]` : "";
  const apps = entries.map((entry) => (entry.app ? clean(entry.app.name) : "")).filter(Boolean);
  const appsText = apps.length ? `apps sharing this remote: ${apps.slice(0, MAX_CANDIDATES).join(", ")}` : "several apps share this remote";
  return `project ${clean(first.project.key)} (team ${clean(first.team.name)}${prefix}); ${appsText}`;
}

function describeClaim(claim: LinkClaim): string {
  return `project ${claim.project}${claim.app ? ` / app ${claim.app}` : ""}`;
}

function agrees(claim: LinkClaim, entry: ResolveEntry): boolean {
  return entry.project.key === claim.project && (claim.app === undefined || entry.app?.name === claim.app);
}

/** The offline repo block: what the extension knows without calling Allye. */
function offlineRepoBlock(remote: string | null, link: LinkState, note?: string): string {
  const lines = [...link.warnings];
  if (remote) lines.push(`Git remote: ${remote}`);
  if (link.claim) lines.push(`This repo claims ${describeClaim(link.claim)} (from ${LINK_FILE}, unverified).`);
  if (remote) lines.push(`Call \`projects.project_resolve repository_url=${remote}\` before the first project-scoped call.`);
  else if (link.claim) lines.push("There is no git remote, so the claim is unverifiable: ask the user to confirm it before using it.");
  if (note) lines.push(note);
  return lines.length ? `## Allye repository\n${lines.join("\n")}` : "";
}

/** Applies BR-01: the remote's resolution is the truth; a link claim is used only when it agrees. */
function describeRepo(remote: string, link: LinkState, resolution: Resolution): string {
  const lines = [...link.warnings, `Git remote: ${remote}`];
  const entries = resolution.match ? [resolution.match] : resolution.candidates;
  const claim = link.claim;
  if (claim) {
    const agreeing = entries.filter((entry) => agrees(claim, entry));
    const match = resolution.status === "resolved" ? resolution.match : null;
    if (agreeing.length) {
      const identity = agreeing.length === 1 ? describeEntry(agreeing[0]) : describeProject(agreeing);
      lines.push(`this repo = ${identity}, confirmed by ${LINK_FILE}.`);
    } else if (match && !match.app && claim.app !== undefined && match.project.key === claim.project) {
      lines.push(`${LINK_FILE} claims ${describeClaim(claim)}; the remote resolves to ${describeEntry(match)}.`);
      lines.push("The project agrees; the claimed app cannot be confirmed (several apps share this remote) — ask the user once which app this repo is.");
    } else {
      lines.push(`${LINK_FILE} claims ${describeClaim(claim)}, which disagrees with the remote's resolution.`);
      lines.push(entries.length
        ? `The remote resolves to: ${describeEntries(entries)}.`
        : "The remote matched no Allye project.");
      lines.push("Do not use either one yet: ask the user once which project/app this repo belongs to, showing both.");
    }
  } else if (resolution.status === "resolved" && resolution.match) {
    lines.push(`this repo = ${describeEntry(resolution.match)}.`);
  } else if (resolution.status === "ambiguous") {
    lines.push(`The remote matches several projects: ${describeEntries(entries)}.`);
    lines.push("Ask the user once which one this repo belongs to before project-scoped work.");
  } else {
    lines.push("The remote matched no Allye project; ask the user when a project is needed.");
  }
  return `## Allye repository\n${lines.join("\n")}`;
}

async function loadRepoContext(cwd: string, online: boolean): Promise<string> {
  return limitText(await buildRepoContext(cwd, online), MAX_REPO_CHARS);
}

async function buildRepoContext(cwd: string, online: boolean): Promise<string> {
  const remote = await readRemote(cwd);
  const link = readLinkFile(cwd);
  if (!online || !remote) return offlineRepoBlock(remote, link);
  try {
    const resolution = parseResolution(await callAllye("projects", { action: "project_resolve", repository_url: remote }));
    if (!resolution) return offlineRepoBlock(remote, link, "Note: Allye `project_resolve` returned a response this extension could not interpret.");
    return describeRepo(remote, link, resolution);
  } catch {
    return offlineRepoBlock(remote, link, "Note: Allye project_resolve failed; resolve the project yourself.");
  }
}

export function buildSystemSections(bootstrap: string, repo: string, nativeBootstrap = true): string[] {
  const sections: string[] = [];
  if (bootstrap) sections.push(`<allye-bootstrap>\n${bootstrap.trim()}\n</allye-bootstrap>`);
  if (nativeBootstrap && repo) sections.push(`<allye-repo>\n${repo}\n</allye-repo>`);
  return sections;
}

export default function allyePiExtension(pi: ExtensionAPI): void {
  const nativeBootstrap = process.env.ALLYE_PI_NATIVE_BOOTSTRAP !== "0";
  let bootstrap = "";
  let repo = "";

  pi.on("resources_discover", () => ({ skillPaths: [skillsPath()] }));

  pi.on("session_start", async (_event, ctx) => {
    bootstrap = loadBootstrap();
    if (nativeBootstrap) repo = await loadRepoContext(ctx.cwd ?? process.cwd(), mcpBridgeAvailable());
  });

  pi.on("before_agent_start", (event) => {
    const sections = buildSystemSections(bootstrap, repo, nativeBootstrap);
    return sections.length ? { systemPrompt: `${event.systemPrompt}\n\n${sections.join("\n\n")}` } : undefined;
  });

  pi.registerCommand("allye-team", {
    description: "Set the default Allye team (needed only to create projects; the team otherwise follows the project)",
    handler: async (args, ctx) => {
      const teamQuery = args?.trim();
      if (!teamQuery) {
        ctx.ui.notify("Usage: /allye-team <name|prefix|id>", "error");
        return;
      }
      try {
        const result = await callAllye("team", { action: "team_set_default", team_query: teamQuery });
        ctx.ui.notify(`Allye default team: ${result}`, "info");
      } catch (error) {
        ctx.ui.notify(`Setting the Allye default team failed: ${error instanceof Error ? error.message : String(error)}. Ask the agent to call the \`team\` tool with action team_set_default instead.`, "error");
      }
    },
  });
}
