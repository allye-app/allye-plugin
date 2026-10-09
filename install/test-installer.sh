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
unset XDG_CONFIG_HOME CODEX_HOME PI_CODING_AGENT_DIR  # the host's values must not leak in
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

# codex goes through as experimental (profile 1.1.0)
rm -rf "$HOME/.codex/skills/team-standards"
run install codex team-standards || { cat "$TMP/out"; fail "codex install"; }
pass "codex installs with allowExperimental"
# opencode is now allowed by the 1.1.0 profile and lands in the XDG allye-skills dir
run install opencode team-standards || { cat "$TMP/out"; fail "opencode install"; }
[ -f "$HOME/.config/opencode/allye-skills/team-standards/SKILL.md" ] && [ ! -e "$HOME/.config/opencode/skills" ] || fail "opencode dir"
pass "opencode installs into opencode/allye-skills"

# the 1.0.0 profile still blocks opencode (frozen), through an ADAPTERS_FILE override
jq '.contractVersion = "1.0.0"' "$ROOT/install/adapters.json" > "$TMP/adapters-100.json"
H100="$TMP/home100"; mkdir -p "$H100"
HOME="$H100" ADAPTERS_FILE="$TMP/adapters-100.json" run install opencode team-standards && fail "opencode must be blocked on 1.0.0"
grep -q 'RUNTIME_INCOMPATIBLE' "$TMP/out" && [ ! -e "$H100/.config/opencode/allye-skills/team-standards" ] || fail "opencode 1.0.0 block message"
HOME="$H100" ADAPTERS_FILE="$TMP/adapters-100.json" run install claude team-standards || { cat "$TMP/out"; fail "claude on 1.0.0"; }
jq '.contractVersion = "9.9.9"' "$ROOT/install/adapters.json" > "$TMP/adapters-999.json"
HOME="$H100" ADAPTERS_FILE="$TMP/adapters-999.json" run install pi team-standards && fail "unknown version must be blocked"
grep -q 'RUNTIME_INCOMPATIBLE' "$TMP/out" || fail "unknown version message"
pass "API compatibility gate is surfaced (1.0.0 and unknown versions stay blocked)"

# ---- 1.1.0 contract, asserted on the logged request bodies for all 5 adapters ----
reqlog() { cat "$TMP/requests.log" 2>/dev/null || true; }
dist_bodies() { reqlog | jq -c 'select(.method == "POST" and (.path | test("/distributions/(request|update)$"))) | .body'; }
complete_bodies() { reqlog | jq -c 'select(.method == "POST" and (.path | test("/complete$"))) | .body'; }
printf 1 > "$TMP/release"; mode normal
H2="$TMP/home2"; mkdir -p "$H2/.claude" "$H2/.codex" "$H2/.config/opencode" "$H2/.pi/agent" "$H2/.omp/agent"
check_adapter() {  # id apiRuntime allowExperimental dir
  local id="$1" api="$2" exp="$3" dir="$4"
  : > "$TMP/requests.log"
  HOME="$H2" run install "$id" team-standards || { cat "$TMP/out"; fail "$id install"; }
  [ -f "$dir/team-standards/SKILL.md" ] || fail "$id installed into $dir"
  [ "$(dist_bodies | wc -l)" -eq 1 ] || fail "$id sends one request"
  dist_bodies | jq -e --arg rt "$api" --argjson exp "$exp" '
    .runtime == $rt and .runtimeVersion == "1.1.0" and .allowExperimental == $exp
    and (.target | test("^[a-z0-9:_-]{1,200}$")) and (.idempotencyKey | length <= 218)
    and (has("requiredCapabilities") | not) and (has("inputFormat") | not) and (has("outputFormat") | not)
    and (has("reinstall") | not)' >/dev/null || fail "$id request body"
  [ "$(complete_bodies | wc -l)" -eq 1 ] || fail "$id completes once"
  complete_bodies | jq -e '.installKind == "directory" and (has("piPackage") | not)' >/dev/null || fail "$id complete body"
  pass "$id: 1.1.0 request and directory completion"
}
check_adapter claude claude false "$H2/.claude/skills"
check_adapter codex codex true "$H2/.codex/skills"
check_adapter opencode opencode true "$H2/.config/opencode/allye-skills"
check_adapter pi pi false "$H2/.pi/agent/skills"
check_adapter omp pi false "$H2/.omp/agent/skills"
[ "$(HOME="$H2" bash -c 'ls "$HOME"/.config/opencode')" = allye-skills ] || fail "opencode only creates allye-skills"

