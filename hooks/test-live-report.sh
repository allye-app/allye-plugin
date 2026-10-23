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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
cleanup() { [ -z "$APID" ] || kill "$APID" 2>/dev/null; rm -rf "$ROOT_TMP"; }
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
end_case() { [ -z "$APID" ] || { kill "$APID" 2>/dev/null; wait "$APID" 2>/dev/null; APID=""; }; }

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
    PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" SHIM_REAL="$REAL" \
    ${RUN_ENV[@]+"${RUN_ENV[@]}"} "$BASH_BIN" "$script" "$@" <"$SB/stdin" >"$SB/out" 2>"$SB/err"
  RC=$?
  [ "$script" != "$HOOK" ] || wait_idle
  OUT=$(cat "$SB/out"); ERR=$(cat "$SB/err")
}
# wait_idle: the flusher is detached; its flush lock is taken before the hook returns, so "no flush lock" = done.
wait_idle() { local i; for i in $(seq 1 400); do compgen -G "$DATA/live/*.flush.lock" >/dev/null || return 0; sleep 0.05; done; }
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
seq_case "permission_prompt then SubagentStart: working first, once" "$WP" "$W" '{"type":"sub_start","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}' '{"type":"sub_start","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}'
SEQ=(pre-tool-use-ask-user-question pre-tool-use-subagent)
seq_case "waiting then a subagent tool: working first" "$WQ" "$W" '{"type":"sub_tool","tool":"Read","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}'
SEQ=(pre-tool-use-ask-user-question stop pre-tool-use)
seq_case "waiting then Stop then a tool: Stop leaves waiting, no working" "$WQ" '{"type":"state","state":"idle","code":"turn_ended"}' '{"type":"tool","tool":"Bash"}'
SEQ=(pre-tool-use-ask-user-question subagent-stop)
seq_case "waiting then SubagentStop: no working (not a trigger)" "$WQ" '{"type":"sub_stop","sub":{"id":"agent-abc123","type":"allye:bridge-pilot","outcome":"pass","task":"ALY-1.2"}}'
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
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; run_fixture mcp-allye-spec-get; cwd_pay session-start-startup "$SB/repo"; run_hook
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
TMC='{"type":"tool","tool":"allye:spec_get"}'
SEQ=(skill-bridge-spec mcp-allye-spec-get)
seq_case "skill then mcp: the weaker mcp bind is not sent" "$S1" "$BSK" "$TMC"
SEQ=(mcp-allye-spec-get skill-bridge-spec)
seq_case "mcp then skill: the stronger skill bind is sent" "$TMC" "$BMC" "$S1" "$BSK"
SEQ=(skill-bridge-spec skill-bridge-spec)
seq_case "skill twice: the same bind is sent once" "$S1" "$BSK" "$S1"
SEQ=(mcp-allye-spec-get mcp-allye-spec-get)
seq_case "mcp twice: the same bind is sent once" "$TMC" "$BMC" "$TMC"
SEQ=(mcp-allye-spec-get mcp-allye-task-start)
seq_case "mcp with a different key (same strength): sent again" "$TMC" "$BMC" '{"type":"tool","tool":"allye:task_start"}' '{"type":"bind","bind":{"source":"mcp","spec":"ALY-203","task":"ALY-203.3"}}'
SEQ=(skill-bridge-spec expansion-bridge-spec)
seq_case "skill via Skill tool then via expansion with another key: sent again" "$S1" "$BSK" '{"type":"bind","bind":{"source":"skill","role":"bridge","mode":"launch","spec":"ALY-7"}}'
SEQ=(skill-bridge-subagent mcp-allye-subagent)
seq_case "calls made inside a subagent never bind" '{"type":"sub_tool","tool":"Skill","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}' '{"type":"sub_tool","tool":"allye:spec_get","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}'
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-5"); run_fixture session-start-startup mcp-allye-spec-get skill-bridge-spec
check "env then mcp then skill: each stronger source is sent" "$(printf '%s\n' "$SSB" '{"type":"bind","bind":{"source":"env","role":"session","spec":"ALY-5"}}' "$TMC" "$BMC" "$S1" "$BSK" | "$JQ_BIN" -cS .)" "$(spooled)"; end_case
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-5"); run_fixture skill-bridge-spec session-start-startup
check "skill then env at SessionStart: the weaker env bind is not sent" "$(printf '%s\n' "$S1" "$BSK" "$SSB" | "$JQ_BIN" -cS .)" "$(spooled)"; end_case
new_case; mkcred; mkrepo "bridge/aly-203-live-reporter"; cwd_pay session-start-startup "$SB/repo"; run_hook; run_fixture mcp-allye-spec-get skill-bridge-spec
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

