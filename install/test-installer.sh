#!/usr/bin/env bash
# End-to-end test of install.sh against a loopback fake of the skills API.
# Offline: no network beyond 127.0.0.1, HOME is a temp dir.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/allye-installer.XXXXXX")"
trap 'kill "${SERVER_PID:-}" 2>/dev/null || true; chmod -R u+rwX "$TMP" "${SHM:-}" 2>/dev/null || true; rm -rf "$TMP" "${SHM:-}"' EXIT
pass() { printf '  PASS: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; exit 1; }

node "$ROOT/install/test/fake-api.mjs" "$TMP" & SERVER_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
[ -s "$TMP/port" ] || fail "fake API did not start"

export HOME="$TMP/home" ALLYE_PAT=pat_test ALLYE_API_URL="http://127.0.0.1:$(cat "$TMP/port")"
unset XDG_CONFIG_HOME CODEX_HOME PI_CODING_AGENT_DIR ALLYE_TEAM_ID ALLYE_MV_T _ALLYE_MV_T  # the host's values must not leak in
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode"
DEST="$HOME/.claude/skills/team-standards"
run() { "$ROOT/install.sh" "$@" >"$TMP/out" 2>&1; }
calls() { cat "$TMP/calls" 2>/dev/null || true; }
reset_calls() { : > "$TMP/calls"; }
reqlog() { cat "$TMP/requests.log" 2>/dev/null || true; }
dist_posts() { reqlog | jq -c 'select(.method == "POST" and (.path | test("/distributions/")))' | wc -l | tr -d ' '; }
SHIMS="$TMP/shims"; mkdir -p "$SHIMS/cp" "$SHIMS/mv-noT" "$SHIMS/mv-fail" "$SHIMS/mv-restore" "$SHIMS/curl"
REAL_CP=$(command -v cp); REAL_MV=$(command -v mv); REAL_CURL=$(command -v curl)
cat > "$SHIMS/cp/cp" <<SH
#!/bin/bash
echo "\$*" >> "$TMP/cp.log"
"$REAL_CP" "\$@"; rc=\$?
for a in "\$@"; do last="\$a"; done
[ -z "\${CORRUPT:-}" ] || printf junk >> "\$last/SKILL.md"
exit \$rc
SH
cat > "$SHIMS/mv-noT/mv" <<SH
#!/bin/bash
echo "\$*" >> "$TMP/mv.log"
if [ "\$1" = -T ]; then echo "mv: illegal option -- T" >&2; exit 64; fi
exec "$REAL_MV" "\$@"
SH
cat > "$SHIMS/mv-fail/mv" <<SH
#!/bin/bash
echo "\$*" >> "$TMP/mv.log"
case "\$*" in *.allye-stage.*) if [ "\$1" = -T ]; then echo "mv: cannot move: Input/output error" >&2; exit 1; fi ;; esac
exec "$REAL_MV" "\$@"
SH
cat > "$SHIMS/mv-restore/mv" <<SH
#!/bin/bash
# fails every move of a hidden .allye-backup.* copy back to a skill path (the restore)
args=("\$@"); n=\${#args[@]}
case "\${args[\$((n-2))]}" in */.allye-backup.*) case "\${args[\$((n-1))]}" in */.allye/backups/*) ;; *) echo "mv: cannot move: Input/output error" >&2; exit 1 ;; esac ;; esac
exec "$REAL_MV" "\$@"
SH
cat > "$SHIMS/curl/curl" <<SH
#!/bin/bash
echo "\$*" >> "$TMP/curl.log"
exec "$REAL_CURL" "\$@"
SH
chmod +x "$SHIMS"/*/*
clean_dir() { [ -z "$(find "$1" -maxdepth 1 \( -name '.allye-stage.*' -o -name '*.allye.lock' -o -name '*.allye.previous.*' -o -name '.allye-backup.*' \) 2>/dev/null)" ]; }
backup_dir() { ls -d "$1"/.allye/backups/"$2"/team-standards.allye.backup.* 2>/dev/null | head -1; }
tree_of() { node "$ROOT/install/skill-tool.mjs" tree-hash "$1"; }
btree_of() { node "$ROOT/install/skill-tool.mjs" tree-hash "$1" --backup; }
fresh_home() { local h="$TMP/h-$1"; mkdir -p "$h"; printf '%s' "$h"; }
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

# AC-06: a locally modified copy is never replaced without --reinstall
printf 'my edit\n' >> "$DEST/SKILL.md"; printf 3 > "$TMP/release"; cp -a "$DEST" "$TMP/dest-snapshot"; : > "$TMP/requests.log"; reset_calls
run install claude team-standards && fail "modified tree must not be replaced"
grep -q -- '--reinstall' "$TMP/out" && grep -q '~/.allye/backups' "$TMP/out" || fail "refusal names --reinstall and ~/.allye/backups"
! grep -q 'edited locally' "$TMP/out" || fail "old wording is gone"
! reqlog | jq -e 'select(.path | test("/distributions/"))' >/dev/null || fail "no POST /distributions/* for modified tree"
diff -r "$TMP/dest-snapshot" "$DEST" >/dev/null || fail "modified folder is byte-identical after the refusal"
grep -q 'my edit' "$DEST/SKILL.md" || fail "local edit kept"
pass "AC-06: local edits are never overwritten without --reinstall"

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
    and .reinstall == {observedLocalState: "missing"}' >/dev/null || fail "$id request body"
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

# AC-05: a missing folder always sends reinstall {missing} with a fresh idempotency key
printf 1 > "$TMP/release"; mode normal
H8=$(fresh_home ac05); D8="$H8/.claude/skills/team-standards"
: > "$TMP/requests.log"
HOME="$H8" run install claude team-standards || { cat "$TMP/out"; fail "AC-05 first install"; }
! grep -q 'reinstall' "$TMP/out" || fail "no reinstall notice for an ordinary row"
key1=$(dist_bodies | jq -r '.idempotencyKey')
dist_bodies | jq -e '.reinstall == {observedLocalState: "missing"}' >/dev/null || fail "first install sends reinstall missing"
rm -rf "$D8"; : > "$TMP/requests.log"
HOME="$H8" run install claude team-standards || { cat "$TMP/out"; fail "AC-05 reinstall after delete"; }
key2=$(dist_bodies | jq -r '.idempotencyKey')
dist_bodies | jq -e '.reinstall == {observedLocalState: "missing"} and (.reinstall | has("observedLocalHash") | not)' >/dev/null || fail "deleted folder sends reinstall missing"
[ -n "$key1" ] && [ "$key1" != "$key2" ] || fail "idempotency key differs between runs"
grep -qi 'reinstall' "$TMP/out" || fail "reinstall notice on origin api:reinstall"
[ -f "$D8/SKILL.md" ] && [ "$(complete_bodies | wc -l | tr -d ' ')" -eq 1 ] || fail "reinstall completes"
pass "AC-05: missing folder sends reinstall {missing}, new key, notice on api:reinstall"

# AC-09: --reinstall never touches foreign or unmanaged folders; no-op on an owned-intact copy
H9=$(fresh_home ac09); D9="$H9/.claude/skills/team-standards"
mkdir -p "$D9"; printf 'mine\n' > "$D9/SKILL.md"; cp -a "$D9" "$TMP/ac09-snap"; : > "$TMP/requests.log"
HOME="$H9" run install claude team-standards --reinstall && fail "unmanaged with --reinstall must be refused"
grep -q "$D9" "$TMP/out" && [ "$(dist_posts)" -eq 0 ] && diff -r "$TMP/ac09-snap" "$D9" >/dev/null || fail "unmanaged untouched, path named, no POST"
rm -rf "$D9" "$TMP/ac09-snap"; cp -a "$D8" "$D9"; jq '.skill_id = "99999999-0000-0000-0000-000000000000"' "$D9/.allye-artifact.json" > "$TMP/sc" && cp "$TMP/sc" "$D9/.allye-artifact.json"
cp -a "$D9" "$TMP/ac09-snap"; : > "$TMP/requests.log"
HOME="$H9" run install claude team-standards --reinstall && fail "foreign with --reinstall must be refused"
grep -q "$D9" "$TMP/out" && [ "$(dist_posts)" -eq 0 ] && diff -r "$TMP/ac09-snap" "$D9" >/dev/null || fail "foreign untouched, path named, no POST"
: > "$TMP/requests.log"
HOME="$H8" run install claude team-standards --reinstall || { cat "$TMP/out"; fail "--reinstall on owned-intact exits 0"; }
grep -q 'already installed' "$TMP/out" && [ "$(dist_posts)" -eq 0 ] || fail "owned-intact same release: already installed, no POST"
pass "AC-09: --reinstall leaves foreign/unmanaged alone and is a no-op on an intact copy"

# AC-15: copies recorded for another target
H10=$(fresh_home ac15); mkdir -p "$H10/.claude/skills"; D10="$H10/.claude/skills/team-standards"
cp -a "$D8" "$D10"   # a copy with its sidecar, recorded for H8's skills dir
: > "$TMP/requests.log"
HOME="$H10" run install claude team-standards || { cat "$TMP/out"; fail "AC-15 intact other-target"; }
dist_bodies | jq -e '.reinstall == {observedLocalState: "missing"} and (has("baseReleaseId") | not)' >/dev/null || fail "intact other-target sends reinstall missing"
HT=$(HOME="$H10" bash -c '. /dev/null; cd "$0"; SCRIPT_DIR="$0"; print_error() { :; }; . install/lib.sh; runtime_target claude' "$ROOT")
[ "$(jq -r .target "$D10/.allye-artifact.json")" = "$HT" ] || fail "sidecar rewritten with the current target"
[ ! -e "$H10/.allye" ] && [ -z "$(ls -A "$H10/.claude/skills" | grep -v '^team-standards$')" ] || fail "no backup and no leftovers for an intact other-target copy"
grep -qi 'another' "$TMP/out" || fail "other-target notice"
pass "AC-15: intact other-target copy is replaced without backup and re-recorded"
rm -rf "$D10"; cp -a "$D8" "$D10"; printf 'edit\n' >> "$D10/SKILL.md"; cp -a "$D10" "$TMP/ac15-snap"; pre=$(tree_of "$D10"); : > "$TMP/requests.log"
HOME="$H10" run install claude team-standards && fail "edited other-target must be refused"
grep -q -- '--reinstall' "$TMP/out" && [ "$(dist_posts)" -eq 0 ] && diff -r "$TMP/ac15-snap" "$D10" >/dev/null || fail "edited other-target refused: names --reinstall, no POST, untouched"
: > "$TMP/requests.log"
HOME="$H10" run install claude team-standards --reinstall || { cat "$TMP/out"; fail "edited other-target + --reinstall exits 0"; }
dist_bodies | jq -e --arg h "$pre" '.reinstall == {observedLocalState: "modified", observedLocalHash: $h} and (has("baseReleaseId") | not) and (has("observedHash") | not)' >/dev/null || fail "edited other-target + --reinstall sends reinstall modified with the pre-run hash"
B=$(backup_dir "$H10" claude); [ -n "$B" ] && [ "$(btree_of "$B")" = "$pre" ] && grep -q edit "$B/SKILL.md" || fail "edited other-target is backed up"
[ "$(jq -r .target "$D10/.allye-artifact.json")" = "$HT" ] && clean_dir "$H10/.claude/skills" || fail "other-target replaced for the current target, no leftovers"
pass "AC-15: edited other-target needs --reinstall, then follows AC-07"

