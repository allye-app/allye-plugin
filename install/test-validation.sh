#!/bin/bash
# Checks the installer's canonical hash and artifact checks against the shared
# canonical-skill fixture (test/fixtures/canonical-skills.json).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node --input-type=module - "$ROOT" <<'NODE'
import { readFileSync } from "node:fs";
const root = process.argv[2];
const { canonicalHash, checkArtifact } = await import(`${root}/install/skill-tool.mjs`);
const { createHash } = await import("node:crypto");
const cases = JSON.parse(readFileSync(`${root}/test/fixtures/canonical-skills.json`, "utf8")).cases;
const bytesOf = (file) => Array.isArray(file.bytes) ? Buffer.from(file.bytes) : Buffer.from(file.bytes, "utf8");
let checked = 0;
for (const c of cases) {
  const files = c.files.map((f) => ({ path: f.path, bytes: bytesOf(f) }));
  if (c.snapshot) {
    if (canonicalHash(files) !== c.snapshot.origin_hash) throw new Error(`canonical hash mismatch: ${c.id}`);
    checked++;
  }
  const hash = canonicalHash(files);
  const artifact = { skill_id: "s", release_id: "r", version: "1.0.0", canonical_hash: hash, integrity: { valid: true },
    manifest: { sha256: hash, files: files.map((f) => ({ path: f.path, bytes: f.bytes.length, sha256: createHash("sha256").update(f.bytes).digest("hex") })) },
    files: files.map((f) => ({ path: f.path, kind: "file", bytes_base64: f.bytes.toString("base64") })) };
  let accepted = true;
  try { checkArtifact(artifact, { skill_id: "s", release_id: "r", canonical_hash: hash }); } catch { accepted = false; }
  if (accepted !== c.valid) throw new Error(`artifact acceptance mismatch for ${c.id}: accepted=${accepted}, fixture valid=${c.valid}`);
}
console.log(`canonical skill fixture: ok (${cases.length} cases, ${checked} hash vectors)`);
NODE
