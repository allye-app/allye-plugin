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

# ─── inert paths (AC-09, BR-01, BR-03) ──────────────────────────────────────
echo "== unpaired =="
new_case; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "no data directory"; end_case
new_case; mkdir -p "$DATA"; chmod 700 "$DATA"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "data directory without credential"; end_case
new_case; DATA_ENV=""; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "CLAUDE_PLUGIN_DATA unset"; end_case
new_case; mkcred; DATA_ENV="relative/dir"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "CLAUDE_PLUGIN_DATA relative"; end_case
new_case; mkcred; DATA_ENV='${CLAUDE_PLUGIN_DATA}/x'; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "CLAUDE_PLUGIN_DATA unexpanded"; end_case
new_case; mkcred; chmod 644 "$CRED"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "credential file readable by others"; end_case
new_case; mkcred "https://evil.example"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "credential URL outside the fixed list"; end_case
new_case; mkcred; "$JQ_BIN" 'del(.token)' "$CRED" >"$SB/c.json" && cat "$SB/c.json" >"$CRED"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "credential without a token"; end_case

echo "== switched off and marked disabled =="
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/off"; BEFORE=$(snapshot "$DATA")
run_hook
check "live off flag: exits 0" "0" "$RC"; check "live off flag: stdout empty" "" "$OUT"; check "live off flag: stderr empty" "" "$ERR"
check "live off flag: no curl, no request" "0 0" "$(curl_calls) $(reqs)"
check "live off flag: nothing changed in CLAUDE_PLUGIN_DATA" "$BEFORE" "$(snapshot "$DATA")"
end_case
new_case; mkcred; mkdir -p "$DATA/live"; chmod 700 "$DATA/live"; : >"$DATA/live/disabled"; BEFORE=$(snapshot "$DATA")
run_hook
check "disabled marker: exits 0" "0" "$RC"; check "disabled marker: stdout empty" "" "$OUT"; check "disabled marker: stderr empty" "" "$ERR"
check "disabled marker: no curl, no request" "0 0" "$(curl_calls) $(reqs)"
check "disabled marker: nothing changed in CLAUDE_PLUGIN_DATA" "$BEFORE" "$(snapshot "$DATA")"
end_case

echo "== missing tools =="
new_case; mkcred; REAL="$REALBIN_NOJQ"; SHIMD="$SHIMS_NOJQ"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "jq missing"; end_case
new_case; mkcred; REAL="$REALBIN_NOCURL"; SHIMD="$SHIMS_NOCURL"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "curl missing"; end_case
new_case; mkcred; REAL="$REALBIN_NOSHA"; SHIMD="$SHIMS_NOSHA"; BEFORE=$(snapshot "$DATA"); run_hook; expect_inert "SHA-256 tool missing"; end_case

echo "== enabled (skeleton: event handling comes later) =="
new_case; mkcred; BEFORE=$(snapshot "$DATA"); run_hook
check "paired and on: exits 0" "0" "$RC"
check "paired and on: stdout empty" "" "$OUT"
check "paired and on: stderr empty" "" "$ERR"
check "paired and on: sends nothing yet" "0 0" "$(curl_calls) $(reqs)"
check "paired and on: token absent from outputs and shim logs" "0" "$(cat "$SB/out" "$SB/err" "$SB/log"/* 2>/dev/null | grep -cF -- "$TOKEN")"
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