echo "== markers in bindings =="
new_case; mkcred; RUN_ENV=("ALLYE_SPEC=ALY-203" "ALLYE_TASK=MARKER_ABCDEF"); mkrepo "bridge/aly-203-MARKER_BRANCH"
for n in skill-bridge-task skill-bridge-bad-key2 expansion-bridge-bad-key mcp-allye-bad-action mcp-bad-chars mcp-other-server; do run_fixture "$n"; done
cwd_pay session-start-startup "$SB/repo"; run_hook
check "ARGS, tool_input, branch and cwd markers absent from every file and log" "0" "$( { bind_files; cat "$SB/out" "$SB/err" "$SB/log/calls.log"; } | grep -cE 'MARKER_(ARGS|BRANCH|CMD|ABCDEF|CWD)' || true)"
check "every bind holds only contract keys and patterns" "0" "$("$JQ_BIN" -c 'select(.type == "bind") | .bind | select((keys - ["source","spec","task","role","mode"] | length > 0) or (.source | IN("skill","mcp","env","branch") | not) or ((.spec // "ALY-1") | test("\\A[A-Z][A-Z0-9]{1,9}-[0-9]+(\\.[0-9]+)?\\z") | not) or ((.task // "ALY-1.1") | test("\\A[A-Z][A-Z0-9]{1,9}-[0-9]+(\\.[0-9]+)?\\z") | not))' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
end_case


# ─── ALY-203.4: subagent outcome (BR-09, AC-07) ─────────────────────────────
echo "== subagent outcome from the structured output only (AC-07) =="
# stop_case LABEL MESSAGE-STRING EXPECTED-EVENT-JSON
stop_case() {
  new_case; mkcred; "$JQ_BIN" --arg m "$2" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
  check "$1" "$(printf '%s\n' "$3" | "$JQ_BIN" -cS .)" "$(spooled)"
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
  check "non-string last_assistant_message $badm -> unknown/returned" "$(printf '%s\n' "$UNK" | "$JQ_BIN" -cS .)|0||" "$(spooled)|$RC|$OUT|$ERR"; end_case
done
new_case; mkcred; "$JQ_BIN" 'del(.last_assistant_message)' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "missing last_assistant_message -> unknown/returned" "$(printf '%s\n' "$UNK" | "$JQ_BIN" -cS .)" "$(spooled)"; end_case
# only the first 64 KB of the message is examined: a status line past it does not count, one inside it does
new_case; mkcred
HUGE=$(head -c 70000 /dev/zero | tr '\0' 'a')
"$JQ_BIN" --arg m "$HUGE
status: passed" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "status line after 64 KB of text is not examined -> unknown" "$(printf '%s\n' "$UNK" | "$JQ_BIN" -cS .)|0||" "$(spooled)|$RC|$OUT|$ERR"; end_case
new_case; mkcred
"$JQ_BIN" --arg m "status: failed
$HUGE" '.last_assistant_message = $m' "$FIX/subagent-stop.json" >"$SB/stdin"; run_hook
check "status line inside the first 64 KB of a huge message counts" "{\"sub\":{\"id\":\"agent-abc123\",\"outcome\":\"fail\",\"type\":\"allye:bridge-pilot\"},\"type\":\"sub_stop\"}|0||" "$(spooled)|$RC|$OUT|$ERR"; end_case

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
check "files are keyed by sha256(session id): bind, cred, flushed, seq, spool and state (no lock left behind)" "$(test_sha "$RAWSID").bind $(test_sha "$RAWSID").cred $(test_sha "$RAWSID").flushed $(test_sha "$RAWSID").seq $(test_sha "$RAWSID").spool $(test_sha "$RAWSID").state" "$(cd "$DATA/live" && ls | tr '\n' ' ' | sed 's/ $//')"
check "stdout and stderr were empty for every payload" "" "$(cat "$SB/out" "$SB/err")"
check "every spool line holds only contract fields (seq included)" "0" "$("$JQ_BIN" -c 'select((keys - ["seq","at","type","state","tool","code","sub","bind","gates"]) | length > 0)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
check "every state value is in the contract enumeration" "0" "$("$JQ_BIN" -r 'select(.state != null) | .state | select(IN("started","working","waiting_input","idle","error","ended") | not)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
check "every code value is in the contract enumeration" "0" "$("$JQ_BIN" -r 'select(.code != null) | .code | select(IN("turn_ended","asked_question","permission_prompt","advisory","returned","cli_error_rate_limit","cli_error_authentication_failed","cli_error_billing_error","cli_error_invalid_request","cli_error_server_error","cli_error_max_output_tokens","cli_error_unknown","end_clear","end_resume","end_logout","end_prompt_input_exit","end_live_off","end_other") | not)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
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
    PATH="$SHIMD:$REALBIN" SHIM_LOG="$SB/log" SHIM_REAL="$REALBIN" ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
    "$BASH_BIN" "$HOOK" <"$1" >"$2" 2>&1 &
  BGPIDS="$BGPIDS $!"
}
BGPIDS=""
wait_bg() { wait $BGPIDS; BGPIDS=""; wait_idle; }   # never a bare `wait`: it would also wait for the fake API server
echo "== skill vs mcp binding race (SHD-02) =="
for round in 1 2 3 4 5 6; do
  new_case; mkcred; RUN_ENV=()
  bg_hook "$FIX/skill-bridge-spec.json" "$SB/o1"; bg_hook "$FIX/mcp-allye-spec-get.json" "$SB/o2"; bg_hook "$FIX/mcp-allye-task-start.json" "$SB/o3"; wait_bg
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
check "seq counter survives the emptied spool: the next seq is higher" "yes" "$([ "$(spool_seqs | tail -n 1)" -gt "$SENT1" ] && echo yes || echo no)"
end_case

