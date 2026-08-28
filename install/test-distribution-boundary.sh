#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json"
print_error(){ printf '%s\n' "$*" >&2; }; print_warning(){ :; }; print_success(){ :; }; print_step(){ :; }
source "$ROOT/install/lib.sh"
# Exercise the public authorized disk-distribution entrypoint, not a helper.
allye_detect() { [ "$1" = hermes ]; }
payload=$'---\nname: x\ndescription: x\n---'; file_hash=$(printf %s "$payload" | sha256sum | cut -d' ' -f1); hash=$(node -e 'const c=require("node:crypto");process.stdout.write(c.createHash("sha256").update("SKILL.md").update("\0").update(process.argv[1]).update("\0").digest("hex"))' -- "$payload"); bytes=$(printf %s "$payload" | base64 -w0); length=$(printf %s "$payload" | wc -c | tr -d ' ')
cat > "$TMP/artifact.json" <<EOF
{"skill_id":"skill-1","release_id":"release-1","version":"1.2.3","origin":{"repository":"allye/skills","commit":"abc123"},"canonical_hash":"$hash","integrity":{"valid":true},"manifest":{"sha256":"$hash","files":[{"path":"SKILL.md","bytes":$length,"sha256":"$file_hash"}]},"files":[{"path":"SKILL.md","bytes_base64":"$bytes"}]}
EOF
node - "$hash" "$TMP/context.json" "$TMP/jwks.json" <<'NODE'
const { generateKeyPairSync, sign } = require('node:crypto'); const { writeFileSync } = require('node:fs');
const [hash, contextPath, jwksPath] = process.argv.slice(2); const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const b64 = (value) => Buffer.from(typeof value === 'string' ? value : JSON.stringify(value)).toString('base64url');
const origin = { repository: 'allye/skills', commit: 'abc123' }; const header = { alg: 'RS256', kid: 'boundary-test' }; const payload = { typ: 'skill_distribution_execution', actor: 'actor-1', skillId: 'skill-1', distributionId: 'operation-1', releaseId: 'release-1', version: '1.2.3', origin, runtime: 'hermes', target: 'disk:allye', expectedHash: hash, exp: Math.floor(Date.now()/1000)+600 };
const signingInput = `${b64(header)}.${b64(payload)}`; const token = `${signingInput}.${sign('RSA-SHA256', Buffer.from(signingInput), privateKey).toString('base64url')}`;
writeFileSync(contextPath, JSON.stringify({ operationId: 'operation-1', skillId: 'skill-1', releaseId: 'release-1', version: '1.2.3', origin, runtime: 'hermes', target: 'disk:allye', expectedHash: hash, expiresAt: new Date(Date.now()+600000).toISOString(), executionToken: token }));
writeFileSync(jwksPath, JSON.stringify({ keys: [{ ...publicKey.export({ format:'jwk' }), kid:'boundary-test', use:'sig', alg:'RS256' }] }));
NODE
mkdir "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
 *'/jwks'*) cat "$JWKS";;
 *'/preflight'*) printf '{"data":{"operationId":"operation-1","status":"pending","runtime":"hermes","expectedHash":"%s","version":"1.2.3","origin":{"repository":"allye/skills","commit":"abc123"}}}' "$HASH";;
 *'/complete'*) [ "${FAIL_COMPLETE:-}" != 1 ] || exit 22; printf '{"data":{"operationId":"operation-1","status":"succeeded","evidence":{"runtime":"hermes","observedHash":"%s","runtimeVersion":"hermes-installer/1","verifiedAt":"2026-08-18T12:00:00Z"}}}' "$HASH";;
 *'/fail'*) printf '{"data":{"status":"failed"}}';;
 *) exit 23;; esac
