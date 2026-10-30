// Checks the ALY-269 return-channel spike document and its scrubbed fixtures.
// Offline, no dependencies.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const DOC = "docs/spikes/live-return-channel.md";
const FX = {
  perm: "hooks/fixtures/live/spike-permission-request.json",
  ask: "hooks/fixtures/live/spike-ask-question.json",
  post: "hooks/fixtures/live/spike-post-tool-use.json",
};
const read = (p) => readFileSync(join(root, p), "utf8");

const IDS = ["A01", "A02", "A03", "A04", "A05", "A06", "A07", "A08", "A09", "A10"];

// Checkers return an array of problems (empty = ok).
export function checkAnswerLines(text) {
  const problems = [];
  const lines = text.split("\n");
  for (const id of IDS) {
    const hits = lines.filter((l) => l.startsWith(id + " "));
    if (hits.length !== 1) problems.push(`${id}: expected exactly one line, found ${hits.length}`);
    else if (hits[0].slice(id.length).trim() === "") problems.push(`${id}: empty answer`);
  }
  return problems;
}

const TERMS = {
  A01: [/PermissionRequest/], A02: [/PreToolUse/], A03: [/SIGTERM/], A04: [/timeout/],
  A05: [/updatedInput/], A06: [/PermissionRequest/, /tool_use_id/], A07: [/PostToolUseFailure/, /tool_use_id/],
  A08: [/AskUserQuestion/], A09: [/deny/], A10: [/allow/, /deny/],
};
export function checkTerms(text) {
  const problems = [];
  for (const [id, res] of Object.entries(TERMS)) {
    const line = text.split("\n").find((l) => l.startsWith(id + " ")) ?? "";
    for (const re of res) if (!re.test(line)) problems.push(`${id}: missing ${re}`);
  }
  return problems;
}

export function checkVerdict(text) {
  const last = text.split("\n").filter((l) => l.trim() !== "").pop() ?? "";
  return /^VERDICT: permission=(go|no-go) question=(go|no-go)$/.test(last)
    ? []
    : [`bad last line: ${last}`];
}

export function checkDesign(text) {
  const problems = [];
  if (!/question[^\n]*PermissionRequest/i.test(text)) problems.push("question path via PermissionRequest not stated");
  if (!/PostToolUseFailure[^\n]*tool_use_id/.test(text)) problems.push("PostToolUseFailure tool_use_id not stated");
  return problems;
}

export function checkScrub(text) {
  const problems = [];
  for (const bad of ["/home/", "/Users/", "alyh_", "Bearer"]) {
    if (text.includes(bad)) problems.push(`contains ${bad}`);
  }
  if (/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(text)) problems.push("uuid");
  for (const m of text.match(/toolu_[A-Za-z0-9_]+/g) ?? []) {
    if (m !== "toolu_SCRUBBED") problems.push(`tool id ${m}`);
  }
  return problems;
}

test("doc has one non-empty line per A01..A10", () => {
  assert.deepEqual(checkAnswerLines(read(DOC)), []);
});

test("doc ends with a verdict line", () => {
  assert.deepEqual(checkVerdict(read(DOC)), []);
});

test("doc states the design consequences", () => {
  assert.deepEqual(checkDesign(read(DOC)), []);
});

test("doc lines carry their key terms", () => {
  assert.deepEqual(checkTerms(read(DOC)), []);
});

test("doc has no home path, uuid or foreign tool id", () => {
  assert.ok(!read(DOC).includes("/home/"));
  assert.deepEqual(checkScrub(read(DOC)), []);
});

test("fixtures parse and are scrubbed", () => {
  for (const p of Object.values(FX)) {
    JSON.parse(read(p));
    assert.deepEqual(checkScrub(read(p)), [], p);
  }
});

test("tool_use_id absent from PermissionRequest, present in PostToolUse", () => {
  const perm = JSON.parse(read(FX.perm));
  const ask = JSON.parse(read(FX.ask));
  const post = JSON.parse(read(FX.post));
  assert.equal(perm.hook_event_name, "PermissionRequest");
  assert.equal(ask.hook_event_name, "PermissionRequest");
  assert.equal(post.hook_event_name, "PostToolUse");
  assert.ok(!("tool_use_id" in perm));
  assert.ok(!("tool_use_id" in ask));
  assert.ok(Array.isArray(ask.tool_input.questions) && ask.tool_input.questions.length > 0);
  assert.equal(typeof post.tool_use_id, "string");
});

test("negative control: answer lines", () => {
  const full = IDS.map((id) => `${id} ok`).join("\n");
  assert.deepEqual(checkAnswerLines(full), []);
  assert.notDeepEqual(checkAnswerLines(full.replace("A05 ok", "A05 ")), []);
  assert.notDeepEqual(checkAnswerLines(full.replace("A07 ok\n", "")), []);
  assert.notDeepEqual(checkAnswerLines(full + "\nA02 dup"), []);
});

test("negative control: verdict", () => {
  assert.deepEqual(checkVerdict("x\nVERDICT: permission=go question=no-go\n\n"), []);
  assert.notDeepEqual(checkVerdict("A01 x\n"), []);
  assert.notDeepEqual(checkVerdict("VERDICT: permission=maybe question=go\n"), []);
  assert.notDeepEqual(checkVerdict("VERDICT: permission=go question=go\ntrailing text\n"), []);
});

test("negative control: terms and design", () => {
  assert.notDeepEqual(checkTerms("A06 nothing"), []);
  assert.notDeepEqual(checkDesign("nothing here"), []);
});

test("negative control: one assertion per scrub pattern", () => {
  assert.deepEqual(checkScrub("toolu_SCRUBBED /path/SCRUBBED"), []);
  assert.notDeepEqual(checkScrub("/home/x"), []);
  assert.notDeepEqual(checkScrub("/Users/x"), []);
  assert.notDeepEqual(checkScrub("alyh_abc"), []);
  assert.notDeepEqual(checkScrub("Bearer abc"), []);
  assert.notDeepEqual(checkScrub("123e4567-e89b-12d3-a456-426614174000"), []);
  assert.notDeepEqual(checkScrub("toolu_01AbCdEf"), []);
});
