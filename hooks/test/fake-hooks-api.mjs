// Loopback fake of the Allye hook-pairing API used by hooks/test-allye-hooks.sh (run by node in
// tests only; the scripts under test run with node removed from PATH).
// Usage: node fake-hooks-api.mjs <dir>. Writes <dir>/port. Control files in <dir>:
//   mode: normal | err | bad-token | malformed | not-json | redirect | oversized | slow | hostile   (per request)
//   status, code: used by mode err (status default 500; code optional, absent = no code)
// GET /api/memories/preferences (hooks/test-session-preferences.sh) uses the same mode file:
//   normal (two items, one with a null title) | empty | shape (200 not shaped as D-05) | hostile
//   (control, bidi, zero-width, tag characters, headings, fences) | big (20 items of 400 multi-byte
//   characters; pad = one item of <dir>/pad 'a' characters; huge1..3 = ~900 KB bodies; bigger = 900 characters, exceeds the cap) | lines (one item of many one-character lines) | err | slow | swap401 (replaces the
//   credential file with <dir>/swap-src at <dir>/swap-dst, then answers 401 HOOK_CREDENTIAL_INVALID)
// Logs: requests.log (JSON lines {method, path, body, authorization}); last-token (the token the
// last successful exchange issued). Contract: D-04 (bodies in the envelope's `data`), D-05 error shape.
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { appendFileSync, copyFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";

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

    if (req.method === "GET" && req.url === "/api/memories/preferences") {
      const item = (i, title, content) => ({ id: `m-${i}`, title, content, tags: [], createdAt: "2026-01-01T00:00:00.000Z", updatedAt: "2026-01-01T00:00:00.000Z" });
      if (mode === "slow") return void setTimeout(() => send(res, 200, envelope({ items: [] })), 30000);
      if (mode === "err") return failure(res, req.url, Number(read("status", "500")), read("code", "") || undefined);
      if (mode === "swap401") {
        copyFileSync(read("swap-src", ""), read("swap-dst", ""));
        return failure(res, req.url, 401, "HOOK_CREDENTIAL_INVALID");
      }
      if (mode === "empty") return send(res, 200, envelope({ items: [] }));
      if (mode === "shape") return send(res, 200, envelope({ items: "nope" }));
      if (mode === "not-json") return send(res, 200, "<html>not json</html>");
      if (mode === "big" || mode === "bigger") {
        const n = mode === "big" ? 400 : 900;
        return send(res, 200, envelope({ items: Array.from({ length: 20 }, (_, i) => item(i, `Pref ${i}`, Array.from({ length: n }, (_, k) => ["é", "世", "🎉"][k % 3]).join(""))) }));
      }
      if (mode === "pad") return send(res, 200, envelope({ items: [item(1, "T", "a".repeat(Number(read("pad", "1"))))] }));
      if (mode === "huge1") return send(res, 200, envelope({ items: [item(1, "t".repeat(50000), "a".repeat(900000))] }));
      if (mode === "huge2") return send(res, 200, envelope({ items: [item(1, "\u200b".repeat(10000), "\n".repeat(200000) + "\u200b".repeat(100000) + "\r".repeat(100000))] }));
      if (mode === "huge3") return send(res, 200, envelope({ items: Array.from({ length: 200 }, (_, i) => item(i, "t", "\n".repeat(2000))) }));
      if (mode === "lines") return send(res, 200, envelope({ items: [item(1, "Many lines", Array.from({ length: 20000 }, () => "x").join("\n"))] }));
      if (mode === "hostile") {
        return send(res, 200, envelope({ items: [
          item(1, "Ti\u202etle\u200b\n# Fake", "# Heading\n```\nrun rm -rf\n```\nline\u2028two\r\nthree\rfour\u0085five\u001b[31mred\u0007bell\u007f\u0090x\u200d\u2060\ufeff\u2066y\udb40\udc41tag"),
          item(2, null, "second"),
          item(3, "", "third"),
        ] }));
      }
      return send(res, 200, envelope({ items: [item(1, "Prefer tabs", "Use tabs.\nNever spaces."), item(2, null, "Reply in Portuguese")] }));
    }

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
