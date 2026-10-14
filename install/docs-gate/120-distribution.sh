#!/bin/bash
# ALY-46.11: distribution of the git docs templates and the docs-check script.
# Present path: the allye-pi tarball (root package.json `files`) ships
# templates/git-docs/*.md and install/docs-check.mjs, so `<plugin>` (two levels above
# skills/bridge) holds them on Pi/OMP; the allye-opencode prepare.ts copies both into the
# package and its `files` publishes them; the Codex install guide copies them next to
# ~/.codex/skills. Absent path: the skills keep the fail-closed `unresolved` lines, and
# docs-check run from a plugin copy without templates still exits 0/1/2.
# Offline (npm pack --dry-run --offline, no fetch). Runnable alone; exits 0 or 1.
set -euo pipefail
# shellcheck source=install/docs-gate/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Present path -------------------------------------------------------------------

# 1. allye-pi tarball (root): every template and the script are packed.
if packed=$(cd "$ROOT" && npm pack --dry-run --json --offline --ignore-scripts 2>/dev/null); then
  files=$(node -e 'const p=JSON.parse(require("fs").readFileSync(0,"utf8"));for(const f of p[0].files)console.log(f.path)' <<<"$packed")
  want=(install/docs-check.mjs)
  for t in "$ROOT"/templates/git-docs/*.md; do want+=("templates/git-docs/$(basename "$t")"); done
  [ "${#want[@]}" -ge 5 ] || fail "templates/git-docs: expected 4 templates, found $((${#want[@]} - 1))"
  for f in "${want[@]}"; do
    grep -Fxq -- "$f" <<<"$files" || fail "allye-pi tarball: missing $f"
  done
else
  fail "npm pack --dry-run failed in $ROOT"
fi

# 2. allye-opencode: prepare.ts copies both into the package (static read: it runs on
# bun, which may be absent), package.json `files` publishes them, and the copies are
# gitignored.
PREP=packages/allye-opencode/scripts/prepare.ts
has_line "$PREP" 'cpSync(join(root, "templates", "git-docs"), join(pkg, "templates", "git-docs"), { recursive: true })'
has_line "$PREP" 'cpSync(join(root, "install", "docs-check.mjs"), join(pkg, "install", "docs-check.mjs"))'
has_line "$PREP" 'for (const dir of ["templates", "install"]) rmSync(join(pkg, dir), { recursive: true, force: true })'
pkgfiles=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).files.join("\n"))' "$ROOT/packages/allye-opencode/package.json")
for f in templates install; do
  grep -Fxq "$f" <<<"$pkgfiles" || fail "packages/allye-opencode/package.json: files lacks $f"
done
has_line packages/allye-opencode/.gitignore 'templates/'
has_line packages/allye-opencode/.gitignore 'install/'

# 3. Codex install guide: copies both to <plugin> = ~/.codex (two levels above
# ~/.codex/skills/bridge), only over Allye's own copies, and says what happens without
# them. ALY-85: one pinned tag archive, preflight (checks and backups) before any replace,
# no branch source. The guide's blocks are extracted and run against a temp HOME with a
# fake curl serving a fixture archive.
DOC=docs/install-codex.md
has_line "$DOC" '# never place user text in the script unless it already matched ^v?[0-9]+\.[0-9]+\.[0-9]+$; write only the matched digits and dots (never the original text, never a value containing a quote)'
has_line "$DOC" "RAW=''   # set to the version only if you checked the user's text as a whole against ^v?[0-9]+\\.[0-9]+\\.[0-9]+\$ (digits, dots, optional leading v); otherwise leave empty"
has_line "$DOC" '[ -n "$RAW" ] || RAW=$(curl --proto '"'"'=https'"'"' --proto-redir '"'"'=https'"'"' --tlsv1.2 -fsSL https://api.github.com/repos/allye-app/allye-plugin/releases/latest | jq -r '"'"'.tag_name // empty'"'"')'
has_line "$DOC" 'RAW="${RAW#v}"'
has_line "$DOC" 'if ! [[ "$RAW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "No valid release version: $RAW" >&2; return 1 2>/dev/null || exit 1; fi'
has_line "$DOC" 'VERSION="$RAW"'
has_line "$DOC" 'echo "Installing Allye $VERSION"'
count_line "$DOC" ': "${VERSION:?run Step 0 first}"' 2
count_line "$DOC" '[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }' 2
has_line "$DOC" '  if ! curl --proto '"'"'=https'"'"' --proto-redir '"'"'=https'"'"' --tlsv1.2 -fsSL https://github.com/allye-app/allye-plugin/archive/refs/tags/v"$VERSION".tar.gz -o "$ALLYE_TMP/release.tar.gz"; then'
has_line "$DOC" '  if [ -n "$(find "$ALLYE_TMP" -type l -print -quit)" ]; then'
has_line "$DOC" '  case "$ALLYE_TMP" in "$td"/tmp.*) ;; *) echo "Unexpected temp dir; nothing changed." >&2; unset ALLYE_TMP; return 1 ;; esac'
has_line "$DOC" '  { ( umask 077; mkdir -p "$HOME/.allye/backups/codex" ) && chmod 700 "$HOME/.allye/backups/codex"; } || { echo "Backup directory failed; nothing changed." >&2; allye_clean; return 1; }'
has_line "$DOC" '  ( umask 077; cp -a "$1" "$b" ) || return 1'
has_line "$DOC" '      allye_backup "$dst" "$name" || { echo "Backup of $name failed; ~/.codex is unchanged (backups already made stay under ~/.allye/backups/codex)." >&2; allye_clean; return 1; }'
has_line "$DOC" '    allye_backup "$T" git-docs || { echo "Backup of git-docs failed; ~/.codex is unchanged (backups already made stay under ~/.allye/backups/codex)." >&2; allye_clean; return 1; }'
has_line "$DOC" '    allye_backup "$C" docs-check.mjs || { echo "Backup of docs-check.mjs failed; ~/.codex is unchanged (backups already made stay under ~/.allye/backups/codex)." >&2; allye_clean; return 1; }'
has_line "$DOC" '    ( umask 077; cp -p "$DEST" "$B" ) || allye_abort "Backup of AGENTS.md failed; AGENTS.md is unchanged." || return 1'
has_line "$DOC" '  if [ -L "$DEST" ]; then DEST=$(readlink -f "$DEST") || allye_abort "Cannot resolve the ~/.codex/AGENTS.md link; AGENTS.md is unchanged." || return 1; fi'
has_line "$DOC" '  if [ -L "$T" ] || { [ -e "$T" ] && { [ ! -f "$T/.allye-templates" ] || [ "$(head -n 1 "$T/CLAUDE.md" 2>/dev/null)" != "@AGENTS.md" ]; }; }; then'
has_line "$DOC" '    echo "Skipped $T: not Allye'"'"'s git docs templates. Ask the user before replacing it."'
has_line "$DOC" '    rm -rf "$T"'
has_line "$DOC" '    { cp -R "$SRC/templates/git-docs" "$HOME/.codex/templates/" && touch "$T/.allye-templates"; } || { echo "Copy of git-docs failed after the backups above; restore from them." >&2; allye_clean; return 1; }'
has_line "$DOC" '  if [ -L "$C" ] || { [ -e "$C" ] && ! grep -Fxq "// docs-check: deterministic checks for a repository'"'"'s git docs (no dependencies)." "$C"; }; then'
has_line "$DOC" '    echo "Skipped $C: not Allye'"'"'s docs-check script. Ask the user before replacing it."'
has_line "$DOC" '    cp "$SRC/install/docs-check.mjs" "$C" || { echo "Copy of docs-check.mjs failed after the backups above; restore from it." >&2; allye_clean; return 1; }'
has_line "$DOC" 'Replace an existing `~/.codex/skills/bridge*` skill, `~/.codex/templates/git-docs` and `~/.codex/install/docs-check.mjs` only when they are Allye'"'"'s copies; otherwise ask the user. The script below checks them (an Allye skill is a directory whose `SKILL.md` has the line `name: <directory name>`; Allye'"'"'s templates directory holds the `.allye-templates` marker this step writes and its `CLAUDE.md` starts with `@AGENTS.md`; Allye'"'"'s script carries the docs-check header line; a symbolic link is never Allye'"'"'s copy) and skips a foreign copy with a message.'
has_line "$DOC" 'Without `~/.codex/templates/git-docs` and `~/.codex/install/docs-check.mjs`, Bridge reports docs-check as `unresolved` and never improvises a substitute.'
deny "$DOC" 'refs/heads/|/main/|allye-plugin-main|/tmp/allye|raw\.githubusercontent'
has_line "$DOC" '  if grep -Eq '"'"'^/|(^|/)\.\.(/|$)'"'"' "$ALLYE_TMP/names" || grep -Eq '"'"'^[lh]'"'"' "$ALLYE_TMP/types"; then'
has_line "$DOC" '  if ! tar -xzf "$ALLYE_TMP/release.tar.gz" --no-same-owner -C "$ALLYE_TMP"; then'
has_line "$DOC" '  [ -d "$ALLYE_TMP" ] && [ ! -L "$ALLYE_TMP" ] && [ -O "$ALLYE_TMP" ] && [ -f "$ALLYE_TMP/.allye-tmp" ] || { echo "ALLYE_TMP is not the directory Step 2 made for you; AGENTS.md is unchanged." >&2; return 1; }'
has_line "$DOC" '  if [ -n "${ALLYE_TMP:-}" ]; then allye_clean; fi'
has_line "$DOC" '      NEWFILE="$NEW" awk '"'"'$0 == "<!-- allye:begin -->" { while ((getline l < ENVIRON["NEWFILE"]) > 0) print l; skip = 1; next } skip && $0 == "<!-- allye:end -->" { skip = 0; next } !skip { print }'"'"' "$DEST" >"$OUT" || allye_abort "Replacing the Allye section failed; AGENTS.md is unchanged." || return 1'
has_line "$DOC" '  : >"$ALLYE_TMP/.allye-tmp" || { echo "Cannot write in the temp dir; nothing changed." >&2; rm -rf "$ALLYE_TMP"; unset ALLYE_TMP; return 1; }'
has_line "$DOC" '    [[ "$name" =~ ^bridge[A-Za-z0-9_-]*$ ]] || { echo "Unexpected skill directory name in the archive; nothing changed." >&2; allye_clean; return 1; }'
has_line "$DOC" '    todo+=("$name")'
has_line "$DOC" '  for name in ${todo[@]+"${todo[@]}"}; do'
has_line "$DOC" '    if [ "$(grep -Fxc '"'"'<!-- allye:begin -->'"'"' "$OUT")" != 1 ] || [ "$(grep -Fxc '"'"'<!-- allye:end -->'"'"' "$OUT")" != 1 ]; then'
has_line "$DOC" '    cp -p "$DEST" "$OUT" || allye_abort "Cannot prepare the new AGENTS.md; AGENTS.md is unchanged." || return 1'
! grep -Fq 'for name in $todo' "$ROOT/$DOC" || fail "$DOC: the skill list must not be word-split"
grep -Eq -- "--proto-redir '=https'.*api.github.com" "$ROOT/$DOC" || fail "$DOC: api curl without --proto-redir"
! grep -Eq 'awk +-v' "$ROOT/$DOC" || fail "$DOC: awk values must go through ENVIRON, not -v"
grep -Fq 'case "${ALLYE_TMP:-}" in *..*|"$td"/tmp.*/*) ;;' "$ROOT/$DOC" || fail "$DOC: allye_clean must refuse a value with .."
# The rule comes before the block.
rule=$(grep -n '^Replace an existing `~/.codex/skills/bridge\*` skill' "$ROOT/$DOC" | cut -d: -f1)
block=$(grep -n '^allye_step2() {$' "$ROOT/$DOC" | cut -d: -f1)
[ -n "$rule" ] && [ -n "$block" ] && [ "$rule" -lt "$block" ] || fail "$DOC: the replace-only-Allye's-copies rule must precede the copy block"
[ "$(head -n 1 "$ROOT/templates/git-docs/CLAUDE.md")" = "@AGENTS.md" ] || fail "templates/git-docs/CLAUDE.md: first line is not @AGENTS.md (the Codex guide's ownership check)"
grep -Fxq "// docs-check: deterministic checks for a repository's git docs (no dependencies)." "$ROOT/install/docs-check.mjs" ||
  fail "install/docs-check.mjs: header line changed (the Codex guide's ownership check)"