# AC-07: --reinstall on an owned-modified copy (newer release available)
H11=$(fresh_home ac07); D11="$H11/.claude/skills/team-standards"
HOME="$H11" run install claude team-standards || fail "AC-07 setup"
chmod 755 "$D11"; printf 'edit\n' >> "$D11/SKILL.md"; pre=$(tree_of "$D11"); : > "$TMP/requests.log"; : > "$TMP/cp.log"
printf 2 > "$TMP/release"
PATH="$SHIMS/cp:$PATH" HOME="$H11" run install claude team-standards --reinstall || { cat "$TMP/out"; fail "AC-07 exits 0"; }
printf 1 > "$TMP/release"
dist_bodies | jq -e --arg h "$pre" '.reinstall == {observedLocalState: "modified", observedLocalHash: $h} and (has("baseReleaseId") | not)' >/dev/null || fail "owned-modified + --reinstall sends reinstall modified"
! reqlog | jq -e 'select(.path | test("/distributions/update$"))' >/dev/null || fail "reinstall never rides on update"
grep -q 'Standards 2' "$D11/SKILL.md" && [ "$(jq -r .release_id "$D11/.allye-artifact.json")" = release-2 ] || fail "newer release installed"
B=$(backup_dir "$H11" claude)
[ -n "$B" ] && grep -q -F "$B" "$TMP/out" || fail "backup path printed"
[ "$(btree_of "$B")" = "$pre" ] && grep -q 'edit' "$B/SKILL.md" || fail "backup tree hash equals the pre-run hash"
[ -f "$B/.allye-artifact.backup.json" ] && [ ! -e "$B/.allye-artifact.json" ] || fail "backup sidecar renamed"
[ "$(stat -c %a "$H11/.allye")" = 700 ] && [ "$(stat -c %a "$H11/.allye/backups")" = 700 ] && [ "$(stat -c %a "$H11/.allye/backups/claude")" = 700 ] || fail "backup dirs are 0700"
[ "$(stat -c %a "$B")" = 700 ] || fail "the backup dir itself is 0700 even when the edited folder was 0755"
[ ! -s "$TMP/cp.log" ] || fail "a same-device backup is a move, never a copy"
clean_dir "$H11/.claude/skills" || fail "no stage, lock or hidden entries left"
HOME="$H11" run status || fail "status"
! grep -q 'backup' "$TMP/out" && [ "$(grep -c 'team-standards' "$TMP/out")" -eq 1 ] || fail "status does not list the backup"
pass "AC-07: reinstall backs up the edited copy outside discovery and installs the new release"

# backup name collision: .<pid> appended, existing backups untouched
H18=$(fresh_home collide); D18="$H18/.claude/skills/team-standards"
HOME="$H18" run install claude team-standards || fail "collision setup"
printf 'edit\n' >> "$D18/SKILL.md"; root="$H18/.allye/backups/claude"; mkdir -p "$root"
now=$(date +%s)
for off in $(seq -2 25); do d="$root/team-standards.allye.backup.$(date -u -d "@$((now + off))" +%Y%m%dT%H%M%SZ)"; mkdir -p "$d"; printf keep > "$d/marker"; done
HOME="$H18" run install claude team-standards --reinstall || { cat "$TMP/out"; fail "collision reinstall"; }
newb=$(find "$root" -maxdepth 1 -name 'team-standards.allye.backup.*Z.[0-9]*')
[ "$(grep -c . <<<"$newb")" -eq 1 ] && grep -q edit "$newb/SKILL.md" || fail "pid appended to the colliding backup name"
for d in "$root"/team-standards.allye.backup.*; do [ "$d" = "$newb" ] || { [ "$(ls -A "$d")" = marker ] && [ "$(cat "$d/marker")" = keep ] || fail "existing backup untouched: $d"; }; done
pass "backup name collisions get .<pid> and never overwrite"

# AC-08: rejected artifact, token or complete leaves the edited folder in place
ac08() {  # mode, expect fail POST (1|0)
  local h; h=$(fresh_home "ac08-$1"); local d="$h/.claude/skills/team-standards" before
  HOME="$h" run install claude team-standards || fail "AC-08 setup ($1)"
  printf 'edit\n' >> "$d/SKILL.md"; before=$(tree_of "$d"); cp -a "$d" "$TMP/ac08-snap"; reset_calls; mode "$1"
  HOME="$h" run install claude team-standards --reinstall && fail "AC-08 $1 must fail"
  mode normal
  [ "$(tree_of "$d")" = "$before" ] && diff -r "$TMP/ac08-snap" "$d" >/dev/null || fail "AC-08 $1: edited folder restored identically"
  clean_dir "$h/.claude/skills" && [ ! -e "$h/.allye/backups" ] || fail "AC-08 $1: no backup, stage, lock or hidden entries"
  if [ "$2" = 1 ]; then calls | grep -q 'distributions/op-[0-9]*/fail' || fail "AC-08 $1: POST fail"; else ! calls | grep -q '/fail' || fail "AC-08 $1: no row, no fail"; fi
  rm -rf "$TMP/ac08-snap"
}
ac08 bad-artifact 0; ac08 bad-token 1; ac08 reject-complete 1
pass "AC-08: rejected artifact, token and complete restore the edited folder"

# AC-17: the folder changes after the request (mutate-on-preflight)
H19=$(fresh_home ac17); D19="$H19/.claude/skills/team-standards"
HOME="$H19" run install claude team-standards || fail "AC-17 setup"
printf 'edit\n' >> "$D19/SKILL.md"; printf '%s' "$D19/SKILL.md" > "$TMP/mutate-path"; mode mutate-on-preflight; reset_calls
HOME="$H19" run install claude team-standards --reinstall && fail "AC-17 must fail"
mode normal; rm -f "$TMP/mutate-path"
calls | grep -q 'fail code=FOLDER_CHANGED' || fail "AC-17: POST fail"
[ "$(tail -n 2 "$D19/SKILL.md" | paste -sd'|')" = "edit|changed while the install ran" ] || fail "AC-17: folder left as the user changed it"
clean_dir "$H19/.claude/skills" && [ ! -e "$H19/.allye/backups" ] || fail "AC-17: no backup and no leftovers"
pass "AC-17: a folder changed after the request aborts with POST fail, untouched"

# AC-18: backups dir on another filesystem (copy, verify, delete the hidden copy)
SHM=$(mktemp -d /dev/shm/allye-installer.XXXXXX 2>/dev/null || true)
if [ -n "$SHM" ] && [ "$(stat -c %d "$SHM")" != "$(stat -c %d "$TMP")" ]; then
  export PI_CODING_AGENT_DIR="$TMP/pi18"
  HOME="$SHM" run install pi team-standards || { cat "$TMP/out"; fail "AC-18 setup"; }
  printf 'edit\n' >> "$PI_CODING_AGENT_DIR/skills/team-standards/SKILL.md"; pre=$(tree_of "$PI_CODING_AGENT_DIR/skills/team-standards")
  : > "$TMP/cp.log"
  PATH="$SHIMS/cp:$PATH" HOME="$SHM" run install pi team-standards --reinstall || { cat "$TMP/out"; fail "AC-18 reinstall"; }
  grep -q -- '-a' "$TMP/cp.log" || fail "AC-18: a cross-device backup is made with cp -a"
  B=$(backup_dir "$SHM" pi)
  [ -n "$B" ] && [ "$(btree_of "$B")" = "$pre" ] && [ -f "$B/.allye-artifact.backup.json" ] || fail "AC-18: cross-device backup verified"
  [ "$(stat -c %d "$B")" != "$(stat -c %d "$PI_CODING_AGENT_DIR/skills")" ] && clean_dir "$PI_CODING_AGENT_DIR/skills" || fail "AC-18: really cross-device, hidden copy deleted"
  # a copy that does not verify keeps the hidden edit and the installed release
  export PI_CODING_AGENT_DIR="$TMP/pi18b"
  HOME="$SHM" run install pi team-standards || fail "AC-18 corrupt setup"
  printf 'edit\n' >> "$PI_CODING_AGENT_DIR/skills/team-standards/SKILL.md"
  CORRUPT=1 PATH="$SHIMS/cp:$PATH" HOME="$SHM" run install pi team-standards --reinstall && fail "AC-18: a corrupt backup copy must fail the run"
  hid=$(find "$PI_CODING_AGENT_DIR/skills" -maxdepth 1 -name '.allye-backup.team-standards.*')
  grep -q 'installed, backup not moved' "$TMP/out" && [ -n "$hid" ] && grep -q edit "$hid/SKILL.md" || fail "AC-18: hidden edit kept when the copy does not verify"
  ! grep -q edit "$PI_CODING_AGENT_DIR/skills/team-standards/SKILL.md" && [ "$(jq -r .release_id "$PI_CODING_AGENT_DIR/skills/team-standards/.allye-artifact.json")" = release-1 ] || fail "AC-18: the installed release is kept"
  unset PI_CODING_AGENT_DIR
  pass "AC-18: cross-device backup is copied, verified and the hidden copy deleted"
elif [ "${CI:-}" = true ]; then
  fail "AC-18: /dev/shm on another filesystem than ${TMPDIR:-/tmp} is required when CI=true"
else
  echo "  SKIP: AC-18 (the backups dir is on the same filesystem as the skills dir)"
fi

# AC-20: restore_backup with a destination parent that cannot be written
if [ "$(id -u)" = 0 ] && [ "${CI:-}" = true ]; then fail "AC-20/AC-23 need a non-root user when CI=true (root ignores directory permissions)"
elif [ "$(id -u)" = 0 ]; then echo "  SKIP: AC-20 and AC-23 (running as root ignores directory permissions)"; else
  mkdir -p "$TMP/ac20/skills/.allye-backup.x.1.2"; printf mine > "$TMP/ac20/skills/.allye-backup.x.1.2/SKILL.md"; chmod a-w "$TMP/ac20/skills"
  if out=$(lib restore_backup "$TMP/ac20/skills/.allye-backup.x.1.2" "$TMP/ac20/skills/x" 2>&1); then rc=0; else rc=$?; fi
  [ "$rc" -ne 0 ] && grep -q -F "$TMP/ac20/skills/.allye-backup.x.1.2" <<<"$out" && [ "$(cat "$TMP/ac20/skills/.allye-backup.x.1.2/SKILL.md")" = mine ] || fail "AC-20: restore failure prints the hidden path and deletes nothing"
  chmod u+w "$TMP/ac20/skills"
  pass "AC-20: a failed restore prints the hidden staging path and deletes nothing"

  # AC-23: complete succeeds, the backup cannot be moved
  H23=$(fresh_home ac23); D23="$H23/.claude/skills/team-standards"
  HOME="$H23" run install claude team-standards || fail "AC-23 setup"
  printf 'edit\n' >> "$D23/SKILL.md"; mkdir -p "$H23/.allye/backups/claude"; chmod 500 "$H23/.allye/backups/claude"
  HOME="$H23" run install claude team-standards --reinstall && fail "AC-23 must exit non-zero"
  chmod 700 "$H23/.allye/backups/claude"
  hid=$(find "$H23/.claude/skills" -maxdepth 1 -name '.allye-backup.team-standards.*')
  grep -q 'installed, backup not moved' "$TMP/out" && grep -q -F "$hid" "$TMP/out" || fail "AC-23: message and hidden path printed"
  grep -q edit "$hid/SKILL.md" && grep -q 'Standards 1' "$D23/SKILL.md" && ! grep -q edit "$D23/SKILL.md" || fail "AC-23: release kept, hidden copy untouched"
  [ -z "$(ls -A "$H23/.allye/backups/claude")" ] && [ ! -d "$H23/.claude/skills/team-standards.allye.lock" ] || fail "AC-23: no partial backup, lock released"
  HOME="$H23" run install claude team-standards && fail "AC-23: the next run is blocked by the leftover"
  grep -q -F "$hid" "$TMP/out" || fail "AC-23: next run names the leftover"
  pass "AC-23: a failed backup move keeps the install and the hidden copy"
fi

