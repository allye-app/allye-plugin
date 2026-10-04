#!/bin/bash
# Guards the shared bootstrap text and every harness copy of it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/bootstrap/allye.md"
fail() { echo "FAIL: $*" >&2; exit 1; }

lines=$(wc -l < "$SRC")
[ "$lines" -lt 40 ] || fail "bootstrap/allye.md has $lines lines (max 39)"
for mode in 'launch <spec>' 'mission "<goal>"' '`blueprint`' 'blueprint --auto' dispatch repair optimize shield inspect survey; do
  grep -qF -- "$mode" "$SRC" || fail "bootstrap does not describe Bridge mode: $mode"
done
for tool in projects epics specs tasks team team_switch; do
  grep -qw -- "$tool" "$SRC" || fail "bootstrap does not mention MCP tool/action: $tool"
done
if grep -qiE 'work[ _-]?items?|boards?|sprints?' "$SRC"; then fail "bootstrap mentions a removed concept (work items/boards/sprints)"; fi

cmp -s "$SRC" "$ROOT/manifests/codex/AGENTS.md" || fail "manifests/codex/AGENTS.md is stale; run scripts/sync-bootstrap.sh"
echo "bootstrap: ok ($lines lines, Codex copy in sync)"