# restart notice only when the first OpenCode install created the dir
H3="$TMP/home3"; mkdir -p "$H3"
HOME="$H3" run install opencode team-standards || fail "opencode first install"
grep -q 'restart OpenCode' "$TMP/out" || fail "restart notice on first install"
H3p="$TMP/home3p"; mkdir -p "$H3p/.config/opencode/allye-skills"; chmod 755 "$H3p/.config/opencode/allye-skills"
HOME="$H3p" run install opencode team-standards || { cat "$TMP/out"; fail "opencode into an existing dir"; }
[ -f "$H3p/.config/opencode/allye-skills/team-standards/SKILL.md" ] || fail "installed into the existing dir"
! grep -q 'restart OpenCode' "$TMP/out" || fail "no restart notice when the dir already existed"
HOME="$H3" run install claude team-standards || fail "claude install"
! grep -q 'restart OpenCode' "$TMP/out" || fail "no restart notice for other adapters"
pass "OpenCode restart notice"

# the allye-skills dir is created 0755 whatever the umask; a writable existing dir gets a notice
H3b="$TMP/home3b"; mkdir -p "$H3b"
( umask 002; HOME="$H3b" run install opencode team-standards ) || { cat "$TMP/out"; fail "opencode under umask 002"; }
[ "$(stat -c %a "$H3b/.config/opencode/allye-skills")" = 755 ] || fail "allye-skills created 0755 under umask 002"
! grep -q 'group- or world-writable' "$TMP/out" || fail "no writable notice for 0755"
H3c="$TMP/home3c"; mkdir -p "$H3c/.config/opencode/allye-skills"; chmod 775 "$H3c/.config/opencode/allye-skills"
: > "$TMP/requests.log"
HOME="$H3c" run install opencode team-standards && fail "0775 dir must be refused"
grep -q 'chmod go-w' "$TMP/out" && grep -q 'ignores' "$TMP/out" || fail "0775 dir message"
! reqlog | grep -q '/distributions/' && [ -z "$(ls -A "$H3c/.config/opencode/allye-skills")" ] || fail "0775 dir: no POST, nothing created"
H3d="$TMP/home3d"; mkdir -p "$H3d/.config/opencode" "$TMP/real-skills"
ln -s "$TMP/real-skills" "$H3d/.config/opencode/allye-skills"
: > "$TMP/requests.log"
HOME="$H3d" run install opencode team-standards && fail "symlinked dir must be refused"
grep -q 'symlink' "$TMP/out" || fail "symlink message"
! reqlog | grep -q '/distributions/' && [ -z "$(ls -A "$TMP/real-skills")" ] || fail "symlink: no POST, nothing created"
pass "OpenCode dir is created 0755; symlinked or writable dirs are refused"

