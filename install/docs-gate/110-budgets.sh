#!/bin/bash
# ALY-46.11: NFR-02 / AC-15 skill budgets. Every crew skills/bridge*/SKILL.md that exists
# at the base grows by at most 40 lines, skills/bridge-navigator/SKILL.md stays within
# 150 lines, skills/ holds only bridge and bridge-* (non-bridge skills untouched), and the
# legacy `docs` tool name (mcp__plugin_allye_allye__docs) is neither introduced nor
# removed. Never fetches and never touches the network.
#
# One measure in both modes: net growth, current lines - base lines.
# Base resolution, in order:
#   1. BASE_REF (env, non-empty): git mode against that ref (net = added - deleted of
#      `git diff --numstat <base>`, working tree vs base).
#   2. git merge-base HEAD origin/main, when origin/main exists locally and the merge-base
#      is not HEAD itself: git mode against it.
#   3. Otherwise (shallow CI checkout, tarball, no origin/main, or HEAD already on main as
#      on a push to main, where a git diff would pass vacuously): table mode against the
#      pinned BASELINE below.
#
# Updating BASELINE: the table holds the SKILL.md line counts at 572b404 (origin/main when
# ALY-46 started). After this change merges, set each entry to the merged line counts
# (`git show <merged main sha>:skills/<dir>/SKILL.md | wc -l`) and BASELINE_SHA to that
# sha in the release commit: otherwise later PRs checked in table mode would measure
# against 572b404 and spend this change's growth again. Do the same when a larger budget
# is approved on purpose, saying why in the commit body.
#
# The self-tests at the end run in temp dirs (never the worktree): table mode in a git
# repo without origin/main and with origin/main at HEAD, +40 passing and +41 net failing
# in both modes, +41/-41 passing in both, and a 151-line Navigator.
# Runnable alone; exits 0 or 1.
set -euo pipefail
# shellcheck source=install/docs-gate/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASELINE_SHA=572b404
BASELINE="bridge 110
bridge-architect 97
bridge-armorer 112
bridge-copilot 79
bridge-dispatcher 97
bridge-medic 82
bridge-optimizer 68
bridge-pilot 70
bridge-recon 84
bridge-shield 75
bridge-strategist 93
bridge-watcher 74"
LEGACY_DOCS_TOOL="mcp__plugin_allye_allye__docs"
LEGACY_DOCS_BASELINE=0
MAX_GROWTH=40
NAVIGATOR_MAX=150

# legacy_count <dir>: occurrences of the legacy docs tool name under <dir>/skills.
legacy_count() { { grep -rFo -- "$LEGACY_DOCS_TOOL" "$1/skills" || true; } | wc -l | tr -d ' '; }

# budgets <root>: checks <root>/skills; prints "budgets: mode ..." and one line per
# violation ("budgets: FAIL ..."); returns 1 on any violation.
budgets() {
  local root="$1" mode base="" bad=0 dir name n growth cur head
  if [ -n "${BASE_REF:-}" ]; then
    mode=git
    base=$(git -C "$root" rev-parse --verify --quiet "$BASE_REF^{commit}") || {
      echo "budgets: FAIL BASE_REF $BASE_REF is not a commit in $root"
      return 1
    }
  elif git -C "$root" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1 &&
    base=$(git -C "$root" merge-base HEAD origin/main 2>/dev/null) &&
    head=$(git -C "$root" rev-parse HEAD) && [ "$base" != "$head" ]; then
    mode=git
  else
    mode=table
  fi
  if [ "$mode" = git ]; then
    echo "budgets: mode git (base $base)"
  else
    echo "budgets: mode table (baseline $BASELINE_SHA)"
  fi

  for dir in "$root"/skills/*/; do
    name=$(basename "$dir")
    case "$name" in
      bridge | bridge-*) ;;
      *) echo "budgets: FAIL non-bridge skill skills/$name"; bad=1 ;;
    esac
  done

  if [ "$mode" = git ]; then
    while IFS= read -r name; do
      case "$name" in
        skills/bridge/* | skills/bridge-*/*) ;;
        *) echo "budgets: FAIL non-bridge skill changed: $name"; bad=1 ;;
      esac
    done < <(git -C "$root" diff --name-only "$base" -- skills/)
    while IFS= read -r name; do
      [ "$name" = bridge-navigator ] && continue
      git -C "$root" cat-file -e "$base:skills/$name/SKILL.md" 2>/dev/null || continue
      [ -f "$root/skills/$name/SKILL.md" ] || continue
      growth=$(git -C "$root" diff --numstat "$base" -- "skills/$name/SKILL.md" | awk '{print $1 - $2}')
      growth=${growth:-0}
      [ "$growth" -le "$MAX_GROWTH" ] ||
        { echo "budgets: FAIL skills/$name/SKILL.md grew by $growth lines (max $MAX_GROWTH)"; bad=1; }
    done < <(cd "$root/skills" && ls -d bridge bridge-* 2>/dev/null)
    n=$(git -C "$root" grep -Fo -- "$LEGACY_DOCS_TOOL" "$base" -- skills | wc -l | tr -d ' ')
  else
    while read -r name n; do
      [ -f "$root/skills/$name/SKILL.md" ] || continue
      cur=$(wc -l <"$root/skills/$name/SKILL.md" | tr -d ' ')
      growth=$((cur - n))
      [ "$growth" -le "$MAX_GROWTH" ] ||
        { echo "budgets: FAIL skills/$name/SKILL.md grew by $growth lines (max $MAX_GROWTH)"; bad=1; }
    done <<<"$BASELINE"
    n=$LEGACY_DOCS_BASELINE
  fi

  if [ -f "$root/skills/bridge-navigator/SKILL.md" ]; then
    cur=$(wc -l <"$root/skills/bridge-navigator/SKILL.md" | tr -d ' ')
    [ "$cur" -le "$NAVIGATOR_MAX" ] ||
      { echo "budgets: FAIL skills/bridge-navigator/SKILL.md has $cur lines (max $NAVIGATOR_MAX)"; bad=1; }
  fi

  cur=$(legacy_count "$root")
  [ "$cur" -eq "$n" ] ||
    { echo "budgets: FAIL legacy $LEGACY_DOCS_TOOL mentions changed ($n at base, $cur now)"; bad=1; }
  return "$bad"
}