# AC-19: complete applied but the response is lost
H24=$(fresh_home ac19); D24="$H24/.claude/skills/team-standards"
mode lost-complete
HOME="$H24" run install claude team-standards && fail "AC-19 must fail"
grep -qi 'may already be recorded' "$TMP/out" && grep -qi 'rerun' "$TMP/out" || fail "AC-19: tells the user to rerun"
[ ! -e "$D24" ] && clean_dir "$H24/.claude/skills" || fail "AC-19: rolled back, nothing left"
mode normal; : > "$TMP/requests.log"
HOME="$H24" run install claude team-standards || { cat "$TMP/out"; fail "AC-19 rerun"; }
dist_bodies | jq -e '.reinstall == {observedLocalState: "missing"}' >/dev/null && grep -qi 'reinstall' "$TMP/out" && [ -f "$D24/SKILL.md" ] || fail "AC-19: rerun sends reinstall missing, api:reinstall, installs"
pass "AC-19: a lost complete response is rolled back and the rerun reinstalls"

# AC-27: access lost on preflight/complete, retired on request: rolled back, nothing left
H25=$(fresh_home ac27); D25="$H25/.claude/skills/team-standards"
HOME="$H25" run install claude team-standards || fail "AC-27 setup"
cp -a "$D25" "$TMP/ac27-snap"; before=$(tree_of "$D25"); printf 2 > "$TMP/release"
for m in access-lost-on-complete access-lost-on-preflight marketplace-retired; do
  mode "$m"; reset_calls
  HOME="$H25" run install claude team-standards && fail "AC-27 $m must fail"
  case "$m" in marketplace-retired) grep -qi 'retired' "$TMP/out" ;; *) grep -qi 'view access' "$TMP/out" ;; esac || fail "AC-27 $m: specific message"
  ! grep -qi 'admin' "$TMP/out" || fail "AC-27 $m: no admin wording"
  [ "$(tree_of "$D25")" = "$before" ] && diff -r "$TMP/ac27-snap" "$D25" >/dev/null && clean_dir "$H25/.claude/skills" || fail "AC-27 $m: previous folder restored, nothing left"
  case "$m" in
    marketplace-retired) ! calls | grep -q '/fail' || fail "AC-27 $m: no row, no fail" ;;
    *) calls | grep -q 'distributions/op-[0-9]*/fail' || fail "AC-27 $m: POST fail" ;;
  esac
done
# the same with an edited copy and --reinstall
printf 'edit\n' >> "$D25/SKILL.md"; before=$(tree_of "$D25"); cp -a "$D25" "$TMP/ac27-snap2"; mode access-lost-on-complete
HOME="$H25" run install claude team-standards --reinstall && fail "AC-27 reinstall must fail"
[ "$(tree_of "$D25")" = "$before" ] && diff -r "$TMP/ac27-snap2" "$D25" >/dev/null && clean_dir "$H25/.claude/skills" && [ ! -e "$H25/.allye/backups" ] || fail "AC-27: edited copy restored on a rejected complete"
mode normal; printf 1 > "$TMP/release"
pass "AC-27: access lost and retired skills roll back with the specific message"

# AC-24: token claims and key ids
H26=$(fresh_home ac24)
mode no-iss-aud; HOME="$H26" run install claude team-standards || { cat "$TMP/out"; fail "AC-24 token without iss/aud"; }
mode normal; rm -rf "$H26/.claude/skills/team-standards"
printf custom-kid > "$TMP/kid"; HOME="$H26" run install claude team-standards || { cat "$TMP/out"; fail "AC-24 custom kid"; }
rm -rf "$H26/.claude/skills/team-standards"; printf ghost-kid > "$TMP/token-kid"; reset_calls
HOME="$H26" run install claude team-standards && fail "AC-24 kid absent from the JWKS must fail"
rm -f "$TMP/kid" "$TMP/token-kid"
grep -q 'ghost-kid' "$TMP/out" && ! calls | grep -q preflight && calls | grep -q 'fail code=TOKEN_INVALID' && [ ! -e "$H26/.claude/skills/team-standards" ] || fail "AC-24: unknown kid fails before preflight"
pass "AC-24: tokens with or without iss/aud and with another kid verify; an unknown kid fails first"

# execution-context 500 and a request 400 print the API's code and hint
H27=$(fresh_home errs)
mode exec-context-500; reset_calls
HOME="$H27" run install claude team-standards && fail "execution-context 500 must fail"
grep -q 'SIGNING_KEY_NOT_CONFIGURED' "$TMP/out" && grep -q 'contact the operator' "$TMP/out" && calls | grep -q 'fail code=EXECUTION_CONTEXT_FAILED' || fail "500: code, hint and POST fail"
[ ! -e "$H27/.claude/skills/team-standards" ] && clean_dir "$H27/.claude/skills" || fail "500: nothing changed"
mode bad-request; reset_calls
HOME="$H27" run install claude team-standards && fail "400 must fail"
grep -q 'VALIDATION_FAILED' "$TMP/out" && grep -q 'upgrade the installer' "$TMP/out" && [ ! -e "$H27/.claude/skills/team-standards" ] || fail "400: code and hint, nothing changed"
mode normal
pass "execution-context 500 and request 400 messages carry the API's code and hint"

# AC-08 also when the preflight is rejected (access lost) with --reinstall
ac08 access-lost-on-preflight 1
pass "AC-08: a rejected preflight with --reinstall leaves the edited folder in place"

# D-30: the class (not just the bytes) is re-checked right before the move-aside
H30=$(fresh_home d30); D30="$H30/.claude/skills/team-standards"
HOME="$H30" run install claude team-standards || fail "D-30 setup"
printf 'edit\n' >> "$D30/SKILL.md"; printf '%s' "$D30/.allye-artifact.json" > "$TMP/mutate-path"; mode mutate-on-preflight; reset_calls
HOME="$H30" run install claude team-standards --reinstall && fail "D-30: a class change must abort"
mode normal; rm -f "$TMP/mutate-path"
grep -q 'changed while the install was running' "$TMP/out" && calls | grep -q 'fail code=FOLDER_CHANGED' || fail "D-30: aborted with POST fail"
[ -f "$D30/SKILL.md" ] && grep -q edit "$D30/SKILL.md" && [ ! -e "$H30/.allye/backups" ] && clean_dir "$H30/.claude/skills" || fail "D-30: folder untouched, no backup"
pass "D-30: re-classification catches a changed sidecar before the move-aside"

# lock contention: a lock held by another run is respected and left in place
H31=$(fresh_home lock); mkdir -p "$H31/.claude/skills/team-standards.allye.lock"; : > "$TMP/requests.log"
HOME="$H31" run install claude team-standards && fail "a held lock must stop the install"
grep -q 'Another install' "$TMP/out" && [ "$(dist_posts)" -eq 0 ] && [ -d "$H31/.claude/skills/team-standards.allye.lock" ] || fail "lock: message, no POST, lock kept"
pass "lock contention: the other run's lock is never removed"

# D-35 / SHD-01: only this skill's own leftovers block (foo vs foo.bar)
H32=$(fresh_home others); S32="$H32/.claude/skills"; mkdir -p "$S32"
mkdir -p "$S32/.allye-backup.other-skill.20260101T000000Z.1" "$S32/.allye-backup.team-standards.bar.20260101T000000Z.1" "$S32/.allye-backup.team-standards.notes"
HOME="$H32" run install claude team-standards || { cat "$TMP/out"; fail "leftovers of other skills must not block"; }
pass "leftovers of other skills (including a dotted-slug sibling) do not block"

# symlinked skill folder is never followed or replaced
H33=$(fresh_home symdest); S33="$H33/.claude/skills"
HOME="$H33" run install claude team-standards || fail "symlink setup"
mv "$S33/team-standards" "$H33/real"; ln -s "$H33/real" "$S33/team-standards"
for flag in "" "--reinstall"; do
  : > "$TMP/requests.log"
  HOME="$H33" run install claude team-standards $flag && fail "symlinked folder must be refused ($flag)"
  [ -L "$S33/team-standards" ] && [ "$(dist_posts)" -eq 0 ] && [ -f "$H33/real/SKILL.md" ] || fail "symlink kept, no POST ($flag)"
done
pass "a symlinked skill folder is refused with and without --reinstall"

# omp keeps its backups under its adapter id, not the API runtime (pi)
H34=$(fresh_home omp); HOME="$H34" run install omp team-standards || fail "omp setup"
printf 'edit\n' >> "$H34/.omp/agent/skills/team-standards/SKILL.md"
HOME="$H34" run install omp team-standards --reinstall || { cat "$TMP/out"; fail "omp reinstall"; }
[ -n "$(backup_dir "$H34" omp)" ] && [ ! -e "$H34/.allye/backups/pi" ] || fail "omp backups live under backups/omp"
pass "backups are kept under the adapter id (omp), not the API runtime"

# SHD-02: mv -T support is probed once; a genuine -T failure is never retried with another mv
: > "$TMP/mv.log"; H35=$(fresh_home mvnoT)
PATH="$SHIMS/mv-noT:$PATH" HOME="$H35" run install claude team-standards || { cat "$TMP/out"; fail "install with a mv that lacks -T"; }
grep -q '^-n .*\.allye-stage\.' "$TMP/mv.log" && [ -f "$H35/.claude/skills/team-standards/SKILL.md" ] || fail "mv -n is used when -T is unsupported"
: > "$TMP/mv.log"; H36=$(fresh_home mvfail)
PATH="$SHIMS/mv-fail:$PATH" HOME="$H36" run install claude team-standards && fail "a failing mv -T must fail the install"
! grep '\.allye-stage\.' "$TMP/mv.log" | grep -qv '^-T ' && [ ! -e "$H36/.claude/skills/team-standards" ] && clean_dir "$H36/.claude/skills" || fail "no fallback after a genuine mv -T failure"
pass "SHD-02: mv -T is probed; no fallback after a real failure"

# integrated restore failure: the rejected complete cannot put the edit back
H37=$(fresh_home restorefail); D37="$H37/.claude/skills/team-standards"
HOME="$H37" run install claude team-standards || fail "restore-failure setup"
printf 'edit\n' >> "$D37/SKILL.md"; mode reject-complete; reset_calls
PATH="$SHIMS/mv-restore:$PATH" HOME="$H37" run install claude team-standards --reinstall && fail "restore failure must exit non-zero"
mode normal
hid=$(find "$H37/.claude/skills" -maxdepth 1 -name '.allye-backup.team-standards.*')
[ -n "$hid" ] && grep -q edit "$hid/SKILL.md" && grep -q -F "$hid" "$TMP/out" && grep -q 'nothing was deleted' "$TMP/out" || fail "restore failure prints the hidden path and keeps the edit"
calls | grep -q 'fail code=COMPLETION_REJECTED' && [ ! -d "$H37/.claude/skills/team-standards.allye.lock" ] || fail "fail POSTed, lock released"
pass "a restore that fails inside a rejected complete prints the hidden path and deletes nothing"

# SHD-05: the fail POST without a token is best effort
H38=$(fresh_home failauth); mode exec-context-500; printf 1 > "$TMP/fail-needs-token"
HOME="$H38" run install claude team-standards && fail "execution-context 500 with a refused fail POST must still fail"
rm -f "$TMP/fail-needs-token"; mode normal
grep -q 'SIGNING_KEY_NOT_CONFIGURED' "$TMP/out" && grep -q 'Could not record the failure' "$TMP/out" || fail "original error kept, fail refusal only warns"
pass "SHD-05: a refused fail report never masks the original error"