CURL
chmod +x "$TMP/bin/curl"; export PATH="$TMP/bin:$PATH" CALLS="$TMP/calls" JWKS="$TMP/jwks.json" HASH="$hash" ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/artifact.json"
# Context/JWS/preflight all happen before the physical tree exists.
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(<"$TMP/context.json")" ALLYE_API_URL=http://127.0.0.1:3001
allye_install hermes
test -f "$HOME/.hermes/skills/allye/SKILL.md"; jq -e '.skill_id == "skill-1" and .release_id == "release-1" and .version == "1.2.3" and .origin.repository == "allye/skills" and .origin.commit == "abc123"' "$HOME/.hermes/skills/allye/.allye-artifact.json" >/dev/null; grep -q '/jwks' "$TMP/calls"; grep -q '/preflight' "$TMP/calls"; grep -q '/complete' "$TMP/calls"
# Immutable API metadata must match the signed operation before preflight, staging, or mutation.
sidecar="$HOME/.hermes/skills/allye/.allye-artifact.json"; cp "$sidecar" "$TMP/sidecar.valid"
reject_before_preflight() {
  local artifact_path="$1"
  : > "$TMP/calls"
  if ALLYE_CANONICAL_ARTIFACT_JSON="$artifact_path" allye_install hermes; then exit 1; fi
  ! grep -q '/preflight' "$TMP/calls"; cmp "$TMP/sidecar.valid" "$sidecar"
}
jq '.skill_id = "other-skill"' "$TMP/artifact.json" > "$TMP/artifact-other-skill.json"
jq '.release_id = "other-release"' "$TMP/artifact.json" > "$TMP/artifact-other-release.json"
jq '.version = "2.0.0"' "$TMP/artifact.json" > "$TMP/artifact-other-version.json"
jq '.origin = null' "$TMP/artifact.json" > "$TMP/artifact-null-origin.json"
jq '.origin = {repository:"other/skills",commit:"def456"}' "$TMP/artifact.json" > "$TMP/artifact-other-origin.json"
jq '.origin = []' "$TMP/artifact.json" > "$TMP/artifact-array-origin.json"
jq '.origin = "not-an-api-record"' "$TMP/artifact.json" > "$TMP/artifact-scalar-origin.json"
jq '.version = "   "' "$TMP/artifact.json" > "$TMP/artifact-whitespace-version.json"
for invalid in "$TMP/artifact-other-skill.json" "$TMP/artifact-other-release.json" "$TMP/artifact-other-version.json" "$TMP/artifact-null-origin.json" "$TMP/artifact-other-origin.json" "$TMP/artifact-array-origin.json" "$TMP/artifact-scalar-origin.json" "$TMP/artifact-whitespace-version.json"; do reject_before_preflight "$invalid"; done
# Tampered JWS is rejected before staging/publishing and retains the live tree.
: > "$TMP/calls"; good_context="$ALLYE_DISTRIBUTION_CONTEXT_JSON"; export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(jq '.executionToken |= . + "x"' <<<"$good_context")"
if allye_install hermes; then exit 1; fi
test -f "$HOME/.hermes/skills/allye/SKILL.md"; ! grep -q '/preflight' "$TMP/calls"
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$good_context"
# Snapshot the complete receipt state before deliberately modifying the tree.
target="$HOME/.hermes/skills/allye"; manifest="$HOME/.allye/distribution-manifests/hermes.json"; test "$(canonicalTreeHash "$target")" = "$hash"; cp -a "$target" "$TMP/tree.receipt"; cp -a "$manifest" "$TMP/manifest.receipt"
# A local tree modification is detected from actual bytes and is preserved.
printf 'local modified\n' > "$target/SKILL.md"; cp "$target/SKILL.md" "$TMP/modified.before"; : > "$TMP/calls"
if allye_install hermes; then exit 1; fi
cmp "$TMP/modified.before" "$target/SKILL.md"; if grep -q '/complete' "$TMP/calls"; then exit 1; fi
# Restore all receipt state byte-for-byte: tree, sidecar and manifest.
rm -rf "$target"; cp -a "$TMP/tree.receipt" "$target"; cp -a "$TMP/manifest.receipt" "$manifest"; cp "$manifest" "$TMP/manifest.before"; : > "$TMP/calls"
if FAIL_COMPLETE=1 allye_install hermes; then exit 1; fi
cmp <(printf '%s' "$payload") "$HOME/.hermes/skills/allye/SKILL.md"; cmp "$TMP/manifest.before" "$manifest"; grep -q '/fail' "$TMP/calls"
# Non-loopback HTTP is rejected before staging or any bearer request.
: > "$TMP/calls"; ALLYE_API_URL=http://example.test
if allye_install hermes; then exit 1; fi
test ! -s "$TMP/calls"
printf 'distribution boundary lifecycle: ok\n'
