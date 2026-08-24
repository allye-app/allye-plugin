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

# Option 2: all shared adapter configuration is unmanaged and fails closed.
for runtime in codex opencode pi; do
  before=$(find "$HOME" -type f -exec sha256sum {} + | sort)
  set +e; allye_install "$runtime" >"$TMP/$runtime.out" 2>&1; status=$?; set -e
  [ "$status" -ne 0 ] || exit 1
  grep -Fq 'CONFLICT_UNMANAGED' "$TMP/$runtime.out"
  after=$(find "$HOME" -type f -exec sha256sum {} + | sort); [ "$before" = "$after" ] || exit 1
  set +e; allye_uninstall "$runtime" >"$TMP/$runtime-uninstall.out" 2>&1; status=$?; set -e
  [ "$status" -ne 0 ] || exit 1
  grep -Fq 'DISTRIBUTION_REMOVE_OWNERSHIP_UNAVAILABLE' "$TMP/$runtime-uninstall.out"
done

# Pi package persistence is also a shared unmanaged path under Option 2.
test ! -e "$HOME/.pi/agent/settings.json"

rm "$TMP/bin/codex"
if allye_install codex; then
  printf '%s\n' 'missing Codex must not report success' >&2
  exit 1
fi
printf '%s\n' 'multi-runtime distribution adapters: ok'
