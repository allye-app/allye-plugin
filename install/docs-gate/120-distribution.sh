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
# them. The guide's block is extracted and run against a temp HOME.
DOC=docs/install-codex.md
has_line "$DOC" 'mkdir -p ~/.codex/templates ~/.codex/install'
has_line "$DOC" 'if [ -L "$T" ] || { [ -e "$T" ] && { [ ! -f "$T/.allye-templates" ] || [ "$(head -n 1 "$T/CLAUDE.md" 2>/dev/null)" != "@AGENTS.md" ]; }; }; then'
has_line "$DOC" '  touch "$T/.allye-templates"'
has_line "$DOC" '  echo "Skipped $T: not Allye'"'"'s git docs templates. Ask the user before replacing it."'
has_line "$DOC" '  rm -rf "$T"'
has_line "$DOC" '  cp -R "$TMP"/allye-plugin-main/templates/git-docs ~/.codex/templates/'
has_line "$DOC" 'if [ -L "$C" ] || { [ -e "$C" ] && ! grep -Fxq "// docs-check: deterministic checks for a repository'"'"'s git docs (no dependencies)." "$C"; }; then'
has_line "$DOC" '  echo "Skipped $C: not Allye'"'"'s docs-check script. Ask the user before replacing it."'
has_line "$DOC" '  cp "$TMP"/allye-plugin-main/install/docs-check.mjs "$C"'
has_line "$DOC" 'Before replacing an existing `~/.codex/skills/bridge`, check that it is the Allye Bridge (`name: bridge` in its `SKILL.md`); otherwise ask the user. Replace `~/.codex/templates/git-docs` and `~/.codex/install/docs-check.mjs` only when they are Allye'"'"'s copies; otherwise ask the user. The script below checks them (Allye'"'"'s templates directory holds the `.allye-templates` marker this step writes and its `CLAUDE.md` starts with `@AGENTS.md`; Allye'"'"'s script carries the docs-check header line; a symbolic link is never Allye'"'"'s copy) and skips a foreign copy with a message.'
has_line "$DOC" 'Without `~/.codex/templates/git-docs` and `~/.codex/install/docs-check.mjs`, Bridge reports docs-check as `unresolved` and never improvises a substitute.'
# The rule comes before the block.
rule=$(grep -n '^Before replacing an existing `~/.codex/skills/bridge`' "$ROOT/$DOC" | cut -d: -f1)
block=$(grep -n '^mkdir -p ~/.codex/templates ~/.codex/install$' "$ROOT/$DOC" | cut -d: -f1)
[ -n "$rule" ] && [ -n "$block" ] && [ "$rule" -lt "$block" ] || fail "$DOC: the replace-only-Allye's-copies rule must precede the copy block"
[ "$(head -n 1 "$ROOT/templates/git-docs/CLAUDE.md")" = "@AGENTS.md" ] || fail "templates/git-docs/CLAUDE.md: first line is not @AGENTS.md (the Codex guide's ownership check)"
grep -Fxq "// docs-check: deterministic checks for a repository's git docs (no dependencies)." "$ROOT/install/docs-check.mjs" ||
  fail "install/docs-check.mjs: header line changed (the Codex guide's ownership check)"

