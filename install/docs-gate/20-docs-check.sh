#!/bin/bash
# ALY-46.2: the git docs starter templates (BR-03, AC-11, D-91) and the Node docs-check
# script (AC-16, D-97). Every rule has a failing fixture under fixtures/, asserted on the
# exact output (full equality) and exit 1; a clean fixture exits 0, a usage error exits 2,
# and the templates, laid out as a repo, pass docs-check. Runnable alone; exits 0 or 1.
set -euo pipefail
# shellcheck source=install/docs-gate/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CHECK="$ROOT/install/docs-check.mjs"
FIX="$ROOT/install/docs-gate/fixtures"
TPL="templates/git-docs"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A hung docs-check (e.g. a slug loop) fails the check instead of blocking the gate.
NODE=(node)
if command -v timeout >/dev/null 2>&1; then NODE=(timeout 30 node); fi

# expect <label> <exit> <expected stdout> <args...>: docs-check exits with <exit> and its
# stdout equals <expected stdout> exactly.
expect() {
  local label="$1" want_code="$2" want_out="$3" out code=0
  shift 3
  out=$("${NODE[@]}" "$CHECK" "$@" 2>/dev/null) || code=$?
  [ "$code" -eq "$want_code" ] || fail "$label: expected exit $want_code, got $code"
  [ "$out" = "$want_out" ] || fail "$label: unexpected output:
--- expected
$want_out
--- got
$out"
}

[ -f "$CHECK" ] || { fail "missing $CHECK"; finish; }

# Clean fixture: duplicate and taken slugs, punctuation, same-file and cross-file anchors,
# ?query, `..name` root files, <angle targets>, skipped URLs, quoted headings, fenced
# (backtick, tilde, indented, nested, quoted) and inline-code links ignored.
expect clean 0 "docs-check: ok (3 files)" --root "$FIX/clean"

LINK_OUT="docs-check: README.md:3: link: missing target missing.md
docs-check: README.md:4: link: missing target docs/missing.md#x
docs-check: README.md:5: link: missing target img/missing.png
docs-check: README.md:6: link: target outside root ../outside.md
docs-check: README.md:8: link: missing target missing file.md
docs-check: README.md:9: link: missing target gone.md?plain=1
docs-check: README.md:10: link: missing target gone(1).md"
expect link 1 "$LINK_OUT" --root "$FIX/link"

expect anchor 1 "docs-check: README.md:3: anchor: no heading for #missing-section in README.md
docs-check: README.md:4: anchor: no heading for #nope in docs/page.md
docs-check: README.md:5: anchor: no heading for #not-a-heading in README.md
docs-check: README.md:6: anchor: no heading for #usage-1 in README.md" --root "$FIX/anchor"

expect fence-backtick 1 'docs-check: README.md:7: fence: unclosed ```` fence' --root "$FIX/fence-backtick"
expect fence-tilde 1 'docs-check: README.md:3: fence: unclosed ~~~ fence' --root "$FIX/fence-tilde"
expect fence-indented 1 'docs-check: README.md:11: fence: unclosed ~~~ fence' --root "$FIX/fence-indented"

# A 4-space indented ``` after a blank line outside a list is code, never a fence opener:
# only the later link is reported (no fence finding).
expect indented-code 1 'docs-check: README.md:8: link: missing target missing.md' --root "$FIX/indented-code"

expect lines-readme 1 'docs-check: README.md:151: lines: 151 lines, limit 150' --root "$FIX/lines-readme"
expect lines-agents 1 'docs-check: AGENTS.md:101: lines: 101 lines, limit 100' --root "$FIX/lines-agents"
expect lines-architecture 1 'docs-check: docs/ARCHITECTURE.md:301: lines: 301 lines, limit 300' --root "$FIX/lines-architecture"

# Files mode: only the named files are checked (paths relative to --root).
expect files-mode 1 "$LINK_OUT" --root "$FIX/link" README.md
expect files-mode-clean 0 "docs-check: ok (1 files)" --root "$FIX/clean" docs/guide.md

