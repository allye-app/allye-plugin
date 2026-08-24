#!/bin/bash
set -euo pipefail

# Smoke-test the Pi installer with a fake `pi` binary. This verifies that the
# installer delegates package persistence to Pi instead of editing settings.json.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/allye-pi-installer.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home/.pi/agent" "$TMP_DIR/installed-package/packages/allye-pi/src" "$TMP_DIR/installed-package/skills"
cat > "$TMP_DIR/installed-package/package.json" <<'EOF'
{"name":"allye-pi","version":"1.7.1","pi":{"extensions":["./packages/allye-pi/src/index.ts"],"skills":["./skills"]}}
EOF
touch "$TMP_DIR/installed-package/packages/allye-pi/src/index.ts"
cat > "$TMP_DIR/bin/pi" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "${ALLYE_PI_TEST_LOG:?}"
case "${1:-}" in
  list)
    printf '%s\n  %s\n' "$(cat "${ALLYE_PI_TEST_INSTALLED:?}")" "${ALLYE_PI_TEST_PACKAGE_ROOT:?}"
    ;;
  --version)
    printf 'pi 0.84.1\n'
    ;;
  install)
    printf '%s\n' "${2:?package source}" > "${ALLYE_PI_TEST_INSTALLED:?}"
    ;;
  remove)
    rm -f "${ALLYE_PI_TEST_INSTALLED:?}"
    ;;
  *)
    printf 'unexpected pi command: %s\n' "$*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$TMP_DIR/bin/pi"

export HOME="$TMP_DIR/home"
export PATH="$TMP_DIR/bin:$PATH"
export ALLYE_PI_TEST_LOG="$TMP_DIR/pi.log"
export ALLYE_PI_TEST_INSTALLED="$TMP_DIR/pi-installed"
export ALLYE_PI_TEST_PACKAGE_ROOT="$TMP_DIR/installed-package"
export SCRIPT_DIR="$REPO_ROOT"
export ADAPTERS_FILE="$REPO_ROOT/install/adapters.json"
export MCP_URL="https://mcp.allye.app/mcp"
print_step() { :; }
print_success() { :; }
print_warning() { :; }
print_error() { printf '%s\n' "$*" >&2; }

# Option 2: Pi's shared package/configuration path is unmanaged and must not
# be authorized by a local or absent context.
unset ALLYE_PI_INSTALL_SOURCE || true
source "$REPO_ROOT/install/lib.sh"
if allye_install pi; then exit 1; fi
if allye_uninstall pi; then exit 1; fi
test ! -e "$ALLYE_PI_TEST_INSTALLED"

# The installer must never create or rewrite Pi settings itself.
test ! -e "$HOME/.pi/agent/settings.json"

printf 'Pi installer smoke check passed\n'
