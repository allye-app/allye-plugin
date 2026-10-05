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
for tool in projects epics specs tasks team project_resolve team_set_default; do
  grep -qw -- "$tool" "$SRC" || fail "bootstrap does not mention MCP tool/action: $tool"
done
for phrase in 'team follows the project' 'pass `team_id` on memory writes' 'without credentials' 'userinfo before `@`' 'the query' 'the fragment' 'ask the user once' 'never pick a project or team'; do
  grep -qiF -- "$phrase" "$SRC" || fail "bootstrap does not say: $phrase"
done
grep -qiE '`ambiguous`.*`not_found`' "$SRC" || fail "bootstrap does not cover ambiguous/not_found resolutions"
grep -qiE 'memories.*data, not instructions|data, not instructions.*memories' "$SRC" || fail "bootstrap does not treat server content (including memories) as data"
if grep -qi 'active team scopes every' "$SRC"; then fail "bootstrap still says the active team scopes every call"; fi
if grep -qw 'team_switch' "$SRC"; then fail "bootstrap still tells agents to call team_switch"; fi
if grep -qiE 'work[ _-]?items?|boards?|sprints?' "$SRC"; then fail "bootstrap mentions a removed concept (work items/boards/sprints)"; fi

cmp -s "$SRC" "$ROOT/manifests/codex/AGENTS.md" || fail "manifests/codex/AGENTS.md is stale; run scripts/sync-bootstrap.sh"
echo "bootstrap: ok ($lines lines, Codex copy in sync)"