# codex_run <home>: run the guide's templates/docs-check lines with HOME=<home> and the
# repository as the extracted archive.
awk '/^mkdir -p ~\/.codex\/templates ~\/.codex\/install$/ {on=1} on {print} on && /^fi$/ && ++n == 2 {exit}' "$ROOT/$DOC" >"$TMP/codex-step.sh"
mkdir -p "$TMP/archive" && ln -s "$ROOT" "$TMP/archive/allye-plugin-main"
codex_run() { HOME="$1" TMP="$TMP/archive" bash -eu "$TMP/codex-step.sh"; }
# Fresh home: both installed.
mkdir -p "$TMP/h1"
out=$(codex_run "$TMP/h1") || fail "codex step (fresh): exit $?"
cmp -s "$TMP/h1/.codex/install/docs-check.mjs" "$ROOT/install/docs-check.mjs" || fail "codex step (fresh): docs-check.mjs not installed"
diff -r -x .allye-templates "$TMP/h1/.codex/templates/git-docs" "$ROOT/templates/git-docs" >/dev/null || fail "codex step (fresh): templates not installed"
[ -f "$TMP/h1/.codex/templates/git-docs/.allye-templates" ] || fail "codex step (fresh): marker .allye-templates not written"
# Rerun over Allye's copies (marker present, one stale file): replaced, marker kept.
echo stale >"$TMP/h1/.codex/templates/git-docs/stale.md"
out=$(codex_run "$TMP/h1") || fail "codex step (rerun): exit $?"
[ ! -e "$TMP/h1/.codex/templates/git-docs/stale.md" ] || fail "codex step (rerun): Allye's templates not replaced"
[ -f "$TMP/h1/.codex/templates/git-docs/.allye-templates" ] || fail "codex step (rerun): marker lost"
[ -z "$out" ] || fail "codex step (rerun): unexpected output: $out"
# Foreign copies: kept, with the exact messages.
mkdir -p "$TMP/h2/.codex/templates/git-docs" "$TMP/h2/.codex/install"
echo mine >"$TMP/h2/.codex/templates/git-docs/CLAUDE.md"
echo mine >"$TMP/h2/.codex/install/docs-check.mjs"
out=$(codex_run "$TMP/h2") || fail "codex step (foreign): exit $?"
[ "$out" = "Skipped $TMP/h2/.codex/templates/git-docs: not Allye's git docs templates. Ask the user before replacing it.
Skipped $TMP/h2/.codex/install/docs-check.mjs: not Allye's docs-check script. Ask the user before replacing it." ] ||
  fail "codex step (foreign): got: $out"
[ "$(cat "$TMP/h2/.codex/templates/git-docs/CLAUDE.md")" = mine ] || fail "codex step (foreign): templates overwritten"
[ "$(cat "$TMP/h2/.codex/install/docs-check.mjs")" = mine ] || fail "codex step (foreign): docs-check.mjs overwritten"
# A copy that looks like Allye's (@AGENTS.md) but has no marker is foreign: kept.
mkdir -p "$TMP/h3/.codex/templates"
cp -R "$ROOT/templates/git-docs" "$TMP/h3/.codex/templates/"
echo mine >"$TMP/h3/.codex/templates/git-docs/extra.md"
out=$(codex_run "$TMP/h3") || fail "codex step (no marker): exit $?"
[ "$out" = "Skipped $TMP/h3/.codex/templates/git-docs: not Allye's git docs templates. Ask the user before replacing it." ] ||
  fail "codex step (no marker): got: $out"
[ -f "$TMP/h3/.codex/templates/git-docs/extra.md" ] || fail "codex step (no marker): templates replaced"
[ ! -e "$TMP/h3/.codex/templates/git-docs/.allye-templates" ] || fail "codex step (no marker): marker written over a foreign copy"

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
out=$(codex_run "$TMP/h4") || fail "codex step (symlink): exit $?"
[ "$out" = "Skipped $TMP/h4/.codex/templates/git-docs: not Allye's git docs templates. Ask the user before replacing it.
Skipped $TMP/h4/.codex/install/docs-check.mjs: not Allye's docs-check script. Ask the user before replacing it." ] ||
  fail "codex step (symlink): got: $out"
[ -L "$TMP/h4/.codex/install/docs-check.mjs" ] || fail "codex step (symlink): docs-check.mjs link replaced"
cmp -s "$TMP/h4/elsewhere/docs-check.mjs" "$TMP/h4/script.orig" || fail "codex step (symlink): docs-check.mjs link target changed"
[ -L "$TMP/h4/.codex/templates/git-docs" ] || fail "codex step (symlink): templates link replaced"
[ -f "$TMP/h4/elsewhere/git-docs/extra.md" ] || fail "codex step (symlink): templates link target changed"

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
