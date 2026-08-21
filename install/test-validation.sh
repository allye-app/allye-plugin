#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node - "$ROOT/test/fixtures/canonical-skills.json" <<'NODE'
const crypto = require('node:crypto');
const fs = require('node:fs');
const source = fs.readFileSync(process.argv[2]);
if (crypto.createHash('sha256').update(source).digest('hex') !== '6d3119a4e825c061bd496cc5324c137051e7db1648b937533c210d6fe4b6501e') throw new Error('fixture mismatch');
const cases = JSON.parse(source).cases;
const expected = {
  'valid-with-resources': { valid: true, issues: [] },
  'script-static-warning': { valid: true, issues: [['warning','CANONICAL_SKILL_SCRIPT_STATIC_ANALYSIS','scripts/setup.sh']] },
  'unsafe-entries': { valid: false, issues: [
    ['error','CANONICAL_SKILL_MISSING_ROOT','SKILL.md'], ['error','CANONICAL_SKILL_PATH_TRAVERSAL','../escape.md'],
    ['error','CANONICAL_SKILL_SYMLINK_FORBIDDEN','shortcut'], ['error','CANONICAL_SKILL_BINARY_FORBIDDEN','assets/blob.bin'] ] },
};
for (const testCase of cases) {
  const contract = expected[testCase.id]; if (!contract || testCase.valid !== contract.valid) throw new Error(`semantic valid mismatch: ${testCase.id}`);
  const actual = testCase.issues.map(({severity,code,path}) => [severity,code,path]);
  if (JSON.stringify(actual) !== JSON.stringify(contract.issues)) throw new Error(`semantic issues mismatch: ${testCase.id}`);
  for (const file of testCase.files) if (file.path.startsWith('scripts/') && !String(file.bytes).includes('NEVER_EXECUTE')) throw new Error('script sentinel missing');
}
console.log('Canonical skill fixture semantic conformance passed');
NODE
