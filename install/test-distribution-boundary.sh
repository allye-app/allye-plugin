#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json"
print_error(){ printf '%s\n' "$*" >&2; }; print_warning(){ :; }; print_success(){ :; }; print_step(){ :; }
source "$ROOT/install/lib.sh"
payload=$'---\nname: x\ndescription: x\n---'; hash=$(printf %s "$payload" | sha256sum | cut -d' ' -f1); bytes=$(printf %s "$payload" | base64 -w0); length=$(printf %s "$payload" | wc -c | tr -d ' ')
cat > "$TMP/artifact.json" <<EOF
{"release_id":"release-1","canonical_hash":"$hash","integrity":{"valid":true},"manifest":{"sha256":"$hash","files":[{"path":"SKILL.md","bytes":$length,"sha256":"$hash"}]},"files":[{"path":"SKILL.md","bytes_base64":"$bytes"}]}
EOF
node - "$hash" "$TMP/context.json" "$TMP/jwks.json" <<'NODE'
const { generateKeyPairSync, sign } = require('node:crypto'); const { writeFileSync } = require('node:fs');
const [hash, contextPath, jwksPath] = process.argv.slice(2); const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const b64 = (value) => Buffer.from(typeof value === 'string' ? value : JSON.stringify(value)).toString('base64url');
const header = { alg: 'RS256', kid: 'boundary-test' }; const payload = { typ: 'skill_distribution_execution', actor: 'actor-1', skillId: 'skill-1', distributionId: 'operation-1', releaseId: 'release-1', runtime: 'hermes', target: 'disk:allye', expectedHash: hash, exp: Math.floor(Date.now()/1000)+600 };
const signingInput = `${b64(header)}.${b64(payload)}`; const token = `${signingInput}.${sign('RSA-SHA256', Buffer.from(signingInput), privateKey).toString('base64url')}`;
writeFileSync(contextPath, JSON.stringify({ operationId: 'operation-1', skillId: 'skill-1', releaseId: 'release-1', runtime: 'hermes', target: 'disk:allye', expectedHash: hash, expiresAt: new Date(Date.now()+600000).toISOString(), executionToken: token }));
writeFileSync(jwksPath, JSON.stringify({ keys: [{ ...publicKey.export({ format:'jwk' }), kid:'boundary-test', use:'sig', alg:'RS256' }] }));
NODE
mkdir "$TMP/bin"
cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
 *'/jwks'*) cat "$JWKS";;
 *'/preflight'*) printf '{"data":{"operationId":"operation-1","status":"pending","runtime":"hermes","expectedHash":"%s"}}' "$HASH";;
 *'/complete'*) [ "${FAIL_COMPLETE:-}" != 1 ] || exit 22; printf '{"data":{"operationId":"operation-1","status":"succeeded","evidence":{"runtime":"hermes","observedHash":"%s","runtimeVersion":"hermes-installer/1","verifiedAt":"2026-08-18T12:00:00Z"}}}' "$HASH";;
 *'/fail'*) printf '{"data":{"status":"failed"}}';;
 *) exit 23;; esac
CURL
chmod +x "$TMP/bin/curl"; export PATH="$TMP/bin:$PATH" CALLS="$TMP/calls" JWKS="$TMP/jwks.json" HASH="$hash" ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/artifact.json"
# Context/JWS/preflight all happen before the physical tree exists.
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(<"$TMP/context.json")" ALLYE_API_URL=http://127.0.0.1:3001
install_skills_to_disk hermes
test -f "$HOME/.hermes/skills/allye/SKILL.md"; grep -q '/jwks' "$TMP/calls"; grep -q '/preflight' "$TMP/calls"; grep -q '/complete' "$TMP/calls"
# Tampered JWS is rejected before staging/publishing and retains the live tree.
: > "$TMP/calls"; good_context="$ALLYE_DISTRIBUTION_CONTEXT_JSON"; export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(jq '.executionToken |= . + "x"' <<<"$good_context")"
if install_skills_to_disk hermes; then exit 1; fi
test -f "$HOME/.hermes/skills/allye/SKILL.md"; ! grep -q '/preflight' "$TMP/calls"
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$good_context"
# Rejected completion restores the old physical tree and reports failure.
printf 'old\n' > "$HOME/.hermes/skills/allye/SKILL.md"; : > "$TMP/calls"
if FAIL_COMPLETE=1 install_skills_to_disk hermes; then exit 1; fi
grep -qx 'old' "$HOME/.hermes/skills/allye/SKILL.md"; grep -q '/fail' "$TMP/calls"
# Non-loopback HTTP is rejected before staging or any bearer request.
: > "$TMP/calls"; ALLYE_API_URL=http://example.test
if install_skills_to_disk hermes; then exit 1; fi
test ! -s "$TMP/calls"
printf 'distribution boundary lifecycle: ok\n'
