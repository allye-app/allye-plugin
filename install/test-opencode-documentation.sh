#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
node - "$ROOT" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const root = process.argv[2];
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');
const fail = (message) => { throw new Error(message); };

const opencodeGuide = read('docs', 'install-opencode.md');
if (!opencodeGuide.includes('- Workflow guidance is included with the installed Allye plugin')) {
  fail('OpenCode confirmation must describe bundled workflow guidance');
}
if (/Allye marketplace/i.test(opencodeGuide) || /workflow skills available/i.test(opencodeGuide)) {
  fail('OpenCode confirmation must not announce an active Allye Skills marketplace');
}

const allowedNativeHostReferences = [
  ['README.md', read('README.md'), /\/plugin marketplace add allye-app\/allye-plugin/, /The host command name below is not an Allye Skills catalogue/],
  ['CLAUDE.md', read('CLAUDE.md'), /Claude Code plugin marketplace/, /Two parallel distribution mechanisms/],
];
for (const [name, content, nativeReference, boundary] of allowedNativeHostReferences) {
  if (!nativeReference.test(content) || !boundary.test(content)) {
    fail(`${name} native host marketplace reference is missing its non-Allye-Skills boundary`);
  }
}

const historicalSpecPath = path.join('docs', 'allye', 'specs', '2026-07-12-guided-delivery-workflow-design.md');
const historicalSpec = read(...historicalSpecPath.split(path.sep));
if (!historicalSpec.includes('.claude-plugin/{plugin.json, marketplace.json}')) {
  fail('Historical specification marketplace reference unexpectedly changed');
}

console.log('OpenCode marketplace documentation boundary: ok (active=0, allowed-native-host=2, allowed-historical=1)');
NODE
