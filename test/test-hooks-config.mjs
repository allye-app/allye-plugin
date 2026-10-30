// Independent guard (ALY-269 AC-11, AC-06) over hooks/hooks.json and the answer budget of hooks/live-answer.sh.
// Offline, no dependencies, no wall-clock assertions, never runs a hook.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (p) => readFileSync(join(root, p), "utf8");
const ANSWER_CMD = "${CLAUDE_PLUGIN_ROOT}/hooks/live-answer.sh";
const MAX_TIMEOUT = 120;

// Flatten hooks.json into {event, matcher, hook} entries.
export function entries(cfg) {
  const out = [];
  for (const [event, groups] of Object.entries(cfg.hooks ?? {})) {
    for (const g of groups) for (const hook of g.hooks ?? []) out.push({ event, matcher: g.matcher, hook });
  }
  return out;
}
const isBlocking = (e) => e.hook.async !== true;

// Checkers return an array of problems (empty = ok).
export function checkTimeouts(cfg) {
  const problems = [];
  for (const e of entries(cfg).filter(isBlocking)) {
    const t = e.hook.timeout;
    if (typeof t !== "number" || !(t > 0) || t > MAX_TIMEOUT) {
      problems.push(`${e.event}: blocking hook ${e.hook.command} needs a numeric timeout in (0, ${MAX_TIMEOUT}], got ${t}`);
    }
  }
  return problems;
}

export function checkPreToolUse(cfg) {
  const problems = [];
  for (const e of entries(cfg).filter((x) => x.event === "PreToolUse")) {
    if (isBlocking(e)) problems.push(`PreToolUse: blocking hook ${e.hook.command}`);
    if (String(e.hook.command).includes("live-answer.sh")) problems.push("PreToolUse: runs live-answer.sh");
  }
  return problems;
}

export function checkAnswerHook(cfg) {
  const problems = [];
  const blocking = entries(cfg).filter((e) => e.event === "PermissionRequest" && isBlocking(e));
  if (blocking.length !== 1) return [`PermissionRequest: expected exactly one blocking hook, found ${blocking.length}`];
  const [e] = blocking;
  if (e.hook.command !== ANSWER_CMD) problems.push(`PermissionRequest: blocking command is ${e.hook.command}`);
  if (e.matcher !== "") problems.push(`PermissionRequest: matcher must be the empty string, got ${JSON.stringify(e.matcher)}`);
  if (e.hook.timeout !== 120) problems.push(`PermissionRequest: timeout must be 120, got ${e.hook.timeout}`);
  return problems;
}

export function checkAsyncReporters(cfg) {
  const problems = [];
  for (const e of entries(cfg).filter((x) => String(x.hook.command).endsWith("/live-report.sh") && x.event !== "SessionEnd")) {
    if (e.hook.async !== true) problems.push(`${e.event}: live-report.sh must be async`);
    if (typeof e.hook.timeout !== "number") problems.push(`${e.event}: async reporter needs a timeout`);
  }
  return problems;
}

export function parseBudget(script) {
  const m = script.match(/^ANSWER_BUDGET_DEFAULT=(\d+)\s*$/m);
  return m ? Number(m[1]) : null;
}

export function checkBudget(cfg, script) {
  const problems = [];
  const budget = parseBudget(script);
  if (budget !== 110) problems.push(`ANSWER_BUDGET_DEFAULT must be 110, got ${budget}`);
  const [e] = entries(cfg).filter((x) => x.event === "PermissionRequest" && isBlocking(x));
  if (budget !== null && (!e || typeof e.hook.timeout !== "number" || e.hook.timeout < budget + 10)) {
    problems.push(`hooks.json timeout ${e?.hook.timeout} must be >= budget + 10 (${budget + 10})`);
  }
  return problems;
}

// The override can only lower the budget: the cap line must compare it with -lt "$ANSWER_BUDGET_DEFAULT".
export function checkOverrideOnlyLowers(script) {
  const lines = script.split("\n").filter((l) => l.includes("LIVE_ANSWER_BUDGET_S") && l.includes("BUDGET=$(("));
  if (lines.length !== 1) return [`LIVE_ANSWER_BUDGET_S cap line not statically checkable (found ${lines.length} assignment lines)`];
  return /-lt\s+"\$ANSWER_BUDGET_DEFAULT"/.test(lines[0])
    ? []
    : ['LIVE_ANSWER_BUDGET_S cap line lacks -lt "$ANSWER_BUDGET_DEFAULT"'];
}

const cfgOf = (event, groups) => ({ hooks: { [event]: groups } });
const answerHook = { type: "command", command: ANSWER_CMD, timeout: 120 };
const validCfg = () => cfgOf("PermissionRequest", [{ matcher: "", hooks: [{ ...answerHook }] }]);

// ---- real files
const real = JSON.parse(read("hooks/hooks.json"));
const script = read("hooks/live-answer.sh");