# XDG_CONFIG_HOME (trailing slash stripped, empty means unset)
H4="$TMP/home4"; mkdir -p "$H4"
XDG_CONFIG_HOME="$TMP/xdg/" HOME="$H4" run install opencode team-standards || { cat "$TMP/out"; fail "opencode XDG"; }
[ -f "$TMP/xdg/opencode/allye-skills/team-standards/SKILL.md" ] && ! grep -q '//' <<<"$(jq -r .target "$TMP/xdg/opencode/allye-skills/team-standards/.allye-artifact.json")" || fail "XDG dir"
XDG_CONFIG_HOME="" HOME="$H4" run install opencode team-standards || { cat "$TMP/out"; fail "opencode empty XDG"; }
[ -f "$H4/.config/opencode/allye-skills/team-standards/SKILL.md" ] || fail "empty XDG falls back to ~/.config"
H4b="$TMP/home4b"; mkdir -p "$H4b"
XDG_CONFIG_HOME="rel/xdg" HOME="$H4b" run install opencode team-standards || { cat "$TMP/out"; fail "opencode relative XDG"; }
[ -f "$H4b/.config/opencode/allye-skills/team-standards/SKILL.md" ] && [ ! -e rel ] || fail "relative XDG is treated as unset"
pass "XDG_CONFIG_HOME is honoured (empty or relative means unset)"

# CODEX_HOME / PI_CODING_AGENT_DIR: set, trailing slash, empty, relative
H5="$TMP/home5"; mkdir -p "$H5"
CODEX_HOME="$TMP/ch/" HOME="$H5" run install codex team-standards || { cat "$TMP/out"; fail "CODEX_HOME install"; }
[ -f "$TMP/ch/skills/team-standards/SKILL.md" ] && [ ! -e "$H5/.codex" ] || fail "CODEX_HOME dir"
CODEX_HOME="" HOME="$H5" run install codex team-standards || fail "empty CODEX_HOME"
[ -f "$H5/.codex/skills/team-standards/SKILL.md" ] || fail "empty CODEX_HOME means ~/.codex"
PI_CODING_AGENT_DIR="$TMP/pidir/" HOME="$H5" run install pi team-standards || { cat "$TMP/out"; fail "PI dir install"; }
[ -f "$TMP/pidir/skills/team-standards/SKILL.md" ] || fail "PI_CODING_AGENT_DIR dir"
PI_CODING_AGENT_DIR="$TMP/pidir/" HOME="$H5" run install omp team-standards || fail "omp ignores PI_CODING_AGENT_DIR"
[ -f "$H5/.omp/agent/skills/team-standards/SKILL.md" ] || fail "omp dir"
for var in CODEX_HOME:codex PI_CODING_AGENT_DIR:pi; do
  : > "$TMP/requests.log"
  env "${var%%:*}=relative/dir" HOME="$H5" "$ROOT/install.sh" install "${var##*:}" team-standards >"$TMP/out" 2>&1 && fail "relative ${var%%:*} must fail"
  grep -q "${var%%:*}" "$TMP/out" || fail "relative ${var%%:*} message"
  ! reqlog | grep -q '/distributions/' || fail "relative ${var%%:*}: no POST /distributions/*"
  env "${var%%:*}=relative/dir" HOME="$H5" "$ROOT/install.sh" install claude team-standards >"$TMP/out" 2>&1 || { cat "$TMP/out"; fail "other adapters unaffected by relative ${var%%:*}"; }
done
pass "CODEX_HOME and PI_CODING_AGENT_DIR are normalised, relative values are refused"

