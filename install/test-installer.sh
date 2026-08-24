#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT/install/test-conflicts.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json"
print_error(){ :; }; print_warning(){ :; }; print_success(){ :; }; print_step(){ :; }
source "$ROOT/install/lib.sh"
payload=$'---\nname: x\ndescription: x\n---'; hash=$(printf %s "$payload" | sha256sum | cut -d' ' -f1); bytes=$(printf %s "$payload" | base64 -w0); length=$(printf %s "$payload" | wc -c | tr -d ' ')
cat > "$TMP/artifact.json" <<EOF
{"release_id":"release-1","canonical_hash":"$hash","integrity":{"valid":true},"manifest":{"sha256":"$hash","files":[{"path":"SKILL.md","bytes":$length,"sha256":"$hash"}]},"files":[{"path":"SKILL.md","bytes_base64":"$bytes"}]}
EOF
export ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/artifact.json"
# A legacy/contextless invocation is never a physical distribution.
if install_skills_to_disk hermes; then exit 1; fi
test ! -e "$HOME/.hermes/skills/allye"
printf 'contextless disk installer: fail-closed\n'
