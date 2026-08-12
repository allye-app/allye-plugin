import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import test from "node:test";
import {
  acquireLocalClaim,
  activeToolsForMode,
  canUseOwnedPane,
  claimConflict,
  classifyWaitResult,
  collectPaneRecords,
  deliverWaitEvent,
  dispatchStateIsAcceptable,
  formatWaitEvent,
  inspectTeamSelection,
  invalidStartupContext,
  releaseLocalClaim,
  resolveOrchestrationMode,
  shouldEmitWaitEvent,
  shutdownOwnership,
  waitEventNotificationLevel,
} from "./index.ts";

test("runtime tool is active only in orchestrator mode", () => {
  const base = ["read", "bash", "allye_runtime", "mcp"];
  assert.deepEqual(activeToolsForMode(base, "executor"), ["read", "bash", "mcp"]);
  assert.deepEqual(activeToolsForMode(["read", "bash", "mcp"], "orchestrator"), [
    "read",
    "bash",
    "mcp",
    "allye_runtime",
  ]);
});

test("dispatch accepts a fast idle/done agent but rejects blocked or unknown states", () => {
  assert.equal(dispatchStateIsAcceptable('{"agent_status":"working"}'), true);
  assert.equal(dispatchStateIsAcceptable('{"agent_status":"idle"}'), true);
  assert.equal(dispatchStateIsAcceptable('{"agent_status":"done"}'), true);
  assert.equal(dispatchStateIsAcceptable('{"agent_status":"blocked"}'), false);
  assert.equal(dispatchStateIsAcceptable('{"agent_status":"unknown"}'), false);
});

test("wait events classify outcomes and require Allye collection", () => {
  assert.equal(classifyWaitResult({ code: 0, killed: false, stdout: "done", stderr: "" }, 1000), "completed");
  assert.equal(classifyWaitResult({ code: 1, killed: false, stdout: "", stderr: "failed" }, 1000), "error");
  assert.equal(classifyWaitResult({ code: 1, killed: true, stdout: "", stderr: "" }, 1000), "timeout");
  assert.equal(classifyWaitResult(undefined, 1000, new Error("aborted by shutdown")), "aborted");
  assert.match(formatWaitEvent({ name: "agent-a", timeoutMs: 1000, outcome: "completed", timestamp: "now" }), /allye_runtime collect/);
  assert.match(formatWaitEvent({ name: "agent-a", timeoutMs: 1000, outcome: "completed", timestamp: "now" }), /not a completion verdict/);
});

test("wait notification is suppressed after shutdown and duplicated settlement", () => {
  const settled = new Set<string>();
  assert.equal(shouldEmitWaitEvent(false, settled, "agent-a"), true);
  assert.equal(shouldEmitWaitEvent(false, settled, "agent-a"), false);
  assert.equal(shouldEmitWaitEvent(true, settled, "agent-b"), false);
});

test("wait settlement persists, notifies, and queues a follow-up turn", () => {
  const event = { name: "agent-a", timeoutMs: 1000, outcome: "completed" as const, timestamp: "now" };
  const settled = new Set<string>();
  const entries: unknown[] = [];
  const notifications: Array<{ message: string; level: string }> = [];
  const messages: unknown[] = [];
  const result = deliverWaitEvent(event, false, settled, {
    appendEntry: (_type, value) => entries.push(value),
    notify: (message, level) => notifications.push({ message, level }),
    sendMessage: (message, options) => messages.push({ message, options }),
  });
  assert.deepEqual(result, { delivered: true, persisted: true, notified: true, sent: true, errors: [] });
  assert.deepEqual(entries, [event]);
  assert.equal(notifications[0]?.level, "info");
  assert.match(notifications[0]?.message ?? "", /allye_runtime collect/);
  assert.equal(messages.length, 1);
  assert.deepEqual((messages[0] as { options: unknown }).options, { triggerTurn: true, deliverAs: "followUp" });
});

test("wait settlement remains durable when notification or follow-up delivery fails", () => {
  const event = { name: "agent-b", timeoutMs: 1000, outcome: "timeout" as const, timestamp: "now" };
  const errors: string[] = [];
  const result = deliverWaitEvent(event, false, new Set<string>(), {
    appendEntry: () => undefined,
    notify: () => { throw new Error("ui unavailable"); },
    sendMessage: () => { throw new Error("session unavailable"); },
  });
  errors.push(...result.errors);
  assert.equal(result.persisted, true);
  assert.equal(result.notified, false);
  assert.equal(result.sent, false);
  assert.equal(result.errors.length, 2);
  assert.match(errors.join(" "), /ui unavailable/);
  assert.match(errors.join(" "), /session unavailable/);
  assert.equal(waitEventNotificationLevel(event), "warning");
  assert.equal(deliverWaitEvent(event, true, new Set<string>(), { appendEntry: () => undefined }).delivered, false);
});

