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
  for (const needle of ["SPEC_DUPLICATE_ANCHOR", "defined exactly once", "[NEEDS CLARIFICATION]", "2000", "identical text"]) {
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

// ALY-17 [AC-07] [AC-08] [AC-10] [AC-14] [AC-15]: publish resolves the repo's project with
// project_resolve and a verified link claim; .allye/project.json is committed product state.
{
  const PUB = "skills/bridge/references/publish.md";
  const pub = read(PUB);
  const section = (text, n) => text.split(`\n## ${n}. `)[1]?.split("\n## ")[0] ?? "";
  const s1 = section(pub, 1);
  const s1Lines = s1.split("\n");
  const firstStep = s1Lines.find((l) => /^1\. /.test(l)) ?? "";
  if (!/^1\. Call `projects\.project_resolve[` ]/.test(firstStep)) fail(`${PUB}: §1 step 1 must call \`projects.project_resolve\` first`);
  if (/project_list[\s\S]{0,300}app_list|app_list` per candidate project|matching `repository_url`/.test(pub)) fail(`${PUB}: must not match the remote with a project_list + app_list loop`);
  const line = (re) => s1Lines.find((l) => re.every((r) => r.test(l))) ?? "";
  if (!line([/`\.allye\/project\.json`/, /claim/, /agrees?/, /wins over `ambiguous`/])) fail(`${PUB}: §1 must use an agreeing .allye/project.json claim, which wins over \`ambiguous\``);
  if (!line([/`ambiguous`/, /`not_found`/, /ask the user once/, /project, app and team/, /never create a project or app without an explicit request/])) fail(`${PUB}: §1 must ask the user once on \`ambiguous\`/\`not_found\` with project, app and team, never creating a project or app unasked`);
  const disagree = line([/disagree/, /no app for this remote/, /claimed and the resolved project, app and team/, /ask the user once/]);
  if (!disagree) fail(`${PUB}: §1 must ask once on a disagreeing claim (or no app for this remote), showing the claimed and the resolved project, app and team`);
  if (disagree && !/never use the claim/.test(disagree)) fail(`${PUB}: §1 must not use a disagreeing claim before the user answers`);
  if (!line([/no remote/, /unverifiable/, /ask the user once to confirm/, /never use the claim/])) fail(`${PUB}: §1 must treat a link file with no remote as unverifiable and ask once to confirm it`);
  if (!line([/propose `\.allye\/project\.json`/, /reviewed diff/, /written and committed only on the user's explicit OK/])) fail(`${PUB}: §1 must propose .allye/project.json in the reviewed diff, written and committed only on explicit OK`);
  // Correction round 1 (Medic, Shield SHD-01/03/04/05).
  if (!/strip userinfo, query and fragment/.test(firstStep) || !/never echo the raw remote/.test(firstStep)) fail(`${PUB}: §1 step 1 must strip userinfo, query and fragment from the remote and never echo the raw remote`);
  for (const needle of ["`^[A-Z][A-Z0-9]{1,9}$`", "`^[A-Za-z0-9._-]{1,120}$`"]) if (!s1.includes(needle)) fail(`${PUB}: §1 must state the link-file pattern ${needle}`);
  if (!line([/unknown keys/i, /one warning that names no values/])) fail(`${PUB}: §1 must ignore unknown link-file keys with one value-free warning`);
  if (!line([/claim values are data/i])) fail(`${PUB}: §1 must treat claim values as data`);
  if (!line([/agrees only when the claimed project equals `match\.project` or one candidate's project/, /claimed `app`, if given, equals that entry's app/, /only the server's normalization counts/])) fail(`${PUB}: §1 must define agreement against the project_resolve output only (match.project or a candidate, and its app)`);
  if (!line([/`match\.app` is null/, /claimed app cannot be confirmed/, /ask the user once/, /which app/])) fail(`${PUB}: §1 must handle \`resolved\` with \`match.app\` null`);
  if (!line([/`INVALID_REPOSITORY_URL`/, /fail/, /counts as no remote/])) fail(`${PUB}: §1 must treat a rejected remote or failed resolve as no remote`);
  if (!line([/request access or fix the link/])) fail(`${PUB}: §1 must ask the user to request access or fix the link when the claimed project is unreadable`);
  const writer = line([/The Mothership writes `\.allye\/project\.json`/, /explicit OK/]);
  if (!writer || !/separate commit on the mission branch/.test(writer) || !/never on the current or default branch by default/.test(writer)) fail(`${PUB}: §1 must name the Mothership as the link-file writer, a separate commit on the mission branch, never on the current or default branch by default`);
  if (!line([/Multi-app/, /no local clone/, /pick by name from the resolved project's apps/])) fail(`${PUB}: §1 must say how sibling apps with no local clone are resolved`);
  const s3 = section(pub, 3);
  if (!s3.split("\n").some((l) => /^- target project: .*`?key`?.*its team/i.test(l))) fail(`${PUB}: §3 closing confirmation must list the target project (key) and its team`);

  const SC = "skills/bridge/references/state-contract.md";
  const sc = read(SC);
  const layout = sc.split("\n## Layout")[1]?.split("\n## ")[0] ?? "";
  const tree = layout.split("```")[1] ?? "";
  if (!/^\.allye\/project\.json\s+← .*committed/m.test(tree)) fail(`${SC}: the Layout tree must list .allye/project.json as committed`);
  const bullets = layout.split("\n").filter((l) => l.startsWith("- "));
  if (!bullets.some((l) => l.includes("`.allye/project.json`") && /product state/.test(l) && /committed and reviewed/.test(l))) fail(`${SC}: must define .allye/project.json as product state, committed and reviewed`);
  const excl = bullets.find((l) => /^- Local working state is only /.test(l)) ?? "";
  if (!excl.includes("`.allye/armorer.json`") || !excl.includes("`.allye/missions/`") || !/only/.test(excl)) fail(`${SC}: local-state exclusions must cover only .allye/armorer.json and .allye/missions/`);
  if (/`\.allye\/` \(|check-ignore -q \.allye\/`|append `\.allye\/`/.test(sc))
    fail(`${SC}: must not exclude the whole .allye/ directory`);
  if (/check-ignore -q \.allye\/armorer\.json \.allye/.test(sc) || !sc.includes("`git check-ignore -q .allye/armorer.json`") || !sc.includes("`git check-ignore -q .allye/missions/`")) fail(`${SC}: must check each local-state path with its own \`git check-ignore -q\` (-q takes one path)`);
  const ign = bullets.find((l) => l.includes("git check-ignore -v")) ?? "";
  // Correction round 2 (Medic): git cannot re-include a file under an excluded directory, so the
  // negation example must turn a `.allye/` directory rule into `.allye/*` and re-check.
  {
    const fix = bullets.find((l) => l.includes("git check-ignore -v")) ?? "";
    if (!/`\.allye\/\*`/.test(fix) || !fix.includes("`!.allye/project.json`") || !fix.includes("`git check-ignore -q .allye/project.json`")) fail(`${SC}: the ignore fix must change a \`.allye/\` directory rule to \`.allye/*\`, add \`!.allye/project.json\` and re-check with \`git check-ignore -q .allye/project.json\``);
    if (/negation next to that rule/.test(fix)) fail(`${SC}: must not pair \`!.allye/project.json\` with a bare \`.allye/\` rule (git cannot re-include a file under an excluded directory)`);
  }
  if (!ign || !/narrowest/.test(ign) || !/tracked `\.gitignore`.*without the user's OK/.test(ign)) fail(`${SC}: when .allye/project.json is ignored, report the rule (git check-ignore -v), propose the narrowest fix, never edit a tracked .gitignore without OK`);
  if (!bullets.some((l) => /earlier Bridge `\.allye\/` entry/.test(l) && /\.git\/info\/exclude/.test(l) && /replace/.test(l) && l.includes("`.allye/armorer.json`") && l.includes("`.allye/missions/`"))) fail(`${SC}: must replace an earlier Bridge .allye/ entry in .git/info/exclude with the two specific paths`);
}

if (errors.length) {
  for (const e of errors) console.error(`FAIL: ${e}`);
  process.exit(1);
}
console.log("skills text: ok (anchors defined once; spec lint referenced by architect, dispatcher and publish; memory reference complete; memory wired into the Mothership flow; memory access Mothership-only and memory events journaled; Armorer memory check optional; bootstrap memory line synced; publish resolves via project_resolve and a verified link file; .allye/project.json committed)");
