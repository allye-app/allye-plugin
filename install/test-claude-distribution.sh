#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/allye-claude-distribution.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json"
export ALLYE_MANIFEST_DIR="$TMP/manifests" ALLYE_API_URL="http://127.0.0.1:3001" CALLS="$TMP/calls"
print_error(){ printf '%s\n' "$*" >&2; }
print_warning(){ printf '%s\n' "$*" >&2; }
print_success(){ :; }
print_step(){ :; }
source "$ROOT/install/lib.sh"

skill=$'---\nname: Claude distribution\ndescription: Canonical Claude layout\n---\n\n# Claude skill\n'
reference=$'# Reference\n\nAccessible from Claude skill layout.\n'
skill_hash=$(printf %s "$skill" | sha256sum | cut -d' ' -f1)
reference_hash=$(printf %s "$reference" | sha256sum | cut -d' ' -f1)
hash=$(node - "$skill" "$reference" <<'NODE'
const { createHash } = require('node:crypto');
const [skill, reference] = process.argv.slice(2);
const h = createHash('sha256');
for (const [path, content] of [["references/guide.md", reference], ["SKILL.md", skill]].sort(([a], [b]) => a.localeCompare(b))) h.update(path).update('\0').update(content).update('\0');
process.stdout.write(h.digest('hex'));
NODE
)
skill_b64=$(printf %s "$skill" | base64 -w0)
reference_b64=$(printf %s "$reference" | base64 -w0)
cat > "$TMP/artifact.json" <<EOF
{"skill_id":"skill-1","release_id":"release-1","version":"1.2.3","origin":null,"canonical_hash":"$hash","integrity":{"valid":true},"manifest":{"sha256":"$hash","files":[{"path":"SKILL.md","bytes":$(printf %s "$skill" | wc -c | tr -d ' '),"sha256":"$skill_hash"},{"path":"references/guide.md","bytes":$(printf %s "$reference" | wc -c | tr -d ' '),"sha256":"$reference_hash"}]},"files":[{"path":"SKILL.md","bytes_base64":"$skill_b64","kind":"file"},{"path":"references/guide.md","bytes_base64":"$reference_b64","kind":"file"}]}
EOF
export ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/artifact.json"
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(jq -cn --arg hash "$hash" '{operationId:"operation-1",skillId:"skill-1",releaseId:"release-1",runtime:"claude",target:"claude:global",expectedHash:$hash,executionToken:"test-token"}')"

allye_detect() { [ "$1" = "claude" ]; }
preflight_ok() {
  [ "$2" = "claude" ]
  jq -e --arg hash "$hash" '.runtime == "claude" and .releaseId == "release-1" and .expectedHash == $hash' <<<"$ALLYE_DISTRIBUTION_CONTEXT_JSON" >/dev/null
  printf 'preflight\n' >> "$CALLS"
}
allye_distribution_preflight() { preflight_ok "$@"; }
allye_distribution_report() {
  local action="$1" runtime="$3" target="$HOME/.claude/skills/allye" manifest
  [ "$runtime" = "claude" ] || return 1
  printf '%s\n' "$action" >> "$CALLS"
  if [ "$action" = complete ]; then
    [ "$(canonicalTreeHash "$target")" = "$hash" ]
    jq -e --arg hash "$hash" '.skill_id == "skill-1" and .release_id == "release-1" and .canonical_hash == $hash and .runtime == "claude"' "$target/.allye-artifact.json" >/dev/null
    manifest=$(readManifest claude)
    jq -e --arg path "$target" --arg hash "$hash" '.version == 1 and any(.artifacts[]; .path == $path and .skillId == "skill-1" and .releaseId == "release-1" and .hash == $hash)' <<<"$manifest" >/dev/null
  fi
}

# API lifecycle/compatibility blocks happen before staging or any local path.
original_home="$HOME"
export HOME="$TMP/blocked-home"
allye_distribution_preflight() { return 1; }
if allye_install claude; then exit 1; fi
test ! -e "$HOME/.claude/skills/allye"
test ! -e "$HOME/.claude.json"
test ! -e "$HOME/.claude/settings.json"
export HOME="$original_home"
allye_distribution_preflight() { preflight_ok "$@"; }

# The physical Claude path is adapter-owned; shared MCP/hooks must remain untouched.
mkdir -p "$HOME/.claude"
printf '{"mcpServers":{"user":{"url":"https://user.example.test"}}}' > "$HOME/.claude.json"
printf '{"hooks":{"UserHook":[]}}' > "$HOME/.claude/settings.json"
cp "$HOME/.claude.json" "$TMP/claude.json.before"
cp "$HOME/.claude/settings.json" "$TMP/settings.before"

allye_install claude
TARGET="$HOME/.claude/skills/allye"
test -f "$TARGET/SKILL.md"
test -f "$TARGET/references/guide.md"
cmp <(printf %s "$skill") "$TARGET/SKILL.md"
cmp <(printf %s "$reference") "$TARGET/references/guide.md"
cmp "$TMP/claude.json.before" "$HOME/.claude.json"
cmp "$TMP/settings.before" "$HOME/.claude/settings.json"
grep -Fxq preflight "$CALLS"; grep -Fxq complete "$CALLS"

# A pending retry with an intact receipt is idempotent: no tree/manifest rewrite.
cp -a "$TARGET" "$TMP/intact-tree"
cp "$(manifestPath claude)" "$TMP/intact-manifest"
: > "$CALLS"
allye_install claude
diff -r "$TMP/intact-tree" "$TARGET"
cmp "$TMP/intact-manifest" "$(manifestPath claude)"
grep -Fxq complete "$CALLS"

# A locally edited owned tree requires an explicit decision; it is never overwritten.
printf 'local edit\n' > "$TARGET/SKILL.md"
cp "$TARGET/SKILL.md" "$TMP/local.before"
: > "$CALLS"
if allye_install claude; then exit 1; fi
cmp "$TMP/local.before" "$TARGET/SKILL.md"
! grep -Fxq complete "$CALLS"

# Missing Claude runtime is a diagnostic non-success and does not mutate layout/configuration.
cp "$HOME/.claude.json" "$TMP/claude.json.missing.before"
cp "$HOME/.claude/settings.json" "$TMP/settings.missing.before"
allye_detect() { return 1; }
: > "$CALLS"
if allye_install claude; then exit 1; fi
cmp "$TMP/claude.json.missing.before" "$HOME/.claude.json"
cmp "$TMP/settings.missing.before" "$HOME/.claude/settings.json"
grep -Fxq fail "$CALLS"

printf 'claude distribution: ok\n'