# doc_block <heading prefix>: the first bash block under that heading of the guide.
doc_block() {
  awk -v h="$1" 'index($0, h) == 1 {on=1; next} on && /^```bash$/ {inb=1; next} inb && /^```$/ {exit} inb {print}' "$ROOT/$DOC"
}
doc_block '## Step 0:' >"$TMP/step0.tpl"
doc_block '## Step 2:' >"$TMP/step2.sh"
doc_block '## Step 3:' >"$TMP/step3.sh"
for f in step0.tpl step2.sh step3.sh; do [ -s "$TMP/$f" ] || fail "$DOC: bash block for $f not found"; done
cat "$TMP/step2.sh" "$TMP/step3.sh" >"$TMP/both.sh"

# Fakes: curl serves a fixture archive (or fails), date is fixed, cp can be made to fail.
BIN="$TMP/bin"; BIN2="$TMP/bin2"; mkdir -p "$BIN" "$BIN2"
cat >"$BIN/curl" <<'SH'
#!/bin/bash
echo "$*" >>"${FAKE_CURL_LOG:-/dev/null}"
[ "${FAKE_CURL:-ok}" = fail ] && exit 22
out=/dev/stdout
while [ $# -gt 0 ]; do if [ "$1" = -o ]; then out="$2"; shift; fi; shift; done
cat "$FAKE_TARBALL" >"$out"
SH
cat >"$BIN/date" <<'SH'
#!/bin/bash
echo 20260101T000000Z
SH
cat >"$BIN2/cp" <<SH
#!/bin/bash
for a in "\$@"; do case "\$a" in *docs-check.mjs.allye.backup.*) exit 1 ;; esac; done
exec "$(command -v cp)" "\$@"
SH
chmod +x "$BIN/curl" "$BIN/date" "$BIN2/cp"
VER=9.9.9
FX="$TMP/fx/allye-plugin-$VER"
mkdir -p "$FX/skills" "$FX/install" "$FX/manifests/codex" "$FX/templates"
cp -R "$ROOT"/skills/bridge* "$FX/skills/"
cp "$ROOT/install/docs-check.mjs" "$FX/install/"
cp "$ROOT/manifests/codex/AGENTS.md" "$FX/manifests/codex/"
cp -R "$ROOT/templates/git-docs" "$FX/templates/"
[ -z "$(find "$TMP/fx" -type l -print -quit)" ] || fail "fixture archive source holds symbolic links"
TARBALL="$TMP/fx.tar.gz"
tar -czf "$TARBALL" -C "$TMP/fx" "allye-plugin-$VER"
# An archive with a symbolic link.
cp -R "$TMP/fx" "$TMP/fxl"
ln -s /etc/passwd "$TMP/fxl/allye-plugin-$VER/skills/bridge/link"
tar -czf "$TMP/fxl.tar.gz" -C "$TMP/fxl" "allye-plugin-$VER"

