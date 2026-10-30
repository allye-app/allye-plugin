#!/bin/bash
# Loopback stub of the Allye live-request endpoints (ALY-268) for the `answer *` sections of hooks/test-live-report.sh.
# TEST FIXTURE ONLY; it is never installed or run by the plugin.
#
# Why node and not pure shell: bash cannot listen on a socket, and nc/socat are not guaranteed on the machines that run the suite
# (here socat exists, nc does not). The suite already requires node for hooks/test/fake-hooks-api.mjs, and that fake (under
# hooks/test/, out of this slice) has no /api/live routes, so this file carries a small node server in a here-document. Like the fake API it runs
# OUTSIDE the sandbox PATH of the hook under test (the hook runs with `env -i` and no node).
#
# Usage: answer-stub-server.sh NODE DIR      (the harness starts it with every descriptor above 2 closed; the shell `exec`s node, so $! is
# node's pid). It writes DIR/port when listening, appends one JSON line per request to DIR/requests.log
# ({method, path, auth, ctype, body}: `auth` is true/false, the credential itself is never logged), and re-reads these control files
# of DIR at every request:
#   open         ok (default) | unanswerable | 404 (code not_found) | run_not_found (404, code run_not_found) | 405 | 429 | 500 | garbage | notjson | redirect | hold | killmid
#   wait         space-separated modes, the Nth wait call takes the Nth word (the last repeats):
#                pending (default) | allow | deny | question | decision | nodecision | terminal | expired | no_audience | slow | hold | malformed | unknown | redirect | 500 | 404 | 429
#                rawdata (ALY-269.5): answers with the file wait-data as the whole `data` object (any decision shape)
#   expires-in   seconds from the open to `expiresAt` (default 100); expires-at: a raw expiresAt string that overrides it
#   decision     (ALY-269.4) raw JSON file read by the wait mode `decision`: its content becomes `data.decision` of an `answered` wait
#                (`nodecision` answers with no decision key at all)
#   cancel, ack  ok (default) | hold | 500
# Envelope as the API: success {data: ...}; error {timestamp, requestId, correlationId, path, error: {statusCode, message: {code, message}}}.
# `redirect` answers 302 to /redirect-target of this same stub, so a test can see that the target is never requested.
[ "$#" -eq 2 ] || exit 2
NODE="$1"; DIR="$2"
JS=$(cat <<'EOF'
import { createServer } from "node:http";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
const dir = process.argv[1];
const read = (n, d) => (existsSync(`${dir}/${n}`) ? readFileSync(`${dir}/${n}`, "utf8").trim() || d : d);
const socks = new Set();
let waits = 0;
const send = (res, code, body, extra = {}) => { res.writeHead(code, { "content-type": "application/json", ...extra }); res.end(typeof body === "string" ? body : JSON.stringify(body)); };
const ok = (res, data) => send(res, 200, { timestamp: "2026-01-01T00:00:00.000Z", requestId: "r-1", data });
const fail = (res, path, statusCode, code, extra = {}) =>
  send(res, statusCode, { timestamp: "2026-01-01T00:00:00.000Z", requestId: "r-1", correlationId: "c-1", path,
    error: { statusCode, message: { code, message: "STUB-ERROR-TEXT" } } }, extra);
const common = (req, res, mode, okFn) => {
  switch (mode) {
    case "hold": return;
    case "500": return fail(res, req.url, 500, "internal_error");
    case "404": return fail(res, req.url, 404, "not_found");
    case "run_not_found": return send(res, 404, { timestamp: "2026-01-01T00:00:00.000Z", requestId: "r-1", correlationId: "c-1", path: req.url, error: { statusCode: 404, message: { code: "run_not_found", message: "Session not found." } } });
    case "405": return fail(res, req.url, 405, "method_not_allowed");
    case "429": return fail(res, req.url, 429, "rate_limited", { "retry-after": "30" });
    case "redirect": return send(res, 302, "", { location: `http://127.0.0.1:${server.address().port}/redirect-target` });
    case "notjson": return send(res, 200, "<html>not json</html>");
    case "malformed": case "garbage": return send(res, 200, "{\"data\": {\"status\": ");
    case "killmid": res.writeHead(200, { "content-type": "application/json", "content-length": "1000" }); res.write("{\"data\":{\"id\":\"r"); setTimeout(() => res.socket.destroy(), 20); return;
    default: return okFn();
  }
};
const server = createServer((req, res) => {
  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    appendFileSync(`${dir}/requests.log`, JSON.stringify({ method: req.method, path: req.url, auth: !!req.headers.authorization, ctype: req.headers["content-type"] ?? null, body: raw }) + "\n");
    const path = req.url.split("?")[0];
    if (path === "/redirect-target") return ok(res, { id: "stub-req-1", expiresAt: new Date(Date.now() + 100000).toISOString(), answerable: true });
    if (req.method === "POST" && path === "/api/live/requests") {
      const m = read("open", "ok");
      return common(req, res, m, () => ok(res, { id: "stub-req-1", expiresAt: read("expires-at", "") || new Date(Date.now() + Number(read("expires-in", "100")) * 1000).toISOString(), answerable: m !== "unanswerable" }));
    }
    const w = path.match(/^\/api\/live\/requests\/([^/]+)\/(wait|ack|cancel)$/);
    if (!w) return fail(res, req.url, 404, "not_found");
    if (w[2] === "wait" && req.method === "GET") {
      const list = read("wait", "pending").split(/\s+/); const m = list[Math.min(waits++, list.length - 1)];
      return common(req, res, m, () => {
        const done = (status, extra = {}) => ok(res, { status, ...extra });
        switch (m) {
          case "pending": return done("pending");
          case "slow": return setTimeout(() => done("pending"), 1500);
          case "allow": return done("answered", { decision: { behavior: "allow" } });
          case "deny": return done("answered", { decision: { behavior: "deny", message: "no" } });
          case "question": return done("answered", { decision: { answers: [{ q: 0, picks: [0] }] } });
          case "decision": return done("answered", { decision: JSON.parse(read("decision", "null")) });
          case "nodecision": return done("answered");
          case "rawdata": return ok(res, JSON.parse(read("wait-data", "{}")));   // ALY-269.5: the raw `data` of the wait answer, from the control file wait-data
          case "terminal": return done("terminal", { reason: "cmd_end" });
          case "expired": return done("expired", { reason: "expired" });
          case "no_audience": return done("expired", { reason: "no_audience" });
          default: return done("something_else", { reason: "weird" });
        }
      });
    }
    const m = read(w[2], "ok");
    if (m === "ok") return ok(res, { id: w[1], state: w[2] === "ack" ? "delivered" : "terminal" });
    return common(req, res, m, () => {});
  });
});
server.on("connection", (s) => { socks.add(s); s.on("close", () => socks.delete(s)); });
const bye = () => { for (const s of socks) s.destroy(); process.exit(0); };
process.on("SIGTERM", bye); process.on("SIGINT", bye);
server.listen(0, "127.0.0.1", () => writeFileSync(`${dir}/port`, String(server.address().port)));
EOF
)
exec "$NODE" --input-type=module -e "$JS" "$DIR"
