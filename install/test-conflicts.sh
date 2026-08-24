#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/allye-conflicts.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home" SCRIPT_DIR="$ROOT" ADAPTERS_FILE="$ROOT/install/adapters.json" MCP_URL="https://mcp.example.test"
export ALLYE_MANIFEST_DIR="$TMP/manifests"
print_error(){ printf '%s\n' "$*" >&2; }
print_warning(){ :; }
print_success(){ :; }
print_step(){ :; }
source "$ROOT/install/lib.sh"

for runtime in claude codex opencode pi; do
  target="$TMP/$runtime/managed-target"
  expected_content="release-$runtime"
  expected_hash=$(printf %s "$expected_content" | sha256sum | cut -d' ' -f1)
  expected=$(jq -cn --arg path "$target" --arg skill "skill-$runtime" --arg release "release-$runtime" --arg hash "$expected_hash" '{path:$path,skillId:$skill,releaseId:$release,contentHash:$hash}')

  # Missing targets are eligible, and recording ownership emits only public identity/hash metadata.
  missing=$(classifyConflict "$runtime" "$expected")
  jq -e '.classification == "missing" and .allowed == true and .code == "CREATE_ALLOWED"' <<<"$missing" >/dev/null
  mkdir -p "$(dirname "$target")"; printf %s "$expected_content" > "$target"
  recordManagedArtifact "$runtime" "$expected"
  readManifest "$runtime" | jq -e --arg path "$target" --arg hash "$expected_hash" '.artifacts[] | select(.path == $path and .skillId == "skill-'"$runtime"'" and .releaseId == "release-'"$runtime"'" and .hash == $hash and (.updatedAt | type == "string"))' >/dev/null
  if jq -e '.. | objects | keys[]? | test("^(pat|token|secret|password|authorization)$"; "i")' "$(manifestPath "$runtime")" >/dev/null; then exit 1; fi

  # Exact owned bytes may update; local changes never become an automatic overwrite.
  intact=$(classifyConflict "$runtime" "$expected")
  jq -e '.classification == "owned-intact" and .allowed == true and .code == "UPDATE_ALLOWED"' <<<"$intact" >/dev/null
  printf 'local modification' > "$target"
  modified=$(classifyConflict "$runtime" "$expected")
  jq -e '.classification == "owned-modified" and .allowed == false and .code == "CONFLICT_MODIFIED"' <<<"$modified" >/dev/null
  test "$(<"$target")" = 'local modification'

  # A different recorded skill owns the destination; an unrecorded file is not adopted.
  foreign=$(jq -cn --arg path "$target" --arg hash "$expected_hash" '{path:$path,skillId:"other-skill",releaseId:"other-release",contentHash:$hash}')
  recordManagedArtifact "$runtime" "$foreign"
  conflict=$(classifyConflict "$runtime" "$expected")
  jq -e '.classification == "foreign" and .allowed == false and .code == "CONFLICT_FOREIGN"' <<<"$conflict" >/dev/null

  unmanaged="$TMP/$runtime/unmanaged-target"; printf 'user content' > "$unmanaged"
  unowned=$(jq -cn --arg path "$unmanaged" --arg hash "$expected_hash" '{path:$path,skillId:"skill-'"$runtime"'",releaseId:"release-'"$runtime"'",contentHash:$hash}')
  decision=$(classifyConflict "$runtime" "$unowned")
  jq -e '.classification == "unmanaged" and .allowed == false and .code == "CONFLICT_UNMANAGED"' <<<"$decision" >/dev/null
  test "$(<"$unmanaged")" = 'user content'
done

# Atomic transaction failures never truncate user content. `after-backup` keeps
# a named recovery handle; all temporary staging paths are removed.
atomic_target="$TMP/atomic/user.json"; mkdir -p "$(dirname "$atomic_target")"; printf 'original' > "$atomic_target"
if ALLYE_INSTALL_FAILPOINT=before-commit atomicWrite "$atomic_target" 'replacement'; then exit 1; fi
test "$(<"$atomic_target")" = original
if find "$(dirname "$atomic_target")" -name '.allye-tx.*' -print -quit | grep -q .; then exit 1; fi
if ALLYE_INSTALL_FAILPOINT=after-backup atomicWrite "$atomic_target" 'replacement'; then exit 1; fi
test "$(<"$atomic_target")" = original
find "$(dirname "$atomic_target")" -name '*.allye.backup.*' -type f -print -quit | grep -q .
if find "$(dirname "$atomic_target")" -name '.allye-tx.*' -print -quit | grep -q .; then exit 1; fi
atomicWrite "$atomic_target" 'replacement'
test "$(<"$atomic_target")" = replacement

# A malformed user JSON document is a conflict, not an invitation to replace
# it with `{}`. Valid JSON remains eligible for the existing additive merge.
json_path="$HOME/.config/opencode/opencode.json"; mkdir -p "$(dirname "$json_path")"; printf '{broken' > "$json_path"
json_before=$(<"$json_path")
if write_mcp_json "$(allye_agent_json opencode)"; then exit 1; fi
test "$(<"$json_path")" = "$json_before"

# Real OpenCode writer: no context blocks, authorized creation records,
# repetition is idempotent, and a local edit/uninstall is preserved.
rm -f "$json_path"
if write_mcp_json "$(allye_agent_json opencode)"; then exit 1; fi
test ! -e "$json_path"
# Even a structural forged context cannot authorize a derived shared config.
export ALLYE_DISTRIBUTION_CONTEXT_JSON='{"skillId":"skill-opencode","releaseId":"release-opencode","runtime":"opencode","expectedHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
set +e; diagnostic=$(write_mcp_json "$(allye_agent_json opencode)" 2>&1); status=$?; set -e
[ "$status" -ne 0 ] || exit 1
printf '%s\n' "$diagnostic" | grep -Fq 'CONFLICT_UNMANAGED' || exit 1
test ! -e "$json_path"
set +e; diagnostic=$(allye_uninstall opencode 2>&1); status=$?; set -e
[ "$status" -ne 0 ] || exit 1
printf '%s\n' "$diagnostic" | grep -Fq 'DISTRIBUTION_REMOVE_OWNERSHIP_UNAVAILABLE' || exit 1
test ! -e "$json_path"

printf 'conflict ownership matrix: ok\n'
