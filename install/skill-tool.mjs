#!/usr/bin/env node
// Allye skills installer — integrity and signature helpers (Node >= 18, no deps).
//
//   tree-hash <dir> [--backup]               canonical hash of an installed tree (--backup: a backup tree)
//   stage-artifact <artifact.json> <expected.json> <stage-dir>
//                                            verify an API artifact and write its files
//   verify-token <context.json> <jwks.json>  verify the RS256 execution token
//
// The canonical hash matches the API (canonical-skill.contract.ts): files sorted
// by path (code-unit order), sha256 over `path \0 bytes \0` for each file.
// Exit 0 on success; on failure print one actionable line to stderr, exit 1.
import { createHash, createPublicKey, verify } from "node:crypto";
import { lstatSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";

export const SIDECAR = ".allye-artifact.json";
export const BACKUP_SIDECAR = ".allye-artifact.backup.json";
const ALLOWED_PATH = /^(SKILL\.md|(references|assets|scripts)\/[^/]+(\/[^/]+)*)$/;

const fail = (message) => {
  process.stderr.write(`${message}\n`);
  process.exit(1);
};
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const byPath = (a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0);

export function canonicalHash(files) {
  const digest = createHash("sha256");
  for (const file of [...files].sort(byPath)) digest.update(file.path, "utf8").update("\0").update(file.bytes).update("\0");
  return digest.digest("hex");
}

// tree-hash --backup exists to verify a backup tree after its sidecar was renamed (installer
// finalize_backup); it has no production caller in the shell flow and is covered by tests.
// The backup sidecar name is only a provenance marker inside a backup tree (options.backup);
// in an installed tree a file with that name is the user's and is part of the hash.
export function readTree(root, options = {}) {
  const sidecars = new Set(options.backup ? [SIDECAR, BACKUP_SIDECAR] : [SIDECAR]);
  const files = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      const rel = relative(root, path).split(sep).join("/");
      const stat = lstatSync(path);
      const sidecarName = dir === root && sidecars.has(name); // the sidecar, at the tree root only
      if (sidecarName && stat.isFile()) continue;
      if (sidecarName || stat.isSymbolicLink() || (!stat.isFile() && !stat.isDirectory())) throw new Error(`unexpected non-regular entry: ${rel}`);
      if (stat.isDirectory()) walk(path);
      else files.push({ path: rel, bytes: readFileSync(path) });
    }
  };
  walk(root);
  return files;
}

export function checkArtifact(artifact, expected) {
  for (const key of ["skill_id", "release_id", "canonical_hash"]) {
    if (artifact[key] !== expected[key]) throw new Error(`artifact ${key} is ${JSON.stringify(artifact[key])}, expected ${JSON.stringify(expected[key])}`);
  }
  if (typeof artifact.version !== "string" || !artifact.version.trim()) throw new Error("artifact has no version");
  if (artifact.integrity?.valid !== true) throw new Error("API did not mark the artifact integrity as valid");
  if (!/^[a-f0-9]{64}$/.test(String(artifact.canonical_hash))) throw new Error("artifact canonical_hash is not a sha256 hex digest");
  if (artifact.manifest?.sha256 !== artifact.canonical_hash) throw new Error("artifact manifest.sha256 differs from canonical_hash");
  const manifest = new Map((artifact.manifest.files ?? []).map((entry) => [entry.path, entry]));
  if (!Array.isArray(artifact.files) || artifact.files.length === 0) throw new Error("artifact has no files");
  if (artifact.files.length !== manifest.size) throw new Error("artifact files and manifest differ in length");
  const seen = new Set();
  const files = artifact.files.map((file) => {
    const path = file.path;
    if (typeof path !== "string" || !ALLOWED_PATH.test(path) || path.split("/").some((part) => part === "." || part === ".." || part === "")) {
      throw new Error(`artifact path is not allowed: ${JSON.stringify(path)} (only SKILL.md, references/, assets/, scripts/)`);
    }
    if (seen.has(path)) throw new Error(`artifact path is duplicated: ${path}`);
    seen.add(path);
    if (typeof file.bytes_base64 !== "string" || !/^[A-Za-z0-9+/]*={0,2}$/.test(file.bytes_base64)) throw new Error(`artifact bytes are not base64: ${path}`);
    const bytes = Buffer.from(file.bytes_base64, "base64");
    const entry = manifest.get(path);
    if (!entry) throw new Error(`artifact file is missing from the manifest: ${path}`);
    if (entry.bytes !== bytes.byteLength || entry.sha256 !== sha256(bytes)) throw new Error(`artifact file failed its integrity check: ${path}`);
    return { path, bytes };
  });
  if (!seen.has("SKILL.md")) throw new Error("artifact has no SKILL.md");
  if (canonicalHash(files) !== artifact.canonical_hash) throw new Error("recomputed canonical hash differs from the artifact canonical_hash");
  return files;
}

const b64json = (part) => JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
const canonicalJson = (value) => {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
};

export function checkToken(context, jwks, nowSeconds = Math.floor(Date.now() / 1000)) {
  const token = context.executionToken;
  const [h, p, s] = typeof token === "string" ? token.split(".") : [];
  if (!h || !p || !s) throw new Error("execution token is not a compact JWS");
  const header = b64json(h);
  const payload = b64json(p);
  const keys = (jwks.data ?? jwks).keys ?? [];
  const key = keys.find((candidate) => candidate.kid === header.kid && candidate.kty === "RSA");
  if (header.alg !== "RS256" || !key) throw new Error(`execution token key ${JSON.stringify(header.kid)} is not in the API JWKS`);
  if (!verify("RSA-SHA256", Buffer.from(`${h}.${p}`), createPublicKey({ key, format: "jwk" }), Buffer.from(s, "base64url"))) throw new Error("execution token signature is invalid");
  if (payload.typ !== "skill_distribution_execution") throw new Error("execution token has the wrong type");
  if (!Number.isInteger(payload.exp) || payload.exp <= nowSeconds) throw new Error("execution token has expired; run the install again");
  if (payload.distributionId !== context.operationId) throw new Error("execution token is bound to another distribution");
  for (const name of ["skillId", "releaseId", "version", "runtime", "target", "expectedHash"]) {
    if (payload[name] !== context[name]) throw new Error(`execution token ${name} differs from its context`);
  }
  if (canonicalJson(payload.origin ?? null) !== canonicalJson(context.origin ?? null)) throw new Error("execution token origin differs from its context");
  return payload;
}

const isMain = process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;
if (isMain) {
  const [command, ...args] = process.argv.slice(2);
  try {
    if (command === "tree-hash") {
      process.stdout.write(canonicalHash(readTree(args[0], { backup: args[1] === "--backup" })));
    } else if (command === "stage-artifact") {
      const artifact = JSON.parse(readFileSync(args[0], "utf8"));
      const files = checkArtifact(artifact.data ?? artifact, JSON.parse(readFileSync(args[1], "utf8")));
      for (const file of files) {
        const target = join(args[2], ...file.path.split("/"));
        mkdirSync(dirname(target), { recursive: true });
        writeFileSync(target, file.bytes);
      }
      process.stdout.write(String(files.length));
    } else if (command === "verify-token") {
      checkToken(JSON.parse(readFileSync(args[0], "utf8")), JSON.parse(readFileSync(args[1], "utf8")));
    } else {
      fail("usage: skill-tool.mjs tree-hash <dir> [--backup] | stage-artifact <artifact> <expected> <dir> | verify-token <context> <jwks>");
    }
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error));
  }
}
