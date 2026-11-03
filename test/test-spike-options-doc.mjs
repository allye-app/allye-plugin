// Checks the ALY-288 permission-options spike document and its scrubbed fixtures.
// Offline, no dependencies. SPIKE_GATE=1 adds the verdict gate (AC-07).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const DOC = "docs/spikes/live-permission-options.md";
const FX_DIR = "hooks/fixtures/live";
const read = (p) => readFileSync(join(root, p), "utf8");
const pad = (n) => String(n).padStart(2, "0");
const range = (p, n) => Array.from({ length: n }, (_, i) => p + pad(i + 1));
const IDS = [...range("S", 24), ...range("T", 28)];

// Checkers return an array of problems (empty = ok).
export function checkLines(text) {
  const problems = [];
  const lines = text.split("\n");
  for (const id of IDS) {
    const hits = lines.filter((l) => l.startsWith(id + " "));
    if (hits.length !== 1) problems.push(`${id}: expected exactly one line, found ${hits.length}`);
    else if (hits[0].slice(id.length).trim() === "") problems.push(`${id}: empty answer`);
  }
  return problems;
}

const VERDICT_RE = /^VERDICT: update=(go|no-go) auto=(go|no-go) late=(safe|unsafe) beat=(none|found)$/;
const lastLine = (text) => text.split("\n").filter((l) => l.trim() !== "").pop() ?? "";
export function checkVerdict(text) {
  const last = lastLine(text);
  return VERDICT_RE.test(last) ? [] : [`bad last line: ${last}`];
}

export function checkGate(text) {
  const problems = [];
  if (!/^VERDICT: update=go auto=(go|no-go) late=safe beat=none$/.test(lastLine(text))) {
    problems.push(`verdict is not update=go late=safe beat=none: ${lastLine(text)}`);
  }
  const s22 = text.split("\n").find((l) => l.startsWith("S22 ")) ?? "";
  if (!/(^|\s)settings\.json=identical(\s|$)/.test(s22)) problems.push("S22: settings.json is not identical");
  if (!/(^|\s)settings\.local\.json=(identical|absent-unchanged)(\s|$)/.test(s22)) problems.push("S22: settings.local.json is not identical/unchanged");
  if (!/(^|\s)opens=0(\s|$)/.test(s22)) problems.push("S22: opens=0 not recorded");
  return problems;
}

export function checkScrub(text) {
  const problems = [];
  for (const bad of ["/home/", "/Users/", "alyh_", "Bearer", "sk-ant-"]) {
    if (text.includes(bad)) problems.push(`contains ${bad}`);
  }
  if (/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(text)) problems.push("uuid");
  if (/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}/.test(text)) problems.push("email");
  if (/\b(ghp|gho|xox[bp])_[A-Za-z0-9]{10,}/.test(text)) problems.push("token shape");
  if (/\btoolu_[A-Za-z0-9]{8,}/.test(text)) problems.push("tool id");
  return problems;
}