test("multi-team initialization without an active team requires explicit selection", () => {
  const state = inspectTeamSelection(`初始化\n\`\`\`json
{"profile":{"teams":[{"id":"team-a","name":"Development","prefix":"TEMA"},{"id":"team-b","name":"BeachApp","prefix":"BEAC"}]}}
\`\`\``);
  assert.equal(state.teamSelectionRequired, true);
  assert.equal(state.teams.length, 2);
  assert.match(state.text, /team_switch/);
  assert.match(state.text, /never choose a team silently/i);
});

test("invalid initialization is fail-closed and distinct from a resolved team", () => {
  const state = invalidStartupContext("network down");
  assert.equal(state.teamSelectionRequired, true);
  assert.equal(state.allyeUnavailable, true);
  assert.match(state.text, /bootstrap blocked/);
  assert.match(state.text, /team_switch/);
});

test("Hermes always wins orchestration mode resolution", () => {
  assert.equal(resolveOrchestrationMode({ ALLYE_PI_MODE: "orchestrator", ALLYE_ORCHESTRATOR: "hermes" }), "hermes");
  assert.equal(resolveOrchestrationMode({ ALLYE_PI_MODE: "orchestrator" }), "pi");
});

test("pane ownership accepts only registered panes and layout metadata", () => {
  const state = { panes: [{ workspaceId: "w1", tabId: "t1", paneId: "p1" }], waits: new Set<string>() };
  assert.equal(canUseOwnedPane(state, "p1"), true);
  assert.equal(canUseOwnedPane(state, "p2"), false);
  assert.deepEqual(collectPaneRecords({ layout: { workspace_id: "w1", tab_id: "t1", panes: [{ pane_id: "p1" }, { pane_id: "p2" }] } }), [
    { workspaceId: "w1", tabId: "t1", paneId: "p1" },
    { workspaceId: "w1", tabId: "t1", paneId: "p2" },
  ]);
});

test("local claim rejects incompatible ownership and accepts the same claim", () => {
  const existing = { runId: "run-a", workItemKey: "TEMA-1", master: "hermes" as const, pid: 10, ownerToken: "owner-a", claimedAt: "now", leaseExpiresAt: "2099-01-01T00:00:00.000Z" };
  const requested = { runId: "run-b", workItemKey: "TEMA-1", master: "pi" as const, pid: 20, ownerToken: "owner-b", claimedAt: "now", leaseExpiresAt: "2099-01-01T00:00:00.000Z" };
  assert.match(claimConflict(existing, requested) ?? "", /ownership conflict/);
  assert.equal(claimConflict(existing, { ...existing }), null);
});

function testClaim(overrides: Partial<{ runId: string; workItemKey: string; master: "pi" | "hermes"; pid: number; ownerToken: string; claimedAt: string; leaseExpiresAt: string }> = {}) {
  return {
    runId: "run-a",
    workItemKey: "TEMA-1",
    master: "pi" as const,
    pid: process.pid,
    ownerToken: "owner-a",
    claimedAt: new Date().toISOString(),
    leaseExpiresAt: new Date(Date.now() + 60_000).toISOString(),
    ...overrides,
  };
}

test("same owner releases its lock but another owner cannot", () => {
  const root = mkdtempSync(`${tmpdir()}/allye-pi-release-`);
  const previous = process.env.ALLYE_PI_LOCK_DIR;
  process.env.ALLYE_PI_LOCK_DIR = root;
  const owner = testClaim();
  const other = testClaim({ ownerToken: "owner-b", pid: process.pid + 1 });
  acquireLocalClaim(root, owner);
  assert.equal(releaseLocalClaim(other), false);
  assert.equal(releaseLocalClaim(owner), true);
  assert.equal(releaseLocalClaim(owner), false);
  if (previous === undefined) delete process.env.ALLYE_PI_LOCK_DIR;
  else process.env.ALLYE_PI_LOCK_DIR = previous;
  rmSync(root, { recursive: true, force: true });
});

