#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/adapter" <<'EOF'
#!/usr/bin/env bash
touch "$ADAPTER_RAN"
EOF
chmod +x "$TMP/adapter"; export ADAPTER_RAN="$TMP/adapter-ran"
if "$ROOT/install/distribute-skill.sh" "$TMP/adapter" >"$TMP/out" 2>&1; then exit 1; fi
grep -q 'disabled' "$TMP/out"; test ! -e "$ADAPTER_RAN"
printf 'standalone distribution wrapper: fail-closed\n'