# codex_run <home> <script> [ENV=value...]: run a guide block with HOME=<home>, a fresh
# TMPDIR (kept in LASTTD), fake curl/date and VERSION set.
# Sandbox: env -i (nothing of the caller's XDG_*, CODEX_HOME, PI_*, OPENCODE_* leaks in),
# and a guard that aborts the whole gate when HOME or ~/.codex resolve outside $TMP.
sandbox_guard() {
  local root home real sub
  root=$(cd "$TMP" && pwd -P)
  home=$(cd "$1" 2>/dev/null && pwd -P) || home=""
  case "$home" in
    "$root"/*) ;;
    *) echo "$NAME: sandbox guard: HOME '$1' is outside $TMP; aborting" >&2; kill -s TERM $$; exit 1 ;;
  esac
  for sub in .codex .allye .codex/skills; do
    if [ -e "$1/$sub" ] || [ -L "$1/$sub" ]; then
      real=$(readlink -f "$1/$sub")
      case "$real" in
        "$root"/*) ;;
        *) echo "$NAME: sandbox guard: $1/$sub resolves to $real, outside $TMP; aborting" >&2; kill -s TERM $$; exit 1 ;;
      esac
    fi
  done
}
codex_run() {
  local h="$1" sc="$2"
  shift 2
  sandbox_guard "$h"
  LASTTD=$(mktemp -d "$TMP/td.XXXXXX")
  echo "$LASTTD" >"$TMP/lasttd"
  env -i PATH="$BIN:$PATH" HOME="$h" XDG_CONFIG_HOME="$h/.config" TMPDIR="$LASTTD" FAKE_TARBALL="$TARBALL" FAKE_CURL_LOG="$TMP/curl.log" VERSION="$VER" "$@" bash -u "$sc" 2>>"$TMP/codex-stderr"
}
sha_of() { (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do if [ -f "$f" ] && [ ! -L "$f" ]; then printf '%s %s\n' "$f" "$(cksum <"$f")"; else printf '%s\n' "$f"; fi; done); }
BKD=.allye/backups/codex
S=20260101T000000Z

# Step 0: valid pasted version accepted; a multi-line paste and a non-version refused.
step0() { # <input>
  while IFS= read -r line; do
    case "$line" in "RAW=''"*) printf 'RAW=%q\n' "$1" ;; *) printf '%s\n' "$line" ;; esac
  done <"$TMP/step0.tpl" >"$TMP/step0.sh"
  mkdir -p "$TMP/h0"
  sandbox_guard "$TMP/h0"
  env -i PATH="$PATH" HOME="$TMP/h0" XDG_CONFIG_HOME="$TMP/h0/.config" bash -u "$TMP/step0.sh" 2>&1
}
out=$(step0 'v1.2.3') || fail "Step 0 (valid): exit $?"
[ "$out" = "Installing Allye 1.2.3" ] || fail "Step 0 (valid): got: $out"
code=0; out=$(step0 $'1.2.3\nrm -rf x') || code=$?
[ "$code" -ne 0 ] || fail "Step 0 (multi-line): accepted"
! grep -q 'Installing Allye' <<<"$out" || fail "Step 0 (multi-line): proceeded"
code=0; out=$(step0 'main') || code=$?
[ "$code" -ne 0 ] || fail "Step 0 (invalid): accepted"
code=0; out=$(step0 "1.2.3'; echo pwn; '") || code=$?
[ "$code" -ne 0 ] || fail "Step 0 (quote): accepted"

# Step 2, fresh home: skills, templates and docs-check installed from the tag archive.
mkdir -p "$TMP/h1"
out=$(codex_run "$TMP/h1" "$TMP/step2.sh") || fail "codex step (fresh): exit $?"
grep -Fq "archive/refs/tags/v$VER.tar.gz" "$TMP/curl.log" || fail "codex step (fresh): not the tag archive: $(cat "$TMP/curl.log")"
grep -Fq -- '--proto =https' "$TMP/curl.log" || fail "codex step (fresh): curl without --proto =https"
cmp -s "$TMP/h1/.codex/install/docs-check.mjs" "$ROOT/install/docs-check.mjs" || fail "codex step (fresh): docs-check.mjs not installed"
diff -r -x .allye-templates "$TMP/h1/.codex/templates/git-docs" "$ROOT/templates/git-docs" >/dev/null || fail "codex step (fresh): templates not installed"
[ -f "$TMP/h1/.codex/templates/git-docs/.allye-templates" ] || fail "codex step (fresh): marker .allye-templates not written"
cmp -s "$TMP/h1/.codex/skills/bridge/SKILL.md" "$ROOT/skills/bridge/SKILL.md" || fail "codex step (fresh): bridge skill not installed"
[ -z "$(ls -A "$TMP/h1/$BKD")" ] || fail "codex step (fresh): backups created with nothing to replace"
# Rerun over Allye's copies (marker present, one stale file): replaced, marker kept, backed up.
echo stale >"$TMP/h1/.codex/templates/git-docs/stale.md"
echo "skill edit" >"$TMP/h1/.codex/skills/bridge/EDIT.md"
: >"$TMP/codex-stderr"
out=$(codex_run "$TMP/h1" "$TMP/step2.sh") || fail "codex step (rerun): exit $?"
[ ! -e "$TMP/h1/.codex/templates/git-docs/stale.md" ] || fail "codex step (rerun): Allye's templates not replaced"
[ -f "$TMP/h1/.codex/templates/git-docs/.allye-templates" ] || fail "codex step (rerun): marker lost"
[ -z "$out" ] || fail "codex step (rerun): unexpected output: $out"
[ -f "$TMP/h1/$BKD/git-docs.allye.backup.$S/stale.md" ] || fail "codex step (rerun): templates not backed up"
[ -f "$TMP/h1/$BKD/docs-check.mjs.allye.backup.$S" ] || fail "codex step (rerun): docs-check.mjs not backed up"
[ -f "$TMP/h1/$BKD/bridge.allye.backup.$S/EDIT.md" ] || fail "codex step (rerun): bridge skill not backed up"
[ ! -e "$TMP/h1/.codex/skills/bridge/EDIT.md" ] || fail "codex step (rerun): bridge skill not replaced"
grep -Fq "Backup: $TMP/h1/$BKD/git-docs.allye.backup.$S" "$TMP/codex-stderr" || fail "codex step (rerun): backup path not reported"
[ "$(stat -c %a "$TMP/h1/$BKD" 2>/dev/null || stat -f %Lp "$TMP/h1/$BKD")" = 700 ] || fail "codex step (rerun): backup dir not mode 700"
[ "$(stat -c %a "$TMP/h1/$BKD/docs-check.mjs.allye.backup.$S" 2>/dev/null || stat -f %Lp "$TMP/h1/$BKD/docs-check.mjs.allye.backup.$S")" = 600 ] || fail "codex step (rerun): file backup not mode 600"
# A second run in the same second does not overwrite the first backup.
out=$(codex_run "$TMP/h1" "$TMP/step2.sh") || fail "codex step (same second): exit $?"
[ "$(ls "$TMP/h1/$BKD" | grep -c '^docs-check.mjs.allye.backup.')" = 2 ] || fail "codex step (same second): backup collision"
# Foreign copies: kept, with the exact messages.
mkdir -p "$TMP/h2/.codex/templates/git-docs" "$TMP/h2/.codex/install"
echo mine >"$TMP/h2/.codex/templates/git-docs/CLAUDE.md"
echo mine >"$TMP/h2/.codex/install/docs-check.mjs"
out=$(codex_run "$TMP/h2" "$TMP/step2.sh") || fail "codex step (foreign): exit $?"
[ "$out" = "Skipped $TMP/h2/.codex/templates/git-docs: not Allye's git docs templates. Ask the user before replacing it.
Skipped $TMP/h2/.codex/install/docs-check.mjs: not Allye's docs-check script. Ask the user before replacing it." ] ||
  fail "codex step (foreign): got: $out"
[ "$(cat "$TMP/h2/.codex/templates/git-docs/CLAUDE.md")" = mine ] || fail "codex step (foreign): templates overwritten"
[ "$(cat "$TMP/h2/.codex/install/docs-check.mjs")" = mine ] || fail "codex step (foreign): docs-check.mjs overwritten"
# A copy that looks like Allye's (@AGENTS.md) but has no marker is foreign: kept.
mkdir -p "$TMP/h3/.codex/templates"
cp -R "$ROOT/templates/git-docs" "$TMP/h3/.codex/templates/"
echo mine >"$TMP/h3/.codex/templates/git-docs/extra.md"
out=$(codex_run "$TMP/h3" "$TMP/step2.sh") || fail "codex step (no marker): exit $?"
[ "$out" = "Skipped $TMP/h3/.codex/templates/git-docs: not Allye's git docs templates. Ask the user before replacing it." ] ||
  fail "codex step (no marker): got: $out"
[ -f "$TMP/h3/.codex/templates/git-docs/extra.md" ] || fail "codex step (no marker): templates replaced"
[ ! -e "$TMP/h3/.codex/templates/git-docs/.allye-templates" ] || fail "codex step (no marker): marker written over a foreign copy"

# The marker present but CLAUDE.md not starting with @AGENTS.md: foreign, kept.
mkdir -p "$TMP/h14/.codex/templates"
cp -R "$ROOT/templates/git-docs" "$TMP/h14/.codex/templates/"
touch "$TMP/h14/.codex/templates/git-docs/.allye-templates"
printf 'mine\n' >"$TMP/h14/.codex/templates/git-docs/CLAUDE.md"
out=$(codex_run "$TMP/h14" "$TMP/step2.sh") || fail "codex step (marker, other CLAUDE.md): exit $?"
[ "$out" = "Skipped $TMP/h14/.codex/templates/git-docs: not Allye's git docs templates. Ask the user before replacing it." ] ||
  fail "codex step (marker, other CLAUDE.md): got: $out"
[ "$(cat "$TMP/h14/.codex/templates/git-docs/CLAUDE.md")" = mine ] || fail "codex step (marker, other CLAUDE.md): replaced"

# Symbolic links are foreign even when their target looks like Allye's: kept, the link
# target unchanged (cp never writes through a link).
mkdir -p "$TMP/h4/.codex/templates" "$TMP/h4/.codex/install" "$TMP/h4/elsewhere"
cp "$ROOT/install/docs-check.mjs" "$TMP/h4/elsewhere/docs-check.mjs"
echo "// local edit" >>"$TMP/h4/elsewhere/docs-check.mjs"
cp "$TMP/h4/elsewhere/docs-check.mjs" "$TMP/h4/script.orig"
ln -s ../../elsewhere/docs-check.mjs "$TMP/h4/.codex/install/docs-check.mjs"
cp -R "$ROOT/templates/git-docs" "$TMP/h4/elsewhere/git-docs"
touch "$TMP/h4/elsewhere/git-docs/.allye-templates"
echo mine >"$TMP/h4/elsewhere/git-docs/extra.md"
ln -s ../../elsewhere/git-docs "$TMP/h4/.codex/templates/git-docs"
out=$(codex_run "$TMP/h4" "$TMP/step2.sh") || fail "codex step (symlink): exit $?"
[ "$out" = "Skipped $TMP/h4/.codex/templates/git-docs: not Allye's git docs templates. Ask the user before replacing it.
Skipped $TMP/h4/.codex/install/docs-check.mjs: not Allye's docs-check script. Ask the user before replacing it." ] ||
  fail "codex step (symlink): got: $out"
[ -L "$TMP/h4/.codex/install/docs-check.mjs" ] || fail "codex step (symlink): docs-check.mjs link replaced"
cmp -s "$TMP/h4/elsewhere/docs-check.mjs" "$TMP/h4/script.orig" || fail "codex step (symlink): docs-check.mjs link target changed"
[ -L "$TMP/h4/.codex/templates/git-docs" ] || fail "codex step (symlink): templates link replaced"
[ -f "$TMP/h4/elsewhere/git-docs/extra.md" ] || fail "codex step (symlink): templates link target changed"

# Backup failures abort before anything is replaced, whichever copy fails.
seed_installed() { # <home>: an Allye install with a stale template, an edited skill and script
  mkdir -p "$1"
  codex_run "$1" "$TMP/step2.sh" >/dev/null || fail "codex step (seed $1): exit $?"
  echo stale >"$1/.codex/templates/git-docs/stale.md"
  echo sentinel >"$1/.codex/skills/bridge/SENTINEL"
  echo "// keep" >>"$1/.codex/install/docs-check.mjs"
}
seed_installed "$TMP/h5"
rm -rf "$TMP/h5/.allye/backups/codex" && : >"$TMP/h5/.allye/backups/codex"
before=$(sha_of "$TMP/h5/.codex")
: >"$TMP/fail-stderr"
code=0; out=$(codex_run "$TMP/h5" "$TMP/step2.sh") || code=$?
[ "$code" -ne 0 ] || fail "codex step (backup fails): not aborted"
[ "$(sha_of "$TMP/h5/.codex")" = "$before" ] || fail "codex step (backup fails): ~/.codex changed"
[ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex step (backup fails): temp dir left behind"
# Reverse case: the skills and templates backups succeed, the docs-check backup fails.
seed_installed "$TMP/h7"
before=$(sha_of "$TMP/h7/.codex")
: >"$TMP/codex-stderr"
code=0; out=$(codex_run "$TMP/h7" "$TMP/step2.sh" PATH="$BIN2:$BIN:$PATH") || code=$?
[ "$code" -ne 0 ] || fail "codex step (docs-check backup fails): not aborted"
[ "$(sha_of "$TMP/h7/.codex")" = "$before" ] || fail "codex step (docs-check backup fails): ~/.codex changed"
[ -f "$TMP/h7/.codex/skills/bridge/SENTINEL" ] || fail "codex step (docs-check backup fails): skills replaced"
[ -f "$TMP/h7/.codex/templates/git-docs/stale.md" ] || fail "codex step (docs-check backup fails): templates replaced"
[ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex step (docs-check backup fails): temp dir left behind"
# A failed download changes nothing under ~/.codex and leaves no temp dir.
seed_installed "$TMP/h8"
before=$(sha_of "$TMP/h8/.codex")
code=0; out=$(codex_run "$TMP/h8" "$TMP/step2.sh" FAKE_CURL=fail) || code=$?
[ "$code" -ne 0 ] || fail "codex step (download fails): not aborted"
[ "$(sha_of "$TMP/h8/.codex")" = "$before" ] || fail "codex step (download fails): ~/.codex changed"
[ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex step (download fails): temp dir left behind"
# An archive with a symbolic link is refused.
code=0; out=$(codex_run "$TMP/h8" "$TMP/step2.sh" FAKE_TARBALL="$TMP/fxl.tar.gz") || code=$?
[ "$code" -ne 0 ] || fail "codex step (archive symlink): not refused"
[ "$(sha_of "$TMP/h8/.codex")" = "$before" ] || fail "codex step (archive symlink): ~/.codex changed"
[ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex step (archive symlink): temp dir left behind"
# Inherited TMP/ALLYE_TMP are never deleted (success and failure).
mkdir -p "$TMP/precious" && echo keep >"$TMP/precious/file"
mkdir -p "$TMP/h9"
codex_run "$TMP/h9" "$TMP/step2.sh" TMP="$TMP/precious" ALLYE_TMP="$TMP/precious" >/dev/null || fail "codex step (inherited env): exit $?"
[ "$(cat "$TMP/precious/file")" = keep ] || fail "codex step (inherited env): inherited dir deleted"
codex_run "$TMP/h9" "$TMP/step2.sh" TMP="$TMP/precious" ALLYE_TMP="$TMP/precious" FAKE_CURL=fail >/dev/null && fail "codex step (inherited env): download failure accepted"
[ "$(cat "$TMP/precious/file")" = keep ] || fail "codex step (inherited env, failure): inherited dir deleted"
# Step 3 alone with an inherited non-temp ALLYE_TMP is refused, not deleted.
codex_run "$TMP/h9" "$TMP/step3.sh" ALLYE_TMP="$TMP/precious" TS="$S" >/dev/null && fail "codex AGENTS (inherited env): accepted"
[ "$(cat "$TMP/precious/file")" = keep ] || fail "codex AGENTS (inherited env): inherited dir deleted"

# Skills: a foreign or linked bridge skill is skipped (kept, with a message); crew skills still installed.
mkdir -p "$TMP/h10/.codex/skills/bridge" "$TMP/h10/elsewhere/bridge-recon"
printf 'name: other\n' >"$TMP/h10/.codex/skills/bridge/SKILL.md"
printf 'name: bridge-recon\n' >"$TMP/h10/elsewhere/bridge-recon/SKILL.md"
ln -s ../../elsewhere/bridge-recon "$TMP/h10/.codex/skills/bridge-recon"
out=$(codex_run "$TMP/h10" "$TMP/step2.sh") || fail "codex step (foreign skill): exit $?"
[ "$out" = "Skipped $TMP/h10/.codex/skills/bridge: not Allye's bridge skill. Ask the user before replacing it.
Skipped $TMP/h10/.codex/skills/bridge-recon: not Allye's bridge-recon skill. Ask the user before replacing it." ] ||
  fail "codex step (foreign skill): got: $out"
[ "$(cat "$TMP/h10/.codex/skills/bridge/SKILL.md")" = "name: other" ] || fail "codex step (foreign skill): overwritten"
[ -L "$TMP/h10/.codex/skills/bridge-recon" ] || fail "codex step (foreign skill): link replaced"
cmp -s "$TMP/h10/.codex/skills/bridge-pilot/SKILL.md" "$ROOT/skills/bridge-pilot/SKILL.md" || fail "codex step (foreign skill): other crew skills not installed"
[ ! -e "$TMP/h10/$BKD/bridge.allye.backup.$S" ] || fail "codex step (foreign skill): foreign skill backed up as Allye's"
# Archives with absolute paths, parent paths or link entries are refused before extraction.
if tar --version 2>/dev/null | grep -q GNU; then
  # Absolute paths: the archive holds the whole expected tree under a leading slash.
  mkdir -p "$TMP/absroot"
  tar -czPf "$TMP/abs.tar.gz" -C "$TMP/fx" --transform 's,^,/,' "allye-plugin-$VER"  2>/dev/null
  [ "$(tar -tzf "$TMP/abs.tar.gz" | head -n 1 | cut -c1)" = / ] || fail "fixture abs.tar.gz has no absolute entries"
  tar -czf "$TMP/dd.tar.gz" -C "$TMP/fx" --transform 's,^,../,' "allye-plugin-$VER"  2>/dev/null
  [ "$(tar -tzf "$TMP/dd.tar.gz" | head -n 1 | cut -c1-3)" = ../ ] || fail "fixture dd.tar.gz has no parent entries"
  # A hard-link entry.
  cp -R "$TMP/fx" "$TMP/fxh"
  ln "$TMP/fxh/allye-plugin-$VER/install/docs-check.mjs" "$TMP/fxh/allye-plugin-$VER/install/dup.mjs"
  tar -czf "$TMP/hl.tar.gz" -C "$TMP/fxh" "allye-plugin-$VER"
  [ -n "$(tar -tvzf "$TMP/hl.tar.gz" | grep '^h')" ] || fail "fixture hl.tar.gz has no hard-link entry"
  # Skill directory names that are not bridge[A-Za-z0-9_-]*: refused, nothing is word-split.
  for odd in 'bridge x' 'bridge?z' 'bridge*'; do
    k=$(printf '%s' "$odd" | tr -c 'A-Za-z0-9' _)
    cp -R "$TMP/fx" "$TMP/fxo$k"
    mkdir -p "$TMP/fxo$k/allye-plugin-$VER/skills/$odd"
    echo "name: $odd" >"$TMP/fxo$k/allye-plugin-$VER/skills/$odd/SKILL.md"
    tar -czf "$TMP/odd$k.tar.gz" -C "$TMP/fxo$k" "allye-plugin-$VER"
  done
  seed_installed "$TMP/h11"
  mkdir -p "$TMP/h11/.codex/skills/x" "$TMP/h11/.codex/skills/z"
  echo precious >"$TMP/h11/.codex/skills/x/SENTINEL"
  echo precious >"$TMP/h11/.codex/skills/z/SENTINEL"
  before=$(sha_of "$TMP/h11/.codex")
  # A regular file where a skill directory is expected.
  cp -R "$TMP/fx" "$TMP/fxf"
  echo "name: bridge-x" >"$TMP/fxf/allye-plugin-$VER/skills/bridge-x"
  tar -czf "$TMP/filebridge.tar.gz" -C "$TMP/fxf" "allye-plugin-$VER"
  for bad in abs dd fxl hl oddbridge_x oddbridge_z oddbridge_ filebridge; do
    code=0; out=$(codex_run "$TMP/h11" "$TMP/step2.sh" FAKE_TARBALL="$TMP/$bad.tar.gz") || code=$?
    [ "$code" -ne 0 ] || fail "codex step (archive $bad): not refused"
    [ "$(sha_of "$TMP/h11/.codex")" = "$before" ] || fail "codex step (archive $bad): ~/.codex changed"
    [ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex step (archive $bad): temp dir left behind"
  done
  [ -f "$TMP/h11/.codex/skills/x/SENTINEL" ] && [ -f "$TMP/h11/.codex/skills/z/SENTINEL" ] || fail "codex step (odd skill names): other skills deleted"
else
  echo "$NAME: SKIPPED archive-entry cases (absolute, parent, hard-link, odd names): tar is not GNU tar" >&2
fi
# A previous ALLYE_TMP made by Step 2 is cleaned before a new one is made.
mkdir -p "$TMP/h12" "$TMP/prevtd/tmp.old" "$TMP/prevtd2/tmp.foreign"
echo x >"$TMP/prevtd/tmp.old/file"
: >"$TMP/prevtd/tmp.old/.allye-tmp"
echo keep >"$TMP/prevtd2/tmp.foreign/file"
code=0; out=$(codex_run "$TMP/h12" "$TMP/step2.sh" TMPDIR="$TMP/prevtd" ALLYE_TMP="$TMP/prevtd/tmp.old") || code=$?
[ "$code" -eq 0 ] || fail "codex step (previous ALLYE_TMP): exit $code"
[ ! -e "$TMP/prevtd/tmp.old" ] || fail "codex step (previous ALLYE_TMP): not cleaned"
# A user-owned tmp.* directory without Step 2's marker is kept.
code=0; out=$(codex_run "$TMP/h12" "$TMP/step2.sh" TMPDIR="$TMP/prevtd2" ALLYE_TMP="$TMP/prevtd2/tmp.foreign") || code=$?
[ "$(cat "$TMP/prevtd2/tmp.foreign/file")" = keep ] || fail "codex step (foreign tmp dir): deleted"
# Step 3 refuses an ALLYE_TMP with .. and leaves it alone.
mkdir -p "$TMP/h13/.codex" "$TMP/trav/tmp.keep"
tar -xzf "$TARBALL" -C "$TMP/trav/tmp.keep"
printf 'user\n' >"$TMP/h13/.codex/AGENTS.md"
code=0; out=$(codex_run "$TMP/h13" "$TMP/step3.sh" TMPDIR="$TMP/trav" ALLYE_TMP="$TMP/trav/tmp.keep/../tmp.keep" TS="$S") || code=$?
[ "$code" -ne 0 ] || fail "codex AGENTS (traversal): accepted"
[ -d "$TMP/trav/tmp.keep" ] || fail "codex AGENTS (traversal): directory deleted"
# Step 3 refuses a nested ALLYE_TMP and a tmp.* directory without the marker, leaving them alone.
mkdir -p "$TMP/nest/tmp.a/tmp.b" "$TMP/nest/tmp.nomark"
tar -xzf "$TARBALL" -C "$TMP/nest/tmp.a/tmp.b"
: >"$TMP/nest/tmp.a/tmp.b/.allye-tmp"
tar -xzf "$TARBALL" -C "$TMP/nest/tmp.nomark"
for t in tmp.a/tmp.b tmp.nomark; do
  code=0; out=$(codex_run "$TMP/h13" "$TMP/step3.sh" TMPDIR="$TMP/nest" ALLYE_TMP="$TMP/nest/$t" TS="$S") || code=$?
  [ "$code" -ne 0 ] || fail "codex AGENTS ($t): accepted"
  [ -d "$TMP/nest/$t" ] || fail "codex AGENTS ($t): directory deleted"
done
[ "$(cat "$TMP/h13/.codex/AGENTS.md")" = user ] || fail "codex AGENTS (nested/unmarked): file changed"
[ "$(cat "$TMP/h13/.codex/AGENTS.md")" = user ] || fail "codex AGENTS (traversal): file changed"

# AGENTS.md (Steps 2 and 3 together): append, rerun (one section, user text kept),
# unmarked refusal, fresh, symlinked file, failed backup.
ag_expect() { printf '<!-- allye:begin -->\n'; cat "$ROOT/manifests/codex/AGENTS.md"; printf '<!-- allye:end -->\n'; }
mkdir -p "$TMP/a1/.codex"
printf 'user line 1\n\nuser line 2\n' >"$TMP/a1/.codex/AGENTS.md"
chmod 640 "$TMP/a1/.codex/AGENTS.md"
out=$(codex_run "$TMP/a1" "$TMP/both.sh") || fail "codex AGENTS (append): exit $?"
[ "$(grep -Fxc '<!-- allye:begin -->' "$TMP/a1/.codex/AGENTS.md")" = 1 ] || fail "codex AGENTS (append): marker count"
cmp -s "$TMP/a1/$BKD/AGENTS.md.allye.backup.$S" <(printf 'user line 1\n\nuser line 2\n') || fail "codex AGENTS (append): not backed up"
[ "$(stat -c %a "$TMP/a1/.codex/AGENTS.md" 2>/dev/null || stat -f %Lp "$TMP/a1/.codex/AGENTS.md")" = 640 ] || fail "codex AGENTS (append): file mode changed"
[ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex AGENTS (append): temp dir left behind"
cp "$TMP/a1/.codex/AGENTS.md" "$TMP/a1/first"
out=$(codex_run "$TMP/a1" "$TMP/both.sh") || fail "codex AGENTS (rerun): exit $?"
cmp -s "$TMP/a1/.codex/AGENTS.md" "$TMP/a1/first" || fail "codex AGENTS (rerun): file changed"
[ "$(grep -Fxc '<!-- allye:end -->' "$TMP/a1/.codex/AGENTS.md")" = 1 ] || fail "codex AGENTS (rerun): more than one section"
[ "$(grep -c '^# Allye$' "$TMP/a1/.codex/AGENTS.md")" = 1 ] || fail "codex AGENTS (rerun): duplicate Allye heading"
head -n 3 "$TMP/a1/.codex/AGENTS.md" | cmp -s - <(printf 'user line 1\n\nuser line 2\n') || fail "codex AGENTS (rerun): user text changed"
[ "$(ls -A "$TMP/a1/.codex" | grep -c 'AGENTS.md.')" = 0 ] || fail "codex AGENTS (rerun): temp files left"
mkdir -p "$TMP/a2/.codex"
printf '# Allye\n\nold workflow section\n' >"$TMP/a2/.codex/AGENTS.md"
code=0; out=$(codex_run "$TMP/a2" "$TMP/both.sh") || code=$?
[ "$code" -ne 0 ] || fail "codex AGENTS (unmarked): not refused"
[ "$(cat "$TMP/a2/.codex/AGENTS.md")" = "$(printf '# Allye\n\nold workflow section')" ] || fail "codex AGENTS (unmarked): file changed"
grep -Fq 'old workflow' "$TMP/a2/.codex/AGENTS.md" && grep -q '1:# Allye' <<<"$out" || fail "codex AGENTS (unmarked): lines not shown: $out"
[ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex AGENTS (unmarked): temp dir left behind"
mkdir -p "$TMP/a3"
out=$(codex_run "$TMP/a3" "$TMP/both.sh") || fail "codex AGENTS (fresh): exit $?"
cmp -s "$TMP/a3/.codex/AGENTS.md" <(ag_expect) || fail "codex AGENTS (fresh): content"
# A stale MARKED section is replaced; text before and after it stays exactly as is.
mkdir -p "$TMP/a6/.codex"
printf 'user-before\n<!-- allye:begin -->\nOLD STALE\n<!-- allye:end -->\nuser-after\n' >"$TMP/a6/.codex/AGENTS.md"
out=$(codex_run "$TMP/a6" "$TMP/both.sh") || fail "codex AGENTS (stale marked): exit $?"
cmp -s "$TMP/a6/.codex/AGENTS.md" <(printf 'user-before\n'; ag_expect; printf 'user-after\n') || fail "codex AGENTS (stale marked): not exactly before + fresh section + after"
! grep -q 'OLD STALE' "$TMP/a6/.codex/AGENTS.md" || fail "codex AGENTS (stale marked): old section kept"
# Malformed markers: refused, the file unchanged, no leftovers.
n=0
for body in \
  $'user\n<!-- allye:begin -->\nhalf\n' \
  $'user\n<!-- allye:end -->\nx\n<!-- allye:begin -->\n' \
  $'<!-- allye:begin -->\na\n<!-- allye:end -->\n<!-- allye:begin -->\nb\n<!-- allye:end -->\n' \
  $'user\n<!-- allye:end -->\n'; do
  n=$((n + 1))
  mkdir -p "$TMP/m$n/.codex"
  printf '%s' "$body" >"$TMP/m$n/.codex/AGENTS.md"
  code=0; out=$(codex_run "$TMP/m$n" "$TMP/both.sh") || code=$?
  [ "$code" -ne 0 ] || fail "codex AGENTS (malformed $n): not refused"
  [ "$(cat "$TMP/m$n/.codex/AGENTS.md"; echo .)" = "$(printf '%s' "$body"; echo .)" ] || fail "codex AGENTS (malformed $n): file changed"
  [ "$(ls -A "$TMP/m$n/.codex" | grep -c 'AGENTS.md\.')" = 0 ] || fail "codex AGENTS (malformed $n): temp files left"
  [ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex AGENTS (malformed $n): temp dir left behind"
done
# Failing or lying tools leave AGENTS.md untouched, with no temp files and no temp dir.
mkdir -p "$TMP/bin3" "$TMP/bin4" "$TMP/bin5"
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin3/awk"
printf '#!/bin/bash\necho garbage\n' >"$TMP/bin4/awk"
cat >"$TMP/bin5/cp" <<SH
#!/bin/bash
for a in "\$@"; do case "\$a" in */AGENTS.md.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]) exit 1 ;; esac; done
exec "$(command -v cp)" "\$@"
SH
chmod +x "$TMP/bin3/awk" "$TMP/bin4/awk" "$TMP/bin5/cp"
n=0
for shim in bin3 bin4 bin5; do
  n=$((n + 1))
  mkdir -p "$TMP/s$n/.codex"
  printf 'user-before\n<!-- allye:begin -->\nOLD\n<!-- allye:end -->\nuser-after\n' >"$TMP/s$n/.codex/AGENTS.md"
  code=0; out=$(codex_run "$TMP/s$n" "$TMP/both.sh" PATH="$TMP/$shim:$BIN:$PATH") || code=$?
  [ "$code" -ne 0 ] || fail "codex AGENTS (shim $shim): not aborted"
  [ "$(cat "$TMP/s$n/.codex/AGENTS.md")" = "$(printf 'user-before\n<!-- allye:begin -->\nOLD\n<!-- allye:end -->\nuser-after')" ] || fail "codex AGENTS (shim $shim): file changed"
  [ "$(ls -A "$TMP/s$n/.codex" | grep -c 'AGENTS.md\.')" = 0 ] || fail "codex AGENTS (shim $shim): temp files left"
  [ -z "$(ls -A "$(cat "$TMP/lasttd")")" ] || fail "codex AGENTS (shim $shim): temp dir left behind"