const PLACEHOLDER = /^<[a-z]+>$/;
const SCRUBBED_KEYS = new Set(["ruleContent", "tool_input", "session_id", "cwd", "transcript_path", "scratchpad_dir", "prompt_id", "agent_id"]);
// AC-04: these fields must hold only a placeholder (every leaf under them).
function leaves(v, out = []) {
  if (v !== null && typeof v === "object") for (const x of Object.values(v)) leaves(x, out);
  else out.push(v);
  return out;
}
export function checkFixture(obj) {
  const problems = [];
  const walk = (node, path) => {
    if (Array.isArray(node)) return node.forEach((x, i) => walk(x, `${path}[${i}]`));
    if (node === null || typeof node !== "object") return;
    for (const [k, v] of Object.entries(node)) {
      const p = `${path}.${k}`;
      if (SCRUBBED_KEYS.has(k) || k === "directories" || (k === "toolName" && /rules\[\d+\]$/.test(path))) {
        for (const leaf of leaves(v)) {
          if (typeof leaf !== "string" || !PLACEHOLDER.test(leaf)) problems.push(`${p}: not scrubbed`);
        }
      } else walk(v, p);
    }
  };
  walk(obj, "$");
  const MODES = ["acceptEdits", "auto", "default", "plan", "bypassPermissions", "dontAsk"];
  const DESTS = ["session", "localSettings", "projectSettings", "userSettings"];
  if (typeof obj.permission_mode === "string" && !MODES.includes(obj.permission_mode)) problems.push(`permission_mode ${obj.permission_mode}`);
  const list = obj.permission_suggestions;
  if (list !== undefined && list !== null && !Array.isArray(list)) problems.push("permission_suggestions not a list");
  for (const [i, e] of (Array.isArray(list) ? list : []).entries()) {
    const at = `permission_suggestions[${i}]`;
    if (!["addDirectories", "addRules", "setMode"].includes(e.type)) problems.push(`${at}: type ${e.type}`);
    if (!DESTS.includes(e.destination)) problems.push(`${at}: destination ${e.destination}`);
    if (e.type === "setMode" && !MODES.includes(e.mode)) problems.push(`${at}: mode ${e.mode}`);
    if (e.type === "addRules" && !["allow", "deny"].includes(e.behavior)) problems.push(`${at}: behavior ${e.behavior}`);
  }
  return problems;
}

const fixtureFiles = () =>
  readdirSync(join(root, FX_DIR)).filter((f) => /^spike-options-.+\.json$/.test(f)).sort();

test("doc has one non-empty line per S01..S24 and T01..T28", () => {
  assert.deepEqual(checkLines(read(DOC)), []);
});

test("doc ends with a verdict line", () => {
  assert.deepEqual(checkVerdict(read(DOC)), []);
});

test("doc has no home path, token shape or email", () => {
  assert.deepEqual(checkScrub(read(DOC)), []);
});

test("fixtures parse, are scrubbed and carry literal type, behavior, mode, destination", () => {
  const files = fixtureFiles();
  assert.ok(files.length >= 8, `expected fixtures, found ${files.length}`);
  for (const f of files) {
    const text = read(join(FX_DIR, f));
    const obj = JSON.parse(text);
    assert.deepEqual(checkScrub(text), [], f);
    assert.deepEqual(checkFixture(obj), [], f);
    assert.equal(obj.hook_event_name, "PermissionRequest", f);
    for (const e of obj.permission_suggestions ?? []) {
      assert.ok(["addDirectories", "addRules", "setMode"].includes(e.type), `${f}: type ${e.type}`);
      assert.ok(["session", "localSettings", "projectSettings"].includes(e.destination), `${f}: destination`);
    }
  }
});

test("SPIKE_GATE: verdict, settings identical, zero opens", { skip: process.env.SPIKE_GATE !== "1" }, () => {
  assert.deepEqual(checkGate(read(DOC)), []);
});

test("negative control: lines", () => {
  const full = IDS.map((id) => `${id} ok`).join("\n");
  assert.deepEqual(checkLines(full), []);
  assert.notDeepEqual(checkLines(full.replace("S05 ok", "S05 ")), []);
  assert.notDeepEqual(checkLines(full.replace("T28 ok", "")), []);
  assert.notDeepEqual(checkLines(full + "\nS24 dup"), []);
  assert.notDeepEqual(checkLines(full + "\nT01 dup"), []);
});

test("negative control: verdict", () => {
  assert.deepEqual(checkVerdict("x\nVERDICT: update=go auto=go late=safe beat=none\n\n"), []);
  assert.notDeepEqual(checkVerdict("S01 x\n"), []);
  assert.notDeepEqual(checkVerdict("VERDICT: update=maybe auto=go late=safe beat=none\n"), []);
  assert.notDeepEqual(checkVerdict("VERDICT: update=go auto=go late=safe beat=none\ntrailing\n"), []);
  assert.notDeepEqual(checkVerdict("VERDICT: update=go auto=go late=safe\n"), []);
});