# pure path rules, including "/" and detection
lib() { ( SCRIPT_DIR="$ROOT"; print_error() { echo "$*" >&2; }; print_warning() { echo "$*" >&2; }; . "$ROOT/install/lib.sh"; [ -z "${LIB_PATH+x}" ] || PATH="$LIB_PATH"; "$@" ); }
[ "$(CODEX_HOME=/ lib runtime_skills_dir codex)" = "/skills" ] || fail 'CODEX_HOME "/" stays "/"'
[ "$(CODEX_HOME=// lib runtime_skills_dir codex)" = "/skills" ] || fail 'CODEX_HOME "//" is "/"'
[ "$(CODEX_HOME=/a/b/ lib runtime_skills_dir codex)" = "/a/b/skills" ] || fail "trailing slash stripped"
[ "$(PI_CODING_AGENT_DIR=/ lib runtime_skills_dir pi)" = "/skills" ] || fail 'PI dir "/"'
[ "$(PI_CODING_AGENT_DIR=/p/ HOME=/h lib runtime_skills_dir pi)" = "/p/skills" ] || fail "PI dir trailing slash"
[ "$(CODEX_HOME= HOME=/h lib runtime_skills_dir codex)" = "/h/.codex/skills" ] || fail "empty CODEX_HOME"
[ "$(XDG_CONFIG_HOME=/x/ HOME=/h lib runtime_skills_dir opencode)" = "/x/opencode/allye-skills" ] || fail "XDG dir"
[ "$(XDG_CONFIG_HOME=rel HOME=/h lib runtime_skills_dir opencode)" = "/h/.config/opencode/allye-skills" ] || fail "relative XDG"
[ "$(XDG_CONFIG_HOME=/ HOME=/h lib runtime_skills_dir opencode)" = "/opencode/allye-skills" ] || fail 'XDG "/"'
[ "$(XDG_CONFIG_HOME= HOME=/h lib runtime_skills_dir opencode)" = "/h/.config/opencode/allye-skills" ] || fail "empty XDG"
H6="$TMP/home6"; mkdir -p "$H6/ch" "$H6/xdg/opencode" "$H6/pidir" "$H6/none" "$TMP/nobin"
ln -s "$(command -v jq)" "$TMP/nobin/jq"  # a PATH without codex/opencode/pi/omp
det() { LIB_PATH="$TMP/nobin" HOME="$H6/none" lib runtime_detected "$@"; }
CODEX_HOME="$H6/ch" det codex || fail "detection checks CODEX_HOME"
CODEX_HOME="" det codex && fail "no CODEX_HOME and no ~/.codex: not detected"
CODEX_HOME="$H6/missing" det codex && fail "CODEX_HOME that does not exist: not detected"
XDG_CONFIG_HOME="$H6/xdg" det opencode || fail "detection checks XDG"
XDG_CONFIG_HOME="" det opencode && fail "no XDG and no ~/.config/opencode: not detected"
PI_CODING_AGENT_DIR="$H6/pidir" det pi || fail "detection checks PI_CODING_AGENT_DIR"
PI_CODING_AGENT_DIR="" det pi && fail "no PI_CODING_AGENT_DIR and no ~/.pi/agent: not detected"
pass "path normalisation and detection"

# status with relative home overrides: rc 0, invalid ones flagged, the rest still listed
CODEX_HOME=rel PI_CODING_AGENT_DIR=rel HOME="$H5" run status || fail "status with relative overrides exits 0"
[ "$(grep -c 'invalid home override' "$TMP/out")" -eq 2 ] || fail "status flags codex and pi"
grep -q 'Codex.*invalid home override' "$TMP/out" && grep -q 'Pi .*invalid home override' "$TMP/out" || fail "status names the runtimes"
grep -q 'Claude Code' "$TMP/out" && grep -q 'OpenCode' "$TMP/out" && grep -q 'OMP' "$TMP/out" || fail "other runtimes still listed"
pass "status survives relative home overrides"

# AC-21: an owned-intact older release is updated with the sidecar's base, no reinstall
H7="$TMP/home7"; mkdir -p "$H7"
printf 1 > "$TMP/release"
HOME="$H7" run install claude team-standards || fail "AC-21 first install"
base_hash=$(jq -r .canonical_hash "$H7/.claude/skills/team-standards/.allye-artifact.json")
printf 2 > "$TMP/release"; : > "$TMP/requests.log"
HOME="$H7" run install claude team-standards || { cat "$TMP/out"; fail "AC-21 update"; }
reqlog | jq -e 'select(.path | test("/distributions/update$")) | .body | .baseReleaseId == "release-1" and .observedHash == "'"$base_hash"'" and .runtimeVersion == "1.1.0" and (has("reinstall") | not)
  and (.target | test("^[a-z0-9:_-]{1,200}$")) and (.idempotencyKey | length <= 218)
  and (has("requiredCapabilities") | not) and (has("inputFormat") | not) and (has("outputFormat") | not)' >/dev/null || fail "update body"