# SHD-06: backups location checks
H39=$(fresh_home sym-backups); D39="$H39/.claude/skills/team-standards"
HOME="$H39" run install claude team-standards || fail "SHD-06 setup"
printf 'edit\n' >> "$D39/SKILL.md"; cp -a "$D39" "$TMP/shd06-snap"; mkdir -p "$TMP/elsewhere"; ln -s "$TMP/elsewhere" "$H39/.allye"; : > "$TMP/requests.log"
HOME="$H39" run install claude team-standards --reinstall && fail "a symlinked ~/.allye must be refused"
grep -q 'symlink' "$TMP/out" && [ "$(dist_posts)" -eq 0 ] && diff -r "$TMP/shd06-snap" "$D39" >/dev/null && [ -z "$(ls -A "$TMP/elsewhere")" ] || fail "symlinked backups root: refused before any POST, nothing written"
mkdir -p "$TMP/relcwd/relhome"; ( cd "$TMP/relcwd" && HOME=relhome run install claude team-standards ) || fail "relative HOME setup"
printf 'edit\n' >> "$TMP/relcwd/relhome/.claude/skills/team-standards/SKILL.md"; : > "$TMP/requests.log"
( cd "$TMP/relcwd" && HOME=relhome run install claude team-standards --reinstall ) && fail "a relative HOME must be refused for --reinstall"
grep -q 'absolute' "$TMP/out" && [ "$(dist_posts)" -eq 0 ] || fail "relative HOME: refused before any POST"
H40=$(fresh_home chain); HOME="$H40" run install claude team-standards || fail "chain setup"
mkdir -m 755 "$H40/.allye"; printf 'edit\n' >> "$H40/.claude/skills/team-standards/SKILL.md"
HOME="$H40" run install claude team-standards --reinstall || { cat "$TMP/out"; fail "chain reinstall"; }
[ "$(stat -c %a "$H40/.allye")" = 755 ] && [ "$(stat -c %a "$H40/.allye/backups")" = 700 ] && [ "$(stat -c %a "$H40/.allye/backups/claude")" = 700 ] || fail "only the components this run created are 0700"
pass "SHD-06: unsafe backups locations are refused before any POST; created components are 0700"

# SHD-07: a killed run releases its lock and says where the edited copy is
H41=$(fresh_home killed); D41="$H41/.claude/skills/team-standards"
HOME="$H41" run install claude team-standards || fail "kill setup"
printf 'edit\n' >> "$D41/SKILL.md"; mode hang-complete; reset_calls; rm -f "$TMP/kill.pid"
HOME="$H41" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards --reinstall >"$TMP/kill.out" 2>&1 &
for _ in $(seq 1 100); do calls | grep -q '/complete' && break; sleep 0.2; done
calls | grep -q '/complete' || fail "kill: the run reached complete"
kpid=$(cat "$TMP/kill.pid"); kill -TERM -- "-$kpid" 2>/dev/null || true
for _ in $(seq 1 50); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
mode normal
grep -q 'Interrupted' "$TMP/kill.out" && grep -q edit "$H41/.claude/skills/team-standards/SKILL.md" && clean_dir "$H41/.claude/skills" || fail "kill: the published release is rolled back and the edited copy is back in place (SHD-25)"
[ ! -d "$H41/.claude/skills/team-standards.allye.lock" ] && [ -z "$(find "$H41/.claude/skills" -maxdepth 1 -name '.allye-stage.*')" ] || fail "kill: lock and stage released"
pass "SHD-07: INT/TERM releases the lock and puts the edited copy back"

# SHD-08: the PAT never appears in curl's argv
: > "$TMP/curl.log"; H42=$(fresh_home argv)
PATH="$SHIMS/curl:$PATH" HOME="$H42" run install claude team-standards || { cat "$TMP/out"; fail "install through the curl shim"; }
[ -s "$TMP/curl.log" ] && ! grep -qiE 'pat_test|authorization|bearer' "$TMP/curl.log" || fail "SHD-08: no credential in curl argv"
pass "SHD-08: bearer tokens travel on stdin, not in argv"

# AC-16: a symlink or special file in an owned copy is refused, naming the entry
H12=$(fresh_home ac16); D12="$H12/.claude/skills/team-standards"
HOME="$H12" run install claude team-standards || fail "AC-16 setup"
ln -s /etc/hostname "$D12/references/sneaky-link"; cp -a "$D12" "$TMP/ac16-snap"
for flag in "" "--reinstall"; do
  : > "$TMP/requests.log"
  HOME="$H12" run install claude team-standards $flag && fail "symlink in owned copy must be refused ($flag)"
  grep -q 'references/sneaky-link' "$TMP/out" || fail "refusal names the symlink ($flag)"
  [ "$(dist_posts)" -eq 0 ] && diff -r "$TMP/ac16-snap" "$D12" >/dev/null || fail "no POST, folder untouched ($flag)"
done
pass "AC-16: unhashable trees are refused naming the entry"

# AC-22: a leftover .allye-backup.<name>.* blocks the install (D-35)
H13=$(fresh_home ac22); D13="$H13/.claude/skills/team-standards"
HOME="$H13" run install claude team-standards || fail "AC-22 setup"
LEFT="$H13/.claude/skills/.allye-backup.team-standards.20260101T000000Z.4242"
mkdir -p "$LEFT"; printf 'kept\n' > "$LEFT/SKILL.md"; cp -a "$H13/.claude/skills" "$TMP/ac22-snap"
for flag in "" "--reinstall"; do
  : > "$TMP/requests.log"
  HOME="$H13" run install claude team-standards $flag && fail "leftover must block the install ($flag)"
  grep -q "$LEFT" "$TMP/out" && grep -q '.allye/backups' "$TMP/out" && grep -qi 'delete' "$TMP/out" || fail "leftover path and recovery printed ($flag)"
  [ "$(dist_posts)" -eq 0 ] && diff -r "$TMP/ac22-snap" "$H13/.claude/skills" >/dev/null || fail "no POST, nothing touched ($flag)"
done
rm -rf "$D13"   # even a missing folder is blocked
: > "$TMP/requests.log"
HOME="$H13" run install claude team-standards && fail "leftover blocks a missing folder too"
[ "$(dist_posts)" -eq 0 ] && [ ! -e "$D13" ] || fail "missing folder: no POST, nothing created"
pass "AC-22: leftover backups block the install under the lock"

# AC-26: a pending rollback row on the member's ledger changes nothing on the client
H14=$(fresh_home ac26); D14="$H14/.claude/skills/team-standards"
HOME="$H14" run install claude team-standards || fail "AC-26 setup"
mode pending-rollback; : > "$TMP/requests.log"
HOME="$H14" run install claude team-standards || { cat "$TMP/out"; fail "AC-26 same release"; }
grep -q 'already installed' "$TMP/out" && [ "$(dist_posts)" -eq 0 ] || fail "AC-26 same release: already installed, no POST"
printf 2 > "$TMP/release"
HOME="$H14" run install claude team-standards || { cat "$TMP/out"; fail "AC-26 newer release"; }
reqlog | jq -e 'select(.path | test("/distributions/update$")) | .body | .baseReleaseId == "release-1" and (has("reinstall") | not)' >/dev/null || fail "AC-26 newer release goes through update"
[ "$(jq -r .release_id "$D14/.allye-artifact.json")" = release-2 ] || fail "AC-26 update installed"
jq -e '[.[].rows[] | select(.kind == "rollback" and .status == "pending")] | length >= 1' "$TMP/ledger.json" >/dev/null \
  && jq -e '[.[] | select(.rows | map(.kind) | index("rollback") > index("install"))] | length >= 1' "$TMP/ledger.json" >/dev/null || fail "AC-26: the fake really holds a pending rollback row over the applied row"
mode normal; printf 1 > "$TMP/release"
pass "AC-26: a pending rollback row never changes noop or update answers"

# AC-14: specific API errors, no admin-reset wording anywhere
H15=$(fresh_home ac14); D15="$H15/.claude/skills/team-standards"
mode not-authorized; : > "$TMP/requests.log"
HOME="$H15" run install claude team-standards && fail "not-authorized must fail"
grep -qi 'view access' "$TMP/out" && ! grep -qi 'admin' "$TMP/out" || fail "request: view-access message without admin wording"
[ ! -e "$D15" ] || fail "nothing installed when not authorized"
mode normal; HOME="$H15" run install claude team-standards || fail "AC-14 setup"
printf 2 > "$TMP/release"; mode not-authorized
HOME="$H15" run install claude team-standards && fail "not-authorized on update must fail"
grep -qi 'view access' "$TMP/out" && ! grep -qi 'admin' "$TMP/out" || fail "update: view-access message without admin wording"
[ "$(jq -r .release_id "$D15/.allye-artifact.json")" = release-1 ] || fail "update refused: release kept"
mode marketplace-retired; H16=$(fresh_home retired)
HOME="$H16" run install claude team-standards && fail "retired must fail"
grep -qi 'retired' "$TMP/out" && grep -qi 'read-only' "$TMP/out" && grep -qi 'nothing was installed' "$TMP/out" && ! grep -qi 'admin' "$TMP/out" || fail "410 message"
[ ! -e "$H16/.claude/skills/team-standards" ] || fail "nothing installed when retired"
mode team-selection-required
HOME="$H16" run install claude team-standards && fail "team selection must fail"
grep -qi 'several teams' "$TMP/out" && grep -q -- '--team' "$TMP/out" && grep -qi 'skill id' "$TMP/out" && ! grep -qi 'admin' "$TMP/out" || fail "422 message"
mode blocked; HOME="$H16" run install claude team-standards && fail "blocked must fail"
grep -q 'RUNTIME_INCOMPATIBLE' "$TMP/out" && grep -q 'upgrade the API' "$TMP/out" || fail "RUNTIME_INCOMPATIBLE prints the API code and hint"
mode normal; printf 1 > "$TMP/release"
needle="Ask an Allye admin to $(printf 'reset')"
! grep -rIq -F "$needle" "$ROOT" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.allye || fail "the admin-reset wording no longer exists in the repo"
pass "AC-14: specific messages for 409, 410, 422 and RUNTIME_INCOMPATIBLE"

# the tree hash excludes the sidecar at the root; the backup sidecar name only for backup trees (SHD-26)
H17=$(fresh_home hash); mkdir -p "$H17/t/references"; printf a > "$H17/t/SKILL.md"; before=$(tree_of "$H17/t")
printf x > "$H17/t/.allye-artifact.json"; printf y > "$H17/t/.allye-artifact.backup.json"
[ "$(tree_of "$H17/t")" != "$before" ] || fail "SHD-26: a user file named like the backup sidecar is part of an installed tree"
[ "$(btree_of "$H17/t")" = "$before" ] || fail "tree hash --backup ignores both sidecar names at the root"
rm "$H17/t/.allye-artifact.backup.json"; [ "$(tree_of "$H17/t")" = "$before" ] || fail "tree hash ignores the sidecar at the root"
printf z > "$H17/t/references/.allye-artifact.json"
[ "$(tree_of "$H17/t")" != "$before" ] || fail "a nested file with a sidecar name is part of the tree"
pass "tree hash excludes .allye-artifact.json at the root; .allye-artifact.backup.json only with --backup"

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
[ "$(fake "$(jq -c '.reinstall = {observedLocalState:"missing"} | .releaseId = "release-9"' <<<"$base")")" = 409 ] || fail "a reinstall must target the current approved release"
for f in requiredCapabilities inputFormat outputFormat; do
  [ "$(fake "$(jq -c --arg f "$f" '.[$f] = "x"' <<<"$base")")" = 400 ] && grep -q "$f" "$TMP/fake.out" || fail "$f -> 400 naming the field"
done
[ "$(fake "$(jq -c '.runtime = "opencode" | .allowExperimental = false' <<<"$base")")" = 409 ] || fail "opencode needs allowExperimental"
[ "$(fake "$(jq -c '.runtime = "cursor"' <<<"$base")")" = 409 ] || fail "unknown runtime blocked"
pass "fake API enforces the 1.1.0 and reinstall validation rules"

