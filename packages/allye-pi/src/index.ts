import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { dirname, resolve } from "node:path";
import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { randomUUID } from "node:crypto";
import { Type } from "typebox";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);
const MCP_SERVER = "allye";
const MAX_CONTEXT_CHARS = 12_000;
const RUNTIME_TIMEOUT_MS = 30_000;
const AGENT_NAME = /^[a-z][a-z0-9_-]{0,31}$/;

type PiMode = "orchestrator" | "executor";
type McpResult = { content?: Array<{ type?: string; text?: string }> };
type StartupContext = {
  text: string;
  teamSelectionRequired: boolean;
  allyeUnavailable: boolean;
  teams: Array<{ id: string; name: string; prefix?: string }>;
};
type WaitRegistrar = (name: string, timeoutMs: number) => Record<string, unknown>;
type WaitCanceller = (name: string) => void;
export type WaitOutcome = "completed" | "timeout" | "error" | "aborted";
export type WaitExecutionResult = {
  code: number;
  killed: boolean;
  stdout: string;
  stderr: string;
};
export type WaitEvent = {
  name: string;
  timeoutMs: number;
  outcome: WaitOutcome;
  code?: number;
  killed?: boolean;
  stdout?: string;
  stderr?: string;
  error?: string;
  timestamp: string;
};
export type WaitEventDelivery = {
  appendEntry: (customType: string, event: WaitEvent) => void;
  notify?: (message: string, level: "info" | "warning" | "error") => void;
  sendMessage?: (
    message: { customType: string; content: string; display: boolean; details: WaitEvent },
    options: { triggerTurn: true; deliverAs: "followUp" },
  ) => void;
};
export type WaitEventDeliveryResult = {
  delivered: boolean;
  persisted: boolean;
  notified: boolean;
  sent: boolean;
  errors: string[];
};
export type OrchestrationMode = "pi" | "hermes";
export type OrchestrationClaim = {
  runId: string;
  workItemKey: string;
  master: OrchestrationMode;
  pid: number;
  sessionId?: string;
  ownerToken: string;
  claimedAt: string;
  leaseExpiresAt: string;
};
export type OwnedPane = {
  workspaceId: string;
  tabId: string;
  paneId: string;
  agentName?: string;
};
export type OwnershipState = {
  claim?: OrchestrationClaim;
  panes: OwnedPane[];
  waits: Set<string>;
};
const RUNTIME_TOOL_NAME = "allye_runtime";
const DEFAULT_LOCK_DIR = ".allye/pi-orchestration-locks";
const DEFAULT_LEASE_MS = 30 * 60 * 1000;
const WAIT_EVENT_TYPE = "allye-herdr-wait";

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

function initialMode(): PiMode {
  if (resolveOrchestrationMode(process.env) === "hermes") return "executor";
  const explicit = process.env.ALLYE_PI_MODE?.toLowerCase();
  if (explicit === "orchestrator"
    && resolveOrchestrationMode(process.env) === "pi"
    && process.env.ALLYE_ORCHESTRATION_RUN_ID
    && process.env.ALLYE_WORK_ITEM_KEY) return explicit;
  if (explicit === "executor") return explicit;
  return "executor";
}

function canonicalSkillsPath(): string {
  // The package lives at packages/allye-pi; skills/ is the repository's one
  // canonical source and is intentionally not copied into this adapter.
  return resolve(dirname(fileURLToPath(import.meta.url)), "../../../skills");
}

type ActiveMcpToolCaller = (
  serverName: string,
  toolName: string,
  args?: Record<string, unknown>,
  signal?: AbortSignal,
) => Promise<unknown>;

async function configuredMcpCall(toolName: string, args: Record<string, unknown>): Promise<unknown> {
  // pi-mcp-adapter intentionally exposes its cooperating-extension bridge on
  // the in-process runtime. There is no public callMcpTool export in the
  // supported package version, so do not dynamically import its TypeScript
  // source from node_modules. A missing bridge is a hard bootstrap failure.
  const globalBridge = (globalThis as typeof globalThis & {
    __piMcpAdapterActiveToolCaller?: ActiveMcpToolCaller | null;
  }).__piMcpAdapterActiveToolCaller;
  if (!globalBridge) throw new Error("pi-mcp-adapter is not initialized; start the configured MCP adapter before using Allye");
  return globalBridge(MCP_SERVER, toolName, args);
}

