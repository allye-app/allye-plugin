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
  // ALY-20: the Server check names the same fallback condition as publish §4; the Outcome covers the server result.
  const server = lint.split("\n## Server check")[1]?.split("\n## ")[0] ?? "";
  if (!server.includes("unknown or unsupported action")) fail(`${LINT}: Server check must limit the fallback to an "unknown or unsupported action" rejection`);
  const outcome = lint.split("\n## Outcome")[1]?.split("\n## ")[0] ?? "";
  for (const needle of ["valid: false", "failed read"]) if (!outcome.includes(needle)) fail(`${LINT}: Outcome must mention "${needle}"`);
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
  const text = read(file);
  if (!text.includes("specs.spec_validate")) fail(`${file}: must call specs.spec_validate in the anchor lint self-check`);
  for (const needle of ["unknown or unsupported action", "input validation"]) {
    if (!text.includes(needle)) fail(`${file}: the spec_validate fallback must use the publish §4 condition ("${needle}")`);
  }
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
  for (const needle of ["**Fallback:**", "unknown or unsupported action", "input validation"]) {
    if (!pub4.includes(needle)) fail(`${PUB}: §4 gate must define the spec_validate fallback ("${needle}")`);
  }
  // AC-04: an epic created in this same publish is not passed to spec_validate.
  for (const needle of ["epic created in this publish", "without `epic`"]) if (!pub4.includes(needle)) fail(`${PUB}: §4 must state the epic-omission rule ("${needle}")`);
  // submit_ready: false never blocks but keeps the spec draft, and spec_submit skips it.
  for (const needle of ["`submit_ready: false` do not block", "stays `draft`"]) if (!pub4.includes(needle)) fail(`${PUB}: §4 must say "${needle}"`);
  const submitLine = pub4.split("\n").find((l) => l.includes("specs.spec_submit")) ?? "";
  if (!submitLine.includes("not `submit_ready: false`")) fail(`${PUB}: §4 must restrict specs.spec_submit to specs whose report is not \`submit_ready: false\``);
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