# ---- round 2 corrections (ALY-34.3) ----
mkshim() {  # name; body on stdin (REAL_MV is exported for the shim)
  mkdir -p "$SHIMS/$1"; cat > "$SHIMS/$1/mv"; chmod +x "$SHIMS/$1/mv"
}
export REAL_MV
mkshim mv-race <<'SH'
#!/bin/bash
# edits the installed folder right before it is moved to its .allye.previous.* name
args=("$@"); n=$#
case "${args[$((n-1))]}" in *.allye.previous.*) printf 'raced\n' >> "${args[$((n-2))]}/SKILL.md" ;; esac
exec "$REAL_MV" "$@"
SH
mkshim mv-prevfail <<'SH'
#!/bin/bash
# fails every move out of a .allye.previous.* name (the restore of the previous release)
args=("$@"); n=$#
case "${args[$((n-2))]}" in *.allye.previous.*) echo "mv: cannot move: Input/output error" >&2; exit 1 ;; esac
exec "$REAL_MV" "$@"
SH
mkshim mv-nrace <<'SH'
#!/bin/bash
# no -T (BSD style); a directory appears at the skill path right before mv -n runs
args=("$@"); n=$#
if [ "$1" = -T ]; then echo "mv: illegal option -- T" >&2; exit 64; fi
case "${args[$((n-1))]}" in */team-standards) mkdir -p "${args[$((n-1))]}" ;; esac
exec "$REAL_MV" "$@"
SH
mkshim mv-hang <<'SH'
#!/bin/bash
# hangs while the staged release is being moved into place (the skill path is empty then)
if [ "$1" = -T ]; then case "$*" in *.allye-stage.*) echo hang >> "$MV_HANG_FLAG"; sleep 30 ;; esac; fi
exec "$REAL_MV" "$@"
SH

# D-39: only the allowed routes are called; X-Team-Id only with --team / ALLYE_TEAM_ID
H50=$(fresh_home d39); D50="$H50/.claude/skills/team-standards"
mode normal; printf 1 > "$TMP/release"; : > "$TMP/requests.log"
HOME="$H50" run install claude team-standards || { cat "$TMP/out"; fail "D-39 install"; }
printf 2 > "$TMP/release"; HOME="$H50" run install claude team-standards || fail "D-39 update"
printf 'edit\n' >> "$D50/SKILL.md"; HOME="$H50" run install claude team-standards --reinstall || { cat "$TMP/out"; fail "D-39 reinstall"; }
rm -rf "$D50"; HOME="$H50" run install claude team-standards || fail "D-39 missing"
mode reject-complete; HOME="$(fresh_home d39b)" run install claude team-standards && fail "D-39 reject-complete must fail"
mode normal
SK=11111111-2222-3333-4444-555555555555
stray=$(reqlog | jq -r .path | grep -Ev "^/api/skills/(resolve/team-standards|$SK|$SK/releases/[^/]+/artifact|distribution-execution/jwks|$SK/distributions/(request|update)|$SK/distributions/op-[0-9]+/(execution-context|preflight|complete|fail))\$" || true)
[ -z "$stray" ] || fail "D-39: a route outside the allowed set was called: $stray"
for need in '/distributions/update' '/distributions/request' '/execution-context' '/preflight' '/complete' '/fail' '/jwks' '/artifact' '/resolve/'; do
  reqlog | jq -r .path | grep -q -e "$need" || fail "D-39: the run exercised $need"
done
! reqlog | jq -r .path | grep -qE 'results|export|rollback|remove' || fail "D-39: results, export, rollback and remove are never called"
reqlog | jq -s -e 'length > 0 and all(.xTeam == null)' >/dev/null || fail "D-39: no X-Team-Id without --team"
: > "$TMP/requests.log"; HOME="$(fresh_home d39t)" run install claude team-standards --team team-xyz || { cat "$TMP/out"; fail "D-39 --team install"; }
reqlog | jq -s -e 'length > 0 and all(.xTeam == "team-xyz")' >/dev/null || fail "D-39: X-Team-Id is sent on every request with --team"
: > "$TMP/requests.log"; ALLYE_TEAM_ID=team-env HOME="$(fresh_home d39e)" run install claude team-standards || fail "D-39 env install"
reqlog | jq -s -e 'length > 0 and all(.xTeam == "team-env")' >/dev/null || fail "D-39: ALLYE_TEAM_ID is the documented equivalent of --team"
pass "D-39: only the allowed routes, X-Team-Id only with --team or ALLYE_TEAM_ID"
# Shield F2: the team id is validated before it can reach a header
for bad in $'team\nX-Evil: 1' 'a: b' 'team id' $'t\r\nX: y' "$(printf 'a%.0s' $(seq 1 65))"; do
  : > "$TMP/requests.log"; rc=0
  HOME="$(fresh_home f2a)" run install claude team-standards --team "$bad" || rc=$?
  [ "$rc" -eq 2 ] || fail "F2: hostile --team must be refused with exit 2 (got $rc)"
  grep -q 'team id' "$TMP/out" || fail "F2: clear error for a bad team id"
  [ -z "$(reqlog)" ] || fail "F2: no request may be made with a bad team id"
  : > "$TMP/requests.log"; rc=0
  ALLYE_TEAM_ID="$bad" HOME="$(fresh_home f2b)" run list || rc=$?
  [ "$rc" -eq 2 ] || fail "F2: hostile ALLYE_TEAM_ID must be refused with exit 2 (got $rc)"
  [ -z "$(reqlog)" ] || fail "F2: no request with a bad ALLYE_TEAM_ID"
done
: > "$TMP/requests.log"; HOME="$(fresh_home f2d)" run install claude team-standards --team 00000000-0000-4000-8000-000000000000 || { cat "$TMP/out"; fail "F2: a UUID team id is accepted"; }
reqlog | jq -s -e 'length > 0 and all(.xTeam == "00000000-0000-4000-8000-000000000000")' >/dev/null || fail "F2: valid id sent as X-Team-Id"
pass "Shield F2: hostile team ids are refused before any request"

# SHD-09: the folder is re-classified and re-hashed around the move to .allye.previous.*
H54=$(fresh_home shd09a); D54="$H54/.claude/skills/team-standards"
printf 1 > "$TMP/release"; HOME="$H54" run install claude team-standards || fail "SHD-09 setup"
printf 2 > "$TMP/release"; printf '%s' "$D54/SKILL.md" > "$TMP/mutate-path"; mode mutate-on-preflight; reset_calls
HOME="$H54" run install claude team-standards && fail "SHD-09: an intact copy edited mid-install must abort"
mode normal; rm -f "$TMP/mutate-path"
calls | grep -q 'fail code=FOLDER_CHANGED' && [ "$(tail -n1 "$D54/SKILL.md")" = "changed while the install ran" ] && [ "$(jq -r .release_id "$D54/.allye-artifact.json")" = release-1 ] && clean_dir "$H54/.claude/skills" || fail "SHD-09: edit kept, POST fail, nothing left"
H55=$(fresh_home shd09b); D55="$H55/.claude/skills/team-standards"
printf 1 > "$TMP/release"; printf '%s' "$D55/SKILL.md" > "$TMP/mutate-path"; mode mutate-on-preflight; reset_calls
HOME="$H55" run install claude team-standards && fail "SHD-09: a folder created mid-install must abort"
mode normal; rm -f "$TMP/mutate-path"
calls | grep -q 'fail code=FOLDER_CHANGED' && [ "$(cat "$D55/SKILL.md")" = "changed while the install ran" ] && [ ! -e "$D55/.allye-artifact.json" ] && clean_dir "$H55/.claude/skills" || fail "SHD-09: created folder untouched, POST fail"
H56=$(fresh_home shd09c); D56="$H56/.claude/skills/team-standards"
printf 1 > "$TMP/release"; HOME="$H56" run install claude team-standards || fail "SHD-09c setup"
printf 2 > "$TMP/release"; reset_calls
PATH="$SHIMS/mv-race:$PATH" HOME="$H56" run install claude team-standards && fail "SHD-09: an edit racing the move-aside must abort"
calls | grep -q 'fail code=FOLDER_CHANGED' && [ "$(tail -n1 "$D56/SKILL.md")" = raced ] && [ "$(jq -r .release_id "$D56/.allye-artifact.json")" = release-1 ] && clean_dir "$H56/.claude/skills" || fail "SHD-09: raced edit restored in place, POST fail"
printf 1 > "$TMP/release"
pass "SHD-09: a folder changed or created mid-install is never moved aside or deleted"

# SHD-11: a failed restore of the previous release prints where it is
H57=$(fresh_home shd11); D57="$H57/.claude/skills/team-standards"
printf 1 > "$TMP/release"; HOME="$H57" run install claude team-standards || fail "SHD-11 setup"
printf 2 > "$TMP/release"; mode reject-complete
PATH="$SHIMS/mv-prevfail:$PATH" HOME="$H57" run install claude team-standards && fail "SHD-11 must exit non-zero"
mode normal; printf 1 > "$TMP/release"
prev=$(find "$H57/.claude/skills" -maxdepth 1 -name 'team-standards.allye.previous.*')
[ -n "$prev" ] && grep -q -F "$prev" "$TMP/out" && grep -q 'Standards 1' "$prev/SKILL.md" || fail "SHD-11: the previous path is printed and kept"
rm -rf "$prev"
pass "SHD-11: a failed restore of the previous release prints its path"

# SHD-10: no curl config injection through a bearer
bad=$'pat_x\noutput = "'"$TMP"'/pwned"'
reset_calls; ALLYE_PAT="$bad" run list && fail "SHD-10: a PAT with a newline must be refused"
[ ! -e "$TMP/pwned" ] && [ -z "$(calls)" ] && ! grep -q pwned "$TMP/out" && grep -q 'ALLYE_PAT' "$TMP/out" || fail "SHD-10: refused before any request, token not echoed"
if lib api_call GET /api/skills "" "$bad" >/dev/null 2>&1; then fail "SHD-10: api_call must refuse the bearer"; fi
[ ! -e "$TMP/pwned" ] && [ -z "$(calls)" ] || fail "SHD-10: api_call sent nothing"
mode newline-token; reset_calls
HOME="$(fresh_home shd10)" run install claude team-standards && fail "SHD-10: a hostile execution token must fail"
mode normal
[ ! -e "$TMP/pwned" ] && ! calls | grep -q '/fail' && grep -qi 'credential' "$TMP/out" || fail "SHD-10: no fail report with a hostile token, nothing written"
pass "SHD-10: bearers outside the token alphabet are never put in a curl config"

# SHD-12: BSD mv -n must not nest the source into a directory that appears at the destination
H59=$(fresh_home shd12); : > "$TMP/mv.log"; reset_calls
PATH="$SHIMS/mv-nrace:$PATH" HOME="$H59" run install claude team-standards && fail "SHD-12: nesting must fail the install"
calls | grep -q 'fail code=PUBLISH_FAILED' && [ -z "$(ls -A "$H59/.claude/skills/team-standards")" ] && clean_dir "$H59/.claude/skills" || fail "SHD-12: nothing nested, source moved back, POST fail"
pass "SHD-12: mv -n never leaves the staged release nested in the destination"

# SHD-13: a sidecar name at the root counts only when it is a regular file
mkdir -p "$TMP/t13"; printf a > "$TMP/t13/SKILL.md"; ln -s /etc/hostname "$TMP/t13/.allye-artifact.json"
out=$(node "$ROOT/install/skill-tool.mjs" tree-hash "$TMP/t13" 2>&1) && fail "SHD-13: a symlink named like the sidecar must be refused"
grep -q '.allye-artifact.json' <<<"$out" || fail "SHD-13: the entry is named"
rm "$TMP/t13/.allye-artifact.json"; mkdir "$TMP/t13/.allye-artifact.backup.json"; printf x > "$TMP/t13/.allye-artifact.backup.json/f"
out=$(node "$ROOT/install/skill-tool.mjs" tree-hash "$TMP/t13" --backup 2>&1) && fail "SHD-13: a directory named like the backup sidecar must be refused in a backup tree"
grep -q '.allye-artifact.backup.json' <<<"$out" || fail "SHD-13: the directory is named"
pass "SHD-13: non-regular entries with a sidecar name are refused"