! reqlog | jq -e 'select(.path | test("/distributions/request$"))' >/dev/null || fail "no request on update"
complete_bodies | jq -e '.installKind == "directory"' >/dev/null || fail "update completes"
pass "update carries baseReleaseId and observedHash from the sidecar"

# the fake API enforces the 1.1.0 rules itself (400 naming the field)
fake() {  # body -> status code; path request
  curl -s -o "$TMP/fake.out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H 'X-Allye-Channel: plugin' \
    -H 'Authorization: Bearer pat_test' --data "$1" "$ALLYE_API_URL/api/skills/11111111-2222-3333-4444-555555555555/distributions/${2:-request}"
}
base='{"skillId":"s","releaseId":"release-2","runtime":"claude","runtimeVersion":"1.1.0","allowExperimental":false,"target":"claude:claude:abc","idempotencyKey":"k1"}'
long=$(printf 'a%.0s' $(seq 1 219))
[ "$(fake "$(jq -c --arg k "$long" '.idempotencyKey = $k' <<<"$base")")" = 400 ] && grep -q idempotencyKey "$TMP/fake.out" || fail "long key -> 400"
[ "$(fake "$(jq -c '.target = "Bad Target"' <<<"$base")")" = 400 ] && grep -q '"target' "$TMP/fake.out" || fail "bad target -> 400"
[ "$(fake "$(jq -c '.runtimeVersion = "1.0.0" | .idempotencyKey = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:k"' <<<"$base")")" = 400 ] || fail "1.0.0 other-user key -> 400"
[ "$(fake "$(jq -c '.reinstall = {observedLocalState:"missing"}' <<<"$base")" update)" = 400 ] || fail "reinstall on update -> 400"
[ "$(fake "$(jq -c '.reinstall = {observedLocalState:"missing"} | .baseReleaseId = "release-1"' <<<"$base")")" = 400 ] || fail "reinstall with base -> 400"
[ "$(fake "$(jq -c '.reinstall = {observedLocalState:"modified"}' <<<"$base")")" = 400 ] || fail "modified needs hash"
[ "$(fake "$(jq -c --arg h "$(printf 'a%.0s' $(seq 1 64))" '.reinstall = {observedLocalState:"missing", observedLocalHash:$h}' <<<"$base")")" = 400 ] || fail "missing rejects hash"
[ "$(fake "$(jq -c '.reinstall = {observedLocalState:"modified", observedLocalHash:"ABC"}' <<<"$base")")" = 400 ] || fail "hash must be 64 lowercase hex"
for f in requiredCapabilities inputFormat outputFormat; do
  [ "$(fake "$(jq -c --arg f "$f" '.[$f] = "x"' <<<"$base")")" = 400 ] && grep -q "$f" "$TMP/fake.out" || fail "$f -> 400 naming the field"
done
[ "$(fake "$(jq -c '.runtime = "opencode" | .allowExperimental = false' <<<"$base")")" = 409 ] || fail "opencode needs allowExperimental"
[ "$(fake "$(jq -c '.runtime = "cursor"' <<<"$base")")" = 409 ] || fail "unknown runtime blocked"
pass "fake API enforces the 1.1.0 and reinstall validation rules"

# unknown runtime
run install cursor team-standards && fail "unknown runtime"
grep -q "Unknown runtime 'cursor'" "$TMP/out" || fail "unknown runtime message"
pass "removed runtimes are rejected"

# no staging dirs, locks or rollback handles are left behind
leftovers=$(find "$HOME" -name '.allye-stage.*' -o -name '*.allye.lock' -o -name '*.allye.previous.*')
[ -z "$leftovers" ] || fail "leftovers: $leftovers"
pass "no staging, lock or rollback leftovers"

echo "installer: ok"
