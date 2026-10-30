#!/bin/bash
# NON-GATING latency measurement of hooks/live-report.sh (ALY-263.13, AC-16). It replays the ALY-260-style tool-event sequence of
# hooks/fixtures/live/latency/sequence.json (28 tool events) N times against two scripts in the same kind of sandbox, interleaved
# (baseline call, then current call, for the same event), and PRINTS the per-script p50 and p95 per tool event and the delta in ms.
# It is informational: it never fails on a threshold and exits 0 (architecture guard ALY-54: no test asserts an elapsed-time bound).
#   baseline: the frozen pre-change script, `git show v2.12.0:hooks/live-report.sh` (no tag: "skip: no baseline", exit 0)
#   current : hooks/live-report.sh of this checkout
# Optional environment: ROUNDS (default 5), MEASURE_EXTRA_SCRIPT (a third script to print, e.g. an earlier build of the current one),
# MEASURE_MODE (sub, main or both; default both: the events of a subagent, then of the main session).
# The sandbox is a throwaway HOME/XDG/CLAUDE_PLUGIN_DATA under a temp dir, a fake loopback API (hooks/test/fake-hooks-api.mjs, node) and
# a fake token; nothing real is read or sent. The only process started is the fake API, killed by its recorded pid on exit.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$HOOKS/.." && pwd)"
SEQ="$HOOKS/fixtures/live/latency/sequence.json"
CURRENT="$HOOKS/live-report.sh"
ROUNDS="${ROUNDS:-5}"
MODE="${MEASURE_MODE:-both}"
JQ="$(type -P jq)"; NODE="$(type -P node)"
[ -n "$JQ" ] && [ -f "$SEQ" ] || { echo "skip: jq or the sequence fixture is missing"; exit 0; }
TMP="$(mktemp -d)" || exit 0
# The fake API pid is recorded and only that pid is killed (never by name); it starts with every descriptor above 2 closed so a
# caller's flock fd cannot outlive the run through it; the EXIT/INT/TERM trap kills it and the end of the script checks it is gone.
APID=""; APIDS=()
fake_stop() { local p="$APID"; APID=""; [ -z "$p" ] || { kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; }; return 0; }
cleanup() { fake_stop; rm -rf "$TMP"; }
trap cleanup EXIT
trap 'exit 130' INT; trap 'exit 143' TERM

if ! git -C "$REPO" rev-parse -q --verify "v2.12.0^{commit}" >/dev/null 2>&1; then echo "skip: no baseline"; exit 0; fi
BASE="$TMP/baseline-live-report.sh"
git -C "$REPO" show v2.12.0:hooks/live-report.sh >"$BASE" 2>/dev/null && [ -s "$BASE" ] || { echo "skip: no baseline"; exit 0; }
chmod 755 "$BASE"
# the script reads its sibling lib/credential.sh: give the frozen copy the current library next to it
mkdir -p "$TMP/lib"; cp "$HOOKS/lib/credential.sh" "$TMP/lib/credential.sh" 2>/dev/null
[ -n "$NODE" ] || { echo "skip: no node for the fake API"; exit 0; }
mkdir -p "$TMP/api"
( for _f in $(ls "/proc/$BASHPID/fd" 2>/dev/null); do [ "$_f" -gt 2 ] && eval "exec $_f>&-"; done; exec "$NODE" "$HOOKS/test/fake-hooks-api.mjs" "$TMP/api" >"$TMP/api/node.log" 2>&1 ) &
APID=$!; APIDS+=("$APID")
for _ in $(seq 1 100); do [ -s "$TMP/api/port" ] && break; sleep 0.05; done
PORT="$(cat "$TMP/api/port" 2>/dev/null)"; [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "skip: fake API did not start"; exit 0; }