# SHD-14: pre-existing backups components must not be group/world writable
for lvl in 1 3; do
  H60=$(fresh_home "shd14-$lvl"); HOME="$H60" run install claude team-standards || fail "SHD-14 setup"
  printf 'edit\n' >> "$H60/.claude/skills/team-standards/SKILL.md"; cp -a "$H60/.claude/skills/team-standards" "$TMP/shd14-snap"
  mkdir -m 700 "$H60/.allye"; [ "$lvl" = 1 ] || { mkdir -m 700 "$H60/.allye/backups"; mkdir -m 777 "$H60/.allye/backups/claude"; }
  [ "$lvl" = 3 ] || chmod 775 "$H60/.allye"
  : > "$TMP/requests.log"
  HOME="$H60" run install claude team-standards --reinstall && fail "SHD-14 level $lvl: a writable component must be refused"
  grep -q 'writable' "$TMP/out" && [ "$(dist_posts)" -eq 0 ] && diff -r "$TMP/shd14-snap" "$H60/.claude/skills/team-standards" >/dev/null || fail "SHD-14 level $lvl: refused before any POST, folder untouched"
  rm -rf "$TMP/shd14-snap"
done
pass "SHD-14: group/world-writable backups components are refused"

# SHD-15: a signal between the move-aside and the publish puts the previous release back
H62=$(fresh_home shd15); D62="$H62/.claude/skills/team-standards"
printf 1 > "$TMP/release"; HOME="$H62" run install claude team-standards || fail "SHD-15 setup"
printf 2 > "$TMP/release"; rm -f "$TMP/kill.pid" "$TMP/mv-hang.flag"
MV_HANG_FLAG="$TMP/mv-hang.flag" PATH="$SHIMS/mv-hang:$PATH" HOME="$H62" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards >"$TMP/kill.out" 2>&1 &
for _ in $(seq 1 100); do [ -s "$TMP/mv-hang.flag" ] && break; sleep 0.2; done
[ -s "$TMP/mv-hang.flag" ] || fail "SHD-15: the run reached the publish"
kpid=$(cat "$TMP/kill.pid"); kill -TERM -- "-$kpid" 2>/dev/null || true
for _ in $(seq 1 50); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
printf 1 > "$TMP/release"
grep -q 'Standards 1' "$D62/SKILL.md" && [ "$(jq -r .release_id "$D62/.allye-artifact.json")" = release-1 ] && clean_dir "$H62/.claude/skills" || fail "SHD-15: previous release back in place, nothing left"
pass "SHD-15: a signal during the swap restores the previous release"

# SHD-16: the backup sidecar rename never overwrites a file of the same name
H63=$(fresh_home shd16); D63="$H63/.claude/skills/team-standards"
HOME="$H63" run install claude team-standards || fail "SHD-16 setup"
printf 'edit\n' >> "$D63/SKILL.md"; printf 'user data' > "$D63/.allye-artifact.backup.json"
HOME="$H63" run install claude team-standards --reinstall || { cat "$TMP/out"; fail "SHD-16 reinstall"; }
B=$(backup_dir "$H63" claude)
[ "$(cat "$B/.allye-artifact.backup.json")" = "user data" ] && [ -f "$B/.allye-artifact.json" ] || fail "SHD-16: the user's file is kept, the sidecar keeps its name"
pass "SHD-16: the backup sidecar rename never overwrites"

# SHD-17: a rejected execution token is never answered with the PAT, nor with the @pat sentinel
H67=$(fresh_home shd17); mode bad-token; : > "$TMP/requests.log"
HOME="$H67" run install claude team-standards && fail "SHD-17: a forged token must fail the install"
reqlog | jq -e 'select(.path | test("/fail$"))' >/dev/null || fail "SHD-17: a fail report was sent"
[ "$(reqlog | jq -r 'select(.path | test("/fail$")) | .bearer' | sort -u)" = "op-token" ] || fail "SHD-17: the fail report carries the operation token only"
mode exec-context-500; : > "$TMP/requests.log"
HOME="$H67" run install claude team-standards && fail "SHD-17: no token must fail the install"
! reqlog | jq -e 'select(.bearer == "sentinel")' >/dev/null || fail "SHD-17: the literal @pat is never sent"
mode normal
pass "SHD-17: the fail report never carries the PAT after a token was issued, nor the @pat sentinel"

# SHD-18: slugs that look like the installer's own suffixes are refused
lib valid_slug "team-standards" || fail "SHD-18: a normal slug is valid"
! lib valid_slug "foo.allye.lock" && ! lib valid_slug "a.allye.previous.1" || fail "SHD-18: slugs holding .allye. are refused"
pass "SHD-18: slugs containing .allye. are refused"

# SHD-19: stale stage entries are reported, never touched
H64=$(fresh_home shd19); mkdir -p "$H64/.claude/skills/.allye-stage.zzzzzz"
HOME="$H64" run install claude team-standards || fail "SHD-19 install"
grep -q '.allye-stage.zzzzzz' "$TMP/out" && [ -d "$H64/.claude/skills/.allye-stage.zzzzzz" ] || fail "SHD-19: stale stage reported and kept"
rm -rf "$H64/.claude/skills/.allye-stage.zzzzzz"
pass "SHD-19: stale .allye-stage.* entries are reported"

# SHD-20: the mv -T probe never trusts the environment
ALLYE_MV_T=yes _ALLYE_MV_T=yes PATH="$SHIMS/mv-noT:$PATH" HOME="$(fresh_home shd20)" run install claude team-standards || { cat "$TMP/out"; fail "SHD-20: the probe ignores ALLYE_MV_T"; }
pass "SHD-20: ALLYE_MV_T from the environment is ignored"

# SHD-21: status prints no control characters from the sidecar
H66=$(fresh_home shd21); HOME="$H66" run install claude team-standards || fail "SHD-21 setup"
jq '.version = "1.0\u001b[2Jevil\nforged line"' "$H66/.claude/skills/team-standards/.allye-artifact.json" > "$TMP/sc" && cp "$TMP/sc" "$H66/.claude/skills/team-standards/.allye-artifact.json"
HOME="$H66" run status || fail "SHD-21 status"
! grep -q $'\x1b' "$TMP/out" && ! grep -q '^forged' "$TMP/out" && grep -q 'team-standards' "$TMP/out" || fail "SHD-21: control characters are stripped"
pass "SHD-21: status strips control characters from the version"

# SHD-22: server-derived text never reaches the terminal as control characters or backslash escapes
H68=$(fresh_home shd22); printf 1 > "$TMP/hostile"
no_escapes() { ! grep -q $'\x1b\]0;' "$TMP/out" && ! grep -q $'\r' "$TMP/out" && ! grep -q $'\a' "$TMP/out" && ! LC_ALL=C grep -q $'\xc2\x9b' "$TMP/out" && ! LC_ALL=C grep -q $'\xe2\x80\xae' "$TMP/out" && ! LC_ALL=C grep -q $'\xe2\x80\x8b' "$TMP/out" && ! LC_ALL=C grep -q $'\xe2\x81\xa6' "$TMP/out" ; }
mode bad-request; HOME="$H68" run install claude team-standards && fail "SHD-22: bad-request must fail"
grep -q 'pwn' "$TMP/out" && no_escapes || { cat -v "$TMP/out"; fail "SHD-22: API message and hint are printed without control characters"; }
mode exec-context-500; HOME="$H68" run install claude team-standards && fail "SHD-22: exec-context-500 must fail"
no_escapes || fail "SHD-22: execution-context error text"
mode team-selection-required; HOME="$H68" run install claude team-standards && fail "SHD-22: team selection must fail"
grep -q 'Alpha' "$TMP/out" && no_escapes || fail "SHD-22: team names"
mode normal; HOME="$H68" run install claude team-standards || { cat -v "$TMP/out"; fail "SHD-22: install with a hostile version"; }
grep -q 'installed for claude' "$TMP/out" && no_escapes || fail "SHD-22: release version"
mode normal; HOME="$H68" run list --scope team --query x || fail "SHD-28: list"
grep -q 'team-standards' "$TMP/out" && no_escapes || { cat -v "$TMP/out"; fail "SHD-28: list output has no ESC or C1 controls"; }
rm -f "$TMP/hostile"
pass "SHD-22: server text is printed without control characters or escape expansion"

# SHD-23: the bearer alphabet is ASCII whatever the locale
LC_ALL=en_US.UTF-8 lib valid_bearer "pat_$(printf 'caf\303\251')" && fail "SHD-23: é must not match under a UTF-8 locale"
lib valid_bearer 'pat_abc.DEF-1' || fail "SHD-23: a normal token stays valid"
pass "SHD-23: valid_bearer is ASCII-only under any locale"

# SHD-24: identifiers from the API are validated before they enter a URL
for m in hostile-skill hostile-release hostile-hash hostile-op; do
  H69=$(fresh_home "shd24-$m"); mode "$m"; : > "$TMP/requests.log"
  HOME="$H69" run install claude team-standards && fail "SHD-24 $m: must fail"
  grep -q 'not a valid' "$TMP/out" || { cat "$TMP/out"; fail "SHD-24 $m: clear message"; }
  ! reqlog | jq -e 'select(.path | test("[.][.]|%"))' >/dev/null && [ -z "$(ls -A "$H69/.claude/skills" 2>/dev/null)" ] || fail "SHD-24 $m: no request built from the hostile value, nothing installed"
  [ "$m" != hostile-release ] || [ -z "$(reqlog | jq -r 'select(.path | test("/artifact"))')" ] || fail "SHD-24: no artifact request"
done
mode normal
pass "SHD-24: hostile skill, release, hash and operation ids are refused"

# SHD-25: a signal after the publish and before complete succeeds rolls the release back
H70=$(fresh_home shd25); D70="$H70/.claude/skills/team-standards"
printf 1 > "$TMP/release"; HOME="$H70" run install claude team-standards || fail "SHD-25 setup"
printf 2 > "$TMP/release"; mode hang-complete; reset_calls; rm -f "$TMP/kill.pid"
HOME="$H70" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards >"$TMP/kill.out" 2>&1 &
for _ in $(seq 1 100); do calls | grep -q '/complete' && break; sleep 0.2; done
calls | grep -q '/complete' || fail "SHD-25: the run reached complete"
kpid=$(cat "$TMP/kill.pid"); kill -TERM -- "-$kpid" 2>/dev/null || true
for _ in $(seq 1 50); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
mode normal; printf 1 > "$TMP/release"
grep -q 'Standards 1' "$D70/SKILL.md" && [ "$(jq -r .release_id "$D70/.allye-artifact.json")" = release-1 ] && clean_dir "$H70/.claude/skills" || fail "SHD-25: previous release back, nothing left"
calls | grep -q 'fail' || fail "SHD-25: the failure was reported"
grep -q 'API may now be ahead of your disk' "$TMP/kill.out" && grep -q 'rerun' "$TMP/kill.out" || { cat "$TMP/kill.out"; fail "SHD-31: the rollback by signal says the API may be ahead and to rerun"; }
pass "SHD-25: a signal before complete succeeds rolls back and reports the failure"

