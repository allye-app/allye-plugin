import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { adaptApiArtifact, normalizeApiArtifact } from "./runtime-adapters.ts";

const sourceFiles = [{ path: "SKILL.md", bytes: new TextEncoder().encode("# skill\n"), kind: "file" }, { path: "references/a.md", bytes: new TextEncoder().encode("a"), kind: "file" }];
const aggregate = createHash("sha256"); for (const file of [...sourceFiles].sort((a, b) => a.path < b.path ? -1 : 1)) aggregate.update(file.path).update("\0").update(file.bytes).update("\0");
const source = { skill_id: "skill-1", release_id: "revision-1", version: "1.2.3", origin: { url: "https://example.test/skills/core", commit: "abc123" }, canonical_hash: aggregate.digest("hex"), integrity: { valid: true }, files: sourceFiles };
const allowedDecision = { release_id: source.release_id, canonical_hash: source.canonical_hash, runtime: "claude" as "claude" | "codex" | "opencode" | "pi", contract_version: "1.0.0", state: "compatible", allowed: true, adapter: "claude-workspace", adapter_version: "1.0.0" };
const withDecision = <T extends object>(payload: T, decision = allowedDecision) => ({ skill_id: source.skill_id, version: source.version, origin: source.origin, ...payload, distribution_decision: decision });
const transportSource = () => ({ skill_id: source.skill_id, release_id: source.release_id, version: source.version, origin: source.origin, canonical_hash: source.canonical_hash, integrity: source.integrity, manifest: { sha256: source.canonical_hash, files: source.files.map((file) => ({ path: file.path, bytes: file.bytes.byteLength, sha256: createHash("sha256").update(file.bytes).digest("hex") })) }, files: source.files.map((file) => ({ path: file.path, kind: file.kind, bytes_base64: Buffer.from(file.bytes).toString("base64") })) });
type InstallAdapter = { id: string; mcp?: { path?: string; format?: string }; skills?: { source?: string; path?: string }; capabilities?: readonly string[]; package?: { local_source?: string } };
const installAdapters = JSON.parse(readFileSync(fileURLToPath(new URL("../../../install/adapters.json", import.meta.url)), "utf8")) as { agents: readonly InstallAdapter[] };
const hasAuthorityField = (value: unknown): boolean => value !== null && typeof value === "object" && Object.entries(value).some(([key, nested]) => /^(approval|eligible|eligibility|lifecycle|marketplace|planner|policy|publication|refinement|revocation|risk|selection)$/i.test(key) || hasAuthorityField(nested));
const apiArtifact = (runtime: "claude" | "codex" | "opencode" | "pi" = "claude") => ({ ...source, distribution_decision: { ...allowedDecision, runtime, adapter: `${runtime}-workspace` } });
for (const runtime of ["claude", "codex", "opencode", "pi"] as const) test(`${runtime} derives deterministic byte-preserving API output`, () => {
  const first = adaptApiArtifact(runtime, apiArtifact(runtime)); const second = adaptApiArtifact(runtime, apiArtifact(runtime));
  assert.equal("kind" in first, false); assert.deepEqual(first, second);
  if ("kind" in first) throw new Error(first.message);
  assert.equal(first.skill_id, source.skill_id); assert.equal(first.release_id, source.release_id); assert.equal(first.version, source.version); assert.deepEqual(first.origin, source.origin); assert.equal(first.canonical_hash, source.canonical_hash);
  assert.deepEqual(first.files.map((f) => [...f.bytes]), source.files.map((f) => [...f.bytes]));
});
test("declares every installer adapter's schema, runtime format, capabilities and distribution path without local authority", () => {
  const expected = [
    ["claude", "json", [], "disk", "~/.claude/skills/allye"],
    ["cursor", "json", [], "mcp", "~/.cursor/mcp.json"],
    ["opencode", "json", ["mcp", "json-config", "plugin"], "mcp", "~/.config/opencode/opencode.json"],
    ["codex", "toml", ["mcp", "toml-config", "agents-instructions"], "mcp", "~/.codex/config.toml"],
    ["gemini", "json", [], "mcp", "~/.gemini/settings.json"],
    ["hermes", "yaml-block", [], "disk", "~/.hermes/skills/allye"],
    ["pi", "package", ["package-manager", "resources-discover", "mcp-existing-config"], "package", "{{SCRIPT_DIR}}"],
  ];
  assert.deepEqual(installAdapters.agents.map((adapter) => [adapter.id, adapter.mcp?.format ?? "package", adapter.capabilities ?? [], adapter.skills?.source, adapter.skills?.source === "disk" ? adapter.skills.path : adapter.mcp?.path ?? adapter.package?.local_source]), expected);
  assert.equal(installAdapters.agents.every((adapter) => !hasAuthorityField(adapter)), true);
});
test("consumes the exact API HTTP snapshot", () => {
  const response = JSON.parse(readFileSync(fileURLToPath(new URL("./__fixtures__/canonical-artifact-api.json", import.meta.url)), "utf8"));
  const normalized = normalizeApiArtifact(withDecision(response)); if ("kind" in normalized) throw new Error(normalized.message);
  const claude = adaptApiArtifact("claude", normalized); const pi = adaptApiArtifact("pi", normalized);
  assert.equal("kind" in claude, false); assert.equal("kind" in pi, true);
  const invalid = normalizeApiArtifact(withDecision({ ...response, integrity: { valid: false } }));
  if ("kind" in invalid) throw new Error(invalid.message);
  assert.equal("kind" in adaptApiArtifact("claude", invalid), true);
});
test("carries the non-null API HTTP origin literally through the Plugin with skill_id", () => {
  const response = JSON.parse(readFileSync(fileURLToPath(new URL("../../../allye-api/src/test/fixtures/canonical-artifact-http.json", import.meta.url)), "utf8"));
  const normalized = normalizeApiArtifact(withDecision(response)); if ("kind" in normalized) throw new Error(normalized.message);
  const output = adaptApiArtifact("claude", normalized); if ("kind" in output) throw new Error(output.message);
  const origin = { repository: "allye/skills", commit: "abc123" };
  assert.equal(normalized.skill_id, "skill"); assert.deepEqual(normalized.origin, origin);
  assert.equal(output.skill_id, "skill"); assert.deepEqual(output.origin, origin);
});
test("snapshots the API bytes_base64 and CompatibilityMatrix transport end to end", () => {
  const fixture = JSON.parse(readFileSync(fileURLToPath(new URL("./__fixtures__/canonical-artifact-api.json", import.meta.url)), "utf8"));
  const normalized = normalizeApiArtifact(withDecision(fixture)); if ("kind" in normalized) throw new Error(normalized.message);
  const claude = adaptApiArtifact("claude", normalized); const pi = adaptApiArtifact("pi", normalized);
  assert.deepEqual(JSON.parse(JSON.stringify({ skill: normalized.skill_id, release: normalized.release_id, version: normalized.version, origin: normalized.origin, hash: normalized.canonical_hash, files: normalized.files.map((file) => [file.path, Buffer.from(file.bytes).toString("base64")]) })), { skill: fixture.skill_id, release: "revision-1", version: fixture.version, origin: fixture.origin, hash: fixture.canonical_hash, files: fixture.files.map((file: { path: string; bytes_base64: string }) => [file.path, file.bytes_base64]) });
  assert.equal("kind" in claude, false); assert.equal("kind" in pi, true);
  assert.equal("kind" in normalizeApiArtifact(withDecision({ ...fixture, origin: [] })), true);
});
test("fails closed when the API transport omits the API-owned skill identity", () => {
  const result = normalizeApiArtifact(withDecision({ ...transportSource(), skill_id: undefined }));
  assert.equal("kind" in result, true);
});
test("fails closed when the API transport omits, blanks, or whitespace-only values for its API-owned version", () => {
  for (const version of [undefined, "", "   "]) {
    const result = normalizeApiArtifact(withDecision({ ...transportSource(), version }));
    assert.equal("kind" in result, true);
  }
});
test("normalizes the API/MCP base64 transport DTO without Buffer JSON", () => {
  const normalized = normalizeApiArtifact(withDecision({ ...transportSource(), compatibility_matrix: { profiles: [{ runtime: "claude", state: "compatible", adapterStatus: "available" }, { runtime: "codex", state: "experimental", adapterStatus: "experimental" }, { runtime: "opencode", state: "incompatible", adapterStatus: "available" }, { runtime: "pi", state: "unsupported", adapterStatus: "unavailable" }] } }));
  if ("kind" in normalized) throw new Error(normalized.message);
  assert.deepEqual(normalized.files.map((file) => [...file.bytes]), source.files.map((file) => [...file.bytes]));
});
test("fails closed when the normal API transport omits an evaluator decision", () => {
  const result = normalizeApiArtifact({ ...transportSource(), compatibility_matrix: { profiles: [{ runtime: "claude", state: "compatible", adapterStatus: "available" }, { runtime: "codex", state: "experimental", adapterStatus: "experimental" }, { runtime: "opencode", state: "incompatible", adapterStatus: "available" }, { runtime: "pi", state: "unsupported", adapterStatus: "unavailable" }] } });
  assert.equal("kind" in result, true);
});
test("does not treat CompatibilityMatrix metadata as an output gate", () => {
  const result = normalizeApiArtifact(withDecision({ ...transportSource(), compatibility_matrix: { profiles: [] } }));
  assert.equal("kind" in result, false);
});
test("uses API decision for blocked runtimes, not CompatibilityMatrix profiles", () => {
  const normalized = normalizeApiArtifact(withDecision({ ...transportSource(), compatibility_matrix: { profiles: [{ runtime: "claude", state: "compatible", adapterStatus: "available" }, { runtime: "codex", state: "experimental", adapterStatus: "experimental" }, { runtime: "opencode", state: "incompatible", adapterStatus: "available" }, { runtime: "pi", state: "unsupported", adapterStatus: "unavailable" }] } }, { ...allowedDecision, runtime: "opencode", adapter: "opencode-workspace" }));
  if ("kind" in normalized) throw new Error(normalized.message);
  assert.equal("kind" in adaptApiArtifact("opencode", { ...apiArtifact("opencode"), distribution_decision: { ...allowedDecision, runtime: "opencode", adapter: "opencode-workspace", allowed: false, code: "RUNTIME_UNSUPPORTED", diagnostic: "Blocked" } }), true);
});
test("canonical output digest detects path, kind and byte-layout changes", () => {
  const base = adaptApiArtifact("claude", apiArtifact()); const moved = adaptApiArtifact("claude", { ...apiArtifact(), files: [{ ...source.files[0], path: "references/other.md" }, source.files[1]] });
  const changedKind = adaptApiArtifact("claude", { ...apiArtifact(), files: [{ ...source.files[0], kind: "binary" }, source.files[1]] });
  if ("kind" in base || "kind" in moved || "kind" in changedKind) throw new Error("expected outputs");
  assert.notEqual(base.output_hash, moved.output_hash); assert.notEqual(base.output_hash, changedKind.output_hash);
});
test("consumes the exact structured MCP artifact compatibility payload for allowed and blocked decisions", () => {
  const payload = JSON.parse(readFileSync(fileURLToPath(new URL("./__fixtures__/mcp-artifact-compatibility.json", import.meta.url)), "utf8"));
  const allowed = normalizeApiArtifact(payload); if ("kind" in allowed) throw new Error(allowed.message);
  assert.equal("kind" in adaptApiArtifact("claude", allowed), false);
  const blocked = normalizeApiArtifact({ ...payload, distribution_decision: { ...payload.distribution_decision, allowed: false, state: "experimental", code: "SKILL_DISTRIBUTION_EXPERIMENTAL_POLICY_REQUIRED", diagnostic: "Explicit acknowledgement required" } });
  if ("kind" in blocked) throw new Error(blocked.message);
  const result = adaptApiArtifact("claude", blocked);
  assert.equal("kind" in result, true); if ("kind" in result) assert.equal("files" in result, false);
});
test("derives a fail-closed multi-runtime aggregate without hiding partial failure", async () => {
  const { deriveMultiRuntimeDistribution } = await import("./runtime-adapters.ts");
  const result = deriveMultiRuntimeDistribution([
    { operationId: "op-1", status: "succeeded", runtime: "claude", releaseId: "revision-1", evidence: { runtime: "claude", observedHash: source.canonical_hash, runtimeVersion: "1.0.0", verifiedAt: "2026-08-18T12:01:00.000Z" } },
    { operationId: "op-2", status: "failed", runtime: "codex", releaseId: "revision-1" },
  ]);
  assert.equal(result.aggregate, "failed"); assert.equal(result.items[1].status, "failed");
});
test("only a succeeded API operation with matching runtime evidence can claim a runtime result", async () => {
  const { isVerifiedDistributionResult } = await import("./runtime-adapters.ts");
  assert.equal(isVerifiedDistributionResult({ operationId: "operation-1", status: "succeeded", runtime: "claude", releaseId: "revision-1", evidence: { runtime: "claude", observedHash: source.canonical_hash, runtimeVersion: "1.0.0", verifiedAt: "2026-08-18T12:01:00.000Z" } }, apiArtifact()), true);
  assert.equal(isVerifiedDistributionResult({ operationId: "operation-1", status: "pending", runtime: "claude", releaseId: "revision-1" }, apiArtifact()), false);
});
test("invalid API result produces no output", () => assert.deepEqual(adaptApiArtifact("pi", { ...apiArtifact("pi"), integrity: { valid: false } }), { kind: "adapter_failure", runtime: "pi", release_id: "revision-1", canonical_hash: source.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API canonical artifact is invalid" }));
test("emits no output when the API compatibility decision blocks distribution", () => {
  const result = adaptApiArtifact("codex", { ...apiArtifact("codex"), distribution_decision: { ...allowedDecision, runtime: "codex", allowed: false, code: "SKILL_DISTRIBUTION_EXPERIMENTAL_POLICY_REQUIRED", diagnostic: "Explicit acknowledgement required" } });
  assert.deepEqual(result, { kind: "adapter_failure", runtime: "codex", release_id: source.release_id, canonical_hash: source.canonical_hash, code: "SKILL_DISTRIBUTION_EXPERIMENTAL_POLICY_REQUIRED", message: "Explicit acknowledgement required" });
});