test("stale lock recovery requires explicit opt-in, expired lease, and dead PID", () => {
  const root = mkdtempSync(`${tmpdir()}/allye-pi-stale-`);
  const previous = process.env.ALLYE_PI_LOCK_DIR;
  const previousRecovery = process.env.ALLYE_PI_RECOVER_STALE_LOCK;
  process.env.ALLYE_PI_LOCK_DIR = root;
  process.env.ALLYE_PI_RECOVER_STALE_LOCK = "1";
  const stale = testClaim({ pid: 999999999, ownerToken: "stale", leaseExpiresAt: "2000-01-01T00:00:00.000Z" });
  const next = testClaim({ runId: "run-b", ownerToken: "next" });
  acquireLocalClaim(root, stale);
  acquireLocalClaim(root, next);
  assert.equal(releaseLocalClaim(next), true);
  if (previous === undefined) delete process.env.ALLYE_PI_LOCK_DIR;
  else process.env.ALLYE_PI_LOCK_DIR = previous;
  if (previousRecovery === undefined) delete process.env.ALLYE_PI_RECOVER_STALE_LOCK;
  else process.env.ALLYE_PI_RECOVER_STALE_LOCK = previousRecovery;
  rmSync(root, { recursive: true, force: true });
});

test("active or inconclusive lock fails closed even with stale recovery enabled", () => {
  const root = mkdtempSync(`${tmpdir()}/allye-pi-active-`);
  const previous = process.env.ALLYE_PI_LOCK_DIR;
  const previousRecovery = process.env.ALLYE_PI_RECOVER_STALE_LOCK;
  process.env.ALLYE_PI_LOCK_DIR = root;
  process.env.ALLYE_PI_RECOVER_STALE_LOCK = "1";
  const active = testClaim({ ownerToken: "active", pid: process.pid, leaseExpiresAt: "2000-01-01T00:00:00.000Z" });
  acquireLocalClaim(root, active);
  assert.throws(() => acquireLocalClaim(root, testClaim({ runId: "run-b", ownerToken: "next" })), /owner process is active/);
  if (previous === undefined) delete process.env.ALLYE_PI_LOCK_DIR;
  else process.env.ALLYE_PI_LOCK_DIR = previous;
  if (previousRecovery === undefined) delete process.env.ALLYE_PI_RECOVER_STALE_LOCK;
  else process.env.ALLYE_PI_RECOVER_STALE_LOCK = previousRecovery;
  rmSync(root, { recursive: true, force: true });
});

test("shutdown aborts waits and releases only the owned claim", () => {
  const root = mkdtempSync(`${tmpdir()}/allye-pi-shutdown-`);
  const previous = process.env.ALLYE_PI_LOCK_DIR;
  process.env.ALLYE_PI_LOCK_DIR = root;
  const claim = testClaim();
  acquireLocalClaim(root, claim);
  const controller = new AbortController();
  const waits = new Map([["agent-a", controller]]);
  const ownership = { claim, panes: [], waits: new Set(["agent-a"]) };
  assert.equal(shutdownOwnership(ownership, waits), true);
  assert.equal(controller.signal.aborted, true);
  assert.equal(waits.size, 0);
  assert.equal(ownership.claim, undefined);
  if (previous === undefined) delete process.env.ALLYE_PI_LOCK_DIR;
  else process.env.ALLYE_PI_LOCK_DIR = previous;
  rmSync(root, { recursive: true, force: true });
});

test("local claim is exclusive across incompatible processes", () => {
  const cwd = mkdtempSync(`${tmpdir()}/allye-pi-claim-`);
  const previous = process.env.ALLYE_PI_LOCK_DIR;
  process.env.ALLYE_PI_LOCK_DIR = cwd;
  const existing = { runId: "run-a", workItemKey: "TEMA-1", master: "pi" as const, pid: 10, ownerToken: "owner-a", claimedAt: "now", leaseExpiresAt: "2099-01-01T00:00:00.000Z" };
  const requested = { runId: "run-b", workItemKey: "TEMA-1", master: "pi" as const, pid: 20, ownerToken: "owner-b", claimedAt: "now", leaseExpiresAt: "2099-01-01T00:00:00.000Z" };
  acquireLocalClaim(cwd, existing);
  assert.throws(() => acquireLocalClaim(cwd, requested), /ownership conflict/);
  if (previous === undefined) delete process.env.ALLYE_PI_LOCK_DIR;
  else process.env.ALLYE_PI_LOCK_DIR = previous;
  rmSync(cwd, { recursive: true, force: true });
});

test("an active team avoids the selection gate", () => {
  const state = inspectTeamSelection(`\`\`\`json
{"profile":{"teams":[{"id":"team-a","name":"Development"},{"id":"team-b","name":"BeachApp"}],"team":{"id":"team-a","name":"Development"}}}
\`\`\``);
  assert.equal(state.teamSelectionRequired, false);
  assert.equal(state.text, "");
});