# SHD-29: a signal during the failure report, after the rollback restored the old state, deletes nothing
for variant in edited previous; do
  H80=$(fresh_home shd29-$variant); D80="$H80/.claude/skills/team-standards"
  printf 1 > "$TMP/release"; mode normal; HOME="$H80" run install claude team-standards || fail "SHD-29 setup"
  if [ "$variant" = edited ]; then printf 'edit\n' >> "$D80/SKILL.md"; flags=--reinstall; else printf 2 > "$TMP/release"; flags=""; fi
  before=$(tree_of "$D80")
  mode reject-complete; printf 1 > "$TMP/hang-fail"; reset_calls; rm -f "$TMP/kill.pid"
  # shellcheck disable=SC2086
  HOME="$H80" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards $flags >"$TMP/kill.out" 2>&1 &
  for _ in $(seq 1 100); do calls | grep -q '/fail' && break; sleep 0.2; done
  calls | grep -q '/fail' || fail "SHD-29 $variant: the run reached the fail report"
  kpid=$(cat "$TMP/kill.pid"); kill -TERM -- "-$kpid" 2>/dev/null || true
  for _ in $(seq 1 50); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
  rm -f "$TMP/hang-fail"; mode normal; printf 1 > "$TMP/release"
  [ -d "$D80" ] && [ "$(tree_of "$D80")" = "$before" ] && clean_dir "$H80/.claude/skills" && [ -z "$(backup_dir "$H80" claude)" ] || { cat "$TMP/kill.out"; fail "SHD-29 $variant: the restored state survives the signal intact"; }
done
pass "SHD-29: a signal during the failure report after a rollback deletes nothing"

# SHD-30: a signal right after the staged tree was moved into place still rolls back
mkshim mv-hang-after <<'SH'
#!/bin/bash
# completes the move of the staged release, then hangs before install.sh can record it
"$REAL_MV" "$@"; rc=$?
if [ "$1" = -T ]; then case "$*" in *.allye-stage.*) echo hang >> "$MV_HANG_FLAG"; sleep 30 ;; esac; fi
exit $rc
SH
H81=$(fresh_home shd30); D81="$H81/.claude/skills/team-standards"
printf 1 > "$TMP/release"; HOME="$H81" run install claude team-standards || fail "SHD-30 setup"
printf 2 > "$TMP/release"; rm -f "$TMP/kill.pid" "$TMP/mv-hang.flag"
MV_HANG_FLAG="$TMP/mv-hang.flag" PATH="$SHIMS/mv-hang-after:$PATH" HOME="$H81" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards >"$TMP/kill.out" 2>&1 &
for _ in $(seq 1 100); do [ -s "$TMP/mv-hang.flag" ] && break; sleep 0.2; done
[ -s "$TMP/mv-hang.flag" ] || fail "SHD-30: the run reached the publish"
kpid=$(cat "$TMP/kill.pid"); kill -TERM -- "-$kpid" 2>/dev/null || true
for _ in $(seq 1 50); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
printf 1 > "$TMP/release"
grep -q 'Standards 1' "$D81/SKILL.md" && [ "$(jq -r .release_id "$D81/.allye-artifact.json")" = release-1 ] && clean_dir "$H81/.claude/skills" || { cat "$TMP/kill.out"; fail "SHD-30: previous release back, nothing left"; }
pass "SHD-30: a signal between the publish move and the published flag rolls back"

# SHD-27: a failing stat is unsafe, never assumed 755
mkdir -p "$SHIMS/stat-fail"; printf '#!/bin/bash\nexit 1\n' > "$SHIMS/stat-fail/stat"; chmod +x "$SHIMS/stat-fail/stat"
LIB_PATH="$SHIMS/stat-fail:$PATH" lib others_can_write "$TMP" || fail "SHD-27: a stat failure must count as writable by others"
mkdir -m 700 "$TMP/t27"; lib others_can_write "$TMP/t27" && fail "SHD-27: a 0700 dir is not writable by others"
pass "SHD-27: others_can_write fails closed"


# SHD-35 / SHD-40: clean_text uses portable bytes and also drops bidi/format characters
CLEAN_SRC=$(sed -n '/^clean_text()/,/^}/p' "$ROOT/install.sh"); eval "$CLEAN_SRC"
[ -z "$(grep -c 'x[0-9a-f][0-9a-f]\]' <<<"$CLEAN_SRC" | grep -v '^0$')" ] || fail "SHD-35: clean_text still uses GNU-only \\x escapes"
got=$(clean_text "a$(printf '\302\233')b xc25 $(printf '\303\251\342\202\254')z"); [ "$got" = "ab xc25 $(printf '\303\251\342\202\254')z" ] || { printf '%s' "$got" | od -c | head; fail "SHD-35: U+009B removed, xc25 and é/€ survive"; }
for bytes in '\342\200\213' '\342\200\217' '\342\200\250' '\342\200\256' '\342\201\246' '\342\201\251'; do
  got=$(clean_text "a$(printf "$bytes")b"); [ "$got" = ab ] || fail "SHD-40: bidi/format character $bytes must be removed"
done
for bytes in '\342\200\220' '\342\200\230' '\342\200\257' '\342\201\245' '\342\201\252'; do
  got=$(clean_text "a$(printf "$bytes")b"); [ "$got" = "a$(printf "$bytes")b" ] || fail "SHD-40: neighbour character $bytes must survive"
done
pass "SHD-35/SHD-40: clean_text is byte-portable and drops C1 and bidi/format characters"

# SHD-36: status cleans the sidecar version and slug, and the stored version has no C1
H90=$(fresh_home shd36); HOME="$H90" run install claude team-standards || fail "SHD-36 setup"
jq '.version = "1.0\u009bevil‮rtl"' "$H90/.claude/skills/team-standards/.allye-artifact.json" > "$TMP/sc" && cp "$TMP/sc" "$H90/.claude/skills/team-standards/.allye-artifact.json"
HOME="$H90" run status || fail "SHD-36 status"
! LC_ALL=C grep -q $'\xc2\x9b' "$TMP/out" && ! LC_ALL=C grep -q $'\xe2\x80\xae' "$TMP/out" && grep -q 'team-standards' "$TMP/out" || { cat -v "$TMP/out"; fail "SHD-36: status prints no C1 or bidi characters"; }
grep -q 'team-standards' "$TMP/out" || fail "SHD-36: status still lists the skill"
printf 1 > "$TMP/hostile"; H91=$(fresh_home shd36b); HOME="$H91" run install claude team-standards || fail "SHD-36 hostile install"; rm -f "$TMP/hostile"
! LC_ALL=C grep -q $'\xc2\x9b' "$H91/.claude/skills/team-standards/.allye-artifact.json" && ! LC_ALL=C grep -q $'\xc2\x9b' <<<"$(jq -r .version "$H91/.claude/skills/team-standards/.allye-artifact.json")" || fail "SHD-36: no C1 stored in the sidecar version"
pass "SHD-36: status and the stored version carry no C1 or bidi characters"

# SHD-37: a held lock records its pid; the message says whether it is alive or looks stale
H92=$(fresh_home shd37); L92="$H92/.claude/skills/team-standards.allye.lock"; mkdir -p "$H92/.claude/skills"
sleep 60 & LIVE=$!
mkdir "$L92"; printf '%s\n' "$LIVE" > "$L92/pid"; : > "$TMP/requests.log"
HOME="$H92" run install claude team-standards && fail "SHD-37: a live lock stops the install"
grep -q "pid $LIVE is running" "$TMP/out" && ! grep -q 'looks stale' "$TMP/out" && [ -d "$L92" ] && [ "$(dist_posts)" -eq 0 ] || { cat "$TMP/out"; fail "SHD-37: a live pid is reported as running"; }
kill "$LIVE" 2>/dev/null || true; wait "$LIVE" 2>/dev/null || true
HOME="$H92" run install claude team-standards && fail "SHD-37: a dead-pid lock still stops the install"
grep -q 'looks stale' "$TMP/out" && grep -q -F "rmdir $L92" "$TMP/out" && [ -d "$L92" ] || { cat "$TMP/out"; fail "SHD-37: a dead pid prints the exact rmdir and keeps the lock"; }
rm -f "$L92/pid"
HOME="$H92" run install claude team-standards && fail "SHD-37: a lock without a pid file stops the install"
grep -q 'looks stale' "$TMP/out" && grep -q -F "rmdir $L92" "$TMP/out" && [ -d "$L92" ] || { cat "$TMP/out"; fail "SHD-37: a missing pid file looks stale"; }
rmdir "$L92"
HOME="$H92" run install claude team-standards || fail "SHD-37: after the rmdir the install works"
clean_dir "$H92/.claude/skills" || fail "SHD-37: the pid file does not block the lock release"
pass "SHD-37: a held lock reports its pid state and prints the rmdir, never removing it"

# SHD-37 (real run): the pid written by a running install is the installer's pid, and it is gone after the run
H95=$(fresh_home shd37r); D95="$H95/.claude/skills/team-standards"; L95="$D95.allye.lock"
printf 1 > "$TMP/release"; HOME="$H95" run install claude team-standards || fail "SHD-37r setup"
printf 2 > "$TMP/release"; rm -f "$TMP/kill.pid" "$TMP/mv-hang.flag"
MV_HANG_FLAG="$TMP/mv-hang.flag" PATH="$SHIMS/mv-hang-after:$PATH" HOME="$H95" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards >"$TMP/kill.out" 2>&1 &
for _ in $(seq 1 100); do [ -s "$TMP/mv-hang.flag" ] && break; sleep 0.2; done
[ -s "$TMP/mv-hang.flag" ] || fail "SHD-37r: the run reached the publish"
kpid=$(cat "$TMP/kill.pid")
[ "$(cat "$L95/pid" 2>/dev/null)" = "$kpid" ] || { ls -la "$L95"; fail "SHD-37r: the lock's pid file holds the installer's pid ($kpid)"; }
printf 1 > "$TMP/release"; HOME="$H95" run install claude team-standards && fail "SHD-37r: a second install stops on the held lock"
grep -q "pid $kpid is running" "$TMP/out" && ! grep -q 'looks stale' "$TMP/out" || { cat "$TMP/out"; fail "SHD-37r: the second install reports the running pid"; }
kill -TERM -- "-$kpid" 2>/dev/null || true
for _ in $(seq 1 50); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
[ ! -e "$L95" ] && [ ! -e "$L95/pid" ] && clean_dir "$H95/.claude/skills" || fail "SHD-37r: lock and pid are gone after the run"
pass "SHD-37r: a real run records its pid, a second run sees it, both vanish with the run"

# SHD-41/42/43: stale-lock message
H96="$TMP/h shd42 'q"; mkdir -p "$H96/.claude/skills"; L96="$H96/.claude/skills/team-standards.allye.lock"
mkdir "$L96"; printf '1\n' > "$L96/pid"
HOME="$H96" run install claude team-standards && fail "SHD-43: pid 1 does not count as a running install"
grep -q 'looks stale' "$TMP/out" && ! grep -q 'pid [01] is running' "$TMP/out" && grep -q 'first instants' "$TMP/out" || { cat "$TMP/out"; fail "SHD-43: pid 1 is stale and the message mentions the first instants"; }
cmd=$(sed -n 's/.*remove it with: \(.*\) and rerun\..*/\1/p' "$TMP/out")
[ -n "$cmd" ] && ! grep -q "rmdir '" "$TMP/out" || { cat "$TMP/out"; fail "SHD-42: the command is not wrapped in raw single quotes"; }
(eval "$cmd") && [ ! -e "$L96" ] || { echo "$cmd"; fail "SHD-42: the printed command removes exactly the lock (path with space and quote)"; }
mkdir "$L96"; printf '0\n' > "$L96/pid"
HOME="$H96" run install claude team-standards && fail "SHD-43: pid 0 stops the install"
grep -q 'looks stale' "$TMP/out" || fail "SHD-43: pid 0 is stale"
rmdir_cmd=$(sed -n 's/.*remove it with: \(.*\) and rerun\..*/\1/p' "$TMP/out"); (eval "$rmdir_cmd")
pass "SHD-42/SHD-43: stale-lock command is shell-quoted and pids below 2 look stale"

