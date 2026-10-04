// Guards the spec-authoring text of the Bridge skills: anchors are defined once per spec,
// and the shared anchor lint is the single checklist used by authors and publish. Offline.
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

if (errors.length) {
  for (const e of errors) console.error(`FAIL: ${e}`);
  process.exit(1);
}
console.log("skills text: ok (anchors defined once; spec lint referenced by architect, dispatcher and publish)");
