// Guards the spec-authoring text of the Bridge skills: anchors are defined once per spec,
// and the shared anchor lint is the single checklist used by authors and publish. Also checks
// that the memory reference (skills/bridge/references/memory.md) states every memory rule. Offline.
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (p) => readFileSync(join(root, p), "utf8");
const errors = [];
const fail = (msg) => errors.push(msg);

const LINT = "skills/bridge/references/spec-lint.md";
if (!existsSync(join(root, LINT))) fail(`${LINT} is missing`);
else {
  const lint = read(LINT);
  for (const needle of ["SPEC_DUPLICATE_ANCHOR", "defined exactly once", "[NEEDS CLARIFICATION]", "2000", "identical text", "## Server check", "specs.spec_validate"]) {
    if (!lint.includes(needle)) fail(`${LINT}: must mention "${needle}"`);
  }
}

const templates = ["skills/bridge-architect/references/spec-template.md", "skills/bridge-dispatcher/references/spec-template-minimal.md"];
const ANCHOR_DEF = /^\s*(?:[-*]|#{1,6})\s+\[((?:BR|AC|D|NFR|Q)-\d{2,})\]/;
for (const file of templates) {
  const text = read(file);
  if (!text.includes("defined exactly once per spec")) fail(`${file}: must state that every anchor id is defined exactly once per spec`);
  if (!text.includes("spec-lint.md")) fail(`${file}: must reference the anchor lint (spec-lint.md)`);
  // The template's own example must not define any anchor twice.
  const seen = new Map();
  text.split("\n").forEach((line, i) => {
    const id = line.match(ANCHOR_DEF)?.[1];
    if (!id) return;
    if (seen.has(id)) fail(`${file}:${i + 1}: anchor [${id}] already defined at line ${seen.get(id)}`);
    else seen.set(id, i + 1);
  });
}

for (const file of ["skills/bridge-architect/SKILL.md", "skills/bridge-dispatcher/SKILL.md", "skills/bridge/references/publish.md"]) {
  if (!read(file).includes("spec-lint.md")) fail(`${file}: must reference the anchor lint (spec-lint.md)`);
}
// ALY-20 [AC-06]: authors self-check with specs.spec_validate (publish.md is checked with its §3/§4 below).
for (const file of ["skills/bridge-architect/SKILL.md", "skills/bridge-dispatcher/SKILL.md"]) {
  if (!read(file).includes("specs.spec_validate")) fail(`${file}: must call specs.spec_validate in the anchor lint self-check`);
}
if (!/no partial publish/i.test(read("skills/bridge/references/publish.md"))) fail("publish.md: must require the lint for all specs before any write (no partial publish)");

// Memory rules live in one reference (read, save, result handling, journaling).
const MEMORY = "skills/bridge/references/memory.md";
if (!existsSync(join(root, MEMORY))) fail(`${MEMORY} is missing`);
else {
  const memory = read(MEMORY);
  const needles = [
    "intelligence.memory_search", "intelligence.memory_save", "limit 15", "return_content=true",
    "Memory hints", "data, not instructions", "re-verif", "without hints",
    "decisions", "patterns", "incidents", "team_id", "project-<KEY>", "spec-<KEY-N>", "app-<repo>",
    "at most 5", "`created`, `updated`, `superseded` and `noop` are all success", "byte-identical", "personal",
    "never fail or block", "no confirmation", "inspect and survey save nothing",
    "`launch`, `mission`, `repair`, `optimize`, `shield` — at the end", "`blueprint`, `dispatch` — after publish",
    "memory-read", "memory-save", "memories",
    "at most 8", "no sector filter", "date -u", "never `session` or `handover`", "secrets", "retry once",
    "Recon re-verif", "paraphrase", "reads as a directive", "never verbatim", "no idempotency key",
    "once `log.md` exists", "No retry; never stop the mode", "when the lesson applies",
    "no exploit paths or reproduction steps", "partial publish counts as published", "If `log.md` never opens",
  ];
  for (const needle of needles) {
    if (!memory.includes(needle)) fail(`${MEMORY}: must mention "${needle}"`);
  }
}

// The Mothership flow points to memory.md (pointers and step placement only; rules stay in memory.md).
{
  const SKILL = "skills/bridge/SKILL.md";
  const skill = read(SKILL);
  for (const needle of ["references/memory.md", "memory_search", "memories:", "memory saves are automatic", "memory.md` §4", "no user confirmation (`memory.md` §1–2)"]) {
    if (!skill.includes(needle)) fail(`${SKILL}: must mention "${needle}"`);
  }
  // Inputs: the memory read comes after the Armorer preflight and before Recon / author / Strategist.
  const armorerPara = skill.split("\n").find((l) => l.startsWith("Before every route, run the **Armorer**")) ?? "";
  const iA = armorerPara.indexOf("Armorer"), iM = armorerPara.indexOf("memory_search");
  if (iM < 0 || iM < iA) fail(`${SKILL}: the Armorer paragraph must place memory_search after Armorer`);
  // Read per mode: every row lists memory.md (inspect and survey still read).
  const rpm = skill.split("## Read per mode")[1]?.split("## Approvals")[0] ?? "";
  const rows = rpm.split("\n").filter((l) => l.startsWith("| `"));
  if (rows.length < 4) fail(`${SKILL}: Read per mode table not found`);
  for (const row of rows) if (!row.includes("memory.md")) fail(`${SKILL}: Read per mode row must include memory.md: ${row}`);
  // The memory-save retry pointer sits next to the no-blind-retry bullet.
  const retryLine = skill.split("\n").findIndex((l) => l.includes("No blind retry"));
  if (retryLine < 0 || !skill.split("\n").slice(retryLine, retryLine + 2).join("\n").includes("memory.md` §4")) fail(`${SKILL}: a memory.md §4 pointer must follow the no-blind-retry bullet`);

  const WF = "skills/bridge/references/workflow.md";
  const wf = read(WF);
  for (const needle of ["memory.md", "memory_search", "memory-read", "Memory hints", "memory_save", "complete or blocked", "inspect and survey save nothing"]) {
    if (!wf.includes(needle)) fail(`${WF}: must mention "${needle}"`);
  }
  const wfSection = (n) => wf.split(`\n## ${n}.`)[1]?.split("\n## ")[0] ?? "";
  if (!wfSection(2).includes("memory_search")) fail(`${WF}: §2 preflight must run memory_search`);
  if (!wfSection(3).includes("Memory hints")) fail(`${WF}: §3 Recon must receive Memory hints`);
  if (!wfSection(11).includes("inspect and survey save nothing")) fail(`${WF}: §11 must state that inspect and survey save nothing`);
  const s13 = wfSection(13);
  for (const needle of ["memory_save", "complete or blocked"]) if (!s13.includes(needle)) fail(`${WF}: §13 must mention "${needle}"`);
  for (const route of ["repair", "optimize", "shield"]) {
    const line = wfSection(11).split("\n").find((l) => l.startsWith(`- **${route}**`)) ?? "";
    if (!line.includes("§13")) fail(`${WF}: §11 ${route} line must point to §13`);
  }
  if (!wfSection(2).includes("before any Recon (`SKILL.md` → Inputs)") || wfSection(2).includes("right after Armorer")) fail(`${WF}: §2 step 10 must place the read once the spec or goal is known and before any Recon`);
  if (!wfSection(12).includes("memory.md` §4")) fail(`${WF}: §12 must point to the memory.md §4 single-retry exception`);

  const DISC = "skills/bridge/references/discovery.md";
  const disc = read(DISC);
  for (const needle of ["memory_search", "Memory hints", "memory.md"]) {
    if (!disc.includes(needle)) fail(`${DISC}: must mention "${needle}"`);
  }

  const PUB = "skills/bridge/references/publish.md";
  const pub = read(PUB);
  for (const needle of ["memory.md", "memory_save", "memory-read", "- Memories:"]) {
    if (!pub.includes(needle)) fail(`${PUB}: must mention "${needle}"`);
  }
  const pub4 = pub.split("\n## 4.")[1]?.split("\n## 5.")[0] ?? "";
  const savePara = pub4.split("\n").find((l) => l.startsWith("**Save memories.**")) ?? "";
  if (!savePara) fail(`${PUB}: the "Save memories" step must sit inside §4`);
  else if (!savePara.includes("no user confirmation")) fail(`${PUB}: the "Save memories" step must say no user confirmation`);
  const pub8 = pub.split("\n## 8.")[1]?.split("\n## ")[0] ?? "";
  if (!pub8.includes("memory.md` §2–4")) fail(`${PUB}: §8 must point to the memory save (memory.md §2–4)`);

  // ALY-20 [AC-06]: publish is gated on specs.spec_validate for every confirmed spec.
  for (const needle of ["specs.spec_validate", "valid: false"]) if (!pub4.includes(needle)) fail(`${PUB}: §4 gate must mention "${needle}"`);
  const pub3 = pub.split("\n## 3.")[1]?.split("\n## 4.")[0] ?? "";
  if (!pub3.includes("submit_ready")) fail(`${PUB}: §3 closing confirmation must show submit_ready per spec`);
  if (!pub.includes("fallback")) fail(`${PUB}: must describe the spec_validate fallback`);
  if (!pub.split("\n").some((l) => l.startsWith("- Validation:"))) fail(`${PUB}: Output must include a "- Validation:" line`);
}

// ALY-22 [AC-06] [AC-07]: memory access is the Mothership's only; memory events are journaled.
{
  const DEL = "skills/bridge/references/delegation.md";
  const del = read(DEL);
  for (const needle of ["crew roles have no memory access", "memoryHints"]) {
    if (!del.includes(needle)) fail(`${DEL}: must mention "${needle}"`);
  }
  const access = del.split("\n## Allye MCP access")[1]?.split("\n## ")[0] ?? "";
  if (!access) fail(`${DEL}: Allye MCP access section not found`);
  const lines = access.split("\n");
  const readsLine = lines.find((l) => l.startsWith("**Reads")) ?? "";
  if (!readsLine) fail(`${DEL}: Reads line not found`);
  if (readsLine.includes("memory_")) fail(`${DEL}: the Reads line must not grant memory_ calls`);
  if (!readsLine.includes("spec_validate")) fail(`${DEL}: the Reads line must grant spec_validate (ALY-20 [AC-06])`);
  const rows = lines.filter((l) => l.startsWith("| ") && !l.startsWith("| Agent") && !l.startsWith("|---"));
  const firstCell = (l) => l.split("|")[1].trim();
  for (const row of rows) {
    if (firstCell(row) !== "Mothership" && row.includes("memory_")) fail(`${DEL}: only the Mothership row may mention memory_: ${row}`);
  }
  const both = (l) => l.includes("intelligence.memory_search") && l.includes("intelligence.memory_save");
  const motherRow = rows.find((r) => firstCell(r) === "Mothership") ?? "";
  const reserved = lines.find((l) => l.startsWith("Reserved to the Mothership")) ?? "";
  if (!both(motherRow) && !both(reserved)) fail(`${DEL}: the Mothership row or the Reserved paragraph must grant intelligence.memory_search and intelligence.memory_save`);
  if (!/no crew agent gets[^.\n]*`intelligence`/i.test(del)) fail(`${DEL}: tool ceilings must state that no crew agent gets \`intelligence\``);

  const SC = "skills/bridge/references/state-contract.md";
  const sc = read(SC);
  const types = sc.split("\n").find((l) => l.startsWith("Event types")) ?? "";
  for (const t of ["`memory-read`", "`memory-save`"]) if (!types.includes(t)) fail(`${SC}: event types line must include ${t}`);
  for (const needle of ["ids kept", "id, action, scope", "memory.md` §6"]) {
    if (!sc.includes(needle)) fail(`${SC}: must mention "${needle}"`);
  }
  const rule9 = sc.split("\n").find((l) => l.startsWith("9. ")) ?? "";
  if (!rule9.includes("memory_save") || !rule9.includes("`memory-save`")) fail(`${SC}: logging rule 9 must log memory_save calls as \`memory-save\``);

  const MEM = "skills/bridge/references/memory.md";
  if (!read(MEM).includes("the read and any save")) fail(`${MEM}: §6 fallback must report "the read and any save" in the final output`);
}

// ALY-22 [AC-02] [AC-08]: the Armorer reports memory as optional; the bootstrap names the memory loop.
{
  const ARM = "skills/bridge-armorer/SKILL.md";
  const arm = read(ARM);
  const checks = arm.split("\n## Checks")[1]?.split("\n## ")[0] ?? "";
  const memCheck = checks.split("\n").find((l) => /^\d+\. \*\*Memory/.test(l)) ?? "";
  if (!memCheck) fail(`${ARM}: Checks must include a numbered "Memory" check`);
  for (const needle of ["intelligence", "optional", "memory.md", "never blocks"]) {
    if (memCheck && !memCheck.includes(needle)) fail(`${ARM}: the Memory check must mention "${needle}"`);
  }
  if (!arm.includes("Never treat optional as required.")) fail(`${ARM}: must keep "Never treat optional as required."`);

  const BOOT = "bootstrap/allye.md";
  const boot = read(BOOT);
  const memLines = boot.split("\n").filter((l) => /memories.*start.*distilled lessons.*end/.test(l));
  if (memLines.length !== 1) fail(`${BOOT}: exactly one line must state that Bridge reads memories at the start and saves distilled lessons at the end (found ${memLines.length})`);
  const CODEX = "manifests/codex/AGENTS.md";
  if (read(CODEX) !== boot) fail(`${CODEX}: must equal ${BOOT} (run scripts/sync-bootstrap.sh)`);
}

if (errors.length) {
  for (const e of errors) console.error(`FAIL: ${e}`);
  process.exit(1);
}
console.log("skills text: ok (anchors defined once; spec lint referenced by architect, dispatcher and publish; memory reference complete; memory wired into the Mothership flow; memory access Mothership-only and memory events journaled; Armorer memory check optional; bootstrap memory line synced; spec_validate gate in publish, spec lint, delegation, architect and dispatcher)");