# SHD-44: a rejected complete never deletes what is at the skill path unless this run published it
for variant in userdir symlink; do
  H97=$(fresh_home shd44-$variant); D97="$H97/.claude/skills/team-standards"
  printf 1 > "$TMP/release"; mode normal; HOME="$H97" run install claude team-standards || fail "SHD-44 setup"
  printf 2 > "$TMP/release"; mode reject-complete; printf 1 > "$TMP/hold-complete"; reset_calls; rm -f "$TMP/kill.pid"
  HOME="$H97" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards >"$TMP/kill.out" 2>&1 &
  for _ in $(seq 1 100); do calls | grep -q '/complete' && break; sleep 0.2; done
  calls | grep -q '/complete' || fail "SHD-44 $variant: the run reached complete"
  rm -rf "$D97"
  if [ "$variant" = userdir ]; then mkdir "$D97"; printf 'mine\n' > "$D97/notes.txt"; else mkdir "$H97/elsewhere"; printf 'mine\n' > "$H97/elsewhere/notes.txt"; ln -s "$H97/elsewhere" "$D97"; fi
  printf 0 > "$TMP/hold-complete"
  kpid=$(cat "$TMP/kill.pid")
  for _ in $(seq 1 100); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
  rm -f "$TMP/hold-complete"; mode normal; printf 1 > "$TMP/release"
  [ "$(cat "$D97/notes.txt" 2>/dev/null)" = mine ] && { [ "$variant" = userdir ] || [ -L "$D97" ]; } || { cat "$TMP/kill.out"; fail "SHD-44 $variant: the rejected-complete rollback left the user's path alone"; }
  rm -rf "$H97/.claude/skills"/team-standards.allye.previous.*
done
pass "SHD-44: COMPLETION_REJECTED applies the symlink and operation_id guard"

# SHD-45: clean_text is stable against recomposition
got=$(clean_text "a$(printf '\342\342\200\213\200\213')b"); [ "$got" = ab ] || { printf '%s' "$got" | od -c | head; fail "SHD-45: nested zero-width bytes recompose into one and are removed"; }
got=$(clean_text "a$(printf '\302\302\233\233')b"); [ "$got" = ab ] || { printf '%s' "$got" | od -c | head; fail "SHD-45: nested C1 bytes are removed"; }
for depth in 5 6 16; do
  zw=$(printf '\342\200\213'); c1=$(printf '\302\233'); zwo=$(printf '\342'); zwt=$(printf '\200\213'); c1o=$(printf '\302'); c1t=$(printf '\233')
  for _ in $(seq 2 "$depth"); do zw="$zwo$zw$zwt"; c1="$c1o$c1$c1t"; done
  got=$(clean_text "a${zw}b"); [ "$got" = ab ] || { printf '%s' "$got" | od -c | head; fail "SHD-45: $depth-deep zero-width nesting is fully removed"; }
  got=$(clean_text "a${c1}b"); [ "$got" = ab ] || { printf '%s' "$got" | od -c | head; fail "SHD-45: $depth-deep C1 nesting is fully removed"; }
done
pass "SHD-45: clean_text repeats until stable"

# SHD-46: clean_text is bounded: input cut to 2048 bytes, at most 16 passes, placeholder over the cap
nest() { local o=$1 t=$2 core=$3 d=$4 r="$3"; for _ in $(seq 2 "$d"); do r="$o$r$t"; done; printf '%s' "$r"; }
zwc=$(printf '\342\200\213'); c1c=$(printf '\302\233')
no_bad() { ! printf '%s' "$1" | LC_ALL=C grep -qaP '\xe2\x80\x8b|\xc2[\x80-\x9f]'; }
for kind in zw c1; do
  if [ "$kind" = zw ]; then o=$(printf '\342'); t=$(printf '\200\213'); core=$zwc; else o=$(printf '\302'); t=$(printf '\233'); core=$c1c; fi
  for depth in 5000; do
    deep=$(nest "$o" "$t" "$core" 2000)
    start=$SECONDS; got=$(clean_text "a${deep}b"); el=$((SECONDS-start))
    [ "$el" -le 5 ] || fail "SHD-46: $kind depth-2000 took ${el}s (unbounded)"
    no_bad "$got" || fail "SHD-46: $kind deep output still holds zero-width/C1 bytes"
    [ "${#got}" -le 2060 ] || fail "SHD-46: $kind deep output is bounded in size"
  done
  got=$(clean_text "a$(nest "$o" "$t" "$core" 20)b"); [ "$got" = "[unprintable]" ] || { printf '%s' "$got" | od -c | head -3; fail "SHD-46: $kind over-cap nesting (depth 20) prints only the placeholder"; }
  chunk=$(nest "$o" "$t" "$core" 300); big=$(for _ in $(seq 1 120); do printf '%s' "$chunk"; done)
  start=$SECONDS; got=$(clean_text "$big"); el=$((SECONDS-start))
  [ "$el" -le 5 ] || fail "SHD-46: $kind 100KB string took ${el}s"
  no_bad "$got" || fail "SHD-46: $kind 100KB output holds bad bytes"
done
got=$(clean_text "$(printf 'a%.0s' $(seq 1 5000))"); [ "${#got}" -le 2060 ] && [ "${got%...}" != "$got" ] || fail "SHD-46: long input is cut to 2048 bytes plus an ellipsis"
got=$(clean_text "$(printf '\303\251\342\202\254\346\274\242\345\255\227')"); [ "$got" = "$(printf '\303\251\342\202\254\346\274\242\345\255\227')" ] || fail "SHD-46: legitimate UTF-8 survives"
pass "SHD-46: clean_text is bounded in time and size, and prints a placeholder over the pass cap"

# SHD-47: installer-built path messages are never cut by the 2048-byte server-string bound; the cut trims orphan UTF-8 bytes
seg=$(printf 'd%.0s' $(seq 1 200)); H97L="$TMP/h-shd47"
for _ in 1 2 3 4 5 6 7; do H97L="$H97L/$seg"; done
mkdir -p "$H97L/.claude/skills"; L97="$H97L/.claude/skills/team-standards.allye.lock"; mkdir "$L97"; printf '1\n' > "$L97/pid"
[ "${#L97}" -gt 1400 ] || fail "SHD-47 setup: lock path is long"
HOME="$H97L" run install claude team-standards && fail "SHD-47: a stale lock stops the install"
grep -q 'looks stale' "$TMP/out" && grep -q -F "rmdir $L97" "$TMP/out" && ! grep -q -F '...' "$TMP/out" || { cut -c1-300 "$TMP/out"; fail "SHD-47: a ~1500-char lock path gets a complete rmdir hint with no ellipsis"; }
cmd=$(sed -n 's/.*remove it with: \(.*\) and rerun\..*/\1/p' "$TMP/out"); (eval "$cmd") && [ ! -e "$L97" ] || fail "SHD-47: the printed command removes the long lock"
rm -rf "$TMP/h-shd47"
got=$(clean_text "$(printf 'a%.0s' $(seq 1 5000))" 20480); [ "${#got}" -eq 5000 ] || fail "SHD-47: a 5000-byte message is not cut under the larger bound"
start=$SECONDS; got=$(clean_text "a$(nest "$(printf '\342')" "$(printf '\200\213')" "$zwc" 2000)b" 20480); el=$((SECONDS-start))
[ "$el" -le 5 ] && no_bad "$got" || fail "SHD-47: hostile nested input stays bounded and clean under the larger bound"
big=$(nest "$(printf '\342')" "$(printf '\200\213')" "$zwc" 40000); start=$SECONDS; got=$(clean_text "$big" 20480); el=$((SECONDS-start))
[ "$el" -le 5 ] && no_bad "$got" || fail "SHD-47: a 100KB hostile string stays bounded and clean under the larger bound"
got=$(clean_text "$(printf 'a%.0s' $(seq 1 5000))"); [ "${#got}" -eq 2051 ] || fail "SHD-47: a server string is still cut at 2048 by default"
if command -v iconv >/dev/null 2>&1; then
  got=$(clean_text "$(printf 'a%.0s' $(seq 1 2046))$zwc"); tail3=$(printf '%s' "$got" | LC_ALL=C tail -c 5)
  [ "$tail3" = "aa..." ] && [ "$(printf '%s' "$got" | wc -c)" -eq 2049 ] || { printf '%s' "$got" | tail -c 8 | od -c; fail "SHD-47: an incomplete UTF-8 tail is trimmed before the ellipsis"; }
else printf 'SKIP SHD-47: iconv missing\n'; fi
pass "SHD-47: path messages keep the full path, server strings stay cut at 2048, incomplete UTF-8 tails are trimmed"

# SHD-38: the signal handler never deletes a directory this run did not publish
H93=$(fresh_home shd38); D93="$H93/.claude/skills/team-standards"
printf 1 > "$TMP/release"; HOME="$H93" run install claude team-standards || fail "SHD-38 setup"
printf 2 > "$TMP/release"; rm -f "$TMP/kill.pid" "$TMP/mv-hang.flag"
MV_HANG_FLAG="$TMP/mv-hang.flag" PATH="$SHIMS/mv-hang-after:$PATH" HOME="$H93" setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$TMP/kill.pid" "$ROOT/install.sh" install claude team-standards >"$TMP/kill.out" 2>&1 &
for _ in $(seq 1 100); do [ -s "$TMP/mv-hang.flag" ] && break; sleep 0.2; done
[ -s "$TMP/mv-hang.flag" ] || fail "SHD-38: the run reached the publish"
rm -rf "$D93"; mkdir "$D93"; printf 'mine\n' > "$D93/notes.txt"
kpid=$(cat "$TMP/kill.pid"); kill -TERM -- "-$kpid" 2>/dev/null || true
for _ in $(seq 1 50); do kill -0 "$kpid" 2>/dev/null || break; sleep 0.2; done
printf 1 > "$TMP/release"
[ "$(cat "$D93/notes.txt" 2>/dev/null)" = mine ] || { cat "$TMP/kill.out"; fail "SHD-38: a directory the user created at the skill path survives the signal"; }
rm -rf "$H93/.claude/skills"/team-standards.allye.previous.*
pass "SHD-38: the signal handler only deletes the tree this run published"

# SHD-39: a leftover .allye.previous.* is reported at the start of a run, and kept
H94=$(fresh_home shd39); S94="$H94/.claude/skills"; mkdir -p "$S94/team-standards.allye.previous.4242"
HOME="$H94" run install claude team-standards || { cat "$TMP/out"; fail "SHD-39: a leftover previous does not block"; }
grep -q -F "$S94/team-standards.allye.previous.4242" "$TMP/out" && [ -d "$S94/team-standards.allye.previous.4242" ] || { cat "$TMP/out"; fail "SHD-39: the leftover previous is reported and kept"; }
rm -rf "$S94/team-standards.allye.previous.4242"; clean_dir "$S94" || fail "SHD-39: NFR-02 holds after removing the reported entry"
pass "SHD-39: a leftover .allye.previous.* is reported at the start of the run"

# unknown runtime
run install cursor team-standards && fail "unknown runtime"
grep -q "Unknown runtime 'cursor'" "$TMP/out" || fail "unknown runtime message"
pass "removed runtimes are rejected"

# no staging dirs, locks or rollback handles are left behind
leftovers=$(find "$TMP" "${SHM:-$TMP}" \( -path "$TMP/h-ac22" -o -path "$TMP/h-ac23" -o -path "$TMP/ac20" -o -path "$TMP/ac22-snap" -o -path "$TMP/h-restorefail" -o -path "$TMP/h-killed" -o -path "$TMP/h-others" -o -path "$TMP/h-lock" -o -path "$TMP/shd06-snap" -o -path "$TMP/pi18b" \) -prune -o \
  \( -name '.allye-stage.*' -o -name '*.allye.lock' -o -name '*.allye.previous.*' -o -name '.allye-backup.*' \) -print)
[ -z "$leftovers" ] || fail "leftovers: $leftovers"
pass "NFR-02: no stage, lock, previous or backup leftovers across all modes (except the printed-path cases)"

echo "installer: ok"
