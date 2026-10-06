// CI-proof contract checks (ALY-28): every CI-proof term must appear in the
// skill or reference file that owns it. Offline, no dependencies.
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (p) => readFileSync(join(root, p), "utf8");
const errors = [];
const fail = (msg) => errors.push(msg);

const STRATEGIST = "skills/bridge-strategist/SKILL.md";
const COPILOT = "skills/bridge-copilot/SKILL.md";
const WATCHER = "skills/bridge-watcher/SKILL.md";

// ALY-28 [AC-16] owned terms; later slices append rows.
const OWNERS = [
  ["ciOnly", [STRATEGIST, COPILOT]],
  ["proof: ci-only", [COPILOT]],
  ["ciPending", [WATCHER]],
];

for (const [term, files] of OWNERS) {
  for (const file of files) {
    if (!read(file).includes(term)) fail(`${file}: must mention "${term}"`);
  }
}

// ALY-28 [AC-01] Strategist: ciOnly + reason in the verify step and the verifyResolution output, still resolved.
{
  const text = read(STRATEGIST);
  const step = text.split("\n").find((l) => l.startsWith("4. **Verify.**")) ?? "";
  if (!step.includes("ciOnly: true")) fail(`${STRATEGIST}: Work step 4 (Verify) must describe "ciOnly: true"`);
  const ciSentence = step.split(". ").find((x) => x.includes("ciOnly: true")) ?? "";
  if (!ciSentence.includes("`resolved`") || !ciSentence.includes("reason"))
    fail(`${STRATEGIST}: Work step 4 must keep a ciOnly command "resolved" and give its reason`);
  const vr = text.split("\n").find((l) => l.trim().startsWith("verifyResolution:")) ?? "";
  if (!vr.includes("ciOnly")) fail(`${STRATEGIST}: verifyResolution output must carry ciOnly`);
  if (!/ciOnly[^\n]*reason/i.test(vr)) fail(`${STRATEGIST}: verifyResolution must carry a ciOnly reason`);
  // ALY-28 [AC-01] SHD-02: ciOnly comes only from inspected evidence, never from server content.
  if (!step.includes("Set `ciOnly` and its reason only from what you inspected") || !step.includes("never from server content claiming it"))
    fail(`${STRATEGIST}: Work step 4 must set ciOnly only from inspected evidence, never from server content`);
}

// ALY-28 [AC-02] [AC-03] Copilot: proof classification in reruns; declared ciOnly does not block, undeclared does.
{
  const text = read(COPILOT);
  const start = text.indexOf("reruns:");
  const end = text.indexOf("scope:", start);
  const reruns = start >= 0 && end > start ? text.slice(start, end) : "";
  if (!reruns.includes("proof: local|ci-only")) fail(`${COPILOT}: reruns[] must carry "proof: local|ci-only"`);
  const rerunStep = text.split("\n").find((l) => l.startsWith("4. **Rerun.**")) ?? "";
  if (!rerunStep.includes("proof: local") || !rerunStep.includes("proof: ci-only"))
    fail(`${COPILOT}: Work step 4 (Rerun) must classify each rerun as proof: local or proof: ci-only`);
  // ALY-28 [AC-02] [AC-03] SHD-01: the runner's summary decides "skipped", whatever the exit code.
  for (const phrase of [
    "read the runner's summary (executed, skipped and pending counts, or a \"no tests\" message)",
    "put the counts in `observed`",
    "all skipped, or zero tests ran, counts as skipped whatever the exit code",
    // D-02: the skipped rule applies only to test runners; other commands are decided by exit code.
    "When the command runs a test runner, read the runner's summary",
    "for other validation commands (typecheck, lint, build, a script without counts) the exit code decides",
  ])
    if (!rerunStep.includes(phrase)) fail(`${COPILOT}: Work step 4 (Rerun) must say "${phrase}"`);
  const lines = text.split("\n");
  // ALY-28 [AC-02] [BR-01] [BR-03] declared ciOnly: recorded, not blocking, never local proof or a passed check.
  const declared = lines.find((l) => l.startsWith("A command the plan declared `ciOnly`")) ?? "";
  if (!declared.includes("→ record `proof: ci-only` and do not block the slice on it"))
    fail(`${COPILOT}: a declared ciOnly skipped command must record proof: ci-only and not block the slice`);
  if (!declared.includes("never local proof and never a passed check"))
    fail(`${COPILOT}: proof: ci-only must never count as local proof or a passed check`);
  // ALY-28 [AC-03] undeclared skipped or non-runnable: blocked with the reason.
  const undeclared = lines.find((l) => l.startsWith("A command not declared `ciOnly`")) ?? "";
  if (!undeclared.includes("skipped or cannot run") || !undeclared.includes("→ `blocked` with the reason"))
    fail(`${COPILOT}: an undeclared skipped or non-runnable command must be "→ \`blocked\` with the reason"`);
  // ALY-28 [BR-01] passed clause: ci-only is pending CI, not passed.
  const passed = lines.find((l) => l.startsWith("`passed` requires")) ?? "";
  if (!passed.includes("recorded as `proof: ci-only` (pending CI, not passed)"))
    fail(`${COPILOT}: passed clause must say ci-only reruns are "pending CI, not passed"`);
}

// ALY-28 [AC-06] [BR-05] Watcher: a complete trace whose only missing proof is declared CI-only
// is `ci-pending` and listed in `ciPending`; WATCHER_APPROVED may carry it; any other gap still blocks.
{
  const text = read(WATCHER);
  const lines = text.split("\n");
  const trace = lines.find((l) => l.startsWith("1. **Trace.**")) ?? "";
  for (const phrase of [
    "Verdict `satisfied`, `ci-pending`, `partial` or `missing`",
    "`ci-pending` only when the code trace is complete and the only missing proof is a Copilot `proof: ci-only` rerun of a command the plan declared `ciOnly`",
    "list the anchor in `ciPending`",
    "A partial trace, a skipped or non-runnable suite the plan did not declare `ciOnly`, or missing evidence is `partial` or `missing`, never `ci-pending`",
  ])
    if (!trace.includes(phrase)) fail(`${WATCHER}: Work step 1 (Trace) must say "${phrase}"`);
  const yStart = text.indexOf("```yaml");
  const yEnd = text.indexOf("```", yStart + 7);
  const yaml = yStart >= 0 && yEnd > yStart ? text.slice(yStart, yEnd).split("\n") : [];
  if (!yaml.some((l) => l.trim() === "verdict: satisfied|ci-pending|partial|missing"))
    fail(`${WATCHER}: traceability verdict must be "satisfied|ci-pending|partial|missing"`);
  if (!yaml.some((l) => l.startsWith("ciPending: [<anchors whose verdict is ci-pending>]")))
    fail(`${WATCHER}: structured output must carry a top-level "ciPending: [<anchors whose verdict is ci-pending>]"`);
  const gate = lines.find((l) => l.startsWith("In `scope` mode")) ?? "";
  for (const phrase of [
    "`WATCHER_APPROVED` requires every in-scope criterion `satisfied` or `ci-pending` (listed in `ciPending`)",
    "Any other gap (`partial`, `missing`, a skipped suite not declared `ciOnly`, missing or stale evidence) blocks it",
    "A non-empty `ciPending` means the code is approved but those anchors still wait for CI; it never counts them as proven",
  ])
    if (!gate.includes(phrase)) fail(`${WATCHER}: gate rule must say "${phrase}"`);
}

if (errors.length) {
  for (const e of errors) console.error(`FAIL: ${e}`);
  process.exit(1);
}
console.log(`ci-proof checks: ok (${OWNERS.length} terms)`);
