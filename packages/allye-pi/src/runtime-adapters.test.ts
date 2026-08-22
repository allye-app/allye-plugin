import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { adaptApiArtifact, normalizeApiArtifact } from "./runtime-adapters.ts";

const sourceFiles = [{ path: "SKILL.md", bytes: new TextEncoder().encode("# skill\n"), kind: "file" }, { path: "references/a.md", bytes: new TextEncoder().encode("a"), kind: "file" }];
const aggregate = createHash("sha256"); for (const file of [...sourceFiles].sort((a, b) => a.path < b.path ? -1 : 1)) aggregate.update(file.path).update("\0").update(file.bytes).update("\0");
const source = { release_id: "revision-1", canonical_hash: aggregate.digest("hex"), integrity: { valid: true }, files: sourceFiles };
for (const runtime of ["claude", "codex", "opencode", "pi"] as const) test(`${runtime} derives deterministic byte-preserving API output`, () => {
  const first = adaptApiArtifact(runtime, source); const second = adaptApiArtifact(runtime, source);
  assert.equal("kind" in first, false); assert.deepEqual(first, second);
  if ("kind" in first) throw new Error(first.message);
  assert.equal(first.release_id, source.release_id); assert.equal(first.canonical_hash, source.canonical_hash);
  assert.deepEqual(first.files.map((f) => [...f.bytes]), source.files.map((f) => [...f.bytes]));
});
test("consumes the exact API HTTP snapshot", () => {
  const response = JSON.parse(readFileSync(resolve(process.cwd(), "../allye-api/src/test/fixtures/canonical-artifact-http.json"), "utf8"));
  const normalized = normalizeApiArtifact(response); if ("kind" in normalized) throw new Error(normalized.message);
  const claude = adaptApiArtifact("claude", normalized); const pi = adaptApiArtifact("pi", normalized);
  assert.equal("kind" in claude, false); assert.equal("kind" in pi, true);
  const invalid = normalizeApiArtifact({ ...response, integrity: { valid: false } });
  if ("kind" in invalid) throw new Error(invalid.message);
  assert.equal("kind" in adaptApiArtifact("claude", invalid), true);
});
test("snapshots the API bytes_base64 and CompatibilityMatrix transport end to end", () => {
  const fixture = JSON.parse(readFileSync(fileURLToPath(new URL("./__fixtures__/canonical-artifact-api.json", import.meta.url)), "utf8"));
  const normalized = normalizeApiArtifact(fixture); if ("kind" in normalized) throw new Error(normalized.message);
  const claude = adaptApiArtifact("claude", normalized); const pi = adaptApiArtifact("pi", normalized);
  assert.deepEqual(JSON.parse(JSON.stringify({ release: normalized.release_id, hash: normalized.canonical_hash, files: normalized.files.map((file) => [file.path, Buffer.from(file.bytes).toString("base64")]) })), { release: "revision-1", hash: fixture.canonical_hash, files: fixture.files.map((file: { path: string; bytes_base64: string }) => [file.path, file.bytes_base64]) });
  assert.equal("kind" in claude, false); assert.equal("kind" in pi, true);
});
test("normalizes the API/MCP base64 transport DTO without Buffer JSON", () => {
  const transportFiles = source.files.map((file) => ({ path: file.path, kind: file.kind, bytes_base64: Buffer.from(file.bytes).toString("base64") }));
  const normalized = normalizeApiArtifact({ release_id: source.release_id, canonical_hash: source.canonical_hash, integrity: source.integrity, manifest: { sha256: source.canonical_hash, files: source.files.map((file) => ({ path: file.path, bytes: file.bytes.byteLength, sha256: createHash("sha256").update(file.bytes).digest("hex") })) }, compatibility_matrix: { profiles: [{ runtime: "claude", state: "compatible", adapterStatus: "available" }, { runtime: "codex", state: "experimental", adapterStatus: "experimental" }, { runtime: "opencode", state: "incompatible", adapterStatus: "available" }, { runtime: "pi", state: "unsupported", adapterStatus: "unavailable" }] }, files: transportFiles });
  if ("kind" in normalized) throw new Error(normalized.message);
  assert.deepEqual(normalized.files.map((file) => [...file.bytes]), source.files.map((file) => [...file.bytes]));
});
test("fails closed for an empty API CompatibilityMatrix", () => {
  const result = normalizeApiArtifact({ release_id: source.release_id, canonical_hash: source.canonical_hash, integrity: source.integrity, manifest: { sha256: source.canonical_hash, files: source.files.map((file) => ({ path: file.path, bytes: file.bytes.byteLength, sha256: createHash("sha256").update(file.bytes).digest("hex") })) }, files: source.files.map((file) => ({ path: file.path, kind: file.kind, bytes_base64: Buffer.from(file.bytes).toString("base64") })), compatibility_matrix: { profiles: [] } });
  assert.equal("kind" in result, true);
});
test("honors API CompatibilityMatrix profiles for unsupported runtimes", () => {
  const normalized = normalizeApiArtifact({ release_id: source.release_id, canonical_hash: source.canonical_hash, integrity: source.integrity, manifest: { sha256: source.canonical_hash, files: source.files.map((file) => ({ path: file.path, bytes: file.bytes.byteLength, sha256: createHash("sha256").update(file.bytes).digest("hex") })) }, files: source.files.map((file) => ({ path: file.path, kind: file.kind, bytes_base64: Buffer.from(file.bytes).toString("base64") })), compatibility_matrix: { profiles: [{ runtime: "claude", state: "compatible", adapterStatus: "available" }, { runtime: "codex", state: "experimental", adapterStatus: "experimental" }, { runtime: "opencode", state: "incompatible", adapterStatus: "available" }, { runtime: "pi", state: "unsupported", adapterStatus: "unavailable" }] } });
  if ("kind" in normalized) throw new Error(normalized.message);
  for (const runtime of ["opencode", "pi"] as const) assert.equal("kind" in adaptApiArtifact(runtime, normalized), true);
});
test("canonical output digest detects path, kind and byte-layout changes", () => {
  const base = adaptApiArtifact("claude", source); const moved = adaptApiArtifact("claude", { ...source, files: [{ ...source.files[0], path: "references/other.md" }, source.files[1]] });
  const changedKind = adaptApiArtifact("claude", { ...source, files: [{ ...source.files[0], kind: "binary" }, source.files[1]] });
  if ("kind" in base || "kind" in moved || "kind" in changedKind) throw new Error("expected outputs");
  assert.notEqual(base.output_hash, moved.output_hash); assert.notEqual(base.output_hash, changedKind.output_hash);
});
test("invalid API result produces no output", () => assert.deepEqual(adaptApiArtifact("pi", { ...source, integrity: { valid: false } }), { kind: "adapter_failure", runtime: "pi", release_id: "revision-1", canonical_hash: source.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API canonical artifact is invalid" }));