# 1. The real tree.
out=$(budgets "$ROOT") || fail "budgets failed on the tree:
$out"
echo "$out" | head -1

# 2. Self-tests in temp dirs.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
G=(git -c user.name=docs-gate -c user.email=docs-gate@invalid -c commit.gpgsign=false -c init.defaultBranch=main)

# grow <file> <n>: append n lines.
grow() { local i; for ((i = 0; i < $2; i++)); do echo "extra $i" >>"$1"; done; }

# drop_head <file> <n>: remove the first n lines (temp-file rewrite, no GNU-only sed -i).
drop_head() { tail -n +"$(($2 + 1))" "$1" >"$1.tmp" && mv "$1.tmp" "$1"; }

# expect_run <label> <want rc> <want mode line> <want fail line or ""> <root>
expect_run() {
  local label="$1" want_rc="$2" want_mode="$3" want_fail="$4" root="$5" got rc=0
  got=$(budgets "$root") || rc=$?
  [ "$rc" -eq "$want_rc" ] || fail "$label: expected exit $want_rc, got $rc: $got"
  [ "$(echo "$got" | head -1)" = "$want_mode" ] || fail "$label: expected mode line: $want_mode, got: $got"
  if [ -n "$want_fail" ]; then
    grep -Fxq -- "$want_fail" <<<"$got" || fail "$label: missing line: $want_fail; got: $got"
  fi
}
TABLE="budgets: mode table (baseline $BASELINE_SHA)"

# Table-mode tree: the baseline counts, as a shallow checkout without origin/main.
mk_table_repo() {
  rm -rf "$1" && mkdir -p "$1"
  cp -R "$ROOT/skills" "$1/skills"
  (cd "$1" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm shallow)
}

# a. Fallback path: no origin/main → table mode, passes on the current tree.
mk_table_repo "$TMP/shallow"
expect_run "fallback" 0 "$TABLE" "" "$TMP/shallow"
unset_ok=$(BASE_REF='' budgets "$TMP/shallow" | head -1)
[ "$unset_ok" = "$TABLE" ] || fail "fallback: empty BASE_REF must mean unset, got: $unset_ok"
rm -rf "$TMP/plain" && mkdir -p "$TMP/plain" && cp -R "$ROOT/skills" "$TMP/plain/skills"
expect_run "plain dir" 0 "$TABLE" "" "$TMP/plain"

# b. Table mode: pilot at baseline+40 passes, +41 fails.
mk_table_repo "$TMP/t40"
head -n 70 "$ROOT/skills/bridge-pilot/SKILL.md" >"$TMP/t40/skills/bridge-pilot/SKILL.md"
grow "$TMP/t40/skills/bridge-pilot/SKILL.md" 40
expect_run "table +40" 0 "$TABLE" "" "$TMP/t40"
grow "$TMP/t40/skills/bridge-pilot/SKILL.md" 1
expect_run "table +41" 1 "$TABLE" "budgets: FAIL skills/bridge-pilot/SKILL.md grew by 41 lines (max 40)" "$TMP/t40"
# Net measure: +41/-41 passes.
mk_table_repo "$TMP/tnet"
drop_head "$TMP/tnet/skills/bridge-armorer/SKILL.md" 41
grow "$TMP/tnet/skills/bridge-armorer/SKILL.md" 41
expect_run "table +41 -41" 0 "$TABLE" "" "$TMP/tnet"