done
# A symbolic-link AGENTS.md: the target is updated, the link kept.
mkdir -p "$TMP/a4/.codex" "$TMP/a4/dotfiles"
printf 'mine\n' >"$TMP/a4/dotfiles/AGENTS.md"
ln -s ../dotfiles/AGENTS.md "$TMP/a4/.codex/AGENTS.md"
out=$(codex_run "$TMP/a4" "$TMP/both.sh") || fail "codex AGENTS (symlink): exit $?"
[ -L "$TMP/a4/.codex/AGENTS.md" ] || fail "codex AGENTS (symlink): link replaced"
cmp -s "$TMP/a4/dotfiles/AGENTS.md" <(printf 'mine\n\n'; ag_expect) || fail "codex AGENTS (symlink): target content"
cmp -s "$TMP/a4/$BKD/AGENTS.md.allye.backup.$S" <(printf 'mine\n') || fail "codex AGENTS (symlink): not backed up"
[ "$(ls -A "$TMP/a4/dotfiles")" = AGENTS.md ] || fail "codex AGENTS (symlink): temp files in the link target directory"
[ "$(ls -A "$TMP/a4/.codex" | grep -c 'AGENTS.md\.')" = 0 ] || fail "codex AGENTS (symlink): temp files in .codex"
# Step 3 alone: a failed AGENTS.md backup leaves the file untouched and no temp files.
mkdir -p "$TMP/a5/.codex" "$TMP/a5/.allye/backups" "$TMP/a5td/tmp.keep"
printf 'user\n' >"$TMP/a5/.codex/AGENTS.md"
: >"$TMP/a5/.allye/backups/codex"
tar -xzf "$TARBALL" -C "$TMP/a5td/tmp.keep"
: >"$TMP/a5td/tmp.keep/.allye-tmp"
code=0; out=$(codex_run "$TMP/a5" "$TMP/step3.sh" TMPDIR="$TMP/a5td" ALLYE_TMP="$TMP/a5td/tmp.keep" TS="$S") || code=$?
[ "$code" -ne 0 ] || fail "codex AGENTS (backup fails): not aborted"
[ "$(cat "$TMP/a5/.codex/AGENTS.md")" = user ] || fail "codex AGENTS (backup fails): file changed"
[ "$(ls -A "$TMP/a5/.codex" | grep -c 'AGENTS.md\.')" = 0 ] || fail "codex AGENTS (backup fails): temp files left"
[ ! -e "$TMP/a5td/tmp.keep" ] || fail "codex AGENTS (backup fails): archive dir not cleaned"