test("real hooks.json: every blocking hook has a timeout in (0, 120]", () => {
  assert.deepEqual(checkTimeouts(real), []);
});
test("real hooks.json: exactly one blocking PermissionRequest hook, the answer hook", () => {
  assert.deepEqual(checkAnswerHook(real), []);
});
test("real hooks.json: PreToolUse has no blocking hook and does not run live-answer.sh", () => {
  assert.deepEqual(checkPreToolUse(real), []);
  assert.ok(entries(real).some((e) => e.event === "PreToolUse"), "PreToolUse reporter entry expected");
});
test("real hooks.json: async reporters keep async and a timeout", () => {
  assert.deepEqual(checkAsyncReporters(real), []);
  assert.ok(entries(real).filter((e) => e.hook.async === true).length >= 10);
});
test("AC-06: answer budget is 110 and the hook timeout leaves 10 s", () => {
  assert.deepEqual(checkBudget(real, script), []);
});
test("AC-06: LIVE_ANSWER_BUDGET_S can only lower the budget", () => {
  assert.deepEqual(checkOverrideOnlyLowers(script), []);
});

// ---- negative controls
test("negative: blocking hook without timeout fails", () => {
  const cfg = cfgOf("SessionStart", [{ hooks: [{ type: "command", command: "x" }] }]);
  assert.equal(checkTimeouts(cfg).length, 1);
});
test("negative: timeout 121 fails, 120 passes", () => {
  const mk = (t) => cfgOf("SessionStart", [{ hooks: [{ type: "command", command: "x", timeout: t }] }]);
  assert.equal(checkTimeouts(mk(121)).length, 1);
  assert.deepEqual(checkTimeouts(mk(120)), []);
  assert.equal(checkTimeouts(mk(0)).length, 1);
});
test("negative: async hook without timeout is not a blocking hook", () => {
  const cfg = cfgOf("SessionStart", [{ hooks: [{ type: "command", command: "x", async: true }] }]);
  assert.deepEqual(checkTimeouts(cfg), []);
});
test("negative: blocking PreToolUse hook fails", () => {
  const cfg = cfgOf("PreToolUse", [{ hooks: [{ type: "command", command: "x", timeout: 5 }] }]);
  assert.equal(checkPreToolUse(cfg).length, 1);
  const cfg2 = cfgOf("PreToolUse", [{ hooks: [{ type: "command", command: ANSWER_CMD, async: true, timeout: 5 }] }]);
  assert.equal(checkPreToolUse(cfg2).length, 1);
});
test("negative: two blocking PermissionRequest hooks fail", () => {
  const cfg = cfgOf("PermissionRequest", [{ matcher: "", hooks: [{ ...answerHook }, { ...answerHook }] }]);
  assert.equal(checkAnswerHook(cfg).length, 1);
});
test("negative: non-empty matcher fails", () => {
  const cfg = cfgOf("PermissionRequest", [{ matcher: "Bash", hooks: [{ ...answerHook }] }]);
  assert.equal(checkAnswerHook(cfg).length, 1);
});
test("negative: missing answer hook fails", () => {
  const cfg = cfgOf("PermissionRequest", [{ hooks: [{ type: "command", command: "r", async: true, timeout: 20 }] }]);
  assert.equal(checkAnswerHook(cfg).length, 1);
  assert.deepEqual(checkAnswerHook(validCfg()), []);
});
test("negative: wrong command or timeout on the answer hook fails", () => {
  const a = cfgOf("PermissionRequest", [{ matcher: "", hooks: [{ ...answerHook, timeout: 100 }] }]);
  assert.equal(checkAnswerHook(a).length, 1);
  const b = cfgOf("PermissionRequest", [{ matcher: "", hooks: [{ ...answerHook, command: "other.sh" }] }]);
  assert.equal(checkAnswerHook(b).length, 1);
});
test("negative: budget pins", () => {
  assert.equal(checkBudget(validCfg(), "ANSWER_BUDGET_DEFAULT=100\n").length, 1);
  const tight = cfgOf("PermissionRequest", [{ matcher: "", hooks: [{ ...answerHook, timeout: 115 }] }]);
  assert.equal(checkBudget(tight, "ANSWER_BUDGET_DEFAULT=110\n").length, 1);
  assert.equal(checkBudget(validCfg(), "# nothing\n").length, 1);
  assert.deepEqual(checkBudget(validCfg(), "ANSWER_BUDGET_DEFAULT=110\n"), []);
});
test("negative: override that can raise the budget fails", () => {
  const bad = '*) if [ "$X" -ge 1 ]; then BUDGET=$((10#$LIVE_ANSWER_BUDGET_S)); fi ;;';
  assert.equal(checkOverrideOnlyLowers(bad).length, 1);
  assert.equal(checkOverrideOnlyLowers("none").length, 1);
});
test("negative: async reporter without async or timeout fails", () => {
  const cfg = cfgOf("Stop", [{ hooks: [{ type: "command", command: "${CLAUDE_PLUGIN_ROOT}/hooks/live-report.sh", timeout: 20 }] }]);
  assert.equal(checkAsyncReporters(cfg).length, 1);
});
