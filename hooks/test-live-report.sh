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
  for t in bash curl jq sha256sum shasum od find mktemp mv uname tr id rm chmod mkdir cat dirname sleep grep sed cut head env date git; do
    case " $* " in *" $t "*) continue ;; esac
    p=$(type -P "$t") && ln -s "$p" "$dir/$t"
  done
}
link_shims() { local dir="$1" s; shift; mkdir -p "$dir"; for s in "$SHIMS"/*; do case " $* " in *" $(basename "$s") "*) continue ;; esac; ln -s "$s" "$dir/$(basename "$s")"; done; }
REALBIN="$ROOT_TMP/realbin";             make_realbin "$REALBIN"
REALBIN_NOCURL="$ROOT_TMP/realbin-nc";   make_realbin "$REALBIN_NOCURL" curl
REALBIN_NOJQ="$ROOT_TMP/realbin-nj";     make_realbin "$REALBIN_NOJQ" jq
REALBIN_NOSHA="$ROOT_TMP/realbin-nosha"; make_realbin "$REALBIN_NOSHA" sha256sum shasum
SHIMS_NOCURL="$ROOT_TMP/shims-nc";       link_shims "$SHIMS_NOCURL" curl
SHIMS_NOJQ="$ROOT_TMP/shims-nj";         link_shims "$SHIMS_NOJQ" jq
SHIMS_NOSHA="$ROOT_TMP/shims-nosha";     link_shims "$SHIMS_NOSHA" sha256sum shasum

TOKEN="alyh_$(printf 'Ab1_-%.0s' $(seq 1 8))xyz"    # 5*8+3 = 43 characters

N=0
new_case() {
  N=$((N + 1)); SB="$ROOT_TMP/case$N"
  mkdir -p "$SB/home" "$SB/config" "$SB/cache" "$SB/log" "$SB/api"
  DATA="$SB/plugindata"; CRED="$DATA/hook-credential.json"
  REAL="$REALBIN"; SHIMD="$SHIMS"; RUN_ENV=(); DATA_ENV="$DATA"
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
  OUT=$(cat "$SB/out"); ERR=$(cat "$SB/err")
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

# ─── helpers for spooled events (ALY-203.2) ─────────────────────────────────
FIX="$SCRIPT_DIR/fixtures/live"
RAWSID="RAWSESSION-7f3a9c1e-0b2d-4e11-9a55-c0ffee123456"   # session_id of every fixture
MARKERS=(MARKER_PROMPT_xyz MARKER_CMD MARKER_PATH MARKER_MSG MARKER_LASTMSG MARKER_BRANCH MARKER_CWD MARKER_TRANSCRIPT MARKER_ARGS MARKER_RESPONSE MARKER_TITLE MARKER_MODEL MARKER_SOURCE MARKER_TYPE MARKER_ERR MARKER_REASON MARKER_AGENT MARKER_ABCDEF MARKER_NewEvent)
test_sha() { if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -d' ' -f1; else printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; fi; }
DEFAULT_SID="sess-0001"
spool_of() { echo "$DATA/live/$(test_sha "$1").spool"; }
# spooled SID: the spool lines without their `at`, compact, one per line ("" when no spool).
spooled() { local f; f=$(spool_of "${1:-$RAWSID}"); [ -f "$f" ] && "$JQ_BIN" -cS 'del(.at)' "$f" || true; }
# run_fixture NAME...: feeds each fixture in order on stdin (same session), sets OUT/ERR/RC of the last.
run_fixture() { local n; for n in "$@"; do cp "$FIX/$n.json" "$SB/stdin"; run_hook; done; }
expected_of() { local n; for n in "$@"; do cat "$FIX/$n.expect"; done; }
# expect_fixture NAME: a fresh sandbox, the fixture alone -> exactly its .expect events and nothing else.
expect_fixture() {
  new_case; mkcred; run_fixture "$1"
  check "$1: exits 0, silent" "0||" "$RC|$OUT|$ERR"
  check "$1: spools exactly the listed events" "$(expected_of "$1" | "$JQ_BIN" -cS .)" "$(spooled)"
  check "$1: no request sent in this slice" "0 0" "$(curl_calls) $(reqs)"
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
new_case; mkcred; REAL="$REALBIN_NOJQ"; SHIMD="$SHIMS_NOJQ"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "jq missing"; REAL="$REALBIN"; SHIMD="$SHIMS"; run_hook; expect_spooled "jq missing"; end_case
new_case; mkcred; REAL="$REALBIN_NOCURL"; SHIMD="$SHIMS_NOCURL"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "curl missing"; REAL="$REALBIN"; SHIMD="$SHIMS"; run_hook; expect_spooled "curl missing"; end_case
new_case; mkcred; REAL="$REALBIN_NOSHA"; SHIMD="$SHIMS_NOSHA"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "SHA-256 tool missing"; REAL="$REALBIN"; SHIMD="$SHIMS"; run_hook; expect_spooled "SHA-256 tool missing"; end_case

echo "== enabled: spools, sends nothing yet (positive control) =="
new_case; mkcred; run_hook
check "paired and on: exits 0" "0" "$RC"
check "paired and on: stdout empty" "" "$OUT"
check "paired and on: stderr empty" "" "$ERR"
check "paired and on: sends nothing yet (no curl, no request)" "0 0" "$(curl_calls) $(reqs)"
check "paired and on: the event is spooled, keyed by the hash" '{"state":"working","type":"state"}' "$(spooled "$DEFAULT_SID")"
check "paired and on: live dir 0700, spool 0600, state file present" "700 600 working" \
  "$(find "$DATA/live" -maxdepth 0 -printf '%m' ) $(find "$(spool_of "$DEFAULT_SID")" -printf '%m') $(cat "${DATA}/live/$(test_sha "$DEFAULT_SID").state")"
check "paired and on: at is ISO-8601 UTC" "yes" "$("$JQ_BIN" -r '.at | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z") | if . then "yes" else "no" end' "$(spool_of "$DEFAULT_SID")")"
check "paired and on: no seq field yet" "no" "$("$JQ_BIN" -r 'has("seq") | if . then "yes" else "no" end' "$(spool_of "$DEFAULT_SID")")"
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
seq_case "waiting then SubagentStop: no working (not a trigger)" "$WQ" '{"type":"sub_stop","sub":{"id":"agent-abc123","type":"allye:bridge-pilot"}}'
SEQ=(pre-tool-use pre-tool-use)
seq_case "no waiting: no working is inserted" '{"type":"tool","tool":"Bash"}' '{"type":"tool","tool":"Bash"}'
SEQ=(permission-request pre-tool-use-tool-space pre-tool-use)
seq_case "a dropped PreToolUse still spools working once; the next tool follows" "$WP" "$W" '{"type":"tool","tool":"Bash"}'

# ─── AC-02 / AC-14: no marker and no raw session id anywhere ────────────────
echo "== markers and the raw session id (AC-02, AC-14) =="
new_case; mkcred
for f in "$FIX"/*.json; do cp "$f" "$SB/stdin"; run_hook; [ -z "$OUT$ERR" ] || echo "  (output from $(basename "$f"))"; done
ALLTXT="$SB/all.txt"; { find "$DATA" -type f -exec cat {} +; find "$DATA" -print; cat "$SB/log"/* "$SB/api/requests.log" 2>/dev/null; } >"$ALLTXT"
for m in "${MARKERS[@]}"; do check "marker $m absent from every file, filename, shim log and request" "0" "$(grep -cF -- "$m" "$ALLTXT" || true)"; done
check "spool is non-empty (not vacuous)" "yes" "$([ "$(cat "$DATA"/live/*.spool | wc -l | tr -d ' ')" -gt 20 ] && echo yes || echo no)"
check "raw session id absent from every file, filename, shim log and request" "0" "$(grep -cF -- "$RAWSID" "$ALLTXT" || true)"
check "files are keyed by sha256(session id): spool and state" "$(test_sha "$RAWSID").spool $(test_sha "$RAWSID").state" "$(cd "$DATA/live" && ls | tr '\n' ' ' | sed 's/ $//')"
check "stdout and stderr were empty for every payload" "" "$(cat "$SB/out" "$SB/err")"
check "every spool line holds only contract fields of this slice" "0" "$("$JQ_BIN" -c 'select((keys - ["at","type","state","tool","code","sub"]) | length > 0)' "$DATA"/live/*.spool | wc -l | tr -d ' ')"
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
# test-allye-hooks.sh. At this slice live-report.sh sends nothing, so the ingest route is in the allowed
# set but not yet observed; the observed set must be a subset of the allowed set and equal the two
# routes the other scripts use.
echo "== hosts and routes (AC-17) =="
new_case
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
check "route set observed now: exchange and preferences" "/api/hook-pairings/exchange /api/memories/preferences " "$OBS_ROUTES"
check "no request was refused by the shim (no non-loopback host)" "no" "$([ -s "$SB/log/refused.log" ] && echo yes || echo no)"
check "every request the API saw is in the allowed set or the test-only stand-in" "0" \
  "$("$JQ_BIN" -r '.path' "$SB/api/requests.log" | while read -r p; do case " $ALLOWED /api/hook-pairings " in *" $p "*) ;; *) echo bad;; esac; done | wc -l | tr -d ' ')"
end_case

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