# Boundaries: exactly at the limit passes.
mkdir -p "$TMP/limit/docs"
{ for i in $(seq 1 150); do echo "line $i"; done; } > "$TMP/limit/README.md"
{ for i in $(seq 1 100); do echo "line $i"; done; } > "$TMP/limit/AGENTS.md"
{ for i in $(seq 1 300); do echo "line $i"; done; } > "$TMP/limit/docs/ARCHITECTURE.md"
expect at-limit 0 "docs-check: ok (3 files)" --root "$TMP/limit"

# Usage errors exit 2.
expect usage-unknown-option 2 "" --nope
expect usage-root-missing-value 2 "" --root
expect usage-root-not-dir 2 "" --root "$TMP/does-not-exist"
expect usage-file-missing 2 "" --root "$FIX/clean" nope.md
expect usage-file-is-dir 2 "" --root "$FIX/clean" docs
expect usage-file-outside 2 "" --root "$FIX/clean" ../link/README.md
expect usage-double-dash 2 "" --root "$FIX/clean" --
expect usage-help 2 "" --help

# Symlinks are resolved before existence is reported (no existence oracle): an escaping or
# dangling symlink, or a symlinked directory pointing outside, is always "outside root";
# a symlink inside the root with a missing tail is "missing target".
mkdir -p "$TMP/sym/root/docs" "$TMP/sym/outsidedir"
printf '# Outside\n' > "$TMP/sym/outside.md"
printf '# Page\n' > "$TMP/sym/root/docs/page.md"
ln -s ../outside.md "$TMP/sym/root/out.md"
ln -s ../nowhere.md "$TMP/sym/root/dangling.md"
ln -s ../outsidedir "$TMP/sym/root/outdir"
ln -s docs "$TMP/sym/root/inlink"
printf '# Sym\n\n[o](out.md)\n[d](dangling.md)\n[x](outdir/nofile.md)\n[m](inlink/missing.md)\n[ok](inlink/page.md#page)\n' > "$TMP/sym/root/README.md"
expect symlink-link 1 'docs-check: README.md:3: link: target outside root out.md
docs-check: README.md:4: link: target outside root dangling.md
docs-check: README.md:5: link: target outside root outdir/nofile.md
docs-check: README.md:6: link: missing target inlink/missing.md' --root "$TMP/sym/root"
expect symlink-file 2 "" --root "$TMP/sym/root" out.md

# Slug sets are computed once per file: 3000 headings and 3000 anchor links finish within
# the timeout guard.
mkdir -p "$TMP/big/docs"
for i in $(seq 1 3000); do echo "## H $i"; done > "$TMP/big/docs/b.md"
for i in $(seq 1 3000); do echo "[l](b.md#h-$i)"; done > "$TMP/big/docs/a.md"
expect many-anchors 0 "docs-check: ok (2 files)" --root "$TMP/big"

# Lines longer than 10000 characters are reported and not parsed; adversarial lines just
# under the cap finish within the timeout guard.
mkdir -p "$TMP/long"
{
  echo '# Long'
  printf '](%.0s' $(seq 1 4900); echo
  printf '[a](b "%.0s' $(seq 1 1400); echo
  printf '](<%.0s' $(seq 1 3300); echo
  printf '#%.0s' $(seq 1 6); printf ' %.0s' $(seq 1 9000); echo x
} > "$TMP/long/README.md"
expect long-lines-under-cap 0 "docs-check: ok (1 files)" --root "$TMP/long"
printf 'x%.0s' $(seq 1 10001) >> "$TMP/long/README.md"; echo >> "$TMP/long/README.md"
expect long-line 1 'docs-check: README.md:6: lines: line longer than 10000 characters' --root "$TMP/long"

# The `<a ...>` anchor scan is linear: 3000 lines of `x>` followed by 3300 unclosed `<a `
# openers finish well within the timeout guard (a quadratic scan takes over 30 s and the
# guard's exit 124 fails the check); a valid anchor on a later line still counts.
mkdir -p "$TMP/openers/docs"
{
  echo '# Openers'
  line="x>$(printf '<a %.0s' $(seq 1 3300))"
  awk -v l="$line" 'BEGIN { for (i = 0; i < 3000; i++) print l }'
  echo "<a name=\"dq\"></a> <A id='sq'></a>"
  echo '[d](#dq) [s](#sq)'
} > "$TMP/openers/docs/openers.md"
expect many-openers 0 "docs-check: ok (1 files)" --root "$TMP/openers"

