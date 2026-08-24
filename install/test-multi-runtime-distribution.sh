#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/allye-multi-runtime.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home/.codex" "$TMP/home/.config/opencode" "$TMP/home/.pi/agent" "$TMP/arbitrary" "$TMP/installed-package/packages/allye-pi/src" "$TMP/installed-package/skills"
cat > "$TMP/installed-package/package.json" <<'EOF'
{"name":"allye-pi","version":"1.7.1","pi":{"extensions":["./packages/allye-pi/src/index.ts"],"skills":["./skills"]}}
EOF
touch "$TMP/installed-package/packages/allye-pi/src/index.ts"
cat > "$TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TMP/bin/opencode" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TMP/bin/pi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ALLYE_PI_TEST_LOG:?}"
case "${1:-}" in
  install) printf '%s\n' "${2:?package source}" > "${ALLYE_PI_TEST_INSTALLED:?}"; printf 'install %s\n' "${2:?package source}" >> "${PI_ORDER_LOG:?}" ;;
  remove) rm -f "${ALLYE_PI_TEST_INSTALLED:?}" ;;
  list)
    source="${PI_LIST_SOURCE_OVERRIDE:-$(cat "${ALLYE_PI_TEST_INSTALLED:?}")}"
    printf '  %s\n    %s\n' "$source" "${ALLYE_PI_TEST_PACKAGE_ROOT:?}"
    ;;
  --version) printf 'pi 0.84.1\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/codex" "$TMP/bin/opencode" "$TMP/bin/pi"

export HOME="$TMP/home" PATH="$TMP/bin:$PATH" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json"
export MCP_URL="https://mcp.allye.app/mcp" ALLYE_PI_TEST_LOG="$TMP/pi.log" ALLYE_PI_TEST_INSTALLED="$TMP/pi-installed" ALLYE_PI_TEST_PACKAGE_ROOT="$TMP/installed-package" PI_ORDER_LOG="$TMP/pi-order.log"
print_error(){ printf '%s\n' "$*" >&2; }
print_warning(){ :; }
print_success(){ :; }
print_step(){ :; }
source "$ROOT/install/lib.sh"
# API distribution boundary is already covered by the disk lifecycle suite;
# this installer fixture asserts that Pi invokes that existing boundary only
# after validating the actual installed package root.
allye_distribution_preflight() { printf 'preflight %s\n' "$2" >> "$TMP/pi-order.log"; [ "$2" = "pi" ] && [ "$(jq -r '.runtime' <<<"$ALLYE_DISTRIBUTION_CONTEXT_JSON")" = "$2" ]; }
allye_distribution_report() { printf '%s %s %s\n' "$1" "$3" "${6:-}" >> "$TMP/pi-completion.log"; [ "${PI_REJECT_COMPLETE:-}" != 1 ]; }

cat > "$HOME/.codex/config.toml" <<'EOF'
[existing]
header = "preserved"
EOF
cp "$HOME/.codex/config.toml" "$TMP/codex-user.toml"
printf '%s\n' '# personal codex instruction' > "$HOME/.codex/AGENTS.md"
cat > "$HOME/.config/opencode/opencode.json" <<'EOF'
{"mcp":{"other":{"url":"https://other.test"}},"plugin":["existing","allye-opencode"]}
EOF

# A source lookup is independent of the caller's current directory.
(cd "$TMP/arbitrary" && allye_install codex)
grep -Fqx 'header = "preserved"' "$HOME/.codex/config.toml"
grep -Fqx '[mcp_servers.allye]' "$HOME/.codex/config.toml"
grep -Fqx '# personal codex instruction' "$HOME/.codex/AGENTS.md"
grep -Fq '# BEGIN ALLYE_INSTALLER_VERSION=1 CODEX AGENTS' "$HOME/.codex/AGENTS.md"

# An invalid instruction manifest is rejected before config or AGENTS mutation.
BAD_HOME="$TMP/bad-home"; mkdir -p "$BAD_HOME"; original_home="$HOME"; export HOME="$BAD_HOME"
bad_adapter=$(allye_agent_json codex | jq '.bootstrap.source = "missing/AGENTS.md"')
if allye_install_one "$bad_adapter"; then exit 1; fi
test ! -e "$HOME/.codex/config.toml"; test ! -e "$HOME/.codex/AGENTS.md"
export HOME="$original_home"

# A write failure after TOML staging restores the pre-install state.
ROLLBACK_HOME="$TMP/rollback-home"; mkdir -p "$ROLLBACK_HOME/.codex/AGENTS.md"; export HOME="$ROLLBACK_HOME"
if allye_install_one "$(allye_agent_json codex)" >"$TMP/rollback.out" 2>&1; then exit 1; fi
grep -Fq 'configuration was rolled back' "$TMP/rollback.out"
test ! -e "$HOME/.codex/config.toml"
export HOME="$original_home"

