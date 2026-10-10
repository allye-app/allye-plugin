// Loopback fake of the Allye skills API used by install/test-installer.sh.
// Control files in $DIR: release (1|2), mode (normal|bad-artifact|bad-token|
// reject-complete|blocked|not-authorized|team-selection-required|
// marketplace-retired|pending-rollback|mutate-on-preflight|lost-complete|access-lost-on-preflight|
// hostile-skill|hostile-release|hostile-hash|hostile-op (ids that would break a URL path)|
// access-lost-on-complete|hang-complete|no-iss-aud|newline-token|exec-context-500|bad-request), token-kid (header kid of the
// tokens, default = kid), mutate-path (file appended to by mutate-on-preflight), kid (JWKS key id, default test-kid), port (written).
// hang-fail (file, 1) makes POST .../fail hang. hold-complete (file, 1) delays the reject-complete answer until it is not 1.
// hostile (file, 1) appends terminal control sequences to server texts and the release version.
// Logs: calls (text, one line per request) and requests.log (JSON lines
// {method, path, body, xTeam}). It mirrors the delivered API rules (D-32) but never
// evaluates capabilities or formats (D-37).
import { createServer } from "node:http";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const dir = process.argv[2];
const SKILL_ID = "11111111-2222-3333-4444-555555555555";
const ISS = "https://api.allye.test";
const AUD = "allye-skill-installer";
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const read = (name, fallback) => (existsSync(`${dir}/${name}`) ? readFileSync(`${dir}/${name}`, "utf8").trim() : fallback);
const sha = (b) => createHash("sha256").update(b).digest("hex");
const b64 = (v) => Buffer.from(typeof v === "string" ? v : JSON.stringify(v)).toString("base64url");

// Compatibility matrix: runtime -> "compatible" | "experimental"; absent = blocked.
const MATRIX = {
  "1.0.0": { claude: "compatible", codex: "experimental", pi: "compatible" },
  "1.1.0": { claude: "compatible", codex: "experimental", opencode: "experimental", pi: "compatible" },
};

// hostile=1 appends terminal control sequences to every server-supplied text (SHD-22).
const H = () => (read("hostile", "") === "1" ? "\u001b]0;pwn\u0007\r\u009b31mC1\u202eRLO\u200bZW\u2066iso\\033]0;pwn2\\007" : "");

function release() {
  const n = read("release", "1");
  const files = [
    { path: "SKILL.md", bytes: Buffer.from(`---\nname: team-standards\ndescription: Team coding standards v${n}\n---\n\n# Standards ${n}\n`) },
    { path: "references/style.md", bytes: Buffer.from(`# Style ${n}\n`) },
  ];
  const digest = createHash("sha256");
  for (const f of [...files].sort((a, b) => (a.path < b.path ? -1 : 1))) digest.update(f.path).update("\0").update(f.bytes).update("\0");
  const mode = read("mode", "normal");
  return {
    id: mode === "hostile-release" ? "release-1/../../x" : `release-${n}`,
    version: `1.${n}.0${H()}`,
    files,
    hash: mode === "hostile-hash" ? "abc?x=1" : digest.digest("hex"),
  };
}
const skill = () => {
  const r = release();
  return { id: read("mode", "normal") === "hostile-skill" ? "aaa/../bbb" : SKILL_ID, slug: "team-standards", name: `Team standards${H()}`, scope: "team", release: { release_id: r.id, version: r.version, canonical_hash: r.hash, origin: null } };
};
const ops = new Map();
const ledger = new Map(); // `${skill}|${runtime}|${target}` -> { rows: [{ kind: "install"|"rollback", status, op? }] }
// The member's answers come from the last applied install row; a pending rollback row opened by
// an owner or admin sits after it and must change nothing (D-32).
const applied = (row) => [...(row?.rows ?? [])].reverse().find((r) => r.kind === "install" && r.status === "applied")?.op;
const persist = () => writeFileSync(`${dir}/ledger.json`, JSON.stringify([...ledger].map(([key, row]) => ({ key, rows: row.rows.map((r) => ({ kind: r.kind, status: r.status, releaseId: r.op?.releaseId })) }))));
const byKey = new Map(); // idempotencyKey -> op
const send = (res, code, data) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(code < 300 ? { requestId: "r", data } : data)); };
const bad = (res, field, message, hint) => send(res, 400, { code: "VALIDATION_FAILED", field, message: `${field}: ${message}${H()}`, ...(hint || H() ? { hint: `${hint ?? "see the API docs"}${H()}` } : {}) });

