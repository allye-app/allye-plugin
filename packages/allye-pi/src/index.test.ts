import assert from "node:assert/strict";
import test from "node:test";
import {
  activeToolsForCapabilities,
  adaptiveInstructions,
  classifyWaitResult,
  deliverWaitEvent,
  describeCapabilities,
  formatWaitEvent,
  inspectTeamSelection,
  invalidStartupContext,
  loadUsingAllyeSkill,
  shouldEmitWaitEvent,
  waitEventNotificationLevel,
} from "./index.ts";

test("using-allye remains available as the startup bootstrap skill", () => {
  assert.match(loadUsingAllyeSkill(), /Default posture/);
  assert.match(loadUsingAllyeSkill(), /adaptive toolkit/);
});

test("adaptive capabilities expose optional Herdr without a workflow mode", () => {
  assert.deepEqual(describeCapabilities({ HERDR_ENV: "1", ALLYE_PI_MCP: "1", ALLYE_PI_SUBAGENTS: "1" }, true), { piSession: true, allyeMcp: true, filesystem: true, subagents: true, herdr: true });
  assert.deepEqual(describeCapabilities({ ALLYE_PI_MCP: "0" }, true), { piSession: true, allyeMcp: false, filesystem: true, subagents: false, herdr: false });
  assert.match(adaptiveInstructions({ piSession: true, allyeMcp: false, filesystem: true, subagents: false, herdr: false }), /not a mandatory workflow/i);
  assert.deepEqual(activeToolsForCapabilities(["read", "allye_herdr"], { piSession: true, allyeMcp: true, filesystem: true, subagents: false, herdr: false }), ["read"]);
  assert.deepEqual(activeToolsForCapabilities(["read"], { piSession: true, allyeMcp: true, filesystem: true, subagents: false, herdr: true }), ["read", "allye_herdr"]);
});

test("wait events classify outcomes and require collection before a verdict", () => {
  assert.equal(classifyWaitResult({ code: 0, killed: false, stdout: "done", stderr: "" }, 1000), "completed");
  assert.equal(classifyWaitResult({ code: 1, killed: false, stdout: "", stderr: "failed" }, 1000), "error");
  assert.equal(classifyWaitResult({ code: 1, killed: true, stdout: "", stderr: "" }, 1000), "timeout");
  assert.equal(classifyWaitResult(undefined, 1000, new Error("aborted by shutdown")), "aborted");
  const text = formatWaitEvent({ name: "agent-a", timeoutMs: 1000, outcome: "completed", timestamp: "now" });
  assert.match(text, /delegation evidence only/i);
  assert.match(text, /allye_herdr collect/i);
});

test("wait settlement persists, notifies, and queues a follow-up", () => {
  const event = { name: "agent-a", timeoutMs: 1000, outcome: "completed" as const, timestamp: "now" };
  const entries: unknown[] = [];
  const notifications: Array<{ message: string; level: string }> = [];
  const messages: unknown[] = [];
  const result = deliverWaitEvent(event, false, new Set(), {
    appendEntry: (_type, value) => entries.push(value),
    notify: (message, level) => notifications.push({ message, level }),
    sendMessage: (message, options) => messages.push({ message, options }),
  });
  assert.deepEqual(result, { delivered: true, persisted: true, notified: true, sent: true, errors: [] });
  assert.deepEqual(entries, [event]);
  assert.equal(notifications[0]?.level, "info");
  assert.equal(messages.length, 1);
  assert.deepEqual((messages[0] as { options: unknown }).options, { triggerTurn: true, deliverAs: "followUp" });
});

test("wait settlement is suppressed after shutdown and duplicate settlement", () => {
  const settled = new Set<string>();
  assert.equal(shouldEmitWaitEvent(false, settled, "agent-a"), true);
  assert.equal(shouldEmitWaitEvent(false, settled, "agent-a"), false);
  assert.equal(shouldEmitWaitEvent(true, settled, "agent-b"), false);
  assert.equal(deliverWaitEvent(
    { name: "agent-c", timeoutMs: 1000, outcome: "timeout", timestamp: "now" },
    true,
    new Set(),
    { appendEntry: () => undefined },
  ).delivered, false);
  assert.equal(waitEventNotificationLevel({ name: "x", timeoutMs: 1, outcome: "timeout", timestamp: "now" }), "warning");
});

test("wait delivery remains durable when optional channels fail", () => {
  const result = deliverWaitEvent(
    { name: "agent-b", timeoutMs: 1000, outcome: "error", timestamp: "now" },
    false,
    new Set(),
    {
      appendEntry: () => undefined,
      notify: () => { throw new Error("ui unavailable"); },
      sendMessage: () => { throw new Error("session unavailable"); },
    },
  );
  assert.equal(result.persisted, true);
  assert.equal(result.notified, false);
  assert.equal(result.sent, false);
  assert.equal(result.errors.length, 2);
});

test("unavailable Allye context does not block local work", () => {
  const state = invalidStartupContext("network down");
  assert.equal(state.teamSelectionRequired, false);
  assert.equal(state.allyeUnavailable, true);
  assert.match(state.text, /optional context unavailable/i);
  assert.match(state.text, /continue with local/i);
});

test("multi-team initialization requires an explicit team only when none is active", () => {
  const state = inspectTeamSelection(`\`\`\`json
{"profile":{"teams":[{"id":"team-a","name":"Development","prefix":"TEMA"},{"id":"team-b","name":"BeachApp","prefix":"BEAC"}]}}
\`\`\``);
  assert.equal(state.teamSelectionRequired, true);
  assert.match(state.text, /team_switch/);

  const active = inspectTeamSelection(`\`\`\`json
{"profile":{"teams":[{"id":"team-a","name":"Development"},{"id":"team-b","name":"BeachApp"}],"team":{"id":"team-a"}}}
\`\`\``);
  assert.equal(active.teamSelectionRequired, false);
});
