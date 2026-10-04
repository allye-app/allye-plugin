#!/usr/bin/env bash
# End-to-end test of install.sh against a loopback fake of the skills API.
# Offline: no network beyond 127.0.0.1, HOME is a temp dir.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/allye-installer.XXXXXX")"
trap 'kill "${SERVER_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT
pass() { printf '  PASS: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; exit 1; }

node "$ROOT/install/test/fake-api.mjs" "$TMP" & SERVER_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
[ -s "$TMP/port" ] || fail "fake API did not start"

export HOME="$TMP/home" ALLYE_PAT=pat_test ALLYE_API_URL="http://127.0.0.1:$(cat "$TMP/port")"
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode"
DEST="$HOME/.claude/skills/team-standards"
run() { "$ROOT/install.sh" "$@" >"$TMP/out" 2>&1; }
calls() { cat "$TMP/calls" 2>/dev/null || true; }
reset_calls() { : > "$TMP/calls"; }
mode() { printf '%s' "$1" > "$TMP/mode"; }

# list
run list || fail "list exits 0"
grep -q 'team-standards' "$TMP/out" && grep -q '1.1.0' "$TMP/out" || fail "list shows slug and version"
pass "list shows the approved skills"

# bad PAT is rejected with an actionable message
ALLYE_PAT=pat_wrong run list && fail "wrong PAT must fail"
grep -q 'HTTP 401' "$TMP/out" && grep -q 'Settings → API' "$TMP/out" || fail "401 message"
pass "rejected PAT is reported"

# non-loopback http is refused before any request
reset_calls
ALLYE_API_URL=http://example.test run list && fail "http non-loopback must fail"
[ -z "$(calls)" ] || fail "no request for refused URL"
pass "non-loopback http is refused"

# tampered artifact: refused before the ledger is touched, nothing written
mode bad-artifact; reset_calls
run install claude team-standards && fail "tampered artifact must fail"
grep -q 'integrity check' "$TMP/out" || fail "integrity message"
! calls | grep -q distributions || fail "no distribution for tampered artifact"
[ ! -e "$DEST" ] || fail "nothing written for tampered artifact"
pass "tampered artifact is refused before the ledger"

# forged execution token: refused, failure reported, nothing written
mode bad-token; reset_calls
run install claude team-standards && fail "forged token must fail"
grep -q 'signature is invalid' "$TMP/out" || fail "token message"
calls | grep -q 'fail code=TOKEN_INVALID' || fail "failure reported"
! calls | grep -q preflight || fail "no preflight with forged token"
[ ! -e "$DEST" ] || fail "nothing written for forged token"
pass "forged execution token is refused and reported"

# happy path
mode normal; reset_calls
run install claude team-standards || { cat "$TMP/out"; fail "install exits 0"; }
[ "$(calls | grep -c POST)" -eq 4 ] || fail "request, execution-context, preflight, complete"
calls | grep -q 'POST /api/skills/:id/distributions/request' && calls | grep -q 'distributions/op-[0-9]*/complete' || fail "flow order"
grep -q 'Standards 1' "$DEST/SKILL.md" && [ -f "$DEST/references/style.md" ] || fail "files written"
jq -e '.release_id == "release-1" and .runtime == "claude" and (.target | startswith("claude:claude:"))' "$DEST/.allye-artifact.json" >/dev/null || fail "sidecar"
pass "install verifies, publishes and records evidence"

# re-run is a local no-op
reset_calls
run install claude team-standards || fail "re-run exits 0"
grep -q 'already installed' "$TMP/out" && ! calls | grep -q POST || fail "re-run makes no distribution"
pass "re-run is idempotent"

# status
run status || fail "status exits 0"
grep -q 'team-standards.*1.1.0.*intact' "$TMP/out" || fail "status shows intact"
pass "status reports installed skills"

# upgrade uses /update with the installed base, completion rejection restores the old tree
printf 2 > "$TMP/release"; mode reject-complete; reset_calls
run install claude team-standards && fail "rejected completion must fail"
calls | grep -q 'distributions/update base=release-1' || fail "update with base release"
calls | grep -q 'fail code=COMPLETION_REJECTED' || fail "failure reported after rejection"
grep -q 'Standards 1' "$DEST/SKILL.md" && [ "$(jq -r .release_id "$DEST/.allye-artifact.json")" = release-1 ] || fail "previous tree restored"
pass "rejected completion restores the previous release"

mode normal; reset_calls
run install claude team-standards || fail "upgrade exits 0"
grep -q 'Standards 2' "$DEST/SKILL.md" && [ "$(jq -r .release_id "$DEST/.allye-artifact.json")" = release-2 ] || fail "upgraded"
pass "upgrade installs the new release"

# local edits are preserved
printf 'my edit\n' >> "$DEST/SKILL.md"; printf 3 > "$TMP/release"; reset_calls
run install claude team-standards && fail "modified tree must not be replaced"
grep -q 'edited locally' "$TMP/out" && grep -q 'my edit' "$DEST/SKILL.md" || fail "local edit kept"
! calls | grep -q distributions || fail "no distribution for modified tree"
pass "local edits are never overwritten"

# unmanaged directory is preserved
mkdir -p "$HOME/.codex/skills/team-standards"; printf 'mine\n' > "$HOME/.codex/skills/team-standards/SKILL.md"
run install codex team-standards && fail "unmanaged dir must be kept"
grep -q 'not installed by Allye' "$TMP/out" && grep -q mine "$HOME/.codex/skills/team-standards/SKILL.md" || fail "unmanaged kept"
pass "unmanaged directories are never overwritten"

# codex goes through as experimental, opencode is blocked by the API gate
rm -rf "$HOME/.codex/skills/team-standards"
run install codex team-standards || { cat "$TMP/out"; fail "codex install"; }
pass "codex installs with allowExperimental"
run install opencode team-standards && fail "opencode must be blocked"
grep -q 'RUNTIME_INCOMPATIBLE' "$TMP/out" && [ ! -e "$HOME/.config/opencode/skills/team-standards" ] || fail "opencode blocked message"
pass "API compatibility gate is surfaced"

# unknown runtime
run install cursor team-standards && fail "unknown runtime"
grep -q "Unknown runtime 'cursor'" "$TMP/out" || fail "unknown runtime message"
pass "removed runtimes are rejected"

# no staging dirs, locks or rollback handles are left behind
leftovers=$(find "$HOME" -name '.allye-stage.*' -o -name '*.allye.lock' -o -name '*.allye.previous.*')
[ -z "$leftovers" ] || fail "leftovers: $leftovers"
pass "no staging, lock or rollback leftovers"

echo "installer: ok"