# 3b. `npm test` (what CI runs) reaches test:docs-gate, directly or through another script.
reach=$(node -e '
const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).scripts;
const seen = new Set();
const walk = (name) => {
  if (seen.has(name) || !s[name]) return false;
  seen.add(name);
  if (name === "test:docs-gate") return true;
  return [...s[name].matchAll(/npm run (\S+)/g)].some((m) => walk(m[1]));
};
console.log(walk("test") ? "yes" : "no");' "$ROOT/package.json")
[ "$reach" = yes ] || fail "package.json: scripts.test does not reach test:docs-gate"
has_line package.json '    "test:installer": "bash install/test-validation.sh && bash install/test-installer.sh && npm run test:docs-gate",'

# --- Absent path --------------------------------------------------------------------

# 4. The skills keep the fail-closed lines (pinned in their own checks; asserted here so
# this check stays meaningful alone).
has_line skills/bridge-strategist/SKILL.md '   Its verify is the Allye plugin'"'"'s docs-check script, `node <plugin>/install/docs-check.mjs --root <repo>`: `resolved` when `install/docs-check.mjs` exists in the plugin install, else `unresolved` with that reason; never improvise a substitute.'
has_line skills/bridge-copilot/SKILL.md '   A docs-check the plan left `unresolved`, or missing from the plugin install → `blocked` naming it; never skip it or substitute another check.'
has_line skills/bridge-dispatcher/SKILL.md '- When `templates/git-docs/` or `install/docs-check.mjs` is absent from the install, report it `unresolved` in `gitDocs` and improvise no template or check.'