test("negative control: gate", () => {
  const ok = "S22 settings.json=identical settings.local.json=absent-unchanged claude.json=changed-evidence-only opens=0\nVERDICT: update=go auto=go late=safe beat=none\n";
  assert.deepEqual(checkGate(ok), []);
  assert.notDeepEqual(checkGate(ok.replace("update=go", "update=no-go")), []);
  assert.notDeepEqual(checkGate(ok.replace("late=safe", "late=unsafe")), []);
  assert.notDeepEqual(checkGate(ok.replace("beat=none", "beat=found")), []);
  assert.notDeepEqual(checkGate(ok.replace("settings.json=identical", "settings.json=changed")), []);
  assert.notDeepEqual(checkGate(ok.replace("absent-unchanged", "changed")), []);
  assert.notDeepEqual(checkGate(ok.replace("opens=0", "opens=2")), []);
  assert.notDeepEqual(checkGate(ok.replace("S22 ", "S22x ")), []);
});

test("negative control: scrub patterns", () => {
  assert.deepEqual(checkScrub("<string> /tmp/x"), []);
  assert.notDeepEqual(checkScrub("/home/x"), []);
  assert.notDeepEqual(checkScrub("/Users/x"), []);
  assert.notDeepEqual(checkScrub("Bearer abc"), []);
  assert.notDeepEqual(checkScrub("alyh_abc"), []);
  assert.notDeepEqual(checkScrub("someone@example.com"), []);
  assert.notDeepEqual(checkScrub("123e4567-e89b-12d3-a456-426614174000"), []);
  assert.notDeepEqual(checkScrub("toolu_01AbCdEfGh"), []);
});

test("negative control: fixture fields", () => {
  const good = {
    session_id: "<string>", cwd: "<string>", transcript_path: "<string>", tool_input: { command: "<string>" },
    permission_suggestions: [
      { type: "addDirectories", directories: ["<string>"], destination: "session" },
      { type: "addRules", rules: [{ toolName: "<string>", ruleContent: "<string>" }], behavior: "allow", destination: "localSettings" },
    ],
  };
  good.permission_mode = "default";
  good.permission_suggestions.push({ type: "setMode", mode: "acceptEdits", destination: "session" });
  assert.deepEqual(checkFixture(good), []);
  const bad = (mut) => { const c = structuredClone(good); mut(c); return checkFixture(c); };
  assert.notDeepEqual(bad((c) => { c.session_id = "abc"; }), []);
  assert.notDeepEqual(bad((c) => { c.cwd = "/tmp/x"; }), []);
  assert.notDeepEqual(bad((c) => { c.transcript_path = "x"; }), []);
  assert.notDeepEqual(bad((c) => { c.tool_input.command = "ls"; }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions[0].directories[0] = "/tmp"; }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions[1].rules[0].ruleContent = "git x"; }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions[1].rules[0].toolName = "Bash"; }), []);
  assert.notDeepEqual(bad((c) => { c.scratchpad_dir = "/tmp/x"; }), []);
  assert.notDeepEqual(bad((c) => { c.prompt_id = "p1"; }), []);
  assert.notDeepEqual(bad((c) => { c.agent_id = "a1"; }), []);
  assert.notDeepEqual(bad((c) => { c.permission_mode = "weird"; }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions[1].behavior = "maybe"; }), []);
  assert.notDeepEqual(bad((c) => { delete c.permission_suggestions[1].behavior; }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions[1].destination = "userSettings2"; }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions.push({ type: "setMode", destination: "session" }); }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions.push({ type: "setMode", mode: "<string>", destination: "session" }); }), []);
  assert.notDeepEqual(bad((c) => { c.permission_suggestions.push({ type: "bogus", destination: "session" }); }), []);
});