# File system errors exit 2 with `docs-check: error: <message>` on stderr.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$TMP/eacces/docs"
  printf '# Locked\n' > "$TMP/eacces/docs/locked.md"
  chmod 000 "$TMP/eacces/docs/locked.md"
  code=0
  err=$("${NODE[@]}" "$CHECK" --root "$TMP/eacces" 2>&1 >/dev/null) || code=$?
  chmod 600 "$TMP/eacces/docs/locked.md"
  [ "$code" -eq 2 ] || fail "fs-error: expected exit 2, got $code"
  case "$err" in "docs-check: error: EACCES: "*) ;; *) fail "fs-error: unexpected stderr: $err";; esac
fi

# Templates laid out as a target repo pass docs-check (AC-11).
for f in README.md AGENTS.md CLAUDE.md ARCHITECTURE.md; do
  [ -f "$ROOT/$TPL/$f" ] || fail "missing $TPL/$f"
done
mkdir -p "$TMP/repo/docs"
cp "$ROOT/$TPL/README.md" "$ROOT/$TPL/AGENTS.md" "$ROOT/$TPL/CLAUDE.md" "$TMP/repo/" 2>/dev/null || true
cp "$ROOT/$TPL/ARCHITECTURE.md" "$TMP/repo/docs/ARCHITECTURE.md" 2>/dev/null || true
expect templates 0 "docs-check: ok (4 files)" --root "$TMP/repo"

# The plugin's own docs pass docs-check (README within 150 lines, links and anchors).
expect plugin-repo 0 "docs-check: ok ($(cd "$ROOT" && { ls README.md AGENTS.md CLAUDE.md 2>/dev/null; find docs -type f -name '*.md'; } | wc -l | tr -d ' ') files)" --root "$ROOT"

# CLAUDE.md imports AGENTS.md on its first line (D-91).
[ "$(head -n 1 "$ROOT/$TPL/CLAUDE.md" 2>/dev/null)" = "@AGENTS.md" ] || fail "$TPL/CLAUDE.md: first line must be exactly @AGENTS.md"

# Allye links are slug-free page URLs (/kb/<space-key>/<short_id>, space-key = project key
# or _company), at least one per README and AGENTS; any other allye.app URL fails.
KB_URL='https://allye.app/hq/kb/{{space-key}}/{{short_id}}'
for f in README.md AGENTS.md ARCHITECTURE.md; do
  [ -f "$ROOT/$TPL/$f" ] || continue
  while IFS= read -r url; do
    [ "$url" = "$KB_URL" ] || fail "$TPL/$f: Allye URL must be $KB_URL (found $url)"
  done < <(grep -oE 'https?://[^ )]*allye\.app[^ )]*' "$ROOT/$TPL/$f" || true)
done
for f in README.md AGENTS.md; do
  grep -Fq "($KB_URL)" "$ROOT/$TPL/$f" 2>/dev/null || fail "$TPL/$f: must link to an Allye page with $KB_URL"
done

# Deny-list (same as 10-spec-template): no template weakens the docs rules.
for f in README.md AGENTS.md CLAUDE.md ARCHITECTURE.md; do
  [ -f "$ROOT/$TPL/$f" ] || continue
  deny "$TPL/$f" 'docs impact[^.]*(optional|may be omitted|can be omitted|may be skipped)'
  deny "$TPL/$f" 'personal[^.]*without (asking|confirmation|the user)'
  deny "$TPL/$f" 'personal[^.]*(always|freely) (search|read|cop)'
  deny "$TPL/$f" 'adr: yes[^.]*optional'
  # Placeholders are visible {{...}}, never raw tags GitHub hides; no personal-space links.
  deny "$TPL/$f" '<[a-z/!]'
  deny "$TPL/$f" '~me|/kb/~'
done

finish
