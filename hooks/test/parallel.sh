#!/bin/bash
# Parallel section runner shared by the hook test suites (see hooks/test/README.md). Source it near the top of a
# test script, after `set -u`, and call `pt_dispatch "$@"`.
#
# A test script is a preamble (helpers, sandbox setup), then sections, then a tally. Sections that depend on each
# other's helpers are grouped with a `#@group <id> <weight> [shards=N]` comment line placed before the group's first
# `echo "== NAME =="`; weight is the group's rough serial seconds (scheduling only). `#@always` ... `#@end` keeps a block of helpers
# in every run (without `#@end` the block runs to the next section), `#@tally` starts the final tally and `#@keepnext` keeps the next section (a final check that every worker runs); both
# are kept in every run.
#
# Runs:
#   (no arguments)      every group, at most PT_JOBS (default and maximum 4) workers at once, output printed per group
#   --serial            the whole file in this process, as before
#   --group ID[,ID...]  only those groups, in this process
#   --only REGEX        only the sections whose name matches REGEX, in this process (LIVE_TEST_SECTIONS does the same)
#   --list              print the group ids and weights
#   --jobs N            workers (1..4)
# Each worker is the file itself with the unselected sections cut out (awk), run by bash; the workers do not share state
# (own sandbox root, own fake API). The orchestrator records the pid of every worker it starts, kills only those on
# EXIT/INT/TERM, and holds no lock file descriptor, so nothing it starts inherits one.

PT_SELF=""; PT_TMP=""; PT_PIDS=(); PT_FINAL_FMT='%s passed, %s failed'