# 5. docs-check from a plugin copy without templates: 0 clean, 1 findings, 2 usage.
mkdir -p "$TMP/plugin/install" "$TMP/repo"
cp "$ROOT/install/docs-check.mjs" "$TMP/plugin/install/"
[ ! -e "$TMP/plugin/templates" ] || fail "temp plugin unexpectedly has templates"
printf '# Repo\n\nSee [usage](#usage).\n\n## Usage\n' >"$TMP/repo/README.md"
code=0; out=$(node "$TMP/plugin/install/docs-check.mjs" --root "$TMP/repo" 2>&1) || code=$?
[ "$code" -eq 0 ] || fail "absent templates, clean repo: expected exit 0, got $code: $out"
[ "$out" = "docs-check: ok (1 files)" ] || fail "absent templates, clean repo: got: $out"
printf '# Repo\n\nSee [gone](gone.md).\n' >"$TMP/repo/README.md"
code=0; out=$(node "$TMP/plugin/install/docs-check.mjs" --root "$TMP/repo" 2>/dev/null) || code=$?
[ "$code" -eq 1 ] || fail "absent templates, broken link: expected exit 1, got $code"
[ "$out" = "docs-check: README.md:3: link: missing target gone.md" ] || fail "absent templates, broken link: got: $out"
code=0; node "$TMP/plugin/install/docs-check.mjs" --root >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || fail "absent templates, usage error: expected exit 2, got $code"

finish