# c. Navigator: 150 passes, 151 fails.
mk_table_repo "$TMP/nav"
: >"$TMP/nav/skills/bridge-navigator/SKILL.md"
grow "$TMP/nav/skills/bridge-navigator/SKILL.md" 150
expect_run "navigator 150" 0 "$TABLE" "" "$TMP/nav"
grow "$TMP/nav/skills/bridge-navigator/SKILL.md" 1
expect_run "navigator 151" 1 "$TABLE" "budgets: FAIL skills/bridge-navigator/SKILL.md has 151 lines (max 150)" "$TMP/nav"

# d. Non-bridge skill dir and a legacy docs tool rename fail.
mk_table_repo "$TMP/other"
mkdir -p "$TMP/other/skills/other" && echo x >"$TMP/other/skills/other/SKILL.md"
expect_run "non-bridge dir" 1 "$TABLE" "budgets: FAIL non-bridge skill skills/other" "$TMP/other"
mk_table_repo "$TMP/legacy"
echo "$LEGACY_DOCS_TOOL" >>"$TMP/legacy/skills/bridge-recon/SKILL.md"
expect_run "legacy docs tool" 1 "$TABLE" "budgets: FAIL legacy $LEGACY_DOCS_TOOL mentions changed (0 at base, 1 now)" "$TMP/legacy"

# e. origin/main at HEAD (a push to main) → table mode, never a vacuous git diff.
mk_table_repo "$TMP/git"
base=$(git -C "$TMP/git" rev-parse HEAD)
git -C "$TMP/git" update-ref refs/remotes/origin/main "$base"
expect_run "origin/main at HEAD" 0 "$TABLE" "" "$TMP/git"
head -n 75 "$ROOT/skills/bridge-shield/SKILL.md" >"$TMP/git/skills/bridge-shield/SKILL.md"
grow "$TMP/git/skills/bridge-shield/SKILL.md" 41
expect_run "origin/main at HEAD +41" 1 "$TABLE" "budgets: FAIL skills/bridge-shield/SKILL.md grew by 41 lines (max 40)" "$TMP/git"
git -C "$TMP/git" checkout -q -- skills

# f. Git mode (HEAD past origin/main): +40 passes, +41 net fails, +41/-41 passes,
# BASE_REF wins.
echo x >"$TMP/git/skills/bridge-recon/notes.md"
git -C "$TMP/git" add -A && "${G[@]}" -C "$TMP/git" commit -qm next
GITM="budgets: mode git (base $base)"
expect_run "git clean" 0 "$GITM" "" "$TMP/git"
grow "$TMP/git/skills/bridge-shield/SKILL.md" 40
expect_run "git +40" 0 "$GITM" "" "$TMP/git"
grow "$TMP/git/skills/bridge-shield/SKILL.md" 1
expect_run "git +41" 1 "$GITM" "budgets: FAIL skills/bridge-shield/SKILL.md grew by 41 lines (max 40)" "$TMP/git"
git -C "$TMP/git" checkout -q -- skills
drop_head "$TMP/git/skills/bridge-armorer/SKILL.md" 41
grow "$TMP/git/skills/bridge-armorer/SKILL.md" 41
expect_run "git +41 -41" 0 "$GITM" "" "$TMP/git"
git -C "$TMP/git" checkout -q -- skills
mkdir -p "$TMP/git/skills/zz" && echo x >"$TMP/git/skills/zz/SKILL.md" && git -C "$TMP/git" add -A
expect_run "git non-bridge" 1 "$GITM" "budgets: FAIL non-bridge skill changed: skills/zz/SKILL.md" "$TMP/git"
rm -rf "$TMP/git/skills/zz" && git -C "$TMP/git" add -A
git -C "$TMP/git" update-ref -d refs/remotes/origin/main
grow "$TMP/git/skills/bridge-pilot/SKILL.md" 41
out=$(BASE_REF="$base" budgets "$TMP/git") && fail "BASE_REF +41: expected failure, got: $out"
[ "$(echo "$out" | head -1)" = "$GITM" ] || fail "BASE_REF: expected git mode, got: $out"
out=$(BASE_REF=nope budgets "$TMP/git") && fail "BASE_REF invalid: expected failure"
grep -Fxq "budgets: FAIL BASE_REF nope is not a commit in $TMP/git" <<<"$out" || fail "BASE_REF invalid: got: $out"

finish