echo "== flush policy: 5 seconds or an important event (AC-04) =="
T0=1800000000
at() { RUN_ENV=("SHIM_DATE_NOW=$((T0 + $1))"); }
new_case; mkcred; SHIMD="$SHIMS"
at 0; run_fixture user-prompt-submit
check "t+0: the first state change is sent" "1" "$(nbodies)"
at 1; run_fixture pre-tool-use; at 2; run_fixture pre-tool-use; at 4; run_fixture pre-tool-use
check "three non-important events within 5 s: nothing sent, all three spooled" "1 3" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 4; run_fixture post-tool-use
check "still nothing at 4 s (a PostToolUse adds no line)" "1 3" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 5; run_fixture pre-tool-use
check "at 5 s since the last flush: one request carrying the 4 spooled events" "2 4 0" "$(nbodies) $("$JQ_BIN" -r '.events | length' "$SB/api/ingest-bodies.log" | tail -n 1) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 6; run_fixture pre-tool-use
check "1 s after that flush a plain event waits" "2 1" "$(nbodies) $(wc -l <"$(spool_of "$RAWSID")" | tr -d ' ')"
at 6; run_fixture subagent-start
check "a subagent start is important: sent at once with the waiting event" "3 tool,sub_start" "$(nbodies) $("$JQ_BIN" -r '[.events[].type] | join(",")' "$SB/api/ingest-bodies.log" | tail -n 1)"
at 6; run_fixture subagent-stop
check "a subagent stop is important" "4" "$(nbodies)"
at 6; run_fixture skill-bridge-spec
check "a binding is important (tool + bind in one request)" "5" "$(nbodies)"
at 6; run_fixture notification-idle-prompt
check "a state change (working -> idle) is important" "6" "$(nbodies)"
at 6; run_fixture notification-idle-prompt
check "idle -> idle is not a change: nothing sent within the interval" "6" "$(nbodies)"
end_case
new_case; mkcred; SHIMD="$SHIMS"; mkdir -p "$SB/proj/.allye/missions/m-1"
SHA1=$(printf 'a%.0s' $(seq 1 40)); printf -- '- Gates: SHIELD_CLEAR %s · WATCHER_APPROVED — · MISSION_COMPLETE — · CI_PENDING —\n' "$SHA1" >"$SB/proj/.allye/missions/m-1/log.md"
at 0; run_fixture user-prompt-submit; at 1; GCWDV="$SB/proj"; FPV="$SB/proj/.allye/missions/m-1/log.md"
"$JQ_BIN" -c --arg c "$SB/proj" --arg f "$FPV" '. + {hook_event_name:"PostToolUse", tool_name:"Write", tool_input:{file_path:$f}, cwd:$c}' "$FIX/post-tool-use.json" >"$SB/stdin"; run_hook
check "gates are important: sent at once" "2 gates" "$(nbodies) $("$JQ_BIN" -r '.events[-1].type' "$SB/api/ingest-bodies.log" | tail -n 1)"
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

# 5xx and a dropped connection: the spool stays, no marker, no back-off, the next hook after 5 s retries
for m in 5xx drop; do
  new7; printf '%s' "$m" >"$SB/api/ingest-mode"; at 0; run_fixture user-prompt-submit
  check "answer '$m': one request, line kept, no marker, no back-off, exit 0 silent" "1 1 no no 0|" "$(nbodies) $(spn) $([ -e "$(LV disabled)" ] && echo yes || echo no) $([ -e "$(LV backoff)" ] && echo yes || echo no) $RC|$OUT$ERR"
  sweep "answer '$m'"
  printf 'ok' >"$SB/api/ingest-mode"; at 4; run_fixture pre-tool-use; check "'$m': 4 s later nothing is sent" "1" "$(nbodies)"
  at 5; run_fixture pre-tool-use
  check "after '$m' and 5 s with an OK API: the kept line goes out with the new ones" "2 0" "$(nbodies) $(spn)"
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
  env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" SHIM_REAL="$REAL" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"
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

