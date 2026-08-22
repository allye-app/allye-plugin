#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json" SEED_FILE="$ROOT/seed/seed-skills.json"
print_error(){ printf '%s\n' "$*" >&2; }; print_warning(){ :; }; print_success(){ :; }; print_step(){ :; }
source "$ROOT/install/lib.sh"
payload=$(printf '%s\n' '---' 'name: x' 'description: x' '---')
hash=$(printf '%s' "$payload" | sha256sum | cut -d' ' -f1)
length=$(printf '%s' "$payload" | wc -c | tr -d ' ')
bytes=$(printf '%s' "$payload" | base64 -w0)
cat > "$TMP/artifact.json" <<EOF
{"release_id":"release-1","canonical_hash":"$(printf a%.0s {1..64})","integrity":{"valid":true},"manifest":{"sha256":"$(printf a%.0s {1..64})","files":[{"path":"SKILL.md","bytes":$length,"sha256":"$hash"}]},"files":[{"path":"SKILL.md","bytes_base64":"$bytes"}]}
EOF
export ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/artifact.json"
install_skills_to_disk hermes
out="$HOME/.hermes/skills/allye/SKILL.md"
test -f "$out"; grep -q '"release_id":"release-1"' "$HOME/.hermes/skills/allye/.allye-artifact.json"; first=$(sha256sum "$out")
install_skills_to_disk hermes; test "$first" = "$(sha256sum "$out")"
# A multistep publication failure before the tree swap preserves the old tree.
export ALLYE_INSTALL_FAILPOINT=before-tree-swap
if install_skills_to_disk hermes; then exit 1; fi
unset ALLYE_INSTALL_FAILPOINT
test "$first" = "$(sha256sum "$out")"
# Missing/unsupported Python exchange capability fails before staging and preserves live tree.
export ALLYE_PYTHON_BIN=false
if install_skills_to_disk hermes; then exit 1; fi
unset ALLYE_PYTHON_BIN
test -f "$out"; test "$first" = "$(sha256sum "$out")"
rm -rf "$HOME/.hermes"; jq '.integrity.valid=false' "$TMP/artifact.json" > "$TMP/bad.json"; export ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/bad.json"
if install_skills_to_disk hermes; then exit 1; fi
test ! -e "$HOME/.hermes"
# Traversal and duplicate paths fail before a disk tree is created.
jq '.integrity.valid=true | .files[0].path="references/../../escape" | .manifest.files[0].path="references/../../escape"' "$TMP/artifact.json" > "$TMP/traversal.json"; export ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/traversal.json"
if install_skills_to_disk hermes; then exit 1; fi
test ! -e "$HOME/.hermes/skills/allye/SKILL.md"; test ! -e "$TMP/escape"
jq '.files += [.files[0]]' "$TMP/artifact.json" > "$TMP/duplicate.json"; export ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/duplicate.json"
if install_skills_to_disk hermes; then exit 1; fi
test ! -e "$HOME/.hermes/skills/allye/SKILL.md"
printf 'API artifact installer contract passed\n'
