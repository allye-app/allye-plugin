import { createHash } from "node:crypto";

export type Runtime = "claude" | "codex" | "opencode" | "pi";
type ApiFile = { path: string; bytes: Uint8Array; kind: string };
type ApiArtifact = { release_id: string; canonical_hash: string; files: readonly ApiFile[]; integrity: { valid: boolean }; compatibility?: Partial<Record<Runtime, { state: string; adapterStatus: string }>> };
type TransportArtifact = { release_id: string; canonical_hash: string; files: readonly { path: string; bytes_base64: string; kind: string }[]; integrity: { valid: boolean }; manifest?: { sha256: string; files: readonly { path: string; bytes: number; sha256: string }[] }; compatibility_matrix?: { profiles: readonly { runtime: string; state: string; adapterStatus: string }[] } };

/** Normalizes the transport DTO returned by the API/MCP endpoint; no local source is read. */
export function normalizeApiArtifact(payload: TransportArtifact): ApiArtifact | RuntimeFailure {
  try {
    if (!payload.manifest || !payload.compatibility_matrix || payload.manifest.sha256 !== payload.canonical_hash) throw new Error("manifest");
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
    const requiredRuntimes = ["claude", "codex", "opencode", "pi"] as const;
    const profiles = payload.compatibility_matrix.profiles;
    if (profiles.length !== requiredRuntimes.length || new Set(profiles.map((profile) => profile.runtime)).size !== requiredRuntimes.length || profiles.some((profile) => !requiredRuntimes.includes(profile.runtime as Runtime) || !profile.state || !profile.adapterStatus)) throw new Error("compatibility");
    const compatibility = Object.fromEntries(profiles.map((profile) => [profile.runtime, { state: profile.state, adapterStatus: profile.adapterStatus }]));
    return { ...payload, compatibility, files };
  } catch { return { kind: "adapter_failure", runtime: "pi", release_id: payload.release_id, canonical_hash: payload.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API transport artifact is invalid" }; }
}
export type RuntimeOutput = { runtime: Runtime; adapter: string; adapter_version: "1.0"; release_id: string; canonical_hash: string; output_hash: string; files: readonly ApiFile[] };
export type RuntimeFailure = { kind: "adapter_failure"; runtime: Runtime; release_id: string; canonical_hash: string; code: string; message: string };

/** Plugin consumes only an API/MCP response; it does not load local canonical source. */
export function adaptApiArtifact(runtime: Runtime, artifact: ApiArtifact): RuntimeOutput | RuntimeFailure {
  const compatibility = artifact.compatibility?.[runtime];
  if (compatibility && (compatibility.state === "unsupported" || compatibility.state === "incompatible" || compatibility.adapterStatus === "unavailable")) return { kind: "adapter_failure", runtime, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash, code: "RUNTIME_UNSUPPORTED", message: `Runtime ${runtime} is unsupported by the API CompatibilityMatrix` };
  if (!artifact.integrity.valid || !artifact.release_id || !artifact.canonical_hash) return { kind: "adapter_failure", runtime, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API canonical artifact is invalid" };
  const files = artifact.files.map((file) => ({ ...file, bytes: new Uint8Array(file.bytes) }));
  if (files.some((file) => !file.path || file.path.includes(".."))) return { kind: "adapter_failure", runtime, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash, code: "CANONICAL_ARTIFACT_INVALID", message: "API canonical artifact contains an invalid path" };
  const adapter = `${runtime}-workspace`;
  const digest = createHash("sha256").update(JSON.stringify({ runtime, adapter, release_id: artifact.release_id, canonical_hash: artifact.canonical_hash }));
  for (const file of [...files].sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0)) {
    digest.update(file.path).update("\0").update(file.kind).update("\0").update(String(file.bytes.byteLength)).update("\0").update(file.bytes).update("\0");
  }
  const output_hash = digest.digest("hex");
  return { runtime, adapter, adapter_version: "1.0", release_id: artifact.release_id, canonical_hash: artifact.canonical_hash, output_hash, files };
}