echo "== SessionEnd (AC-10, BR-12) =="
new7; printf '3000' >"$SB/api/ingest-delay"; at 0; run_fixture user-prompt-submit; wait_idle; printf '3000' >"$SB/api/ingest-delay"
cp "$FIX/session-end-clear.json" "$SB/stdin"; M0=$(date +%s%N)
env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" SHIM_REAL="$REAL" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"; M1=$(date +%s%N)
check "SessionEnd with a 3 s API returns in under 1 s, silent" "yes|" "$([ $(( (M1 - M0) / 1000000 )) -lt 1000 ] && echo yes || echo no)|$(cat "$SB/out" "$SB/err")"
wait_idle
check "the final event was still delivered (received by the API) through a request limited to 1 second" "ended end_clear max-time = 1" \
  "$("$JQ_BIN" -r '.events[-1] | "\(.state) \(.code)"' "$SB/api/ingest-bodies.log" | tail -n 1) $(tail -n 8 "$SB/log/curl-config.log" | grep '^max-time' | tail -n 1)"
check "the earlier (non-final) request used the normal limit" "max-time = 8" "$(grep '^max-time' "$SB/log/curl-config.log" | head -n 1)"
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
n=0; for i in 1 2 3 4 5 6 7 8 9 10; do n=$((n + 1)); bg_hook "$FIX/subagent-start.json" "$SB/par.$n"; done; wait_bg
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
  env -i HOME="$SB/home" PATH="$SHIMS:$REALBIN" SHIM_LOG="$SB/log" SHIM_REAL="$REALBIN" CLAUDE_PLUGIN_DATA="$DATA" "$BASH_BIN" -c "
    LC_ALL=C; umask 077; UID_NOW=\$(id -u); . '$LIB'; CFP=''; SEND_MAXTIME=8; SEND_CONNECT=3
    $(for f in lock_is_stale lock_take lock_drop lock_touch private_file_ok jq_valid_def credfp backoff_active backoff_set mark_disabled batch_build spool_drop_sent flush_run; do fn_body "$HOOK" "$f"; done)
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
env -i HOME="$SB/home" PATH="$SHIMS:$REALBIN" SHIM_LOG="$SB/log" SHIM_REAL="$REALBIN" "$BASH_BIN" -c "
  LC_ALL=C; umask 077; UID_NOW=\$(id -u); . '$LIB'; CFP=''; SEND_MAXTIME=8; SEND_CONNECT=3
  $(for f in lock_is_stale lock_take lock_drop lock_touch private_file_ok jq_valid_def credfp backoff_active backoff_set mark_disabled batch_build spool_drop_sent flush_run; do fn_body "$HOOK" "$f"; done)
  HASH='$(test_sha "$RAWSID")'; LIVE_DIR='$DATA/live'; SPOOL='$SPF'; LOCKD=\"\$LIVE_DIR/x.lock\"; FLOCK=\"\$LIVE_DIR/x.flush.lock\"; BATCHF=\"\$LIVE_DIR/x.batch\"; HDRF=\"\$LIVE_DIR/x.hdr\"; RESPF=\"\$LIVE_DIR/x.resp\"; DIR='$DATA'; BACKOFFF=\"\$LIVE_DIR/backoff\"
  LIVE_API='$API'; LIVE_TOKEN='$TOKEN'; TMPF=''
  mkdir \"\$FLOCK\"; printf '%s %s' \"\$(date +%s)\" 'someone-else' >\"\$FLOCK/t\"; FTOK=not-mine; flush_run"
check "flusher that no longer owns its lock sends nothing and keeps the spool" "0 1" "$(nbodies) $(wc -l <"$SPF" | tr -d ' ')"; end_case

echo "== append while a request is in flight =="
new_case; mkcred; SHIMD="$SHIMS"; printf '1500' >"$SB/api/ingest-delay"; at 0
run_fixture_bg() { cp "$FIX/$1.json" "$SB/stdin"; env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" SHIM_REAL="$REAL" SHIM_DATE_NOW="$((T0 + 0))" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"; }
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
env -i HOME="$SB/home" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" CLAUDE_PLUGIN_DATA="$DATA" PATH="$SHIMD:$REAL" SHIM_LOG="$SB/log" SHIM_REAL="$REAL" "$BASH_BIN" "$HOOK" <"$SB/stdin" >"$SB/out" 2>"$SB/err"; S1=$(date +%s)
check "a hook whose flush meets a 3 s API returns in under 2 s, silent" "yes|" "$([ $((S1 - S0)) -lt 2 ] && echo yes || echo no)|$(cat "$SB/out" "$SB/err")"
wait_idle; check "and the detached flush still delivers" "1" "$(nbodies)"
end_case

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

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
