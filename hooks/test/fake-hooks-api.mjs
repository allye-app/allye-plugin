// Loopback fake of the Allye hook-pairing API used by hooks/test-allye-hooks.sh (run by node in
// tests only; the scripts under test run with node removed from PATH).
// Usage: node fake-hooks-api.mjs <dir>. Writes <dir>/port. Control files in <dir>:
//   mode: normal | err | bad-token | malformed | not-json | redirect | oversized | slow | hostile   (per request)
//   status, code: used by mode err (status default 500; code optional, absent = no code)
// Logs: requests.log (JSON lines {method, path, body, authorization}); last-token (the token the
// last successful exchange issued). Contract: D-04 (bodies in the envelope's `data`), D-05 error shape.
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";

const dir = process.argv[2];
const read = (name, fallback) => (existsSync(`${dir}/${name}`) ? readFileSync(`${dir}/${name}`, "utf8").trim() : fallback);
const sha = (s) => createHash("sha256").update(s).digest("hex");
const pairings = new Map(); // pairingCode -> { challenge, deviceName, used }
let counter = 0;

const send = (res, code, body) => { res.writeHead(code, { "content-type": "application/json" }); res.end(typeof body === "string" ? body : JSON.stringify(body)); };
const envelope = (data) => ({ timestamp: "2026-01-01T00:00:00.000Z", requestId: "r-1", data });
const failure = (res, path, statusCode, code) =>
  send(res, statusCode, {
    timestamp: "2026-01-01T00:00:00.000Z", requestId: "r-1", correlationId: "c-1", path,
    error: { statusCode, message: { ...(code ? { code } : {}), message: "SERVER-TEXT-LEAK should never be printed" } },
  });

const server = createServer((req, res) => {
  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    let body = null;
    try { body = raw ? JSON.parse(raw) : null; } catch { /* kept null */ }
    appendFileSync(`${dir}/requests.log`, JSON.stringify({ method: req.method, path: req.url, body, authorization: req.headers.authorization ?? null }) + "\n");
    const mode = read("mode", "normal");

    // Stand-in for the MCP tool: binds a pairing code to a challenge (POST /api/hook-pairings).
    if (req.method === "POST" && req.url === "/api/hook-pairings") {
      if (!body || !/^[0-9a-f]{64}$/.test(body.challenge ?? "")) return failure(res, req.url, 400, "VALIDATION_FAILED");
      counter += 1;
      const pairingCode = `alyp_${sha(`code-${counter}-${body.challenge}`).slice(0, 32)}`;
      pairings.set(pairingCode, { challenge: body.challenge, deviceName: body.deviceName, used: false });
      return send(res, 201, envelope({ pairingCode, expiresAt: "2026-01-01T00:05:00.000Z", email: "dev@example.test", tenantName: "Acme Org", deviceName: body.deviceName }));
    }

    if (req.method === "POST" && req.url === "/api/hook-pairings/exchange") {
      if (mode === "slow") return void setTimeout(() => send(res, 201, envelope({})), 30000);
      if (mode === "err") return failure(res, req.url, Number(read("status", "500")), read("code", "") || undefined);
      if (mode === "redirect") { res.writeHead(302, { location: "http://evil.example/x" }); return void res.end(); }
      if (mode === "oversized") return send(res, 201, envelope({ pad: "x".repeat(70000) }));
      if (mode === "not-json") return send(res, 201, "<html>not json SERVER-TEXT-LEAK</html>");
      if (mode === "malformed") return send(res, 201, envelope("a string, not an object"));
      if (mode === "bad-token") {
        return send(res, 201, envelope({ token: 'alyh_OFFFORMAT"\n[injected]', email: "dev@example.test", tenantName: "Acme Org", deviceName: "x", absoluteExpiresAt: "2026-04-01T00:00:00.000Z" }));
      }
      if (!body || !/^alyp_[0-9a-f]{32}$/.test(body.pairingCode ?? "") || !/^[0-9a-f]{64}$/.test(body.verifier ?? "")) {
        return failure(res, req.url, 400, "VALIDATION_FAILED");
      }
      const p = pairings.get(body.pairingCode);
      if (!p || p.used || sha(body.verifier) !== p.challenge) return failure(res, req.url, 400, "HOOK_PAIRING_INVALID");
      p.used = true;
      const token = `alyh_${createHash("sha256").update(body.pairingCode).digest("base64url")}`;
      writeFileSync(`${dir}/last-token`, token);
      const hostile = mode === "hostile";
      return send(res, 201, envelope({
        token,
        email: hostile ? "dev\u001b[31m@example.test‮" : "dev@example.test",
        tenantName: hostile ? "Acme\u001b]0;pwn\u0007 Org​" : "Acme Org",
        deviceName: p.deviceName,
        absoluteExpiresAt: "2026-04-01T00:00:00.000Z",
      }));
    }
    return failure(res, req.url, 404, "NOT_FOUND");
  });
});

server.listen(0, "127.0.0.1", () => writeFileSync(`${dir}/port`, String(server.address().port)));
