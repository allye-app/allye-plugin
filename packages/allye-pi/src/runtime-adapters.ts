import { createHash } from "node:crypto";

export type Runtime = "claude" | "codex" | "opencode" | "pi";
type ApiFile = { path: string; bytes: Uint8Array; kind: string };
type ApiDecision = { release_id: string; canonical_hash: string; runtime: Runtime; contract_version: string; state: string; allowed: boolean; adapter: string | null; adapter_version: string | null; code?: string | null; diagnostic?: string; limitations?: readonly string[] };
type ApiArtifact = { release_id: string; canonical_hash: string; files: readonly ApiFile[]; integrity: { valid: boolean }; distribution_decision: ApiDecision };
type TransportArtifact = { release_id: string; canonical_hash: string; files: readonly { path: string; bytes_base64: string; kind: string }[]; integrity: { valid: boolean }; manifest?: { sha256: string; files: readonly { path: string; bytes: number; sha256: string }[] }; compatibility_matrix?: { profiles: readonly { runtime: string; state: string; adapterStatus: string }[] }; distribution_decision?: ApiDecision };

/** Normalizes the transport DTO returned by the API/MCP endpoint; no local source is read. */
export function normalizeApiArtifact(payload: TransportArtifact): ApiArtifact | RuntimeFailure {
  try {
    if (!payload.manifest || !payload.distribution_decision || payload.manifest.sha256 !== payload.canonical_hash) throw new Error("manifest");
    const decision = payload.distribution_decision;
    if (decision.release_id !== payload.release_id || decision.canonical_hash !== payload.canonical_hash || !decision.runtime || !decision.contract_version || !decision.state || typeof decision.allowed !== "boolean") throw new Error("decision");
    const seen = new Set<string>();
    const files = payload.files.map((file) => {
      if (!/^(SKILL\.md|(references|assets|scripts)\/[^/]+(?:\/[^/]+)*)$/.test(file.path) || !["file", "binary"].includes(file.kind) || seen.has(file.path) || !/^[A-Za-z0-9+/]*={0,2}$/.test(file.bytes_base64)) throw new Error("path");
      seen.add(file.path); const bytes = new Uint8Array(Buffer.from(file.bytes_base64, "base64"));
      const entry = payload.manifest!.files.find((candidate) => candidate.path === file.path);
      if (!entry || entry.bytes !== bytes.byteLength || entry.sha256 !== createHash("sha256").update(bytes).digest("hex")) throw new Error("integrity");
      return { path: file.path, kind: file.kind, bytes };
    });
    if (files.length !== payload.manifest.files.length) throw new Error("manifest");
    const digest = createHash("sha256");
    for (const file of [...files].sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0)) digest.update(file.path).update("\0").update(file.bytes).update("\0");
    if (digest.digest("hex") !== payload.canonical_hash) throw new Error("aggregate");
    return { release_id: payload.release_id, canonical_hash: payload.canonical_hash, integrity: payload.integrity, files, distribution_decision: decision };
  } catch { return { kind: "adapter_failure", runtime: "pi", release_id: payload.release_id, canonical_hash: payload.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API transport artifact is invalid" }; }
}
export type RuntimeOutput = { runtime: Runtime; adapter: string; adapter_version: string; release_id: string; canonical_hash: string; output_hash: string; files: readonly ApiFile[] };
export type RuntimeFailure = { kind: "adapter_failure"; runtime: Runtime; release_id: string; canonical_hash: string; code: string; message: string };
/** API public result projection. The Plugin never turns output generation into installation evidence. */
export type DistributionResult = { operationId: string | null; status: "pending" | "succeeded" | "failed" | "noop" | "conflict" | "blocked"; runtime: Runtime; releaseId: string; evidence?: { runtime: Runtime; observedHash: string; runtimeVersion: string; verifiedAt: string } };
export type MultiRuntimeDistributionResult = { items: readonly DistributionResult[]; aggregate: DistributionResult["status"] };
export function deriveMultiRuntimeDistribution(items: readonly DistributionResult[]): MultiRuntimeDistributionResult {
  const states = new Set(items.map((item) => item.status));
  const aggregate = states.has("failed") ? "failed" : states.has("blocked") ? "blocked" : states.has("conflict") ? "conflict" : states.has("pending") ? "pending" : items.length > 0 && [...states].every((state) => state === "succeeded") ? "succeeded" : states.has("noop") ? "noop" : "conflict";
  return { items, aggregate };
}
export function isVerifiedDistributionResult(result: DistributionResult, artifact: ApiArtifact): boolean {
  return result.status === "succeeded"
    && result.operationId !== null
    && result.runtime === artifact.distribution_decision.runtime
    && result.releaseId === artifact.release_id
    && result.evidence?.runtime === result.runtime
    && result.evidence.observedHash === artifact.canonical_hash
    && Boolean(result.evidence.runtimeVersion)
    && Boolean(result.evidence.verifiedAt);
}
/** The sole Plugin mutation gate; remove/pending/failure outcomes are always read-only. */
export function mayMaterializeDistribution(result: DistributionResult, artifact: ApiArtifact): boolean {
  return isVerifiedDistributionResult(result, artifact);
}

/** Plugin consumes only an API/MCP response; it does not load local canonical source. */
export function adaptApiArtifact(runtime: Runtime, artifact: ApiArtifact): RuntimeOutput | RuntimeFailure {
  // The API evaluator is authoritative. Consumers never reconstruct a
  // CompatibilityMatrix decision from local transport metadata.
  const decision = artifact.distribution_decision;
  if (decision.runtime !== runtime || !decision.allowed || !decision.adapter || !decision.adapter_version) return {
    kind: "adapter_failure", runtime, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash,
    code: decision.code ?? "SKILL_DISTRIBUTION_BLOCKED",
    message: decision.diagnostic ?? "Distribution was blocked by the API CompatibilityMatrix",
  };
  if (!artifact.integrity.valid || !artifact.release_id || !artifact.canonical_hash) return { kind: "adapter_failure", runtime, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API canonical artifact is invalid" };
  const files = artifact.files.map((file) => ({ ...file, bytes: new Uint8Array(file.bytes) }));
  if (files.some((file) => !file.path || file.path.includes(".."))) return { kind: "adapter_failure", runtime, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API canonical artifact contains an invalid path" };
  const adapter = decision.adapter;
  const digest = createHash("sha256").update(JSON.stringify({ runtime, adapter, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash }));
  for (const file of [...files].sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0)) {
    digest.update(file.path).update("\0").update(file.kind).update("\0").update(String(file.bytes.byteLength)).update("\0").update(file.bytes).update("\0");
  }
  const output_hash = digest.digest("hex");
  return { runtime, adapter, adapter_version: decision.adapter_version, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash, output_hash, files };
}
