#!/bin/bash
# Runs every docs-gate check (install/docs-gate/NN-*.sh, top level only, never
# fixtures/) in numeric order. Fails when any check fails or when none is found.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/install/docs-gate"

scripts=()
while IFS= read -r name; do
  [ -n "$name" ] && scripts+=("$name")
done < <(for f in "$DIR"/[0-9]*-*.sh; do [ -f "$f" ] && basename "$f"; done | sort -n)

if [ "${#scripts[@]}" -eq 0 ]; then
  echo "docs-gate: no checks found in install/docs-gate" >&2
  exit 1
fi

failed=0
for name in "${scripts[@]}"; do
  echo "docs-gate: $name"
  if ! bash "$DIR/$name"; then
    echo "docs-gate: FAIL $name" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "docs-gate: failed" >&2
  exit 1
fi
echo "docs-gate: ok (${#scripts[@]} checks)"