SID="MEASURE-7f3a9c1e-0b2d-4e11-9a55-c0ffee123456"
# sandbox NAME: HOME, XDG and plugin data of one script, the credential, the transcript layout
sandbox() {
  local d="$TMP/$1"
  mkdir -p "$d/home/.claude/projects/p/$SID/subagents" "$d/config" "$d/cache" "$d/data"; chmod 700 "$d/data"
  "$JQ" -n --arg u "http://127.0.0.1:$PORT" '{token:"alyh_Ab1_-Ab1_-Ab1_-Ab1_-Ab1_-Ab1_-Ab1_-Ab1_-xyz", email:"dev@example.test", tenantName:"Acme Org", deviceName:"laptop", apiUrl:$u, absoluteExpiresAt:"2036-12-01T00:00:00.000Z", pairedAt:"2026-01-01T00:00:00Z"}' >"$d/data/hook-credential.json"
  chmod 600 "$d/data/hook-credential.json"
  printf '%s' '{"description":"Implement ALY-260.4 for the slice"}' >"$d/home/.claude/projects/p/$SID/subagents/agent-lat1.meta.json"
}
# payloads MODE: one file per event, built before anything is timed
payloads() {
  local mode="$1" n i
  n=$("$JQ" 'length' "$SEQ")
  for i in $(seq 0 $((n - 1))); do
    "$JQ" --argjson i "$i" --arg sid "$SID" --arg tp "@@/home/.claude/projects/p/$SID.jsonl" --arg mode "$mode" '.[$i]
      | {session_id: $sid, transcript_path: $tp, cwd: "/tmp", hook_event_name: "PreToolUse", tool_name, tool_input, tool_use_id: ("toolu_" + ($i | tostring))}
      + (if $mode == "sub" then {agent_id: "lat1", agent_type: "allye:bridge-pilot"} else {} end)' "$SEQ" >"$TMP/payload-$mode-$i.json"
  done
}
# one_call SCRIPTNAME SANDBOX PAYLOAD: wall ms (with one decimal as integer tenths) of one hook call
declare -A SAMPLES
call() {  # call LABEL SCRIPT SANDBOX PAYLOAD KEY
  local label="$1" script="$2" sb="$3" pl="$4" key="$5" t0 t1 f
  f="$TMP/pl.$label.json"; sed "s#@@#$TMP/$sb#" "$pl" >"$f"
  t0=${EPOCHREALTIME/[.,]/}
  env -i HOME="$TMP/$sb/home" XDG_CONFIG_HOME="$TMP/$sb/config" XDG_CACHE_HOME="$TMP/$sb/cache" CLAUDE_PLUGIN_DATA="$TMP/$sb/data" \
    PATH="$PATH" ALLYE_LIVE_WATCH=0 "$BASH" "$script" <"$f" >/dev/null 2>&1
  t1=${EPOCHREALTIME/[.,]/}
  SAMPLES[$key]="${SAMPLES[$key]:-} $(( (t1 - t0) / 100 ))"   # tenths of a millisecond
}
pctl() {  # pctl P LIST: the nearest-rank percentile of integers (tenths of ms), printed in ms with one decimal
  local p="$1" a=("${@:2}") n idx v
  n=${#a[@]}; [ "$n" -gt 0 ] || { printf 'n/a'; return; }
  mapfile -t a < <(printf '%s\n' "${a[@]}" | sort -n)
  idx=$(( (p * n + 99) / 100 - 1 )); [ "$idx" -ge 0 ] || idx=0
  v=${a[$idx]}; printf '%d.%d' $((v / 10)) $((v % 10))
}
EXTRA="${MEASURE_EXTRA_SCRIPT:-}"; if [ -f "$EXTRA" ]; then cp "$EXTRA" "$TMP/extra-live-report.sh" && chmod 755 "$TMP/extra-live-report.sh" && EXTRA="$TMP/extra-live-report.sh"; else EXTRA=""; fi
N=$("$JQ" 'length' "$SEQ")
echo "latency measurement (informational, never gating): $N tool events x $ROUNDS rounds per mode, interleaved"
for mode in sub main; do
  case "$MODE" in both) ;; "$mode") ;; *) continue ;; esac
  payloads "$mode"
  SAMPLES=()
  for r in $(seq 1 "$ROUNDS"); do
    for s in baseline current extra; do sandbox "$s-$mode-$r"; done
    # the first hook of a session opens the run: not a tool event, not measured
    for s in baseline current extra; do
      sc="$CURRENT"; [ "$s" = baseline ] && sc="$BASE"; [ "$s" = extra ] && { [ -n "$EXTRA" ] || continue; sc="$EXTRA"; }
      "$JQ" -nc --arg sid "$SID" '{session_id:$sid, cwd:"/tmp", hook_event_name:"UserPromptSubmit"}' >"$TMP/warm.json"
      env -i HOME="$TMP/$s-$mode-$r/home" XDG_CONFIG_HOME="$TMP/$s-$mode-$r/config" XDG_CACHE_HOME="$TMP/$s-$mode-$r/cache" CLAUDE_PLUGIN_DATA="$TMP/$s-$mode-$r/data" \
        PATH="$PATH" ALLYE_LIVE_WATCH=0 "$BASH" "$sc" <"$TMP/warm.json" >/dev/null 2>&1
    done
    for i in $(seq 0 $((N - 1))); do
      call b "$BASE" "baseline-$mode-$r" "$TMP/payload-$mode-$i.json" "baseline"
      call c "$CURRENT" "current-$mode-$r" "$TMP/payload-$mode-$i.json" "current"
      [ -z "$EXTRA" ] || call x "$EXTRA" "extra-$mode-$r" "$TMP/payload-$mode-$i.json" "extra"
    done
  done
  echo "mode $mode ($((N * ROUNDS)) samples per script), ms per tool event:"
  printf '  baseline v2.12.0   p50 %7s  p95 %7s\n' "$(pctl 50 ${SAMPLES[baseline]})" "$(pctl 95 ${SAMPLES[baseline]})"
  [ -z "$EXTRA" ] || printf '  extra              p50 %7s  p95 %7s\n' "$(pctl 50 ${SAMPLES[extra]})" "$(pctl 95 ${SAMPLES[extra]})"
  printf '  current            p50 %7s  p95 %7s\n' "$(pctl 50 ${SAMPLES[current]})" "$(pctl 95 ${SAMPLES[current]})"
  b=$(pctl 95 ${SAMPLES[baseline]}); c=$(pctl 95 ${SAMPLES[current]})
  bt=${b/./}; ct=${c/./}
  d=$((ct - bt)); sgn=""; [ "$d" -ge 0 ] || { sgn="-"; d=$((-d)); }
  printf '  delta p95 (current - baseline): %s%d.%d ms (informational; AC-16 budget 30 ms is recorded by the Mothership, not asserted here)\n' "$sgn" $((d / 10)) $((d % 10))
done
fake_stop
for p in ${APIDS[@]+"${APIDS[@]}"}; do kill -0 "$p" 2>/dev/null && { kill -9 "$p" 2>/dev/null; echo "FAIL: the fake API (pid $p) survived the run"; exit 1; }; done
exit 0
