#!/bin/bash
# Assertions for hooks/live-report.sh (Claude Code Live reporter), hooks/lib/credential.sh and the
# route/host pin across the three ALLY-195/203 scripts. No framework: this script is the harness.
#
# Sandbox (NFR-03): every case gets its own HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME and
# CLAUDE_PLUGIN_DATA in a temp dir and its own loopback fake API (hooks/test/fake-hooks-api.mjs, run
# by node here only). The scripts under test run with `env -i`, a PATH of logging shims
# (hooks/test/shims) followed by symlinks to the real tools and no `node`. The curl shim refuses
# non-loopback hosts and logs argv, environment and the url/limit lines of its config. Tokens are
# throwaway fakes; no real credential is ever read.
set -u

# Optional section filter (ALY-258.1): LIVE_TEST_SECTIONS is an extended regex over the section names, i.e. the text of the
# `echo "== NAME =="` lines. When set, a copy of this file is run holding the setup, the sections whose name matches, the
# `#@always` blocks (shared helpers) and the final tally. Unset: the whole file runs as always. A selected section may use
# helpers that an earlier, unselected section defines: select those together (the activity sections share their helpers).
if [ -n "${LIVE_TEST_SECTIONS:-}" ] && [ -z "${LIVE_TEST_FILTERED:-}" ]; then
  _self="${BASH_SOURCE[0]}"; _dir="$(cd "$(dirname "$_self")" && pwd)"
  _tmp=$(mktemp "${TMPDIR:-/tmp}/live-test-filtered.XXXXXX") || exit 1
  awk -v re="$LIVE_TEST_SECTIONS" '
    BEGIN { keep = 1 }
    /^echo "== / { n = $0; sub(/^echo "== /, "", n); sub(/ ==".*$/, "", n); keep = (n ~ re) }
    /^#@always/ { keep = 1 }
    /^echo "\$PASS passed/ { keep = 1 }
    keep { print }' "$_self" >"$_tmp" && [ -s "$_tmp" ] && grep -q '^echo "== ' "$_tmp" || { echo "live test filter: could not build the filtered copy" >&2; rm -f "$_tmp"; exit 1; }
  LIVE_TEST_FILTERED=1 LIVE_TEST_DIR="$_dir" bash "$_tmp"; _rc=$?
  rm -f "$_tmp"; exit "$_rc"
fi

SCRIPT_DIR="${LIVE_TEST_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
HOOK="$SCRIPT_DIR/live-report.sh"
LIB="$SCRIPT_DIR/lib/credential.sh"
PAIRHOOK="$SCRIPT_DIR/allye-hooks.sh"
PREFHOOK="$SCRIPT_DIR/session-preferences.sh"
SHIMS="$SCRIPT_DIR/test/shims"
FAKE="$SCRIPT_DIR/test/fake-hooks-api.mjs"
NODE_BIN="$(type -P node)"
BASH_BIN="$(type -P bash)"
CURL_BIN="$(type -P curl)"
JQ_BIN="$(type -P jq)"
PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1))
  fi
}
contains() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }

ROOT_TMP="$(mktemp -d)"
APID=""
FAKE_WAIT_PID=""
# TRACK (ALY-217): "<pid> <start>" of every fake owner and watcher a case started; at exit each is killed only while that
# pid still has that start time (never by name), so a failing run leaves no process behind.
TRACK=()
cleanup() {
  local e p s
  for e in ${TRACK[@]+"${TRACK[@]}"}; do
    p=${e%% *}; s=${e#* }
    [[ "$p" =~ ^[0-9]+$ ]] && [[ "$s" =~ ^[0-9]+$ ]] && [ "$(pstart "$p")" = "$s" ] && kill "$p" 2>/dev/null
  done
  for e in "$ROOT_TMP"/case*/plugindata; do final_reap "$e"; done
  [ -z "$APID" ] || kill "$APID" 2>/dev/null; [ -z "$FAKE_WAIT_PID" ] || kill "$FAKE_WAIT_PID" 2>/dev/null; rm -rf "$ROOT_TMP"
}
trap cleanup EXIT

make_realbin() {  # $1 = dir, rest = tools to leave out. node and stat are deliberately absent.
  local dir="$1" t p; shift
  mkdir -p "$dir"
  for t in bash curl jq sha256sum shasum od find mktemp mv uname tr id rm chmod mkdir cat dirname sleep grep sed cut head env date git timeout wc tail; do
    case " $* " in *" $t "*) continue ;; esac
    p=$(type -P "$t") && ln -s "$p" "$dir/$t"
  done
}
link_shims() { local dir="$1" s; shift; mkdir -p "$dir"; for s in "$SHIMS"/*; do case " $* " in *" $(basename "$s") "*) continue ;; esac; ln -s "$s" "$dir/$(basename "$s")"; done; }
REALBIN="$ROOT_TMP/realbin";             make_realbin "$REALBIN"
REALBIN_NOCURL="$ROOT_TMP/realbin-nc";   make_realbin "$REALBIN_NOCURL" curl
REALBIN_NOJQ="$ROOT_TMP/realbin-nj";     make_realbin "$REALBIN_NOJQ" jq
REALBIN_NOSHA="$ROOT_TMP/realbin-nosha"; make_realbin "$REALBIN_NOSHA" sha256sum shasum
REALBIN_NOTO="$ROOT_TMP/realbin-nto";    make_realbin "$REALBIN_NOTO" timeout
# ALY-217: the same tools, with a sleep that logs its argument to $SHIM_LOG/sleep.log (the sleeper's wait is S.mmm).
REALBIN_SL="$ROOT_TMP/realbin-sl";       make_realbin "$REALBIN_SL" sleep
printf '#!%s\nprintf "sleep %%s\\n" "$*" >>"${SHIM_LOG:?}/sleep.log"\nexec %s "$@"\n' "$BASH_BIN" "$(type -P sleep)" >"$REALBIN_SL/sleep"; chmod +x "$REALBIN_SL/sleep"
SHIMS_NOCURL="$ROOT_TMP/shims-nc";       link_shims "$SHIMS_NOCURL" curl
SHIMS_NOJQ="$ROOT_TMP/shims-nj";         link_shims "$SHIMS_NOJQ" jq
SHIMS_NOSHA="$ROOT_TMP/shims-nosha";     link_shims "$SHIMS_NOSHA" sha256sum shasum
# The default shim dir of a case: curl is a stub that fails at once, so the (detached) flush of every spool-oriented
# test leaves the spool as it is. The ALY-203.6 tests switch to the real logging curl shim with SHIMD="$SHIMS".
SHIMS_STUB="$ROOT_TMP/shims-stub";       link_shims "$SHIMS_STUB" curl
printf '#!/bin/bash\ncat >/dev/null\nprintf "curl [stub]\\n" >>"${SHIM_LOG:?}/calls.log"\nexit 7\n' >"$SHIMS_STUB/curl"; chmod +x "$SHIMS_STUB/curl"

TOKEN="alyh_$(printf 'Ab1_-%.0s' $(seq 1 8))xyz"    # 5*8+3 = 43 characters

N=0
new_case() {
  N=$((N + 1)); SB="$ROOT_TMP/case$N"
  mkdir -p "$SB/home" "$SB/config" "$SB/cache" "$SB/log" "$SB/api"
  DATA="$SB/plugindata"; CRED="$DATA/hook-credential.json"
  REAL="$REALBIN"; SHIMD="$SHIMS_STUB"; RUN_ENV=(); DATA_ENV="$DATA"
  : >"$SB/api/requests.log"
  "$NODE_BIN" "$FAKE" "$SB/api" >"$SB/api/node.log" 2>&1 &
  APID=$!
  local i; for i in $(seq 1 100); do [ -s "$SB/api/port" ] && break; sleep 0.05; done
  PORT=$(cat "$SB/api/port"); API="http://127.0.0.1:$PORT"
  printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-0001","cwd":"/tmp/x"}' >"$SB/stdin"
}
end_case() { fake_wait_off; final_reap "$DATA"; [ -z "$APID" ] || { kill "$APID" 2>/dev/null; wait "$APID" 2>/dev/null; APID=""; }; }
# final_reap DATADIR (ALY-217.7): a final flusher still running under DATADIR is killed by the pid its final.lock records,
# only while that pid has the recorded start time (never by name); it removes its own lock on the way out.
final_reap() {
  local d p s
  for d in "$1"/live/*.final.lock; do
    [ -d "$d" ] || continue
    p=""; s=""; { read -r p s <"$d/p"; } 2>/dev/null
    [[ "$p" =~ ^[0-9]+$ ]] && [[ "$s" =~ ^[0-9]+$ ]] && [ "$(pstart "$p")" = "$s" ] && kill "$p" 2>/dev/null
  done
  return 0
}

mkcred() {  # [apiUrl]: private data dir and credential file (throwaway fake token)
  mkdir -p "$DATA" && chmod 700 "$DATA"
  "$JQ_BIN" -n --arg t "$TOKEN" --arg u "${1-$API}" '{token:$t, email:"dev@example.test", tenantName:"Acme Org", deviceName:"laptop", apiUrl:$u, absoluteExpiresAt:"2026-12-01T00:00:00.000Z", pairedAt:"2026-01-01T00:00:00Z"}' >"$CRED"
  chmod 600 "$CRED"
}

# run_script SCRIPT [ARGS...]: runs a script in the sandbox with $SB/stdin on stdin; sets OUT, ERR, RC.
run_script() {
  local script="$1"; shift
  env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" \
    ${DATA_ENV:+CLAUDE_PLUGIN_DATA="$DATA_ENV"} \
    PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REAL" \
    ${RUN_ENV[@]+"${RUN_ENV[@]}"} "$BASH_BIN" "$script" "$@" <"$SB/stdin" >"$SB/out" 2>"$SB/err"
  RC=$?
  [ "$script" != "$HOOK" ] || wait_idle
  OUT=$(cat "$SB/out"); ERR=$(cat "$SB/err")
}
# wait_idle: the flusher and the delayed-flush sleeper (ALY-217) are detached; the flush lock and flush.wait are taken
# before the hook returns, so "no flush lock and no flush.wait" = done. A flush.wait held by the harness's own fake
# holder ($FAKE_WAIT_PID) is ignored.
wait_idle() {
  local i w p busy
  for i in $(seq 1 400); do
    busy=0
    compgen -G "$DATA/live/*.flush.lock" >/dev/null && busy=1
    for w in "$DATA"/live/*.flush.wait; do
      [ -e "$w" ] || continue
      p=""; { read -r p _ <"$w/p"; } 2>/dev/null
      [ -n "$FAKE_WAIT_PID" ] && [ "$p" = "$FAKE_WAIT_PID" ] && continue
      busy=1
    done
    [ "$busy" = 0 ] && return 0
    sleep 0.05
  done
}
# pstart PID: the start time of PID (field 22 of /proc/PID/stat), as the reporter records it.
pstart() { local l; [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1; { IFS= read -r l <"/proc/$1/stat"; } 2>/dev/null || return 1; l=${l##*) }; set -- $l; [ -n "${20:-}" ] || return 1; printf '%s' "${20}"; }
# fake_wait_on: a live process of the harness holds $RAWSID's flush.wait, so no hook can arm a sleeper; fake_wait_off ends it.
fake_wait_on() {
  local d="$DATA/live/$(test_sha "$RAWSID").flush.wait"
  sleep 300 & FAKE_WAIT_PID=$!
  mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; mkdir "$d"; printf '%s %s' "$FAKE_WAIT_PID" "$(pstart "$FAKE_WAIT_PID")" >"$d/p"
}
fake_wait_off() {
  [ -n "$FAKE_WAIT_PID" ] || return 0
  kill "$FAKE_WAIT_PID" 2>/dev/null; wait "$FAKE_WAIT_PID" 2>/dev/null; FAKE_WAIT_PID=""
  rm -rf "$DATA/live/$(test_sha "$RAWSID").flush.wait"
}
run_hook() { run_script "$HOOK"; }
curl_calls() { [ -f "$SB/log/calls.log" ] && { grep -c '^curl' "$SB/log/calls.log" || true; } || echo 0; }
reqs() { wc -l <"$SB/api/requests.log" | tr -d ' '; }
# snapshot DIR: every path with its mode, plus the content checksum of every file.
snapshot() {
  [ -e "$1" ] || [ -L "$1" ] || { echo "(absent)"; return; }
  find "$1" -printf '%p %m %y\n' 2>/dev/null | sort
  find "$1" -type f -exec cksum {} + 2>/dev/null | sort
}

# expect_inert LABEL: exit 0, nothing printed, no request, no curl, no change under CLAUDE_PLUGIN_DATA.
expect_inert() {
  check "$1: exits 0" "0" "$RC"
  check "$1: stdout empty" "" "$OUT"
  check "$1: stderr empty" "" "$ERR"
  check "$1: no curl call" "0" "$(curl_calls)"
  check "$1: no request reached the API" "0" "$(reqs)"
  check "$1: no file or directory created or changed in CLAUDE_PLUGIN_DATA" "$BEFORE" "$(snapshot "$DATA")"
  check "$1: no live directory" "no" "$([ -e "$DATA/live" ] && echo yes || echo no)"
}

echo "== environment =="
check "node is not on the hook PATH" "" "$(env -i PATH="$SHIMS:$REALBIN" "$BASH_BIN" -c 'command -v node')"
check "the reporter exists and is executable" "yes" "$([ -x "$HOOK" ] && echo yes || echo no)"
check "the credential helper exists" "yes" "$([ -f "$LIB" ] && echo yes || echo no)"
for s in "$HOOK" "$LIB" "$0"; do check "bash -n $(basename "$s")" "0" "$("$BASH_BIN" -n "$s" 2>/dev/null; echo $?)"; done

# ─── credential helper lock (D-10) ──────────────────────────────────────────
echo "== credential helper =="
fn_body() {  # FILE NAME: the text of function NAME (column-0 definition, one-line or up to a column-0 "}")
  awk -v n="$2" '
    $0 ~ "^" n "\\(\\)" { print; if ($0 ~ /\}[ \t]*$/) exit; inf = 1; next }
    inf { print; if ($0 ~ /^\}/) exit }' "$1"
}
for f in valid_dir_arg safe_file have_sha sha_hex valid_api_url; do
  lib_body=$(fn_body "$LIB" "$f")
  check "$f: defined in the helper" "yes" "$([ -n "$lib_body" ] && echo yes || echo no)"
  check "$f: body identical to allye-hooks.sh" "$(fn_body "$PAIRHOOK" "$f")" "$lib_body"
done
check "valid_api_url: body identical to the mirror in session-preferences.sh" "$(fn_body "$PREFHOOK" valid_api_url)" "$(fn_body "$LIB" valid_api_url)"
check "the helper defines exactly the six functions (sourcing prints nothing, runs nothing)" \
  "have_sha load_live_credential safe_file sha_hex valid_api_url valid_dir_arg" \
  "$(env -i PATH="$REALBIN" "$BASH_BIN" -c ". '$LIB' && declare -F | sed 's/^declare -f //' | tr '\n' ' ' | sed 's/ \$//'" 2>&1)"
check "the helper has no top-level set, exit or command" "0" "$(grep -cE '^(set|exit|trap|umask|[A-Za-z_]+=)' "$LIB" || true)"

# lcc DIR: load_live_credential in a clean shell; prints "rc|token-ok|api".
lcc() {
  env -i PATH="$REALBIN" "$BASH_BIN" -c ". '$LIB'; UID_NOW=\$(id -u); LC_ALL=C
    out=\$(load_live_credential '$1' 2>&1); echo \"[\$out]\"
    load_live_credential '$1'; rc=\$?; echo \"\$rc|\${LIVE_TOKEN:-}|\${LIVE_API:-}\"" 2>&1 | tr '\n' ' '
}
new_case; mkcred
check "load_live_credential: valid credential sets LIVE_TOKEN and LIVE_API, silent" "[] 0|$TOKEN|$API " "$(lcc "$DATA")"
chmod 644 "$CRED"
check "load_live_credential: group/other readable file refused" "[] 1|| " "$(lcc "$DATA")"
chmod 600 "$CRED"; chmod 755 "$DATA"
check "load_live_credential: directory not 0700 refused" "[] 1|| " "$(lcc "$DATA")"
chmod 700 "$DATA"
check "load_live_credential: relative directory refused" "[] 1|| " "$(lcc "plugindata")"
mkcred "https://evil.example"
check "load_live_credential: URL outside the fixed list refused" "[] 1|| " "$(lcc "$DATA")"
mkcred; "$JQ_BIN" '.token = "alyh_short"' "$CRED" >"$SB/c.json" && cat "$SB/c.json" >"$CRED"
check "load_live_credential: malformed token refused" "[] 1|| " "$(lcc "$DATA")"
mkcred; ln -s "$CRED" "$SB/link.json"; mv "$DATA" "$SB/real"; ln -s "$SB/real" "$DATA"
check "load_live_credential: symlinked directory refused" "[] 1|| " "$(lcc "$DATA")"
rm "$DATA"; mv "$SB/real" "$DATA"; rm -f "$CRED"; ln -s "$SB/link.json" "$CRED"
check "load_live_credential: symlinked credential refused" "[] 1|| " "$(lcc "$DATA")"
rm -f "$CRED"
check "load_live_credential: missing credential refused" "[] 1|| " "$(lcc "$DATA")"
end_case

#@always
# ─── helpers for spooled events (ALY-203.2) ─────────────────────────────────
FIX="$SCRIPT_DIR/fixtures/live"
RAWSID="RAWSESSION-7f3a9c1e-0b2d-4e11-9a55-c0ffee123456"   # session_id of every fixture
MARKERS=(MARKER_PROMPT_xyz MARKER_CMD MARKER_PATH MARKER_MSG MARKER_LASTMSG MARKER_BRANCH MARKER_CWD MARKER_TRANSCRIPT MARKER_ARGS MARKER_RESPONSE MARKER_TITLE MARKER_MODEL MARKER_SOURCE MARKER_TYPE MARKER_ERR MARKER_REASON MARKER_AGENT MARKER_ABCDEF MARKER_NewEvent)
test_sha() { if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -d' ' -f1; else printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; fi; }
DEFAULT_SID="sess-0001"
spool_of() { echo "$DATA/live/$(test_sha "$1").spool"; }
# spooled SID: the spool lines without their `at` and `seq`, compact, one per line ("" when no spool).
spooled() { local f; f=$(spool_of "${1:-$RAWSID}"); [ -f "$f" ] && "$JQ_BIN" -cS 'del(.at, .seq)' "$f" || true; }
# run_fixture NAME...: feeds each fixture in order on stdin (same session), sets OUT/ERR/RC of the last.
run_fixture() { local n; for n in "$@"; do cp "$FIX/$n.json" "$SB/stdin"; run_hook; done; }
expected_of() { local n; for n in "$@"; do cat "$FIX/$n.expect"; done; }
# expect_fixture NAME: a fresh sandbox, the fixture alone -> exactly its .expect events and nothing else.
expect_fixture() {
  new_case; mkcred; run_fixture "$1"
  check "$1: exits 0, silent" "0||" "$RC|$OUT|$ERR"
  check "$1: spools exactly the listed events" "$(expected_of "$1" | "$JQ_BIN" -cS .)" "$(spooled)"
  check "$1: the flush reached no API (the stub curl fails; no request arrived)" "0" "$(reqs)"
  end_case
}
# expect_spooled LABEL: the discriminating counterpart of an inert case: same default payload, condition removed.
expect_spooled() {
  check "$1 (condition removed): exits 0, silent" "0||" "$RC|$OUT|$ERR"
  check "$1 (condition removed): the event is spooled" '{"state":"working","type":"state"}' "$(spooled "$DEFAULT_SID")"
}

# ─── inert paths (AC-09, BR-01, BR-03), each with its discriminating counterpart ──────
echo "== unpaired =="
new_case; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "no data directory"; mkcred; run_hook; expect_spooled "no data directory"; end_case
new_case; mkdir -p "$DATA"; chmod 700 "$DATA"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "data directory without credential"; mkcred; run_hook; expect_spooled "data directory without credential"; end_case
new_case; DATA_ENV=""; mkcred; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "CLAUDE_PLUGIN_DATA unset"; DATA_ENV="$DATA"; run_hook; expect_spooled "CLAUDE_PLUGIN_DATA unset"; end_case
new_case; mkcred; DATA_ENV="relative/dir"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "CLAUDE_PLUGIN_DATA relative"; DATA_ENV="$DATA"; run_hook; expect_spooled "CLAUDE_PLUGIN_DATA relative"; end_case
new_case; mkcred; DATA_ENV='${CLAUDE_PLUGIN_DATA}/x'; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "CLAUDE_PLUGIN_DATA unexpanded"; DATA_ENV="$DATA"; run_hook; expect_spooled "CLAUDE_PLUGIN_DATA unexpanded"; end_case
new_case; mkcred; chmod 644 "$CRED"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "credential file readable by others"; chmod 600 "$CRED"; run_hook; expect_spooled "credential file readable by others"; end_case
new_case; mkcred "https://evil.example"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "credential URL outside the fixed list"; mkcred; run_hook; expect_spooled "credential URL outside the fixed list"; end_case
new_case; mkcred; "$JQ_BIN" 'del(.token)' "$CRED" >"$SB/c.json" && cat "$SB/c.json" >"$CRED"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "credential without a token"; mkcred; run_hook; expect_spooled "credential without a token"; end_case
new_case; mkcred; chmod 755 "$DATA"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "data directory not 0700"; chmod 700 "$DATA"; run_hook; expect_spooled "data directory not 0700"; end_case

echo "== switched off and marked disabled =="
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/off"; BEFORE=$(snapshot "$DATA")
run_hook
check "live off flag: exits 0" "0" "$RC"; check "live off flag: stdout empty" "" "$OUT"; check "live off flag: stderr empty" "" "$ERR"
check "live off flag: no curl, no request" "0 0" "$(curl_calls) $(reqs)"
check "live off flag: nothing changed in CLAUDE_PLUGIN_DATA" "$BEFORE" "$(snapshot "$DATA")"
rm "$DATA/live/off"; run_hook; expect_spooled "live off flag"
end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/disabled"; BEFORE=$(snapshot "$DATA")
run_hook
check "disabled marker: exits 0" "0" "$RC"; check "disabled marker: stdout empty" "" "$OUT"; check "disabled marker: stderr empty" "" "$ERR"
check "disabled marker: no curl, no request" "0 0" "$(curl_calls) $(reqs)"
check "disabled marker: nothing changed in CLAUDE_PLUGIN_DATA" "$BEFORE" "$(snapshot "$DATA")"
rm "$DATA/live/disabled"; run_hook; expect_spooled "disabled marker"
end_case

echo "== missing tools =="
new_case; mkcred; REAL="$REALBIN_NOJQ"; SHIMD="$SHIMS_NOJQ"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "jq missing"; REAL="$REALBIN"; SHIMD="$SHIMS_STUB"; run_hook; expect_spooled "jq missing"; end_case
new_case; mkcred; REAL="$REALBIN_NOCURL"; SHIMD="$SHIMS_NOCURL"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "curl missing"; REAL="$REALBIN"; SHIMD="$SHIMS_STUB"; run_hook; expect_spooled "curl missing"; end_case
new_case; mkcred; REAL="$REALBIN_NOSHA"; SHIMD="$SHIMS_NOSHA"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "SHA-256 tool missing"; REAL="$REALBIN"; SHIMD="$SHIMS_STUB"; run_hook; expect_spooled "SHA-256 tool missing"; end_case

echo "== enabled: spools, flush with a failing curl keeps the spool, seq on each line (positive control) =="
new_case; mkcred; run_hook
check "paired and on: exits 0" "0" "$RC"
check "paired and on: stdout empty" "" "$OUT"
check "paired and on: stderr empty" "" "$ERR"
check "paired and on: one flush attempt through the stub curl, no request reached an API" "1 0" "$(curl_calls) $(reqs)"
check "paired and on: the event is spooled, keyed by the hash" '{"state":"working","type":"state"}' "$(spooled "$DEFAULT_SID")"
check "paired and on: live dir 0700, spool 0600, state file present" "700 600 working" \
  "$(find "$DATA/live" -maxdepth 0 -printf '%m' ) $(find "$(spool_of "$DEFAULT_SID")" -printf '%m') $(cat "${DATA}/live/$(test_sha "$DEFAULT_SID").state")"
check "paired and on: at is ISO-8601 UTC" "yes" "$("$JQ_BIN" -r '.at | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z") | if . then "yes" else "no" end' "$(spool_of "$DEFAULT_SID")")"
check "paired and on: the line carries an integer seq (Unix ms based)" "yes" "$("$JQ_BIN" -r '(.seq | type == "number" and . == floor and . >= 1000000000000) | if . then "yes" else "no" end' "$(spool_of "$DEFAULT_SID")")"
check "paired and on: token absent from outputs and shim logs" "0" "$(cat "$SB/out" "$SB/err" "$SB/log"/* 2>/dev/null | grep -cF -- "$TOKEN")"
end_case

# ─── live directory safety (Shield SHD-01 of ALY-203.1) ─────────────────────
echo "== live directory safety =="
new_case; mkcred; mkdir -p "$SB/elsewhere"; chmod 700 "$SB/elsewhere"; ln -s "$SB/elsewhere" "$DATA/live"; cp "$FIX/user-prompt-submit.json" "$SB/stdin"; run_hook
check "symlinked live dir: nothing written through it" "0|" "$(find "$SB/elsewhere" -type f | wc -l | tr -d ' ')|$OUT$ERR"; end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 755 "$DATA/live"; cp "$FIX/user-prompt-submit.json" "$SB/stdin"; run_hook
check "live dir not 0700: nothing written" "0" "$(find "$DATA/live" -type f | wc -l | tr -d ' ')"; end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; H=$(test_sha "$RAWSID"); : >"$SB/target"; ln -s "$SB/target" "$DATA/live/$H.spool"; cp "$FIX/user-prompt-submit.json" "$SB/stdin"; run_hook
check "symlinked spool: nothing written through it" "0" "$(wc -c <"$SB/target" | tr -d ' ')"; end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; H=$(test_sha "$RAWSID"); : >"$DATA/live/$H.spool"; chmod 644 "$DATA/live/$H.spool"; cp "$FIX/user-prompt-submit.json" "$SB/stdin"; run_hook
check "spool not 0600: nothing appended" "0" "$(wc -c <"$DATA/live/$H.spool" | tr -d ' ')"; end_case

# ─── event fixtures (AC-01, BR-15, D-08) ────────────────────────────────────
echo "== one fixture per event: exactly the listed events =="
for f in "$FIX"/*.json; do
  n=$(basename "$f" .json)
  [ -f "$FIX/$n.expect" ] || { check "$n: has an .expect file" "yes" "no"; continue; }
  expect_fixture "$n"
done
check "every confirmed event of the table has a fixture" "0" "$(for e in SessionStart UserPromptSubmit UserPromptExpansion PreToolUse PostToolUse PermissionRequest Notification SubagentStart SubagentStop Stop StopFailure SessionEnd; do grep -lq "\"hook_event_name\": \"$e\"" "$FIX"/*.json || echo "$e"; done | wc -l | tr -d ' ')"

# ─── AC-15 / BR-14: working before the first tool or subagent event after waiting_input ─────
echo "== waiting_input then working (AC-15) =="
seq_case() {  # LABEL EXPECT-JSON-LINES... (fixtures from $SEQ)
  local label="$1"; shift
  new_case; mkcred; run_fixture "${SEQ[@]}"
  check "$label" "$(printf "%s\n" "$@" | "$JQ_BIN" -cS .)" "$(spooled)"
  check "$label: silent, exits 0" "0||" "$RC|$OUT|$ERR"
  end_case
}
W='{"type":"state","state":"working"}'; WQ='{"type":"state","state":"waiting_input","code":"asked_question"}'; WP='{"type":"state","state":"waiting_input","code":"permission_prompt"}'
SEQ=(pre-tool-use-ask-user-question pre-tool-use pre-tool-use post-tool-use)
seq_case "AskUserQuestion then tools: working once, before the first tool; PostToolUse adds no tool event" "$WQ" "$W" '{"type":"tool","tool":"Bash"}' '{"type":"tool","tool":"Bash"}'
SEQ=(permission-request post-tool-use post-tool-use)
seq_case "PermissionRequest then PostToolUse: working only, once, no tool event" "$WP" "$W"
SEQ=(permission-request post-tool-use-subagent post-tool-use-subagent)
seq_case "PermissionRequest then PostToolUse in a subagent: working only, no sub_tool" "$WP" "$W"
SEQ=(post-tool-use post-tool-use-subagent)
seq_case "PostToolUse without waiting: nothing spooled"
SEQ=(permission-request post-tool-use-tool-space)
seq_case "waiting then a PostToolUse with a hostile tool name: working still spooled" "$WP" "$W"
SEQ=(permission-request subagent-start-bad-type subagent-start-bad-type)
seq_case "waiting then a SubagentStart failing its pattern: working spooled once, event dropped" "$WP" "$W"
SEQ=(pre-tool-use-ask-user-question pre-tool-use-subagent-bad-id)
seq_case "waiting then a subagent PreToolUse with a bad id: working spooled, event dropped" "$WQ" "$W"
SEQ=(notification-permission-prompt subagent-start subagent-start)
seq_case "permission_prompt then SubagentStart twice: working first, once; the second start of the id is not spooled (AC-36)" "$WP" "$W" '{"type":"sub_start","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}'
SEQ=(pre-tool-use-ask-user-question pre-tool-use-subagent)
seq_case "waiting then a subagent tool: working first, then the synthetic sub_start" "$WQ" "$W" '{"type":"sub_start","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}' '{"type":"sub_tool","tool":"Read","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}'
SEQ=(pre-tool-use-ask-user-question stop pre-tool-use)
seq_case "waiting then Stop then a tool: Stop leaves waiting, no working" "$WQ" '{"type":"state","state":"idle","code":"turn_ended"}' '{"type":"tool","tool":"Bash"}'
SEQ=(pre-tool-use-ask-user-question subagent-stop)
seq_case "waiting then SubagentStop: no working (not a trigger, nor is its synthetic sub_start)" "$WQ" '{"type":"sub_start","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}' '{"type":"sub_stop","sub":{"id":"agent-abc123","type":"allye:bridge-pilot","outcome":"pass","task":"ALY-1.2"}}'
SEQ=(pre-tool-use pre-tool-use)
seq_case "no waiting: no working is inserted" '{"type":"tool","tool":"Bash"}' '{"type":"tool","tool":"Bash"}'
SEQ=(permission-request pre-tool-use-tool-space pre-tool-use)
seq_case "a dropped PreToolUse still spools working once; the next tool follows" "$WP" "$W" '{"type":"tool","tool":"Bash"}'

# ─── ALY-203.3: tool reduction (BR-13) and binding sources (BR-08, AC-06) ───
echo "== tool reduction and binding fixtures =="
GIT_BIN="$(type -P git)"
git_calls() { [ -f "$SB/log/calls.log" ] && { grep '^git' "$SB/log/calls.log" || true; } || true; }
git_count() { git_calls | grep -c . || true; }
mkrepo() {  # BRANCH: a throwaway repository (the git shim wraps the real git, so real branches are used)
  rm -rf "$SB/repo"; mkdir -p "$SB/repo"
  env -i HOME="$SB/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null PATH="$REALBIN" "$GIT_BIN" init -q "$SB/repo" &&
  env -i HOME="$SB/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null PATH="$REALBIN" "$GIT_BIN" -C "$SB/repo" symbolic-ref HEAD "refs/heads/$1"
}
# cwd_pay NAME CWD: the fixture NAME with its cwd replaced (jq -n so any string, including a newline, is encoded)
cwd_pay() { "$JQ_BIN" --arg c "$2" '.cwd = $c' "$FIX/$1.json" >"$SB/stdin"; }
bind_files() { find "$DATA/live" -type f \( -name '*.spool' -o -name '*.state' -o -name '*.bind' \) -exec cat {} + 2>/dev/null; }
GITARGV_PRE="git [-c] [core.fsmonitor=] [-c] [core.hooksPath=/dev/null] [-C] ["
GITARGV_POST="] [branch] [--show-current]"
SSB='{"state":"started","type":"state"}'
# the skill-*, expansion-* and mcp-* fixtures are checked by the generic loop below

echo "== bridge invocation: every mode, with and without a key =="
for m in launch mission blueprint dispatch repair optimize shield inspect survey; do
  new_case; mkcred
  "$JQ_BIN" --arg a "$m" '.tool_input.args = $a' "$FIX/skill-bridge-no-key.json" >"$SB/stdin"; run_hook
  check "Skill tool call, mode $m, no key" "$(printf '%s\n' '{"type":"tool","tool":"Skill"}' "{\"type\":\"bind\",\"bind\":{\"source\":\"skill\",\"role\":\"bridge\",\"mode\":\"$m\"}}" | "$JQ_BIN" -cS .)" "$(spooled)"
  "$JQ_BIN" --arg a "$m ALY-12" '.command_args = $a' "$FIX/expansion-bridge-no-key.json" >"$SB/stdin"; run_hook
  check "UserPromptExpansion, mode $m, with key" "$(printf '%s\n' '{"type":"tool","tool":"Skill"}' "{\"type\":\"bind\",\"bind\":{\"source\":\"skill\",\"role\":\"bridge\",\"mode\":\"$m\"}}" "{\"type\":\"bind\",\"bind\":{\"source\":\"skill\",\"role\":\"bridge\",\"mode\":\"$m\",\"spec\":\"ALY-12\"}}" | "$JQ_BIN" -cS .)" "$(spooled)"
  end_case
done
for bad in "ALY-203.2.1" "ALY-" "A-1" "ALYALYALYALY-1" "ALY-1x" "aly-1" "ALY-203;MARKER_ARGS" ; do
  new_case; mkcred; "$JQ_BIN" --arg a "mission $bad" '.command_args = $a' "$FIX/expansion-bridge-no-key.json" >"$SB/stdin"; run_hook
  check "invalid key '$bad' is dropped, the mode stays" '{"bind":{"mode":"mission","role":"bridge","source":"skill"},"type":"bind"}' "$(spooled)"
  end_case
done
for bad in "launch2" "LAUNCH" "mission," "" "ship"; do
  new_case; mkcred; "$JQ_BIN" --arg a "$bad ALY-203" '.command_args = $a' "$FIX/expansion-bridge-no-key.json" >"$SB/stdin"; run_hook
  check "invalid mode '$bad': no bind, key not sent alone" "" "$(spooled)"
  end_case
done

echo "== environment: ALLYE_SPEC and ALLYE_TASK at SessionStart =="
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-203" "ALLYE_TASK=ALY-203.3"); run_fixture session-start-startup
check "env spec and task: bind source env, role session" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"env","role":"session","spec":"ALY-203","task":"ALY-203.3"}}' | "$JQ_BIN" -cS .)" "$(spooled)"
check "env: silent, exit 0, git not called" "0|0" "$RC|$(git_count)"
run_fixture session-start-resume
check "env: the same bind is not repeated on resume" "1" "$(spooled | grep -c '"source":"env"' || true)"
end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-8"); run_fixture session-start-startup
check "env spec only" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"env","role":"session","spec":"ALY-8"}}' | "$JQ_BIN" -cS .)" "$(spooled)"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_TASK=ALY-8.2"); run_fixture session-start-startup
check "env task only" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"env","role":"session","task":"ALY-8.2"}}' | "$JQ_BIN" -cS .)" "$(spooled)"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-203" "ALLYE_TASK=bad MARKER_ARGS"); run_fixture session-start-startup
check "env: invalid task dropped, valid spec kept" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"env","role":"session","spec":"ALY-203"}}' | "$JQ_BIN" -cS .)" "$(spooled)"
check "env: invalid value absent from every file" "0" "$(bind_files | grep -cF MARKER_ARGS || true)"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=aly-203" "ALLYE_TASK=ALY-203.3.4"); run_fixture session-start-startup
check "env: all values invalid, no bind" "$SSB" "$(spooled)"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-203"); run_fixture user-prompt-submit
check "env is evaluated at SessionStart only" '{"state":"working","type":"state"}' "$(spooled)"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-203"); run_fixture session-start-bad-source
check "env: a SessionStart that maps to nothing binds nothing" "" "$(spooled)"; end_case

echo "== branch: the safe git call (BR-08) =="
branch_case() {  # LABEL BRANCH EXPECTED-BIND-JSON-or-empty
  new_case; mkcred; mkrepo "$2"; cwd_pay session-start-startup "$SB/repo"; run_hook
  local exp="$SSB"; [ -z "$3" ] || exp=$(printf '%s\n' "$SSB" "{\"type\":\"bind\",\"bind\":$3}" | "$JQ_BIN" -cS .)
  check "$1: spool" "$exp" "$(spooled)"
  check "$1: exit 0, silent" "0||" "$RC|$OUT|$ERR"
  check "$1: git called once with exactly the safe argv" "$GITARGV_PRE$SB/repo$GITARGV_POST" "$(git_calls)"
  check "$1: branch name absent from spool, state, bind, output and logs" "0" "$( { bind_files; cat "$SB/out" "$SB/err" "$SB/log"/*; } | grep -cF MARKER_BRANCH || true)"
  end_case
}
branch_case "bridge/aly-203-live-reporter" "bridge/aly-203-live-reporter" '{"source":"branch","spec":"ALY-203"}'
branch_case "ALY-203-foo" "ALY-203-foo" '{"source":"branch","spec":"ALY-203"}'
branch_case "lower-case key" "aly-77-x" '{"source":"branch","spec":"ALY-77"}'
branch_case "task key" "bridge/aly-203.4-x" '{"source":"branch","task":"ALY-203.4"}'
branch_case "mixed-case prefix" "Bridge/Aly-9-x" '{"source":"branch","spec":"ALY-9"}'
branch_case "hostile name that matches" "bridge/aly-203-MARKER_BRANCH" '{"source":"branch","spec":"ALY-203"}'
branch_case "main" "main" ""
branch_case "feature/aly-203-x (prefix not allowed)" "feature/aly-203-x" ""
branch_case "key without trailing dash" "aly-203" ""
branch_case "hostile name that does not match" "x-MARKER_BRANCH" ""
branch_case "hostile name with a key in the middle" "MARKER_BRANCH-aly-203-x" ""
branch_case "key too long" "abcdefghijk-1-x" ""
new_case; mkcred; mkdir -p "$SB/repo"; cwd_pay session-start-startup "$SB/repo"; run_hook
check "directory that is not a repository: no bind, still silent" "0|$SSB" "$RC|$(spooled)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; cwd_pay session-start-resume "$SB/repo"; run_hook
check "branch on a resume SessionStart" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"branch","spec":"ALY-203"}}' | "$JQ_BIN" -cS .)" "$(spooled)"
run_hook
check "branch: the same bind is not repeated (git runs again, nothing sent)" "1 2" "$(spooled | grep -c '"source":"branch"' || true) $(git_count)"
end_case

echo "== git is called only at SessionStart, only with a safe cwd, only without a stronger binding =="
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"
for n in user-prompt-submit pre-tool-use stop session-end-clear notification-idle-prompt pre-tool-use-skill skill-bridge-bad-mode mcp-allye-bad-key subagent-start; do cwd_pay "$n" "$SB/repo"; run_hook; done
check "git not called for non-SessionStart events" "0" "$(git_count)"
check "no branch bind from them" "0" "$(spooled | grep -c '"source":"branch"' || true)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; cwd_pay session-start-bad-source "$SB/repo"; run_hook
check "git not called when the SessionStart maps to nothing" "0" "$(git_count)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; RUN_ENV=("ALLYE_SPEC=ALY-5"); cwd_pay session-start-startup "$SB/repo"; run_hook
check "env binding present: git not called, env bind sent" "0 1" "$(git_count) $(spooled | grep -c '"source":"env"' || true)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; run_fixture skill-bridge-spec; cwd_pay session-start-startup "$SB/repo"; run_hook
check "skill binding already sent: git not called, no branch bind" "0 0" "$(git_count) $(spooled | grep -c '"source":"branch"' || true)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; run_fixture mcp-allye-task-start-half-bad-key; cwd_pay session-start-startup "$SB/repo"; run_hook
check "mcp binding already sent: git not called" "0" "$(git_count)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; RUN_ENV=("ALLYE_SPEC=ALY-5"); cwd_pay session-start-startup "$SB/repo"; run_hook; RUN_ENV=(); cwd_pay session-start-resume "$SB/repo"; run_hook
check "env binding sent earlier in the session: git not called later" "0" "$(git_count)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; run_fixture session-start-startup; run_hook
check "cwd /work/MARKER_CWD (not a directory): git not called" "0" "$(git_count)"; end_case
for c in "relative/repo" "." "" "$(printf '/tmp\n/etc')" "$(printf '/tmp/x\ty')" "$(printf '/tmp/x\033[2J')"; do
  new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; cwd_pay session-start-startup "$c"; run_hook
  check "unsafe cwd '$(printf '%s' "$c" | tr '\n\t\033' '\\\\\\')': git not called, nothing bound" "0 $SSB" "$(git_count) $(spooled)"; end_case
done
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; "$JQ_BIN" '.cwd = 7' "$FIX/session-start-startup.json" >"$SB/stdin"; run_hook
check "non-string cwd: git not called" "0 $SSB" "$(git_count) $(spooled)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; "$JQ_BIN" 'del(.cwd)' "$FIX/session-start-startup.json" >"$SB/stdin"; run_hook
check "missing cwd: git not called" "0 $SSB" "$(git_count) $(spooled)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; ln -s "$SB/repo" "$SB/repolink"; cwd_pay session-start-startup "$SB/repolink"; run_hook
check "cwd through a symlink to a directory is passed as given, safe argv" "$GITARGV_PRE$SB/repolink$GITARGV_POST" "$(git_calls)"; end_case

echo "== git limited to one second, with and without timeout(1) =="
slow_case() {  # LABEL REALDIR
  new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; REAL="$2"
  SHIMD="$SB/slowshims"; link_shims "$SHIMD" git; ln -sf "$SHIMS_STUB/curl" "$SHIMD/curl"
  printf '#!/bin/bash\necho "git [$*]" >>"${SHIM_LOG:?}/calls.log"\nexec sleep 5\n' >"$SHIMD/git"; chmod +x "$SHIMD/git"
  cwd_pay session-start-startup "$SB/repo"
  local t0 t1; t0=$(date +%s); run_hook; t1=$(date +%s)
  check "$1: the hook returns well before the 5 s git would take" "yes" "$([ $((t1 - t0)) -le 3 ] && echo yes || echo no)"
  check "$1: git was started, no bind from a killed git, started state spooled, exit 0, silent" "1|$SSB|0||" "$(grep -c '^git' "$SB/log/calls.log")|$(spooled)|$RC|$OUT|$ERR"
  end_case
}
slow_case "timeout(1) present" "$REALBIN"
slow_case "timeout(1) absent (background-and-kill)" "$REALBIN_NOTO"
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; REAL="$REALBIN_NOTO"; cwd_pay session-start-startup "$SB/repo"; run_hook
check "without timeout(1): same safe argv and the bind is still found" "$GITARGV_PRE$SB/repo$GITARGV_POST|2" "$(git_calls)|$(spooled | wc -l | tr -d ' ')"; end_case

echo "== strength ordering and repeats =="
S1='{"type":"tool","tool":"Skill"}'
BSK='{"type":"bind","bind":{"source":"skill","role":"bridge","mode":"mission","spec":"ALY-203"}}'
BMC='{"type":"bind","bind":{"source":"mcp","spec":"ALY-203"}}'
TMC='{"type":"tool","tool":"allye:task_start"}'   # ALY-217.4: only task_start/task_submit bind
SEQ=(skill-bridge-spec mcp-allye-task-start-half-bad-key)
seq_case "skill then mcp: the weaker mcp bind is not sent" "$S1" "$BSK" "$TMC"
SEQ=(mcp-allye-task-start-half-bad-key skill-bridge-spec)
seq_case "mcp then skill: the stronger skill bind is sent" "$TMC" "$BMC" "$S1" "$BSK"
SEQ=(skill-bridge-spec skill-bridge-spec)
seq_case "skill twice: the same bind is sent once" "$S1" "$BSK" "$S1"
SEQ=(mcp-allye-task-start-half-bad-key mcp-allye-task-start-half-bad-key)
seq_case "mcp twice: the same bind is sent once" "$TMC" "$BMC" "$TMC"
SEQ=(mcp-allye-task-start-half-bad-key mcp-allye-task-start)
seq_case "mcp with a different key (same strength): sent again" "$TMC" "$BMC" '{"type":"tool","tool":"allye:task_start"}' '{"type":"bind","bind":{"source":"mcp","spec":"ALY-203","task":"ALY-203.3"}}'
SEQ=(skill-bridge-spec expansion-bridge-spec)
seq_case "skill via Skill tool then via expansion with another key: sent again" "$S1" "$BSK" '{"type":"bind","bind":{"source":"skill","role":"bridge","mode":"launch","spec":"ALY-7"}}'
SEQ=(skill-bridge-subagent mcp-allye-subagent)
seq_case "calls made inside a subagent never bind (a task_start that binds in the main session)" '{"type":"sub_start","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}' '{"type":"sub_tool","tool":"Skill","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}' '{"type":"sub_tool","tool":"allye:task_start","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}'
new_case; mkcred; "$JQ_BIN" 'del(.agent_id, .agent_type)' "$FIX/mcp-allye-subagent.json" >"$SB/stdin"; run_hook
check "control: the same task_start payload outside a subagent binds (the subagent case is not vacuous)" '{"bind":{"source":"mcp","spec":"ALY-203","task":"ALY-203.3"},"type":"bind"}' "$(spooled | grep '"bind"')"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-5"); run_fixture session-start-startup mcp-allye-task-start-half-bad-key skill-bridge-spec
check "env then mcp then skill: each stronger source is sent" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"env","role":"session","spec":"ALY-5"}}' "$TMC" "$BMC" "$S1" "$BSK" | "$JQ_BIN" -cS .)" "$(spooled)"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-5"); run_fixture skill-bridge-spec session-start-startup
check "skill then env at SessionStart: the weaker env bind is not sent" "$(printf '%s\n' "$S1" "$BSK" "$SSB" | "$JQ_BIN" -cS .)" "$(spooled)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; cwd_pay session-start-startup "$SB/repo"; run_hook; run_fixture mcp-allye-task-start-half-bad-key skill-bridge-spec
check "branch then mcp then skill: each stronger source is sent" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"branch","spec":"ALY-203"}}' "$TMC" "$BMC" "$S1" "$BSK" | "$JQ_BIN" -cS .)" "$(spooled)"
cwd_pay session-start-resume "$SB/repo"; run_hook
check "then a resume SessionStart: git not called again, no bind" "1" "$(git_count)"; end_case

echo "== bind state file =="
new_case; mkcred; run_fixture skill-bridge-spec
BF="$DATA/live/$(test_sha "$RAWSID").bind"
check "bind state: 0600, keyed by hash, holds only rank and the bind" "600 4|{\"source\":\"skill\",\"role\":\"bridge\",\"mode\":\"mission\",\"spec\":\"ALY-203\"}" "$(find "$BF" -printf '%m')$(printf ' ')$(cut -d'|' -f1 "$BF")|$(cut -d'|' -f2- "$BF")"
chmod 644 "$BF"; run_fixture mcp-allye-task-start
check "bind state with a wrong mode: no bind is sent or recorded" "0" "$(spooled | grep -c '"source":"mcp"' || true)"
chmod 600 "$BF"; rm "$BF"; ln -s "$SB/stdin" "$BF"; run_fixture mcp-allye-task-start
check "symlinked bind state: nothing bound, link target untouched" "0" "$(spooled | grep -c '"source":"mcp"' || true)"
end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; printf 'garbage' >"$DATA/live/$(test_sha "$RAWSID").bind"; chmod 600 "$DATA/live/$(test_sha "$RAWSID").bind"; run_fixture skill-bridge-spec
check "garbage in the bind state is treated as no binding" "$(printf '%s\n' "$S1" "$BSK" | "$JQ_BIN" -cS .)" "$(spooled)"; end_case

echo "== bind: spec_context, spec_get and launch keys report a touch (ALY-263.5) =="
# touch_run ACTION SPEC [AGENT]: a main-session (or subagent) call of the Allye specs tool; the other tool_input fields hold a marker.
touch_run() {
  "$JQ_BIN" --arg a "$1" --arg s "$2" --arg ag "${3:-}" '.tool_input = {action: $a, spec: $s, content: "MARKER_CMD", query: "MARKER_ARGS"} | if $ag != "" then . + {agent_id: $ag, agent_type: "allye:bridge-pilot"} else . end' "$FIX/mcp-allye-spec-get.json" >"$SB/stdin"; run_hook
}
binds() { spooled | grep '"type":"bind"' || true; }
TF() { echo "$DATA/live/$(test_sha "$RAWSID").touch"; }
BTC='{"bind":{"source":"mcp","spec":"ALY-203"},"type":"bind"}'
BSK='{"type":"bind","bind":{"source":"skill","role":"bridge","mode":"mission","spec":"ALY-203"}}'
BTC2='{"bind":{"source":"mcp","spec":"ALY-9"},"type":"bind"}'
for act in spec_context spec_get; do
  new_case; mkcred; touch_run "$act" ALY-203
  check "$act of the main session binds its key" "$BTC" "$(binds)"
  check "$act: only the key leaves (no marker in any file, log or request)" "0" "$( { grep -rhF -e MARKER_CMD -e MARKER_ARGS "$DATA/live" "$SB/out" "$SB/err" "$SB/log" 2>/dev/null || true; } | wc -l | tr -d ' ')"
  check "$act: touch state is 0600" "600" "$(find "$(TF)" -printf '%m' 2>/dev/null)"
  end_case
done
for k in aly-203 ABCDEFGHIJK-1 ALY- ALY-203x "ALY-203 extra" ALY-203.3 A-1 "ALY-203
ALY-5" 1ALY-2; do
  new_case; mkcred; touch_run spec_context "$k"
  check "spec_context with the key '$(printf '%s' "$k" | tr '\n' '~')': no bind" "" "$(binds)"
  end_case
done
for act in spec_list spec_validate spec_approve spec_update; do
  new_case; mkcred; touch_run "$act" ALY-203
  check "$act never binds" "" "$(binds)"
  end_case
done
new_case; mkcred; touch_run spec_context ALY-203 agent-abc123
check "a subagent's spec_context never binds" "" "$(binds)"
touch_run spec_get ALY-203
check "control: the same call in the main session binds" "$BTC" "$(binds)"
end_case
new_case; mkcred; run_fixture skill-bridge-spec; BF="$DATA/live/$(test_sha "$RAWSID").bind"; BEFOREB=$(cat "$BF")
touch_run spec_context ALY-9
check "a weaker mcp touch after a held skill binding is still sent" "$(printf '%s\n' "$BSK" "$BTC2" | "$JQ_BIN" -cS .)" "$(binds)"
check "the held binding is unchanged" "$BEFOREB" "$(cat "$BF")"
end_case
new_case; mkcred; touch_run spec_context ALY-203; touch_run spec_get ALY-203
check "the same key again within a minute is sent once" "$BTC" "$(binds)"
touch_run spec_context ALY-9
check "a different key within the minute is sent" "$(printf '%s\n' "$BTC" "$BTC2" | "$JQ_BIN" -cS .)" "$(binds)"
sed -i 's/ [0-9]*$/ 1000000000000/' "$(TF)"
touch_run spec_context ALY-203
check "the same key after the minute is sent again" "3" "$(binds | wc -l | tr -d ' ')"
end_case
new_case; mkcred; run_fixture skill-bridge-spec; run_fixture skill-bridge-spec
check "a launch with the same key and content within a minute is sent once" "1" "$(binds | wc -l | tr -d ' ')"
sed -i 's/ [0-9]*$/ 1000000000000/' "$(TF)"; run_fixture skill-bridge-spec
check "a launch with the key after the minute is sent again" "2" "$(binds | wc -l | tr -d ' ')"
end_case
new_case; mkcred; for i in $(seq 1 20); do touch_run spec_context "ALY-$i"; done
check "every distinct key within the minute is sent" "20" "$(binds | wc -l | tr -d ' ')"
check "the touch state is bounded" "yes" "$([ "$(wc -l <"$(TF)" | tr -d ' ')" -le 16 ] && echo yes || echo no)"
end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; printf 'garbage\n\x01' >"$(TF)"; chmod 600 "$(TF)"; touch_run spec_context ALY-203
check "a corrupt touch state is ignored: the bind is sent" "$BTC" "$(binds)"
check "the corrupt touch state is replaced by a valid one" "yes" "$(grep -qE '^ALY-203 [0-9]{13}$' "$(TF)" && [ "$(wc -l <"$(TF)" | tr -d ' ')" = 1 ] && echo yes || echo no)"
end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$SB/target"; ln -s "$SB/target" "$(TF)"; touch_run spec_context ALY-203
check "a symlinked touch state: nothing written through it" "0" "$(wc -c <"$SB/target" | tr -d ' ')"
end_case

echo "== markers in bindings =="
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-203" "ALLYE_TASK=MARKER_ABCDEF"); mkrepo "bridge/aly-203-MARKER_BRANCH"
for n in skill-bridge-task skill-bridge-bad-key2 expansion-bridge-bad-key mcp-allye-bad-action mcp-allye-task-start-bad-key mcp-allye-task-start-half-bad-key mcp-allye-task-submit mcp-bad-chars mcp-other-server; do run_fixture "$n"; done
cwd_pay session-start-startup "$SB/repo"; run_hook
check "ARGS, tool_input, branch and cwd markers absent from every file and log" "0" "$( { bind_files; cat "$SB/out" "$SB/err" "$SB/log/calls.log"; } | grep -cE 'MARKER_(ARGS|BRANCH|CMD|ABCDEF|CWD)' || true)"
check "every bind holds only contract keys and patterns" "0" "$("$JQ_BIN" -c 'select(.type == "bind") | .bind | select((keys - ["source","spec","task","role","mode"] | length > 0) or (.source | IN("skill","mcp","env","branch") | not) or ((.spec // "ALY-1") | test("\\A[A-Z][A-Z0-9]{1,9}-[0-9]+(\\.[0-9]+)?\\z") | not) or ((.task // "ALY-1.1") | test("\\A[A-Z][A-Z0-9]{1,9}-[0-9]+(\\.[0-9]+)?\\z") | not))' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
end_case


# ─── ALY-203.4: subagent outcome (BR-09, AC-07) ─────────────────────────────
echo "== subagent outcome from the structured output only (AC-07) =="
# stopped: the spooled lines without the synthetic sub_start that precedes the sub_stop of an unseen id (ALY-217.7, D-26).
stopped() { spooled | grep -v '"type":"sub_start"' || true; }
# stop_case LABEL MESSAGE-STRING EXPECTED-EVENT-JSON
stop_case() {
  new_case; mkcred; "$JQ_BIN" --arg m "$2" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
  check "$1" "$(printf '%s\n' "$3" | "$JQ_BIN" -cS .)" "$(stopped)"
  check "$1: exit 0, silent" "0||" "$RC|$OUT|$ERR"
  check "$1: the message text is not stored" "0" "$(bind_files | grep -cF -e MARKER_LASTMSG -e MARKER_PROSE || true)"
  end_case
}
SUBP='"id":"agent-abc123","type":"allye:bridge-pilot"'
for st in passed approved ready; do
  stop_case "status $st -> pass" "MARKER_LASTMSG
role: pilot
status: $st" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
done
stop_case "status advisory -> pass with code advisory" "status: advisory" "{\"type\":\"sub_stop\",\"code\":\"advisory\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
stop_case "status failed -> fail" "status: failed" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"fail\"}}"
for st in blocked needs-input escalate; do
  stop_case "status $st -> blocked" "status: $st" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"blocked\"}}"
done
UNK="{\"type\":\"sub_stop\",\"code\":\"returned\",\"sub\":{$SUBP,\"outcome\":\"unknown\"}}"
stop_case "no status line -> unknown/returned" "MARKER_LASTMSG all done" "$UNK"
stop_case "empty message -> unknown/returned" "" "$UNK"
stop_case "unknown status value" "status: great" "$UNK"
stop_case "uppercase status value" "status: PASSED" "$UNK"
stop_case "status with trailing junk" "status: passed MARKER_PROSE" "$UNK"
stop_case "status embedded in prose is not a line of its own" "I think the status: passed is fine, MARKER_PROSE" "$UNK"
stop_case "status in the middle of a line after text" "done - status: passed" "$UNK"
stop_case "status key with other prefix" "substatus: passed" "$UNK"
stop_case "indented status line is accepted (documented)" "  status: passed" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
stop_case "the first status line wins" "status: failed
status: passed" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"fail\"}}"
stop_case "the first status line wins even when it is unknown" "status: nope
status: passed" "$UNK"
stop_case "CRLF line ending" "$(printf 'status: passed\r\nMARKER_LASTMSG')" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
stop_case "task valid key" "status: passed
task: ALY-203.4" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\",\"task\":\"ALY-203.4\"}}"
stop_case "task spec-style key" "status: failed
task: ALY-203" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"fail\",\"task\":\"ALY-203\"}}"
stop_case "task that is not a key is dropped" "status: passed
task: do the thing MARKER_PROSE" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
stop_case "task dotted twice is dropped" "status: passed
task: ALY-203.4.5" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
stop_case "task lowercase is dropped" "status: passed
task: aly-1" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
stop_case "task key in prose is dropped" "status: passed
see task: ALY-1.2 later" "{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"
stop_case "task with unknown status still carries the valid key" "task: ALY-9.1" "{\"type\":\"sub_stop\",\"code\":\"returned\",\"sub\":{$SUBP,\"outcome\":\"unknown\",\"task\":\"ALY-9.1\"}}"
for badm in 'null' '7' '["status: passed"]' '{"a":1}' 'true'; do
  new_case; mkcred; "$JQ_BIN" --argjson m "$badm" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
  check "non-string last_assistant_message $badm -> unknown/returned" "$(printf '%s\n' "$UNK" | "$JQ_BIN" -cS .)|0||" "$(stopped)|$RC|$OUT|$ERR"; end_case
done
new_case; mkcred; "$JQ_BIN" 'del(.last_assistant_message)' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "missing last_assistant_message -> unknown/returned" "$(printf '%s\n' "$UNK" | "$JQ_BIN" -cS .)" "$(stopped)"; end_case
# only the first 64 KB of the message is examined: a status line past it does not count, one inside it does
new_case; mkcred
HUGE=$(head -c 70000 /dev/zero | tr '\0' 'a')
"$JQ_BIN" --arg m "$HUGE
status: passed" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "status line after 64 KB of text is not examined -> unknown" "$(printf '%s\n' "$UNK" | "$JQ_BIN" -cS .)|0||" "$(stopped)|$RC|$OUT|$ERR"; end_case
new_case; mkcred
"$JQ_BIN" --arg m "status: failed
$HUGE" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "status line inside the first 64 KB of a huge message counts" "{\"sub\":{\"id\":\"agent-abc123\",\"outcome\":\"fail\",\"type\":\"allye:bridge-pilot\"},\"type\":\"sub_stop\"}|0||" "$(stopped)|$RC|$OUT|$ERR"; end_case

# ─── ALY-263.1: crew result from the subagent transcript (AC-01, AC-02, AC-03, BR-01, BR-02, D-10, D-16) ──────
# The transcript is synthetic: one JSON object per line, the real shape ends with a SubagentHandback tool_use whose input.message is the
# report and no text block. Foreign owner is not tested: a file of another user needs root (the owner check is `find -user`, as in
# private_file_ok, whose tests cover the same primitive).
echo "== subagent outcome from the transcript (ALY-263.1 AC-01, AC-02, AC-03, BR-01, BR-02) =="
tr_hb() { "$JQ_BIN" -nc --arg m "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"SubagentHandback",input:{message:$m}}]}}'; }
tr_tx() { "$JQ_BIN" -nc --arg m "$1" '{type:"assistant",message:{content:[{type:"text",text:$m}]}}'; }
tr_res() { "$JQ_BIN" -nc --arg m "$1" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t1",content:$m}]}}'; }
tr_blob() { "$JQ_BIN" -nc --arg m "$1" '{type:"api-request-blob",request:{messages:[{type:"assistant",message:{content:[{type:"tool_use",name:"SubagentHandback",input:{message:$m}}]}}]}}'; }
tr_new() { new_case; mkcred; PROJ="$(mkdir -p "$SB/home/.claude/projects/p" && cd -P "$SB/home/.claude/projects/p" && pwd -P)"; TDIR="$PROJ/$RAWSID/subagents"; mkdir -p "$TDIR"; AF="$TDIR/agent-agent-abc123.jsonl"; }
# tr_run LABEL EXPECTED(pass|fail|unknown) [JQ-FILTER] [MESSAGE]: the payload names $AF and carries MESSAGE as last_assistant_message.
tr_run() {
  local exp
  case "$2" in pass) exp="{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}" ;; fail) exp="{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"fail\"}}" ;; *) exp="$UNK" ;; esac
  "$JQ_BIN" --arg tp "$PROJ/t.jsonl" --arg ap "$AF" --arg m "${4-closing words}" '.transcript_path = $tp | .agent_transcript_path = $ap | .last_assistant_message = $m' "$FIX/subagent-stop.json" | "$JQ_BIN" "${3:-.}" >"$SB/stdin"
  run_hook
  check "$1" "$(printf '%s\n' "$exp" | "$JQ_BIN" -cS .)|0||" "$(stopped)|$RC|$OUT|$ERR"
}
tr_new; { tr_hb "role: pilot
status: failed"; } >"$AF"; tr_run "handback only (the real shape): its status is used" fail; end_case
tr_new; { tr_hb "status: failed"; tr_res "ok"; tr_hb "status: passed"; } >"$AF"; tr_run "several handbacks: the last one wins" pass; end_case
tr_new; { tr_hb "status: passed"; tr_hb "no report here"; } >"$AF"; tr_run "last handback without a status is not replaced by an earlier one" unknown; end_case
tr_new; { tr_hb "status: failed"; tr_tx "status: passed"; } >"$AF"; tr_run "handback followed by closing text: the handback wins" fail; end_case
tr_new; { tr_hb "nothing to report"; tr_tx "status: passed"; } >"$AF"; tr_run "handback without a status: the last text block is the next candidate" pass; end_case
tr_new; { tr_tx "status: passed"; tr_tx "all done, nothing else"; } >"$AF"; tr_run "markers in an earlier turn are not read" unknown; end_case
tr_new; { tr_tx "status: passed"; tr_tx "status: failed"; } >"$AF"; tr_run "the last text block, never a join of blocks" fail; end_case
tr_new; { tr_hb "status: passed
status: failed"; } >"$AF"; tr_run "two status lines in the handback: rejected" unknown; end_case
tr_new; { tr_hb "status: passed
summary: one thing here
summary: another thing here"; } >"$AF"; tr_run "two summary lines in the handback: rejected" unknown; end_case
tr_new; { tr_hb "  status: passed
 status: passed"; } >"$AF"; tr_run "indented status lines are not column-0: rejected" unknown; end_case
tr_new; { tr_res "status: passed"; } >"$AF"; tr_run "status inside a tool_result is not read" unknown; end_case
tr_new; { tr_blob "status: passed"; } >"$AF"; tr_run "an assistant line inside a blob is not read" unknown; end_case
tr_new; printf 'not json at all\n%s\n{"type":"assistant",\n' "$(tr_hb "status: passed")" >"$AF"; tr_run "invalid JSON lines are skipped" pass; end_case
tr_new; printf '%s' "$(tr_hb "status: passed")" >"$AF"; tr_run "an unterminated last line is dropped" unknown; end_case
tr_new; { tr_hb "status: failed"; } >"$AF"; tr_run "a status already in the message: the transcript is not read" pass . "status: passed"; end_case
tr_new; { tr_hb "status: failed"; } >"$AF"; tr_run "an indented status in the message is not column-0: the transcript is read" fail . "  status: passed"; end_case
tr_new; { tr_hb "status: failed"; } >"$AF"; tr_run "a status line without a value: the transcript is read" fail . "status:"; end_case
# a derived path when the payload has no agent_transcript_path
tr_new; { tr_hb "status: failed"; } >"$AF"; tr_run "no agent_transcript_path: the path is derived from the ids" fail 'del(.agent_transcript_path)'; end_case
# size: the tail rule
tr_new; { tr_hb "status: passed"; printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$(head -c 1200000 /dev/zero | tr '\0' a)"; } >"$AF"; tr_run "a handback earlier than the last 1 MB is not read" unknown; end_case
tr_new; "$JQ_BIN" -nc --rawfile pad <(head -c 300000 /dev/zero | tr '\0' a) '{type:"assistant",message:{content:[{type:"tool_use",name:"SubagentHandback",input:{message:("status: passed\n" + $pad)}}]}}' >"$AF"; tr_run "a line larger than 256 KB widens the read once to 1 MB" pass; end_case
tr_new; printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s\\nstatus: passed"}]}}\n' "$(head -c 104857600 /dev/zero | tr '\0' a)" >"$AF"; tr_run "a single 100 MB line fails closed" unknown; rm -f "$AF"; end_case
# hostile paths
tr_new; mkdir -p "$PROJ/other"; { tr_hb "status: passed"; } >"$PROJ/other/real.jsonl"; ln -s "$PROJ/other/real.jsonl" "$AF"; tr_run "a symlinked transcript file reads nothing" unknown; end_case
tr_new; rm -rf "$PROJ/$RAWSID"; mkdir -p "$PROJ/elsewhere/subagents"; { tr_hb "status: passed"; } >"$PROJ/elsewhere/subagents/agent-agent-abc123.jsonl"; ln -s "$PROJ/elsewhere" "$PROJ/$RAWSID"; tr_run "a symlinked parent directory reads nothing" unknown; end_case
tr_new; mkfifo "$AF"; tr_run "a FIFO reads nothing and does not hang" unknown; end_case
tr_new; { tr_hb "status: passed"; } >"$AF"; tr_run "a .. component reads nothing" unknown ".agent_transcript_path = \"$TDIR/../subagents/agent-agent-abc123.jsonl\""; end_case
tr_new; { tr_hb "status: passed"; } >"$AF"; tr_run "a newline in the path reads nothing" unknown ".agent_transcript_path = \"$AF\" + \"\\n\""; end_case
tr_new; { tr_hb "status: passed"; } >"$AF"; tr_run "a newline inside a directory name reads nothing" unknown ".agent_transcript_path = \"$PROJ/\\n/$RAWSID/subagents/agent-agent-abc123.jsonl\""; end_case
tr_new; { tr_hb "status: passed"; } >"$AF"; tr_run "a basename outside the pattern reads nothing" unknown ".agent_transcript_path = \"$TDIR/notes.jsonl\""; end_case
tr_new; { tr_hb "status: passed"; } >"$AF"; mkdir -p "$SB/elsewhere"; cp "$AF" "$SB/elsewhere/agent-x.jsonl"; tr_run "a file outside the Claude projects directory reads nothing" unknown ".agent_transcript_path = \"$SB/elsewhere/agent-x.jsonl\""; end_case
tr_new; { tr_hb "status: passed"; } >"$AF"; tr_run "an environment of another home: the payload cannot move the root" unknown '.agent_transcript_path = "/etc/passwd"'; end_case
tr_new; { tr_hb "status: passed"; } >"$AF"; mkdir -p "$SB/altcfg/projects"; RUN_ENV=("CLAUDE_CONFIG_DIR=$SB/altcfg"); tr_run "CLAUDE_CONFIG_DIR moves the root: a file under HOME is outside" unknown; end_case
tr_new; mkdir -p "$SB/altcfg/projects/p/$RAWSID/subagents"; { tr_hb "status: passed"; } >"$SB/altcfg/projects/p/$RAWSID/subagents/agent-agent-abc123.jsonl"; RUN_ENV=("CLAUDE_CONFIG_DIR=$SB/altcfg"); PROJ="$SB/altcfg/projects/p"; AF="$PROJ/$RAWSID/subagents/agent-agent-abc123.jsonl"; tr_run "CLAUDE_CONFIG_DIR is honored" pass; end_case
tr_new; { tr_hb "status: passed MARKER_LASTMSG"; } >"$AF"; tr_run "only the parsed fields leave: the report text is not stored" unknown . ""; check "no report text in any file" "0" "$(grep -rlF MARKER_LASTMSG "$DATA" "$SB/log" 2>/dev/null | wc -l | tr -d ' ')"; end_case

# SHD-04: a `gate:` line taken from a transcript only sets the sub.gate display field (the same parser as today); it never makes a gates event
tr_new; { tr_hb "status: passed
gate: SHIELD_CLEAR"; } >"$AF"
"$JQ_BIN" --arg tp "$PROJ/t.jsonl" --arg ap "$AF" '.transcript_path = $tp | .agent_transcript_path = $ap | .last_assistant_message = "closing words" | .agent_type = "allye:bridge-shield"' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "a gate line from the transcript sets sub.gate only" "{\"sub\":{\"gate\":\"SHIELD_CLEAR\",\"id\":\"agent-abc123\",\"outcome\":\"pass\",\"type\":\"allye:bridge-shield\"},\"type\":\"sub_stop\"}|0" "$(stopped)|$(spooled | grep -c '"type":"gates"' || true)"; end_case
# The shared 2 s budget (SHD-01, SHD-02), proven on the deadline value with a fake clock: no elapsed-time bound is asserted.
tr_new; { tr_hb "status: passed"; } >"$AF"
RDSRC=$(sed -n '/^RD_END=""$/,/^# transcript_report FILE:/p' "$HOOK" | sed '$d')
rd_unit() {  # rd_unit SCRIPT: runs SCRIPT with the budget functions, a fake clock (FAKE_NOW, ms) and the sandbox HOME
  env -i HOME="$SB/home" PATH="$REAL" BASH="$BASH_BIN" "$BASH_BIN" -c 'UID_NOW=$(id -u); now_ms() { printf "%s" "$FAKE_NOW"; }; '"$RDSRC"'
'"$1" 2>&1
}
T0=1800000000000
check "no deadline set: the budget is spent" "rc=1" "$(rd_unit 'FAKE_NOW='$T0'; x=$(rd_left); echo "$x rc=$?" | sed "s/^ //"')"
check "deadline passed: rd_left fails and a valid file reads nothing" "rc=1 rc=1 out=" "$(rd_unit 'FAKE_NOW='$T0'; RD_END='$T0'; rd_left >/dev/null; a=$?; o=$(claude_safe_tail "'"$AF"'" 262144); echo "rc=$a rc=$? out=$o"')"
check "budget left is read from the deadline" "1.500 0.800" "$(rd_unit 'RD_END='$((T0 + 1500))'; FAKE_NOW='$T0'; a=$(rd_left); FAKE_NOW='$((T0 + 700))'; b=$(rd_left); echo "$a $b"')"
check "the deadline survives a command substitution (the second read sees less)" "$((T0 + 2000)) rc=0 rc=1" "$(rd_unit 'RD_END='$((T0 + 2000))'; FAKE_NOW='$T0'; o=$(claude_safe_tail "'"$AF"'" 262144); a=$?; FAKE_NOW='$((T0 + 2500))'; o2=$(claude_safe_tail "'"$AF"'" 262144); echo "$RD_END rc=$a rc=$?"')"
check "a read within the budget returns the tail" "full" "$(rd_unit 'RD_END='$((T0 + 2000))'; FAKE_NOW='$T0'; claude_safe_tail "'"$AF"'" 262144 | head -1')"
# a stat step that hangs (a find stub) is killed by the timeout child: the read fails, whatever the time it takes
mkdir -p "$SB/hangbin"; printf '#!%s\nexec %s 5\n' "$BASH_BIN" "$(type -P sleep)" >"$SB/hangbin/find"; chmod +x "$SB/hangbin/find"
check "a hanging find is cut by the budget: nothing is read" "failed" "$(env -i HOME="$SB/home" PATH="$SB/hangbin:$REALBIN" BASH="$BASH_BIN" "$BASH_BIN" -c 'UID_NOW=$(id -u); now_ms() { date +%s%3N; }; '"$RDSRC"'
RD_END=$(( $(now_ms) + 1000 )); o=$(claude_safe_tail "'"$AF"'" 262144); [ $? -ne 0 ] && [ -z "$o" ] && echo failed' 2>&1)"
end_case

# ─── ALY-263.4: dispatch description from the subagent metadata file at SubagentStop (AC-07, AC-02, BR-02, BR-03, D-03, D-14) ──────
# The metadata file has no id key in real sessions (spike ALY-263.8): the link is the filename agent-<hook agent_id>.meta.json.
echo "== subagent outcome: desc from the metadata file (ALY-263.4 AC-07, AC-02, BR-02, BR-03, D-03, D-14) =="
# md_new: a case with the transcript layout of tr_new and MF, the metadata file of the agent.
md_new() { tr_new; MF="$TDIR/agent-agent-abc123.meta.json"; }
# md_run LABEL EXPECTED-DESC ("" = no desc key) [JQ-FILTER over the payload]: the stop of a "status: passed" report.
md_run() {
  local exp
  if [ -n "$2" ]; then exp="{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\",\"desc\":$("$JQ_BIN" -n --arg d "$2" '$d')}}"; else exp="{\"type\":\"sub_stop\",\"sub\":{$SUBP,\"outcome\":\"pass\"}}"; fi
  "$JQ_BIN" --arg tp "$PROJ/t.jsonl" --arg ap "$AF" '.transcript_path = $tp | .agent_transcript_path = $ap | .last_assistant_message = "status: passed"' "$FIX/subagent-stop.json" | "$JQ_BIN" "${3:-.}" >"$SB/stdin"
  run_hook
  check "$1" "$(printf '%s\n' "$exp" | "$JQ_BIN" -cS .)|0||" "$(stopped)|$RC|$OUT|$ERR"
}
MDESC='Implement the metadata description for ALY-263.4'
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{agentType:"allye:bridge-pilot",description:$d,toolUseId:"toolu_MARKER_TUID",spawnDepth:1,extra:"MARKER_EXTRA"}' >"$MF"
md_run "metadata present: its description is sent as desc on sub_stop" "$MDESC"
check "toolUseId and the other keys of the file are not stored or sent" "0" "$(grep -rlF -e MARKER_TUID -e MARKER_EXTRA "$DATA" "$SB/log" 2>/dev/null | wc -l | tr -d ' ')"; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; md_run "no agent_transcript_path: the path is derived from the ids" "$MDESC" 'del(.agent_transcript_path)'; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; md_run "the payload cannot carry its own meta_desc" "$MDESC" '.meta_desc = "MARKER_PAYLOAD_DESC injected from the payload"'; end_case
md_new; md_run "no metadata file: nothing extra, exit 0, silent" ""; end_case
md_new; md_run "no metadata file and a payload meta_desc: nothing" "" '.meta_desc = "MARKER_PAYLOAD_DESC injected from the payload"'; end_case
md_new; printf '{"description": "Truncated MARKER_DESC here' >"$MF"; md_run "corrupt JSON: nothing" ""; end_case
md_new; printf '["description","Implement the metadata description"]' >"$MF"; md_run "JSON that is not an object: nothing" ""; end_case
for dv in 7 null true '["Implement the metadata description"]' '{"a":"Implement the metadata description"}'; do
  md_new; printf '{"description":%s}' "$dv" >"$MF"; md_run "description $dv is not a string: nothing" ""; end_case
done
md_new; printf '{"description":""}' >"$MF"; md_run "empty description: nothing" ""; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" --rawfile pad <(head -c 70000 /dev/zero | tr '\0' a) '{description:$d,pad:$pad}' >"$MF"; md_run "oversize file (over 64 KB): nothing" ""; end_case
md_new; "$JQ_BIN" -nc '{description:"Review the change with sk-live12345abcdef and ghp_0123456789abcdefghij"}' >"$MF"; md_run "secrets in the description are dropped by the cleaner" "Review the change with and"; end_case
md_new; "$JQ_BIN" -nc '{description:"/etc/MARKER_PATH/x.txt"}' >"$MF"; md_run "a description that is only a path is dropped whole" ""; end_case
md_new; "$JQ_BIN" -nc --arg d "$(for i in $(seq 1 100); do printf 'word '; done)" '{description:$d}' >"$MF"; "$JQ_BIN" --arg tp "$PROJ/t.jsonl" --arg ap "$AF" '.transcript_path = $tp | .agent_transcript_path = $ap | .last_assistant_message = "status: passed"' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "a long description: at most 140 code points with the ellipsis" "yes" "$(stopped | "$JQ_BIN" -r '.sub.desc | if (length <= 140 and endswith("…")) then "yes" else "no" end')"; end_case
# id mismatch
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{agentId:"agent-other",description:$d}' >"$MF"; md_run "an agentId key that differs from the hook agent id: dropped" ""; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{agent_id:"agent-other",description:$d}' >"$MF"; md_run "an agent_id key that differs from the hook agent id: dropped" ""; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{agentId:"agent-abc123",description:$d}' >"$MF"; md_run "an agentId key equal to the hook agent id: kept" "$MDESC"; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; cp "$MF" "$TDIR/agent-other.meta.json"; rm -f "$MF"; md_run "the file of another agent id is not read" ""; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; md_run "payload path that does not name the hook agent id: the metadata file is not read" "" ".agent_transcript_path = \"$TDIR/agent-zzz.jsonl\""; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; "$JQ_BIN" --arg tp "$PROJ/t.jsonl" '.transcript_path = $tp | .agent_id = "a/b" | del(.agent_transcript_path) | .last_assistant_message = "status: passed"' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "an agent id with a slash builds no path and sends no event" "|0||" "$(stopped)|$RC|$OUT|$ERR"; end_case
# hostile paths (the helpers of the transcript section)
md_new; mkdir -p "$PROJ/other"; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$PROJ/other/real.json"; ln -s "$PROJ/other/real.json" "$MF"; md_run "a symlinked metadata file reads nothing" ""; end_case
md_new; rm -rf "$PROJ/$RAWSID"; mkdir -p "$PROJ/elsewhere/subagents"; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$PROJ/elsewhere/subagents/agent-agent-abc123.meta.json"; ln -s "$PROJ/elsewhere" "$PROJ/$RAWSID"; md_run "a symlinked parent directory reads nothing" ""; end_case
md_new; mkfifo "$MF"; md_run "a FIFO metadata file reads nothing and does not hang" ""; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; md_run "a .. component reads nothing" "" ".agent_transcript_path = \"$TDIR/../subagents/agent-agent-abc123.jsonl\""; end_case
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; md_run "a newline in the path reads nothing" "" ".agent_transcript_path = \"$AF\" + \"\\n\""; end_case
# display text: off flags
for fl in activity-off detailed-off; do
  md_new; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/$fl"; chmod 600 "$DATA/live/$fl"
  "$JQ_BIN" -nc '{description:"Implement the MARKER_DESC description for the task"}' >"$MF"; md_run "$fl: no desc in the spool" ""
  check "$fl: the description is on no disk file" "0" "$(grep -rlF MARKER_DESC "$DATA" "$SB/log" 2>/dev/null | wc -l | tr -d ' ')"; end_case
done
md_new; "$JQ_BIN" -nc '{description:"Implement the MARKER_DESC description for the task"}' >"$MF"; md_run "texts on: the description is in the spool (control for the off cases)" "Implement the MARKER_DESC description for the task"; end_case
# a status in the message and a metadata file: both work, the transcript is not needed
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"; md_run "a report in the message: desc still comes from the file" "$MDESC" 'del(.agent_transcript_path) | .transcript_path = "'"$PROJ"'/t.jsonl"'; end_case
# the shared budget: a spent deadline reads nothing
md_new; "$JQ_BIN" -nc --arg d "$MDESC" '{description:$d}' >"$MF"
check "a spent deadline reads no metadata" "rc=1 out=" "$(rd_unit 'FAKE_NOW='$T0'; RD_END='$T0'; o=$(claude_safe_tail "'"$MF"'" 65536); echo "rc=$? out=$o"')"; end_case

# ─── ALY-258.2: summary and chips from the crew report (AC-03, AC-04, AC-05, AC-11, AC-12, AC-15, AC-17, BR-01, BR-04, D-05) ──────
echo "== report lines: summary, attempt, next, gate, checks and severity counts (ALY-258.2 AC-04, AC-05, AC-15, AC-17, BR-01, BR-04) =="
# rl_case LABEL MESSAGE EXTRAS-JSON [AGENT-TYPE] [off]: the sub_stop of a "status: passed" report is {id, type, outcome:pass} + EXTRAS.
# (uses the `stopped` helper of the subagent outcome section: select both sections together)
nowiso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
RLSUM='Reviewed the parser change and found it consistent'
rl_case() {
  local ty="${4:-allye:bridge-pilot}"
  new_case; mkcred; [ "${5:-}" = off ] && { mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/activity-off"; chmod 600 "$DATA/live/activity-off"; }
  "$JQ_BIN" --arg m "$2" --arg t "$ty" '.last_assistant_message = $m | .agent_type = $t' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
  check "$1" "$("$JQ_BIN" -cS -n --arg t "$ty" --argjson x "$3" '{type: "sub_stop", sub: ({id: "agent-abc123", type: $t, outcome: "pass"} + $x)}')" "$(stopped)"
  check "$1: exit 0, silent" "0||" "$RC|$OUT|$ERR"
  end_case
}
P=$'status: passed\n'
rl_case "summary valid: cleaned text goes on sub.summary" "${P}summary: $RLSUM" "{\"summary\":\"$RLSUM\"}"
rl_case "summary valid with CRLF line ends" "$(printf 'status: passed\r\nsummary: %s\r\nattempt: 1\r\n' "$RLSUM")" "{\"summary\":\"$RLSUM\",\"attempt\":1}"
rl_case "summary alone at column 0 inside a code fence still matches" $'```\nsummary: '"$RLSUM"$'\n```\nstatus: passed' "{\"summary\":\"$RLSUM\"}"
rl_case "summary of two words is dropped (3-word minimum)" "${P}summary: Looks good" "{}"
rl_case "summary below 8 characters is dropped" "${P}summary: a b c" "{}"
rl_case "summary with a path and a secret: the cleaner drops those tokens, the rest is kept" "${P}summary: Reviewed the change in /etc/MARKER_PATH with sk-live12345abcdef and found it fine" '{"summary":"Reviewed the change in with and found it fine"}'
rl_case "summary that is only a path is dropped" "${P}summary: /etc/MARKER_PATH/x.txt" "{}"
LONG=$(head -c 5000 /dev/zero | tr '\0' 'a'); LONGW=$(for i in $(seq 1 600); do printf 'word '; done)
rl_case "summary of 5000 characters without spaces is dropped by the cleaner (one long token)" "${P}summary: $LONG" "{}"
new_case; mkcred; "$JQ_BIN" --arg m "${P}summary: $LONGW" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "summary of 3000 characters of words: capped at 140 code points with an ellipsis, one line" "yes" "$(stopped | "$JQ_BIN" -r '.sub.summary | if (length <= 140 and endswith("…") and (contains("\n") | not)) then "yes" else "no" end')"; end_case
rl_case "summary indented: omitted" "${P}  summary: $RLSUM" "{}"
rl_case "summary behind a list marker: omitted" "${P}- summary: $RLSUM" "{}"
rl_case "summary in bold: omitted" "${P}**summary:** $RLSUM" "{}"
rl_case "summary with a different case of the key: omitted" "${P}Summary: $RLSUM
SUMMARY: $RLSUM" "{}"
rl_case "summary repeated: omitted (zero or several)" "${P}summary: $RLSUM
summary: Another summary text that is long enough" "{}"
rl_case "summary once at column 0 plus an indented copy: the column-0 line is the one match" "${P}summary: $RLSUM
  summary: Another summary text that is long enough" "{\"summary\":\"$RLSUM\"}"
rl_case "summary: off flag sends no summary (BR-03) but keeps the chips" "${P}summary: $RLSUM
attempt: 2" '{"attempt":2}' allye:bridge-pilot off
rl_case "summary line past 64 KB is not examined" "${P}$(head -c 70000 /dev/zero | tr '\0' 'a')
summary: $RLSUM" "{}"
# chips
rl_case "attempt 0, 1, 2 are ints (0 is allowed)" "${P}attempt: 0" '{"attempt":0}'
rl_case "attempt 2" "${P}attempt: 2" '{"attempt":2}'
for bad in 3 -1 01 1.5 +1 one '1 extra' '1,' ''; do rl_case "attempt '$bad' is omitted" "${P}attempt: $bad" "{}"; done
rl_case "attempt repeated: omitted" "${P}attempt: 1
attempt: 1" "{}"
rl_case "attempt indented / bold / capital: omitted" "${P}  attempt: 1
**attempt:** 1
Attempt: 1" "{}"
rl_case "attempt inside prose: omitted" "${P}this is attempt: 1 of 2" "{}"
rl_case "next pilot-correction maps to pilot_correction" "${P}next: pilot-correction" '{"next":"pilot_correction"}'
for t in reviewers pilot_correction mothership watcher done; do rl_case "next $t is accepted" "${P}next: $t" "{\"next\":\"$t\"}"; done
rl_case "next Mothership (capital) is lowercased and accepted" "${P}next: Mothership" '{"next":"mothership"}'
rl_case "next outside the enum is omitted" "${P}next: nobody" "{}"
rl_case "next with trailing junk is omitted" "${P}next: done MARKER_PROSE" "{}"
rl_case "next repeated: omitted" "${P}next: done
next: watcher" "{}"
rl_case "gate SHIELD_CLEAR from a shield" "${P}gate: SHIELD_CLEAR" '{"gate":"SHIELD_CLEAR"}' allye:bridge-shield
rl_case "gate WATCHER_APPROVED from a watcher" "${P}gate: WATCHER_APPROVED" '{"gate":"WATCHER_APPROVED"}' allye:bridge-watcher
rl_case "gate WATCHER_APPROVED from a shield is omitted" "${P}gate: WATCHER_APPROVED" "{}" allye:bridge-shield
rl_case "gate SHIELD_CLEAR from a watcher is omitted" "${P}gate: SHIELD_CLEAR" "{}" allye:bridge-watcher
rl_case "gate SHIELD_CLEAR from a pilot is omitted (AC-17)" "${P}gate: SHIELD_CLEAR" "{}"
rl_case "gate null is ignored" "${P}gate: null" "{}" allye:bridge-shield
rl_case "gate in lowercase is omitted" "${P}gate: shield_clear" "{}" allye:bridge-shield
rl_case "gate repeated: omitted" "${P}gate: SHIELD_CLEAR
gate: SHIELD_CLEAR" "{}" allye:bridge-shield
rl_case "checks ok/run valid" "${P}checks: ok=3 run=4" '{"checks":{"ok":3,"run":4}}' allye:bridge-copilot
rl_case "checks 0 and 99" "${P}checks: ok=0 run=99" '{"checks":{"ok":0,"run":99}}'
for bad in 'ok=100 run=3' 'ok=-1 run=3' 'ok=01 run=3' 'ok=1.5 run=3' 'ok=+3 run=3' 'run=3 ok=3' 'ok=3' 'ok=3 run=4 extra' 'ok=3,run=4' 'ok=x run=4'; do rl_case "checks '$bad' is omitted (all or nothing)" "${P}checks: $bad" "{}"; done
rl_case "checks repeated: omitted" "${P}checks: ok=1 run=1
checks: ok=1 run=1" "{}"
rl_case "severity_counts valid" "${P}severity_counts: critical=0 high=1 medium=2 low=3 info=4" '{"findings":{"critical":0,"high":1,"medium":2,"low":3,"info":4}}' allye:bridge-medic
for bad in 'critical=100 high=1 medium=2 low=3 info=4' 'critical=-1 high=1 medium=2 low=3 info=4' 'critical=00 high=1 medium=2 low=3 info=4' 'critical=1.5 high=1 medium=2 low=3 info=4' 'critical=+1 high=1 medium=2 low=3 info=4' 'high=1 critical=0 medium=2 low=3 info=4' 'critical=0 high=1 medium=2 low=3' 'critical=0 high=1 medium=2 low=3 info=4 extra=1' 'critical=0 high=1 medium=2 low=3 info=4 MARKER_PROSE'; do rl_case "severity_counts '$bad' is omitted (all or nothing)" "${P}severity_counts: $bad" "{}"; done
rl_case "severity_counts repeated: omitted" "${P}severity_counts: critical=0 high=0 medium=0 low=0 info=0
severity_counts: critical=0 high=0 medium=0 low=0 info=0" "{}"
rl_case "all lines together" "${P}task: ALY-258.2
summary: $RLSUM
attempt: 1
next: reviewers
gate: WATCHER_APPROVED
checks: ok=2 run=2
severity_counts: critical=0 high=0 medium=0 low=0 info=1" "{\"task\":\"ALY-258.2\",\"summary\":\"$RLSUM\",\"attempt\":1,\"next\":\"reviewers\",\"gate\":\"WATCHER_APPROVED\",\"checks\":{\"ok\":2,\"run\":2},\"findings\":{\"critical\":0,\"high\":0,\"medium\":0,\"low\":0,\"info\":1}}" allye:bridge-watcher
# AC-12: a report with none of the new lines gives the previous event; the code of an unknown status stays
rl_case "legacy report (none of the new lines, prose around): exactly the previous sub_stop" "MARKER_LASTMSG role: pilot
summary text here is prose, attempt 1, next steps: none
status: passed
task: ALY-1.2" '{"task":"ALY-1.2"}'
# BR-01 / NFR-01: nothing but the cleaned summary leaves; a marker in prose, other lines and unknown keys is in no file, log or body
new_case; mkcred; SHIMD="$SHIMS"
"$JQ_BIN" --arg m "MARKER_LASTMSG prose line
status: passed
summary: $RLSUM
attempt: 1 MARKER_PROSE
next: done
extra: MARKER_ABCDEF
notes: MARKER_MSG
checks: ok=1 run=2 MARKER_ARGS
severity_counts: critical=0 high=0 medium=0 low=0 info=0
  summary: MARKER_CMD indented
**gate:** MARKER_TITLE" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
for i in $(seq 1 100); do [ -s "$SB/api/ingest-bodies.log" ] && break; sleep 0.05; done; wait_idle
SENTR="$SB/api/ingest-bodies.log"
check "BR-01: the sub_stop that left the machine holds the cleaned summary and the valid chips only" "{\"attempt\":null,\"checks\":null,\"findings\":{\"critical\":0,\"high\":0,\"info\":0,\"low\":0,\"medium\":0},\"id\":\"agent-abc123\",\"next\":\"done\",\"outcome\":\"pass\",\"summary\":\"$RLSUM\",\"type\":\"allye:bridge-pilot\"}" \
  "$("$JQ_BIN" -cS '.events[] | select(.type == "sub_stop") | .sub | {attempt: .attempt, checks: .checks} + .' "$SENTR" 2>/dev/null | head -n 1)"
SCANR="$SB/scanr.txt"; { find "$DATA" -type f ! -name hook-credential.json -exec cat {} +; find "$DATA" -print; cat "$SB/log"/* "$SENTR" 2>/dev/null; } >"$SCANR"
N8=0; for m in "$RAWSID" "${MARKERS[@]}"; do [ "$(grep -cF -- "$m" "$SCANR" || true)" = 0 ] || { N8=$((N8 + 1)); echo "    found: $m"; }; done
check "BR-01/NFR-01: no marker of prose, other lines, other keys or indented lines is in any file, log or request body" "0" "$N8"
check "BR-01: the summary text reached the API (the scan is not vacuous)" "yes" "$(grep -q "$RLSUM" "$SENTR" 2>/dev/null && echo yes || echo no)"
end_case
# jq cost of the parse on a 64 KB message (informational, not an assertion)
new_case; mkcred
BIGM=$(for i in $(seq 1 1000); do printf 'line %s of the report with some prose text here to fill 64 kilobytes\n' "$i"; done | head -c 65000)
"$JQ_BIN" --arg m "status: passed
summary: $RLSUM
$BIGM" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"
T0=$(date +%s%N 2>/dev/null || echo 0); run_hook; T1=$(date +%s%N 2>/dev/null || echo 0)
echo "    info (NFR-02): hook run on a 64 KB crew message: $(( (T1 - T0) / 1000000 )) ms, no added network call"
check "NFR-02: the 64 KB message still gives the summary" "$RLSUM" "$(stopped | "$JQ_BIN" -r '.sub.summary')"
end_case

echo "== longer texts in batches and the new nested keys (ALY-258.2 AC-11, NFR-03) =="
nowiso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# sumline SEQ TEXT: a spooled sub_stop with every new nested key
sumline() { "$JQ_BIN" -nc --argjson s "$1" --arg t "$2" --arg at "$(nowiso)" '{seq: $s, at: $at, type: "sub_stop", sub: {id: "agent-s\($s)", type: "allye:bridge-watcher", outcome: "pass", task: "ALY-258.2", summary: $t, attempt: 1, next: "done", gate: "WATCHER_APPROVED", checks: {ok: 1, run: 2}, findings: {critical: 0, high: 1, medium: 2, low: 3, info: 4}}}'; }
CJK=$(printf '字%.0s' $(seq 1 140))
sentr_seqs() { [ -f "$SB/api/ingest-bodies.log" ] && "$JQ_BIN" -r '.events[] | select(.type == "sub_stop") | .seq' "$SB/api/ingest-bodies.log" || true; }
sp2() { mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$DATA/live/$(test_sha "$RAWSID").spool"; : >"$SPF"; chmod 600 "$SPF"; }
new_case; mkcred; SHIMD="$SHIMS"; sp2; for i in $(seq 1 60); do sumline "$((2000 + i))" "$CJK"; done >"$SPF"; run_fixture user-prompt-submit
check "AC-11/NFR-03: 60 events with 140-code-point summaries split into several requests, each at most 16384 B and 50 events" "yes yes yes" \
  "$([ "$(wc -l <"$SB/api/ingest-bodies.log" | tr -d ' ')" -ge 2 ] && echo yes || echo no) $([ "$(awk '{ if (length($0) > m) m = length($0) } END { print m }' "$SB/api/ingest-bodies.log")" -le 16384 ] && echo yes || echo no) $([ "$("$JQ_BIN" -r '.events | length' "$SB/api/ingest-bodies.log" | sort -n | tail -n 1)" -le 50 ] && echo yes || echo no)"
check "AC-11: nothing lost: all 60 events sent once, in order, none left in the spool" "60 60 yes 0" "$(sentr_seqs | wc -l | tr -d ' ') $(sentr_seqs | sort -n | uniq | wc -l | tr -d ' ') $(sentr_seqs | awk 'NR > 1 && $1 <= p { b = 1 } { p = $1 } END { print (b ? "no" : "yes") }') $(grep -c '"sub_stop"' "$SPF" || true)"
check "AC-11: every new nested key leaves intact (no silent drop)" "60" "$("$JQ_BIN" -c --arg t "$CJK" '.events[] | select(.sub.summary == $t and .sub.attempt == 1 and .sub.next == "done" and .sub.gate == "WATCHER_APPROVED" and .sub.checks == {ok: 1, run: 2} and .sub.findings == {critical: 0, high: 1, medium: 2, low: 3, info: 4} and .sub.task == "ALY-258.2")' "$SB/api/ingest-bodies.log" | wc -l | tr -d ' ')"
end_case
# the defensive value checks of the allowlist: a wrong type or range drops that field, never the event
new_case; mkcred; SHIMD="$SHIMS"; sp2
{ "$JQ_BIN" -nc --arg at "$(nowiso)" '{seq: 3001, at: $at, type: "sub_stop", sub: {id: "agent-w1", type: "allye:bridge-pilot", outcome: "pass", summary: 5, attempt: 3, next: "nobody", gate: "x", checks: {ok: 100, run: 1}, findings: {critical: 1}, evil: "MARKER_ABCDEF"}}'
  "$JQ_BIN" -nc --arg at "$(nowiso)" '{seq: 3002, at: $at, type: "sub_stop", sub: {id: "agent-w2", type: "allye:bridge-pilot", outcome: "pass", attempt: 1.5, checks: {ok: 1, run: 2, extra: "MARKER_ABCDEF"}, summary: "ok"}}'; } >"$SPF"; run_fixture user-prompt-submit
check "allowlist: wrong types and ranges drop the field, the event and its valid keys stay; a nested object keeps only its keys" '{"id":"agent-w1","outcome":"pass","type":"allye:bridge-pilot"}|{"checks":{"ok":1,"run":2},"id":"agent-w2","outcome":"pass","summary":"ok","type":"allye:bridge-pilot"}' \
  "$("$JQ_BIN" -cS '.events[] | select(.seq == 3001) | .sub' "$SB/api/ingest-bodies.log")|$("$JQ_BIN" -cS '.events[] | select(.seq == 3002) | .sub' "$SB/api/ingest-bodies.log")"
check "allowlist: the extra key inside checks and the unknown key of sub are in no body" "0" "$(grep -cE 'MARKER_ABCDEF|extra' "$SB/api/ingest-bodies.log" || true)"
end_case

# ─── ALY-203.4: mission gates (BR-10, AC-08, AC-16) ─────────────────────────
echo "== mission gates from the journal (AC-08, AC-16) =="
SHA1=GATESHA1MARKER; SHA2=GATESHA2MARKER
gates_line() {  # S W C M: values (use - for the dash)
  local v; v() { [ "$1" = "-" ] && printf '\xe2\x80\x94' || printf '%s' "$1"; }
  printf -- '- Gates: SHIELD_CLEAR %s \xc2\xb7 WATCHER_APPROVED %s \xc2\xb7 CI_PENDING %s \xc2\xb7 MISSION_COMPLETE %s\n' "$(v "$1")" "$(v "$2")" "$(v "$3")" "$(v "$4")"
}
mklog() {  # SLUG LINE...: writes $SB/proj/.allye/missions/SLUG/log.md (real directories)
  local slug="$1"; shift
  mkdir -p "$SB/proj/.allye/missions/$slug"; { echo "# Mission log MARKER_GATEFILE"; echo; printf '%s\n' "$@"; echo "- Other: MARKER_GATEFILE"; } >"$SB/proj/.allye/missions/$slug/log.md"
}
# fire TOOL [FILEPATH]: PostToolUse for the sandbox project
fire() {
  "$JQ_BIN" -n --arg t "$1" --arg f "${2-$SB/proj/.allye/missions/m-1/log.md}" --arg c "${GCWDV-$SB/proj}" \
    '{session_id:"sess-gate-1",hook_event_name:"PostToolUse",cwd:$c,tool_name:$t,tool_input:{file_path:$f,content:"MARKER_GATEFILE"},tool_response:{}}' >"$SB/stdin"
  run_hook
}
gev() { spooled sess-gate-1 | grep '"type":"gates"' || true; }
gevn() { local g; g=$(gev); [ -n "$g" ] && printf '%s\n' "$g" | grep -c . || echo 0; }
GATEFILES() { find "$DATA/live" -type f -exec cat {} + 2>/dev/null; }
gcase() {  # LABEL S W C M EXPECTED-ARRAY (tokens)
  new_case; mkcred; mklog m-1 "$(gates_line "$2" "$3" "$4" "$5")"; fire Write
  if [ "$6" = "[]" ]; then check "$1" "0" "$(gevn)"; else check "$1" "{\"gates\":$6,\"type\":\"gates\"}" "$(gev)"; fi
  check "$1: exit 0, silent" "0||" "$RC|$OUT|$ERR"
  check "$1: sha values and file markers do not leave" "0" "$( { GATEFILES; cat "$SB/out" "$SB/err"; grep -v '^find ' "$SB/log/calls.log"; } | grep -cE 'GATESHA|MARKER_GATEFILE|proj/.allye|log\.md' || true)"
  end_case
}
gcase "all dashes: no gates yet, nothing sent" - - - - '[]'
gcase "SHIELD_CLEAR only" "$SHA1" - - - '["SHIELD_CLEAR"]'
gcase "WATCHER_APPROVED only" - "$SHA1" - - '["WATCHER_APPROVED"]'
gcase "CI_PENDING only" - - "$SHA1" - '["CI_PENDING"]'
gcase "MISSION_COMPLETE only" - - - "$SHA1" '["MISSION_COMPLETE"]'
gcase "all four" "$SHA1" "$SHA2" "$SHA1" "$SHA2" '["SHIELD_CLEAR","WATCHER_APPROVED","MISSION_COMPLETE","CI_PENDING"]'
gcase "mixed" "$SHA1" - "$SHA2" - '["SHIELD_CLEAR","CI_PENDING"]'
new_case; mkcred; mklog m-1 "- Gates: SHIELD_CLEAR $SHA1 · WATCHER_APPROVED · BOGUS_TOKEN $SHA2 · CI_PENDING —"; fire Write
check "empty value, unknown token: only SHIELD_CLEAR" '{"gates":["SHIELD_CLEAR"],"type":"gates"}' "$(gev)"; end_case
new_case; mkcred; mklog m-1 "- Notes: Gates: SHIELD_CLEAR $SHA1" "  - Gates: SHIELD_CLEAR $SHA1"; fire Write
check "a Gates: text that is not a line starting with '- Gates:' counts for nothing" "0" "$(gevn)"; end_case
new_case; mkcred; mklog m-1 "- Gates: SHIELD_CLEAR $SHA1 · WATCHER_APPROVED —" "- Gates: MISSION_COMPLETE $SHA2"; fire Write
check "the first Gates line wins" '{"gates":["SHIELD_CLEAR"],"type":"gates"}' "$(gev)"; end_case
new_case; mkcred; mklog m-1 "no gates line here"; fire Write
check "no Gates line: nothing sent" "0" "$(gevn)"; end_case

echo "== gates: complete set, only on change =="
new_case; mkcred
mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write
fire Edit
mklog m-1 "$(gates_line "$SHA2" - - -)"; fire Write
check "same set (different sha values) is not repeated" "1" "$(gevn)"
mklog m-1 "$(gates_line "$SHA1" "$SHA1" - -)"; fire Edit
check "set grows: the complete set is sent" "$(printf '%s\n%s\n' '{"gates":["SHIELD_CLEAR"],"type":"gates"}' '{"gates":["SHIELD_CLEAR","WATCHER_APPROVED"],"type":"gates"}')" "$(gev)"
mklog m-1 "$(gates_line - - - -)"; fire Write
check "back to all dashes: the empty set is sent" '{"gates":[],"type":"gates"}' "$(gev | tail -n 1)"
fire Write
check "empty set is not repeated" "3" "$(gevn)"
check "gate state file: private, keyed by hash, holds only the token set" "600 [] 1" "$(find "$DATA/live/$(test_sha sess-gate-1).gates" -printf '%m') $(cat "$DATA/live/$(test_sha sess-gate-1).gates") $(find "$DATA/live" -name '*.gates' | grep -c .)"
check "gate files: nothing but contract fields (no path, no sha)" "0" "$(GATEFILES | grep -cE 'GATESHA|MARKER_GATEFILE|log\.md|proj' || true)"
GF="$DATA/live/$(test_sha sess-gate-1).gates"; rm -f "$GF"; : >"$GF"; chmod 644 "$GF"
mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write
check "gate state with a wrong mode: nothing sent" "3" "$(gevn)"
rm -f "$GF"; ln -s "$SB/stdin" "$GF"; fire Write
check "symlinked gate state: nothing sent, target untouched" "3|yes" "$(gevn)|$([ -s "$SB/stdin" ] && echo yes || echo no)"
end_case

echo "== gates: other files, tools and paths send nothing (AC-08, AC-16) =="
no_gates() {  # LABEL, after the event(s) have fired
  check "$1: no gates event" "0" "$(gevn)"
  check "$1: exit 0, silent" "0||" "$RC|$OUT|$ERR"
}
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Read; no_gates "tool Read"; end_case
for badti in '"str"' 'null' '[1]'; do
  new_case; mkcred; run_fixture permission-request
  "$JQ_BIN" --argjson t "$badti" '.tool_name = "Write" | .tool_input = $t' "$FIX/post-tool-use.json" >"$SB/stdin"; run_hook
  check "Write with tool_input $badti after waiting: working still spooled, no gates" "$(printf '%s\n%s\n' "$WP" "$W" | "$JQ_BIN" -cS .)|0||" "$(spooled)|$RC|$OUT|$ERR"; end_case
done
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Bash; no_gates "tool Bash"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire NotebookEdit; no_gates "tool NotebookEdit"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"
"$JQ_BIN" -n --arg f "$SB/proj/.allye/missions/m-1/log.md" --arg c "$SB/proj" '{session_id:"sess-gate-1",hook_event_name:"PreToolUse",cwd:$c,tool_name:"Write",tool_input:{file_path:$f}}' >"$SB/stdin"; run_hook
no_gates "PreToolUse (file not written yet)"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"
"$JQ_BIN" -n --arg f "$SB/proj/.allye/missions/m-1/log.md" --arg c "$SB/proj" '{session_id:"sess-gate-1",hook_event_name:"PostToolUse",agent_id:"agent-abc123",agent_type:"allye:bridge-pilot",cwd:$c,tool_name:"Write",tool_input:{file_path:$f}}' >"$SB/stdin"; run_hook
no_gates "write made inside a subagent"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/missions/m-1/crew/shield.md"; no_gates "crew file"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; cp "$SB/proj/.allye/missions/m-1/log.md" "$SB/proj/.allye/missions/m-1/notes.md"; fire Write "$SB/proj/.allye/missions/m-1/notes.md"; no_gates "another file name in the mission dir"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/missions/m-1/sub/log.md"; no_gates "log.md one level too deep"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; mkdir -p "$SB/proj/other"; cp "$SB/proj/.allye/missions/m-1/log.md" "$SB/proj/other/log.md"; fire Write "$SB/proj/other/log.md"; no_gates "log.md in another directory"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/log.md"; no_gates "log.md directly in .allye"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/missions/../missions/m-1/log.md"; no_gates "path with .. inside"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; mkdir -p "$SB/proj/x"; fire Write "$SB/proj/x/../.allye/missions/m-1/log.md"; no_gates "path with .. before .allye"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write ".allye/missions/m-1/log.md"; no_gates "relative file path"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; GCWDV="relative/dir" fire Write; no_gates "relative cwd"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; GCWDV="$SB/proj/" fire Write "$SB/proj//.allye/missions/m-1/log.md"; no_gates "double slash"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; GCWDV="$SB/other" fire Write; no_gates "file outside the cwd of the payload"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; GCWDV="$(printf '%s\n/etc' "$SB/proj")" fire Write; no_gates "cwd with a control character"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/missions/m-1/log.md"$'\n'; no_gates "file path ending in a newline"; end_case
for bad in Upper UPPER m.1 m_1 m..1 "m 1" ""; do
  new_case; mkcred; mkdir -p "$SB/proj/.allye/missions/ok"; mklog "ok" "$(gates_line "$SHA1" - - -)"
  if [ -n "$bad" ]; then mkdir -p "$SB/proj/.allye/missions/$bad"; cp "$SB/proj/.allye/missions/ok/log.md" "$SB/proj/.allye/missions/$bad/log.md"; fi
  fire Write "$SB/proj/.allye/missions/$bad/log.md"; no_gates "slug '$bad'"; end_case
done
new_case; mkcred; LONG=$(head -c 81 /dev/zero | tr '\0' 'a'); mklog "$LONG" "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/missions/$LONG/log.md"; no_gates "slug of 81 characters"; end_case
new_case; mkcred; LONG=$(head -c 80 /dev/zero | tr '\0' 'a'); mklog "$LONG" "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/missions/$LONG/log.md"
check "slug of 80 characters is accepted (counterpart)" '{"gates":["SHIELD_CLEAR"],"type":"gates"}' "$(gev)"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; mkdir -p "$SB/proj/.allye/missions/9-z-"; cp "$SB/proj/.allye/missions/m-1/log.md" "$SB/proj/.allye/missions/9-z-/log.md"; fire Write "$SB/proj/.allye/missions/9-z-/log.md"
check "lowercase digits and dashes slug is accepted (counterpart)" '{"gates":["SHIELD_CLEAR"],"type":"gates"}' "$(gev)"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; fire Write "$SB/proj/.allye/missions/m-1/missing.md"; no_gates "file does not exist"; end_case
new_case; mkcred; mkdir -p "$SB/proj/.allye/missions/m-1/log.md"; fire Write; no_gates "log.md is a directory"; end_case

echo "== gates: symlinks (AC-16) =="
new_case; mkcred; mklog real "$(gates_line "$SHA1" - - -)"; ln -s "$SB/proj/.allye/missions/real/log.md" "$SB/proj/.allye/missions/m-1" 2>/dev/null; rm -f "$SB/proj/.allye/missions/m-1"
mkdir -p "$SB/proj/.allye/missions/m-1"; ln -s "$SB/proj/.allye/missions/real/log.md" "$SB/proj/.allye/missions/m-1/log.md"; fire Write; no_gates "symlinked log.md"; end_case
new_case; mkcred; mklog real "$(gates_line "$SHA1" - - -)"; ln -s "$SB/proj/.allye/missions/real" "$SB/proj/.allye/missions/m-1"; fire Write; no_gates "symlinked slug directory"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; mv "$SB/proj/.allye/missions" "$SB/realmissions"; ln -s "$SB/realmissions" "$SB/proj/.allye/missions"; fire Write; no_gates "symlinked missions directory"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; mv "$SB/proj/.allye" "$SB/realallye"; ln -s "$SB/realallye" "$SB/proj/.allye"; fire Write; no_gates "symlinked .allye directory"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; ln -s "$SB/proj" "$SB/projlink"; GCWDV="$SB/projlink" fire Write "$SB/projlink/.allye/missions/m-1/log.md"
check "a cwd that is itself a symlink to the project is resolved physically and accepted" '{"gates":["SHIELD_CLEAR"],"type":"gates"}' "$(gev)"; end_case
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" - - -)"; ln -s "$SB/proj/.allye/missions/m-1/log.md" "$SB/proj/.allye/missions/m-1/alias.md"; fire Write "$SB/proj/.allye/missions/m-1/alias.md"; no_gates "a symlink to the real log.md under another name"; end_case

echo "== gates: the 64 KB read limit (AC-16) =="
# A logging `head` shim (the shim dir is locked, so it is built here) is the read-size probe: the oversized file must
# never be opened at all, the accepted one is read through head -c 65536.
head_probe() {
  SHIMD="$SB/probeshims"; link_shims "$SHIMD"; ln -sf "$SHIMS_STUB/curl" "$SHIMD/curl"
  printf '#!/bin/bash\nexec "%s/_wrap.sh" head "$@"\n' "$SHIMS" >"$SHIMD/head"; chmod +x "$SHIMD/head"
}
padto() {  # FILE SIZE: append x bytes until the file is exactly SIZE bytes
  local have; have=$(find "$1" -printf '%s')
  head -c $(($2 - have)) /dev/zero | tr '\0' 'x' >>"$1"
}
# oversize: 65537 bytes; a valid Gates line first, so reading any of it would send SHIELD_CLEAR
new_case; mkcred; head_probe; mkdir -p "$SB/proj/.allye/missions/m-1"
gates_line "$SHA1" - - - >"$SB/proj/.allye/missions/m-1/log.md"; padto "$SB/proj/.allye/missions/m-1/log.md" 65537
check "fixture: oversized file is exactly 65537 bytes" "65537" "$(find "$SB/proj/.allye/missions/m-1/log.md" -printf '%s')"
fire Write; no_gates "65537-byte file (valid Gates line inside the first 64 KB)"
check "oversized file: never read (no head -c call at all)" "0" "$(grep -c '^head \[-c\]' "$SB/log/calls.log" || true)"
end_case
# the same file at exactly 65536 bytes is accepted, read through head -c 65536 and nothing else
new_case; mkcred; head_probe; mkdir -p "$SB/proj/.allye/missions/m-1"
gates_line "$SHA1" - - - >"$SB/proj/.allye/missions/m-1/log.md"; padto "$SB/proj/.allye/missions/m-1/log.md" 65536
check "fixture: boundary file is exactly 65536 bytes" "65536" "$(find "$SB/proj/.allye/missions/m-1/log.md" -printf '%s')"
fire Write
check "65536-byte file is accepted (counterpart)" '{"gates":["SHIELD_CLEAR"],"type":"gates"}' "$(gev)"
check "the read is bounded: exactly one head call, head -c 65536" "1|head [-c] [65536] [$SB/proj/.allye/missions/m-1/log.md]" "$(grep -c '^head \[-c\]' "$SB/log/calls.log")|$(grep '^head \[-c\]' "$SB/log/calls.log")"
end_case
# a valid line after 64 KB in a file of unrelated size is simply never reached: file over the limit, Gates line only at the end
new_case; mkcred; head_probe; mkdir -p "$SB/proj/.allye/missions/m-1"
head -c 70000 /dev/zero | tr '\0' 'x' >"$SB/proj/.allye/missions/m-1/log.md"; printf '\n' >>"$SB/proj/.allye/missions/m-1/log.md"; gates_line "$SHA1" - - - >>"$SB/proj/.allye/missions/m-1/log.md"
fire Write; no_gates "valid Gates line only beyond 64 KB"; end_case

echo "== gates: markers =="
new_case; mkcred; mklog m-1 "$(gates_line "$SHA1" "$SHA2" - -)"; fire Write; fire Edit
check "gates event keys are exactly seq, type, gates and at" "seq,type,gates,at" "$("$JQ_BIN" -r 'select(.type=="gates") | keys_unsorted | join(",")' "$DATA/live/$(test_sha sess-gate-1).spool" | head -n 1)"
check "every gates token is in the enumeration" "0" "$("$JQ_BIN" -r 'select(.type=="gates") | .gates[] | select(IN("SHIELD_CLEAR","WATCHER_APPROVED","MISSION_COMPLETE","CI_PENDING") | not)' "$DATA"/live/*.spool | grep -c . || true)"
check "no sha, journal text, path or slug in any file or log" "0" "$( { GATEFILES; find "$DATA" -print; cat "$SB/out" "$SB/err" "$SB/log"/* 2>/dev/null | grep -v '^env\|^PWD\|^find ' ; } | grep -cE 'GATESHA|MARKER_GATEFILE|log\.md|missions|m-1' || true)"
end_case

# ─── AC-02 / AC-14: no marker and no raw session id anywhere ────────────────
echo "== markers and the raw session id (AC-02, AC-14) =="
new_case; mkcred
for f in "$FIX"/*.json; do cp "$f" "$SB/stdin"; run_hook; [ -z "$OUT$ERR" ] || echo "  (output from $(basename "$f"))"; done
ALLTXT="$SB/all.txt"; { find "$DATA" -type f -exec cat {} +; find "$DATA" -print; cat "$SB/log"/* "$SB/api/requests.log" 2>/dev/null; } >"$ALLTXT"
for m in "${MARKERS[@]}"; do check "marker $m absent from every file, filename, shim log and request" "0" "$(grep -cF -- "$m" "$ALLTXT" || true)"; done
check "spool is non-empty (not vacuous)" "yes" "$([ "$(cat "$DATA"/live/*.spool | wc -l | tr -d ' ')" -gt 20 ] && echo yes || echo no)"
check "raw session id absent from every file, filename, shim log and request" "0" "$(grep -cF -- "$RAWSID" "$ALLTXT" || true)"
final_reap "$DATA"; for i in $(seq 1 200); do [ -e "$DATA/live/$(test_sha "$RAWSID").final.lock" ] || break; sleep 0.05; done   # the SessionEnd fixtures' final flusher (stub curl)
check "files are keyed by sha256(session id): acts, bind, cred, flushed, seq, spool, state, subs and touch (no lock left behind)" "$(test_sha "$RAWSID").acts $(test_sha "$RAWSID").bind $(test_sha "$RAWSID").cred $(test_sha "$RAWSID").flushed $(test_sha "$RAWSID").seq $(test_sha "$RAWSID").spool $(test_sha "$RAWSID").state $(test_sha "$RAWSID").subs $(test_sha "$RAWSID").touch" "$(cd "$DATA/live" && ls | tr '\n' ' ' | sed 's/ $//')"
check "stdout and stderr were empty for every payload" "" "$(cat "$SB/out" "$SB/err")"
check "every spool line holds only contract fields (seq included)" "0" "$("$JQ_BIN" -c 'select((keys - ["seq","at","type","state","tool","code","sub","bind","gates","activity"]) | length > 0)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
check "every spool line holds only permitted nested sub keys (ALY-258.1 nested allowlist)" "0" "$("$JQ_BIN" -c 'select((.sub // {} | keys) - ["id","type","outcome","task","desc","summary","attempt","next","gate","checks","findings"] | length > 0)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
check "every state value is in the contract enumeration" "0" "$("$JQ_BIN" -r 'select(.state != null) | .state | select(IN("started","working","waiting_input","idle","error","ended") | not)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
check "every code value is in the contract enumeration" "0" "$("$JQ_BIN" -r 'select(.code != null) | .code | select(IN("turn_ended","asked_question","permission_prompt","advisory","returned","cli_error_rate_limit","cli_error_authentication_failed","cli_error_billing_error","cli_error_invalid_request","cli_error_server_error","cli_error_max_output_tokens","cli_error_unknown","end_clear","end_resume","end_logout","end_prompt_input_exit","end_live_off","end_other") | not)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
end_case

# ─── ALY-217.6: activity phrases (BR-10..BR-13, AC-27..AC-33) ────────────────
# The fixtures activity-bash*, activity-todowrite* and activity-redact-* (the redaction table of AC-30) are checked by
# the generic fixture loop above; these cases cover the cap, the Agent/Task stash, the switch and the privacy scan.
echo "== activity phrases: cap, Agent stash, switch and privacy (ALY-217.6) =="
H6=$(test_sha "$RAWSID"); AGF() { echo "$DATA/live/$H6.agents"; }
# bash_act DESC-JSON: a Bash PreToolUse whose description is the JSON string DESC-JSON (escapes allowed).
bash_act() { "$JQ_BIN" --argjson d "$1" '.tool_input.description = $d' "$FIX/activity-bash.json" >"$SB/stdin"; run_hook; }
# last_act: the activity of the last spooled line ("<none>" when absent), as JSON (escapes for non-ASCII).
last_act() { spooled | tail -n 1 | "$JQ_BIN" -a '.activity // "<none>"'; }
cplen() { "$JQ_BIN" -rn --argjson s "$1" '$s | length'; }
new_case; mkcred
P140=$("$JQ_BIN" -ac '[range(40) | "a\u00e7\u00f5es"] | join(" ") | .[0:140]' <<<null)
P141=$("$JQ_BIN" -ac '[range(40) | "a\u00e7\u00f5es"] | join(" ") | .[0:141]' <<<null)
E141=$("$JQ_BIN" -ac '[range(40) | "a\u00e7\u00f5es"] | join(" ") | .[0:137] + "\u2026"' <<<null)
check "AC-06: the 140-code-point test phrase has 140 code points (more bytes)" "140 yes" "$(cplen "$P140") $([ "$("$JQ_BIN" -rn --argjson s "$P140" '$s | utf8bytelength')" -gt 140 ] && echo yes || echo no)"
bash_act "$P140"; check "AC-06: a phrase of exactly 140 code points is sent unchanged" "$P140" "$(last_act)"
bash_act "$P141"; check "AC-06: 141 code points are cut at the last space, with the ellipsis inside the 140" "$E141 138" "$(last_act) $(cplen "$(last_act)")"
P48='"Atualizando as configura\u00e7\u00f5es do m\u00f3dulo de lan\u00e7amento agora"'
bash_act "$P48"; check "AC-06: a 58-code-point phrase is no longer cut (cap 140)" "$P48" "$(last_act)"
bash_act '"\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9\u00e9 ok go"'
check "AC-06: a short unspaced run is sent whole" "yes" "$(case "$(last_act)" in *'ok go"') echo yes ;; *) echo no ;; esac)"
HARD=$("$JQ_BIN" -nc '("\u00e9" * 150) + " ok go"')
bash_act "$HARD"; check "AC-06: no space in the first 140: a hard cut at 139 multi-byte code points plus the ellipsis (140)" "140 yes" "$(cplen "$(last_act)") $(case "$(last_act)" in *'\u00e9\u2026"') echo yes ;; *) echo no ;; esac)"
bash_act '"Run\tthe\n  unit\r\n\u2028tests   now"'; check "AC-31: tabs, line breaks and runs of spaces become one space" '"Run the unit tests now"' "$(last_act)"
bash_act '"Rebuild the shield report for the release candidate before the gate"'
check "AC-06: a phrase under the cap is sent whole" '"Rebuild the shield report for the release candidate before the gate"' "$(last_act)"
end_case

echo "== activity: the Agent/Task stash correlated with SubagentStart: desc and task on sub_start (ALY-258.1 AC-01, AC-03, AC-16, D-32) =="
T6=1800000000
# agent_pay TOOL TYPE-or-- DESC: a main-session PreToolUse of TOOL with a prompt marker (TYPE -- = no subagent_type).
agent_pay() {
  "$JQ_BIN" -n --arg t "$1" --arg ty "$2" --arg d "$3" --arg s "$RAWSID" '{session_id: $s, cwd: "/work/MARKER_CWD", hook_event_name: "PreToolUse", tool_name: $t,
    tool_input: ({description: $d, prompt: "MARKER_PROMPT_xyz read /etc/MARKER_PATH"} + (if $ty == "--" then {} else {subagent_type: $ty} end)), tool_use_id: "toolu_ag"}
    | if $noid == "1" then del(.tool_use_id) else . end' --arg noid "${AGENT_NOID:-0}" >"$SB/stdin"
}
start_pay() { "$JQ_BIN" -n --arg id "$1" --arg ty "$2" --arg s "$RAWSID" '{session_id: $s, cwd: "/work/MARKER_CWD", hook_event_name: "SubagentStart", agent_id: $id, agent_type: $ty}' >"$SB/stdin"; }
at6() { RUN_ENV=("SHIM_DATE_NOW=$((T6 + $1))"); }
agent() { at6 "$1"; agent_pay "$2" "$3" "$4"; run_hook; }
sstart() { at6 "$1"; start_pay "$2" "$3"; run_hook; }
lines_of() { spooled | "$JQ_BIN" -c "select($1)"; }
# sub_of ID: the sub object of the sub_start of ID; start_of: all sub_start events as "id:desc:task" ("-" when absent).
sub_of() { spooled | "$JQ_BIN" -cS --arg id "$1" 'select(.type == "sub_start" and .sub.id == $id) | .sub'; }
ntool_agent() { lines_of '.type == "sub_tool" and .tool == "Agent"' | grep -c . || true; }
ents() { "$JQ_BIN" -c 'map(.t)' "$(AGF)" 2>/dev/null || echo none; }
new_case; mkcred
agent 0 Agent allye:bridge-medic "Review the spec for gaps"
check "the Agent tool event still carries the cleaned description" '{"activity":"Review the spec for gaps","tool":"Agent","type":"tool"}' "$(spooled | tail -n 1)"
check "AC-16: the stash exists, mode 0600, and holds the type, time, cleaned phrase and the tool_use_id only" "600 yes" "$(find "$(AGF)" -printf '%m') $("$JQ_BIN" -e 'length == 1 and .[0].t == "allye:bridge-medic" and .[0].a == "Review the spec for gaps" and .[0].id == "toolu_ag" and (.[0] | keys) == ["a","id","ms","t"]' "$(AGF)" >/dev/null && echo yes || echo no)"
sstart 5 agent-m1 allye:bridge-medic
check "AC-01: exactly one stashed entry of the type: sub_start carries the cleaned desc" '{"sub":{"desc":"Review the spec for gaps","id":"agent-m1","type":"allye:bridge-medic"},"type":"sub_start"}' "$(spooled | tail -n 1)"
check "AC-01: no separate Agent sub_tool event" "0" "$(ntool_agent)"
check "AC-01: the consumed entry left the stash (an empty stash is removed)" "no" "$([ -e "$(AGF)" ] && echo yes || echo no)"
sstart 6 agent-m2 allye:bridge-medic
check "AC-01: a second sub_start of the type with nothing stashed gets no desc and no task" '{"id":"agent-m2","type":"allye:bridge-medic"}' "$(sub_of agent-m2)"
end_case
# AC-03: the task key comes from the cleaned description (a key the cleaner dropped is never sent)
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Implement ALY-258.1 cleaner for the slice"; sstart 1 agent-t1 allye:bridge-pilot
check "AC-03: the first dotted task key of the description goes on sub_start as sub.task" '{"desc":"Implement ALY-258.1 cleaner for the slice","id":"agent-t1","task":"ALY-258.1","type":"allye:bridge-pilot"}' "$(sub_of agent-t1)"
agent 2 Agent allye:bridge-pilot "Do ALY-258.1 then ALY-258.2 later today"; sstart 3 agent-t2 allye:bridge-pilot
check "AC-03: two keys: the first wins" "ALY-258.1" "$(sub_of agent-t2 | "$JQ_BIN" -r .task)"
agent 4 Agent allye:bridge-pilot "Work on the spec ALY-258 as a whole"; sstart 5 agent-t3 allye:bridge-pilot
check "AC-03: a spec key without the dotted task part is not a task: desc only" '{"desc":"Work on the spec ALY-258 as a whole","id":"agent-t3","type":"allye:bridge-pilot"}' "$(sub_of agent-t3)"
agent 6 Agent allye:bridge-pilot "Work on aly-258.1 in lower case please"; sstart 7 agent-t4 allye:bridge-pilot
check "AC-03: a lower-case key is not a task" "null" "$(sub_of agent-t4 | "$JQ_BIN" -r '.task')"
agent 8 Agent allye:bridge-pilot "Work on ../x/ALY-258.1 now with care"; sstart 9 agent-t5 allye:bridge-pilot
check "AC-03: a key inside a token the cleaner dropped is not sent (the desc is)" '{"desc":"Work on now with care","id":"agent-t5","type":"allye:bridge-pilot"}' "$(sub_of agent-t5)"
agent 10 Agent allye:bridge-pilot "XYZABCDEFGHIJK-1.2 is not a key here today"; sstart 11 agent-t6 allye:bridge-pilot
check "AC-03: a key cannot start in the middle of a longer upper-case word" "null" "$(sub_of agent-t6 | "$JQ_BIN" -r '.task')"
end_case
# AC-16: parallel same-type dispatches are ambiguous: no desc, no task, and the entries of the type are dropped
new_case; mkcred
agent 0 Agent allye:bridge-pilot "First pilot slice ALY-258.1 phrase"; agent 1 Task allye:bridge-pilot "Second pilot slice ALY-258.2 phrase"
check "AC-16: Task works like Agent (its own tool event carries the phrase)" '"Second pilot slice ALY-258.2 phrase"' "$(last_act)"
sstart 2 agent-p1 allye:bridge-pilot; sstart 3 agent-p2 allye:bridge-pilot
check "AC-16: two parallel launches of one type: neither start gets a desc or a task" '{"id":"agent-p1","type":"allye:bridge-pilot"}|{"id":"agent-p2","type":"allye:bridge-pilot"}' "$(sub_of agent-p1)|$(sub_of agent-p2)"
check "AC-16: after the ambiguous start the second start consumes the tombstone that is left (an empty stash is removed)" "no 0" "$([ -e "$(AGF)" ] && echo yes || echo no) $(ntool_agent)"
agent 4 Agent allye:bridge-pilot "Third pilot slice phrase here"; sstart 5 agent-p3 allye:bridge-pilot
check "AC-16: the dropped entries do not linger: a later single dispatch matches again" '"Third pilot slice phrase here"' "$(sub_of agent-p3 | "$JQ_BIN" '.desc')"
end_case
# Shield SHD-01: an ambiguous start poisons the other entries of the type (tombstones) until their TTL
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Pilot launch X1 phrase here"; agent 1 Agent allye:bridge-pilot "Pilot launch X2 phrase here"
sstart 2 agent-x1 allye:bridge-pilot
check "SHD-01: start X1 is ambiguous (X1, X2 in flight): no desc; X2 stays as a tombstone (empty text, poison mark, own ms)" '{"id":"agent-x1","type":"allye:bridge-pilot"}|[{"a":"","ms":1800000001000,"p":true,"t":"allye:bridge-pilot"}]' "$(sub_of agent-x1)|$("$JQ_BIN" -cS 'map(del(.id))' "$(AGF)")"
agent 3 Agent allye:bridge-pilot "Pilot launch X3 phrase here"
sstart 4 agent-x2 allye:bridge-pilot; sstart 5 agent-x3 allye:bridge-pilot
check "SHD-01: X3 dispatched after the ambiguous start: start X2 gets no desc/task, nor does start X3 (the poison stays until the TTL)" '{"id":"agent-x2","type":"allye:bridge-pilot"}|{"id":"agent-x3","type":"allye:bridge-pilot"}' "$(sub_of agent-x2)|$(sub_of agent-x3)"
agent 100 Agent allye:bridge-pilot "Pilot launch X4 phrase here"; sstart 101 agent-x4 allye:bridge-pilot
check "SHD-01: a later dispatch after the TTL matches normally" '"Pilot launch X4 phrase here"' "$(sub_of agent-x4 | "$JQ_BIN" '.desc')"
end_case
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Pilot launch Y1 phrase here"; agent 1 Agent allye:bridge-pilot "Pilot launch Y2 phrase here"; sstart 2 agent-y1 allye:bridge-pilot
agent 3 Agent allye:bridge-medic "Medic launch phrase unaffected"; sstart 4 agent-ym allye:bridge-medic
check "SHD-01: the poison is per subagent type: another type still matches" '"Medic launch phrase unaffected"' "$(sub_of agent-ym | "$JQ_BIN" '.desc')"
sstart 70 agent-y2 allye:bridge-pilot
check "SHD-01: a tombstone older than 60 s is pruned (no entry left)" "no" "$([ -e "$(AGF)" ] && echo yes || echo no)"
end_case
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Pilot phrase for the first type"; agent 1 Agent allye:bridge-medic "Medic phrase for the other type"; sstart 2 agent-c1 allye:bridge-copilot
check "AC-16: a start of a type with no entry gets nothing and leaves the other entries stashed" '{"id":"agent-c1","type":"allye:bridge-copilot"}|["allye:bridge-pilot","allye:bridge-medic"]' "$(sub_of agent-c1)|$(ents)"
sstart 3 agent-c2 allye:bridge-medic; sstart 4 agent-c3 allye:bridge-pilot
check "AC-01: one entry per type: each start gets its own desc" 'Medic phrase for the other type|Pilot phrase for the first type|none' "$(sub_of agent-c2 | "$JQ_BIN" -r .desc)|$(sub_of agent-c3 | "$JQ_BIN" -r .desc)|$(ents)"
end_case
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Pilot phrase that will never start"; sstart 1 agent-d1 allye:bridge-medic
check "AC-16: a dispatch whose subagent never starts (or starts as another type) sends nothing and stays stashed until its TTL" '{"id":"agent-d1","type":"allye:bridge-medic"}|["allye:bridge-pilot"]' "$(sub_of agent-d1)|$(ents)"
sstart 59 agent-d2 allye:bridge-pilot
check "AC-16: within 60 s the matching type still gets it" '"Pilot phrase that will never start"' "$(sub_of agent-d2 | "$JQ_BIN" '.desc')"
end_case
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Pilot phrase that will expire"; sstart 61 agent-z allye:bridge-pilot
check "AC-16: an entry older than 60 s sends no desc and no task and is pruned" '{"id":"agent-z","type":"allye:bridge-pilot"}|no' "$(sub_of agent-z)|$([ -e "$(AGF)" ] && echo yes || echo no)"
agent 100 Agent allye:bridge-pilot "Expired entry for the pilot"; agent 170 Agent allye:bridge-pilot "Fresh entry for the pilot now"; sstart 171 agent-z2 allye:bridge-pilot
check "AC-16: an expired entry does not make a start ambiguous: the one unexpired entry matches" '"Fresh entry for the pilot now"' "$(sub_of agent-z2 | "$JQ_BIN" '.desc')"
end_case
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Go"
check "AC-01: a launch with no usable phrase has a tool event without activity but keeps its stash place" '<none>|1' "$(spooled | head -n 1 | "$JQ_BIN" -r '.activity // "<none>"')|$("$JQ_BIN" 'length' "$(AGF)")"
sstart 1 agent-a1 allye:bridge-pilot
check "AC-01: its start gets no desc and the entry is consumed" '{"id":"agent-a1","type":"allye:bridge-pilot"}|no' "$(sub_of agent-a1)|$([ -e "$(AGF)" ] && echo yes || echo no)"
agent 2 Agent allye:bridge-pilot "Go"; agent 3 Agent allye:bridge-pilot "Pilot phrase kept in line"; sstart 4 agent-a2 allye:bridge-pilot
check "AC-16: an empty entry and a phrase of one type are two dispatches: ambiguous, no desc" '{"id":"agent-a2","type":"allye:bridge-pilot"}' "$(sub_of agent-a2)"
end_case
new_case; mkcred
agent 0 Agent -- "General purpose search task"; sstart 1 agent-g1 general-purpose
check "AC-01: an absent subagent_type counts as general-purpose" '"General purpose search task"' "$(sub_of agent-g1 | "$JQ_BIN" '.desc')"
agent 2 Agent 'bad type with spaces' "Phrase with a bad type"
check "a subagent_type failing its pattern is not stashed (the tool event keeps its phrase)" '"Phrase with a bad type" no' "$(last_act) $([ -e "$(AGF)" ] && echo yes || echo no)"
end_case
new_case; mkcred
AGENT_NOID=1 agent 0 Agent allye:bridge-pilot "Pilot phrase without a tool use id"
check "AC-16: the tool_use_id is stashed when the payload has it only (here none: no id key)" '["a","ms","t"]' "$("$JQ_BIN" -c '.[0] | keys' "$(AGF)")"
sstart 1 agent-n1 allye:bridge-pilot
check "AC-16: matching is by type within the TTL (SubagentStart carries no tool_use_id): desc still attached" '"Pilot phrase without a tool use id"' "$(sub_of agent-n1 | "$JQ_BIN" '.desc')"
end_case
new_case; mkcred
mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
printf '[{"t":"allye:bridge-pilot","ms":%s,"a":"Hand written entry for the pilot","id":123},{"t":"allye:bridge-pilot","ms":%s,"a":"Entry with a hostile id slash","id":"a/b"},{"t":"allye:bridge-medic","ms":%s,"a":"Medic hand written entry here","id":"toolu_ok"}]' $((T6 * 1000 - 1000)) $((T6 * 1000 - 1000)) $((T6 * 1000 - 1000)) >"$(AGF)"; chmod 600 "$(AGF)"
sstart 0 agent-h1 allye:bridge-pilot; sstart 0 agent-h2 allye:bridge-medic
check "a stash entry whose id is not a string or fails the id pattern is ignored; a valid one matches" '{"id":"agent-h1","type":"allye:bridge-pilot"}|Medic hand written entry here' "$(sub_of agent-h1)|$(sub_of agent-h2 | "$JQ_BIN" -r .desc)"
end_case
new_case; mkcred
for i in $(seq 1 20); do agent "$i" Agent allye:bridge-pilot "Pilot launch number $(printf '%02d' "$i") here"; done
check "the stash keeps at most 16 entries (the oldest dropped)" "16 Pilot launch number 05 here" "$("$JQ_BIN" 'length' "$(AGF)") $("$JQ_BIN" -r '.[0].a' "$(AGF)")"
end_case

echo "== synthetic sub_start for unseen subagents (ALY-217.7 AC-35, AC-36, D-26) =="
SUBF() { echo "$DATA/live/$H6.subs"; }
# stool T ID TYPE [TOOL]: a PreToolUse inside subagent ID at T6 + T; ids_of: "<type>:<sub id>" of every spooled line.
stool() {
  at6 "$1"
  "$JQ_BIN" -n --arg id "$2" --arg ty "$3" --arg t "${4:-Read}" --arg s "$RAWSID" '{session_id: $s, cwd: "/work/MARKER_CWD", hook_event_name: "PreToolUse",
    tool_name: $t, tool_input: {file_path: "/x/MARKER_PATH"}, tool_use_id: "toolu_s", agent_id: $id, agent_type: $ty}' >"$SB/stdin"
  run_hook
}
ids_of() { spooled | "$JQ_BIN" -r '"\(.type):\(.sub.id // "")"' | tr '\n' ',' | sed 's/,$//'; }
subs_of() { tr '\n' ' ' <"$(SUBF)" 2>/dev/null | sed 's/ $//'; }
new_case; mkcred
stool 0 agent-bg1 allye:bridge-pilot
check "AC-35: an unseen sub id: a sub_start with the same sub and at, seq just below its sub_tool" "true" \
  "$("$JQ_BIN" -s 'length == 2 and .[0].type == "sub_start" and .[1].type == "sub_tool" and .[0].sub == .[1].sub and .[0].at == .[1].at and .[0].seq + 1 == .[1].seq' "$(spool_of "$RAWSID")")"
check "AC-35/AC-36: the id is added to <hash>.subs (mode 0600, one id per line)" "600|agent-bg1" "$(find "$(SUBF)" -printf '%m' 2>/dev/null)|$(cat "$(SUBF)" 2>/dev/null)"
stool 1 agent-bg1 allye:bridge-pilot
check "AC-35: a later sub_tool of that id gets no second sub_start" "sub_start:agent-bg1,sub_tool:agent-bg1,sub_tool:agent-bg1" "$(ids_of)"
sstart 2 agent-bg1 allye:bridge-pilot
check "AC-36: a SubagentStart for an id already in the set spools no sub_start" "sub_start:agent-bg1,sub_tool:agent-bg1,sub_tool:agent-bg1" "$(ids_of)"
sstart 3 agent-rs1 allye:bridge-medic; stool 4 agent-rs1 allye:bridge-medic
check "AC-36: a real SubagentStart spools its sub_start and adds the id, so its sub_tool gets no synthetic one" \
  "sub_start:agent-bg1,sub_tool:agent-bg1,sub_tool:agent-bg1,sub_start:agent-rs1,sub_tool:agent-rs1|agent-bg1 agent-rs1" "$(ids_of)|$(subs_of)"
"$JQ_BIN" '.agent_id = "agent-rs1" | .agent_type = "allye:bridge-medic"' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "a SubagentStop of a seen id gets no sub_start" "sub_stop:agent-rs1" "$(ids_of | sed 's/.*,//')"
end_case
# AC-36: 64 ids at most, the oldest dropped; ids that fail the pattern are never used or written
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
for i in $(seq 1 64); do echo "agent-c$i"; done >"$(SUBF)"; chmod 600 "$(SUBF)"
stool 0 agent-c1 allye:bridge-pilot
check "AC-36: an id already in a full set: no sub_start, the set is left as it is" "sub_tool:agent-c1|64" "$(ids_of)|$(wc -l <"$(SUBF)" | tr -d ' ')"
stool 1 agent-new allye:bridge-pilot
check "AC-36: a new id in a full set: the set keeps 64 ids, the oldest dropped, the new one last, still 0600" "64 agent-c2 agent-new 600" \
  "$(wc -l <"$(SUBF)" | tr -d ' ') $(head -n 1 "$(SUBF)") $(tail -n 1 "$(SUBF)") $(find "$(SUBF)" -printf '%m')"
printf 'agent-ok\nbad id!\nagent/MARKER_AGENT\n%s\n' "$(printf 'x%.0s' $(seq 1 65))" >"$(SUBF)"
stool 2 agent-x allye:bridge-pilot
check "AC-36: ids failing the sub id pattern are dropped when the set is read and rewritten" "agent-ok agent-x" "$(subs_of)"
run_fixture sub-tool-unseen-bad-id
check "AC-36: a sub_tool whose id fails the pattern spools nothing and never reaches the set" "agent-ok agent-x|0" "$(subs_of)|$(grep -c MARKER_AGENT "$(spool_of "$RAWSID")" || true)"
end_case
# fail safe: a set that is not a private regular file is neither used nor rewritten (no synthetic sub_start then)
for kind in mode symlink; do
  new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; printf 'agent-f1\n' >"$SB/subs.real"; chmod 600 "$SB/subs.real"
  if [ "$kind" = mode ]; then cp "$SB/subs.real" "$(SUBF)"; chmod 644 "$(SUBF)"; else ln -s "$SB/subs.real" "$(SUBF)"; fi
  stool 0 agent-f2 allye:bridge-pilot
  check "a set with a foreign $kind: the sub_tool is spooled alone and the set is not rewritten" "sub_tool:agent-f2|agent-f1" "$(ids_of)|$(cat "$SB/subs.real")"
  end_case
done
# D-24/D-26, AC-02: the synthetic sub_start consumes the Agent stash exactly like a real SubagentStart
new_case; mkcred
agent 0 Agent allye:bridge-pilot "Implement ALY-258.1 the slice now"
stool 1 agent-bgp allye:bridge-pilot
check "AC-02: the synthetic sub_start of a background agent carries desc and task; no Agent sub_tool; then the tool" \
  "sub_start:|sub_tool:Read" "$(lines_of '.sub.id == "agent-bgp"' | "$JQ_BIN" -r '"\(.type):\(.tool // "")"' | tr '\n' '|' | sed 's/|$//')"
check "AC-02: its sub is {id, type, desc, task}" '{"desc":"Implement ALY-258.1 the slice now","id":"agent-bgp","task":"ALY-258.1","type":"allye:bridge-pilot"}' "$(sub_of agent-bgp)"
check "D-26: the consumed stash entry is gone; seq order kept" "no true" "$([ -e "$(AGF)" ] && echo yes || echo no) $("$JQ_BIN" -s '[.[] | select(.sub.id == "agent-bgp") | .seq] | . == sort and (.[1] == .[0] + 1)' "$(spool_of "$RAWSID")")"
stool 2 agent-bgq allye:bridge-pilot
check "AC-02: a second unseen agent of the type with nothing stashed gets a bare sub_start" '{"id":"agent-bgq","type":"allye:bridge-pilot"}' "$(sub_of agent-bgq)"
end_case
new_case; mkcred
agent 0 Agent allye:bridge-pilot "First background pilot phrase"; agent 1 Agent allye:bridge-pilot "Second background pilot phrase"
stool 2 agent-bgr allye:bridge-pilot; stool 3 agent-bgs allye:bridge-pilot
check "AC-02/AC-16: two parallel same-type dispatches: neither synthetic sub_start gets a desc" '{"id":"agent-bgr","type":"allye:bridge-pilot"}|{"id":"agent-bgs","type":"allye:bridge-pilot"}' "$(sub_of agent-bgr)|$(sub_of agent-bgs)"
end_case

echo "== activity: on by default, the activity-off flag, live off (AC-32) =="
new_case; mkcred
run_fixture activity-bash; check "AC-32: no flag: the phrase is sent" '"Run the agent runs unit tests"' "$(last_act)"
: >"$DATA/live/activity-off"; chmod 600 "$DATA/live/activity-off"
run_fixture activity-bash activity-todowrite; agent 0 Agent allye:bridge-pilot "Pilot phrase while off"; sstart 1 agent-o1 allye:bridge-pilot
check "AC-32: flag set: tool events still spooled, none carries activity, no sub_tool, no agents stash" "4 0 0 no" \
  "$(spooled | tail -n 4 | grep -c .) $(spooled | tail -n 4 | grep -c '"activity"' || true) $(lines_of '.type == "sub_tool"' | grep -c . || true) $([ -e "$(AGF)" ] && echo yes || echo no)"
check "ALY-258.1 BR-03: flag set: the sub_start carries neither desc nor task" '{"id":"agent-o1","type":"allye:bridge-pilot"}' "$(sub_of agent-o1)"
rm -f "$DATA/live/activity-off"; run_fixture activity-bash
check "AC-32: flag removed: phrases are sent again from the next hook" '"Run the agent runs unit tests"' "$(last_act)"
ln -s "$SB/nowhere" "$DATA/live/activity-off"; run_fixture activity-todowrite
check "AC-32: a dangling symlink named activity-off also counts as off (fail safe)" '"<none>"' "$(last_act)"
rm -f "$DATA/live/activity-off"
N6=$(spooled | grep -c .); : >"$DATA/live/off"; chmod 600 "$DATA/live/off"; run_fixture activity-bash
check "AC-32: live off: nothing is spooled whatever the activity flag" "$N6" "$(spooled | grep -c .)"
end_case

echo "== activity: privacy (BR-13, AC-33) =="
new_case; mkcred; SHIMD="$SHIMS"
for n in activity-bash activity-bash-subagent activity-todowrite activity-todowrite-subagent activity-redact-path activity-redact-secret activity-redact-bearer activity-redact-backticks activity-redact-token activity-redact-email activity-redact-url; do run_fixture "$n"; done
agent 0 Agent allye:bridge-pilot "Inspect /etc/MARKER_PATH with token=MARKER_ARGS now please"
agent 1 Agent allye:bridge-medic "Second launch phrase read back from the stash"
check "AC-33: the agents stash is 0600 in the 0700 live directory and holds only the cleaned phrase" "600 700 Inspect with now please" "$(find "$(AGF)" -printf '%m') $(find "$DATA/live" -maxdepth 0 -printf '%m') $("$JQ_BIN" -r '.[0].a' "$(AGF)")"
for i in $(seq 1 100); do [ -s "$SB/api/ingest-bodies.log" ] && break; sleep 0.05; done; wait_idle
SCAN6="$SB/scan6.txt"; { find "$DATA" -type f ! -name hook-credential.json -exec cat {} +; find "$DATA" -print; cat "$SB/log/calls.log" "$SB/log/curl-config.log" "$SB/api/requests.log" "$SB/api/ingest-bodies.log" 2>/dev/null; } >"$SCAN6"
check "AC-33: phrases reached the API (the scan is not vacuous)" "yes" "$(grep -q 'Run the agent runs unit tests' "$SB/api/ingest-bodies.log" 2>/dev/null && echo yes || echo no)"
N6=0; for m in "$RAWSID" "${MARKERS[@]}"; do [ "$(grep -cF -- "$m" "$SCAN6" || true)" = 0 ] || { N6=$((N6 + 1)); echo "    found: $m"; }; done
check "AC-33: no command, prompt, todo content or dropped description part in files, names, curl argv/config or request bodies" "0" "$N6"
sstart 2 agent-q1 allye:bridge-medic
wait_idle
check "ALY-217.6 SHD-02: the stash was read back (a sub_start carries its desc), so the argv check below is not vacuous" "yes" "$(cat "$(spool_of "$RAWSID")" "$SB/api/ingest-bodies.log" 2>/dev/null | "$JQ_BIN" -r 'select(.type == "sub_start"), (.events[]? | select(.type == "sub_start")) | .sub.desc' 2>/dev/null | grep -qx 'Second launch phrase read back from the stash' && echo yes || echo no)"
check "ALY-217.6 SHD-02: no phrase or stash text in the argv of any jq, curl or other tool call (calls.log)" "0" \
  "$(grep -cE 'Run the agent runs unit tests|Writing the activity phrase tests|Inspect with now please|Second launch phrase|Login with and then' "$SB/log/calls.log" || true)"
end_case

echo "== activity: Detailed Live ack flag, texts stripped at flush, stash cleared (ALY-258.3 AC-08, AC-14, BR-03, D-36) =="
# detailed-off: the local flag written when a 2xx ack carries `detailed: false` (strict boolean); any other 2xx ack clears it.
DOFF() { echo "$DATA/live/detailed-off"; }
sent_evs() { [ -f "$SB/api/ingest-bodies.log" ] && "$JQ_BIN" -c '.events[]' "$SB/api/ingest-bodies.log" || true; }
ntext() { sent_evs | "$JQ_BIN" -c 'select(has("activity") or (.sub // {} | has("desc") or has("summary")))' | grep -c . || true; }
# seed3: spool one event of every shape that can carry a text, plus the structured fields (low seqs, an empty spool first).
seed3() {
  local at f; at=$(date -u +%Y-%m-%dT%H:%M:%SZ); f=$(spool_of "$RAWSID")
  mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
  "$JQ_BIN" -nc --arg at "$at" '[
    {seq: 1000000000001, at: $at, type: "tool", tool: "Bash", activity: "TEXTACT run the unit tests now"},
    {seq: 1000000000002, at: $at, type: "sub_start", sub: {id: "s1", type: "allye:bridge-pilot", desc: "TEXTDESC implement the slice now", task: "ALY-1.2"}},
    {seq: 1000000000003, at: $at, type: "sub_tool", tool: "Read", activity: "TEXTSUBACT reading the files now", sub: {id: "s1", type: "allye:bridge-pilot"}},
    {seq: 1000000000004, at: $at, type: "sub_stop", sub: {id: "s1", type: "allye:bridge-pilot", outcome: "done", task: "ALY-1.2", summary: "TEXTSUM all green here now", attempt: 1, next: "watcher", checks: {ok: 3, run: 3}, findings: {critical: 0, high: 0, medium: 1, low: 0, info: 0}, gate: "SHIELD_CLEAR"}}
  ] | .[]' >>"$f"; chmod 600 "$f"
}
# ack3 MODE: a fresh case against the real curl shim; the first state change is sent at once and its ack is MODE.
ack3() { new_case; mkcred; SHIMD="$SHIMS"; [ -z "$1" ] || printf '%s' "$1" >"$SB/api/ingest-detailed"; }
ack3 false; run_fixture user-prompt-submit; wait_idle
check "AC-14: a 2xx ack with detailed:false writes the local flag: regular file, 0600, one request, no extra call" "yes 600 1" "$([ -f "$(DOFF)" ] && [ ! -L "$(DOFF)" ] && echo yes || echo no) $(find "$(DOFF)" -printf '%m' 2>/dev/null) $(reqs)"
check "AC-14: the flag holds no text" "0" "$(wc -c <"$(DOFF)" | tr -d ' ')"
seed3; run_fixture session-start-startup; wait_idle
check "AC-14/BR-03: events spooled with texts before the flag are stripped at flush (no activity, desc or summary, no text)" "0 0" "$(sent_evs | grep -c 'TEXT' || true) $(ntext)"
check "AC-14: the stripped events are all sent (tool, sub_start, sub_tool, sub_stop)" "tool sub_start sub_tool sub_stop" "$(sent_evs | "$JQ_BIN" -r 'select(.seq >= 1000000000001 and .seq <= 1000000000004) | .type' | tr '\n' ' ' | sed 's/ $//')"
check "BR-03: structured fields continue (task, attempt, next, checks, findings, gate, outcome)" '{"attempt":1,"checks":{"ok":3,"run":3},"findings":{"critical":0,"high":0,"info":0,"low":0,"medium":1},"gate":"SHIELD_CLEAR","id":"s1","next":"watcher","outcome":"done","task":"ALY-1.2","type":"allye:bridge-pilot"}' "$(sent_evs | "$JQ_BIN" -cS 'select(.type == "sub_stop") | .sub' | tail -n 1)"
check "BR-03: the sub_start keeps its id, type and task" '{"id":"s1","task":"ALY-1.2","type":"allye:bridge-pilot"}' "$(sent_evs | "$JQ_BIN" -cS 'select(.type == "sub_start") | .sub' | tail -n 1)"
check "the bodies contain no TEXT marker at all" "0" "$(grep -c TEXT "$SB/api/ingest-bodies.log" || true)"
# with the flag, the hook itself attaches no text and writes no stash (and clears the one that exists)
last_sent_act() { sent_evs | tail -n 1 | "$JQ_BIN" -a '.activity // "<none>"'; }
run_fixture activity-bash; wait_idle; check "BR-03: flag set: the tool event goes out without activity" '"<none>"' "$(last_sent_act)"
agent 3 Agent allye:bridge-pilot "Pilot phrase while the API says detailed false"; sstart 4 agent-dl1 allye:bridge-pilot; wait_idle
check "BR-03: flag set: no agents stash, and the sub_start carries neither desc nor task" 'no {"id":"agent-dl1","type":"allye:bridge-pilot"}' "$([ -e "$(AGF)" ] && echo yes || echo no) $(sent_evs | "$JQ_BIN" -cS 'select(.type == "sub_start" and .sub.id == "agent-dl1") | .sub')"
end_case

# the stash is cleared when texts go off (the flag appears after the stash was written)
ack3 false; SHIMD="$SHIMS_STUB"; agent 0 Agent allye:bridge-pilot "Stashed before the flag appeared"
check "setup: the stash exists before the ack" "yes" "$([ -f "$(AGF)" ] && echo yes || echo no)"
SHIMD="$SHIMS"; run_fixture user-prompt-submit; wait_idle
check "BR-03: with the flag, the Agent stash is deleted" "no yes" "$([ -e "$(AGF)" ] || [ -L "$(AGF)" ] && echo yes || echo no) $([ -f "$(DOFF)" ] && echo yes || echo no)"
end_case

# the stash is also cleared by the hook when the activity-off flag is set (BR-03, AC-08)
new_case; mkcred; agent 0 Agent allye:bridge-pilot "Stashed before the opt-out"
[ -f "$(AGF)" ] || echo "    setup: no stash"; : >"$DATA/live/activity-off"; chmod 600 "$DATA/live/activity-off"; run_fixture activity-bash
check "AC-08: with activity-off, an existing Agent stash is deleted at the next hook" "no" "$([ -e "$(AGF)" ] && echo yes || echo no)"
mkdir -p "$SB/elsewhere"; printf 'x' >"$SB/elsewhere/target"; ln -s "$SB/elsewhere/target" "$(AGF)"; run_fixture activity-bash
check "AC-08: a stash that is a symlink is removed as the link, never its target" "yes" "$([ "$(cat "$SB/elsewhere/target")" = x ] && echo yes || echo no)"
end_case

# activity-off strips at flush too, and sends the structure
new_case; mkcred; SHIMD="$SHIMS"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/activity-off"; chmod 600 "$DATA/live/activity-off"
seed3; run_fixture user-prompt-submit; wait_idle
check "AC-08/BR-03: activity-off: spooled texts are stripped at flush, structure sent" "0 4" "$(ntext) $(sent_evs | grep -c '"seq":100000000000[1-4]' || true)"
check "activity-off alone writes no detailed-off flag" "no" "$([ -e "$(DOFF)" ] && echo yes || echo no)"
end_case

# the final flusher / SessionEnd path strips too
ack3 ""; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$(DOFF)"; chmod 600 "$(DOFF)"
seed3; run_fixture session-end-clear; wait_idle
check "AC-14: SessionEnd (hook send): spooled texts are stripped, the ended event goes out" "0 yes" "$(ntext) $(sent_evs | grep -q '"state":"ended"' && echo yes || echo no)"
end_case
ack3 ""; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$(DOFF)"; chmod 600 "$(DOFF)"
printf '5xx' >"$SB/api/ingest-mode"; seed3; run_fixture user-prompt-submit; wait_idle
printf 'ok' >"$SB/api/ingest-mode"; : >"$SB/api/ingest-bodies.log"; run_fixture session-end-clear; wait_idle
for i in $(seq 1 200); do [ -z "$(ls -d "$DATA"/live/*.final.lock 2>/dev/null)" ] && break; sleep 0.05; done
check "AC-14: SessionEnd after a failed flush: the sent bodies carry no text" "0" "$(ntext)"
end_case

# a valid ack that is not the strict boolean false clears the flag (absent = true); none of them can set it
for m in true "" junk null; do
  ack3 "$m"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$(DOFF)"; chmod 600 "$(DOFF)"
  run_fixture user-prompt-submit; wait_idle
  check "AC-14: valid ack '${m:-<no field>}' clears the flag (absent = true), one request" "no 1" "$([ -e "$(DOFF)" ] || [ -L "$(DOFF)" ] && echo yes || echo no) $(reqs)"
  end_case
done
# a 2xx that is not a valid ack (empty, not JSON) neither sets nor clears the flag (Shield SHD-01: fail closed)
for m in nobody notjson; do
  ack3 "$m"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$(DOFF)"; chmod 600 "$(DOFF)"
  run_fixture user-prompt-submit; wait_idle
  check "SHD-01: 2xx without a valid ack ('$m') leaves an existing flag set, one request" "yes 1" "$([ -e "$(DOFF)" ] && echo yes || echo no) $(reqs)"
  end_case
  ack3 "$m"; run_fixture user-prompt-submit; wait_idle
  check "SHD-01: 2xx without a valid ack ('$m') does not set a missing flag" "no" "$([ -e "$(DOFF)" ] || [ -L "$(DOFF)" ] && echo yes || echo no)"
  end_case
done
for m in true "" junk null; do
  ack3 "$m"; run_fixture user-prompt-submit; wait_idle
  check "AC-14: ack '${m:-<no field>}' never sets the flag" "no" "$([ -e "$(DOFF)" ] || [ -L "$(DOFF)" ] && echo yes || echo no)"
  end_case
done
# a failed or non-2xx send changes nothing
for m in 5xx 400 413 429 403 422 401-other drop; do
  ack3 false; printf '%s' "$m" >"$SB/api/ingest-mode"; run_fixture user-prompt-submit; wait_idle
  A=$([ -e "$(DOFF)" ] && echo yes || echo no)
  rm -rf "$SB/api/ingest-mode"; end_case
  ack3 true; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$(DOFF)"; chmod 600 "$(DOFF)"; printf '%s' "$m" >"$SB/api/ingest-mode"; run_fixture user-prompt-submit; wait_idle
  check "AC-14: answer '$m': the flag is neither set (detailed:false) nor cleared (detailed:true)" "no yes" "$A $([ -e "$(DOFF)" ] && echo yes || echo no)"
  end_case
done
# a 200 KB ack is not read: the send fails closed, the flag is unchanged
ack3 false; printf 'huge' >"$SB/api/ingest-mode"; run_fixture user-prompt-submit; wait_idle
check "AC-14: a huge ack (200 KB of padding) never sets the flag" "no" "$([ -e "$(DOFF)" ] && echo yes || echo no)"
end_case
ack3 true; printf 'huge' >"$SB/api/ingest-mode"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$(DOFF)"; chmod 600 "$(DOFF)"; run_fixture user-prompt-submit; wait_idle
check "AC-14: a huge ack leaves an existing flag as it is (the send failed, nothing was read)" "yes" "$([ -e "$(DOFF)" ] && echo yes || echo no)"
end_case
# the flag is re-evaluated at each flush: cleared by an ack true, the next flush carries texts again
ack3 false; run_fixture user-prompt-submit; wait_idle
printf 'true' >"$SB/api/ingest-detailed"; run_fixture session-start-startup; wait_idle
check "AC-14: ack true after ack false removes the flag again" "no" "$([ -e "$(DOFF)" ] && echo yes || echo no)"
run_fixture activity-bash; wait_idle; check "AC-14: with the flag gone the next tool event carries its activity again" '"Run the agent runs unit tests"' "$(last_sent_act)"
end_case
# fail-safe existence test and no symlink following
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; ln -s "$SB/nowhere" "$(DOFF)"; run_fixture activity-bash
check "AC-14: a dangling symlink named detailed-off also turns texts off (fail safe)" '"<none>"' "$(last_act)"
end_case
ack3 false; mkdir -p "$DATA/live" "$SB/elsewhere"; chmod 700 "$DATA/live"; printf 'keep' >"$SB/elsewhere/target"; ln -s "$SB/elsewhere/target" "$(DOFF)"
run_fixture user-prompt-submit; wait_idle
check "AC-14: ack false over a symlinked flag: replaced by a regular 0600 file, the link target is untouched" "regular 600 keep" "$([ -f "$(DOFF)" ] && [ ! -L "$(DOFF)" ] && echo regular || echo other) $(find "$(DOFF)" -printf '%m' 2>/dev/null) $(cat "$SB/elsewhere/target")"
end_case
ack3 true; mkdir -p "$DATA/live" "$SB/elsewhere"; chmod 700 "$DATA/live"; printf 'keep' >"$SB/elsewhere/target"; ln -s "$SB/elsewhere/target" "$(DOFF)"
run_fixture user-prompt-submit; wait_idle
check "AC-14: ack true over a symlinked flag removes the link only" "no keep" "$([ -e "$(DOFF)" ] || [ -L "$(DOFF)" ] && echo yes || echo no) $(cat "$SB/elsewhere/target")"
end_case

echo "== activity: one sub_tool per subagent tool, per-agent duplicates, order and the texts-off gate (ALY-263.3 AC-05, BR-03, D-02, D-18) =="
# subact ID DESC [TOOL]: a subagent Bash PreToolUse of agent ID whose description is DESC (the phrase source until the classifier).
subact() { "$JQ_BIN" --arg id "$1" --arg d "$2" '.agent_id = $id | .tool_input.description = $d' "$FIX/activity-bash-subagent.json" >"$SB/stdin"; run_hook; }
# sub_acts ID: the activities of the sub_tool events of ID in spool order, "-" for an event without one, one line.
sub_acts() { lines_of ".type == \"sub_tool\" and .sub.id == \"$1\"" | "$JQ_BIN" -r '.activity // "-"' | tr '\n' '|'; }
new_case; mkcred
subact a1 "Run the first unit tests now"
check "AC-05: a subagent tool with a description: one sub_tool with sub.id and activity" '{"activity":"Run the first unit tests now","sub":{"id":"a1","type":"allye:bridge-pilot"},"tool":"Bash","type":"sub_tool"}' "$(lines_of '.type == "sub_tool"' | "$JQ_BIN" -cS . | tail -n 1)"
subact a1 "Run the first unit tests now"
check "AC-05: the same phrase again by the same agent: the event goes on, the phrase is skipped" "Run the first unit tests now|-|" "$(sub_acts a1)"
subact a2 "Run the first unit tests now"
check "AC-05: another agent with the same phrase still sends it" "Run the first unit tests now|" "$(sub_acts a2)"
subact a1 "Run the first unit tests now"
check "AC-05: the other agent's phrase did not reset the per-agent memory" "Run the first unit tests now|-|-|" "$(sub_acts a1)"
subact a1 "Lint the changed scripts first"; subact a1 "Run the first unit tests now"
check "AC-05: a different phrase is sent and the old one is sent again once it is no longer the previous" "Run the first unit tests now|-|-|Lint the changed scripts first|Run the first unit tests now|" "$(sub_acts a1)"
check "D-18: the per-agent memory is a private file (0600) in the live directory" "600" "$(find "$DATA/live" -maxdepth 1 -name '*.acts' -printf '%m')"
for i in $(seq 1 20); do subact "bulk$i" "Run the first unit tests now"; done
check "D-18: the per-agent memory is bounded (the newest 16 agents)" "yes" "$("$JQ_BIN" -e 'length == 16' "$DATA/live/$(test_sha "$RAWSID").acts" >/dev/null && echo yes || echo no)"
end_case

new_case; mkcred
subact b1 "Login with token=MARKER_ARGS and password: MARKER_ARGS then API_KEY=x for the user"
check "AC-05: a phrase with a secret is dropped by the cleaner: no secret leaves the cleaner, in the spool or the memory" "0" "$(cat "$(spool_of "$RAWSID")" "$DATA"/live/*.acts 2>/dev/null | grep -c 'MARKER_ARGS' || true)"
"$JQ_BIN" 'del(.agent_id, .agent_type)' "$FIX/activity-bash-subagent.json" >"$SB/stdin"; run_hook
check "AC-05: no agent_id: a tool event, never a sub_tool" "tool 1" "$(lines_of '.type == "tool" or .type == "sub_tool"' | "$JQ_BIN" -r '.type' | tail -n 1) $(lines_of '.type == "sub_tool"' | grep -c . || true)"
end_case

ack3 ""
subact c1 "Read the first spec carefully"; subact c1 "Edit the second script carefully"; subact c1 "Run the third check carefully"; subact c2 "Run the third check carefully"
wait_idle
check "AC-05: a batch of several phrases is sent whole and in order, none collapsed to the latest" "Read the first spec carefully|Edit the second script carefully|Run the third check carefully|Run the third check carefully|" "$(sent_evs | "$JQ_BIN" -r 'select(.type == "sub_tool" and .activity != null) | .activity' | tr '\n' '|')"
end_case

# texts off: no phrase is spooled or remembered on disk, whatever the flag kind
for fl in activity-off detailed-off; do
  new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
  subact d1 "Run the MARKERONE unit tests now"
  : >"$DATA/live/$fl"; chmod 600 "$DATA/live/$fl"
  subact d1 "Run the MARKERTWO unit tests now"
  check "BR-03: $fl: no phrase reaches the spool or any file after the flag appears" "0" "$(grep -rl 'MARKERTWO' "$DATA" 2>/dev/null | grep -c . || true)"
  check "BR-03: $fl: the memory of the phrases is removed" "0" "$(find "$DATA/live" -maxdepth 1 -name '*.acts' | grep -c . || true)"
  check "BR-03: $fl: the sub_tool event itself still goes on" "2" "$(lines_of '.type == "sub_tool"' | grep -c . || true)"
  end_case
done
# SHD-03: 16 phrases of 140 multibyte code points (about 9 KB of memory) are still remembered, so their repeats are skipped
new_case; mkcred
mbp() { "$JQ_BIN" -rn --arg i "$1" '"\ud83d\ude00" as $e | ($i + ($e * 44)) + " " + ($e * 46) + " " + ($e * 46)'; }
check "SHD-03: the test phrase has 140 code points and about 560 bytes" "140 yes" "$(mbp 10 | "$JQ_BIN" -R 'length' | tr -d '\n') $([ "$(mbp 10 | wc -c)" -gt 540 ] && echo yes || echo no)"
for i in $(seq 10 25); do subact "mb$i" "$(mbp $i)"; done
subact mb10 "$(mbp 10)"; subact mb25 "$(mbp 25)"
check "SHD-03: the memory holds 16 multibyte phrases above 8 KB and is still read: their repeats are skipped" "yes - -" "$([ "$(wc -c <"$DATA/live/$(test_sha "$RAWSID").acts")" -gt 8192 ] && echo yes || echo no) $(lines_of '.type == "sub_tool" and .sub.id == "mb10"' | "$JQ_BIN" -r '.activity // "-"' | tail -n 1) $(lines_of '.type == "sub_tool" and .sub.id == "mb25"' | "$JQ_BIN" -r '.activity // "-"' | tail -n 1)"
end_case
# SHD-05: the ack detailed:false removes the memory of every session
ack3 false; SHIMD="$SHIMS_STUB"; subact f1 "Run the MARKERFOUR unit tests now"
check "setup: the memory exists before the ack" "yes" "$([ -f "$DATA/live/$(test_sha "$RAWSID").acts" ] && echo yes || echo no)"
SHIMD="$SHIMS"; run_fixture user-prompt-submit; wait_idle
check "SHD-05: an ack with detailed:false removes the last-phrase memory" "no" "$([ -e "$DATA/live/$(test_sha "$RAWSID").acts" ] && echo yes || echo no)"
end_case
# a spool that already holds the phrase when the flag flips: stripped at flush, the outbox gets none
ack3 ""; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
printf '5xx' >"$SB/api/ingest-mode"; subact e1 "Run the MARKERTHREE unit tests now"; wait_idle
check "setup: the phrase is in the spool before the flag" "1" "$(grep -c MARKERTHREE "$(spool_of "$RAWSID")" || true)"
: >"$(DOFF)"; chmod 600 "$(DOFF)"; printf 'ok' >"$SB/api/ingest-mode"; : >"$SB/api/ingest-bodies.log"; run_fixture user-prompt-submit; wait_idle
check "BR-03: the flag flips with the phrase already in the spool: the request carries no phrase, the sub_tool does" "0 1" "$(grep -c MARKERTHREE "$SB/api/ingest-bodies.log" || true) $(sent_evs | "$JQ_BIN" -c 'select(.type == "sub_tool")' | grep -c . || true)"
end_case

echo "== text cleaner: shared vectors, cap 140, nested allowlist and marker scan (ALY-258.1 AC-06, AC-07, D-33, NFR-01) =="
VEC="$FIX/vectors/agent-run-text-vectors.json"
# The cleaner is replayed straight from the reporter's own jq program: the definitions up to the activity switch are cut
# out of live-report.sh (so there is no second copy) and actphrase(140) is applied to every vector input.
CLEANER_DEFS=$(sed -n "/^JQ_PROG='/,/^# BR-10 (D-24 a, b, c)/p" "$HOOK" | sed "1s/^JQ_PROG='//;\$d")
nowiso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
check "the cleaner definitions were found in the reporter" "yes" "$(case "$CLEANER_DEFS" in *"def actphrase("*) echo yes ;; *) echo no ;; esac)"
# gen_of: build the string of an input_gen / output_gen object (prefix + unit x times, sliced by code point, + suffix).
GEN='def gen: . as $g | (($g.prefix // "") + ([range($g.times // 0) | $g.unit] | join(""))) as $b | (if $g.slice then $b[$g.slice[0]:$g.slice[1]] else $b end) + ($g.suffix // "");'
vec_input() { "$JQ_BIN" -c "$GEN"' if .input != null then .input else (.input_gen | gen) end' <<<"$1"; }
vec_expect() { "$JQ_BIN" -c "$GEN"' if .output_gen != null then (.output_gen | gen) else .output end' <<<"$1"; }
clean_of() { printf '%s' "$1" | "$JQ_BIN" -c "$CLEANER_DEFS"' def actcap: 140; actphrase(actcap)'; }
NVEC=$("$JQ_BIN" '.vectors | length' "$VEC"); NSKIP=0; BADV=0; BADV_NAMES=""
BADCP='def badcp: . < 32 or (. >= 127 and . <= 159) or . == 173 or (. >= 8203 and . <= 8207) or (. >= 8234 and . <= 8238) or (. >= 8288 and . <= 8303) or (. >= 65024 and . <= 65039) or . == 65279 or (. >= 65529 and . <= 65533) or (. >= 917504 and . <= 917999);'
while IFS= read -r vj; do
  [ -n "$vj" ] || continue
  mode=$("$JQ_BIN" -r '.plugin' <<<"$vj"); name=$("$JQ_BIN" -r '.name' <<<"$vj")
  if [ "$mode" = skip ]; then NSKIP=$((NSKIP + 1)); [ -n "$("$JQ_BIN" -r '.reason // empty' <<<"$vj")" ] || { BADV=$((BADV + 1)); BADV_NAMES="$BADV_NAMES [skip without reason: $name]"; }; continue; fi
  got=$(clean_of "$(vec_input "$vj")"); want=$(vec_expect "$vj")
  if [ "$mode" = safe ]; then
    po=$("$JQ_BIN" -c 'if has("plugin_output") then .plugin_output else "__unset__" end' <<<"$vj")
    [ "$po" = '"__drop__"' ] || [ "$po" = '"__unset__"' ] || want="$po"
  fi
  bad=0
  if [ "$mode" = exact ] || { [ "$mode" = safe ] && [ "$want" != "$(vec_expect "$vj")" ]; }; then [ "$got" = "$want" ] || bad=1; fi
  # forbidden tokens never survive; the result is one line of at most 140 code points; no invisible or control code point
  "$JQ_BIN" -en --argjson g "$got" --argjson v "$vj" "$BADCP"' ($g == null) or (($g | type) == "string" and ($g | length) <= 140 and ($g | explode | any(badcp) | not) and ([$v.forbidden[] | . as $f | select($g | contains($f))] | length == 0))' >/dev/null 2>&1 || bad=1
  # idempotent: cleaning a result gives it back
  # (a cut can leave fewer than 3 words, which the cleaner then refuses: the check holds for results of 3 or more words)
  if [ "$got" != null ] && [ "$("$JQ_BIN" -r 'split(" ") | length' <<<"$got")" -ge 3 ]; then [ "$(clean_of "$got")" = "$got" ] || bad=1; fi
  if [ "$bad" = 1 ]; then BADV=$((BADV + 1)); BADV_NAMES="$BADV_NAMES [$name: got $got want $want]"; fi
done < <("$JQ_BIN" -c '.vectors[]' "$VEC")
check "AC-07/D-33: the vector table has vectors, every skip names its reason (not vacuous)" "yes" "$([ "$NVEC" -ge 80 ] && [ "$NSKIP" -ge 3 ] && echo yes || echo no)"
check "AC-07/D-33: $NVEC vectors replayed through the cleaner ($NSKIP documented skips): forbidden tokens absent, expected output, one line of at most 140, idempotent" "0" "$BADV$BADV_NAMES"
check "AC-07: the 139/140/141 boundary vectors are in the table" "3" "$("$JQ_BIN" '[.vectors[] | select(.name | test("^(139|140|141) code points"))] | length' "$VEC")"

# ALY-258 (SHD-01): the API's own vector file (ALY-257, allye-api origin/develop e8c361ee9f8970253dcd7c99c8f569f64237e7b5) is replayed too.
# The plugin may be stricter than the API scrubber, never looser: every whitespace token of an input that the API drops (it is not among the
# tokens of the expected output) must be absent from the plugin output. Vectors the API cuts (input over 140 characters) or rejects (expected
# null) have no per-token verdict and are skipped; tokens that are not plain printable ASCII are skipped (the API normalises/strips them).
APIVEC="$FIX/vectors/api-agent-run-text-vectors.json"
NAPI=$("$JQ_BIN" 'length' "$APIVEC"); APIBAD=0; APIBAD_NAMES=""; APICHK=0
while IFS= read -r vj; do
  [ -n "$vj" ] || continue
  got=$(clean_of "$("$JQ_BIN" -c '.input' <<<"$vj")")
  hit=$("$JQ_BIN" -rn --argjson g "$got" --argjson v "$vj" '
    ($v.expected | split(" ")) as $keep
    | [$v.input | split(" ")[] | select(length > 0 and test("\\A[\\x21-\\x7e]+\\z") and (. as $t | $keep | index($t) | not))] as $dropped
    | ($g // "" | split(" ")) as $out
    | [$dropped[] | select(. as $t | $out | index($t))] | join(" ")')
  APICHK=$((APICHK + 1))
  if [ -n "$hit" ]; then APIBAD=$((APIBAD + 1)); APIBAD_NAMES="$APIBAD_NAMES [$("$JQ_BIN" -r .name <<<"$vj"): survived $hit]"; fi
done < <("$JQ_BIN" -c '.[] | select(.expected != null and (.input | type) == "string" and (.input | length) <= 140)' "$APIVEC")
check "SHD-01: the API vector file is vendored with its 102 vectors and most of them carry a per-token verdict (not vacuous)" "yes" "$([ "$NAPI" -ge 100 ] && [ "$APICHK" -ge 80 ] && echo yes || echo no)"
check "SHD-01: $APICHK API vectors replayed: no token the API drops survives in the plugin output (plugin stricter, never looser)" "0" "$APIBAD$APIBAD_NAMES"
for needle in '*.internal' '10.0.0.5:' 'host=10.0.0.5' '10.0.0.1,10.0.0.2' 'db.internal:5432' 'example.com:8080' 'a.example.com|b.example.com'; do
  nv=$("$JQ_BIN" -c --arg n "$needle" '[.[] | select((.input | strings | contains($n)))] | length' "$APIVEC")
  check "SHD-01: the API vector file has a vector with the network token $needle" "yes" "$([ "$nv" -ge 1 ] && echo yes || echo no)"
done

# the hostile description through the reporter itself: only the cleaned desc leaves, in a request body
new_case; mkcred; SHIMD="$SHIMS"
HOSTILE='Review ALY-258.1 for sk-live12345abcdef at /etc/MARKER_PATH password=MARKER_ARGS done'
agent_pay Agent allye:bridge-pilot "$HOSTILE"; at6 0; run_hook
start_pay agent-v1 allye:bridge-pilot; at6 1; run_hook
for i in $(seq 1 100); do [ -s "$SB/api/ingest-bodies.log" ] && break; sleep 0.05; done; wait_idle
SENT="$SB/api/ingest-bodies.log"
check "AC-07: the sub_start left the machine with the cleaned desc and the task key only" '{"desc":"Review ALY-258.1 for at done","id":"agent-v1","task":"ALY-258.1","type":"allye:bridge-pilot"}' "$("$JQ_BIN" -cS '.events[] | select(.type == "sub_start") | .sub' "$SENT" 2>/dev/null | head -n 1)"
SCANV="$SB/scanv.txt"; { find "$DATA" -type f ! -name hook-credential.json -exec cat {} +; find "$DATA" -print; cat "$SB/log"/* "$SENT" 2>/dev/null; } >"$SCANV"
N7=0; for m in "$RAWSID" "${MARKERS[@]}" sk-live12345abcdef hunter2; do [ "$(grep -cF -- "$m" "$SCANV" || true)" = 0 ] || { N7=$((N7 + 1)); echo "    found: $m"; }; done
check "AC-07/NFR-01: the prompt, the dropped parts of the description and the secrets are in no file, name, log or request body" "0" "$N7"
check "NFR-01: every sent sub holds only permitted keys and every text is at most 140 code points" "0" "$("$JQ_BIN" -c '.events[] | select((.sub // {} | keys) - ["id","type","outcome","task","desc","summary","attempt","next","gate","checks","findings"] | length > 0 or ((.sub.desc // "") | length) > 140 or ((.activity // "") | length) > 140)' "$SENT" | wc -l | tr -d ' ')"
end_case
# the nested allowlist applies at send time: an unknown key inside sub never leaves, and the text is still capped by the cleaner
new_case; mkcred; SHIMD="$SHIMS"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$DATA/live/$(test_sha "$RAWSID").spool"
{ printf '%s\n' '{"seq":1,"at":"'"$(nowiso)"'","type":"sub_start","sub":{"id":"agent-k1","type":"allye:bridge-pilot","desc":"Review the spec for gaps","task":"ALY-258.1","evil":"MARKER_ABCDEF","prompt":"MARKER_PROMPT_xyz"}}'; } >"$SPF"; chmod 600 "$SPF"
run_fixture user-prompt-submit
for i in $(seq 1 100); do [ -s "$SB/api/ingest-bodies.log" ] && break; sleep 0.05; done; wait_idle
check "AC-11: the nested allowlist keeps id, type, desc, task and drops any other key of sub" '{"desc":"Review the spec for gaps","id":"agent-k1","task":"ALY-258.1","type":"allye:bridge-pilot"}' "$("$JQ_BIN" -cS '.events[] | select(.seq == 1) | .sub' "$SB/api/ingest-bodies.log" 2>/dev/null)"
check "AC-11: the dropped nested keys are in no request body" "0" "$(grep -cE 'MARKER_ABCDEF|MARKER_PROMPT_xyz' "$SB/api/ingest-bodies.log" || true)"
end_case

echo "== a payload that is not JSON, or a session id that fails its pattern =="
new_case; mkcred; : >"$SB/stdin"; run_hook
check "empty stdin: exits 0, silent, nothing spooled, no live dir" "0||0|no" "$RC|$OUT$ERR|$(find "$DATA" -name "*.spool" | wc -l | tr -d " ")|$([ -e "$DATA/live" ] && echo yes || echo no)"; end_case
new_case; mkcred; printf '%s' 'not json MARKER_PROMPT_xyz' >"$SB/stdin"; run_hook
check "not JSON: silent, nothing created in live" "0||0" "$RC|$OUT$ERR|$(find "$DATA" -name '*.spool' | wc -l | tr -d ' ')"
printf '%s' '{"hook_event_name":"Stop","session_id":"bad id MARKER_CMD"}' >"$SB/stdin"; run_hook
check "session id failing its pattern: nothing spooled" "0" "$(find "$DATA" -name '*.spool' | wc -l | tr -d ' ')"
printf '%s' '{"hook_event_name":"Stop"}' >"$SB/stdin"; run_hook
check "no session id: nothing spooled" "0" "$(find "$DATA" -name '*.spool' | wc -l | tr -d ' ')"
end_case

# ─── ALY-203.5: seq, lock, spool cap (BR-04, BR-05, AC-12, SHD-01..03) ──────
echo "== seq (BR-05) =="
seqs() { "$JQ_BIN" -r '.seq' "$(spool_of "${1:-$RAWSID}")" 2>/dev/null; }
increasing() { awk 'NR > 1 && $1 <= prev { bad = 1 } { prev = $1 } END { print (bad ? "no" : "yes") }'; }
new_case; mkcred
cp "$FIX/permission-request.json" "$SB/stdin"; run_hook
cp "$FIX/pre-tool-use.json" "$SB/stdin"; run_hook; cp "$FIX/post-tool-use.json" "$SB/stdin"; run_hook
check "waiting then a tool: three lines with strictly increasing seq (two events from one hook included)" "3 yes" "$(seqs | wc -l | tr -d ' ') $(seqs | increasing)"
check "seq counter file: private, holds the last seq" "600 $(seqs | tail -n 1)" "$(find "$DATA/live/$(test_sha "$RAWSID").seq" -printf '%m') $(cat "$DATA/live/$(test_sha "$RAWSID").seq")"
check "no lock directory left behind, no temp file" "0" "$(find "$DATA/live" -name '*.lock*' -o -name '.*.??????' | wc -l | tr -d ' ')"
LASTSEQ=$(seqs | tail -n 1)
rm -f "$DATA/live/$(test_sha "$RAWSID").seq"; cp "$FIX/user-prompt-submit.json" "$SB/stdin"; run_hook
check "lost counter heals: the next seq is above every earlier one" "yes" "$([ "$(seqs | tail -n 1)" -gt "$LASTSEQ" ] && echo yes || echo no)"
SF="$DATA/live/$(test_sha "$RAWSID").seq"; L2=$(seqs | tail -n 1)
printf 'garbage' >"$SF"; run_hook
check "corrupt counter heals" "yes" "$([ "$(seqs | tail -n 1)" -gt "$L2" ] && echo yes || echo no)"
L3=$(seqs | tail -n 1); printf '%s' "$((L3 + 5000))" >"$SF"; run_hook
check "counter ahead of the clock keeps counting: previous + 1" "$((L3 + 5001))" "$(seqs | tail -n 1)"
printf '%s' "9007199254740000" >"$SF"; L4=$(seqs | tail -n 1); run_hook
check "absurd counter (days ahead) heals to the clock" "yes" "$([ "$(seqs | tail -n 1)" -le "$((L4 + 100000))" ] && echo yes || echo no)"
rm -f "$SF"; ln -s "$SB/target-seq" "$SF"; : >"$SB/target-seq"; run_hook
check "symlinked counter: not written through, replaced by a private file" "0 600" "$(wc -c <"$SB/target-seq" | tr -d ' ') $(find "$SF" -printf '%m')"
for bad in 0007 00 01234567890123456; do printf '%s' "$bad" >"$SF"; L5=$(seqs | tail -n 1); run_hook
  check "counter '$bad' (not a canonical integer) heals, a seq is still allocated" "yes" "$([ "$(seqs | tail -n 1)" != "$L5" ] && [ "$(seqs | tail -n 1)" -gt 1000000000000 ] && echo yes || echo no)"; done
chmod 644 "$SF"; run_hook
check "counter with mode 0644 heals to a private file" "600 $(seqs | tail -n 1)" "$(find "$SF" -printf '%m') $(cat "$SF")"
end_case

echo "== lock primitive (BR-04, D-03) =="
# ALY-211: now_ms keeps millisecond precision when date ignores the width of %3N and prints nanoseconds (uutils).
mkdir -p "$ROOT_TMP/nsdate"; printf '#!/bin/bash\n[ "$1" = "+%%s%%3N" ] && echo 1792783222668076324 || exec "%s" "$@"\n' "$(type -P date)" >"$ROOT_TMP/nsdate/date"; chmod +x "$ROOT_TMP/nsdate/date"
check "now_ms: nanoseconds from date %3N are cut to milliseconds" "1792783222668" "$(env -i PATH="$ROOT_TMP/nsdate:$REALBIN" "$BASH_BIN" -c "$(fn_body "$HOOK" now_ms); now_ms")"
check "now_ms: a plain millisecond date result is kept" "yes" "$(env -i PATH="$REALBIN" "$BASH_BIN" -c "$(fn_body "$HOOK" now_ms); now_ms" | grep -qE '^[0-9]{13}$' && echo yes || echo no)"
prim() { env -i PATH="$REALBIN" "$BASH_BIN" -c "LC_ALL=C; $(fn_body "$HOOK" lock_is_stale); $(fn_body "$HOOK" lock_take); $(fn_body "$HOOK" lock_drop); $1"; }
tok_of() { cut -d' ' -f2 "$1/t" 2>/dev/null; }   # the owner token a lock directory holds
new_case
D="$SB/p.lock"
check "lock_take on a free lock" "0 yes" "$(prim "lock_take '$D' 0; echo \$?" | tr -d '\n') $([ -d "$D" ] && echo yes || echo no)"
check "a held fresh lock is not taken and not broken (waiting 3 tries)" "1 yes" "$(prim "lock_take '$D' 3; echo \$?" | tr -d '\n') $([ -d "$D" ] && echo yes || echo no)"
prim "lock_drop '$D' wrong-token"; check "lock_drop with another hook's token leaves the lock alone" "yes" "$([ -d "$D" ] && echo yes || echo no)"
prim "lock_drop '$D' ''"; check "lock_drop with an empty token leaves the lock alone" "yes" "$([ -d "$D" ] && echo yes || echo no)"
prim "lock_drop '$D' '$(tok_of "$D")'"; check "lock_drop with its own token releases it" "no" "$([ -d "$D" ] && echo yes || echo no)"
check "lock_take records epoch and a unique owner token" "yes" "$(prim "lock_take '$D' 0; echo \$LOCK_TOKEN" | grep -qE '^[0-9]+\.[0-9]+$' && grep -qE '^[0-9]+ [0-9]+\.[0-9]+$' "$D/t" && echo yes || echo no)"
prim "lock_drop '$D' '$(tok_of "$D")'"
mkdir "$D"; printf '%s' "$(( $(date +%s) - 25 ))" >"$D/t"
check "a lock 25 s old is not stale" "1" "$(prim "lock_take '$D' 0; echo \$?" | tr -d '\n')"
printf '%s' "$(( $(date +%s) - 31 ))" >"$D/t"
check "a lock 31 s old is broken and taken" "0 fresh" "$(prim "lock_take '$D' 0; echo \$?" | tr -d '\n') $([ "$(( $(date +%s) - $(cut -d' ' -f1 "$D/t") ))" -lt 5 ] && echo fresh || echo old)"
check "the broken lock leaves nothing behind" "0" "$(find "$SB" -name 'p.lock.old.*' | wc -l | tr -d ' ')"
rm -rf "$D"; mkdir "$D"
check "a lock without a time file is fresh (not broken)" "1" "$(prim "lock_take '$D' 0; echo \$?" | tr -d '\n')"
printf 'junk' >"$D/t"
check "a lock with a junk time file is fresh (not broken)" "1" "$(prim "lock_take '$D' 0; echo \$?" | tr -d '\n')"
# SHD-01: a lock judged stale and renamed away, but found fresh after the rename, is put back and the try fails closed.
rm -rf "$D"; mkdir "$D"; printf '%s %s' "$(date +%s)" "owner.1" >"$D/t"
mkdir "$D.brk"; check "a fresh breaker mutex keeps a stale lock from being broken by a second taker" "1" "$(printf '%s' "$(( $(date +%s) - 40 ))" >"$D/t"; prim "lock_take '$D' 0; echo \$?" | tr -d '\n')"
rm -rf "$D.brk"; printf '%s %s' "$(date +%s)" "owner.1" >"$D/t"
check "a fresh lock mis-judged stale is restored untouched and not taken" "1 owner.1 0" "$(prim "$(fn_body "$HOOK" lock_is_stale | sed 's/^lock_is_stale()/real_stale()/'); CALLS=0; lock_is_stale() { CALLS=\$((CALLS + 1)); [ \$CALLS -le 2 ] && return 0; real_stale \"\$@\"; }; lock_take '$D' 0; echo \$?" | tr -d '\n') $(cut -d' ' -f2 "$D/t" 2>/dev/null) $(find "$SB" -name 'p.lock.old.*' | wc -l | tr -d ' ')"
rm -rf "$D"
# At most one flusher at a time (AC-12): ten competing try-locks, then ten waiting ones.
FP=""; FL="$SB/fl.lock"; FLOG="$SB/fl.log"; : >"$FLOG"
for i in 1 2 3 4 5 6 7 8 9 10; do prim "lock_take '$FL' 0 && { echo in >>'$FLOG'; sleep 0.2; echo out >>'$FLOG'; lock_drop '$FL' \"\$LOCK_TOKEN\"; }" & FP="$FP $!"; done; wait $FP; FP=""
check "ten try-lock flushers: sections never overlap and at least one ran" "yes yes" "$([ -z "$(tr '\n' ' ' <"$FLOG" | sed 's/in out //g')" ] && echo yes || echo no) $([ -s "$FLOG" ] && echo yes || echo no)"
: >"$FLOG"
for i in 1 2 3 4 5 6 7 8 9 10; do prim "lock_take '$FL' 1000 && { echo in >>'$FLOG'; sleep 0.05; echo out >>'$FLOG'; lock_drop '$FL' \"\$LOCK_TOKEN\"; }" & FP="$FP $!"; done; wait $FP; FP=""
check "ten waiting flushers: all ten ran, one at a time" "10 yes no" "$(grep -c '^in' "$FLOG") $([ -z "$(tr '\n' ' ' <"$FLOG" | sed 's/in out //g')" ] && echo yes || echo no) $([ -d "$FL" ] && echo yes || echo no)"
# Medic 2: ten waiting takers over a 40 s old lock: the stale break is done once, sections never overlap.
: >"$FLOG"; mkdir "$FL"; printf '%s' "$(( $(date +%s) - 40 ))" >"$FL/t"
for i in 1 2 3 4 5 6 7 8 9 10; do prim "lock_take '$FL' 1000 && { echo in >>'$FLOG'; sleep 0.05; echo out >>'$FLOG'; lock_drop '$FL' \"\$LOCK_TOKEN\"; }" & FP="$FP $!"; done; wait $FP; FP=""
check "ten waiting takers over a 40 s old lock: all ten ran, one at a time, nothing left" "10 yes 0" "$(grep -c '^in' "$FLOG") $([ -z "$(tr '\n' ' ' <"$FLOG" | sed 's/in out //g')" ] && echo yes || echo no) $(find "$SB" -name 'fl.lock*' | wc -l | tr -d ' ')"
# ALY-211: uutils coreutils (Ubuntu 25.10+, the 26.04 runner) lets several concurrent mkdir calls on one new directory
# all succeed, so mkdir alone is no lock. The shim below is the worst case (mkdir never fails); ownership must still be
# decided by the exclusive claim of DIR/t, for the lock and for the breaker mutex.
mkdir -p "$SB/mk"; printf '#!/bin/bash\n"%s" "$@" 2>/dev/null\nexit 0\n' "$(type -P mkdir)" >"$SB/mk/mkdir"; chmod +x "$SB/mk/mkdir"
primmk() { env -i PATH="$SB/mk:$REALBIN" "$BASH_BIN" -c "LC_ALL=C; $(fn_body "$HOOK" lock_is_stale); $(fn_body "$HOOK" lock_take); $(fn_body "$HOOK" lock_drop); $1"; }
: >"$FLOG"; rm -rf "$FL"
for i in 1 2 3 4 5 6 7 8 9 10; do primmk "lock_take '$FL' 1000 && { echo in >>'$FLOG'; sleep 0.05; echo out >>'$FLOG'; lock_drop '$FL' \"\$LOCK_TOKEN\"; }" & FP="$FP $!"; done; wait $FP; FP=""
check "mkdir that always succeeds: ten waiting flushers still run one at a time, nothing left" "10 yes 0" "$(grep -c '^in' "$FLOG") $([ -z "$(tr '\n' ' ' <"$FLOG" | sed 's/in out //g')" ] && echo yes || echo no) $(find "$SB" -name 'fl.lock*' | wc -l | tr -d ' ')"
: >"$FLOG"; mkdir "$FL"; printf '%s' "$(( $(date +%s) - 40 ))" >"$FL/t"
for i in 1 2 3 4 5 6 7 8 9 10; do primmk "lock_take '$FL' 1000 && { echo in >>'$FLOG'; sleep 0.05; echo out >>'$FLOG'; lock_drop '$FL' \"\$LOCK_TOKEN\"; }" & FP="$FP $!"; done; wait $FP; FP=""
check "mkdir that always succeeds: ten takers over a 40 s old lock run one at a time, nothing left" "10 yes 0" "$(grep -c '^in' "$FLOG") $([ -z "$(tr '\n' ' ' <"$FLOG" | sed 's/in out //g')" ] && echo yes || echo no) $(find "$SB" -name 'fl.lock*' | wc -l | tr -d ' ')"
rm -rf "$FL"; mkdir "$FL"; printf '%s %s' "$(date +%s)" "owner.1" >"$FL/t"
check "mkdir that always succeeds: a held fresh lock is not taken" "1" "$(primmk "lock_take '$FL' 0; echo \$?" | tr -d '\n')"
end_case

echo "== lock in the hook (SHD-02) =="
new_case; mkcred; H=$(test_sha "$RAWSID"); mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
mkdir "$DATA/live/$H.lock"; printf '%s' "$(( $(date +%s) - 40 ))" >"$DATA/live/$H.lock/t"; run_fixture user-prompt-submit
check "a stale session lock (40 s) is broken: the event is spooled, lock released" '{"state":"working","type":"state"}|no' "$(spooled)|$([ -d "$DATA/live/$H.lock" ] && echo yes || echo no)"; end_case
new_case; mkcred; H=$(test_sha "$RAWSID"); mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
mkdir "$DATA/live/$H.lock"; printf '%s' "$(date +%s)" >"$DATA/live/$H.lock/t"
( sleep 1; rm -rf "$DATA/live/$H.lock" ) & RP=$!; run_fixture user-prompt-submit; wait $RP
check "a fresh session lock is waited for, not stolen: spooled after the release" '{"state":"working","type":"state"}|no' "$(spooled)|$([ -d "$DATA/live/$H.lock" ] && echo yes || echo no)"; end_case
new_case; mkcred; run_fixture post-tool-use
check "a hook that maps to nothing releases the lock too" "no" "$([ -n "$(find "$DATA/live" -name '*.lock' 2>/dev/null)" ] && echo yes || echo no)"; end_case

# bg_hook IN OUT: the hook in the background with its own stdin and capture files (parallel-safe run_script).
bg_hook() {
  env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" \
    PATH="$SHIMD:$REALBIN" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REALBIN" ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
    "$BASH_BIN" "$HOOK" <"$1" >"$2" 2>&1 &
  BGPIDS="$BGPIDS $!"
}
BGPIDS=""
wait_bg() { wait $BGPIDS; BGPIDS=""; wait_idle; }   # never a bare `wait`: it would also wait for the fake API server
echo "== skill vs mcp binding race (SHD-02) =="
for round in 1 2 3 4 5 6; do
  new_case; mkcred; RUN_ENV=()
  bg_hook "$FIX/skill-bridge-spec.json" "$SB/o1"; bg_hook "$FIX/mcp-allye-task-start-half-bad-key.json" "$SB/o2"; bg_hook "$FIX/mcp-allye-task-start.json" "$SB/o3"; wait_bg
  BF="$DATA/live/$(test_sha "$RAWSID").bind"
  ORDER=$("$JQ_BIN" -r 'select(.type=="bind") | {skill:4,mcp:3,env:2,branch:1}[.bind.source]' "$(spool_of "$RAWSID")" | tr -d '\n')
  check "race $round: a skill bind is sent, no weaker bind after it, and the file holds the strongest" "yes 4 4" "$(case "$ORDER" in *4) echo yes ;; *) echo "no($ORDER)" ;; esac) $(echo "$ORDER" | grep -o 4 | head -n 1) $(cut -d'|' -f1 "$BF")"
  check "race $round: no output, no lock left" "|no" "$(cat "$SB/o1" "$SB/o2" "$SB/o3")|$([ -n "$(find "$DATA/live" -name '*.lock' 2>/dev/null)" ] && echo yes || echo no)"
  end_case
done

echo "== ten parallel hooks of one session (AC-12) =="
new_case; mkcred; RUN_ENV=()
n=0; for f in user-prompt-submit pre-tool-use stop user-prompt-submit pre-tool-use notification-idle-prompt user-prompt-submit pre-tool-use stop user-prompt-submit; do n=$((n + 1)); bg_hook "$FIX/$f.json" "$SB/par.$n"; done; wait_bg
SP=$(spool_of "$RAWSID")
check "ten hooks: ten lines, none lost" "10" "$(wc -l <"$SP" | tr -d ' ')"
check "ten hooks: every line is a whole JSON object (none torn)" "10" "$("$JQ_BIN" -c 'select(type == "object")' "$SP" | wc -l | tr -d ' ')"
check "ten hooks: seq unique" "10" "$(seqs | sort -u | wc -l | tr -d ' ')"
check "ten hooks: seq strictly increasing in file order" "yes" "$(seqs | increasing)"
check "ten hooks: the expected multiset of events (fixture expectations summed)" "$(for f in user-prompt-submit pre-tool-use stop user-prompt-submit pre-tool-use notification-idle-prompt user-prompt-submit pre-tool-use stop user-prompt-submit; do "$JQ_BIN" -cS . "$FIX/$f.expect"; done | sort | tr '\n' ' ')" "$("$JQ_BIN" -cS 'del(.at, .seq)' "$SP" | sort | tr '\n' ' ')"
check "ten hooks: counter equals the largest seq, outputs empty, no lock left" "$(seqs | tail -n 1)||no" "$(cat "$DATA/live/$(test_sha "$RAWSID").seq")|$(cat "$SB"/par.*)|$([ -n "$(find "$DATA/live" -name '*.lock' 2>/dev/null)" ] && echo yes || echo no)"
end_case

echo "== spool cap (SHD-03) =="
fill() {  # LINES PADBYTES: a private spool of valid contract lines (marked by index), padded by a long tool-free code field
  local pad; pad=$(head -c "$2" /dev/zero | tr '\0' 'a')
  mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
  SPF="$DATA/live/$(test_sha "$RAWSID").spool"; : >"$SPF"; chmod 600 "$SPF"
  "$JQ_BIN" -nc --argjson n "$1" --arg pad "$pad" 'range(1; $n + 1) | {seq: ., type: "state", state: "working", at: "2026-01-01T00:00:00Z", idx: ., pad: $pad}' >"$SPF"
}
new_case; mkcred; fill 600 0; run_fixture user-prompt-submit
check "600 lines + 1: 500 kept, the oldest dropped, the new line is last" "500 102 working" "$(wc -l <"$SPF" | tr -d ' ') $("$JQ_BIN" -r '.idx' "$SPF" | head -n 1) $("$JQ_BIN" -r '.state' "$SPF" | tail -n 1)"
check "after the trim the spool is still 0600 and a regular file" "600" "$(find "$SPF" -printf '%m')"
end_case
new_case; mkcred; fill 499 0; run_fixture user-prompt-submit
check "499 lines + 1 = 500: nothing dropped" "500 1" "$(wc -l <"$SPF" | tr -d ' ') $("$JQ_BIN" -r '.idx' "$SPF" | head -n 1)"; end_case
new_case; mkcred; fill 400 1000; cp "$SPF" "$SB/before"; run_fixture user-prompt-submit
check "byte trim is exact: the result is the last 262144 bytes of (old spool + new line) minus the cut first line" "yes" "$({ cat "$SB/before"; tail -n 1 "$SPF"; } | tail -c 262144 | sed 1d | cmp -s - "$SPF" && echo yes || echo no)"
check "byte trim: at most 262144 bytes, first kept idx > 1, indexes contiguous up to 400, the new line last, every line whole" "yes yes yes yes" "$([ "$(wc -c <"$SPF" | tr -d ' ')" -le 262144 ] && echo yes || echo no) $([ "$("$JQ_BIN" -r '.idx // empty' "$SPF" | head -n 1)" -gt 1 ] && echo yes || echo no) $("$JQ_BIN" -s 'map(select(.idx != null) | .idx) as $i | ($i == [range($i[0]; 401)])' "$SPF" | sed 's/true/yes/;s/false/no/') $([ "$("$JQ_BIN" -r '.state' "$SPF" | tail -n 1)" = working ] && [ "$("$JQ_BIN" -c 'select(type=="object")' "$SPF" | wc -l | tr -d ' ')" = "$(wc -l <"$SPF" | tr -d ' ')" ] && echo yes || echo no)"
check "byte trim: dropped more than 100 and fewer than 300 lines (about a quarter of the 400 KB fits)" "yes" "$(n=$(wc -l <"$SPF" | tr -d ' '); [ "$n" -gt 100 ] && [ "$n" -lt 300 ] && echo yes || echo no)"
end_case
new_case; mkcred; fill 5 0; run_fixture user-prompt-submit
check "a small spool is left alone" "6 1" "$(wc -l <"$SPF" | tr -d ' ') $("$JQ_BIN" -r '.idx' "$SPF" | head -n 1)"; end_case

echo "== torn spool tail (SHD-03) =="
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$DATA/live/$(test_sha "$RAWSID").spool"
printf '{"seq":1,"type":"sta' >"$SPF"; chmod 600 "$SPF"; run_fixture user-prompt-submit
check "torn tail without newline: the torn fragment stays on its own line, the new line is whole" "2 {\"seq\":1,\"type\":\"sta working" "$(wc -l <"$SPF" | tr -d ' ') $(head -n 1 "$SPF") $(tail -n 1 "$SPF" | "$JQ_BIN" -r '.state')"
run_fixture user-prompt-submit
check "a spool ending in a newline gets no blank line" "0" "$(grep -c '^$' "$SPF" || true)"
end_case

echo "== state is claimed only when the line is spooled (consistency) =="
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; H=$(test_sha "$RAWSID"); : >"$DATA/live/$H.spool"; chmod 644 "$DATA/live/$H.spool"
run_fixture skill-bridge-spec
check "unusable spool: no seq, state or bind recorded as sent" "" "$(cd "$DATA/live" && ls | grep -v '\.spool$' | tr '\n' ' ')"; end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; H=$(test_sha "$RAWSID"); : >"$DATA/live/$H.state"; chmod 644 "$DATA/live/$H.state"
run_fixture skill-bridge-spec
check "unusable state file: nothing spooled, no seq or bind recorded" "" "$(cd "$DATA/live" && ls | grep -v '\.state$' | tr '\n' ' ')"; end_case
new_case; mkcred; mkdir -p "$SB/elsewhere"; chmod 700 "$SB/elsewhere"; ln -s "$SB/elsewhere" "$DATA/live"; run_fixture user-prompt-submit
check "symlinked live dir: no lock, seq or any entry created through it" "0" "$(find "$SB/elsewhere" -mindepth 1 | wc -l | tr -d ' ')"; end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 755 "$DATA/live"; run_fixture user-prompt-submit
check "live dir mode 0755: no lock, seq or any entry created in it" "0" "$(find "$DATA/live" -mindepth 1 | wc -l | tr -d ' ')"; end_case

nowiso() { date -u +%Y-%m-%dT%H:%M:%SZ; }   # lines that must pass the 23 h freshness rule carry the real time
# ─── ALY-203.6: batching, flush lock and sending (BR-04, BR-06, AC-03, AC-04, AC-12) ──────
echo "== sending: contract body, token only on curl's stdin (AC-03) =="
nbodies() { if [ -f "$SB/api/ingest-bodies.log" ]; then wc -l <"$SB/api/ingest-bodies.log" | tr -d ' '; else echo 0; fi; }
sent_seqs() { [ -f "$SB/api/ingest-bodies.log" ] && "$JQ_BIN" -r '.events[].seq' "$SB/api/ingest-bodies.log" || true; }
spool_seqs() { "$JQ_BIN" -r '.seq' "$(spool_of "${1:-$RAWSID}")" 2>/dev/null || true; }
new_case; mkcred; SHIMD="$SHIMS"; SH=$(test_sha "$RAWSID")
run_fixture user-prompt-submit
check "first state change is sent at once: exit 0, silent" "0||" "$RC|$OUT|$ERR"
check "one request, to the ingest route only, with the credential's host" "1 /api/agent-runs/events" "$(reqs) $("$JQ_BIN" -r '.path' "$SB/api/requests.log")"
check "body: client kind, session hash = sha256 of the id, one event with seq/at/type/state" "claude-code $SH 1 working yes" \
  "$("$JQ_BIN" -r '"\(.client.kind) \(.session.hash) \(.events | length) \(.events[0].state) \(.events[0] | (.seq >= 1000000000000 and (.at | test("Z$")) and .type == "state") | if . then "yes" else "no" end)"' "$SB/api/ingest-bodies.log")"
check "body: only the contract keys at the top and in events" "client,session,events|at,seq,state,type" \
  "$("$JQ_BIN" -r 'keys_unsorted | join(",")' "$SB/api/ingest-bodies.log")|$("$JQ_BIN" -r '.events[0] | keys | join(",")' "$SB/api/ingest-bodies.log")"
check "positive control: the token reached the API in the Authorization header" "Bearer $TOKEN" "$("$JQ_BIN" -r '.authorization' "$SB/api/requests.log")"
check "the shim saw curl run with the config on stdin: url/limits logged, argv is only flags" "yes yes" \
  "$(grep -q "^url = \"$API/api/agent-runs/events\"" "$SB/log/curl-config.log" && grep -q '^max-time ' "$SB/log/curl-config.log" && echo yes || echo no) $(CL=$(grep '^curl' "$SB/log/calls.log" | head -n 1); [[ "$CL" == 'curl [-q] [--silent] [-K] [-] [-D] ['*'.hdr] [-o] ['*'.resp] [-w] [%{http_code}]' ]] && echo yes || echo "no: $CL")"
ALLTXT="$SB/all.txt"; { find "$DATA" -type f ! -name hook-credential.json -exec cat {} +; find "$DATA" -print; cat "$SB/log"/* "$SB/out" "$SB/err" "$SB/api/ingest-bodies.log" 2>/dev/null; } >"$ALLTXT"
check "the token is in no argv, environment, spool, state file, batch, body, shim log, stdout or stderr" "0" "$(grep -cF -- "$TOKEN" "$ALLTXT" || true)"
check "the raw token is not even in a piece (prefix alyh_ + 8) outside the credential file" "0" "$(grep -cF -- "${TOKEN:0:13}" "$ALLTXT" || true)"
check "sent lines are removed from the spool; counter, flushed stamp stay; no batch file, no lock" "0 yes yes no no" \
  "$(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ') $([ -s "$DATA/live/$SH.seq" ] && echo yes || echo no) $([ -s "$DATA/live/$SH.flushed" ] && echo yes || echo no) $([ -e "$DATA/live/$SH.batch" ] && echo yes || echo no) $([ -n "$(find "$DATA/live" -name '*.lock' -o -name '.*.??????')" ] && echo yes || echo no)"
SENT1=$(sent_seqs | tail -n 1); run_fixture pre-tool-use
check "seq counter survives the emptied spool: the next seq is higher (sent by the delayed flush or still spooled)" "yes" "$([ "$( { sent_seqs; spool_seqs; } | sort -n | tail -n 1)" -gt "$SENT1" ] && echo yes || echo no)"
end_case

echo "== flush policy: 2 seconds or an important event (AC-04; 2 s and ms stamps since ALY-217) =="
T0=1800000000
at() { RUN_ENV=("SHIM_DATE_NOW=$((T0 + $1))"); }
new_case; mkcred; SHIMD="$SHIMS"
at 0; run_fixture user-prompt-submit
check "t+0: the first state change is sent; the flush start is stamped in ms" "1 ${T0}000" "$(nbodies) $(cat "$DATA/live/$(test_sha "$RAWSID").flushed")"
fake_wait_on   # a pending sleeper of the harness: these hooks may not arm one, so only the hooks' own policy is seen
at 1; run_fixture pre-tool-use; at 1; run_fixture pre-tool-use; at 1; run_fixture pre-tool-use
check "three non-important events within 2 s: nothing sent, all three spooled" "1 3" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 1; run_fixture post-tool-use
check "still nothing at 1 s (a PostToolUse adds no line)" "1 3" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 2; run_fixture pre-tool-use
check "at 2 s since the last flush: one request carrying the 4 spooled events" "2 4 0" "$(nbodies) $("$JQ_BIN" -r '.events | length' "$SB/api/ingest-bodies.log" | tail -n 1) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 3; run_fixture pre-tool-use
check "1 s after that flush a plain event waits" "2 1" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 3; run_fixture subagent-start
check "a subagent start is important: sent at once with the waiting event" "3 tool,sub_start" "$(nbodies) $("$JQ_BIN" -r '[.events[].type] | join(",")' "$SB/api/ingest-bodies.log" | tail -n 1)"
at 3; run_fixture subagent-stop
check "a subagent stop is important" "4" "$(nbodies)"
at 3; run_fixture skill-bridge-spec
check "a binding is important (tool + bind in one request)" "5" "$(nbodies)"
at 3; run_fixture notification-idle-prompt
check "a state change (working -> idle) is important" "6" "$(nbodies)"
at 3; run_fixture notification-idle-prompt
check "idle -> idle is not a change: nothing sent within the interval" "6" "$(nbodies)"
end_case
new_case; mkcred; SHIMD="$SHIMS"; mkdir -p "$SB/proj/.allye/missions/m-1"
SHA1=$(printf 'a%.0s' $(seq 1 40)); printf -- '- Gates: SHIELD_CLEAR %s · WATCHER_APPROVED — · MISSION_COMPLETE — · CI_PENDING —\n' "$SHA1" >"$SB/proj/.allye/missions/m-1/log.md"
at 0; run_fixture user-prompt-submit; at 1; GCWDV="$SB/proj"; FPV="$SB/proj/.allye/missions/m-1/log.md"
"$JQ_BIN" -c --arg c "$SB/proj" --arg f "$FPV" '. + {hook_event_name:"PostToolUse", tool_name:"Write", tool_input:{file_path:$f}, cwd:$c}' "$FIX/post-tool-use.json" >"$SB/stdin"; run_hook
check "gates are important: sent at once" "2 gates" "$(nbodies) $("$JQ_BIN" -r '.events[-1].type' "$SB/api/ingest-bodies.log" | tail -n 1)"
end_case
# ALY-217.7 AC-35: the synthetic sub_start makes the first sub_tool of an unseen id important; the next one of that id waits
new_case; mkcred; SHIMD="$SHIMS"
at 0; run_fixture user-prompt-submit; fake_wait_on
at 1; run_fixture sub-tool-unseen
check "AC-35: an unseen sub id 1 s after a flush: sub_start and sub_tool sent at once" "2 sub_start,sub_tool" "$(nbodies) $("$JQ_BIN" -r '[.events[].type] | join(",")' "$SB/api/ingest-bodies.log" | tail -n 1)"
at 1; run_fixture sub-tool-unseen
check "AC-35: the next sub_tool of that id is not important (waits for the 2 s interval)" "2 1" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
end_case

echo "== batches of at most 50 events and 16384 bytes =="
fill6() {  # LINES PADBYTES: contract-shaped lines with seq 1..N; PAD makes the code field long
  local pad; pad=$(head -c "$2" /dev/zero | tr '\0' 'a')
  mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$DATA/live/$(test_sha "$RAWSID").spool"; : >"$SPF"; chmod 600 "$SPF"
  "$JQ_BIN" -nc --argjson n "$1" --arg pad "$pad" --arg at "$(nowiso)" 'range(1; $n + 1) | {seq: ., at: $at, type: "state", state: "working"} + (if $pad == "" then {} else {code: $pad} end)' >"$SPF"
}
new_case; mkcred; SHIMD="$SHIMS"; fill6 120 0; run_fixture user-prompt-submit
check "121 lines: three requests of 50, 50 and 21 events" "3 50,50,21" "$(nbodies) $("$JQ_BIN" -r '.events | length' "$SB/api/ingest-bodies.log" | tr '\n' ',' | sed 's/,$//')"
check "every event sent once, in order, none left" "121 121 0" "$(sent_seqs | wc -l | tr -d ' ') $(sent_seqs | sort -n | uniq | wc -l | tr -d ' ') $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
check "events arrive in increasing seq order" "yes" "$(sent_seqs | awk 'NR > 1 && $1 <= p { b = 1 } { p = $1 } END { print (b ? "no" : "yes") }')"
end_case
new_case; mkcred; SHIMD="$SHIMS"; fill6 100 400; run_fixture user-prompt-submit
check "400-byte events: more than three requests, each body at most 16384 bytes and under 50 events (bytes bind first)" "yes yes yes" \
  "$([ "$(nbodies)" -ge 3 ] && echo yes || echo no) $([ "$(awk '{ if (length($0) > m) m = length($0) } END { print m }' "$SB/api/ingest-bodies.log")" -le 16384 ] && echo yes || echo no) $([ "$("$JQ_BIN" -r '.events | length' "$SB/api/ingest-bodies.log" | sort -n | tail -n 1)" -lt 50 ] && echo yes || echo no)"
check "byte-limited batches still deliver all 101 events once" "101 101 0" "$(sent_seqs | wc -l | tr -d ' ') $(sent_seqs | sort -n | uniq | wc -l | tr -d ' ') $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
end_case
new_case; mkcred; SHIMD="$SHIMS"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$DATA/live/$(test_sha "$RAWSID").spool"
{ printf '%s\n' '{"seq":1,"at":"'"$(nowiso)"'","type":"state","state":"working"}' 'not json at all' '{"seq":"x","type":"state"}' '{"seq":2,"at":"'"$(nowiso)"'","type":"nope"}' '{"seq":3,"at":"'"$(nowiso)"'","type":"tool","tool":"Bash","extra":"MARKER_PATH"}'; printf '{"seq":4,"at":"20'; } >"$SPF"; chmod 600 "$SPF"
run_fixture user-prompt-submit
check "torn and invalid lines are skipped and dropped, unknown keys are not forwarded" "1,3,$(sent_seqs | tail -n 1) 0 0" "$(sent_seqs | head -n 2 | tr '\n' ',')$(sent_seqs | tail -n 1) $(wc -l <"$SPF" | tr -d ' ') $(grep -c MARKER_PATH "$SB/api/ingest-bodies.log" || true)"
end_case

echo "== failure handling (BR-07, AC-05) =="
new7() { new_case; mkcred; SHIMD="$SHIMS"; }
CREDFP() { test_sha "$TOKEN"; }
sweep() {  # LABEL: the token is in the Authorization header (positive control) and nowhere else
  { find "$DATA" -type f ! -name hook-credential.json -exec cat {} +; find "$DATA" -print; cat "$SB/log"/* "$SB/out" "$SB/err" "$SB/api/ingest-bodies.log" 2>/dev/null; } >"$SB/all.txt"
  check "$1: token only in the Authorization header, nowhere else" "Bearer $TOKEN 0" "$("$JQ_BIN" -r '.authorization' "$SB/api/requests.log" | tail -n 1) $(grep -cF -- "$TOKEN" "$SB/all.txt" || true)"
}
spn() { if [ -f "$(spool_of "$RAWSID")" ]; then wc -l <"$(spool_of "$RAWSID")" | tr -d ' '; else echo 0; fi; }
LV() { echo "$DATA/live/$1"; }
TOKEN2="alyh_$(printf 'Zz9_-%.0s' $(seq 1 8))xyz"

# 5xx and a dropped connection: the spool stays, no marker, no back-off, the next hook after 2 s retries
for m in 5xx drop; do
  new7; printf '%s' "$m" >"$SB/api/ingest-mode"; at 0; run_fixture user-prompt-submit
  check "answer '$m': one request, line kept, no marker, no back-off, exit 0 silent" "1 1 no no 0|" "$(nbodies) $(spn) $([ -e "$(LV disabled)" ] && echo yes || echo no) $([ -e "$(LV backoff)" ] && echo yes || echo no) $RC|$OUT$ERR"
  sweep "answer '$m'"
  fake_wait_on; printf 'ok' >"$SB/api/ingest-mode"; at 1; run_fixture pre-tool-use; check "'$m': 1 s later nothing is sent" "1" "$(nbodies)"
  at 2; run_fixture pre-tool-use
  check "after '$m' and 2 s with an OK API: the kept line goes out with the new ones" "2 0" "$(nbodies) $(spn)"
  end_case
done
# 400 and 413: that batch is discarded, no back-off, the next important event is sent at once
for m in 400 413; do
  new7; printf '%s' "$m" >"$SB/api/ingest-mode"; at 0; run_fixture user-prompt-submit
  check "answer '$m': the batch is discarded from the spool, no marker, no back-off" "1 0 no no" "$(nbodies) $(spn) $([ -e "$(LV disabled)" ] && echo yes || echo no) $([ -e "$(LV backoff)" ] && echo yes || echo no)"
  sweep "answer '$m'"
  printf 'ok' >"$SB/api/ingest-mode"; at 0; run_fixture subagent-start
  check "after '$m' the next important event is sent at once and alone" "2 1" "$(nbodies) $("$JQ_BIN" -r '.events | length' "$SB/api/ingest-bodies.log" | tail -n 1)"
  end_case
done
# 202 with a null shortId (a brand-new run): tolerated
new7; printf 'ok-null' >"$SB/api/ingest-mode"; at 0; run_fixture user-prompt-submit
check "202 with shortId null: spool emptied, no marker, no back-off" "1 0 no no" "$(nbodies) $(spn) $([ -e "$(LV disabled)" ] && echo yes || echo no) $([ -e "$(LV backoff)" ] && echo yes || echo no)"; end_case
# 403, 422 and 429: back-off until a timestamp, boundaries on the fake clock
backoff_case() {  # LABEL MODE SECONDS [retry-after]
  new7; printf '%s' "$2" >"$SB/api/ingest-mode"; [ -z "${4:-}" ] || printf '%s' "$4" >"$SB/api/ingest-retry-after"
  at 0; run_fixture user-prompt-submit
  check "$1: one request, line kept, back-off until t+$3 for this credential, no disabled marker" "1 1 $((T0 + $3)) $(CREDFP) no" "$(nbodies) $(spn) $(cut -d' ' -f1 "$(LV backoff)") $(cut -d' ' -f2 "$(LV backoff)") $([ -e "$(LV disabled)" ] && echo yes || echo no)"
  check "$1: backoff file is private" "600" "$(find "$(LV backoff)" -printf '%m')"
  sweep "$1"
  printf 'ok' >"$SB/api/ingest-mode"
  at $(($3 - 1)); run_fixture subagent-start; check "$1: an important event 1 s before the end is only spooled" "1 2" "$(nbodies) $(spn)"
  at "$3"; run_fixture subagent-stop; check "$1: at the end of the back-off everything goes out" "2 0" "$(nbodies) $(spn)"
  end_case
}
backoff_case "403" 403 3600
backoff_case "422" 422 600
backoff_case "429 Retry-After 7" 429 7 7
backoff_case "429 Retry-After above the clamp (999999)" 429 3600 999999
backoff_case "429 Retry-After not a number" 429 60 abc
backoff_case "429 Retry-After 0 (clamped up to 1)" 429 1 0
# 401: marker with the credential fingerprint; a re-pair clears it and a new run starts with `state started`
for m in 401 401-inactive; do
  new7; printf '%s' "$m" >"$SB/api/ingest-mode"; at 0; run_fixture user-prompt-submit
  check "answer '$m': disabled marker (0600) holds the credential fingerprint, the spool is discarded, exit 0 silent" "600 cred:$(CREDFP) 0 0|" "$(find "$(LV disabled)" -printf '%m') $(cat "$(LV disabled)") $(spn) $RC|$OUT$ERR"
  sweep "answer '$m'"
  printf 'ok' >"$SB/api/ingest-mode"; at 20; run_fixture subagent-start
  check "'$m': while marked disabled nothing is sent or spooled" "1 0" "$(nbodies) $(spn)"
  TOKEN="$TOKEN2" mkcred; at 30; run_fixture subagent-start
  check "'$m': after a re-pair the marker is gone and the first event sent is state started" "2 no state:started,sub_start" "$(nbodies) $([ -e "$(LV disabled)" ] && echo yes || echo no) $("$JQ_BIN" -r '[.events[] | "\(.type):\(.state // "")" | sub(":$"; "")] | join(",")' "$SB/api/ingest-bodies.log" | tail -n 1)"
  check "'$m': the re-paired request carries the new credential" "Bearer $TOKEN2" "$("$JQ_BIN" -r '.authorization' "$SB/api/requests.log" | tail -n 1)"
  at 31; run_fixture subagent-stop; check "'$m': started is sent once, not again" "3 sub_stop" "$(nbodies) $("$JQ_BIN" -r '[.events[].type] | join(",")' "$SB/api/ingest-bodies.log" | tail -n 1)"
  end_case
done
new7; at 0; run_fixture user-prompt-submit; TOKEN="$TOKEN2" mkcred; at 1; run_fixture subagent-start
check "a re-pair without any failure also opens with state started" "state:started,sub_start" "$("$JQ_BIN" -r '[.events[] | "\(.type):\(.state // "")" | sub(":$"; "")] | join(",")' "$SB/api/ingest-bodies.log" | tail -n 1)"; end_case
new7; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; printf 'cred:%s' "$(test_sha "$TOKEN2")" >"$(LV disabled)"; chmod 600 "$(LV disabled)"; run_fixture user-prompt-submit
check "a marker of ANOTHER credential is cleared: the current credential works" "no 1" "$([ -e "$(LV disabled)" ] && echo yes || echo no) $(nbodies)"; end_case
new7; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; printf 'cred:%s' "$(CREDFP)" >"$(LV disabled)"; chmod 600 "$(LV disabled)"; run_fixture user-prompt-submit
check "a marker of THIS credential keeps the reporter inert" "yes 0" "$([ -e "$(LV disabled)" ] && echo yes || echo no) $(nbodies)"; end_case

echo "== spool bounds under permanent failure (AC-05) =="
new7; printf '5xx' >"$SB/api/ingest-mode"; fill6 600 0; at 0; run_fixture user-prompt-submit
check "600 lines + a failing send: at most 500 lines kept" "1 500" "$(nbodies) $(spn)"; end_case
new7; printf '5xx' >"$SB/api/ingest-mode"; fill6 400 1000; at 0; run_fixture user-prompt-submit
check "400 KB of lines + a failing send: at most 262144 bytes kept" "yes" "$([ "$(wc -c <"$(spool_of "$RAWSID")" | tr -d ' ')" -le 262144 ] && echo yes || echo no)"; end_case

echo "== lines older than 23 hours are dropped at flush (BR-07) =="
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
new7; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$(spool_of "$RAWSID")"
{ for a in 1:82801 2:82800 3:100 4:0; do s=${a%%:*}; age=${a##*:}; "$JQ_BIN" -nc --argjson s "$s" --arg at "$(iso $((T0 - age)))" '{seq:$s, at:$at, type:"state", state:"working"}'; done
  "$JQ_BIN" -nc '{seq:5, at:"garbage", type:"state", state:"working"}'; } >"$SPF"; chmod 600 "$SPF"
at 0; run_fixture user-prompt-submit
check "older than 23 h (82801 s) dropped, exactly 23 h (82800 s) and newer kept, unparsable time dropped; spool emptied" "2,3,4, 0" "$(sent_seqs | head -n 3 | tr '\n' ',') $(spn)"
check "the new event follows in the same batch" "4" "$(sent_seqs | wc -l | tr -d ' ')"; end_case
new7; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$(spool_of "$RAWSID")"
"$JQ_BIN" -nc --arg at "$(iso $((T0 - 90000)))" '{seq:1, at:$at, type:"state", state:"working"}' >"$SPF"; chmod 600 "$SPF"
at 0; run_fixture pre-tool-use
check "a stale line in the spool is never sent: the request holds only the new event, the spool is empty" "1 1 0" "$(nbodies) $(sent_seqs | wc -l | tr -d ' ') $(spn)"; end_case

echo "== correction round: flusher rechecks, bounded body, late 401, advisories =="
hook_once() {  # FILE: the hook once, without waiting for its detached flusher
  cp "$1" "$SB/stdin"
  env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REAL" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"
}
wait_for() {  # CONDITION-COMMAND: poll up to 10 s
  local i; for i in $(seq 1 200); do eval "$1" && return 0; sleep 0.05; done; return 1
}
# SHD-01: the first session's flusher is in flight; another session gets 429 / 401; the first stops before its next batch
for m in 429 401; do
  new7; "$JQ_BIN" -c '.session_id = "SESS-A-0002"' "$FIX/user-prompt-submit.json" >"$SB/a.json"
  printf 'ok:1500\n%s:0\n' "$m" >"$SB/api/ingest-script"; fill6 120 0
  hook_once "$FIX/user-prompt-submit.json"; wait_for '[ "$(nbodies)" -ge 1 ]'
  hook_once "$SB/a.json"; wait_for '[ -e "$(LV backoff)" ] || [ -e "$(LV disabled)" ]'; wait_idle
  check "session B's flusher stops between batches after session A got $m: 2 requests only" "2" "$(nbodies)"
  check "session B keeps its remaining 71 lines (121 - the first batch of 50)" "71" "$(spn)"
  check "$m: the marker/back-off written by session A is in place" "$([ "$m" = 401 ] && echo "no yes" || echo "yes no")" "$([ -e "$(LV backoff)" ] && echo yes || echo no) $([ -e "$(LV disabled)" ] && echo yes || echo no)"
  end_case
done
# SHD-03: a late 401 for the OLD credential, after a re-pair, must not disable or drop the NEW credential's lines
new7; printf '401:1500\n' >"$SB/api/ingest-script"
hook_once "$FIX/user-prompt-submit.json"; wait_for '[ "$(nbodies)" -ge 1 ]'
TOKEN="$TOKEN2" mkcred; hook_once "$FIX/subagent-start.json"; wait_idle
check "late 401 for the old token after a re-pair: no marker, nothing dropped (old line + started + sub_start kept)" "no 3" "$([ -e "$(LV disabled)" ] && echo yes || echo no) $(spn)"
check "the new credential's lines include the started event" "yes" "$(grep -c '"state":"started"' "$(spool_of "$RAWSID")" | sed 's/^1$/yes/')"
printf 'ok' >"$SB/api/ingest-mode"; run_fixture subagent-stop
check "the next flush sends all four lines with the NEW credential" "2 4 Bearer $TOKEN2" "$(nbodies) $(sent_seqs | wc -l | tr -d ' ' | awk '{print $1 - 1}') $("$JQ_BIN" -r '.authorization' "$SB/api/requests.log" | tail -n 1)"
end_case
# SHD-02: an oversized response is a failure (the transfer is cut), no file is left, the spool is kept
new7; printf 'huge' >"$SB/api/ingest-mode"; at 0; run_fixture user-prompt-submit
check "a 200 KB response body: failure, line kept, no marker or back-off, no response/header/batch file left" "1 no no 0" "$(nbodies) $([ -e "$(LV disabled)" ] && echo yes || echo no) $([ -e "$(LV backoff)" ] && echo yes || echo no) $(find "$DATA/live" \( -name '*.resp' -o -name '*.hdr' -o -name '*.batch' \) | wc -l | tr -d ' ')"; end_case
# Medic: a 401 with a code that is not listed backs off 10 minutes; 202 with ignored/dropped consumes the batch
backoff_case "401 with an unlisted code" 401-other 600
new7; printf '0,2,1' >"$SB/api/ingest-counts"; at 0; run_fixture user-prompt-submit
check "202 with accepted 0, ignored 2, dropped 1: the batch is consumed, no marker, no back-off" "1 0 no no" "$(nbodies) $(spn) $([ -e "$(LV disabled)" ] && echo yes || echo no) $([ -e "$(LV backoff)" ] && echo yes || echo no)"; end_case
new7; at 0; run_fixture user-prompt-submit; TOKEN="$TOKEN2" mkcred; at 1; run_fixture session-start-startup
check "re-pair then a SessionStart: exactly one started in that request (no duplicate prepend)" "1" "$("$JQ_BIN" -r '[.events[] | select(.state == "started")] | length' "$SB/api/ingest-bodies.log" | tail -n 1)"; end_case

echo "== SessionEnd: bounded send and the final flusher (AC-10, BR-12, ALY-217.7 AC-37..AC-39, NFR-06) =="
FL7() { echo "$DATA/live/$(test_sha "$RAWSID").final.lock"; }
fpid() { local p=""; { read -r p _ <"$(FL7)/p"; } 2>/dev/null; [[ "$p" =~ ^[0-9]+$ ]] && printf '%s' "$p"; }
# finals_under PREFIX: running final flushers (cmdline `<bash> <live-report.sh> final`) whose CLAUDE_PLUGIN_DATA starts with
# PREFIX (read-only scan of /proc; the environment is read only for processes with that exact cmdline).
finals_under() {
  local f c n=0
  [ -d /proc/self ] || { echo 0; return; }
  for f in /proc/[0-9]*; do
    c=$({ tr '\0' ' ' <"$f/cmdline"; } 2>/dev/null) || continue
    [ "$c" = "$BASH_BIN $HOOK final " ] || continue
    { tr '\0' '\n' <"$f/environ"; } 2>/dev/null | grep -q "^CLAUDE_PLUGIN_DATA=$1" && n=$((n + 1))
  done
  echo "$n"
}
# end_timed [NAME=VALUE...]: SessionEnd (session-end-clear) run directly, without waiting for anything it detached.
# EMS = its wall time in ms; FP / FPS = the final flusher recorded in final.lock right after it returned ("" when none).
end_timed() {
  local m0 m1
  cp "$FIX/session-end-clear.json" "$SB/stdin"; m0=$(date +%s%N)
  env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" \
    SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REAL" "$@" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"
  RC=$?; m1=$(date +%s%N); EMS=$(( (m1 - m0) / 1000000 ))
  FP=$(fpid); FPS=""; [ -z "$FP" ] || FPS=$(pstart "$FP")
}
nended() { grep -c '"state":"ended"' "$SB/api/ingest-bodies.log" 2>/dev/null || true; }
spool_end() { if grep -q '"state":"ended"' "$(spool_of "$RAWSID")" 2>/dev/null; then echo yes; else echo no; fi; }
f_alive() { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ -n "${2:-}" ] && [ "$(pstart "$1")" = "$2" ]; }
# final_done SECONDS: polls until final.lock is gone and the recorded final flusher no longer runs.
final_done() { local i; for i in $(seq 1 $(($1 * 20))); do [ ! -e "$(FL7)" ] && ! f_alive "$FP" "$FPS" && return 0; sleep 0.05; done; return 1; }
endmt() { grep '^max-time' "$SB/log/curl-config.log" | sed 's/^max-time = //' | tr '\n' ' ' | sed 's/ $//'; }

# AC-10/NFR-06 (updated by ALY-217.7): a 3 s API. The hook sends in the foreground with 1 s limits and returns within
# 1.5 s; its request times out, so the final flusher sends again with the normal limits and exits once it is delivered.
new7; printf '3000' >"$SB/api/ingest-delay"; at 0; run_fixture user-prompt-submit; wait_idle
end_timed
check "SessionEnd with a 3 s API returns within 1.5 s (observed $EMS ms), exit 0, silent" "yes 0|" "$([ "$EMS" -le 1500 ] && echo yes || echo no) $RC|$(cat "$SB/out" "$SB/err")"
check "the timed-out final send handed off to a final flusher (final.lock names a live process)" "yes" "$(f_alive "$FP" "$FPS" && echo yes || echo no)"
final_done 15
check "the final flusher delivered the ended event and exited, removing final.lock; nothing left in the spool" "yes no no 0" \
  "$([ "$(nended)" -ge 2 ] && echo yes || echo no) $(spool_end) $([ -e "$(FL7)" ] && echo yes || echo no) $(finals_under "$DATA")"
check "limits: the earlier request 8 s, the hook's final request at most 1 s, the final flusher's request 8 s again" "yes" \
  "$(endmt | grep -qE '^8 (1|0\.[0-9]{3}) 8$' && echo yes || echo no)"
check "the final event is state ended with its end code" "ended end_clear" "$("$JQ_BIN" -r '.events[-1] | "\(.state) \(.code)"' "$SB/api/ingest-bodies.log" | tail -n 1)"
end_case

# AC-38: a send that succeeds starts no final flusher
new7; at 0; run_fixture user-prompt-submit; wait_idle
end_timed
check "AC-38: SessionEnd with an OK API: delivered by the hook itself, no final flusher, empty spool (observed $EMS ms)" "1 no 0 0 yes" \
  "$(nended) $([ -e "$(FL7)" ] && echo yes || echo no) $(finals_under "$DATA") $(spn) $([ "$EMS" -le 1500 ] && echo yes || echo no)"
end_case

# AC-38: the hook's send gets a 503, the final flusher's later attempt a 202: delivered exactly once, spool empty
new7; printf 'ok\n5xx\nok\n' >"$SB/api/ingest-script"; at 0; run_fixture user-prompt-submit; wait_idle
end_timed
check "AC-38: a 503 on the hook's send: the hook returns within 1.5 s and a final flusher takes over" "yes yes" "$([ "$EMS" -le 1500 ] && echo yes || echo no) $(f_alive "$FP" "$FPS" && echo yes || echo no)"
final_done 15
sleep 2.5
check "AC-38: two ended requests in all (the 503 and one 202), nothing left in the spool, final flusher gone" "2 3 0 no 0" \
  "$(nended) $(nbodies) $(spn) $([ -e "$(FL7)" ] && echo yes || echo no) $(finals_under "$DATA")"
end_case

# AC-37: a slow flusher (3 s answer) holds flush.lock when SessionEnd runs: the hook waits at most its bound, hands off,
# and the ended event is delivered, polled up to 15 s. The request after the slow one gets a 503 (whoever sends it: the slow
# flusher's next round or the final flusher), so only a later attempt of the final flusher can deliver it.
new7; printf 'ok:3000\n5xx\nok\n' >"$SB/api/ingest-script"; at 0; hook_once "$FIX/user-prompt-submit.json"
check "AC-37: the first flusher holds flush.lock (not vacuous)" "yes" "$([ -d "$DATA/live/$(test_sha "$RAWSID").flush.lock" ] && echo yes || echo no)"
end_timed
check "AC-37: SessionEnd with flush.lock busy returns within 1.5 s (observed $EMS ms), exit 0, silent" "yes 0|" "$([ "$EMS" -le 1500 ] && echo yes || echo no) $RC|$(cat "$SB/out" "$SB/err")"
for i in $(seq 1 300); do [ "$(nended)" -ge 1 ] && [ "$(spool_end)" = no ] && break; sleep 0.05; done
final_done 15
check "AC-37: the ended event reached the API and left the spool; no final flusher left" "yes no no 0" \
  "$([ "$(nended)" -ge 1 ] && echo yes || echo no) $(spool_end) $([ -e "$(FL7)" ] && echo yes || echo no) $(finals_under "$DATA")"
end_case

# AC-39: one final flusher per session, stdio on /dev/null, SIGHUP survived, exit after its last attempt
new7; printf '5xx' >"$SB/api/ingest-mode"
end_timed ALLYE_LIVE_FINAL_DELAYS="2 2 2"
check "AC-39: a failing API: the hook returns within 1.5 s, a final flusher runs, recorded '<pid> <start>' in final.lock" "yes yes" \
  "$([ "$EMS" -le 1500 ] && echo yes || echo no) $(f_alive "$FP" "$FPS" && echo yes || echo no)"
if [ -n "$FP" ] && [ -d /proc/self ]; then
  check "AC-39: stdin, stdout and stderr of the final flusher are /dev/null" "/dev/null /dev/null /dev/null" "$(readlink "/proc/$FP/fd/0") $(readlink "/proc/$FP/fd/1") $(readlink "/proc/$FP/fd/2")"
  check "AC-39: without setsid on the PATH the final flusher ignores SIGHUP" "1" "$(m=$(sed -n 's/^SigIgn:[[:space:]]*//p' "/proc/$FP/status"); echo $(( 0x$m & 1 )))"
  f_alive "$FP" "$FPS" && kill -HUP "$FP" 2>/dev/null; sleep 0.5
  check "AC-39: a SIGHUP to the recorded pid leaves it running" "yes" "$(f_alive "$FP" "$FPS" && echo yes || echo no)"
fi
FP1="$FP"; FPS1="$FPS"; end_timed ALLYE_LIVE_FINAL_DELAYS="2 2 2"
check "AC-39: a second SessionEnd while it runs starts no second final flusher" "1 $FP1" "$(finals_under "$DATA") $(fpid)"
FP="$FP1"; FPS="$FPS1"; final_done 20
check "AC-39: after its last attempt it exits and removes final.lock; the ended line stays for the API expiry" "no no 0 yes" \
  "$(f_alive "$FP" "$FPS" && echo yes || echo no) $([ -e "$(FL7)" ] && echo yes || echo no) $(finals_under "$DATA") $(spool_end)"
check "AC-39: attempts: two hook sends and four from the final flusher (0, 2, 4, 6 s)" "6" "$(nbodies)"
end_case

echo "== a late line while the flusher finishes (SHD-02) =="
new_case; D="$SB/lt"; mkdir -p "$D"; : >"$D/calls"
out=$(env -i PATH="$REALBIN" "$BASH_BIN" -c "
  LC_ALL=C; SPOOL='$D/spool'; FLOCK='$D/f.lock'; FTOK=''; : >\"\$SPOOL\"
  $(fn_body "$HOOK" lock_is_stale); $(fn_body "$HOOK" lock_take); $(fn_body "$HOOK" lock_drop); $(fn_body "$HOOK" flush_loop)
  flush_run() { echo run >>'$D/calls'; if [ \"\$(wc -l <'$D/calls' | tr -d ' ')\" = 1 ]; then echo late >>\"\$SPOOL\"; : >\"\$SPOOL.sent\"; else : >\"\$SPOOL\"; fi; [ -d \"\$FLOCK\" ] && echo held >>'$D/calls'; return 0; }
  lock_take \"\$FLOCK\" 0 && { FTOK=\$LOCK_TOKEN; flush_loop; }
  echo done")
check "a line appended after the last read is picked up by a second pass; the lock is released between passes and at the end" "run held run held done no" "$(tr '\n' ' ' <"$D/calls" | sed 's/ $//') ${out##*$'\n'} $([ -d "$D/f.lock" ] && echo yes || echo no)"
end_case

echo "== orphans of a killed flusher =="
new7; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; H=$(test_sha "$RAWSID")
mkdir "$DATA/live/$H.flush.lock"; printf '%s %s' "$(( $(date +%s) - 40 ))" "dead.1" >"$DATA/live/$H.flush.lock/t"
printf '%s' '{"client":{"kind":"claude-code"},"session":{"hash":"x"},"events":[{"seq":99,"at":"2026-01-01T00:00:00Z","type":"tool","tool":"ORPHAN_MARKER"}]}' >"$DATA/live/$H.batch"; chmod 600 "$DATA/live/$H.batch"
run_fixture user-prompt-submit
check "orphan flush lock broken, orphan batch overwritten and never sent; the real event goes out once" "1 0 no no" "$(nbodies) $(grep -c ORPHAN_MARKER "$SB/api/ingest-bodies.log" || true) $([ -e "$DATA/live/$H.batch" ] && echo yes || echo no) $([ -e "$DATA/live/$H.flush.lock" ] && echo yes || echo no)"; end_case

echo "== one flusher at a time (AC-12) =="
new_case; mkcred; SHIMD="$SHIMS"; printf '400' >"$SB/api/ingest-delay"
mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; H=$(test_sha "$RAWSID"); mkdir "$DATA/live/$H.flush.lock"; printf '%s %s' "$(date +%s)" "other.1" >"$DATA/live/$H.flush.lock/t"
run_fixture user-prompt-submit
check "a fresh flush lock held by another flusher: no request, the line stays, the lock is untouched" "0 1 other.1" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ') $(cut -d' ' -f2 "$DATA/live/$H.flush.lock/t")"
printf '%s %s' "$(( $(date +%s) - 40 ))" "dead.1" >"$DATA/live/$H.flush.lock/t"; run_fixture subagent-start
check "a flush lock older than 30 s is broken: the spool goes out" "1 0" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
end_case
new_case; mkcred; SHIMD="$SHIMS"; printf '400' >"$SB/api/ingest-delay"; RUN_ENV=()
# ten distinct sub ids (ALY-217.7: a second SubagentStart of one id spools nothing)
n=0; for i in 1 2 3 4 5 6 7 8 9 10; do n=$((n + 1)); "$JQ_BIN" --arg id "agent-par$n" '.agent_id = $id' "$FIX/subagent-start.json" >"$SB/pin.$n"; done
n=0; for i in 1 2 3 4 5 6 7 8 9 10; do n=$((n + 1)); bg_hook "$SB/pin.$n" "$SB/par.$n"; done; wait_bg
SP=$(spool_of "$RAWSID")
check "ten hooks, each an important event, a slow API: never more than one request in flight" "1" "$(cat "$SB/api/ingest-maxinflight" 2>/dev/null)"
check "at least one request was made" "yes" "$([ "$(nbodies)" -ge 1 ] && echo yes || echo no)"
SENTN=$(sent_seqs | wc -l | tr -d ' '); LEFT=$( [ -f "$SP" ] && wc -l <"$SP" | tr -d ' ' || echo 0)
check "sent plus left in the spool is exactly the ten events" "10" "$((SENTN + LEFT))"
check "no event was sent twice, none is both sent and left" "0 0" "$( { sent_seqs; spool_seqs; } | sort -n | uniq -d | wc -l | tr -d ' ') $(sent_seqs | sort -n | uniq -d | wc -l | tr -d ' ')"
check "outputs empty, no flush lock, no state lock, no batch file left" "|no" "$(cat "$SB"/par.*)|$([ -n "$(find "$DATA/live" -name '*.lock' -o -name '*.batch')" ] && echo yes || echo no)"
end_case
echo "== flush_run directly: boundaries, progress, lock_touch (ALY-203.6 correction) =="
# flush_direct: runs flush_run (and the functions it needs, extracted from the hook) against $SB's spool, fake API and
# the real logging curl shim, as the detached flusher would, holding the flush lock like the hook does.
flush_direct() {
  local H; H=$(test_sha "$RAWSID")
  env -i HOME="$SB/home" PATH="$SHIMS:$REALBIN" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REALBIN" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" -c "
    LC_ALL=C; umask 077; UID_NOW=\$(id -u); . '$LIB'; CFP=''; SEND_MAXTIME=8; SEND_CONNECT=3
    $(for f in lock_is_stale lock_take lock_drop lock_touch private_file_ok jq_valid_def credfp backoff_active backoff_set mark_disabled batch_build spool_drop_sent detailed_cache flush_run; do fn_body "$HOOK" "$f"; done)
    HASH='$H'; LIVE_DIR='$DATA/live'; SPOOL=\"\$LIVE_DIR/\$HASH.spool\"; LOCKD=\"\$LIVE_DIR/\$HASH.lock\"; FLOCK=\"\$LIVE_DIR/\$HASH.flush.lock\"
    BATCHF=\"\$LIVE_DIR/\$HASH.batch\"; HDRF=\"\$LIVE_DIR/\$HASH.hdr\"; RESPF=\"\$LIVE_DIR/\$HASH.resp\"; DIR='$DATA'; BACKOFFF=\"\$LIVE_DIR/backoff\"; LIVE_API='$API'; LIVE_TOKEN='$TOKEN'; TMPF=''
    lock_take \"\$FLOCK\" 0 && { FTOK=\$LOCK_TOKEN; flush_run; lock_drop \"\$FLOCK\" \"\$FTOK\"; }"
}
BASE_LEN() { printf '{"client":{"kind":"claude-code"},"session":{"hash":"%s"},"events":[]}' "$(test_sha "$RAWSID")" | wc -c | tr -d ' '; }
line6() {  # SEQ PADBYTES: a valid spool line; the code field pads it
  local pad=""; [ "$2" -gt 0 ] && pad=$(head -c "$2" /dev/zero | tr '\0' 'a')
  "$JQ_BIN" -nc --argjson s "$1" --arg p "$pad" --arg at "$(nowiso)" '{seq: $s, at: $at, type: "state", state: "working"} + (if $p == "" then {} else {code: $p} end)'
}
len6() { line6 "$1" "$2" | wc -c | tr -d ' '; }   # includes the newline
direct_case() { new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; SPF="$DATA/live/$(test_sha "$RAWSID").spool"; : >"$SPF"; chmod 600 "$SPF"; }
body_sizes() { awk '{ print length($0) }' "$SB/api/ingest-bodies.log" | tr '\n' ' ' | sed 's/ $//'; }
ev_counts() { "$JQ_BIN" -r '.events | length' "$SB/api/ingest-bodies.log" | tr '\n' ' ' | sed 's/ $//'; }

# 50 events: the boundary
direct_case; for i in $(seq 1 50); do line6 "$((1000 + i))" 0; done >"$SPF"; flush_direct
check "exactly 50 events: one request of 50, spool empty" "1 50 0" "$(nbodies) $(ev_counts) $(wc -l <"$SPF" | tr -d ' ')"; end_case
direct_case; for i in $(seq 1 51); do line6 "$((1000 + i))" 0; done >"$SPF"; flush_direct
check "51 events: two requests, 50 then 1" "2 50 1" "$(nbodies) $(ev_counts | cut -d' ' -f1) $(ev_counts | cut -d' ' -f2)"; end_case
# 16384 bytes: the body of two events is exactly 16384 / 16385 bytes
BL=$(BASE_LEN); L1=$(len6 1001 100)
direct_case; PADB=$((16384 - BL - (L1 - 1) - 1 - ($(len6 1002 1) - 1) + 1)); { line6 1001 100; line6 1002 "$PADB"; } >"$SPF"; flush_direct
check "two events making a body of exactly 16384 bytes: one request, 16384 bytes" "1 16384 2" "$(nbodies) $(body_sizes) $(ev_counts)"; end_case
direct_case; { line6 1001 100; line6 1002 "$((PADB + 1))"; } >"$SPF"; flush_direct
check "the same with 16385 bytes: split in two requests, both events delivered, spool empty" "2 1 1 0" "$(nbodies) $(ev_counts | cut -d' ' -f1) $(ev_counts | cut -d' ' -f2) $(wc -l <"$SPF" | tr -d ' ')"; end_case
# a single event: exactly at the limit is sent, one byte more is dropped
ONE=$((16384 - BL - ($(len6 1001 1) - 1) + 1)); direct_case; line6 1001 "$ONE" >"$SPF"; flush_direct
check "a single event making a body of exactly 16384 bytes is sent" "1 16384 0" "$(nbodies) $(body_sizes) $(wc -l <"$SPF" | tr -d ' ')"; end_case
direct_case; line6 1001 "$((ONE + 1))" >"$SPF"; flush_direct
check "a single oversize event (16385 bytes) is dropped, nothing sent, spool empty, flusher stops (SHD-03 no-progress)" "0 0" "$(nbodies) $(wc -l <"$SPF" | tr -d ' ')"
check "the flusher left no lock and no batch file" "no" "$([ -n "$(find "$DATA/live" -name '*.lock' -o -name '*.batch')" ] && echo yes || echo no)"; end_case
direct_case; { line6 1001 0; line6 1002 20000; } >"$SPF"; flush_direct
check "valid line then an oversize valid line as the LAST line: first sent, oversize dropped, spool empty" "1 1 0" "$(nbodies) $(ev_counts) $(wc -l <"$SPF" | tr -d ' ')"; end_case
direct_case; { line6 1001 0; printf '%s\n' '{"seq":1002,"at":"2026-01-01T00:00:00Z","type":"nope"}'; } >"$SPF"; flush_direct
check "an object with an unknown type as the last line is dropped too (no endless rounds)" "1 0" "$(nbodies) $(wc -l <"$SPF" | tr -d ' ')"; end_case
direct_case; printf '%s\n' '{"seq":1002,"at":"2026-01-01T00:00:00Z","type":"nope"}' 'junk' >"$SPF"; flush_direct
check "a spool of only invalid lines is emptied without a request" "0 0" "$(nbodies) $(wc -l <"$SPF" | tr -d ' ')"; end_case
# 2xx that removes nothing: the spool is replaced by a read-only directory trick is not needed; a line of an equal size is covered above.

# lock_touch (SHD-01)
touchp() { env -i PATH="$REALBIN" "$BASH_BIN" -c "LC_ALL=C; $(fn_body "$HOOK" lock_touch); $1"; }
new_case; D="$SB/tt.lock"; mkdir "$D"; printf '%s %s' "$(( $(date +%s) - 20 ))" "mine.1" >"$D/t"
check "lock_touch with the stored token refreshes the time and keeps the token" "0 mine.1 fresh" "$(touchp "lock_touch '$D' mine.1; echo \$?" | tr -d '\n') $(cut -d' ' -f2 "$D/t") $([ "$(( $(date +%s) - $(cut -d' ' -f1 "$D/t") ))" -lt 5 ] && echo fresh || echo old)"
printf '%s %s' "$(( $(date +%s) - 20 ))" "theirs.2" >"$D/t"; B=$(cat "$D/t")
check "lock_touch with another token fails and changes nothing" "1 yes" "$(touchp "lock_touch '$D' mine.1; echo \$?" | tr -d '\n') $([ "$(cat "$D/t")" = "$B" ] && echo yes || echo no)"
check "lock_touch with an empty token fails" "1" "$(touchp "lock_touch '$D' ''; echo \$?" | tr -d '\n')"
check "lock_touch leaves no temp file" "t" "$(ls "$D" | tr '\n' ' ' | sed 's/ $//')"
rm -rf "$D"; check "lock_touch on a missing lock fails and creates nothing" "1 no" "$(touchp "lock_touch '$D' mine.1; echo \$?" | tr -d '\n') $([ -e "$D" ] && echo yes || echo no)"
end_case
# a flusher whose lock was taken over stops before sending
direct_case; line6 1001 0 >"$SPF"
env -i HOME="$SB/home" PATH="$SHIMS:$REALBIN" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REALBIN" "$BASH_BIN" -c "
  LC_ALL=C; umask 077; UID_NOW=\$(id -u); . '$LIB'; CFP=''; SEND_MAXTIME=8; SEND_CONNECT=3
  $(for f in lock_is_stale lock_take lock_drop lock_touch private_file_ok jq_valid_def credfp backoff_active backoff_set mark_disabled batch_build spool_drop_sent detailed_cache flush_run; do fn_body "$HOOK" "$f"; done)
  HASH='$(test_sha "$RAWSID")'; LIVE_DIR='$DATA/live'; SPOOL='$SPF'; LOCKD=\"\$LIVE_DIR/x.lock\"; FLOCK=\"\$LIVE_DIR/x.flush.lock\"; BATCHF=\"\$LIVE_DIR/x.batch\"; HDRF=\"\$LIVE_DIR/x.hdr\"; RESPF=\"\$LIVE_DIR/x.resp\"; DIR='$DATA'; BACKOFFF=\"\$LIVE_DIR/backoff\"
  LIVE_API='$API'; LIVE_TOKEN='$TOKEN'; TMPF=''
  mkdir \"\$FLOCK\"; printf '%s %s' \"\$(date +%s)\" 'someone-else' >\"\$FLOCK/t\"; FTOK=not-mine; flush_run"
check "flusher that no longer owns its lock sends nothing and keeps the spool" "0 1" "$(nbodies) $(wc -l <"$SPF" | tr -d ' ')"; end_case

echo "== append while a request is in flight =="
new_case; mkcred; SHIMD="$SHIMS"; printf '1500' >"$SB/api/ingest-delay"; at 0
run_fixture_bg() { cp "$FIX/$1.json" "$SB/stdin"; env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REAL" SHIM_DATE_NOW="$((T0 + 0))" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"; }
run_fixture_bg user-prompt-submit
for i in $(seq 1 100); do [ "$(nbodies)" -ge 1 ] && break; sleep 0.05; done
check "the first request is in flight (received, answer delayed)" "1" "$(nbodies)"
run_fixture_bg pre-tool-use
check "a line appended during the request is in the spool (the in-flight line still is too)" "2" "$(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
wait_idle
check "the flusher picked the appended line up in a second request: both delivered once, spool empty" "2 1 1 0" "$(nbodies) $(ev_counts | cut -d' ' -f1) $(ev_counts | cut -d' ' -f2) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
check "seqs delivered are distinct and increasing" "2 yes" "$(sent_seqs | sort -n | uniq | wc -l | tr -d ' ') $(sent_seqs | awk 'NR > 1 && $1 <= p { b = 1 } { p = $1 } END { print (b ? "no" : "yes") }')"
end_case

echo "== the hook does not wait for curl =="
new_case; mkcred; SHIMD="$SHIMS"; printf '3000' >"$SB/api/ingest-delay"
S0=$(date +%s); cp "$FIX/user-prompt-submit.json" "$SB/stdin"
env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REAL" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"; S1=$(date +%s)
check "a hook whose flush meets a 3 s API returns in under 2 s, silent" "yes|" "$([ $((S1 - S0)) -lt 2 ] && echo yes || echo no)|$(cat "$SB/out" "$SB/err")"
wait_idle; check "and the detached flush still delivers" "1" "$(nbodies)"
end_case

# ─── ALY-217.1: tool lines within 2 s through one delayed flush per session (BR-01, BR-02, D-20, NFR-01) ──────
echo "== delayed tool flush (ALY-217 AC-01..AC-08) =="
# hook_at OFFSET FIXTURE: the hook once at T0+OFFSET ("" = the real clock), without waiting for its flusher or sleeper.
hook_at() {
  cp "$FIX/$2.json" "$SB/stdin"
  env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REAL" \
    ${1:+SHIM_DATE_NOW="$((T0 + $1))"} "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"
}
# sleeps: the sleeper's own waits (S.mmm; lock retries are 0.02 / 0.1), comma-separated.
sleeps() { { grep -E '^sleep [0-9]+\.[0-9]{3}$' "$SB/log/sleep.log" 2>/dev/null || true; } | tr '\n' ',' | sed 's/,$//'; }
types_of() { "$JQ_BIN" -r '[.events[].type] | join(",")' "$SB/api/ingest-bodies.log" | sed -n "${1}p"; }
H7=$(test_sha "$RAWSID"); W7() { echo "$DATA/live/$H7.flush.wait"; }; FL7() { echo "$DATA/live/$H7.flushed"; }
yn() { if eval "$1"; then echo yes; else echo no; fi; }

# AC-01 / NFR-01: the only wall-clock case. The real clock; the tool line comes right after the first flush started.
new_case; mkcred; SHIMD="$SHIMS"
hook_at "" user-prompt-submit; wait_for '[ "$(nbodies)" -ge 1 ]'; wait_idle
M0=$(date +%s%N); hook_at "" pre-tool-use
for i in $(seq 1 200); do [ "$(nbodies)" -ge 2 ] && break; sleep 0.05; done; M1=$(date +%s%N); DMS=$(( (M1 - M0) / 1000000 ))
check "AC-01: a tool line spooled under 2 s after the last flush start reaches the API with no further hook" "2 tool" "$(nbodies) $(types_of 2)"
check "AC-01: the delay is non-zero and under 4 s (observed ${DMS} ms)" "yes" "$(yn '[ "$DMS" -gt 0 ] && [ "$DMS" -lt 4000 ]')"
wait_idle; check "AC-01: afterwards no sleeper, no lock, an empty spool" "no no 0" "$(yn '[ -e "$(W7)" ]') $(yn '[ -n "$(find "$DATA/live" -name "*.lock")" ]') $(spn)"
end_case

# AC-02: 2 s or more since the last flush start: the hook starts the flusher itself, no sleeper
new_case; mkcred; SHIMD="$SHIMS"; REAL="$REALBIN_SL"
at 0; run_fixture user-prompt-submit
printf '1000' >"$SB/api/ingest-delay"; hook_at 2 pre-tool-use
check "AC-02: at t+2 s the flusher is started before the hook exits (flush lock held at return), no sleeper armed, flushed = t+2 s in ms" \
  "yes no $(( (T0 + 2) * 1000 ))" "$(yn '[ -d "$DATA/live/$H7.flush.lock" ]') $(yn '[ -e "$(W7)" ]') $(cat "$(FL7)")"
wait_idle
check "AC-02: request order state then tool, no sleeper wait logged" "2 state tool " "$(nbodies) $(types_of 1) $(types_of 2) $(sleeps)"
end_case

# AC-07: a 10-digit seconds stamp (older version) is read as seconds
for age in 1 3; do
  new_case; mkcred; SHIMD="$SHIMS"; REAL="$REALBIN_SL"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"
  printf 'working' >"$DATA/live/$H7.state"; printf '%s\n' "$((T0 - age))" >"$(FL7)"; chmod 600 "$DATA/live/$H7.state" "$(FL7)"
  at 0; run_fixture pre-tool-use
  if [ "$age" = 1 ]; then
    check "AC-07: a seconds stamp 1 s old: the line waits for one sleeper of the remaining 1.000 s, then is sent; the stamp is now ms" "sleep 1.000 1 tool 13" "$(sleeps) $(nbodies) $(types_of 1) $(tr -d '\n' <"$(FL7)" | wc -c | tr -d ' ')"
  else
    check "AC-07: a seconds stamp 3 s old: sent at once by the hook, no sleeper, the stamp becomes t+0 in ms" " 1 ${T0}000" "$(sleeps) $(nbodies) $(cat "$(FL7)")"
  fi
  end_case
done

# AC-03: one sleeper, one sending flusher, 2 s between non-important flush starts, important events at once
new_case; mkcred; SHIMD="$SHIMS"; REAL="$REALBIN_SL"
at 0; run_fixture user-prompt-submit
hook_at 0 pre-tool-use; WP1=$(cut -d' ' -f1 "$(W7)/p" 2>/dev/null); hook_at 0 pre-tool-use; hook_at 0 pre-tool-use
check "AC-03: three tool lines under 2 s: one flush.wait, still naming the first sleeper (a live process with that start)" "yes yes" \
  "$(yn '[ -n "$WP1" ] && [ "$(cut -d" " -f1 "$(W7)/p")" = "$WP1" ]') $(yn '[ "$(pstart "$WP1")" = "$(cut -d" " -f2 "$(W7)/p")" ]')"
printf '500' >"$SB/api/ingest-delay"; hook_at 0 subagent-start
check "AC-03: an important event starts its flush at once while the sleeper is pending" "yes yes" "$(yn '[ -d "$DATA/live/$H7.flush.lock" ]') $(yn '[ -e "$(W7)" ]')"
wait_idle
check "AC-03: one sleeper (one 2.000 s wait); the important request carried the three tool lines; the woken sleeper found nothing to send" \
  "sleep 2.000 2 tool,tool,tool,sub_start 0" "$(sleeps) $(nbodies) $(types_of 2) $(spn)"
printf '1500' >"$SB/api/ingest-delay"; hook_at 10 pre-tool-use
check "AC-03: 10 s later a tool line is sent at once (flush start stamped t+10 s)" "$(( (T0 + 10) * 1000 ))" "$(cat "$(FL7)")"
hook_at 11 pre-tool-use; hook_at 11 pre-tool-use
wait_idle
check "AC-03: 1 s after that start: one more sleeper waiting the remaining 1.000 s (2 s between the two starts), its flush stamped t+11 s" \
  "sleep 2.000,sleep 1.000 $(( (T0 + 11) * 1000 ))" "$(sleeps) $(cat "$(FL7)")"
check "AC-03: the sleeper waited for the sending flusher: never two requests in flight, both tool lines in the 4th request, spool empty" \
  "1 4 tool,tool 0" "$(cat "$SB/api/ingest-maxinflight") $(nbodies) $(types_of 4) $(spn)"
end_case

# AC-04: a line spooled while a send is in flight (that send fails after 3 s) is still delivered with no further hook
new_case; mkcred; SHIMD="$SHIMS"; printf '5xx:3000\n' >"$SB/api/ingest-script"
hook_at 0 user-prompt-submit; wait_for '[ "$(nbodies)" -ge 1 ]'
hook_at 0 pre-tool-use; wait_idle
check "AC-04: the sleeper retried the flush lock until the failed send ended, then delivered both lines" "2 state,tool 0" "$(nbodies) $(types_of 2) $(spn)"
end_case

# AC-05: no sleeper during a back-off; a woken sleeper sends nothing when sending is not allowed or not useful
new_case; mkcred; SHIMD="$SHIMS"; REAL="$REALBIN_SL"
at 0; run_fixture user-prompt-submit
printf '%s %s' "$((T0 + 600))" "$(test_sha "$TOKEN")" >"$DATA/live/backoff"; chmod 600 "$DATA/live/backoff"
hook_at 0 pre-tool-use
check "AC-05 back-off: no sleeper is armed (no flush.wait at return)" "no" "$(yn '[ -e "$(W7)" ]')"
wait_idle; check "AC-05 back-off: no sleeper wait, nothing sent, the line kept" " 1 1" "$(sleeps) $(nbodies) $(spn)"
end_case
for cond in none ended off disabled backoff nocred empty; do
  new_case; mkcred; SHIMD="$SHIMS"; REAL="$REALBIN_SL"
  at 0; run_fixture user-prompt-submit
  hook_at 0 pre-tool-use
  armed=$(yn '[ -e "$(W7)" ]')
  case "$cond" in
    ended) printf 'ended' >"$DATA/live/$H7.state" ;;
    off) : >"$DATA/live/off" ;;
    disabled) printf 'cred:%s' "$(test_sha "$TOKEN")" >"$DATA/live/disabled"; chmod 600 "$DATA/live/disabled" ;;
    backoff) printf '%s %s' "$((T0 + 600))" "$(test_sha "$TOKEN")" >"$DATA/live/backoff"; chmod 600 "$DATA/live/backoff" ;;
    nocred) rm -f "$CRED" ;;
    empty) : >"$(spool_of "$RAWSID")" ;;
  esac
  wait_idle
  if [ "$cond" = none ]; then
    check "AC-05 control (nothing changed while it slept): the sleeper sends the line" "yes sleep 2.000 2 0" "$armed $(sleeps) $(nbodies) $(spn)"
  else
    check "AC-05 '$cond' while the sleeper slept: it woke and sent nothing" "yes sleep 2.000 1 $([ "$cond" = empty ] && echo 0 || echo 1)" "$armed $(sleeps) $(nbodies) $(spn)"
  fi
  end_case
done

# AC-06: a killed sleeper never blocks the next one (its flush.wait is stale at once)
new_case; mkcred; SHIMD="$SHIMS"
at 0; run_fixture user-prompt-submit
hook_at 0 pre-tool-use; KP=""; KS=""; { read -r KP KS <"$(W7)/p"; } 2>/dev/null
check "AC-06: flush.wait records <pid> <start> of the live sleeper" "yes" "$(yn '[ -n "$KP" ] && [ "$(pstart "$KP")" = "$KS" ]')"
if [ -n "$KP" ] && [ "$(pstart "$KP")" = "$KS" ]; then kill -9 "$KP" 2>/dev/null; for i in $(seq 1 100); do [ "$(pstart "$KP")" = "$KS" ] || break; sleep 0.02; done; fi
check "AC-06: the killed sleeper left flush.wait behind and sent nothing" "yes 1" "$(yn '[ -e "$(W7)" ]') $(nbodies)"
hook_at 0 pre-tool-use; wait_idle
check "AC-06: the next tool line arms a new sleeper, which delivers both lines with no further hook; flush.wait gone" "2 tool,tool 0 no" "$(nbodies) $(types_of 2) $(spn) $(yn '[ -e "$(W7)" ]')"
end_case

# AC-08 (sleeper part): stdout captured through a pipe; the hook returns as soon as it is done
new_case; mkcred; SHIMD="$SHIMS"
at 0; run_fixture user-prompt-submit
cp "$FIX/pre-tool-use.json" "$SB/stdin"; M0=$(date +%s%N)
PIPED=$(env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" ALLYE_LIVE_WATCH=0 SHIM_REAL="$REAL" SHIM_DATE_NOW="$T0" "$BASH_BIN" "$HOOK" <"$SB/stdin" 2>&1)
M1=$(date +%s%N); DMS=$(( (M1 - M0) / 1000000 ))
check "AC-08: with a sleeper armed the piped hook returns (pipe closed) in under 2 s and prints nothing (observed ${DMS} ms)" "yes yes " "$(yn '[ -e "$(W7)" ]') $(yn '[ "$DMS" -lt 2000 ]') $PIPED"
wait_idle; check "AC-08: the sleeper still delivers" "2" "$(nbodies)"
end_case

# ─── ALY-217.2: the session watcher is started for a trusted owner (BR-03, BR-06, BR-07, D-21) ──────────
# The fake owner (hooks/test/fake-owner.mjs, run by node outside the sandbox PATH) runs `sh -c '. chain.sh'`, which
# waits for go.N files and runs the hook under `env -i` for each (node -> sh -c -> env -> bash live-report.sh); only
# these cases set ALLYE_LIVE_WATCH=1 (interval 1 s). Every pid is recorded with its start time in TRACK; cleanup kills
# only the pid recorded in watch.lock (and the fake owner by its recorded pid), after checking that start time.
echo "== session watcher start (ALY-217 AC-08..AC-13, AC-24) =="
SH_BIN="$(type -P sh)"
FOWNER="$SCRIPT_DIR/test/fake-owner.mjs"
WL7() { echo "$DATA/live/$H7.watch.lock"; }; WF7() { echo "$DATA/live/$H7.watch"; }
# watchers_under PREFIX: live watcher processes (cmdline `<bash> <live-report.sh> watch`) whose CLAUDE_PLUGIN_DATA starts
# with PREFIX (read-only scan of /proc; the environment is read only for processes with that exact cmdline).
watchers_under() {
  local f c n=0
  for f in /proc/[0-9]*; do
    c=$({ tr '\0' ' ' <"$f/cmdline"; } 2>/dev/null) || continue
    [ "$c" = "$BASH_BIN $HOOK watch " ] || continue
    { tr '\0' '\n' <"$f/environ"; } 2>/dev/null | grep -q "^CLAUDE_PLUGIN_DATA=$1" && n=$((n + 1))
  done
  echo "$n"
}
check "AC-13: no pre-existing case started a watcher (none running, no watch file or watch lock in any sandbox)" "0 0" \
  "$(watchers_under "$ROOT_TMP") $(find "$ROOT_TMP" \( -name '*.watch' -o -name '*.watch.lock' \) | wc -l | tr -d ' ')"

# wcase [REALBIN] [SHIMDIR]: a watcher sandbox. The watcher's whitelisted environment has no SHIM_LOG, so its PATH gets
# shims wrapped with this case's SHIM_LOG/SHIM_REAL as defaults (the hook's own values win). SHIMDIR (ALY-217.3): the shim
# set to wrap, e.g. "$SHIMS" for the real logging curl (default: the failing stub curl).
wcase() {
  new_case; mkcred; REAL="${1:-$REALBIN}"; [ -z "${2:-}" ] || SHIMD="$2"
  local s; mkdir -p "$SB/wshims" "$SB/own"
  for s in "$SHIMD"/*; do
    case "${s##*/}" in _wrap.sh) continue ;; esac
    printf '#!%s\n: "${SHIM_LOG:=%s}" "${SHIM_REAL:=%s}"; export SHIM_LOG SHIM_REAL\nexec %s "$@"\n' "$BASH_BIN" "$SB/log" "$REAL" "$s" >"$SB/wshims/${s##*/}"
    chmod +x "$SB/wshims/${s##*/}"
  done
  SHIMD="$SB/wshims"; OWN="$SB/own"; CHAIN="$SB/chain.sh"; GO=0; OPID=""; OSTART=""
  mkchain "$OWN" >"$CHAIN"
}
# mkchain OWNDIR: prints chain.sh for a fake owner whose control files live in OWNDIR.
# chain.sh, sourced by `sh -c '. "$1"' sh chain.sh DEPTH`: DEPTH more shells in between, then one hook per go.N file
# (`<stdin file> plain|pipe [NAME=VALUE...]`); done.N holds the hook's wall time in ms; `exit` or 60 s idle ends it.
mkchain() {
  local OWN="$1"
  {
    printf 'if [ "$2" -gt 0 ]; then %q -c %q sh "$1" $(($2 - 1)); exit $?; fi\n' "$SH_BIN" '. "$1"'
    printf 'i=1\nwhile [ "$i" -le 30 ]; do\n'
    printf '  w=0; while [ ! -e %q/go.$i ]; do [ -d %q ] || exit 0; w=$((w + 1)); [ "$w" -le 1200 ] || exit 0; sleep 0.05; done\n' "$OWN" "$OWN"
    printf '  read -r in mode extra <%q/go.$i; [ "$in" != exit ] || exit 0\n' "$OWN"
    printf '  t0=$(date +%%s%%N)\n'
    printf '  set -- env -i HOME=%q XDG_CONFIG_HOME=%q XDG_CACHE_HOME=%q CLAUDE_PLUGIN_DATA=%q PATH=%q SHIM_LOG=%q SHIM_REAL=%q' \
      "$SB/home" "$SB/config" "$SB/cache" "$DATA" "$SHIMD:$REAL" "$SB/log" "$REAL"
    printf ' ALLYE_LIVE_WATCH=1 ALLYE_LIVE_WATCH_INTERVAL=1 ALLYE_LIVE_MARKER=MARKER_ABCDEF CLAUDE_PROJECT_DIR=/work/MARKER_CWD CLAUDE_SESSION_ID=%q $extra %q %q\n' "$RAWSID" "$BASH_BIN" "$HOOK"
    printf '  if [ "$mode" = pipe ]; then "$@" <"$in" 2>&1 | cat >%q/piped.$i; else "$@" <"$in" >%q/out.$i 2>&1; echo $? >%q/rc.$i; fi\n' "$OWN" "$OWN" "$OWN"
    printf '  t1=$(date +%%s%%N); echo $(( (t1 - t0) / 1000000 )) >%q/ms.$i; mv %q/ms.$i %q/done.$i\n' "$OWN" "$OWN" "$OWN"
    printf '  i=$((i + 1))\ndone\n'
  }
}
# owner_start [DEPTH] [EXE]: the fake owner (EXE: node, or a symlink to node with another name) running chain.sh.
owner_start() {
  "${2:-$NODE_BIN}" "$FOWNER" "$OWN" "$SH_BIN" -c '. "$1"' sh "$CHAIN" "${1:-0}"
  wait_for '[ -s "$OWN/owner" ]'
  OPID=""; OPGID=""; { read -r OPID OPGID <"$OWN/owner"; } 2>/dev/null; OSTART=$(pstart "$OPID")
  [[ "$OPID" =~ ^[0-9]+$ ]] && [[ "$OSTART" =~ ^[0-9]+$ ]] && TRACK+=("$OPID $OSTART")
}
# owner_go FIXTURE [plain|pipe] [NAME=VALUE...]: one hook through the chain; waits for it, then for its flusher/sleeper.
owner_go() {
  local f="$1" m="${2:-plain}"; shift; [ $# -gt 0 ] && shift
  cp "$FIX/$f.json" "$OWN/in.$((GO + 1))"
  GO=$((GO + 1)); printf '%s %s %s\n' "$OWN/in.$GO" "$m" "$*" >"$OWN/go.$GO.tmp"; mv "$OWN/go.$GO.tmp" "$OWN/go.$GO"
  wait_for '[ -e "$OWN/done.$GO" ]'; HMS=$(cat "$OWN/done.$GO" 2>/dev/null)
  watch_track
}
# wpid: the watcher pid recorded in watch.lock ("" when none); watch_track adds it to TRACK with its start time.
wpid() { local p="" s=""; { read -r p s <"$(WL7)/p"; } 2>/dev/null; [[ "$p" =~ ^[0-9]+$ ]] && printf '%s' "$p"; }
watch_track() { local p; p=$(wpid); [ -n "$p" ] && [ -n "$(pstart "$p")" ] && TRACK+=("$p $(pstart "$p")"); return 0; }
# alive PID START: the process PID still runs with that start time.
alive() { [[ "$1" =~ ^[0-9]+$ ]] && [ -n "$2" ] && [ "$(pstart "$1")" = "$2" ]; }
# watch_cleanup: kills only the pid recorded in watch.lock after checking its start time, then waits until watch.lock,
# flush.lock and flush.wait are gone; prints "clean" or what is left.
watch_cleanup() {
  local p="" s="" i
  { read -r p s <"$(WL7)/p"; } 2>/dev/null
  [[ "$p" =~ ^[0-9]+$ ]] && [[ "$s" =~ ^[0-9]+$ ]] && alive "$p" "$s" && kill "$p" 2>/dev/null
  for i in $(seq 1 200); do
    [ ! -e "$(WL7)" ] && [ ! -e "$DATA/live/$H7.flush.lock" ] && [ ! -e "$(W7)" ] && { echo clean; return 0; }
    sleep 0.05
  done
  echo "left: $(ls "$DATA/live" | grep -E 'watch.lock|flush.lock|flush.wait' | tr '\n' ' ')"
}
# owner_stop: ends the chain loop, then kills the fake owner by its recorded pid after checking its start time.
owner_stop() {
  [ -n "$OWN" ] && [ -d "$OWN" ] && { printf 'exit\n' >"$OWN/go.$((GO + 1)).tmp"; mv "$OWN/go.$((GO + 1)).tmp" "$OWN/go.$((GO + 1))"; }
  alive "$OPID" "$OSTART" && kill "$OPID" 2>/dev/null
  wait_for '! alive "$OPID" "$OSTART"'
  OPID=""; OSTART=""
}
wend() { echo "$(watch_cleanup)"; owner_stop; end_case; }
envkeys() { tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | sed 's/=.*//' | sort | tr '\n' ' '; }
sigign_hup() { local m; m=$(sed -n 's/^SigIgn:[[:space:]]*//p' "/proc/$1/status" 2>/dev/null); [ -n "$m" ] && echo $(( 0x$m & 1 )); }
sess_of() { local l; { IFS= read -r l <"/proc/$1/stat"; } 2>/dev/null; l=${l##*) }; set -- $l; printf '%s' "${4:-}"; }

if [ ! -d /proc/self ]; then
  echo "  SKIP: watcher cases need /proc (Linux); the macOS ps path is checked manually (D-21)"
else
# AC-09 / AC-12 / BR-06: node -> sh -c -> env -> bash live-report.sh at SessionStart
wcase; owner_start
check "AC-09: the fake owner runs as node in a process group of its own (not vacuous)" "node $OPID" "$(cat "/proc/$OPID/comm" 2>/dev/null) $OPGID"
owner_go session-start-startup
W=$(wpid); WS=$(pstart "$W")
check "AC-09: the hook returned 0 silently and spooled the start" "0||{\"state\":\"started\",\"type\":\"state\"}" "$(cat "$OWN/rc.1" 2>/dev/null)|$(cat "$OWN/out.1")|$(spooled)"
check "AC-09: <hash>.watch names the node owner as '<pid> <start>', mode 0600" "$OPID $OSTART|600" "$(cat "$(WF7)" 2>/dev/null)|$(find "$(WF7)" -printf '%m' 2>/dev/null)"
check "AC-09: <hash>.watch matches ^[0-9]+ [0-9]+\$" "yes" "$(yn 'grep -qxE "[0-9]+ [0-9]+" "$(WF7)"')"
check "AC-09: watch.lock records a live watcher '<pid> <start>' running live-report.sh in watcher mode" "yes $BASH_BIN $HOOK watch " \
  "$(yn '[ -n "$W" ] && [ "$(cut -d" " -f2 "$(WL7)/p")" = "$WS" ]') $(tr '\0' ' ' <"/proc/$W/cmdline" 2>/dev/null)"
check "AC-09: exactly one watcher runs for this sandbox" "1" "$(watchers_under "$DATA")"
check "AC-12: the watcher's environment holds only the whitelisted names" "ALLYE_LIVE_WATCH ALLYE_LIVE_WATCH_INTERVAL CLAUDE_PLUGIN_DATA HOME LIVE_HASH PATH " "$(envkeys "$W")"
check "AC-12: the hash and data dir are this session's; no raw session id, marker or token in its environment or argv" "LIVE_HASH=$H7|CLAUDE_PLUGIN_DATA=$DATA|0" \
  "$(tr '\0' '\n' <"/proc/$W/environ" | grep '^LIVE_HASH=')|$(tr '\0' '\n' <"/proc/$W/environ" | grep '^CLAUDE_PLUGIN_DATA=')|$(cat "/proc/$W/environ" "/proc/$W/cmdline" | tr '\0' '\n' | grep -cE -- "$RAWSID|MARKER_|$TOKEN|SHIM_")"
check "AC-12: stdin, stdout and stderr of the watcher are /dev/null" "/dev/null /dev/null /dev/null" "$(readlink "/proc/$W/fd/0") $(readlink "/proc/$W/fd/1") $(readlink "/proc/$W/fd/2")"
check "BR-06: without setsid on the PATH the watcher ignores SIGHUP (not a session leader)" "1 no" "$(sigign_hup "$W") $(yn '[ "$(sess_of "$W")" = "$W" ]')"
alive "$W" "$WS" && kill -HUP "$W" 2>/dev/null; sleep 1.5
check "BR-06: a SIGHUP to the recorded watcher pid leaves it running and holding watch.lock" "yes $W" "$(yn 'alive "$W" "$WS"') $(wpid)"
check "the watcher made no curl call while it polled (only the hook's flush: one stub curl)" "1" "$(curl_calls)"
check "AC-13: cleanup by the recorded pid: watch.lock, flush.lock and flush.wait gone, watcher gone, its watch file removed" "clean no no" \
  "$(watch_cleanup) $(yn 'alive "$W" "$WS"') $(yn '[ -e "$(WF7)" ]')"
owner_stop; end_case

# AC-11: SessionStart again (compact, resume) for the same session and owner keeps exactly one watcher
wcase; owner_start
owner_go session-start-startup; W1=$(wpid); W1S=$(pstart "$W1")
owner_go session-start-compact; owner_go session-start-resume
check "AC-11: after three SessionStarts under one owner, watch.lock still names the first watcher, alive" "yes yes" "$(yn '[ -n "$W1" ] && [ "$(wpid)" = "$W1" ]') $(yn 'alive "$W1" "$W1S"')"
check "AC-11: exactly one watcher runs; watch still names the owner" "1 $OPID $OSTART" "$(watchers_under "$DATA") $(cat "$(WF7)" 2>/dev/null)"
check "AC-11 / AC-13: cleanup" "clean" "$(watch_cleanup)"; owner_stop; end_case

# AC-08: stdout through a pipe while a watcher and a sleeper are both started (second SessionStart within 2 s: no
# state change, so the line waits for a sleeper)
wcase; at 0; run_fixture session-start-startup
check "AC-08 setup: the first SessionStart (ALLYE_LIVE_WATCH=0) started no watcher" "no no" "$(yn '[ -e "$(WF7)" ]') $(yn '[ -e "$(WL7)" ]')"
owner_start; owner_go session-start-startup pipe "SHIM_DATE_NOW=$T0"
check "AC-08: with a watcher and a sleeper started, the piped hook returned (pipe closed) in under 2 s, printing nothing (observed ${HMS} ms)" "yes yes yes " \
  "$(yn '[ -n "$(wpid)" ]') $(yn '[ -e "$(W7)" ]') $(yn '[ "${HMS:-9999}" -lt 2000 ]') $(cat "$OWN/piped.1" 2>/dev/null)"
wait_idle
check "AC-08: the sleeper ended; the watcher still holds watch.lock" "no yes" "$(yn '[ -e "$(W7)" ]') $(yn '[ -n "$(wpid)" ]')"
check "AC-08 / AC-13: cleanup" "clean" "$(watch_cleanup)"; owner_stop; end_case

# AC-10: no trusted owner -> no watcher, no watch file, the hook spools and flushes as before
for kind in tmux claude node-MainThread node-Main depth6 depth7; do
  wcase
  case "$kind" in
    tmux|claude|node-MainThread|node-Main) mkdir -p "$SB/obin"; ln -s "$NODE_BIN" "$SB/obin/$kind"; owner_start 0 "$SB/obin/$kind"
                 check "AC-10 $kind: the owner's comm is $kind (not vacuous)" "$kind" "$(cat "/proc/$OPID/comm" 2>/dev/null)" ;;
    depth6) owner_start 6 ;;
    depth7) owner_start 7 ;;
  esac
  owner_go session-start-startup
  case "$kind" in
    claude|node-MainThread|depth6) EXP="yes yes 1"; L="an owner named $kind is trusted: watch file, watch.lock, one watcher" ;;
    *) EXP="no no 0"; L="no trusted owner ($kind) -> no watch file, no watch.lock, no watcher" ;;
  esac
  [ "$kind" = depth6 ] && L="a trusted owner 8 levels up (7 shells, then node) gets a watcher"
  [ "$kind" = depth7 ] && L="no trusted owner within 8 levels (8 shells before node) -> no watch file, no watch.lock, no watcher"
  check "AC-10: $L" "$EXP" "$(yn '[ -e "$(WF7)" ]') $(yn '[ -e "$(WL7)" ]') $(watchers_under "$DATA")"
  check "AC-10 $kind: the hook spooled and flushed as before (start line, one flush attempt through the stub curl), silent" \
    "{\"state\":\"started\",\"type\":\"state\"}|1|" "$(spooled)|$(curl_calls)|$(cat "$OWN/out.1")"
  check "AC-10 $kind / AC-13: cleanup" "clean" "$(watch_cleanup)"; owner_stop; end_case
done
# AC-10: the uid rule (owner_find alone: the same live node owner is refused under another uid) and PID 1
wcase; owner_start
ownerp() { env -i PATH="$REALBIN" "$BASH_BIN" -c "LC_ALL=C; UID_NOW=$1; $(fn_body "$HOOK" proc_start); $(fn_body "$HOOK" owner_find); owner_find $2; echo \" rc=\$?\""; }
check "AC-10: owner_find on the live node owner under its own uid -> '<pid> <start>'" "$OPID $OSTART rc=0" "$(ownerp "$(id -u)" "$OPID")"
check "AC-10: owner_find on the same process with another uid -> no owner" " rc=1" "$(ownerp "$(( $(id -u) + 1 ))" "$OPID")"
check "AC-10: owner_find from PID 1 -> no owner" " rc=1" "$(ownerp 0 1)"
check "AC-10: owner_find on a non-numeric pid -> no owner" " rc=1" "$(ownerp "$(id -u)" "1x")"
owner_stop; end_case

# AC-24: after the watcher ended (state ended), later hooks spool normally; only a UserPromptSubmit with no lock holder
# and a session not ended starts a new watcher, and a second one keeps it
wcase; owner_start
owner_go session-start-startup; W1=$(wpid); W1S=$(pstart "$W1")
printf 'ended' >"$DATA/live/$H7.state"
wait_for '! alive "$W1" "$W1S"'
check "AC-24 setup: the watcher saw the state ended and exited, removing watch and watch.lock" "no no no" "$(yn 'alive "$W1" "$W1S"') $(yn '[ -e "$(WL7)" ]') $(yn '[ -e "$(WF7)" ]')"
owner_go pre-tool-use
check "AC-24: a tool hook after the end spools its line and starts no watcher" "yes no" "$(yn 'spooled | grep -q "\"type\":\"tool\""') $(yn '[ -e "$(WL7)" ]')"
owner_go user-prompt-submit; W2=$(wpid); W2S=$(pstart "$W2")
check "AC-24: UserPromptSubmit with no lock holder starts a new watcher and rewrites watch; its line is spooled" "yes yes $OPID $OSTART yes" \
  "$(yn '[ -n "$W2" ] && alive "$W2" "$W2S"') $(yn '[ "$W2 $W2S" != "$W1 $W1S" ]') $(cat "$(WF7)" 2>/dev/null) $(yn 'spooled | grep -q "\"state\":\"working\""')"
owner_go user-prompt-submit
check "AC-24: a second UserPromptSubmit keeps that watcher, exactly one" "$W2 1" "$(wpid) $(watchers_under "$DATA")"
check "AC-24 / AC-13: cleanup" "clean" "$(watch_cleanup)"; owner_stop; end_case

# BR-06 / D-21: with setsid on the PATH the watcher leads a session of its own
if SETSID_BIN=$(type -P setsid); then
  REALBIN_SS="$ROOT_TMP/realbin-ss"; make_realbin "$REALBIN_SS"; ln -s "$SETSID_BIN" "$REALBIN_SS/setsid"
  wcase "$REALBIN_SS"; owner_start; owner_go session-start-startup; W=$(wpid)
  check "BR-06: with setsid present the watcher is a session leader outside the owner's process group, stdio /dev/null" "yes yes /dev/null /dev/null /dev/null" \
    "$(yn '[ -n "$W" ] && [ "$(sess_of "$W")" = "$W" ]') $(yn '[ "$(cat /proc/$W/stat 2>/dev/null | sed "s/.*) //" | cut -d" " -f3)" != "$OPGID" ]') $(readlink "/proc/$W/fd/0") $(readlink "/proc/$W/fd/1") $(readlink "/proc/$W/fd/2")"
  check "BR-06 setsid / AC-13: cleanup" "clean" "$(watch_cleanup)"; owner_stop; end_case
else
  echo "  SKIP: setsid not available on this host"
fi
# ─── ALY-217.3: the watcher ends a dead session with end_process_gone, else exits cleanly (BR-04, BR-05, BR-09) ──────
# Owners are killed only by their recorded pid after a start-time check; every wait is a poll of up to 10 s.
echo "== session watcher end (ALY-217 AC-14..AC-24) =="
GN7() { echo "$DATA/live/$H7.watch.gone"; }
# owner_kill [SIG]: ends the chain loop (so no shell is left behind), then sends SIG (default KILL) to the fake owner's
# recorded pid after checking its start time, and waits until it is gone.
owner_kill() {
  [ -n "$OWN" ] && [ -d "$OWN" ] && { printf 'exit\n' >"$OWN/go.$((GO + 1)).tmp"; mv "$OWN/go.$((GO + 1)).tmp" "$OWN/go.$((GO + 1))"; }
  wait_for '[ -e "$OWN/rc" ]'
  alive "$OPID" "$OSTART" && kill "-${1:-KILL}" "$OPID" 2>/dev/null
  wait_for '! alive "$OPID" "$OSTART"'
}
# touches W: how many lock refreshes (pidlock_pass temp + mv of watch.lock/p) watcher W made so far, from the mv shim log.
touches() { { grep -F "watch.lock/p.$1." "$SB/log/calls.log" 2>/dev/null | grep -c '^mv' ; } || true; }
# polls W N: waits until watcher W made N more lock refreshes (N more poll intervals).
polls() { local t0; t0=$(touches "$1"); wait_for "[ \"\$(touches $1)\" -ge $((t0 + $2)) ]"; }
jqcurl() { { grep -cE '^(jq|curl) ' "$SB/log/calls.log" 2>/dev/null; } || true; }
nend() { { grep -c 'end_process_gone' "$SB/api/ingest-bodies.log" 2>/dev/null; } || true; }
body() { sed -n "${1}p" "$SB/api/ingest-bodies.log"; }
wfiles() { echo "$(yn '[ -e "$(WF7)" ]') $(yn '[ -e "$(WL7)" ]') $(yn '[ -e "$(GN7)" ]')"; }
stateof() { cat "$DATA/live/$H7.state" 2>/dev/null; }
# privacy_scan LABEL (AC-22): no raw session id and no marker in any file or file name under the data dir, in the shim
# argv/config logs or in what the API received (environ.log is left out: it is the hooks' own environment, which the
# harness fills with markers on purpose; the watcher's environment is checked by AC-12).
privacy_scan() {
  local all="$SB/scan.txt" m n=0
  { find "$DATA" -type f ! -name hook-credential.json -exec cat {} +; find "$DATA" -print; cat "$SB/log/calls.log" "$SB/log/curl-config.log" "$SB/api/requests.log" "$SB/api/ingest-bodies.log" 2>/dev/null; } >"$all"
  for m in "$RAWSID" "${MARKERS[@]}"; do [ "$(grep -cF -- "$m" "$all" || true)" = 0 ] || n=$((n + 1)); done
  check "$1: no raw session id and no marker in files, names, curl argv/config or request bodies (scan not empty)" "0 yes" "$n $(yn '[ -s "$all" ]')"
}

# AC-14 / AC-22 / AC-23 / AC-24 / BR-09: pending lines (the API answered 5xx), owner killed -> flush, then one end event
wcase "" "$SHIMS"; printf '5xx' >"$SB/api/ingest-mode"; owner_start
owner_go session-start-startup; owner_go pre-tool-use; wait_idle
W=$(wpid); WS=$(pstart "$W"); SP=$(spool_seqs | tr '\n' ' '); N0=$(nbodies)
check "AC-14 setup: a watcher runs and two lines are pending after failed sends" "yes 2" "$(yn 'alive "$W" "$WS"') $(spool_seqs | grep -c .)"
J0=$(jqcurl); polls "$W" 3
check "AC-23: over three polls with a live owner the watcher made no jq or curl call (shim logs), and kept running" "$J0 yes" "$(jqcurl) $(yn 'alive "$W" "$WS"')"
printf 'ok' >"$SB/api/ingest-mode"
owner_kill KILL
wait_for '! alive "$W" "$WS"'
check "AC-14: the watcher exited after the owner was killed" "no" "$(yn 'alive "$W" "$WS"')"
wait_for '[ "$(nbodies)" -ge $((N0 + 2)) ]'
check "AC-14: exactly two more requests: the pending lines first, then the end event" "$((N0 + 2)) $SP" "$(nbodies) $(body $((N0 + 1)) | "$JQ_BIN" -r '.events[].seq' | tr '\n' ' ')"
EB=$(body $((N0 + 2)))
check "AC-14: the end request holds exactly one event {type: state, state: ended, code: end_process_gone} and the session hash" \
  "1|state ended end_process_gone|at,code,seq,state,type|$H7|claude-code" \
  "$(printf '%s' "$EB" | "$JQ_BIN" -r '"\(.events | length)|\(.events[0] | "\(.type) \(.state) \(.code)")|\(.events[0] | keys | join(","))|\(.session.hash)|\(.client.kind)"')"
check "AC-14: its at is strict ISO-8601 UTC and its seq is above every spooled seq" "yes yes" \
  "$(yn 'printf "%s" "$EB" | "$JQ_BIN" -r ".events[0].at" | grep -qxE "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"') $(yn '[ "$(printf "%s" "$EB" | "$JQ_BIN" -r ".events[0].seq")" -gt "$(printf "%s\n" $SP | sort -n | tail -n 1)" ]')"
check "AC-14: the end request was limited to 1 s (max-time and connect-timeout)" "max-time = 1 connect-timeout = 1" "$(tail -n 4 "$SB/log/curl-config.log" | grep -E '^(max-time|connect-timeout)' | tr '\n' ' ' | sed 's/ $//')"
check "AC-14: state ended, spool empty, watch, watch.lock and the gone marker removed; one end event in all" "ended 0 no no no 1" "$(stateof) $(spool_seqs | grep -c .) $(wfiles) $(nend)"
privacy_scan "AC-22 after an end event"
# BR-09 / AC-24: a later hook of the session reports normally; a UserPromptSubmit under a new owner starts a new watcher
hook_at "" user-prompt-submit; wait_idle
check "AC-24: a hook after the watcher end spools and sends its event (state working) normally" "$((N0 + 3)) working 0 working" \
  "$(nbodies) $(body $((N0 + 3)) | "$JQ_BIN" -r '.events[-1].state') $(spool_seqs | grep -c .) $(stateof)"
OWN="$SB/own2"; mkdir -p "$OWN"; CHAIN="$SB/chain2.sh"; mkchain "$OWN" >"$CHAIN"; GO=0; owner_start
owner_go user-prompt-submit; W2=$(wpid)
check "AC-24: a UserPromptSubmit under a new owner after the end starts a new watcher" "yes yes 1" "$(yn '[ -n "$W2" ] && [ "$W2" != "$W" ]') $(yn 'alive "$W2" "$(pstart "$W2")"') $(watchers_under "$DATA")"
check "AC-14 / AC-24: cleanup" "clean" "$(watch_cleanup)"; owner_stop; end_case

# AC-15 (correction SHD-01): a hook runs after the watcher first saw the owner missing -> nothing is sent at the next
# poll and the count starts over; the owner stays gone, so the end comes after two more clean misses
wcase "" "$SHIMS"; owner_start; owner_go session-start-startup plain ALLYE_LIVE_WATCH_INTERVAL=2; wait_idle
W=$(wpid); WS=$(pstart "$W")
owner_kill KILL
wait_for '[ -e "$(GN7)" ]'
check "AC-15 setup: the watcher saw the owner missing once and still runs" "yes yes" "$(yn '[ -e "$(GN7)" ]') $(yn 'alive "$W" "$WS"')"
hook_at "" pre-tool-use
polls "$W" 2   # the next poll (which sees the hook) and the one after it: both decided, the end can come one poll later
check "AC-15: at the poll after the hook nothing was sent and the watcher kept polling" "yes 0 started" "$(yn 'alive "$W" "$WS"') $(nend) $(stateof)"
wait_for '! alive "$W" "$WS"'; wait_for '[ "$(nend)" -ge 1 ]'
check "AC-15: two clean misses later exactly one end event, state ended, watch files removed" "no 1 ended no no no" \
  "$(yn 'alive "$W" "$WS"') $(nend) $(stateof) $(wfiles)"
privacy_scan "AC-22 after a hook during the debounce"
end_case

# SHD-01: a flusher rewrites the spool between the two misses (delayed API) -> the end is still sent, exactly once
wcase "" "$SHIMS"; owner_start; owner_go session-start-startup plain ALLYE_LIVE_WATCH_INTERVAL=2; wait_idle
W=$(wpid); WS=$(pstart "$W"); N0=$(nbodies)
printf '2500' >"$SB/api/ingest-delay"
polls "$W" 1
owner_go subagent-start   # an important event: its flusher sends at once and rewrites the spool about 2.5 s later
owner_kill KILL
wait_for '[ -e "$(GN7)" ]'
check "SHD-01 setup: at the first miss the hook's flusher is still in flight (the spool is rewritten after the marker)" "yes yes" \
  "$(yn '[ -e "$DATA/live/$H7.flush.lock" ]') $(yn 'alive "$W" "$WS"')"
wait_for '[ "$(nbodies)" -ge $((N0 + 1)) ]'; printf '0' >"$SB/api/ingest-delay"
wait_for '! alive "$W" "$WS"'; wait_for '[ "$(nend)" -ge 1 ]'; wait_idle
check "SHD-01: the spool rewrite by a flusher is not a hook: one end event after the flush, state ended, spool empty, watch files removed" \
  "no 1 $((N0 + 2)) ended 0 no no no" "$(yn 'alive "$W" "$WS"') $(nend) $(nbodies) $(stateof) $(spool_seqs | grep -c .) $(wfiles)"
end_case

# SHD-03: the pre-end flush gets 429 (back-off) or 401 (disabled) -> no end request; the state is still ended
for m in 429 401; do
  wcase "" "$SHIMS"; printf '5xx' >"$SB/api/ingest-mode"; owner_start; owner_go session-start-startup; wait_idle
  W=$(wpid); WS=$(pstart "$W"); N0=$(nbodies)
  printf '%s' "$m" >"$SB/api/ingest-mode"
  owner_kill KILL
  wait_for '! alive "$W" "$WS"'; wait_idle
  check "SHD-03 $m: only the flush request, no end event, state ended, back-off or disabled marker in place, watch files removed" \
    "$((N0 + 1)) 0 ended yes no no no" "$(nbodies) $(nend) $(stateof) $(yn '[ -e "$DATA/live/backoff" ] || [ -e "$DATA/live/disabled" ]') $(wfiles)"
  end_case
done

# AC-16: SessionEnd ran -> the watcher exits within one interval without a request, also once the owner is killed
wcase "" "$SHIMS"; owner_start; owner_go session-start-startup; wait_idle
W=$(wpid); WS=$(pstart "$W")
owner_go session-end-clear; wait_idle; M0=$(date +%s%N); N0=$(nbodies)
wait_for '! alive "$W" "$WS"'; M1=$(date +%s%N)
check "AC-16: after SessionEnd the watcher exited within about one interval (observed $(( (M1 - M0) / 1000000 )) ms), removing watch and watch.lock" \
  "no yes no no no" "$(yn 'alive "$W" "$WS"') $(yn '[ $(( (M1 - M0) / 1000000 )) -lt 2500 ]') $(wfiles)"
owner_kill KILL; wait_idle
check "AC-16: no request from the watcher, also after the owner was killed; no end_process_gone" "$N0 0 ended" "$(nbodies) $(nend) $(stateof)"
end_case

# AC-17: a later SessionStart under another owner rewrites watch; the old owner's death sends nothing, the new one's ends
wcase "" "$SHIMS"; owner_start; owner_go session-start-startup; wait_idle
W=$(wpid); WS=$(pstart "$W"); AOWN="$OWN"; AGO="$GO"; APID_="$OPID"; ASTART="$OSTART"
OWN="$SB/own2"; mkdir -p "$OWN"; CHAIN="$SB/chain2.sh"; mkchain "$OWN" >"$CHAIN"; GO=0; owner_start
owner_go session-start-resume; wait_idle
check "AC-17: watch now names the new owner; the same single watcher runs" "$OPID $OSTART|$W|1" "$(cat "$(WF7)" 2>/dev/null)|$(wpid)|$(watchers_under "$DATA")"
BOWN="$OWN"; BGO="$GO"; BPID="$OPID"; BSTART="$OSTART"; N0=$(nbodies)
OWN="$AOWN"; GO="$AGO"; OPID="$APID_"; OSTART="$ASTART"; owner_kill KILL
polls "$W" 3
check "AC-17: the old owner killed -> after three polls the watcher still runs and sent nothing" "yes $N0 0" "$(yn 'alive "$W" "$WS"') $(nbodies) $(nend)"
OWN="$BOWN"; GO="$BGO"; OPID="$BPID"; OSTART="$BSTART"; owner_kill KILL
wait_for '! alive "$W" "$WS"'; wait_for '[ "$(nend)" -ge 1 ]'
check "AC-17: the new owner killed -> one end event, state ended, watch files removed" "no 1 $((N0 + 1)) ended no no no" "$(yn 'alive "$W" "$WS"') $(nend) $(nbodies) $(stateof) $(wfiles)"
end_case

# AC-18: SIGHUP to the fake owner's recorded process group keeps the watcher; the owner's later death still ends
wcase "" "$SHIMS"; owner_start; owner_go session-start-startup; wait_idle
W=$(wpid); WS=$(pstart "$W"); N0=$(nbodies)
HPG=$(sed 's/.*) //' "/proc/$$/stat" | cut -d' ' -f3)
check "AC-18 setup: the recorded owner pgid is a number other than the harness's, 0 and 1 (not vacuous)" "yes" \
  "$(yn '[[ "$OPGID" =~ ^[0-9]+$ ]] && [ "$OPGID" -gt 1 ] && [ "$OPGID" != "$HPG" ]')"
[[ "$OPGID" =~ ^[0-9]+$ ]] && [ "$OPGID" -gt 1 ] && [ "$OPGID" != "$HPG" ] && alive "$OPID" "$OSTART" && kill -HUP -- "-$OPGID" 2>/dev/null
polls "$W" 2
check "AC-18: after SIGHUP to the owner's group the watcher and the owner still run; nothing was sent" "yes yes $N0" "$(yn 'alive "$W" "$WS"') $(yn 'alive "$OPID" "$OSTART"') $(nbodies)"
owner_kill KILL
wait_for '! alive "$W" "$WS"'; wait_for '[ "$(nend)" -ge 1 ]'
check "AC-18: the owner killed later -> exactly one end event, state ended, watch files removed" "no 1 $((N0 + 1)) ended no no no" "$(yn 'alive "$W" "$WS"') $(nend) $(nbodies) $(stateof) $(wfiles)"
end_case

# AC-19: off, disabled, credential removed -> exit without a request; a changed credential at send time -> no request
for kind in off disabled nocred repaired; do
  wcase "" "$SHIMS"; owner_start; owner_go session-start-startup; wait_idle
  W=$(wpid); WS=$(pstart "$W"); N0=$(nbodies)
  case "$kind" in
    off) : >"$DATA/live/off"; chmod 600 "$DATA/live/off" ;;
    disabled) printf 'cred:%s' "$(test_sha "$TOKEN")" >"$DATA/live/disabled"; chmod 600 "$DATA/live/disabled" ;;
    nocred) rm -f "$CRED" ;;
    repaired) TOKEN="$TOKEN2" mkcred; polls "$W" 2
              check "AC-19 repaired: a re-pair alone does not stop the watcher (fingerprint checked at send time)" "yes" "$(yn 'alive "$W" "$WS"')"
              owner_kill KILL ;;
  esac
  wait_for '! alive "$W" "$WS"'; wait_idle
  check "AC-19 $kind: the watcher exited without any request, removing watch and watch.lock" "no $N0 0 no no no" "$(yn 'alive "$W" "$WS"') $(nbodies) $(nend) $(wfiles)"
  [ "$kind" = repaired ] && check "AC-19 repaired: the state was not set to ended" "started" "$(stateof)"
  owner_stop; end_case
done
wcase "" "$SHIMS"; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/off"; chmod 600 "$DATA/live/off"
owner_start; owner_go session-start-startup
check "AC-19: the reporter is inert at SessionStart (off) -> no watch file, no watch.lock, no watcher, no request" "no no 0 0" \
  "$(yn '[ -e "$(WF7)" ]') $(yn '[ -e "$(WL7)" ]') $(watchers_under "$DATA") $(nbodies)"
owner_stop; end_case

# AC-20: the run cap (test override ALLYE_LIVE_WATCH_CAP=2 s, fresh sandbox) -> exit without sending, owner alive
wcase "" "$SHIMS"; owner_start; owner_go session-start-startup plain ALLYE_LIVE_WATCH_CAP=2; wait_idle
W=$(wpid); WS=$(pstart "$W"); N0=$(nbodies)
check "AC-20 setup: the watcher got the cap override" "ALLYE_LIVE_WATCH_CAP=2" "$(tr '\0' '\n' <"/proc/$W/environ" 2>/dev/null | grep '^ALLYE_LIVE_WATCH_CAP=')"
wait_for '! alive "$W" "$WS"'
check "AC-20: at its cap the watcher exited without a request, removing watch and watch.lock, while the owner lives" "no yes $N0 no no no" \
  "$(yn 'alive "$W" "$WS"') $(yn 'alive "$OPID" "$OSTART"') $(nbodies) $(wfiles)"
owner_stop; end_case

# AC-21: a malformed or missing watch file, or a live directory failing its owner/mode check -> exit without sending
for kind in letters three-fields two-lines zero-pid missing dir-mode; do
  wcase "" "$SHIMS"; owner_start; owner_go session-start-startup; wait_idle
  W=$(wpid); WS=$(pstart "$W"); N0=$(nbodies)
  case "$kind" in
    letters) printf 'abc def' >"$SB/w.tmp" ;;
    three-fields) printf '%s %s 7' "$OPID" "$OSTART" >"$SB/w.tmp" ;;
    two-lines) printf '%s %s\n1 2' "$OPID" "$OSTART" >"$SB/w.tmp" ;;
    zero-pid) printf '0 %s' "$OSTART" >"$SB/w.tmp" ;;
  esac
  case "$kind" in
    missing) rm -f "$(WF7)" ;;
    dir-mode) chmod 755 "$DATA/live" ;;
    *) chmod 600 "$SB/w.tmp"; mv -f "$SB/w.tmp" "$(WF7)" ;;
  esac
  wait_for '! alive "$W" "$WS"'
  check "AC-21 $kind: the watcher exited without any request and released watch.lock" "no $N0 0 no" "$(yn 'alive "$W" "$WS"') $(nbodies) $(nend) $(yn '[ -e "$(WL7)" ]')"
  chmod 700 "$DATA/live"
  owner_stop; end_case
done

# owner_find on the ps branch (Shield LOW of ALY-217.2): a comm holding glob characters is never expanded
wcase; mkdir -p "$SB/psbin" "$SB/globdir"; : >"$SB/globdir/claude"
printf '#!%s\nprintf "  1234 %%s S c*\\n" "$(id -u)"\n' "$BASH_BIN" >"$SB/psbin/ps"; chmod +x "$SB/psbin/ps"
psfind() { (cd "$SB/globdir" && env -i PATH="$SB/psbin:$REALBIN" "$BASH_BIN" -c "LC_ALL=C; UID_NOW=$(id -u); $(fn_body "$HOOK" proc_start); $(fn_body "$HOOK" owner_find | sed 's#-r "/proc/\$p/stat"#-r /nonexistent#; s#! -d /proc/self#! -d /nonexistent#'); owner_find \$\$; echo \" rc=\$?\""); }
check "owner_find (ps branch): a comm 'c*' next to a file named claude is not globbed into an owner" " rc=1" "$(psfind)"
end_case
check "AC-13: after the watcher cases no watcher of the harness is left running" "0" "$(watchers_under "$ROOT_TMP")"
fi

# ─── fake ingest API (harness self-check) ───────────────────────────────────
echo "== fake ingest API =="
ingest() {  # MODE [file...]: POST two events with the stored token; sets HTTP and RBODY; extra control files as NAME=VALUE
  local m="$1"; shift; local kv
  printf '%s' "$m" >"$SB/api/ingest-mode"
  for kv in "$@"; do printf '%s' "${kv#*=}" >"$SB/api/${kv%%=*}"; done
  HTTP=$("$CURL_BIN" -s -o "$SB/ingest.out" -D "$SB/ingest.hdr" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d '{"events":[{"seq":1},{"seq":2}]}' "$API/api/agent-runs/events" 2>/dev/null) || HTTP="curl-fail"
  RBODY=$(cat "$SB/ingest.out" 2>/dev/null)
}
new_case
ingest ok;       check "ok: 202 with counts and a shortId" "202 2,0,0,ab12cd" "$HTTP $("$JQ_BIN" -r '.data|"\(.accepted),\(.ignored),\(.dropped),\(.shortId)"' <<<"$RBODY")"
ingest ok-null;  check "ok-null: shortId null" "202 null" "$HTTP $("$JQ_BIN" -r '.data.shortId' <<<"$RBODY")"
ingest ok ingest-counts=1,1,0; check "counts file overrides the counts" "1,1,0" "$("$JQ_BIN" -r '.data|"\(.accepted),\(.ignored),\(.dropped)"' <<<"$RBODY")"
ingest 400;      check "400" "400 VALIDATION_FAILED" "$HTTP $("$JQ_BIN" -r '.error.message.code' <<<"$RBODY")"
ingest 401;      check "401 invalid credential" "401 HOOK_CREDENTIAL_INVALID" "$HTTP $("$JQ_BIN" -r '.error.message.code' <<<"$RBODY")"
ingest 401-inactive; check "401 inactive account" "401 USER_INACTIVE" "$HTTP $("$JQ_BIN" -r '.error.message.code' <<<"$RBODY")"
ingest 403;      check "403" "403 HOOK_CREDENTIAL_ROUTE_FORBIDDEN" "$HTTP $("$JQ_BIN" -r '.error.message.code' <<<"$RBODY")"
ingest 413;      check "413" "413 PAYLOAD_TOO_LARGE" "$HTTP $("$JQ_BIN" -r '.error.message.code' <<<"$RBODY")"
ingest 422;      check "422" "422 AGENT_RUN_LIMIT" "$HTTP $("$JQ_BIN" -r '.error.message.code' <<<"$RBODY")"
ingest 429 ingest-retry-after=7; check "429 with Retry-After" "429 7" "$HTTP $(grep -i '^retry-after' "$SB/ingest.hdr" | tr -d '\r' | cut -d' ' -f2)"
ingest 5xx;      check "5xx" "503" "$HTTP"
ingest drop;     check "dropped connection" "curl-fail" "$HTTP"
check "every body was recorded" "12" "$(wc -l <"$SB/api/ingest-bodies.log" | tr -d ' ')"
check "existing route unchanged: unknown path still 404" "404" "$("$CURL_BIN" -s -o /dev/null -w '%{http_code}' "$API/api/nope")"
end_case

# ─── hosts and routes across the three scripts (AC-17, BR-15, D-02) ─────────
# One sandbox, one fake API, one curl-shim log. allye-hooks.sh begin/finish, session-preferences.sh and
# live-report.sh all run through the shim PATH; the shim log (curl-config.log) is the observation. The
# assertion covers every request made BY THESE THREE SCRIPTS. The one test-only call that is outside it
# is the stand-in for the MCP tool (POST /api/hook-pairings), made with the real curl as in
# test-allye-hooks.sh. live-report.sh sends its first event as soon as it spools it (a state change), so all three routes
# are observed and the observed set must equal the allowed set.
echo "== hosts and routes (AC-17) =="
new_case; SHIMD="$SHIMS"
RUN_ENV=("ALLYE_API_URL=$API")
printf '' >"$SB/stdin"
run_script "$PAIRHOOK" begin "$DATA"
CH=$(printf '%s\n' "$OUT" | sed -n 's/^challenge: //p'); DEV=$(printf '%s\n' "$OUT" | sed -n 's/^deviceName: //p')
PCODE=$("$CURL_BIN" -s -X POST -H 'Content-Type: application/json' \
  -d "{\"challenge\":\"$CH\",\"deviceName\":\"$DEV\",\"clientKind\":\"claude-code\"}" "$API/api/hook-pairings" | "$JQ_BIN" -r '.data.pairingCode')
run_script "$PAIRHOOK" finish "$DATA" "$CH" "$PCODE"
check "pairing against the fake succeeded" "yes" "$(contains 'Paired' "$OUT")"
RUN_ENV=()
run_script "$PREFHOOK"
printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-0001","cwd":"/tmp/x"}' >"$SB/stdin"
run_script "$HOOK"
check "live-report.sh stays silent in the shared sandbox" "0||" "$RC|$OUT|$ERR"
CRED_HOST=$("$JQ_BIN" -r '.apiUrl' "$CRED" | sed 's#^[a-z]*://##')
CFG="$SB/log/curl-config.log"
OBS_HOSTS=$(sed -n 's/^url = "[a-z]*:\/\/\([^/]*\)\/.*"$/\1/p' "$CFG" | sort -u | tr '\n' ' ')
OBS_ROUTES=$(sed -n 's/^url = "[a-z]*:\/\/[^/]*\(\/[^"]*\)"$/\1/p' "$CFG" | sort -u | tr '\n' ' ')
ALLOWED="/api/agent-runs/events /api/hook-pairings/exchange /api/memories/preferences"
check "observed requests exist (pin is not vacuous)" "yes" "$([ -n "$OBS_ROUTES" ] && echo yes || echo no)"
check "host set equals exactly the host of the credential file" "$CRED_HOST " "$OBS_HOSTS"
check "route set is a subset of the three allowed routes" "0" "$(for r in $OBS_ROUTES; do case " $ALLOWED " in *" $r "*) ;; *) echo bad;; esac; done | wc -l | tr -d ' ')"
check "route set observed: exactly the exchange, the preferences read and the ingest route" "/api/agent-runs/events /api/hook-pairings/exchange /api/memories/preferences " "$OBS_ROUTES"
check "no request was refused by the shim (no non-loopback host)" "no" "$([ -s "$SB/log/refused.log" ] && echo yes || echo no)"
check "every request the API saw is in the allowed set or the test-only stand-in" "0" \
  "$("$JQ_BIN" -r '.path' "$SB/api/requests.log" | while read -r p; do case " $ALLOWED /api/hook-pairings " in *" $p "*) ;; *) echo bad;; esac; done | wc -l | tr -d ' ')"
end_case

# ─── hooks/hooks.json registration (AC-13, BR-15, D-09) ─────────────────────
echo "== hooks.json registers the reporter for exactly the confirmed events =="
HJ="$SCRIPT_DIR/hooks.json"; PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
check "hooks.json parses as JSON with a single top-level key, hooks" "yes hooks" "$("$JQ_BIN" -e 'type == "object"' "$HJ" >/dev/null 2>&1 && echo yes || echo no) $("$JQ_BIN" -r 'keys | join(",")' "$HJ" 2>/dev/null)"
# The confirmed list is the set of hook_event_name values of the event fixtures; the negative controls
# (unmapped-event-*, unknown-event*) are fixtures of events that are NOT registered.
FIX_EVENTS=$(for f in "$FIX"/*.json; do case "$(basename "$f")" in unmapped-event-*|unknown-event*) continue ;; esac; "$JQ_BIN" -r '.hook_event_name' "$f"; done | sort -u | tr '\n' ' ')
REG_EVENTS=$("$JQ_BIN" -r '.hooks | keys[]' "$HJ" 2>/dev/null | sort -u | tr '\n' ' ')
check "the fixture event list is the 12 confirmed events (not vacuous)" "12" "$(printf '%s' "$FIX_EVENTS" | wc -w | tr -d ' ')"
check "registered events == fixture events, no extra event" "$FIX_EVENTS" "$REG_EVENTS"
check "no negative-control event is registered" "0" "$("$JQ_BIN" -r '.hooks | keys[] | select(IN("FileChanged","PostToolUseFailure","PostToolBatch","PermissionDenied","PreCompact") or startswith("MARKER"))' "$HJ" | wc -l | tr -d ' ')"
REPORTER_CMD='${CLAUDE_PLUGIN_ROOT}/hooks/live-report.sh'
rep() { "$JQ_BIN" -r --arg c "$REPORTER_CMD" "$1" "$HJ"; }
check "every event has exactly one reporter hook, in one entry of its own" "12 12" "$(rep '[.hooks[][] | select(.hooks | map(.command) | index($c))] | length') $(rep '[.hooks | to_entries[] | select(.value | map(.hooks[] | select(.command == $c)) | length == 1)] | length')"
check "every reporter entry holds the reporter command alone (no other hook shares it)" "0" "$(rep '[.hooks[][] | select(.hooks | map(.command) | index($c)) | select((.hooks | length) != 1)] | length')"
check "every reporter hook is a command hook with the exact path under CLAUDE_PLUGIN_ROOT" "12" "$(rep '[.hooks[][].hooks[] | select(.command == $c and .type == "command")] | length')"
check "every reporter hook except SessionEnd is async" "11 0" "$(rep '[.hooks | to_entries[] | select(.key != "SessionEnd") | .value[].hooks[] | select(.command == $c and .async == true)] | length') $(rep '[.hooks | to_entries[] | select(.key != "SessionEnd") | .value[].hooks[] | select(.command == $c and .async != true)] | length')"
check "SessionEnd is synchronous (no async) with a 2 second timeout" "null 2" "$(rep '.hooks.SessionEnd[].hooks[] | select(.command == $c) | (.async // null | tostring)') $(rep '.hooks.SessionEnd[].hooks[] | select(.command == $c) | .timeout')"
check "async reporter hooks carry a 20 second timeout (state lock wait plus git, as the flush is detached)" "11 20" "$(rep '[.hooks | to_entries[] | select(.key != "SessionEnd") | .value[].hooks[] | select(.command == $c and (.timeout | type == "number"))] | length') $(rep '[.hooks | to_entries[] | select(.key != "SessionEnd") | .value[].hooks[] | select(.command == $c) | .timeout] | unique | .[0]')"
check "every reporter timeout is a number between 1 and 60" "0" "$(rep '[.hooks[][].hooks[] | select(.command == $c) | select((.timeout | type) != "number" or .timeout < 1 or .timeout > 60)] | length')"
check "the reporter registrations add no matcher (the script filters by itself)" "0" "$(rep '[.hooks[][] | select(.hooks | map(.command) | index($c)) | select(has("matcher"))] | length')"
check "the existing SessionStart hooks are unchanged (same entries, same order, first)" '[{"hooks":[{"command":"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh","timeout":15,"type":"command"}]},{"hooks":[{"command":"${CLAUDE_PLUGIN_ROOT}/hooks/session-preferences.sh","timeout":5,"type":"command"}],"matcher":"startup|clear|compact"}]' \
  "$("$JQ_BIN" -cS '.hooks.SessionStart[0:2]' "$HJ")"
check "the existing hooks are the only non-reporter hooks" "session-preferences.sh session-start.sh" "$(rep '[.hooks[][].hooks[].command | select(. != $c) | sub("^.*/"; "")] | sort | join(" ")')"
check "SessionStart has the two existing entries plus the reporter's" "3" "$(rep '.hooks.SessionStart | length')"
check "the command resolves to an existing executable file in this plugin" "yes" "$(p="${REPORTER_CMD/\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}"; [ -f "$p" ] && [ -x "$p" ] && echo yes || echo no)"
check "the other commands also resolve to executable files" "yes" "$(for c in session-start.sh session-preferences.sh; do [ -x "$PLUGIN_ROOT/hooks/$c" ] || echo no; done | grep -c no | sed 's/^0$/yes/')"

echo "== spike: SubagentStart/Stop on a resume, hook agent_id vs metadata id, metadata at the first tool (ALY-263.8 AC-12, D-14, D-19) =="
# Recorded facts live in fixtures/live/spike-facts.txt (PROVEN/UNPROVEN with the evidence kind). What the real hook sends on a
# SendMessage resume is UNPROVEN, so both shapes are replayed against the CURRENT script: a resume that fires SubagentStart
# again, and one that sends only tool events and a second SubagentStop. Later slices (ALY-263.11) change these expectations knowingly.
SPK='"id":"spk0a1b2c3d4e5f6","type":"allye:bridge-pilot"'
SPK_START="{\"type\":\"sub_start\",\"sub\":{$SPK}}"
SPK_TOOL="{\"type\":\"sub_tool\",\"tool\":\"Read\",\"sub\":{$SPK}}"
SPK_STOP="{\"type\":\"sub_stop\",\"sub\":{$SPK,\"outcome\":\"pass\",\"task\":\"ALY-1.2\"}}"
spike_case() {  # LABEL FIXTURES-CSV EXPECT-JSON-LINES...
  local label="$1" seqs="$2"; shift 2
  new_case; mkcred; run_fixture ${seqs//,/ }
  check "$label" "$(printf "%s\n" "$@" | "$JQ_BIN" -cS .)" "$(spooled)"
  check "$label: silent, exits 0" "0||" "$RC|$OUT|$ERR"
  check "$label: no event carries a resumed flag yet" "0" "$(spooled | grep -c resumed || true)"
  end_case
}
spike_case "baseline: start, tool, stop" spike-start,spike-tool,spike-stop "$SPK_START" "$SPK_TOOL" "$SPK_STOP"
spike_case "resume shape 1 (Start fires again): the second sub_start is dropped by the seen-set, the second tool and stop are sent plain" \
  spike-start,spike-tool,spike-stop,spike-start,spike-tool,spike-stop "$SPK_START" "$SPK_TOOL" "$SPK_STOP" "$SPK_TOOL" "$SPK_STOP"
spike_case "resume shape 2 (no Start, no Stop on the resume): a tool after the stop is sent as a plain sub_tool, nothing marks it" \
  spike-start,spike-stop,spike-tool "$SPK_START" "$SPK_STOP" "$SPK_TOOL"
spike_case "resume shape 3 (tool events only, then a second Stop): both stops are sent plain" \
  spike-start,spike-stop,spike-tool,spike-stop "$SPK_START" "$SPK_STOP" "$SPK_TOOL" "$SPK_STOP"
# the recorded facts: every key present exactly once, with the status the spike reached
SPKF="$FIX/spike-facts.txt"
spkf() { grep -E "^$1=" "$SPKF" | sed -E "s/^$1=([A-Z]+) .*/\1/"; }
check "fact a: SubagentStart on a resume is UNPROVEN" "UNPROVEN" "$(spkf a_start_fires_on_resume)"
check "fact a: SubagentStop on a resume is UNPROVEN" "UNPROVEN" "$(spkf a_stop_fires_on_resume)"
check "fact a: a resume reuses the agent id and its files is PROVEN from transcripts" "PROVEN" "$(spkf a_resume_reuses_id_and_files)"
check "fact b: transcript agentId equals the filename id is PROVEN" "PROVEN" "$(spkf b_transcript_agentId_equals_filename_id)"
check "fact b: the metadata file pairs with the transcript by filename is PROVEN" "PROVEN" "$(spkf b_meta_pairs_with_transcript_by_filename)"
check "fact b: the hook agent_id equals the filename id is UNPROVEN" "UNPROVEN" "$(spkf b_hook_agent_id_equals_filename_id)"
check "fact b: the metadata file holds no id key is PROVEN" "PROVEN" "$(spkf b_meta_has_no_id_key)"
check "fact c: metadata readable at the first tool is UNPROVEN" "UNPROVEN" "$(spkf c_meta_exists_at_first_tool)"
check "the facts file holds no path, home directory or real id" "0" "$(grep -cE '/home/|/Users/|[0-9a-f]{8}-[0-9a-f]{4}-' "$SPKF" || true)"

echo "== no final flusher left behind (ALY-217.7 AC-39) =="
check "AC-39: every case ended with no final flusher still running under the sandbox" "0" "$(finals_under "$ROOT_TMP")"

echo
echo "$PASS passed, $FAIL failed"
# a filtered run that executed no check (a regex that matches nothing) must not look green
[ -z "${LIVE_TEST_FILTERED:-}" ] || [ "$((PASS + FAIL))" -gt 0 ] || { echo "live test filter: no check ran"; exit 1; }
[ "$FAIL" -eq 0 ]