pt_mine() {  # INDEX: 0 when INDEX belongs to this shard (PT_SHARD=k/n); always 0 outside a sharded run. pt_mine 0 = shard 0.
  [ -n "${PT_SHARD:-}" ] || return 0
  [ $(( $1 % ${PT_SHARD#*/} )) -eq "${PT_SHARD%/*}" ]
}

pt_make_copy() {  # OUT ; env PT_SEL_GROUPS (comma list) | PT_SEL_RE (section-name regex)
  awk '
    BEGIN { keep = 1; ng = split(ENVIRON["PT_SEL_GROUPS"], a, ","); for (i = 1; i <= ng; i++) want[a[i]] = 1; re = ENVIRON["PT_SEL_RE"]; g = "" }
    /^#@group / { g = $2; if (ng) keep = (g in want); next_is_group = 1 }
    /^echo "== / {
      n = $0; sub(/^echo "== /, "", n); sub(/ ==".*$/, "", n)
      if (ng) keep = (g in want); else keep = (n ~ re)
      if (kn) { keep = 1; kn = 0 }
    }
    /^#@keepnext/ { kn = 1 }
    /^#@always/ { prev = keep; keep = 1 }
    /^#@end/ { keep = prev; next }
    /^#@tally/ { keep = 1 }
    keep { print }' "$PT_SELF" >"$1"
}

pt_group_table() {  # prints "id weight shards" for every group of the file
  awk '/^#@group /{ w = 1; s = 1; for (i = 3; i <= NF; i++) { if ($i ~ /^shards=/) { s = substr($i, 8) } else if ($i ~ /^[0-9]+$/) { w = $i } } print $2, w, s }' "$PT_SELF"
}

pt_kill_workers() {
  local p
  for p in ${PT_PIDS[@]+"${PT_PIDS[@]}"}; do kill "$p" 2>/dev/null; done
  for p in ${PT_PIDS[@]+"${PT_PIDS[@]}"}; do wait "$p" 2>/dev/null; done
  PT_PIDS=()
}
pt_cleanup() { pt_kill_workers; [ -z "$PT_TMP" ] || rm -rf "$PT_TMP"; }

pt_run_copy() {  # COPY: run one filtered copy as the only child, forwarding TERM/INT, return its status
  local c=0
  PT_SEL_RE="${PT_SEL_RE:-}" PT_WORKER=1 PT_ORIG="$PT_SELF" PT_SCRIPT_DIR="$PT_DIR" bash "$1" & PT_PIDS+=($!)
  trap 'pt_kill_workers; rm -rf "$PT_TMP"; exit 143' INT TERM
  wait "${PT_PIDS[0]}"; c=$?
  trap - INT TERM
  PT_PIDS=()
  return "$c"
}

pt_dispatch() {
  [ -z "${PT_WORKER:-}" ] || { PT_SELF="${PT_ORIG:-}"; return 0; }
  PT_SELF="${BASH_SOURCE[1]}"; PT_DIR="$(cd "$(dirname "$PT_SELF")" && pwd)"
  local mode="all" sel="" jobs="${PT_JOBS:-4}"
  [ -z "${LIVE_TEST_SECTIONS:-}" ] || { mode="only"; sel="$LIVE_TEST_SECTIONS"; }
  while [ $# -gt 0 ]; do
    case "$1" in
      --serial) mode="serial" ;;
      --group) mode="group"; sel="$2"; shift ;;
      --only) mode="only"; sel="$2"; shift ;;
      --list) pt_group_table; exit 0 ;;
      --jobs) jobs="$2"; shift ;;
      *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
  done
  case "$jobs" in ''|*[!0-9]*) jobs=4 ;; esac
  [ "$jobs" -ge 1 ] || jobs=1; [ "$jobs" -le 4 ] || jobs=4   # CPU rule: never more than 4 workers
  [ "$mode" != serial ] || return 0
  PT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pt-run.XXXXXX") || exit 1
  trap pt_cleanup EXIT
  if [ "$mode" = group ] || [ "$mode" = only ]; then
    if [ "$mode" = group ]; then PT_SEL_GROUPS="$sel" pt_make_copy "$PT_TMP/w.sh"; else PT_SEL_GROUPS="" PT_SEL_RE="$sel" pt_make_copy "$PT_TMP/w.sh"; fi
    grep -q '^echo "== ' "$PT_TMP/w.sh" || { echo "no section selected by '$sel'" >&2; exit 1; }
    pt_run_copy "$PT_TMP/w.sh"; local rc=$?
    exit "$rc"
  fi
  # all groups, in parallel
  local ids=() ws=() ss=() id w s k j order
  while read -r id w s; do ids+=("$id"); ws+=("$w"); ss+=("$s"); done < <(pt_group_table)
  [ "${#ids[@]}" -gt 0 ] || return 0   # no groups declared: run the file as it is
  local jobs_list=()   # "weight id shard"
  for j in "${!ids[@]}"; do
    for ((k = 0; k < ss[j]; k++)); do jobs_list+=("$(( ws[j] * 1000 / ss[j] )) ${ids[j]} $k/${ss[j]}"); done
  done
  order=()
  while IFS= read -r j; do order+=("$j"); done < <(printf '%s\n' "${jobs_list[@]}" | sort -rn -k1,1 -s)
  local running=() rid=() n=0 t0=$SECONDS next=0 done_n=0 total=${#order[@]} i p
  local outs=() rcs=()
  local -A jstart
  while [ "$done_n" -lt "$total" ]; do
    while [ "${#running[@]}" -lt "$jobs" ] && [ "$next" -lt "$total" ]; do
      set -- ${order[next]}; local gid="$2" sh="$3" f="$PT_TMP/job.$next"
      PT_SEL_GROUPS="$gid" pt_make_copy "$f.sh"
      ( PT_SHARD="$sh" PT_WORKER=1 PT_ORIG="$PT_SELF" PT_SCRIPT_DIR="$PT_DIR" exec bash "$f.sh" ) >"$f.out" 2>&1 &
      p=$!; PT_PIDS+=("$p"); running+=("$next:$p"); jstart[$next]=$SECONDS
      next=$((next + 1))
    done
    local still=()
    for i in "${running[@]}"; do
      n=${i%%:*}; p=${i#*:}
      if kill -0 "$p" 2>/dev/null; then still+=("$i"); else
        wait "$p"; rcs[n]=$?; done_n=$((done_n + 1))
        set -- ${order[n]}
        printf '[%3ss] done  %s (shard %s) exit %s\n' "$((SECONDS - t0))" "$2" "$3" "${rcs[n]}" >&2
      fi
    done
    running=("${still[@]+"${still[@]}"}")
    [ "$done_n" -ge "$total" ] || sleep 0.1
  done
  PT_PIDS=()
  # report in file order, then the tally
  local pass=0 fail=0 bad=0 a b line
  for j in "${!ids[@]}"; do
    for ((k = 0; k < ss[j]; k++)); do
      for n in "${!order[@]}"; do
        set -- ${order[n]}
        [ "$2" = "${ids[j]}" ] && [ "$3" = "$k/${ss[j]}" ] || continue
        a=0; b=0
        echo "── ${ids[j]} (shard $k/${ss[j]}) ──"
        cat "$PT_TMP/job.$n.out"
        line=$(grep -E '^[0-9]+ passed, [0-9]+ failed$|^Passed: [0-9]+  Failed: [0-9]+$' "$PT_TMP/job.$n.out" | tail -1)
        a=$(printf '%s' "$line" | sed -E 's/^[A-Za-z: ]*([0-9]+)[A-Za-z: ,]*([0-9]+)[A-Za-z: ]*$/\1/'); b=$(printf '%s' "$line" | sed -E 's/^[A-Za-z: ]*([0-9]+)[A-Za-z: ,]*([0-9]+)[A-Za-z: ]*$/\2/')
        if [ -z "$line" ]; then bad=$((bad + 1)); echo "  FAIL: group ${ids[j]} shard $k/${ss[j]} did not finish (exit ${rcs[n]})"; else pass=$((pass + a)); fail=$((fail + b)); fi
        [ "${rcs[n]}" -eq 0 ] || [ "${b:-0}" -gt 0 ] || bad=$((bad + 1))
      done
    done
  done
  echo
  printf "$PT_FINAL_FMT\n" "$pass" "$((fail + bad))"
  echo "wall time $((SECONDS - t0))s with $jobs workers" >&2
  [ "$fail" -eq 0 ] && [ "$bad" -eq 0 ]
  exit $?
}