async function callAllye(toolName: string, args: Record<string, unknown>): Promise<string> {
  return resultText(await configuredMcpCall(toolName, args));
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

export function inspectTeamSelection(initText: string): StartupContext {
  const payload = parseJsonBlock(initText);
  const profile = payload?.profile as Record<string, unknown> | undefined;
  if (!payload || !profile || !Array.isArray(profile.teams)) {
    return invalidStartupContext("Allye initialize returned a payload that the Pi adapter could not interpret.");
  }
  const rawTeams = Array.isArray(profile?.teams) ? profile.teams : [];
  const teams = rawTeams.flatMap((team) => {
    if (!team || typeof team !== "object") return [];
    const value = team as Record<string, unknown>;
    return typeof value.id === "string" && typeof value.name === "string"
      ? [{ id: value.id, name: value.name, ...(typeof value.prefix === "string" ? { prefix: value.prefix } : {}) }]
      : [];
  });
  const activeTeam = profile?.team;
  const hasActiveTeam = Boolean(activeTeam && typeof activeTeam === "object" && typeof (activeTeam as Record<string, unknown>).id === "string");
  const teamSelectionRequired = teams.length > 1 && !hasActiveTeam;
  const instruction = teamSelectionRequired
    ? `## Allye team selection required\nThis account has multiple teams and no active team. Do not call team-scoped work_items or intelligence operations yet. Ask the user to choose one of: ${teams.map((team) => `${team.name}${team.prefix ? ` [${team.prefix}]` : ""} (${team.id})`).join(", ")}. Then use allye_team action team_switch with the chosen team_query. Never choose a team silently.`
    : "";
  return { text: instruction, teamSelectionRequired, allyeUnavailable: false, teams };
}

export function classifyWaitResult(result?: WaitExecutionResult, timeoutMs = 0, error?: unknown): WaitOutcome {
  const errorText = error instanceof Error ? error.message : String(error ?? "");
  if (/abort/i.test(errorText)) return "aborted";
  if (/timeout|timed out/i.test(errorText) || Boolean(result?.killed && timeoutMs > 0)) return "timeout";
  if (!result || result.code !== 0) return "error";
  return "completed";
}

export function shouldEmitWaitEvent(shuttingDown: boolean, settledWaits: Set<string>, name: string): boolean {
  if (shuttingDown || settledWaits.has(name)) return false;
  settledWaits.add(name);
  return true;
}

export function formatWaitEvent(event: WaitEvent): string {
  const output = event.stdout?.trim() || "(no stdout)";
  const error = event.error || event.stderr?.trim() || "(none)";
  return `Herdr wait settled for agent ${event.name}. Outcome: ${event.outcome}. `
    + `This is runtime evidence only, not a completion verdict. `
    + `Use allye_runtime collect now: read work_children for the story and search Allye memories for Review and Implementation evidence before declaring completion.\n\n`
    + `timeout_ms=${event.timeoutMs} code=${event.code ?? "n/a"} killed=${event.killed ?? false} timestamp=${event.timestamp}\n`
    + `stdout:\n${output}\nerror/stderr:\n${error}`;
}

export function waitEventNotificationLevel(event: WaitEvent): "info" | "warning" | "error" {
  if (event.outcome === "error") return "error";
  if (event.outcome === "timeout") return "warning";
  return "info";
}

export function deliverWaitEvent(
  event: WaitEvent,
  shuttingDown: boolean,
  settledWaits: Set<string>,
  delivery: WaitEventDelivery,
): WaitEventDeliveryResult {
  const empty: WaitEventDeliveryResult = {
    delivered: false,
    persisted: false,
    notified: false,
    sent: false,
    errors: [],
  };
  if (!shouldEmitWaitEvent(shuttingDown, settledWaits, event.name)) return empty;

  const message = formatWaitEvent(event);
  const result: WaitEventDeliveryResult = { ...empty, delivered: true };
  try {
    delivery.appendEntry("allye-runtime-wait", event);
    result.persisted = true;
  } catch (error) {
    result.errors.push(`appendEntry: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (delivery.notify) {
    try {
      delivery.notify(message, waitEventNotificationLevel(event));
      result.notified = true;
    } catch (error) {
      result.errors.push(`notify: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  if (delivery.sendMessage) {
    try {
      delivery.sendMessage(
        { customType: WAIT_EVENT_TYPE, content: message, display: true, details: event },
        { triggerTurn: true, deliverAs: "followUp" },
      );
      result.sent = true;
    } catch (error) {
      result.errors.push(`sendMessage: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return result;
}

export function invalidStartupContext(message: string): StartupContext {
  return {
    text: `## Allye bootstrap blocked\n${message}\nDo not call team-scoped work_items or intelligence operations. Resolve Allye connectivity and explicitly select a team with allye_team action team_switch before continuing.`,
    teamSelectionRequired: true,
    allyeUnavailable: true,
    teams: [],
  };
}

export function resolveOrchestrationMode(env: NodeJS.ProcessEnv): OrchestrationMode {
  if (env.ALLYE_ORCHESTRATOR?.toLowerCase() === "hermes") return "hermes";
  return "pi";
}

export function orchestrationLockPath(cwd: string, runId: string): string {
  const safeRunId = runId.replace(/[^a-zA-Z0-9._-]/g, "_");
  return resolve(cwd, DEFAULT_LOCK_DIR, `${safeRunId}.json`);
}

export function canUseOwnedPane(state: OwnershipState, paneId: string): boolean {
  return state.panes.some((pane) => pane.paneId === paneId);
}

export function claimConflict(existing: OrchestrationClaim | undefined, requested: OrchestrationClaim): string | null {
  if (!existing) return null;
  if (existing.runId === requested.runId
    && existing.workItemKey === requested.workItemKey
    && existing.master === requested.master
    && existing.pid === requested.pid
    && existing.ownerToken === requested.ownerToken) return null;
  return `orchestration ownership conflict: ${existing.master}/${existing.runId}/${existing.workItemKey} owns this lock`;
}

function lockRoot(): string {
  return process.env.ALLYE_PI_LOCK_DIR
    ?? process.env.PI_CODING_AGENT_DIR
    ?? resolve(homedir(), ".pi", "agent");
}

function processState(pid: number): "alive" | "dead" | "unknown" {
  try {
    process.kill(pid, 0);
    return "alive";
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ESRCH") return "dead";
    return "unknown";
  }
}

function claimFromEnvironment(sessionId?: string): OrchestrationClaim {
  const runId = process.env.ALLYE_ORCHESTRATION_RUN_ID?.trim();
  const workItemKey = process.env.ALLYE_WORK_ITEM_KEY?.trim();
  if (!runId || !workItemKey) {
    throw new Error("Pi orchestrator requires ALLYE_ORCHESTRATION_RUN_ID and ALLYE_WORK_ITEM_KEY");
  }
  if (resolveOrchestrationMode(process.env) === "hermes") {
    throw new Error("Hermes owns orchestration for this process; Pi remains executor");
  }
  const claimedAt = new Date();
  return {
    runId,
    workItemKey,
    master: "pi",
    pid: process.pid,
    ...(sessionId ? { sessionId } : {}),
    ownerToken: randomUUID(),
    claimedAt: claimedAt.toISOString(),
    leaseExpiresAt: new Date(claimedAt.getTime() + DEFAULT_LEASE_MS).toISOString(),
  };
}

function readClaim(path: string): OrchestrationClaim {
  try {
    const claim = JSON.parse(readFileSync(path, "utf8")) as Partial<OrchestrationClaim>;
    if (typeof claim.runId !== "string" || typeof claim.workItemKey !== "string"
      || (claim.master !== "pi" && claim.master !== "hermes")
      || typeof claim.pid !== "number" || typeof claim.ownerToken !== "string"
      || typeof claim.leaseExpiresAt !== "string") {
      throw new Error("missing required owner, PID, or lease fields");
    }
    return claim as OrchestrationClaim;
  } catch (error) {
    throw new Error(`orchestration lock ${path} is unreadable or invalid (${error instanceof Error ? error.message : String(error)}); refusing to take ownership`);
  }
}

export function acquireLocalClaim(_cwd: string, requested: OrchestrationClaim): void {
  const path = orchestrationLockPath(lockRoot(), requested.workItemKey);
  mkdirSync(resolve(path, ".."), { recursive: true });
  try {
    writeFileSync(path, JSON.stringify(requested, null, 2), { encoding: "utf8", mode: 0o600, flag: "wx" });
    return;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
  }

  const existing = readClaim(path);
  const conflict = claimConflict(existing, requested);
  if (!conflict) return;

  const leaseExpiresAt = Date.parse(existing.leaseExpiresAt);
  const staleRecoveryEnabled = process.env.ALLYE_PI_RECOVER_STALE_LOCK === "1";
  const ownerPidState = processState(existing.pid);
  if (!staleRecoveryEnabled || !Number.isFinite(leaseExpiresAt) || Date.now() <= leaseExpiresAt || ownerPidState !== "dead") {
    const reason = ownerPidState === "alive"
      ? "owner process is active"
      : ownerPidState === "unknown"
        ? "owner process state is inconclusive"
        : "stale recovery is disabled, lease is active, or required lease data is invalid";
    throw new Error(`${conflict}; refusing stale-lock recovery (${reason}). Set ALLYE_PI_RECOVER_STALE_LOCK=1 only after confirming the local PID is gone and the lease expired.`);
  }

  const recoveryMarker = `${path}.recovering`;
  try {
    writeFileSync(recoveryMarker, JSON.stringify({ ownerToken: existing.ownerToken, pid: existing.pid }), { encoding: "utf8", mode: 0o600, flag: "wx" });
  } catch {
    throw new Error(`orchestration lock ${path} is already being recovered; refusing concurrent stale-lock recovery`);
  }
  try {
    const current = readClaim(path);
    if (current.ownerToken !== existing.ownerToken) {
      throw new Error(`orchestration lock ${path} changed owner during stale recovery; refusing takeover`);
    }
    const quarantine = `${path}.stale-${existing.ownerToken}-${randomUUID()}`;
    renameSync(path, quarantine);
    try {
      writeFileSync(path, JSON.stringify(requested, null, 2), { encoding: "utf8", mode: 0o600, flag: "wx" });
    } catch (writeError) {
      try { renameSync(quarantine, path); } catch { /* fail closed; quarantine remains for manual recovery */ }
      throw writeError;
    }
    try { unlinkSync(quarantine); } catch { /* retained quarantine is safe for manual audit */ }
  } finally {
    try { unlinkSync(recoveryMarker); } catch { /* marker is advisory; stale recovery remains fail-closed */ }
  }
}

export function releaseLocalClaim(claim: OrchestrationClaim): boolean {
  const path = orchestrationLockPath(lockRoot(), claim.workItemKey);
  if (!existsSync(path)) return false;
  const existing = readClaim(path);
  if (claimConflict(existing, claim) !== null) return false;
  try {
    unlinkSync(path);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
    throw error;
  }
}

export function shutdownOwnership(ownership: OwnershipState, waits: Map<string, AbortController>): boolean {
  for (const controller of waits.values()) controller.abort();
  waits.clear();
  ownership.waits.clear();
  if (!ownership.claim) return false;
  const released = releaseLocalClaim(ownership.claim);
  if (released) ownership.claim = undefined;
  return released;
}

async function loadStartupContext(): Promise<StartupContext> {
  const sections: string[] = [];
  try {
    const initialization = await callAllye("allye_initialize", {
      action: "init",
      include_user_docs: true,
    });
    const teamState = inspectTeamSelection(initialization);
    sections.push(initialization, teamState.text);
    if (!teamState.allyeUnavailable) {
      sections.push(await callAllye("allye_intelligence", {
        action: "memory_preferences",
      }));
    }
    if (!teamState.teamSelectionRequired && !teamState.allyeUnavailable) {
      sections.push(await callAllye("allye_intelligence", {
        action: "memory_search",
        query: "Pi Allye adapter workflow context",
        limit: 5,
        return_content: true,
      }));
    }
    return {
      text: sections.filter(Boolean).map((section) => limitText(section, MAX_CONTEXT_CHARS)).join("\n\n"),
      teamSelectionRequired: teamState.teamSelectionRequired,
      allyeUnavailable: false,
      teams: teamState.teams,
    };
  } catch (error) {
    return invalidStartupContext(`Allye is unavailable or initialize returned an unreadable payload: ${error instanceof Error ? error.message : String(error)}`);
  }
}

async function loadPromptContext(prompt: string): Promise<string> {
  try {
    return limitText(await callAllye("allye_intelligence", {
      action: "memory_search",
      query: prompt,
      limit: 5,
      return_content: true,
    }), MAX_CONTEXT_CHARS);
  } catch {
    return "";
  }
}

function modeInstructions(mode: PiMode): string {
  if (mode === "orchestrator") {
    return `## Allye Pi role: orchestrator
You are the explicitly selected Pi master for this work item.
- Allye is the source of truth for work items, skills, memories, decisions, and review/delivery state.
- Follow the canonical Allye workflow and gates; do not invent a second workflow.
- Do not implement a story yourself when coordinating it. Dispatch exactly one story at a time to an isolated worktree and executor pane.
- Use the allye_runtime tool only for the Herdr detect/spawn/dispatch/wait/collect contract. The pane cwd stays at the plugin-enabled repository root; absolute worktree paths belong in the briefing.
- Never close panes you did not create, stop Herdr, merge, push, or publish without explicit user approval.
- Hermes and Pi are alternative masters. Confirm that Hermes is not coordinating the same work item before taking control.`;
  }
  return `## Allye Pi role: executor
You are the executor for this session (the safe default).
- Read the canonical Allye skills and the exact story/tasks or handover before changing code.
- Implement only the assigned story/task scope, with the execution skill's verification and reporting rules.
- Follow the canonical execution skill's status protocol: the executor may use Allye to advance its assigned tasks to in_progress and review when the corresponding work and verification are actually complete.
- Do not create or dispatch panes, assume orchestration, or change the assigned scope. Hermes and Pi may both manage status; being allowed to advance assigned task status does not make this session a master.
- If Hermes is the master, follow Hermes' briefing and return a durable implementation/review trace through Allye; do not take control of the work item.
- Stop and report when the scope or a locked decision is unclear; do not guess.`;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runHerdr(args: string[], timeout = RUNTIME_TIMEOUT_MS): Promise<string> {
  const result = await execFileAsync("herdr", args, {
    timeout,
    maxBuffer: 512 * 1024,
    env: process.env,
  });
  return result.stdout || result.stderr || "";
}

function parseJson(text: string): Record<string, unknown> | null {
  try {
    const parsed: unknown = JSON.parse(text);
    return parsed && typeof parsed === "object" ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function herdrResult(text: string): unknown {
  const json = parseJson(text);
  return json?.result ?? json ?? text.trim();
}

function collectValues(value: unknown, key: string, output: string[] = []): string[] {
  if (!value || typeof value !== "object") return output;
  if (Array.isArray(value)) {
    for (const item of value) collectValues(item, key, output);
    return output;
  }
  const object = value as Record<string, unknown>;
  if (typeof object[key] === "string") output.push(object[key] as string);
  for (const child of Object.values(object)) collectValues(child, key, output);
  return output;
}

export function collectPaneRecords(value: unknown, output: OwnedPane[] = []): OwnedPane[] {
  if (!value || typeof value !== "object") return output;
  if (Array.isArray(value)) {
    for (const item of value) collectPaneRecords(item, output);
    return output;
  }
  const object = value as Record<string, unknown>;
  const layout = object.layout && typeof object.layout === "object" ? object.layout as Record<string, unknown> : object;
  const workspaceId = typeof layout.workspace_id === "string" ? layout.workspace_id : undefined;
  const tabId = typeof layout.tab_id === "string" ? layout.tab_id : undefined;
  const panes = Array.isArray(layout.panes) ? layout.panes : [];
  if (workspaceId && tabId) {
    for (const pane of panes) {
      if (pane && typeof pane === "object" && typeof (pane as Record<string, unknown>).pane_id === "string") {
        output.push({ workspaceId, tabId, paneId: (pane as Record<string, unknown>).pane_id as string });
      }
    }
    return output;
  }
  for (const child of Object.values(object)) collectPaneRecords(child, output);
  return output;
}

async function waitForInteractiveShell(pane: string): Promise<void> {
  const shellNames = new Set(["bash", "zsh", "sh", "fish"]);
  for (let attempt = 0; attempt < 10; attempt += 1) {
    try {
      const info = herdrResult(await runHerdr(["pane", "process-info", "--pane", pane], 5_000));
      const foreground = collectValues(info, "name")[0];
      if (foreground && shellNames.has(foreground)) return;
    } catch {
      // The pane may still be initializing; the bounded loop below is the gate.
    }
    if (attempt < 9) await sleep(3_000);
  }
  throw new Error(`Herdr pane ${pane} did not reach an interactive shell within 30 seconds`);
}

export function activeToolsForMode(activeTools: string[], mode: PiMode): string[] {
  const next = new Set(activeTools);
  if (mode === "orchestrator") next.add(RUNTIME_TOOL_NAME);
  else next.delete(RUNTIME_TOOL_NAME);
  return [...next];
}

export function dispatchStateIsAcceptable(stateText: string): boolean {
  if (/blocked|unknown/i.test(stateText)) return false;
  return /working|idle|done/i.test(stateText);
}

function requireOrchestrator(mode: PiMode): void {
  if (mode !== "orchestrator") {
    throw new Error("Herdr orchestration is disabled in executor mode. Set ALLYE_PI_MODE=orchestrator explicitly for the Pi master.");
  }
}

function requireAbsolutePath(value: unknown, name: string): string {
  if (typeof value !== "string" || !value.startsWith("/")) {
    throw new Error(`${name} must be an absolute path`);
  }
  return value;
}

async function runtimeOperation(mode: PiMode, params: Record<string, unknown>, registerWait: WaitRegistrar, cancelWait: WaitCanceller, ownership: OwnershipState): Promise<unknown> {
  requireOrchestrator(mode);
  if (!ownership.claim) throw new Error("Pi orchestrator has no explicit orchestration claim; provide ALLYE_ORCHESTRATION_RUN_ID and ALLYE_WORK_ITEM_KEY");
  const operation = params.operation;
  if (operation === "detect") {
    if (process.env.HERDR_ENV !== "1") return { available: false, reason: "HERDR_ENV is not 1" };
    try {
      const output = await runHerdr(["status"]);
      return { available: /compatible:\s*yes/i.test(output), output: output.trim() };
    } catch (error) {
      return { available: false, reason: error instanceof Error ? error.message : String(error) };
    }
  }

  if (process.env.HERDR_ENV !== "1") {
    throw new Error("Herdr runtime is not active in this Pi session (HERDR_ENV=1 is required).");
  }

  if (operation === "spawn") {
    const cwd = requireAbsolutePath(params.cwd, "cwd");
    const worktree = requireAbsolutePath(params.worktree, "worktree");
    if (!existsSync(worktree)) throw new Error(`worktree does not exist: ${worktree}`);
    if (worktree === cwd) throw new Error("worktree must be isolated from the pane cwd");
    const pane = process.env.HERDR_PANE_ID;
    if (!pane) throw new Error("HERDR_PANE_ID is missing; cannot spawn safely");
    const direction = params.direction === "down" ? "down" : "right";
    const beforeLayout = herdrResult(await runHerdr(["pane", "layout", "--pane", pane]));
    const beforePanes = new Set(collectValues(beforeLayout, "pane_id"));
    await runHerdr(["pane", "split", "--pane", pane, "--direction", direction, "--cwd", cwd, "--no-focus"]);
    const afterLayout = herdrResult(await runHerdr(["pane", "layout", "--pane", pane]));
    const newPane = collectValues(afterLayout, "pane_id").find((id) => !beforePanes.has(id));
    if (!newPane) throw new Error("Herdr split completed but no new pane id was returned");
    const paneRecords = collectPaneRecords(afterLayout);
    const record = paneRecords.find((candidate) => candidate.paneId === newPane && candidate.workspaceId === String((afterLayout as Record<string, unknown>).workspace_id ?? candidate.workspaceId) && candidate.tabId === String((afterLayout as Record<string, unknown>).tab_id ?? candidate.tabId));
    if (!record) throw new Error("Herdr returned a pane without workspace/tab ownership metadata");
    ownership.panes.push(record);
    await waitForInteractiveShell(newPane);
    return { pane: newPane, worktree, cwd, direction, ready: true, ownership: record };
  }

  if (operation === "dispatch") {
    const name = params.name;
    if (typeof name !== "string" || !AGENT_NAME.test(name)) {
      throw new Error("name must match [a-z][a-z0-9_-]{0,31}");
    }
    const kind = typeof params.kind === "string" ? params.kind : "pi";
    const pane = typeof params.pane === "string" ? params.pane : "";
    const briefing = params.briefing;
    const worktree = requireAbsolutePath(params.worktree, "worktree");
    if (!existsSync(worktree)) throw new Error(`worktree does not exist: ${worktree}`);
    if (!pane || typeof briefing !== "string" || briefing.trim().length === 0) {
      throw new Error("dispatch requires pane and a non-empty briefing");
    }
    const ownedPane = ownership.panes.find((candidate) => candidate.paneId === pane);
    if (!ownedPane) throw new Error(`pane ${pane} is not owned by this Pi orchestration run`);
    const currentLayout = herdrResult(await runHerdr(["pane", "layout", "--pane", pane]));
    const currentRecord = collectPaneRecords(currentLayout).find((candidate) => candidate.paneId === pane);
    if (!currentRecord || currentRecord.workspaceId !== ownedPane.workspaceId || currentRecord.tabId !== ownedPane.tabId) {
      throw new Error(`pane ${pane} ownership metadata no longer matches this Pi orchestration run`);
    }
    await waitForInteractiveShell(pane);
    if (!briefing.includes(worktree)) {
      throw new Error("dispatch briefing must contain the absolute worktree path");
    }
    const start = await runHerdr(["agent", "start", name, "--kind", kind, "--pane", pane, "--timeout", "120000", "--"]);
    await runHerdr(["agent", "prompt", name, briefing]);
    // A fast agent can already be idle/done by the time it is inspected. The
    // server-owned wait is registered immediately so that completion is not
    // lost and a fast, successful turn is not falsely rejected.
    const wait = registerWait(name, 3_600_000);
    let agentState: unknown;
    try {
      agentState = herdrResult(await runHerdr(["agent", "get", name]));
    } catch (error) {
      cancelWait(name);
      throw error;
    }
    if (!dispatchStateIsAcceptable(JSON.stringify(agentState))) {
      cancelWait(name);
      throw new Error(`Herdr agent ${name} entered an unsupported state after prompt submission`);
    }
    ownedPane.agentName = name;
    ownership.waits.add(name);
    return {
      started: herdrResult(start),
      state: agentState,
      wait,
      ownership: ownedPane,
    };
  }

  if (operation === "wait") {
    const name = params.name;
    if (typeof name !== "string" || !AGENT_NAME.test(name)) throw new Error("valid agent name is required");
    const timeout = typeof params.timeoutMs === "number" ? params.timeoutMs : 3_600_000;
    if (!ownership.waits.has(name)) throw new Error(`agent ${name} is not owned by this Pi orchestration run`);
    return registerWait(name, timeout);
  }

  if (operation === "collect") {
    const storyId = params.storyId;
    if (typeof storyId !== "string" || storyId.length === 0) throw new Error("collect requires the story UUID as storyId");
    const story = await callAllye("allye_work_items", { action: "work_children", id: storyId });
    const reviewQuery = typeof params.storyKey === "string" ? `Review ${params.storyKey}` : `Review ${storyId}`;
    const review = await callAllye("allye_intelligence", { action: "memory_search", query: reviewQuery, limit: 10, return_content: true });
    const implementationQuery = typeof params.taskKey === "string" ? `Implementation ${params.taskKey}` : `Implementation ${storyId}`;
    const implementation = await callAllye("allye_intelligence", { action: "memory_search", query: implementationQuery, limit: 10, return_content: true });
    return { storyChildren: story, review, implementation };
  }

  throw new Error(`Unknown runtime operation: ${String(operation)}`);
}

function registerRuntimeTool(pi: ExtensionAPI, getMode: () => PiMode, registerWait: WaitRegistrar, cancelWait: WaitCanceller, state: OwnershipState): void {
  pi.registerTool({
    name: "allye_runtime",
    label: "Allye Runtime",
    description: "Drive Herdr from Pi orchestrator mode using detect, spawn, dispatch, wait, and Allye-backed collect.",
    parameters: Type.Object({
      operation: Type.String({ description: "detect | spawn | dispatch | wait | collect" }),
      cwd: Type.Optional(Type.String({ description: "Absolute plugin-enabled repository root for spawn" })),
      worktree: Type.Optional(Type.String({ description: "Absolute isolated worktree path; required for spawn/dispatch" })),
      direction: Type.Optional(Type.String({ description: "right or down" })),
      pane: Type.Optional(Type.String({ description: "Pane id returned by Herdr" })),
      name: Type.Optional(Type.String({ description: "Stable Herdr agent name" })),
      kind: Type.Optional(Type.String({ description: "Herdr agent kind, normally pi" })),
      briefing: Type.Optional(Type.String({ description: "Complete story briefing, including the absolute worktree path" })),
      timeoutMs: Type.Optional(Type.Number({ description: "Bounded wait timeout in milliseconds" })),
      storyId: Type.Optional(Type.String({ description: "Allye story UUID for collect" })),
      storyKey: Type.Optional(Type.String({ description: "Story key for review memory search" })),
      taskKey: Type.Optional(Type.String({ description: "Task key for implementation memory search" })),
    }),
    async execute(_toolCallId, params) {
      try {
        const result = await runtimeOperation(getMode(), params as Record<string, unknown>, registerWait, cancelWait, state);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }], details: result };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return { content: [{ type: "text", text: `Allye runtime error: ${message}` }], isError: true, details: { error: message } };
      }
    },
  });
}

export default function allyePiAdapter(pi: ExtensionAPI): void {
  let mode = initialMode();
  let startupContext: StartupContext = { text: "", teamSelectionRequired: false, allyeUnavailable: true, teams: [] };
  let firstPrompt = true;
  let shuttingDown = false;
  let activeContext: ExtensionContext | undefined;
  const waits = new Map<string, AbortController>();
  const settledWaits = new Set<string>();
  const ownership: OwnershipState = { panes: [], waits: new Set() };

  const registerWait: WaitRegistrar = (name, timeoutMs) => {
    if (settledWaits.has(name)) return { registered: false, name, timeoutMs, duplicate: true, settled: true };
    const existing = waits.get(name);
    if (existing) return { registered: true, name, timeoutMs, duplicate: true };
    const controller = new AbortController();
    waits.set(name, controller);
    void pi.exec("herdr", ["agent", "wait", name, "--timeout", String(timeoutMs)], {
      timeout: timeoutMs + 5_000,
      signal: controller.signal,
    }).then((result) => {
      const event: WaitEvent = {
        name,
        timeoutMs,
        outcome: classifyWaitResult(result, timeoutMs),
        code: result.code,
        killed: result.killed,
        stdout: result.stdout,
        stderr: result.stderr,
        timestamp: new Date().toISOString(),
      };
      deliverWaitEvent(event, shuttingDown, settledWaits, {
        appendEntry: (customType, value) => pi.appendEntry(customType, value),
        notify: activeContext?.hasUI ? (message, level) => activeContext?.ui.notify(message, level) : undefined,
        sendMessage: (message, options) => pi.sendMessage(message, options),
      });
    }).catch((error) => {
      const event: WaitEvent = {
        name,
        timeoutMs,
        outcome: classifyWaitResult(undefined, timeoutMs, error),
        error: error instanceof Error ? error.message : String(error),
        timestamp: new Date().toISOString(),
      };
      deliverWaitEvent(event, shuttingDown, settledWaits, {
        appendEntry: (customType, value) => pi.appendEntry(customType, value),
        notify: activeContext?.hasUI ? (message, level) => activeContext?.ui.notify(message, level) : undefined,
        sendMessage: (message, options) => pi.sendMessage(message, options),
      });
    }).finally(() => {
      waits.delete(name);
    });
    return {
      registered: true,
      name,
      timeoutMs,
      diagnostic: "Wait runs through Pi's managed exec, is bounded, and records stdout/stderr in the session log.",
    };
  };

  const cancelWait: WaitCanceller = (name) => {
    waits.get(name)?.abort();
    waits.delete(name);
  };

  const syncModeTools = () => {
    pi.setActiveTools(activeToolsForMode(pi.getActiveTools(), mode));
  };

  pi.registerMessageRenderer(WAIT_EVENT_TYPE, () => undefined);

  pi.on("resources_discover", () => ({ skillPaths: [canonicalSkillsPath()] }));

  pi.on("session_start", async (_event, ctx) => {
    shuttingDown = false;
    activeContext = ctx;
    mode = initialMode();
    firstPrompt = true;
    syncModeTools();
    if (ctx.hasUI) ctx.ui.setStatus("allye-pi", `loading Allye context (${mode})…`);
    if (process.env.ALLYE_PI_NATIVE_BOOTSTRAP !== "0") startupContext = await loadStartupContext();
    if (mode === "orchestrator") {
      try {
        const claim = claimFromEnvironment(ctx.sessionManager.getSessionId());
        acquireLocalClaim(ctx.cwd, claim);
        ownership.claim = claim;
      } catch (error) {
        mode = "executor";
        syncModeTools();
        startupContext = {
          ...startupContext,
          text: `${startupContext.text}\n## Pi orchestration blocked\n${error instanceof Error ? error.message : String(error)}\nPi remains executor; status management for assigned tasks remains allowed.`,
        };
        if (ctx.hasUI) ctx.ui.notify("Pi orchestration blocked; no compatible ownership claim was acquired. Executor mode remains active.", "warning");
      }
    }
    if (startupContext.teamSelectionRequired && ctx.hasUI) {
      ctx.ui.notify("Allye has multiple teams and no active team. Use /allye-team <name|prefix|id> before team-scoped work.", "warning");
    }
    if (ctx.hasUI) ctx.ui.setStatus("allye-pi", `Allye ${mode} ready`);
  });

  pi.on("session_shutdown", () => {
    shuttingDown = true;
    activeContext = undefined;
    try {
      shutdownOwnership(ownership, waits);
    } catch (error) {
      console.error(`Allye Pi: could not release orchestration lock safely: ${error instanceof Error ? error.message : String(error)}`);
    }
  });

  pi.on("before_agent_start", async (event) => {
    const sections = [
      `<allye-pi-adapter>\n${modeInstructions(mode)}\n\nCanonical Allye skills are loaded from ${canonicalSkillsPath()} — do not create copies.\n${startupContext.teamSelectionRequired ? "\n" + startupContext.text : ""}\n</allye-pi-adapter>`,
    ];
    if (firstPrompt && process.env.ALLYE_PI_NATIVE_BOOTSTRAP !== "0") {
      firstPrompt = false;
      if (startupContext.text) sections.push(`<allye-pi-startup-context>\n${startupContext.text}\n</allye-pi-startup-context>`);
      if (!startupContext.teamSelectionRequired && !startupContext.allyeUnavailable) {
        const relevant = await loadPromptContext(event.prompt);
        if (relevant) sections.push(`<allye-pi-relevant-memory>\n${relevant}\n</allye-pi-relevant-memory>`);
      }
    }
    return { systemPrompt: `${event.systemPrompt}\n\n${sections.join("\n\n")}` };
  });

  pi.registerCommand("allye-mode", {
    description: "Select executor or orchestrator mode for this Pi session",
    getArgumentCompletions: (prefix) => ["executor", "orchestrator"]
      .filter((value) => value.startsWith(prefix.trim()))
      .map((value) => ({ value, label: value })),
    handler: async (args, ctx) => {
      const selected = args?.trim().toLowerCase();
      if (selected !== "executor" && selected !== "orchestrator") {
        ctx.ui.notify("Usage: /allye-mode executor|orchestrator", "error");
        return;
      }
      if (selected === "orchestrator" && resolveOrchestrationMode(process.env) === "hermes") {
        ctx.ui.notify("Hermes owns orchestration for this process; Pi remains executor.", "warning");
        return;
      }
      if (selected === mode) {
        ctx.ui.notify(`Allye mode is already ${mode} for this session`, "info");
        return;
      }
      if (selected === "executor") {
        // Downgrading must release the orchestration claim and abort waits so
        // this session cannot keep coordinating after becoming an executor.
        shutdownOwnership(ownership, waits);
        ownership.panes.length = 0;
      }
      if (selected === "orchestrator" && !ownership.claim) {
        try {
          const claim = claimFromEnvironment(ctx.sessionManager.getSessionId());
          acquireLocalClaim(ctx.cwd, claim);
          ownership.claim = claim;
        } catch (error) {
          ctx.ui.notify(`Pi orchestration blocked: ${error instanceof Error ? error.message : String(error)}`, "error");
          return;
        }
      }
      mode = selected;
      syncModeTools();
      ctx.ui.setStatus("allye-pi", `Allye ${mode}`);
      ctx.ui.notify(`Allye mode set to ${mode} for this session`, "info");
    },
  });

  pi.registerCommand("allye-team", {
    description: "Select the active Allye team without choosing one silently",
    handler: async (args, ctx) => {
      const teamQuery = args?.trim();
      if (!teamQuery) {
        ctx.ui.notify("Usage: /allye-team <name|prefix|id>", "error");
        return;
      }
      try {
        const result = await callAllye("allye_team", { action: "team_switch", team_query: teamQuery });
        startupContext = await loadStartupContext();
        ctx.ui.notify(`Allye team selection: ${result}`, "info");
      } catch (error) {
        ctx.ui.notify(`Allye team selection failed: ${error instanceof Error ? error.message : String(error)}`, "error");
      }
    },
  });

  registerRuntimeTool(pi, () => mode, registerWait, cancelWait, ownership);
}