// ALY-17 [AC-09] [BR-06] [BR-08]: a missing team never blocks a route (the Armorer reports
// defaultTeam for information only), and only .allye/armorer.json and .allye/missions/** are
// local state; .allye/project.json is committed product state.
{
  const ARM = "skills/bridge-armorer/SKILL.md";
  const SKILL = "skills/bridge/SKILL.md";
  const WF = "skills/bridge/references/workflow.md";
  const DEL = "skills/bridge/references/delegation.md";
  for (const file of [ARM, SKILL, WF]) {
    const text = read(file);
    for (const re of [/no active team/i, /active team is set/i, /team_switch/, /(missing|no) (default |active )?team[^.\n]*(→|blocked)/i, /ask[s]? (for|which) (a |the )?(default )?team[^.\n]*before/i])
      if (re.test(text)) fail(`${file}: must not block on, or ask for, a missing team before routes (${re})`);
  }
  const arm = read(ARM);
  if (!/allye: \{ connected: true\|false, defaultTeam: <name\|null> \}/.test(arm)) fail(`${ARM}: output must report \`allye: { connected, defaultTeam: <name|null> }\``);
  const allyeCheck = (arm.split("\n## Checks")[1] ?? "").split("\n").find((l) => /^1\. \*\*Allye/.test(l)) ?? "";
  if (!/`defaultTeam`/.test(allyeCheck) || !/information only/.test(allyeCheck) || !/never blocks/.test(allyeCheck)) fail(`${ARM}: the Allye check must report \`defaultTeam\` for information only and say a missing team never blocks`);
  if (!/blocks? only when Allye is not connected or authenticated/.test(allyeCheck)) fail(`${ARM}: the Allye check must block only when Allye is not connected or authenticated`);
  if (/which (default |active )?team/.test(arm)) fail(`${ARM}: must not list "which team" as an open question`);
  for (const file of [SKILL, WF]) {
    const text = read(file);
    const teamLine = text.split("\n").find((l) => /team_set_default/.test(l)) ?? "";
    if (!/a missing team never gates a route/.test(teamLine)) fail(`${file}: must state that a missing team never gates a route`);
    if (!/create a project with no default team set[^\n]*ask the user which team[^\n]*pass `team_id` on the project creation/.test(teamLine)) fail(`${file}: when creating a project with no default team, must ask which team and prefer passing \`team_id\` on the project creation`);
    if (!/`team\.team_set_default` only when the user asks to set a new default/.test(teamLine)) fail(`${file}: must call \`team.team_set_default\` only when the user asks to set a new default`);
  }
  const del = read(DEL);
  const reserved = del.split("\n").find((l) => l.startsWith("Reserved to the Mothership:")) ?? "";
  if (!reserved.includes("`team.team_set_default`")) fail(`${DEL}: the Reserved paragraph must contain \`team.team_set_default\``);
  if (!/`team\.team_set_default` \([^)]*only when the user asks[^)]*only with the user's answer[^)]*`team_id`/.test(reserved)) fail(`${DEL}: the reserved \`team.team_set_default\` must say "only when the user asks", "only with the user's answer", and prefer \`team_id\``);
  if (/team_switch/.test(del)) fail(`${DEL}: must not reserve or mention \`team.team_switch\``);
  const reads = del.split("\n").find((l) => l.startsWith("**Reads (every role except Armorer):**")) ?? "";
  if (!reads.includes("`projects.project_resolve`")) fail(`${DEL}: the common Reads line must grant \`projects.project_resolve\``);

  // BR-08: no crew text treats the whole .allye/ (bare `.allye/` or `.allye/**`) as local state.
  const crew = ["armorer", "copilot", "watcher", "strategist", "pilot", "recon", "medic", "shield", "optimizer", "architect", "dispatcher"].map((r) => `skills/bridge-${r}/SKILL.md`);
  for (const file of [...crew, DEL, SKILL, WF]) {
    read(file).split("\n").forEach((l, i) => {
      if (/\.allye\/(\*\*)?(?![\w.*<])/.test(l)) fail(`${file}:${i + 1}: must name \`.allye/armorer.json\` / \`.allye/missions/**\`, not the whole \`.allye/\``);
    });
  }
  if (!/`\.allye\/armorer\.json`[^\n]*`\.allye\/missions\/`[^\n]*\.git\/info\/exclude/.test(arm)) fail(`${ARM}: the Mothership must exclude \`.allye/armorer.json\` and \`.allye/missions/\` in .git/info/exclude`);
  const scopeLine = (file, re) => read(file).split("\n").find((l) => re.test(l)) ?? "";
  for (const [file, re] of [["skills/bridge-copilot/SKILL.md", /\*\*Scope\.\*\*/], ["skills/bridge-watcher/SKILL.md", /\*\*Scope\.\*\*/]]) {
    const l = scopeLine(file, re);
    if (!l.includes("`.allye/armorer.json`") || !l.includes("`.allye/missions/**`") || !l.includes("`.allye/project.json`") || !/user-confirmed link-file change/.test(l)) fail(`${file}: Scope must exclude only \`.allye/armorer.json\` and \`.allye/missions/**\` and keep \`.allye/project.json\` in scope (expected only as the user-confirmed link-file change)`);
    if (file.includes("copilot") && !/`\.allye\/project\.json` stays in scope/.test(l)) fail(`${file}: Scope must say \`.allye/project.json\` stays in scope`);
    if (file.includes("watcher") && !/`\.allye\/project\.json` is product state/.test(l) && !/expected only when it is the user-confirmed link-file change/.test(l)) fail(`${file}: Scope must call \`.allye/project.json\` product state, expected only as the user-confirmed link-file change`);
  }
  for (const [file, re] of [[DEL, /forbiddenPaths:/], ["skills/bridge-strategist/SKILL.md", /\*\*Paths\.\*\*/], ["skills/bridge-pilot/SKILL.md", /^Do not edit outside your paths/]]) {
    const l = scopeLine(file, re);
    for (const p of ["`.allye/armorer.json`", "`.allye/missions/**`", "`.allye/project.json`"]) {
      const bare = p.replaceAll("`", "");
      if (!l.includes(p) && !l.includes(bare)) fail(`${file}: ${file === DEL ? "the packet's forbiddenPaths" : file.includes("strategist") ? "the Strategist's per-slice forbidden paths" : "the Pilot's Limits"} must list ${bare}`);
    }
  }
}

if (errors.length) {
  for (const e of errors) console.error(`FAIL: ${e}`);
  process.exit(1);
}
console.log("skills text: ok (anchors defined once; spec lint referenced by architect, dispatcher and publish; memory reference complete; memory wired into the Mothership flow; memory access Mothership-only and memory events journaled; Armorer memory check optional; bootstrap memory line synced; spec_validate gate in publish, spec lint, delegation, architect and dispatcher; fallback condition aligned; epic omission, submit_ready draft rule and spec-lint outcome covered; publish resolves via project_resolve and a verified link file; .allye/project.json committed; a missing team never blocks; only armorer.json and missions/ are local state)");