// Returns an error [field, message] or null.
function validateReinstall(kind, body) {
  const hasR = Object.prototype.hasOwnProperty.call(body, "reinstall");
  if (!hasR) return null;
  if (kind !== "request") return ["reinstall", "only accepted on request"];
  if (body.baseReleaseId !== undefined || body.observedHash !== undefined) return ["reinstall", "cannot be combined with baseReleaseId/observedHash"];
  const r = body.reinstall;
  if (!r || typeof r !== "object" || Array.isArray(r)) return ["reinstall", "must be an object"];
  if (!["missing", "modified"].includes(r.observedLocalState)) return ["reinstall.observedLocalState", "must be missing or modified"];
  if (r.observedLocalState === "modified" && r.observedLocalHash === undefined) return ["reinstall.observedLocalHash", "required for modified"];
  if (r.observedLocalState === "missing" && r.observedLocalHash !== undefined) return ["reinstall.observedLocalHash", "rejected for missing"];
  if (r.observedLocalHash !== undefined && !/^[0-9a-f]{64}$/.test(String(r.observedLocalHash))) return ["reinstall.observedLocalHash", "must be 64 lowercase hex"];
  return null;
}

createServer((req, res) => {
  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    const url = new URL(req.url, "http://x");
    const path = url.pathname;
    const auth = req.headers.authorization ?? "";
    const body = raw ? JSON.parse(raw) : {};
    const mode = read("mode", "normal");
    const kid = read("kid", "test-kid");
    if (mode === "pending-rollback") {
      for (const row of ledger.values()) if (applied(row) && !row.rows.some((r) => r.kind === "rollback")) { row.rows.push({ kind: "rollback", status: "pending" }); persist(); }
    }
    appendFileSync(`${dir}/calls`, `${req.method} ${path.replace(SKILL_ID, ":id")}${body.baseReleaseId ? ` base=${body.baseReleaseId}` : ""}${body.code ? ` code=${body.code}` : ""}\n`);
    const bearer = !auth ? "none" : auth === "Bearer pat_test" ? "pat" : auth === "Bearer @pat" ? "sentinel" : /^Bearer eyJ/.test(auth) ? "op-token" : "other"; // a label, never the credential
    appendFileSync(`${dir}/requests.log`, `${JSON.stringify({ method: req.method, path, body: raw ? body : null, xTeam: req.headers["x-team-id"] ?? null, bearer })}\n`);
    if (req.headers["x-allye-channel"] !== "plugin") return send(res, 400, { code: "BAD_CHANNEL" });
    if (path === "/api/skills/distribution-execution/jwks") return send(res, 200, { keys: [{ ...publicKey.export({ format: "jwk" }), kid, use: "sig", alg: "RS256" }] });
    const op = path.match(/\/distributions\/([^/]+)\/(execution-context|preflight|complete|fail)$/);
    if (op) {
      const o = ops.get(op[1]);
      if (!o) return send(res, 404, { code: "NOT_FOUND" });
      if (op[2] === "execution-context") {
        if (auth !== "Bearer pat_test") return send(res, 401, { code: "UNAUTHORIZED" });
        if (mode === "exec-context-500") return send(res, 500, { code: "SIGNING_KEY_NOT_CONFIGURED", message: `execution signing key is not configured${H()}`, hint: `contact the operator of this API${H()}` });
        const claims = { ...(mode === "no-iss-aud" ? {} : { iss: ISS, aud: AUD }), typ: "skill_distribution_execution", actor: "user-1", skillId: SKILL_ID, distributionId: o.operationId, releaseId: o.releaseId, version: o.version, origin: o.origin, runtime: o.runtime, target: o.target, expectedHash: o.expectedHash, exp: Math.floor(Date.now() / 1000) + 600 };
        const input = `${b64({ alg: "RS256", kid: read("token-kid", kid), typ: "JWT" })}.${b64(claims)}`;
        let token = `${input}.${sign("RSA-SHA256", Buffer.from(input), privateKey).toString("base64url")}`;
        if (mode === "bad-token") token = `${input}.${Buffer.from("forged").toString("base64url")}`;
        if (mode === "newline-token") token += `\noutput = "${dir}/pwned"`; // a hostile token: config injection attempt
        o.token = token;
        return send(res, 201, { operationId: o.operationId, skillId: SKILL_ID, releaseId: o.releaseId, version: o.version, origin: o.origin, runtime: o.runtime, target: o.target, expectedHash: o.expectedHash, executionToken: token, expiresAt: new Date(Date.now() + 600000).toISOString() });
      }
      if (auth !== `Bearer ${o.token}` && !(op[2] === "fail" && auth === "Bearer pat_test" && read("fail-needs-token", "") !== "1")) return send(res, 401, { code: "TOKEN_REQUIRED" });
      if (op[2] === "fail") {
        if (read("hang-fail", "") === "1") return; // never answers: the test signals the installer meanwhile
        if (o.status !== "pending") return send(res, 409, { code: "DISTRIBUTION_NOT_PENDING", message: `operation is ${o.status}` });
        o.status = "failed";
        return send(res, 200, { ...o, status: "failed" });
      }
      if (op[2] === "preflight" && mode === "mutate-on-preflight") {
        const mutated = read("mutate-path", `${dir}/mutated`);
        mkdirSync(dirname(mutated), { recursive: true });
        appendFileSync(mutated, "changed while the install ran\n");
      }
      if (op[2] === "preflight" && mode === "access-lost-on-preflight") return send(res, 409, { code: "DISTRIBUTION_NOT_AUTHORIZED", message: "view access was lost" });
      if (op[2] === "preflight") return send(res, 200, { operationId: o.operationId, status: "pending", skillId: SKILL_ID, releaseId: o.releaseId, expectedHash: o.expectedHash, runtime: o.runtime, target: o.target });
      // complete
      if (mode === "hang-complete") return; // never answers: the test kills the installer
      if (mode === "access-lost-on-complete") return send(res, 409, { code: "DISTRIBUTION_NOT_AUTHORIZED", message: "view access was lost" });
      if (mode === "reject-complete" && read("hold-complete", "") === "1") { // answers only once the test clears hold-complete
        const t = setInterval(() => { if (read("hold-complete", "") !== "1") { clearInterval(t); send(res, 409, { code: "DISTRIBUTION_EVIDENCE_REJECTED", message: "rejected by test" }); } }, 100);
        return;
      }
      if (mode === "reject-complete") return send(res, 409, { code: "DISTRIBUTION_EVIDENCE_REJECTED", message: "rejected by test" });
      const kind = body.installKind;
      if (kind !== undefined && !["directory", "pi-package"].includes(kind)) return bad(res, "installKind", "must be directory or pi-package");
      if (kind === "directory" && body.piPackage !== undefined) return bad(res, "piPackage", "not accepted with installKind directory");
      if (kind === "pi-package" && o.runtime !== "pi") return bad(res, "installKind", "pi-package is only for runtime pi");
      if ((kind === "pi-package" || (kind === undefined && o.runtime === "pi")) && (!body.piPackage || typeof body.piPackage !== "object")) return bad(res, "piPackage", "required");
      if (o.status !== "pending") return send(res, 409, { code: "DISTRIBUTION_NOT_PENDING" });
      if (body.observedHash !== o.expectedHash) return send(res, 409, { code: "HASH_MISMATCH" });
      o.status = "succeeded";
      const row = ledger.get(o.ledgerKey) ?? { rows: [] };
      row.rows.push({ kind: "install", status: "applied", op: o });
      ledger.set(o.ledgerKey, row);
      persist();
      if (mode === "lost-complete") return req.socket.destroy(); // applied, but the response never arrives
      return send(res, 200, { ...o, status: "succeeded", evidence: { observedHash: body.observedHash, runtimeVersion: body.runtimeVersion, verifiedAt: body.verifiedAt } });
    }
    if (auth !== "Bearer pat_test") return send(res, 401, { code: "UNAUTHORIZED", message: "Invalid token" });
    const s = skill();
    if (req.method === "GET" && path === "/api/skills") return send(res, 200, { data: [s], total: 1 });
    if (req.method === "GET" && path === "/api/skills/resolve/team-standards" && mode === "team-selection-required") {
      return send(res, 422, { code: "TEAM_SELECTION_REQUIRED", message: "slug matches skills in several teams", teams: [{ id: "team-a", name: `Alpha${H()}` }, { id: "team-b", name: "Beta" }] });
    }
    if (req.method === "GET" && path === "/api/skills/resolve/team-standards") return send(res, 200, { selected: s, candidates: [s], conflict: false });
    if (req.method === "GET" && path === `/api/skills/${SKILL_ID}`) return send(res, 200, s);
    const art = path.match(/\/releases\/([^/]+)\/artifact$/);
    if (req.method === "GET" && art) {
      const r = release();
      if (art[1] !== r.id || url.searchParams.get("canonicalHash") !== r.hash) return send(res, 409, { code: "RELEASE_NOT_CURRENT" });
      const files = r.files.map((f) => ({ path: f.path, kind: "file", bytes_base64: f.bytes.toString("base64") }));
      if (mode === "bad-artifact") files[1].bytes_base64 = Buffer.from("# tampered\n").toString("base64");
      return send(res, 200, { skill_id: SKILL_ID, release_id: r.id, version: r.version, canonical_hash: r.hash, manifest: { sha256: r.hash, files: r.files.map((f) => ({ path: f.path, bytes: f.bytes.length, sha256: sha(f.bytes) })) }, files, origin: null, integrity: { valid: true, package_digest: r.hash } });
    }
    const dist = path.match(/\/distributions\/(request|update)$/);
    if (req.method === "POST" && dist) {
      const kind = dist[1];
      for (const f of ["requiredCapabilities", "inputFormat", "outputFormat"]) if (f in body) return bad(res, f, "not accepted; the installer never sends it");
      if (mode === "bad-request") return bad(res, "target", "must match ^[a-z0-9:_-]{1,200}$", "upgrade the installer");
      if (mode === "not-authorized") return send(res, 409, { code: "DISTRIBUTION_NOT_AUTHORIZED", message: "caller cannot view this skill" });
      if (mode === "marketplace-retired") return send(res, 410, { code: "MARKETPLACE_RETIRED", message: "marketplace skills are retired" });
      const profile = MATRIX[body.runtimeVersion];
      if (mode === "blocked" || !profile || !profile[body.runtime]) return send(res, 409, { code: "RUNTIME_INCOMPATIBLE", runtime_code: "SKILL_DISTRIBUTION_COMPATIBILITY_INCOMPATIBLE", message: `Runtime ${body.runtime} ${body.runtimeVersion} is not compatible`, hint: "upgrade the API to compatibility profile 1.1.0" });
      if (profile[body.runtime] === "experimental" && body.allowExperimental !== true) return send(res, 409, { code: "RUNTIME_INCOMPATIBLE", message: "experimental runtime needs allowExperimental" });
      const key = body.idempotencyKey;
      if (typeof key !== "string" || key.length === 0) return bad(res, "idempotencyKey", "required");
      if (body.runtimeVersion === "1.1.0") {
        if (key.length > 218) return bad(res, "idempotencyKey", "at most 218 characters");
        if (typeof body.target !== "string" || !/^[a-z0-9:_-]{1,200}$/.test(body.target)) return bad(res, "target", "must match ^[a-z0-9:_-]{1,200}$");
      } else if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:/i.test(key)) {
        return bad(res, "idempotencyKey", "belongs to another user");
      }
      if (typeof body.target !== "string" || body.target.length === 0) return bad(res, "target", "required");
      if (kind === "update" && (!body.baseReleaseId || !body.observedHash)) return bad(res, "baseReleaseId", "update needs baseReleaseId and observedHash");
      const bad_re = validateReinstall(kind, body);
      if (bad_re) return bad(res, bad_re[0], bad_re[1]);
      const ledgerKey = `${SKILL_ID}|${body.runtime}|${body.target}`;
      const row = ledger.get(ledgerKey);
      if (body.reinstall && body.releaseId !== release().id) return send(res, 409, { code: "RELEASE_NOT_CURRENT", message: "a reinstall targets the current approved release" });
      if (kind === "update" && (!applied(row) || applied(row).releaseId !== body.baseReleaseId)) return send(res, 409, { code: "BASE_RELEASE_MISMATCH" });
      if (byKey.has(key)) return send(res, 200, byKey.get(key));
      if (kind === "request" && !body.reinstall && applied(row) && applied(row).releaseId === body.releaseId) {
        return send(res, 200, { status: "noop", skillId: SKILL_ID, releaseId: body.releaseId, runtime: body.runtime, target: body.target });
      }
      const r = release();
      const o = { operationId: `op-${ops.size + 1}`, status: "pending", skillId: SKILL_ID, releaseId: body.releaseId, version: r.version, runtime: body.runtime, target: body.target, expectedHash: r.hash, origin: body.reinstall && applied(row) ? "api:reinstall" : null, ledgerKey };
      ops.set(o.operationId, o);
      byKey.set(key, o);
      return send(res, 201, mode === "hostile-op" ? { ...o, operationId: "op-1/../../x" } : o);
    }
    send(res, 404, { code: "NOT_FOUND", message: `${req.method} ${path}` });
  });
}).listen(0, "127.0.0.1", function () { writeFileSync(`${dir}/port`, String(this.address().port)); });
