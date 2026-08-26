#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node --experimental-strip-types --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { mayMaterializeDistribution, normalizeApiDistributionResult } from "./packages/allye-pi/src/runtime-adapters.ts";

const bytes = new TextEncoder().encode("# skill\n");
const hash = createHash("sha256").update("SKILL.md").update("\0").update(bytes).update("\0").digest("hex");
const artifact = {
  release_id: "release-1", canonical_hash: hash, integrity: { valid: true },
  files: [{ path: "SKILL.md", bytes, kind: "file" }],
  distribution_decision: { release_id: "release-1", canonical_hash: hash, runtime: "claude", contract_version: "1.0.0", state: "compatible", allowed: true, adapter: "claude-workspace", adapter_version: "1.0.0" },
};
const succeeded = { operationId: "operation-1", status: "succeeded", runtime: "claude", releaseId: "release-1", evidence: { runtime: "claude", observedHash: hash, runtimeVersion: "1.0.0", verifiedAt: "2026-08-18T12:01:00.000Z" } };
assert.equal(mayMaterializeDistribution(succeeded, artifact), true, "matching runtime evidence is required for success");
for (const status of ["pending", "failed", "conflict", "blocked"]) {
  assert.equal(mayMaterializeDistribution({ ...succeeded, status, operationId: status === "blocked" ? null : "operation-1" }, artifact), false, `${status} must not become installation`);
}
const integrityBlocked = normalizeApiDistributionResult({ ...succeeded, status: "blocked", operationId: null, failureCode: "RISK_FINDING_BLOCKED", release_id: "release-1", canonical_hash: hash, eligible: false, integrity_status: "risk_blocked", reason_codes: ["RISK_FINDING_BLOCKED"], findings: [{ code: "STATIC_SCRIPT", severity: "high", evidence: { path: "scripts/setup.sh", detector: "static" }, blocking: true }] });
assert.deepEqual(integrityBlocked.eligibility, { release_id: "release-1", canonical_hash: hash, eligible: false, integrity_status: "risk_blocked", reason_codes: ["RISK_FINDING_BLOCKED"], findings: [{ code: "STATIC_SCRIPT", severity: "high", evidence: { path: "scripts/setup.sh", detector: "static" }, blocking: true }] }, "Plugin preserves the complete API eligibility envelope");
assert.equal(mayMaterializeDistribution(integrityBlocked, artifact), false, "API integrity reason cannot be overridden by Plugin policy");
const sandbox = mkdtempSync(join(tmpdir(), "allye-distribution-"));
try {
  const foreign = join(sandbox, "unmanaged.txt");
  writeFileSync(foreign, "preserve me");
  const blockedRemove = { operationId: null, status: "blocked", runtime: "claude", releaseId: "release-1", diagnostic: "DISTRIBUTION_REMOVE_OWNERSHIP_UNAVAILABLE" };
  let writes = 0;
  const maybeWrite = (result) => { if (mayMaterializeDistribution(result, artifact)) writes += 1; };
  maybeWrite(blockedRemove);
  maybeWrite(blockedRemove);
  assert.equal(writes, 0, "blocked remove must have zero mutations, including retries");
  assert.equal(readFileSync(foreign, "utf8"), "preserve me", "unmanaged/foreign content must remain untouched");
} finally { rmSync(sandbox, { recursive: true, force: true }); }
console.log("distribution lifecycle: ok");
NODE