# Uninstall removes only owned TOML/AGENTS blocks; a subsequent install is clean.
allye_uninstall codex
grep -Fqx 'header = "preserved"' "$HOME/.codex/config.toml"
! grep -Fq '[mcp_servers.allye]' "$HOME/.codex/config.toml"
! grep -Fq 'ALLYE_INSTALLER_VERSION=1' "$HOME/.codex/config.toml"
! grep -Fq 'url = "https://mcp.allye.app/mcp"' "$HOME/.codex/config.toml"
! grep -Fq 'enabled = true' "$HOME/.codex/config.toml"
cmp "$TMP/codex-user.toml" "$HOME/.codex/config.toml"
grep -Fqx '# personal codex instruction' "$HOME/.codex/AGENTS.md"
! grep -Fq 'ALLYE_INSTALLER_VERSION=1 CODEX AGENTS' "$HOME/.codex/AGENTS.md"
allye_install codex
test "$(grep -c '# BEGIN ALLYE_INSTALLER_VERSION=1 CODEX AGENTS' "$HOME/.codex/AGENTS.md")" -eq 1

# Unpaired AGENTS delimiters are not safe to classify as installer-owned.
printf '%s\n' '# BEGIN ALLYE_INSTALLER_VERSION=1 CODEX AGENTS' >> "$HOME/.codex/AGENTS.md"
cp "$HOME/.codex/AGENTS.md" "$TMP/unpaired-agents.before"
if allye_uninstall codex; then exit 1; fi
cmp "$TMP/unpaired-agents.before" "$HOME/.codex/AGENTS.md"
sed -i '$d' "$HOME/.codex/AGENTS.md"

allye_install opencode
jq -e '.mcp.other.url == "https://other.test" and (.mcp.allye.url == "https://mcp.allye.app/mcp") and ([.plugin[] | select(. == "allye-opencode")] | length == 1)' "$HOME/.config/opencode/opencode.json" >/dev/null
allye_uninstall opencode
jq -e '.mcp.other.url == "https://other.test" and (.mcp.allye | not) and ([.plugin[] | select(. == "allye-opencode")] | length == 1)' "$HOME/.config/opencode/opencode.json" >/dev/null
allye_install opencode
jq -e '([.plugin[] | select(. == "allye-opencode")] | length == 1)' "$HOME/.config/opencode/opencode.json" >/dev/null

# Receipt reuses the canonical artifact + execution context and binds release,
# hash, Pi runtime version, package source, and declared package layout.
hash=$(printf 'pi receipt' | sha256sum | cut -d' ' -f1)
printf '{"release_id":"release-1","canonical_hash":"%s","integrity":{"valid":true},"manifest":{"sha256":"%s"}}\n' "$hash" "$hash" > "$TMP/artifact.json"
printf '{"operationId":"operation-1","releaseId":"release-1","runtime":"pi","expectedHash":"%s"}\n' "$hash" > "$TMP/context.json"
export ALLYE_CANONICAL_ARTIFACT_JSON="$TMP/artifact.json" ALLYE_DISTRIBUTION_CONTEXT_JSON="$(<"$TMP/context.json")"
allye_install pi
sed -n '1p' "$TMP/pi-order.log" | grep -Fqx 'preflight pi'
sed -n '2p' "$TMP/pi-order.log" | grep -Fqx 'install npm:allye-pi'
receipt=$(pi_distribution_receipt "$(allye_agent_json pi)" 'npm:allye-pi' "$TMP/installed-package")
jq -e '.releaseId == "release-1" and .canonicalHash != "" and .packageSource == "npm:allye-pi" and .packageVersion == "1.7.1" and (.packageManifestDigest | test("^[a-f0-9]{64}$")) and (.packageContentDigest | test("^[a-f0-9]{64}$")) and (.layoutIdentity | startswith("pi:manifest=package.json")) and (has("packagePath") | not)' <<<"$receipt" >/dev/null
grep -Fq 'complete pi {' "$TMP/pi-completion.log"
# Invalid execution context fails before another Pi package mutation.
bad_context=$(jq '.runtime = "codex"' "$TMP/context.json"); before_installs=$(grep -c '^install ' "$ALLYE_PI_TEST_LOG" || true)
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$bad_context"
if allye_install pi; then exit 1; fi
test "$(grep -c '^install ' "$ALLYE_PI_TEST_LOG" || true)" -eq "$before_installs"
export ALLYE_DISTRIBUTION_CONTEXT_JSON="$(<"$TMP/context.json")"
# A rejected completion restores the prior immutable Pi package version.
export PI_REJECT_COMPLETE=1
if allye_install pi; then exit 1; fi
unset PI_REJECT_COMPLETE
grep -Fqx 'install npm:allye-pi@1.7.1' "$ALLYE_PI_TEST_LOG"
allye_uninstall pi
grep -Fqx 'install npm:allye-pi' "$ALLYE_PI_TEST_LOG"
grep -Fqx 'list' "$ALLYE_PI_TEST_LOG"
grep -Fqx 'remove npm:allye-pi' "$ALLYE_PI_TEST_LOG"
test ! -e "$HOME/.pi/agent/settings.json"

# A listed but incompatible source is never accepted as Pi install evidence.
export PI_LIST_SOURCE_OVERRIDE='npm:allye-pi-incompatible'
if pi_installed_package_path 'npm:allye-pi' >/dev/null; then exit 1; fi
unset PI_LIST_SOURCE_OVERRIDE
# A malformed resolved package is removed rather than left as a partial install.
printf '{}' > "$TMP/installed-package/package.json"
if allye_install pi; then exit 1; fi
grep -Fqx 'remove npm:allye-pi' "$ALLYE_PI_TEST_LOG"

rm "$TMP/bin/codex"
if allye_install codex; then
  printf '%s\n' 'missing Codex must not report success' >&2
  exit 1
fi
printf '%s\n' 'multi-runtime distribution adapters: ok'
