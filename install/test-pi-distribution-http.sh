#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'kill "${SERVER_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.pi/agent" "$TMP/pkg/packages/allye-pi/src" "$TMP/pkg/skills"
cat > "$TMP/pkg/package.json" <<'EOF'
{"name":"allye-pi","version":"1.7.1","pi":{"extensions":["./packages/allye-pi/src/index.ts"],"skills":["./skills"]}}
EOF
touch "$TMP/pkg/packages/allye-pi/src/index.ts"
hash=$(printf 'pi-http-receipt' | sha256sum | cut -d' ' -f1)
printf '{"release_id":"release-1","canonical_hash":"%s","integrity":{"valid":true},"manifest":{"sha256":"%s"}}\n' "$hash" "$hash" > "$TMP/artifact.json"
cat > "$TMP/server.js" <<'NODE'
const http=require('node:http'),fs=require('node:fs'),crypto=require('node:crypto');
const [hash,dir]=process.argv.slice(2), {privateKey,publicKey}=crypto.generateKeyPairSync('rsa',{modulusLength:2048});
const b64=(v)=>Buffer.from(typeof v==='string'?v:JSON.stringify(v)).toString('base64url'); const h={alg:'RS256',kid:'pi-test'};
const p={typ:'skill_distribution_execution',actor:'actor-1',skillId:'skill-1',distributionId:'operation-1',releaseId:'release-1',runtime:'pi',target:'package:allye-pi',expectedHash:hash,exp:Math.floor(Date.now()/1000)+600};
const input=`${b64(h)}.${b64(p)}`; const token=`${input}.${crypto.sign('RSA-SHA256',Buffer.from(input),privateKey).toString('base64url')}`;
fs.writeFileSync(`${dir}/context.json`,JSON.stringify({operationId:'operation-1',skillId:'skill-1',releaseId:'release-1',runtime:'pi',target:'package:allye-pi',expectedHash:hash,executionToken:token}));
const send=(r,n,o)=>{r.writeHead(n,{'content-type':'application/json'});r.end(JSON.stringify(o));};
const server=http.createServer((req,res)=>{let body='';req.on('data',c=>body+=c);req.on('end',()=>{
 if(req.url.endsWith('/jwks')) return send(res,200,{keys:[{...publicKey.export({format:'jwk'}),kid:'pi-test',use:'sig',alg:'RS256'}]});
 if(req.url.endsWith('/preflight')) {fs.appendFileSync(`${dir}/events`,'preflight\n');return send(res,200,{data:{operationId:'operation-1',status:'pending',runtime:'pi',expectedHash:hash}});}
 if(req.url.endsWith('/complete')) {fs.appendFileSync(`${dir}/events`,'complete\n');const x=JSON.parse(body||'{}'),q=x.piPackage;if(fs.existsSync(`${dir}/reject`)||!q||q.releaseId!=='release-1'||q.canonicalHash!==hash||q.packagePath) return send(res,409,{error:'rejected'});return send(res,200,{data:{operationId:'operation-1',status:'succeeded',evidence:{runtime:'pi',observedHash:hash,runtimeVersion:x.runtimeVersion,verifiedAt:x.verifiedAt,piPackage:q}}});}
 send(res,404,{});});});server.listen(0,'127.0.0.1',()=>fs.writeFileSync(`${dir}/port`,String(server.address().port)));
NODE
node "$TMP/server.js" "$hash" "$TMP" & SERVER_PID=$!; for _ in $(seq 1 30); do [ -f "$TMP/port" ] && break; sleep .1; done
cat > "$TMP/bin/pi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$PI_LOG"
case "$1" in
 install) printf '%s\n' "$2" > "$PI_STATE"; printf 'install %s\n' "$2" >> "$EVENTS" ;;
 remove) rm -f "$PI_STATE"; printf 'remove\n' >> "$EVENTS" ;;
 list) printf '  %s\n    %s\n' "$(cat "$PI_STATE")" "$PI_ROOT" ;;
 --version) printf '0.84.1\n' ;;
 *) exit 1;; esac
EOF
chmod +x "$TMP/bin/pi"
export HOME="$TMP/home" PATH="$TMP/bin:$PATH" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json" MCP_URL=https://mcp.allye.app/mcp
export PI_LOG="$TMP/pi.log" PI_STATE="$TMP/state" PI_ROOT="$TMP/pkg" EVENTS="$TMP/events" ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/artifact.json" ALLYE_DISTRIBUTION_CONTEXT_JSON="$(<"$TMP/context.json")" ALLYE_API_URL="http://127.0.0.1:$(<"$TMP/port")"
print_error(){ printf '%s\n' "$*" >&2; }; print_warning(){ :; }; print_success(){ :; }; print_step(){ :; }
printf 'npm:unrelated\n' > "$PI_STATE"
source "$ROOT/install/lib.sh"
allye_install pi
grep -Fqx 'preflight' "$TMP/events"; grep -Fqx 'complete' "$TMP/events"; grep -Fq 'install npm:allye-pi' "$TMP/events"
# Context mismatch is rejected before the package manager mutates state.
before=$(grep -c '^install ' "$TMP/events"); export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(jq '.runtime="codex"' "$TMP/context.json")"; if allye_install pi; then exit 1; fi; test "$(grep -c '^install ' "$TMP/events")" -eq "$before"
# Completion rejection restores the verified prior immutable package source.
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(<"$TMP/context.json")"; touch "$TMP/reject"; if allye_install pi; then exit 1; fi; grep -Fqx 'install npm:allye-pi@1.7.1' "$TMP/events"
# The next operation must discover a restored version-pinned source and use it for a safe snapshot.
test "$(pi_installed_package_path 'npm:allye-pi')" = "$TMP/pkg"
pi_package_snapshot "$(allye_agent_json pi)" 'npm:allye-pi' "$TMP/pkg" | jq -e '.packageVersion == "1.7.1"' >/dev/null
# A homonymous package never satisfies the configured package identity.
printf 'npm:allye-pi-homonym@1.7.1\n' > "$PI_STATE"
if pi_installed_package_path 'npm:allye-pi' >/dev/null; then exit 1; fi
printf 'Pi HTTP distribution receipt: ok\n'
