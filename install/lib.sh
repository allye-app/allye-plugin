# Allye installer — shared library
#
# Detection, the version marker, format writers, and the three verbs
# (allye_install, allye_uninstall, allye_status). install.sh sources this
# after Steps 1-3 (PAT, validation, skill seeding) and then dispatches.
#
# Every writer here is additive and idempotent: read the existing file,
# merge in our key/block, write back. Never truncate — these files hold
# the user's own MCP servers, plugins, and settings.

ALLYE_INSTALLER_VERSION=1
ADAPTERS_FILE="$SCRIPT_DIR/install/adapters.json"

# ─── Version marker ────────────────────────────────────────────────────────
# Every file this installer writes carries its version on a comment line (or,
# for pure-JSON files with no comment syntax, as a plain string field), in
# whatever form the file allows. `status` reads it back rather than keeping a
# registry, so a file edited or removed by hand reports honestly.

allye_marker_string() {
  printf 'ALLYE_INSTALLER_VERSION=%s' "$ALLYE_INSTALLER_VERSION"
}

allye_marker() {  # $1 = comment prefix
  printf '%s %s\n' "$1" "$(allye_marker_string)"
}

allye_installed_version() {  # $1 = path -> prints version, or nothing
  [ -f "$1" ] || return 1
  grep -o 'ALLYE_INSTALLER_VERSION=[0-9]\+' "$1" 2>/dev/null | head -1 | cut -d= -f2
}

# ─── Distribution ownership manifest ───────────────────────────────────────
# This is local evidence only: it never carries credentials or decides API
# authorization. A record is created only after a safe installer mutation.
ALLYE_MANIFEST_DIR="${ALLYE_MANIFEST_DIR:-$HOME/.allye/distribution-manifests}"

manifestPath() {  # $1 = runtime
  case "$1" in claude|codex|opencode|pi|cursor|gemini|hermes) ;; *) return 1 ;; esac
  printf '%s/%s.json\n' "$ALLYE_MANIFEST_DIR" "$1"
}

readManifest() {  # $1 = runtime -> normalized JSON manifest
  local runtime="$1" path
  path=$(manifestPath "$runtime") || return 1
  if [ ! -f "$path" ]; then
    jq -cn --arg runtime "$runtime" '{version:1,runtime:$runtime,artifacts:[]}'
    return 0
  fi
  jq -e --arg runtime "$runtime" '
    .version == 1 and .runtime == $runtime and (.artifacts | type == "array")
    and (([.artifacts[].path] | unique | length) == ([.artifacts[].path] | length))
    and all(.artifacts[]; (.path|type == "string") and (.skillId|type == "string") and (.releaseId|type == "string") and (.hash|type == "string" and test("^[a-fA-F0-9]{64}$")) and (.updatedAt|type == "string"))
  ' "$path" >/dev/null || return 1
  jq -cS . "$path"
}

hashFile() {  # $1 = existing non-symlink regular file
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  sha256sum "$1" | cut -d' ' -f1
}

apiManagedArtifact() { # $1 runtime, $2 path, $3 resulting content hash
  local runtime="$1" path="$2" hash="$3" context="${ALLYE_DISTRIBUTION_CONTEXT_JSON:-}"
  jq -e --arg runtime "$runtime" '(.skillId|type == "string" and length > 0) and (.releaseId|type == "string" and length > 0) and (.expectedHash|type == "string" and test("^[a-fA-F0-9]{64}$")) and .runtime == $runtime' >/dev/null <<<"$context" || return 1
  jq -cn --arg path "$path" --arg hash "$hash" --argjson context "$context" '{path:$path,skillId:$context.skillId,releaseId:$context.releaseId,contentHash:$hash}'
}

requireApiOwnershipContext() { # $1 runtime
  apiManagedArtifact "$1" /dev/null "$(printf x | sha256sum | cut -d' ' -f1)" >/dev/null || { print_error "CONFLICT_UNMANAGED: API-backed SkillRevision execution context is required; preserving configuration"; return 1; }
}

backup() {  # $1 = existing path, $2 = transaction id -> prints backup path
  local path="$1" tx_id="$2" backup_path
  [ -e "$path" ] || return 1
  backup_path="${path}.allye.backup.${tx_id}"
  cp -p "$path" "$backup_path" || return 1
  printf '%s\n' "$backup_path"
}

cleanupTransaction() {  # $1 = transaction temp path
  [ -z "${1:-}" ] || rm -f -- "$1"
}

# Same-filesystem transactional file replacement. The caller has already
# constructed/validated content; this routine preserves the old bytes until
# the single `mv` commit and exposes deterministic failpoints for tests.
atomicWrite() {  # $1 = target path, $2 = complete new content
  local path="$1" content="$2" dir temp tx_id backup_path=""
  dir=$(dirname "$path"); mkdir -p "$dir" || return 1
  temp=$(mktemp "$dir/.allye-tx.XXXXXX") || return 1
  tx_id=$(basename "$temp")
  if ! printf '%s' "$content" > "$temp"; then cleanupTransaction "$temp"; return 1; fi
  if [ "${ALLYE_INSTALL_FAILPOINT:-}" = "before-commit" ]; then
    cleanupTransaction "$temp"
    printf '%s\n' '{"status":"failed","code":"PARTIAL_WRITE_CLEANED","diagnostic":"Failpoint before commit; original preserved"}'
    return 1
  fi
  if [ -e "$path" ]; then backup_path=$(backup "$path" "$tx_id") || { cleanupTransaction "$temp"; return 1; }; fi
  if [ "${ALLYE_INSTALL_FAILPOINT:-}" = "after-backup" ]; then
    cleanupTransaction "$temp"
    printf '{"status":"failed","code":"PARTIAL_WRITE_CLEANED","backupPath":"%s","diagnostic":"Failpoint after backup; original preserved"}\n' "$backup_path"
    return 1
  fi
  if [ -e "$path" ]; then chmod --reference="$path" "$temp" && touch -r "$path" "$temp" || { cleanupTransaction "$temp"; return 1; }; fi
  if ! mv -f "$temp" "$path"; then cleanupTransaction "$temp"; printf '{"status":"failed","code":"PARTIAL_WRITE_CLEANED","backupPath":"%s"}\n' "$backup_path"; return 1; fi
  [ -z "$backup_path" ] || rm -f -- "$backup_path"
  printf '{"status":"written","targetPath":"%s"}\n' "$path"
}

writeManifest() {  # $1 = runtime, $2 = normalized manifest JSON
  local runtime="$1" manifest="$2" path dir temp
  path=$(manifestPath "$runtime") || return 1
  dir=$(dirname "$path")
  mkdir -p "$dir" || return 1
  jq -e . >/dev/null <<<"$manifest" || return 1
  atomicWrite "$path" "$(jq -cS . <<<"$manifest")" >/dev/null
}

recordManagedArtifact() {  # $1 = runtime, $2 = ManagedArtifact JSON
  local runtime="$1" artifact="$2" path updated manifest
  path=$(jq -r '.path // empty' <<<"$artifact")
  jq -e '(.path|type == "string" and length > 0) and (.skillId|type == "string" and length > 0) and (.releaseId|type == "string" and length > 0) and (.contentHash|type == "string" and test("^[a-fA-F0-9]{64}$"))' >/dev/null <<<"$artifact" || return 1
  updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  manifest=$(readManifest "$runtime") || return 1
  manifest=$(jq -c --arg path "$path" --arg updated "$updated" --argjson artifact "$artifact" '
    .artifacts = ((.artifacts | map(select(.path != $path))) + [{skillId:$artifact.skillId,releaseId:$artifact.releaseId,path:$artifact.path,hash:($artifact.contentHash|ascii_downcase),updatedAt:$updated}])
  ' <<<"$manifest") || return 1
  writeManifest "$runtime" "$manifest"
}

# Prints an explicit ConflictDecision. Callers must check `.allowed`; no
# existing file is implicitly adopted just because it has an Allye marker.
classifyConflict() {  # $1 = runtime, $2 = expected ManagedArtifact JSON
  local runtime="$1" expected="$2" path actual manifest owner expected_hash
  jq -e '(.path|type == "string" and length > 0) and (.skillId|type == "string" and length > 0) and (.releaseId|type == "string" and length > 0) and (.contentHash|type == "string" and test("^[a-fA-F0-9]{64}$"))' >/dev/null <<<"$expected" || return 1
  path=$(jq -r '.path' <<<"$expected")
  expected_hash=$(jq -r '.contentHash|ascii_downcase' <<<"$expected")
  if [ ! -e "$path" ]; then jq -cn --arg path "$path" '{classification:"missing",allowed:true,code:"CREATE_ALLOWED",path:$path}'; return 0; fi
  actual=$(hashFile "$path" 2>/dev/null || true)
  [ -n "$actual" ] || { jq -cn --arg path "$path" '{classification:"unmanaged",allowed:false,code:"CONFLICT_UNMANAGED",path:$path,diagnostic:"Target is not a regular managed artifact; preserving it"}'; return 0; }
  manifest=$(readManifest "$runtime") || return 1
  owner=$(jq -c --arg path "$path" '.artifacts[] | select(.path == $path)' <<<"$manifest" | tail -n1)
  if [ -z "$owner" ]; then jq -cn --arg path "$path" '{classification:"unmanaged",allowed:false,code:"CONFLICT_UNMANAGED",path:$path,diagnostic:"Target has no Allye ownership record; preserving it"}'; return 0; fi
  if [ "$(jq -r '.skillId' <<<"$owner")" != "$(jq -r '.skillId' <<<"$expected")" ] || [ "$(jq -r '.releaseId' <<<"$owner")" != "$(jq -r '.releaseId' <<<"$expected")" ]; then
    jq -cn --arg path "$path" --arg owner "$(jq -r '.skillId' <<<"$owner")" '{classification:"foreign",allowed:false,code:"CONFLICT_FOREIGN",path:$path,diagnostic:("Target is owned by skill " + $owner + "; preserving it")}'; return 0
  fi
  if [ "$(jq -r '.hash|ascii_downcase' <<<"$owner")" = "$actual" ] && [ "$actual" = "$expected_hash" ]; then
    jq -cn --arg path "$path" '{classification:"owned-intact",allowed:true,code:"UPDATE_ALLOWED",path:$path}'; return 0
  fi
  jq -cn --arg path "$path" '{classification:"owned-modified",allowed:false,code:"CONFLICT_MODIFIED",path:$path,diagnostic:"Target differs from the owned hash; preserving local modification"}'
}

ownershipAwareWrite() { # shared configs are never canonical API artifacts
  print_error "CONFLICT_UNMANAGED: shared $1 configuration has no API-backed ownership artifact; preserving $2"
  return 1
}

# Canonical disk artifacts are the sole directory ownership boundary. The
# sidecar is written from the already preflight-verified API artifact, never
# accepted as authority by itself.
canonicalTreeHash() { # $1 tree; excludes installer sidecar and rejects symlinks
  node - "$1" <<'NODE'
const {createHash}=require('node:crypto'),{readdirSync,readFileSync,lstatSync}=require('node:fs'),{join,relative}=require('node:path');
const root=process.argv[2], files=[]; const walk=d=>{for(const n of readdirSync(d)){const p=join(d,n),r=relative(root,p); if(r==='.allye-artifact.json')continue; const s=lstatSync(p); if(s.isSymbolicLink()||!s.isFile()&&!s.isDirectory())process.exit(1); if(s.isDirectory())walk(p);else files.push([r,p]);}}; walk(root); const h=createHash('sha256'); for(const [r,p] of files.sort((a,b)=>a[0].localeCompare(b[0]))){h.update(r).update('\0').update(readFileSync(p)).update('\0');} process.stdout.write(h.digest('hex'));
NODE
}
classifyCanonicalArtifact() { # $1 runtime, $2 target dir, $3 API-backed ManagedArtifact
  local runtime="$1" target="$2" expected="$3" marker manifest row actual_hash stored_hash
  [ ! -e "$target" ] && { jq -cn '{classification:"missing",allowed:true,code:"CREATE_ALLOWED"}'; return 0; }
  [ ! -L "$target" ] && [ -d "$target" ] || { jq -cn '{classification:"unmanaged",allowed:false,code:"CONFLICT_UNMANAGED",diagnostic:"Artifact target is not a regular directory"}'; return 0; }
  marker="$target/.allye-artifact.json"; [ -f "$marker" ] && [ ! -L "$marker" ] || { jq -cn '{classification:"unmanaged",allowed:false,code:"CONFLICT_UNMANAGED",diagnostic:"Artifact has no safe ownership sidecar"}'; return 0; }
  manifest=$(readManifest "$runtime") || { print_error "CONFLICT_UNMANAGED: invalid or duplicate ownership manifest"; return 1; }
  row=$(jq -c --arg path "$target" '.artifacts[] | select(.path == $path)' <<<"$manifest")
  [ -n "$row" ] || { jq -cn '{classification:"unmanaged",allowed:false,code:"CONFLICT_UNMANAGED",diagnostic:"Artifact has no ownership record"}'; return 0; }
  [ "$(jq -r '.skillId' <<<"$row")" = "$(jq -r '.skillId' <<<"$expected")" ] || { jq -cn '{classification:"foreign",allowed:false,code:"CONFLICT_FOREIGN"}'; return 0; }
  stored_hash=$(jq -r '.hash' <<<"$row"); actual_hash=$(canonicalTreeHash "$target") || { jq -cn '{classification:"owned-modified",allowed:false,code:"CONFLICT_MODIFIED"}'; return 0; }
  if [ "$(jq -r '.canonical_hash // empty' "$marker")" != "$stored_hash" ] || [ "$actual_hash" != "$stored_hash" ]; then jq -cn '{classification:"owned-modified",allowed:false,code:"CONFLICT_MODIFIED"}'; return 0; fi
  # Same owner with a new API release is an authorized upgrade only after the
  # old receipt/tree has passed the integrity check above.
  jq -cn '{classification:"owned-intact",allowed:true,code:"UPDATE_ALLOWED"}'
}

# A retry is idempotent only when the complete on-disk receipt still matches
# the API-authorized immutable artifact. The manifest is evidence, never the
# authorization source; the preflight must already have validated the context.
canonicalArtifactReceiptMatches() { # $1 runtime, $2 target dir, $3 API-backed ManagedArtifact
  local runtime="$1" target="$2" expected="$3" marker manifest row expected_hash
  [ -d "$target" ] && [ ! -L "$target" ] || return 1
  marker="$target/.allye-artifact.json"
  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  expected_hash=$(jq -r '.contentHash|ascii_downcase' <<<"$expected") || return 1
  manifest=$(readManifest "$runtime") || return 1
  row=$(jq -c --arg path "$target" '.artifacts[] | select(.path == $path)' <<<"$manifest")
  [ -n "$row" ] || return 1
  jq -e --arg release "$(jq -r '.releaseId' <<<"$expected")" --arg hash "$expected_hash" --arg runtime "$runtime" '
    .release_id == $release and .canonical_hash == $hash and .runtime == $runtime
  ' "$marker" >/dev/null || return 1
  jq -e --arg skill "$(jq -r '.skillId' <<<"$expected")" --arg release "$(jq -r '.releaseId' <<<"$expected")" --arg hash "$expected_hash" '
    .skillId == $skill and .releaseId == $release and (.hash|ascii_downcase) == $hash
  ' <<<"$row" >/dev/null || return 1
  [ "$(canonicalTreeHash "$target")" = "$expected_hash" ]
}

# ─── Helpers ────────────────────────────────────────────────────────────────

expand_home() {  # $1 = path, possibly starting with ~
  case "$1" in
    "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
    "~") printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

allye_agent_json() {  # $1 = agent id -> prints its adapter object, or empty
  jq -c --arg id "$1" '.agents[] | select(.id == $id)' "$ADAPTERS_FILE"
}

allye_detect() {  # $1 = agent id -> 0 if present on this machine
  local aj cmd dir
  aj=$(allye_agent_json "$1")
  [ -n "$aj" ] || return 1
  cmd=$(echo "$aj" | jq -r '.detect.command // empty')
  dir=$(echo "$aj" | jq -r '.detect.dir // empty')
  if [ -n "$cmd" ] && command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$dir" ]; then
    dir=$(expand_home "$dir")
    [ -d "$dir" ] && return 0
  fi
  return 1
}

# Generic YAML section helpers. There is no YAML parser in the dependency
# budget (Bash/curl/jq only), so these only handle the simple, consistently
# 2-space-indented shape Hermes actually uses — not arbitrary YAML.

yaml_ensure_top_key() {  # $1 = path, $2 = "key:" line
  local path="$1" line="$2"
  if ! grep -qxF "$line" "$path" 2>/dev/null; then
    { echo ""; echo "$line"; } >> "$path"
  fi
}

# Insert (possibly multi-line) $3 as the last child of the section whose
# header line is $2, i.e. right before the next line at or above that
# header's indentation, or at EOF if the section runs to the end of file.
yaml_append_in_section() {  # $1 = path, $2 = header line, $3 = insert text
  local path="$1" target="$2" insert="$3"
  awk -v target="$target" -v insert="$insert" '
    function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
    BEGIN { in_section = 0; done = 0; target_indent = -1; blanks = "" }
    {
      if (!done && $0 == target) {
        print
        in_section = 1
        target_indent = indent_of($0)
        next
      }
      if (in_section && !done) {
        if ($0 ~ /^[ \t]*$/) {
          blanks = blanks $0 "\n"
          next
        }
        cur_indent = indent_of($0)
        if (cur_indent <= target_indent) {
          print insert
          in_section = 0
          done = 1
          printf "%s", blanks
          blanks = ""
        } else {
          printf "%s", blanks
          blanks = ""
        }
      }
      print
    }
    END {
      if (in_section && !done) {
        print insert
        printf "%s", blanks
      }
    }
  ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"
}

# Remove the line matching $2 and everything indented under it (its
# children) — the inverse of yaml_append_in_section's insertion.
yaml_remove_block() {  # $1 = path, $2 = header line
  local path="$1" target="$2"
  awk -v target="$target" '
    function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
    BEGIN { skip = 0; ti = -1 }
    {
      if (!skip && $0 == target) { skip = 1; ti = indent_of($0); next }
      if (skip) {
        if ($0 ~ /^[ \t]*$/) next
        if (indent_of($0) > ti) next
        skip = 0
      }
      print
    }
  ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"
}

yaml_remove_line() {  # $1 = path, $2 = exact line
  local path="$1" line="$2"
  [ -f "$path" ] || return 0
  grep -vxF "$line" "$path" > "$path.allye.tmp" 2>/dev/null && mv "$path.allye.tmp" "$path"
}

# Set (or insert) a 2-space-indented scalar child of $2 ("<key>:") to $4,
# replacing an existing "  <key>: ..." line anywhere in the file or
# appending one as the last child of the section if none exists yet.
yaml_set_scalar() {  # $1 = path, $2 = section header ("memory:"), $3 = key, $4 = value
  local path="$1" section="$2" key="$3" value="$4"
  yaml_ensure_top_key "$path" "$section"
  if grep -q "^  ${key}:" "$path" 2>/dev/null; then
    awk -v key="$key" -v value="$value" '
      $0 ~ "^  " key ":" { print "  " key ": " value; next }
      { print }
    ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"
  else
    yaml_append_in_section "$path" "$section" "  ${key}: ${value}"
  fi
}

yaml_get_scalar() {  # $1 = path, $2 = key -> prints the value of "  <key>: ..." or nothing
  local path="$1" key="$2"
  [ -f "$path" ] || return 0
  awk -v key="$key" '
    $0 ~ "^  " key ":" {
      line = $0
      sub("^  " key ":[ \t]*", "", line)
      print line
      exit
    }
  ' "$path"
}

# List the direct 2-space-indented child keys of $2 (e.g. the platform names
# under "platform_toolsets:"), one per line.
list_yaml_child_keys() {  # $1 = path, $2 = parent header line
  local path="$1" parent="$2"
  [ -f "$path" ] || return 0
  awk -v parent="$parent" '
    function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
    BEGIN { in_section = 0; pi = -1 }
    {
      if (!in_section && $0 == parent) { in_section = 1; pi = indent_of($0); next }
      if (in_section) {
        if ($0 ~ /^[ \t]*$/) next
        ci = indent_of($0)
        if (ci <= pi) { in_section = 0; next }
        if (ci == pi + 2 && $0 ~ /:[ \t]*$/) {
          line = $0
          sub(/^[ \t]+/, "", line)
          sub(/:[ \t]*$/, "", line)
          print line
        }
      }
    }
  ' "$path"
}

yaml_list_contains() {  # $1 = path, $2 = header line (e.g. "  cli:"), $3 = item
  local path="$1" header="$2" item="$3"
  [ -f "$path" ] || return 1
  awk -v header="$header" -v item="$item" '
    function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
    BEGIN { in_section = 0; hi = -1; found = 0 }
    {
      if (!in_section && $0 == header) { in_section = 1; hi = indent_of($0); next }
      if (in_section) {
        if ($0 ~ /^[ \t]*$/) next
        ci = indent_of($0)
        if (ci <= hi) { in_section = 0; next }
        line = $0
        sub(/^[ \t]+-[ \t]+/, "", line)
        if (line == item) { found = 1 }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$path"
}

yaml_list_remove_item() {  # $1 = path, $2 = header line, $3 = item
  local path="$1" header="$2" item="$3"
  [ -f "$path" ] || return 0
  awk -v header="$header" -v item="$item" '
    function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
    BEGIN { in_section = 0; hi = -1 }
    {
      if (!in_section && $0 == header) { in_section = 1; hi = indent_of($0); print; next }
      if (in_section) {
        if ($0 ~ /^[ \t]*$/) { print; next }
        ci = indent_of($0)
        if (ci <= hi) { in_section = 0; print; next }
        line = $0
        sub(/^[ \t]+-[ \t]+/, "", line)
        if (line == item) next
        print
        next
      }
      print
    }
  ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"
}

yaml_list_add_item() {  # $1 = path, $2 = header line, $3 = item
  local path="$1" header="$2" item="$3" lead
  if yaml_list_contains "$path" "$header" "$item"; then
    return 0
  fi
  lead="${header%%[^ ]*}"
  yaml_append_in_section "$path" "$header" "${lead}  - ${item}"
}

# ─── Format writers ─────────────────────────────────────────────────────────
# Each reads the existing file, merges in our key/block, and writes back.
# Running install twice must produce a byte-identical file.

write_mcp_json() {  # $1 = adapter json
  local aj="$1" path key entry content array_path array_val plugin_added=false runtime
  runtime=$(echo "$aj" | jq -r '.id')
  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  key=$(echo "$aj" | jq -r '.mcp.key')

  mkdir -p "$(dirname "$path")"
  if [ -f "$path" ]; then
    content=$(cat "$path") || return 1
    if ! echo "$content" | jq -e . >/dev/null 2>&1; then
      print_error "Invalid JSON at $path; preserving user configuration"
      return 1
    fi
  else
    content='{}'
  fi

  # Preserve whether the plugin list entry was originally installer-owned;
  # recomputing this from the current list would make a repeat appear modified.
  plugin_added=$(echo "$content" | jq -r --arg key "$key" '(getpath(($key | split("."))) | ._allye_installer_plugin_added) == true')
  array_path=$(echo "$aj" | jq -r '.mcp.array_merge.path // empty')
  if [ -n "$array_path" ]; then
    array_val=$(echo "$aj" | jq -r '.mcp.array_merge.value')
    if ! echo "$content" | jq -e --arg p "$array_path" --arg v "$array_val" '((getpath([$p]) // []) | index($v)) != null' >/dev/null; then
      plugin_added=true
    fi
  fi
  entry=$(echo "$aj" | jq -c '.mcp.entry' | sed "s#{{MCP_URL}}#$MCP_URL#g")
  entry=$(echo "$entry" | jq --arg m "$(allye_marker_string)" --argjson added "$plugin_added" '. + {_allye_installer: $m, _allye_installer_plugin_added: $added}')
  content=$(echo "$content" | jq --argjson entry "$entry" --arg key "$key" \
    'setpath(($key | split(".")); $entry)')

  if [ -n "$array_path" ]; then
    content=$(echo "$content" | jq --arg p "$array_path" --arg v "$array_val" \
      'setpath([$p]; ((getpath([$p]) // []) | if index($v) then . else . + [$v] end))')
  fi

  content=$(printf '%s\n' "$content" | jq '.') || return 1
  ownershipAwareWrite "$runtime" "$path" "$content"
}

remove_mcp_toml_section() {  # $1 path, $2 key; preserve all non-owned TOML bytes
  local path="$1" key="$2" marker="$(allye_marker '#')"
  [ -f "$path" ] || return 0
  awk -v marker="$marker" -v header="[$key]" '
    function flush_blank() { if (held_blank) { print ""; held_blank = 0 } }
    $0 == marker { held_blank = 0; pending = 1; next }
    pending && $0 == header { skip = 1; pending = 0; next }
    pending { flush_blank(); print marker; pending = 0 }
    skip && /^\[/ { skip = 0 }
    skip { next }
    $0 == "" { if (held_blank) print ""; held_blank = 1; next }
    { flush_blank(); print }
    END { if (pending) print marker; else flush_blank() }
  ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"
}

write_mcp_toml() {  # $1 = adapter json
  local aj="$1" path key block marker
  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  key=$(echo "$aj" | jq -r '.mcp.key')
  block=$(echo "$aj" | jq -r '.mcp.block' | sed "s#{{MCP_URL}}#$MCP_URL#g")
  marker=$(allye_marker '#')

  mkdir -p "$(dirname "$path")"
  touch "$path"

  if grep -qF "$marker" "$path" 2>/dev/null; then
    return 0
  fi

  remove_mcp_toml_section "$path" "$key"

  {
    echo ""
    echo "$marker"
    echo "$block"
  } >> "$path"
}

write_mcp_yaml_block() {  # $1 = adapter json
  local aj="$1" path top_key block marker_str
  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  top_key=$(echo "$aj" | jq -r '.mcp.key' | cut -d. -f1)
  block=$(echo "$aj" | jq -r '.mcp.block' | sed "s#{{MCP_URL}}#$MCP_URL#g")
  marker_str=$(allye_marker_string)

  mkdir -p "$(dirname "$path")"
  touch "$path"

  if grep -qF "$marker_str" "$path" 2>/dev/null; then
    return 0
  fi

  yaml_ensure_top_key "$path" "${top_key}:"
  yaml_append_in_section "$path" "${top_key}:" "$block
    # $marker_str"
}

# ─── Agent config (Hermes: disable competing engines) ──────────────────────
# An adapter's optional "config" block turns off toolsets the agent has that
# Allye replaces. Every change is merged, never replacing a list the user
# built themselves, and every change is recorded under an "allye_previous:"
# key in the same file so uninstall can put it back.

apply_agent_config() {  # $1 = agent id
  local id="$1" aj config path
  aj=$(allye_agent_json "$id")
  config=$(echo "$aj" | jq -c '.config // empty')
  [ -n "$config" ] || return 0

  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  mkdir -p "$(dirname "$path")"
  touch "$path"

  apply_config_set "$path" "$config"
  apply_config_toolsets "$path" "$config"
}

apply_config_set() {  # $1 = path, $2 = config json
  local path="$1" config="$2" entry dotted top nested value prev
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    dotted=$(echo "$entry" | jq -r '.key')
    value=$(echo "$entry" | jq -r '.value')
    top=$(echo "$dotted" | cut -d. -f1)
    nested=$(echo "$dotted" | cut -d. -f2-)

    if [ -z "$(yaml_get_scalar "$path" "$dotted")" ]; then
      prev=$(yaml_get_scalar "$path" "$nested")
      [ -n "$prev" ] || prev="__absent__"
      yaml_set_scalar "$path" "allye_previous:" "$dotted" "$prev"
    fi

    yaml_set_scalar "$path" "${top}:" "$nested" "$value"
  done < <(echo "$config" | jq -c '.set // {} | to_entries[]')
}

apply_config_toolsets() {  # $1 = path, $2 = config json
  local path="$1" config="$2" platforms plat header item removed_items existing recorded

  platforms=$(list_yaml_child_keys "$path" "platform_toolsets:")
  [ -n "$platforms" ] || return 0

  while IFS= read -r plat; do
    [ -n "$plat" ] || continue
    header="  ${plat}:"

    recorded=$(yaml_get_scalar "$path" "toolsets_removed.${plat}")
    if [ -z "$recorded" ]; then
      removed_items=""
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        if yaml_list_contains "$path" "$header" "$item"; then
          yaml_list_remove_item "$path" "$header" "$item"
          removed_items="${removed_items:+${removed_items},}${item}"
        fi
      done < <(echo "$config" | jq -r '.toolsets_remove // [] | .[]')
      yaml_set_scalar "$path" "allye_previous:" "toolsets_removed.${plat}" "\"${removed_items}\""
    fi

    recorded=$(yaml_get_scalar "$path" "toolsets_added.${plat}")
    if [ -z "$recorded" ]; then
      existing="existing"
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        if yaml_list_contains "$path" "$header" "$item"; then
          :
        else
          yaml_list_add_item "$path" "$header" "$item"
          existing="new"
        fi
      done < <(echo "$config" | jq -r '.toolsets_add // [] | .[]')
      yaml_set_scalar "$path" "allye_previous:" "toolsets_added.${plat}" "\"${existing}\""
    fi
  done <<< "$platforms"
}

revert_agent_config() {  # $1 = agent id
  local id="$1" aj config path
  aj=$(allye_agent_json "$id")
  config=$(echo "$aj" | jq -c '.config // empty')
  [ -n "$config" ] || return 0

  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  [ -f "$path" ] || return 0

  revert_config_toolsets "$path" "$config"
  revert_config_set "$path" "$config"

  yaml_remove_block "$path" "allye_previous:"
}

revert_config_set() {  # $1 = path, $2 = config json
  local path="$1" config="$2" entry dotted top nested prev value
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    dotted=$(echo "$entry" | jq -r '.key')
    value=$(echo "$entry" | jq -r '.value')
    top=$(echo "$dotted" | cut -d. -f1)
    nested=$(echo "$dotted" | cut -d. -f2-)

    prev=$(yaml_get_scalar "$path" "$dotted")
    [ -n "$prev" ] || continue

    if [ "$prev" = "__absent__" ]; then
      yaml_remove_line "$path" "  ${nested}: ${value}"
    else
      yaml_set_scalar "$path" "${top}:" "$nested" "$prev"
    fi
  done < <(echo "$config" | jq -c '.set // {} | to_entries[]')
}

revert_config_toolsets() {  # $1 = path, $2 = config json
  local path="$1" config="$2" platforms plat header removed_csv added_flag item

  platforms=$(list_yaml_child_keys "$path" "platform_toolsets:")
  [ -n "$platforms" ] || return 0

  while IFS= read -r plat; do
    [ -n "$plat" ] || continue
    header="  ${plat}:"

    removed_csv=$(yaml_get_scalar "$path" "toolsets_removed.${plat}")
    removed_csv="${removed_csv%\"}"; removed_csv="${removed_csv#\"}"
    if [ -n "$removed_csv" ]; then
      IFS=',' read -ra removed_items <<< "$removed_csv"
      for item in "${removed_items[@]}"; do
        [ -n "$item" ] || continue
        yaml_list_add_item "$path" "$header" "$item"
      done
    fi

    added_flag=$(yaml_get_scalar "$path" "toolsets_added.${plat}")
    added_flag="${added_flag%\"}"; added_flag="${added_flag#\"}"
    if [ "$added_flag" = "new" ]; then
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        yaml_list_remove_item "$path" "$header" "$item"
      done < <(echo "$config" | jq -r '.toolsets_add // [] | .[]')
    fi
  done <<< "$platforms"
}

# ─── Bootstrap writers ──────────────────────────────────────────────────────

write_bootstrap_hook() {  # $1 = adapter json (claude)
  local aj="$1" path cmd content
  path=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
  cmd=$(echo "$aj" | jq -r '.bootstrap.hook_command' | sed "s#{{SCRIPT_DIR}}#$SCRIPT_DIR#g")

  mkdir -p "$(dirname "$path")"
  if [ -f "$path" ] && content=$(cat "$path") && echo "$content" | jq -e . >/dev/null 2>&1; then
    :
  else
    content='{}'
  fi

  content=$(echo "$content" | jq \
    --arg cmd "$cmd" --arg marker "$(allye_marker_string)" \
    '
    .hooks.SessionStart = (.hooks.SessionStart // []) |
    if (.hooks.SessionStart | any(.hooks[]?.command == $cmd)) then
      .
    else
      .hooks.SessionStart += [
        {
          "matcher": "startup|resume",
          "hooks": [
            { "type": "command", "command": $cmd, "timeout": 15, "_allye_installer": $marker }
          ]
        }
      ]
    end
    ')

  if [ -n "$PAT" ]; then
    content=$(echo "$content" | jq --arg pat "$PAT" '.env = (.env // {}) | .env.ALLYE_PAT = $pat')
  fi

  printf '%s\n' "$content" | jq '.' > "$path"
}

bootstrap_source_path() {  # $1 = bootstrap source from an adapter
  local source="$1"
  source=$(printf '%s' "$source" | sed "s#{{SCRIPT_DIR}}#$SCRIPT_DIR#g")
  case "$source" in
    /*) printf '%s\n' "$source" ;;
    *) printf '%s/%s\n' "$SCRIPT_DIR" "$source" ;;
  esac
}

validate_adapter_install() {  # $1 = adapter json; must run before mutations
  local aj="$1" kind source
  kind=$(echo "$aj" | jq -r '.bootstrap.kind // empty')
  if [ "$kind" = "instructions" ]; then
    source=$(bootstrap_source_path "$(echo "$aj" | jq -r '.bootstrap.source')")
    [ -f "$source" ] || { print_error "Instruction manifest not found: $source"; return 1; }
  fi
}

write_bootstrap_instructions() {  # $1 = adapter json (Codex)
  local aj="$1" path source begin end
  path=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
  source=$(bootstrap_source_path "$(echo "$aj" | jq -r '.bootstrap.source')")
  begin="# BEGIN $(allye_marker_string) CODEX AGENTS"
  end="# END $(allye_marker_string) CODEX AGENTS"

  [ -f "$source" ] || { print_error "Instruction manifest not found: $source"; return 1; }
  mkdir -p "$(dirname "$path")"
  touch "$path"
  # The paired markers scope only the installer-owned block. User guidance
  # before or after it remains untouched and repeat install is idempotent.
  grep -qF "$begin" "$path" 2>/dev/null && return 0
  {
    printf '\n%s\n' "$begin"
    cat "$source"
    printf '%s\n' "$end"
  } >> "$path"
}

validate_bootstrap_instructions_removal() {  # $1 = adapter json
  local aj="$1" path begin end begin_count end_count begin_line end_line
  path=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
  begin="# BEGIN $(allye_marker_string) CODEX AGENTS"
  end="# END $(allye_marker_string) CODEX AGENTS"
  [ -f "$path" ] || return 0
  begin_count=$(grep -Fxc "$begin" "$path" || true)
  end_count=$(grep -Fxc "$end" "$path" || true)
  [ "$begin_count" = 0 ] && [ "$end_count" = 0 ] && return 0
  begin_line=$(grep -Fnx "$begin" "$path" | cut -d: -f1)
  end_line=$(grep -Fnx "$end" "$path" | cut -d: -f1)
  if [ "$begin_count" != 1 ] || [ "$end_count" != 1 ] || [ "$begin_line" -ge "$end_line" ]; then
    print_error "Codex AGENTS markers are malformed or unpaired; preserving user instructions"
    return 1
  fi
}

remove_bootstrap_instructions() {  # $1 = adapter json
  local aj="$1" path begin end
  path=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
  begin="# BEGIN $(allye_marker_string) CODEX AGENTS"
  end="# END $(allye_marker_string) CODEX AGENTS"
  validate_bootstrap_instructions_removal "$aj" || return 1
  [ -f "$path" ] || return 0
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    skip && $0 == end { skip = 0; next }
    !skip { print }
  ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"
}

# ─── Skills-to-disk (agents that read skills from a directory, not MCP) ────
# A skill goes to either the API (seeded in Steps 1-3, for agents that fetch
# over MCP) or disk, never both for the same agent — a stale on-disk copy
# shadowing a fresh seeded one would fail silently.

allye_distribution_api_is_safe() {
  local url="$1"
  if ! node - "$url" <<'NODE'
const raw = process.argv[2]; let parsed;
try { parsed = new URL(raw); } catch { process.exit(1); }
if (parsed.username || parsed.password || parsed.pathname !== '/' || parsed.search || parsed.hash) process.exit(1);
const loopback = parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1' || parsed.hostname === '::1' || parsed.hostname === '[::1]';
if (parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && loopback)) process.exit(1);
NODE
  then print_error "ALLYE_API_URL must be credential-free HTTPS; HTTP is allowed only for structural loopback tests"; return 1; fi
}

allye_distribution_correlation_id() {
  printf '%s' "${ALLYE_CORRELATION_ID:-plugin-correlation-$(jq -r '.operationId // "unknown"' <<<"${ALLYE_DISTRIBUTION_CONTEXT_JSON:-{}}")}"
}

allye_distribution_request_id() {
  printf '%s' "${ALLYE_REQUEST_ID:-plugin-request-$(jq -r '.operationId // "unknown"' <<<"${ALLYE_DISTRIBUTION_CONTEXT_JSON:-{}}")}"
}

allye_distribution_preflight() { # $1 artifact runtime
  local artifact="$1" runtime="$2" context="${ALLYE_DISTRIBUTION_CONTEXT_JSON:-}" api="${ALLYE_API_URL:-}" jwks result
  [ -n "$context" ] && [ -n "$api" ] || { print_error "Physical disk distribution requires ALLYE_DISTRIBUTION_CONTEXT_JSON and ALLYE_API_URL"; return 1; }
  allye_distribution_api_is_safe "$api" || return 1
  jq -e '.operationId|type == "string" and length > 0' >/dev/null <<<"$context" || { print_error "Invalid execution context"; return 1; }
  jq -e '(.skillId|type == "string" and length > 0) and (.releaseId|type == "string" and length > 0) and (.version|type == "string" and (gsub("^\\s+|\\s+$"; "") | length > 0)) and (has("origin") and (.origin == null or (.origin|type == "object"))) and (.runtime|type == "string") and (.target|type == "string") and (.expectedHash|test("^[a-fA-F0-9]{64}$")) and (.executionToken|type == "string")' >/dev/null <<<"$context" || { print_error "Invalid execution context"; return 1; }
  [ "$(jq -r '.runtime' <<<"$context")" = "$runtime" ] || { print_error "Execution context runtime differs from disk adapter"; return 1; }
  jq -e --arg skill "$(jq -r '.skill_id' "$artifact")" --arg release "$(jq -r '.release_id' "$artifact")" --arg version "$(jq -r '.version' "$artifact")" --arg hash "$(jq -r '.canonical_hash|ascii_downcase' "$artifact")" --argjson origin "$(jq -c '.origin' "$artifact")" '
    .skillId == $skill and .releaseId == $release and .version == $version and .origin == $origin and (.expectedHash|ascii_downcase) == $hash
  ' <<<"$context" >/dev/null || { print_error "Execution context immutable identity differs from API artifact"; return 1; }
  jwks=$(curl --silent --show-error --fail "$api/api/skills/distribution-execution/jwks") || { print_error "Could not fetch execution JWKS"; return 1; }
  if ! node - "$context" "$jwks" <<'NODE'
const { createPublicKey, verify } = require('node:crypto');
const [context, jwks] = process.argv.slice(2).map(JSON.parse); const token = context.executionToken;
const [h,p,s] = token.split('.'); if (!h || !p || !s) process.exit(1);
const header = JSON.parse(Buffer.from(h, 'base64url')); const payload = JSON.parse(Buffer.from(p, 'base64url'));
const key = (jwks.data || jwks).keys?.find((item) => item.kid === header.kid && item.kty === 'RSA' && item.alg === 'RS256');
if (!key || header.alg !== 'RS256' || !verify('RSA-SHA256', Buffer.from(`${h}.${p}`), createPublicKey({ key, format: 'jwk' }), Buffer.from(s, 'base64url'))) process.exit(1);
const isOrigin = (value) => value === null || (typeof value === 'object' && !Array.isArray(value));
const canonicalJson = (value) => {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number' && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (typeof value === 'object') return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  throw new Error('non-JSON value');
};
for (const name of ['skillId','releaseId','version','runtime','target','expectedHash']) if (payload[name] !== context[name]) process.exit(1);
if (!isOrigin(payload.origin) || !isOrigin(context.origin) || canonicalJson(payload.origin) !== canonicalJson(context.origin)) process.exit(1);
if (payload.distributionId !== context.operationId) process.exit(1);
if (payload.typ !== 'skill_distribution_execution' || !Number.isInteger(payload.exp) || payload.exp <= Math.floor(Date.now()/1000)) process.exit(1);
NODE
  then print_error "Execution JWS is invalid, expired, or does not match its context"; return 1; fi
  result=$(curl --silent --show-error --fail -X POST \
    -H "Authorization: Bearer $(jq -r '.executionToken' <<<"$context")" \
    -H 'X-Allye-Channel: plugin' \
    -H "X-Correlation-Id: $(allye_distribution_correlation_id)" \
    -H "X-Request-Id: $(allye_distribution_request_id)" \
    "$api/api/skills/$(jq -r '.skillId' <<<"$context")/distributions/$(jq -r '.operationId' <<<"$context")/preflight") || { print_error "Execution preflight rejected"; return 1; }
  jq -e --arg op "$(jq -r '.operationId' <<<"$context")" --arg runtime "$runtime" --arg version "$(jq -r '.version' <<<"$context")" --arg hash "$(jq -r '.expectedHash|ascii_downcase' <<<"$context")" --argjson origin "$(jq -c '.origin' <<<"$context")" '(.data // .) | .operationId == $op and .status == "pending" and .runtime == $runtime and .version == $version and .origin == $origin and (.expectedHash|ascii_downcase) == $hash' >/dev/null <<<"$result" || { print_error "Execution preflight response is not pending matching context"; return 1; }
}

allye_distribution_report() { # $1 complete|fail, $2 artifact, $3 runtime, $4 diagnostic, $5 runtime version, $6 Pi receipt
  local action="$1" artifact="$2" runtime="$3" diagnostic="${4:-}" runtime_version="${5:-${runtime}-installer/1}" pi_package="${6:-}" context="$ALLYE_DISTRIBUTION_CONTEXT_JSON" api="$ALLYE_API_URL" payload response
  if [ "$action" = complete ]; then
    payload=$(jq -cn --arg hash "$(jq -r '.canonical_hash|ascii_downcase' "$artifact")" --arg version "$runtime_version" --arg verified "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson piPackage "${pi_package:-null}" '{observedHash:$hash,runtimeVersion:$version,verifiedAt:$verified} + (if $piPackage == null then {} else {piPackage:$piPackage} end)')
  else payload=$(jq -cn --arg code DISTRIBUTION_COMPLETION_REJECTED --arg diagnostic "$diagnostic" '{code:$code,diagnostic:$diagnostic}'); fi
  response=$(curl --silent --show-error --fail -X POST \
    -H "Authorization: Bearer $(jq -r '.executionToken' <<<"$context")" \
    -H 'Content-Type: application/json' \
    -H 'X-Allye-Channel: plugin' \
    -H "X-Correlation-Id: $(allye_distribution_correlation_id)" \
    -H "X-Request-Id: $(allye_distribution_request_id)" \
    --data "$payload" "$api/api/skills/$(jq -r '.skillId' <<<"$context")/distributions/$(jq -r '.operationId' <<<"$context")/$action") || return 1
  [ "$action" != complete ] || jq -e --arg op "$(jq -r '.operationId' <<<"$context")" --arg hash "$(jq -r '.canonical_hash|ascii_downcase' "$artifact")" --arg runtime "$runtime" --argjson piReceipt "${pi_package:-null}" '(.data // .) | .operationId == $op and .status == "succeeded" and .evidence.runtime == $runtime and (.evidence.observedHash|ascii_downcase) == $hash and (.evidence.runtimeVersion|type == "string" and length > 0) and (.evidence.verifiedAt|type == "string" and length > 0) and ($piReceipt == null or .evidence.piPackage == $piReceipt)' >/dev/null <<<"$response"
}

install_skills_to_disk() {  # $1 = agent id
  local id="$1" aj skills_path artifact skill release version origin hash runtime adapter tmp_root file path encoded expected_hash expected_bytes marker dest python_bin ownership lock_dir decision prior_manifest
  python_bin="${ALLYE_PYTHON_BIN:-python3}"
  local -A seen_paths=()
  aj=$(allye_agent_json "$id")
  skills_path=$(expand_home "$(echo "$aj" | jq -r '.skills.path')")
  artifact="${ALLYE_CANONICAL_ARTIFACT_JSON:-}"
  # Disk bytes are accepted only from a transient API/MCP response. Seed files
  # are identifiers only and are never read as canonical content here.
  if [ -z "$artifact" ] || [ ! -f "$artifact" ]; then print_error "Disk installation requires ALLYE_CANONICAL_ARTIFACT_JSON API/MCP response"; return 1; fi
  if ! jq -e '.release_id | type == "string" and length > 0' "$artifact" >/dev/null ||
    ! jq -e '.canonical_hash | type == "string" and test("^[a-fA-F0-9]{64}$")' "$artifact" >/dev/null ||
    ! jq -e '(.skill_id|type == "string" and length > 0) and (.version|type == "string" and (gsub("^\\s+|\\s+$"; "") | length > 0)) and (has("origin") and (.origin == null or (.origin|type == "object"))) and .integrity.valid == true and .manifest.sha256 == .canonical_hash and (.files|type == "array" and length > 0)' "$artifact" >/dev/null; then
    print_error "Canonical API artifact is invalid"; return 1
  fi
  skill=$(jq -r '.skill_id' "$artifact"); release=$(jq -r '.release_id' "$artifact"); version=$(jq -r '.version' "$artifact"); origin=$(jq -c '.origin' "$artifact"); hash=$(jq -r '.canonical_hash' "$artifact")
  if ! "$python_bin" - <<'PY'
import ctypes, sys
if sys.platform != "linux": raise SystemExit("atomic exchange requires Linux")
if not hasattr(ctypes.CDLL(None), "renameat2"): raise SystemExit("libc renameat2 unavailable")
PY
  then print_error "Atomic directory exchange requires Linux with libc renameat2; refusing installation before writes"; return 1; fi
  runtime=$(echo "$aj" | jq -r '.id'); adapter="${runtime}-workspace"
  # Every physical disk distribution is token-preflighted before staging.
  allye_distribution_preflight "$artifact" "$runtime" || return 1
  ownership=$(apiManagedArtifact "$runtime" "$skills_path" "$hash") || { print_error "Invalid verified execution context"; return 1; }
  decision=$(classifyCanonicalArtifact "$runtime" "$skills_path" "$ownership") || return 1
  jq -e '.allowed == true' >/dev/null <<<"$decision" || { print_error "$(jq -r '.code + ": canonical target preserved"' <<<"$decision")"; return 1; }
  # Retrying the same pending operation must not rewrite an intact Claude tree.
  # Re-read every receipt surface before allowing the API completion boundary.
  if canonicalArtifactReceiptMatches "$runtime" "$skills_path" "$ownership"; then
    if ! allye_distribution_report complete "$artifact" "$runtime"; then
      allye_distribution_report fail "$artifact" "$runtime" "Existing canonical artifact could not be confirmed by the API" || true
      print_error "Distribution completion was not confirmed; existing artifact was preserved"
      return 1
    fi
    return 0
  fi
  mkdir -p "$(dirname "$skills_path")"
  lock_dir="${skills_path}.allye.lock"
  mkdir "$lock_dir" 2>/dev/null || { print_error "CONFLICT_LOCKED: canonical artifact transaction already active"; return 1; }
  trap 'rmdir "$lock_dir" 2>/dev/null || true' RETURN
  tmp_root=$(mktemp -d "$(dirname "$skills_path")/.allye-artifact.XXXXXX") || return 1
  trap 'rm -rf "${tmp_root:-}"; rmdir "${lock_dir:-}" 2>/dev/null || true' RETURN
  while IFS= read -r file; do
    path=$(echo "$file" | jq -r '.path')
    case "$path" in SKILL.md|references/*|assets/*|scripts/*) ;; *) print_error "Invalid API artifact path: $path"; return 1;; esac
    case "$path" in /*|*'//'|./*|../*|*/./*|*/../*|*/.|*/..) print_error "Non-canonical API artifact path: $path"; return 1;; esac
    if [ "${seen_paths[$path]+x}" = x ]; then print_error "Duplicate API artifact path: $path"; return 1; fi
    seen_paths[$path]=1
    encoded=$(echo "$file" | jq -r '.bytes_base64 // empty')
    expected_hash=$(jq -r --arg path "$path" '.manifest.files[] | select(.path == $path) | .sha256' "$artifact")
    expected_bytes=$(jq -r --arg path "$path" '.manifest.files[] | select(.path == $path) | .bytes' "$artifact")
    [ -n "$encoded" ] && [ -n "$expected_hash" ] && [ "$expected_bytes" != "null" ] || { print_error "API artifact manifest/bytes missing: $path"; return 1; }
    dest="$tmp_root/$path"; mkdir -p "$(dirname "$dest")"
    printf '%s' "$encoded" | base64 -d > "$dest" || { print_error "Invalid base64 API artifact bytes: $path"; return 1; }
    [ "$(wc -c < "$dest" | tr -d ' ')" = "$expected_bytes" ] && [ "$(sha256sum "$dest" | cut -d' ' -f1)" = "$expected_hash" ] || { print_error "API artifact integrity check failed: $path"; return 1; }
  done < <(jq -c '.files[]' "$artifact")
  [ "$(jq '.manifest.files | length' "$artifact")" = "$(jq '.files | length' "$artifact")" ] || { print_error "API artifact manifest is incomplete"; return 1; }
  marker=$(jq -cn --arg skill "$skill" --arg release "$release" --arg version "$version" --arg hash "$hash" --arg adapter "$adapter" --arg runtime "$runtime" --arg installer "$(allye_marker_string)" --argjson origin "$origin" '{skill_id:$skill,release_id:$release,version:$version,origin:$origin,canonical_hash:$hash,adapter:$adapter,runtime:$runtime,installer:$installer}')
  [ -f "$tmp_root/SKILL.md" ] || { print_error "API artifact missing SKILL.md"; return 1; }
  # Metadata is a sidecar: canonical SKILL.md bytes are never rewritten.
  printf '%s\n' "$marker" > "$tmp_root/.allye-artifact.json"
  # Publish one complete tree. A test-only failpoint proves the old tree stays
  # intact before the commit rename; no child is individually removed/moved.
  [ "${ALLYE_INSTALL_FAILPOINT:-}" != "before-tree-swap" ] || { print_error "Installer failpoint before tree swap"; return 1; }
  local previous="${skills_path}.allye.previous.$$" had_previous=0
  if [ -e "$skills_path" ]; then
    had_previous=1
    # Linux renameat2(RENAME_EXCHANGE) swaps two existing paths atomically;
    # unlike two mv calls it never leaves skills_path absent. Fail closed when
    # the kernel/libc primitive is unavailable.
    if ! "$python_bin" - "$tmp_root" "$skills_path" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
try: renameat2 = libc.renameat2
except AttributeError: raise OSError("libc renameat2 unavailable")
renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
renameat2.restype = ctypes.c_int
r = renameat2(-100, os.fsencode(sys.argv[1]), -100, os.fsencode(sys.argv[2]), 2)
if r: raise OSError(ctypes.get_errno(), "renameat2(RENAME_EXCHANGE) unavailable")
PY
    then print_error "Atomic directory exchange is unavailable; refusing non-atomic publication"; return 1; fi
    # Keep the old tree as a rollback handle until the API persists matching evidence.
    mv "$tmp_root" "$previous" || { print_error "Atomic exchange completed; prior tree retained at $tmp_root"; return 1; }
  else
    mv "$tmp_root" "$skills_path" || return 1
  fi
  # Snapshot the exact pre-publication manifest. Completion is still part of
  # this transaction, so rejection must restore both disk bytes and receipt.
  prior_manifest=$(readManifest "$runtime") || { print_error "CONFLICT_UNMANAGED: manifest is invalid"; return 1; }
  # The manifest publication is part of the same recoverable transaction: a
  # metadata failure restores the prior tree before any success report.
  if ! recordManagedArtifact "$runtime" "$ownership"; then
    if [ "$had_previous" = 1 ]; then "$python_bin" - "$skills_path" "$previous" <<'PY'
import ctypes, os, sys
libc=ctypes.CDLL(None,use_errno=True); r=libc.renameat2(-100,os.fsencode(sys.argv[1]),-100,os.fsencode(sys.argv[2]),2)
if r: raise OSError(ctypes.get_errno(), "rollback unavailable")
PY
    else rm -rf "$skills_path"; fi
    print_error "PARTIAL_WRITE_CLEANED: manifest publication failed; artifact rolled back"; return 1
  fi
  # Do not claim success from staged bytes: re-read the published tree, sidecar
  # and manifest receipt after the atomic swap and before contacting completion.
  if ! canonicalArtifactReceiptMatches "$runtime" "$skills_path" "$ownership"; then
    if [ "$had_previous" = 1 ]; then
      if ! "$python_bin" - "$skills_path" "$previous" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
renameat2.restype = ctypes.c_int
if renameat2(-100, os.fsencode(sys.argv[1]), -100, os.fsencode(sys.argv[2]), 2): raise OSError(ctypes.get_errno(), "renameat2 rollback unavailable")
PY
      then print_error "Post-write receipt verification failed and atomic rollback failed; retained recovery handle $previous"; return 1; fi
      writeManifest "$runtime" "$prior_manifest" || { print_error "Post-write receipt verification failed; manifest rollback failed"; return 1; }
      rm -rf "$previous"
    else
      rm -rf "$skills_path"
      writeManifest "$runtime" "$prior_manifest" || { print_error "Post-write receipt verification failed; manifest rollback failed"; return 1; }
    fi
    allye_distribution_report fail "$artifact" "$runtime" "Post-write Claude artifact receipt verification failed; publication was rolled back" || true
    print_error "Post-write receipt verification failed; physical publish was rolled back"
    return 1
  fi
  if [ -n "${ALLYE_DISTRIBUTION_CONTEXT_JSON:-}" ] && ! allye_distribution_report complete "$artifact" "$runtime"; then
    # Completion is the success boundary. Restore the prior complete tree (or remove
    # only this newly-created tree) before reporting failure; no residual publish remains.
    if [ "$had_previous" = 1 ]; then
      if ! "$python_bin" - "$skills_path" "$previous" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
renameat2.restype = ctypes.c_int
if renameat2(-100, os.fsencode(sys.argv[1]), -100, os.fsencode(sys.argv[2]), 2): raise OSError(ctypes.get_errno(), "renameat2 rollback unavailable")
PY
      then print_error "Completion rejected and atomic rollback failed; retained recovery handle $previous"; return 1; fi
      if ! writeManifest "$runtime" "$prior_manifest"; then print_error "Completion rejected; manifest rollback failed; retained recovery handle $previous"; return 1; fi
      rm -rf "$previous"
    else
      rm -rf "$skills_path"
      if ! writeManifest "$runtime" "$prior_manifest"; then print_error "Completion rejected; manifest rollback failed after new tree removal"; return 1; fi
    fi
    allye_distribution_report fail "$artifact" "$runtime" "Completion was rejected after publication; physical publish was rolled back" || true
    print_error "Distribution completion was not confirmed; physical publish rolled back"
    return 1
  fi
  [ "$had_previous" = 0 ] || rm -rf "$previous"
  rmdir "$lock_dir" 2>/dev/null || true
  trap - RETURN
}

install_bootstrap_plugin() {  # $1 = adapter json
  local aj="$1" src dest_dir config plugin_name enable_key top_key nested_key

  src="$SCRIPT_DIR/manifests/$(echo "$aj" | jq -r '.id')"
  dest_dir=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
  plugin_name=$(basename "$dest_dir")

  mkdir -p "$dest_dir"
  cp "$src/plugin.yaml" "$dest_dir/plugin.yaml"
  cp "$src/__init__.py" "$dest_dir/__init__.py"

  config=$(expand_home "~/.hermes/config.yaml")
  mkdir -p "$(dirname "$config")"
  touch "$config"

  enable_key=$(echo "$aj" | jq -r '.bootstrap.enable_key')
  top_key=$(echo "$enable_key" | cut -d. -f1)
  nested_key=$(echo "$enable_key" | cut -d. -f2)

  yaml_ensure_top_key "$config" "${top_key}:"
  if ! grep -qxF "  ${nested_key}:" "$config" 2>/dev/null; then
    yaml_append_in_section "$config" "${top_key}:" "  ${nested_key}:"
  fi
  if ! grep -qxF "    - $plugin_name" "$config" 2>/dev/null; then
    yaml_append_in_section "$config" "  ${nested_key}:" "    - $plugin_name"
  fi
}

# ─── Pi package adapter ─────────────────────────────────────────────────────
# Pi owns package installation and persistence. Production installs always use
# the published npm package; local checkout installation is an explicit
# development-only opt-in. This code never edits Pi's settings.json.


pi_expand_path() {  # $1 = adapter path, honoring Pi/project overrides
  case "$1" in
    "~/.pi/agent/"*)
      printf '%s/%s\n' "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" "${1#\~/.pi/agent/}" ;;
    "~/.pi/agent")
      printf '%s\n' "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" ;;
    "~/"*) expand_home "$1" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "${ALLYE_PI_PROJECT_DIR:-$PWD}" "$1" ;;
  esac
}

pi_mcp_paths() {  # $1 = adapter json -> candidate paths
  local aj="$1" raw
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    pi_expand_path "$raw"
  done < <(echo "$aj" | jq -r '.mcp.paths[]?')
}

pi_mcp_source_with_allye() {  # $1 = adapter json -> first configured source
  local aj="$1" path
  while IFS= read -r path; do
    [ -f "$path" ] || continue
    if jq -e '(.mcpServers.allye // {}) | type == "object" and .disabled != true and ((.url? // .command? // "") | type == "string" and length > 0)' "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(pi_mcp_paths "$aj")
  return 1
}

pi_package_source() {  # $1 = adapter json, optional
  local aj="${1:-}" production local_source
  [ -n "$aj" ] || aj=$(allye_agent_json pi)
  production=$(echo "$aj" | jq -r '.package.production_source')
  local_source=$(echo "$aj" | jq -r '.package.local_source' | sed "s#{{SCRIPT_DIR}}#$SCRIPT_DIR#g")

  case "${ALLYE_PI_INSTALL_SOURCE:-npm}" in
    npm) printf '%s\n' "$production" ;;
    local) printf '%s\n' "$local_source" ;;
    *)
      print_error "Unsupported ALLYE_PI_INSTALL_SOURCE: ${ALLYE_PI_INSTALL_SOURCE}"
      print_error "Use 'npm' (default) or 'local' for explicit checkout development."
      return 1
      ;;
  esac
}

pi_source_matches_configured() {  # $1 configured source, $2 source rendered by pi list
  local configured="$1" resolved="$2" version
  [ "$resolved" = "$configured" ] && return 0
  case "$configured" in
    npm:*)
      case "$resolved" in "$configured"@*) version="${resolved#"$configured"@}" ;; *) return 1 ;; esac
      # Only a concrete SemVer pin is accepted; ranges/tags and homonyms fail.
      [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]
      ;;
    *) return 1 ;;
  esac
}

pi_installed_package_path() {  # $1 = configured source; resolve the root Pi actually loaded
  local source="$1" listed line root="" found=0
  command -v pi >/dev/null 2>&1 || return 1
  case "$source" in
    /*) [ -d "$source" ] && { realpath "$source"; return 0; } ;;
  esac
  listed=$(pi list 2>/dev/null) || return 1
  # Pi emits indented source/root pairs. Match exactly the configured source,
  # or its concrete pinned version after a restore; never a homonymous package.
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    if [ "$found" = 0 ]; then
      pi_source_matches_configured "$source" "$line" && found=1
      continue
    fi
    [ -z "$line" ] && continue
    case "$line" in
      /*) root="$line"; break ;;
      *) return 1 ;;
    esac
  done <<<"$listed"
  [ -n "$root" ] && [ -d "$root" ] || return 1
  printf '%s\n' "$root"
}

pi_package_installed() {  # $1 = source; compatibility predicate for status
  local root
  root=$(pi_installed_package_path "$1") && [ -n "$root" ] && [ -d "$root" ]
}

pi_validate_package_layout() {  # $1 = adapter json, $2 = Pi-resolved package root
  local aj="$1" root="$2" manifest discover
  manifest=$(echo "$aj" | jq -r '.layout.packageManifest')
  discover=$(echo "$aj" | jq -r '.layout.resourcesDiscover')
  [ -f "$root/$manifest" ] && [ -f "$root/$discover" ] \
    && jq -e '(.name == "allye-pi") and (.pi.extensions | index("./packages/allye-pi/src/index.ts")) and (.pi.skills | index("./skills"))' "$root/$manifest" >/dev/null
}

pi_package_digests() {  # $1 package root, $2 manifest path, $3 resources-discover path
  node - "$1" "$2" "$3" <<'NODE'
const { createHash } = require('node:crypto'); const { readdirSync, readFileSync, statSync } = require('node:fs'); const { join, relative } = require('node:path');
const [root, manifest, discover] = process.argv.slice(2); const sha = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');
const files = [manifest, discover]; const walk = (dir) => { for (const name of readdirSync(dir)) { const path = join(dir, name); const relativePath = relative(root, path); if (relativePath.startsWith('node_modules/')) continue; if (statSync(path).isDirectory()) walk(path); else files.push(relativePath); } };
walk(join(root, 'skills')); const unique = [...new Set(files)].sort(); const digest = createHash('sha256'); for (const file of unique) digest.update(file).update('\0').update(sha(join(root, file))).update('\0');
process.stdout.write(JSON.stringify({ packageManifestDigest: sha(join(root, manifest)), packageContentDigest: digest.digest('hex'), layoutIdentity: `pi:manifest=${manifest};resources=${discover};skills=skills` }));
NODE
}

pi_distribution_receipt() {  # $1 adapter, $2 source, $3 Pi-resolved package root
  local aj="$1" source="$2" root="$3" context="${ALLYE_DISTRIBUTION_CONTEXT_JSON:-}" artifact="${ALLYE_CANONICAL_ARTIFACT_JSON:-}" version package_version manifest discover digests
  [ -n "$context" ] && [ -n "$artifact" ] && [ -f "$artifact" ] || return 2
  pi_validate_package_layout "$aj" "$root" || return 1
  version=$(pi --version 2>/dev/null | head -n1 | tr -d '\r')
  package_version=$(jq -r '.version // empty' "$root/package.json")
  manifest=$(echo "$aj" | jq -r '.layout.packageManifest')
  discover=$(echo "$aj" | jq -r '.layout.resourcesDiscover')
  digests=$(pi_package_digests "$root" "$manifest" "$discover") || return 1
  [ -n "$version" ] && [ -n "$package_version" ] || return 1
  jq -e '(.operationId|type == "string" and length > 0) and (.releaseId|type == "string" and length > 0) and .runtime == "pi" and (.expectedHash|type == "string" and test("^[a-fA-F0-9]{64}$"))' >/dev/null <<<"$context" \
    && jq -e '(.release_id|type == "string" and length > 0) and (.canonical_hash|type == "string" and test("^[a-fA-F0-9]{64}$")) and .integrity.valid == true and .manifest.sha256 == .canonical_hash' "$artifact" >/dev/null \
    && [ "$(jq -r '.releaseId' <<<"$context")" = "$(jq -r '.release_id' "$artifact")" ] \
    && [ "$(jq -r '.expectedHash|ascii_downcase' <<<"$context")" = "$(jq -r '.canonical_hash|ascii_downcase' "$artifact")" ] \
    || return 1
  jq -cn --arg releaseId "$(jq -r '.releaseId' <<<"$context")" --arg canonicalHash "$(jq -r '.expectedHash|ascii_downcase' <<<"$context")" --arg packageSource "$source" --arg packageVersion "$package_version" --argjson digests "$digests" '{releaseId:$releaseId,canonicalHash:$canonicalHash,packageSource:$packageSource,packageVersion:$packageVersion} + $digests'
}

pi_package_snapshot() {  # $1 adapter, $2 source, $3 resolved root; never stores host path
  local aj="$1" source="$2" root="$3" version manifest discover digests
  pi_validate_package_layout "$aj" "$root" || return 1
  version=$(jq -r '.version // empty' "$root/package.json")
  manifest=$(echo "$aj" | jq -r '.layout.packageManifest')
  discover=$(echo "$aj" | jq -r '.layout.resourcesDiscover')
  digests=$(pi_package_digests "$root" "$manifest" "$discover") || return 1
  [ -n "$version" ] || return 1
  jq -cn --arg packageVersion "$version" --argjson digests "$digests" '{packageVersion:$packageVersion} + $digests'
}

pi_prior_restore_source() {  # $1 source, $2 existing resolved root -> immutable npm version spec
  local source="$1" root="$2" version package
  [ -n "$root" ] && [ -f "$root/package.json" ] || return 1
  version=$(jq -r '.version // empty' "$root/package.json")
  case "$source" in
    npm:*) package="${source#npm:}"; package="${package%@*}"; [ -n "$package" ] && [ -n "$version" ] && printf 'npm:%s@%s\n' "$package" "$version" ;;
    *) return 1 ;;
  esac
}

pi_rollback_install() {  # $1 source, $2 prior immutable source, $3 prior snapshot, $4 adapter
  local source="$1" prior_restore="${2:-}" prior_snapshot="${3:-}" aj="${4:-}" restored_root restored_snapshot
  if [ -n "$prior_restore" ]; then
    pi install "$prior_restore" >/dev/null 2>&1 || { print_error "Pi receipt failed and prior package restore failed: $prior_restore"; return 1; }
    restored_root=$(pi_installed_package_path "$prior_restore") || { print_error "Pi restored package has no resolved Pi list root"; return 1; }
    restored_snapshot=$(pi_package_snapshot "$aj" "$prior_restore" "$restored_root") || { print_error "Pi restored package layout/digests are invalid"; return 1; }
    [ "$restored_snapshot" = "$prior_snapshot" ] || { print_error "Pi restored package receipt differs from the prior immutable package"; return 1; }
    return 0
  fi
  pi remove "$source" >/dev/null 2>&1 || { print_error "Pi receipt failed and automatic package rollback failed: $source"; return 1; }
}

allye_install_pi() {  # $1 = adapter json
  local aj="$1" source mcp_source receipt package_root prior_root prior_restore prior_snapshot receipt_status
  command -v pi >/dev/null 2>&1 || {
    print_error "Pi is not available on PATH."
    return 1
  }
  source=$(pi_package_source "$aj") || return 1
  # A canonical distribution operation must be authorized before Pi mutates
  # package state. Context-less setup remains configuration, never succeeded.
  if [ -n "${ALLYE_DISTRIBUTION_CONTEXT_JSON:-}" ] || [ -n "${ALLYE_CANONICAL_ARTIFACT_JSON:-}" ]; then
    [ -n "${ALLYE_CANONICAL_ARTIFACT_JSON:-}" ] && [ -f "$ALLYE_CANONICAL_ARTIFACT_JSON" ] \
      && allye_distribution_preflight "$ALLYE_CANONICAL_ARTIFACT_JSON" pi \
      || { print_error "Pi canonical distribution preflight failed; no package was installed"; return 1; }
  fi
  if prior_root=$(pi_installed_package_path "$source" 2>/dev/null); then :; else prior_root=""; fi
  if prior_restore=$(pi_prior_restore_source "$source" "$prior_root" 2>/dev/null); then :; else prior_restore=""; fi
  if prior_snapshot=$(pi_package_snapshot "$aj" "$source" "$prior_root" 2>/dev/null); then :; else prior_snapshot=""; fi
  [ -z "$prior_restore" ] || [ -n "$prior_snapshot" ] || { print_error "Existing Pi package cannot be snapshotted for safe replacement"; return 1; }
  print_step "Installing Pi package $source..."
  pi install "$source" || { print_error "Pi could not install $source"; return 1; }
  package_root=$(pi_installed_package_path "$source") || {
    pi_rollback_install "$source" "$prior_restore" "$prior_snapshot" "$aj" || print_error "Pi package state is unrecovered after missing resolved root"
    print_error "Pi did not report a resolved package path after install; package was rolled back"
    return 1
  }
  if ! pi_validate_package_layout "$aj" "$package_root"; then
    pi_rollback_install "$source" "$prior_restore" "$prior_snapshot" "$aj" || print_error "Pi package state is unrecovered after invalid layout"
    print_error "Pi resolved package layout is incompatible; package was rolled back"
    return 1
  fi
  if receipt=$(pi_distribution_receipt "$aj" "$source" "$package_root"); then
    if ! allye_distribution_report complete "$ALLYE_CANONICAL_ARTIFACT_JSON" pi "" "$(pi --version | head -n1)" "$receipt"; then
      pi_rollback_install "$source" "$prior_restore" "$prior_snapshot" "$aj" || print_error "Pi package state is unrecovered after completion rejection"
      print_error "Pi receipt completion was rejected; package was rolled back"
      return 1
    fi
    print_success "Pi canonical distribution evidence verified: $receipt"
  else
    receipt_status=$?
    if [ "$receipt_status" -eq 1 ]; then
      pi_rollback_install "$source" "$prior_restore" "$prior_snapshot" "$aj" || print_error "Pi package state is unrecovered after invalid receipt"
      print_error "Pi package receipt is incompatible with the requested release/hash/layout; package was rolled back"
      return 1
    fi
    print_warning "Pi package configured; canonical distribution is pending an API release/hash execution receipt"
  fi
  if mcp_source=$(pi_mcp_source_with_allye "$aj"); then
    print_success "Allye MCP detected at $mcp_source"
  else
    print_warning "Pi package installed, but no supported MCP source contains an Allye server"
    print_warning "Configure the Allye server with pi-mcp-adapter before starting work."
  fi
  print_success "Pi configured (canonical skills + official package manager)"
}

allye_uninstall_pi() {
  local aj="${1:-}" source
  command -v pi >/dev/null 2>&1 || {
    print_error "Pi is not available on PATH."
    return 1
  }
  source=$(pi_package_source "$aj") || return 1
  print_step "Removing Pi package $source..."
  pi remove "$source" || {
    print_error "Pi could not remove $source"
    return 1
  }
}

# ─── Verbs ──────────────────────────────────────────────────────────────────

allye_install_codex() {  # $1 = validated Codex adapter json
  local aj="$1" config agents backup had_config=0 had_agents=0
  config=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  agents=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
  backup=$(mktemp -d) || return 1
  [ ! -e "$config" ] || { cp -p "$config" "$backup/config"; had_config=1; }
  [ ! -f "$agents" ] || { cp -p "$agents" "$backup/agents"; had_agents=1; }
  if ! write_mcp_toml "$aj" || ! write_bootstrap_instructions "$aj"; then
    [ "$had_config" = 0 ] && rm -f "$config" || cp -p "$backup/config" "$config"
    [ "$had_agents" = 0 ] && rm -f "$agents" || cp -p "$backup/agents" "$agents"
    rm -rf "$backup"
    print_error "Codex installation failed; configuration was rolled back"
    return 1
  fi
  rm -rf "$backup"
}

allye_install_one() {  # $1 = adapter json
  local aj="$1" id label fmt skills_source bootstrap_kind interactive
  id=$(echo "$aj" | jq -r '.id')
  label=$(echo "$aj" | jq -r '.label')
  validate_adapter_install "$aj" || return 1
  # Option 2: these commands mutate shared runtime configuration. The existing
  # execution context authorizes only a canonical disk artifact, never derived
  # JSON/TOML/YAML/hooks/package configuration, so fail closed before any write.
  print_error "CONFLICT_UNMANAGED: shared $id configuration has no API-backed ownership artifact; preserving it"
  return 1
  if [ "$id" = "pi" ]; then
    allye_install_pi "$aj"
    return $?
  fi
  if [ "$id" = "codex" ]; then
    allye_install_codex "$aj" || return 1
    print_success "$label configured"
    return 0
  fi
  fmt=$(echo "$aj" | jq -r '.mcp.format')

  case "$fmt" in
    json) write_mcp_json "$aj" ;;
    toml) write_mcp_toml "$aj" ;;
    yaml-block) write_mcp_yaml_block "$aj" ;;
    *) print_error "Unknown mcp format for $id: $fmt"; return 1 ;;
  esac

  apply_agent_config "$id"

  interactive=$(echo "$aj" | jq -r '.mcp.interactive_auth // false')
  if [ "$interactive" = "true" ]; then
    print_warning "$label MCP needs an interactive login. Run this in a terminal:"
    echo "      hermes mcp add allye --url $MCP_URL --auth oauth"
  fi

  skills_source=$(echo "$aj" | jq -r '.skills.source')
  if [ "$skills_source" = "disk" ]; then
    install_skills_to_disk "$id"
  fi

  bootstrap_kind=$(echo "$aj" | jq -r '.bootstrap.kind // empty')
  case "$bootstrap_kind" in
    hook) write_bootstrap_hook "$aj" ;;
    plugin) install_bootstrap_plugin "$aj" ;;
    instructions) write_bootstrap_instructions "$aj" ;;
  esac

  print_success "$label configured"
}

allye_install() {  # $1 = agent id, optional
  local target="${1:-}" aj id any=0

  if [ -n "$target" ]; then
    aj=$(allye_agent_json "$target")
    if [ -z "$aj" ]; then
      print_error "Unknown agent: $target"
      return 1
    fi
    if ! allye_detect "$target"; then
      print_warning "$target is not detected on this machine — install or select the runtime, then retry; no configuration was written"
      # Runtime absence is a diagnostic non-success. Report it only through an
      # already API-bound execution context; no shared config is touched.
      if [ "$target" = "claude" ] && [ -n "${ALLYE_CANONICAL_ARTIFACT_JSON:-}" ] && [ -n "${ALLYE_DISTRIBUTION_CONTEXT_JSON:-}" ] && [ -n "${ALLYE_API_URL:-}" ]; then
        allye_distribution_report fail "$ALLYE_CANONICAL_ARTIFACT_JSON" claude "Claude Code runtime is not available; no local layout or shared configuration was changed" || true
      fi
      return 1
    fi
    # Public physical distribution bypasses shared runtime config entirely.
    # The disk seam performs the existing JWS/JWKS/API preflight itself.
    if { [ "$target" = "hermes" ] || [ "$target" = "claude" ]; } && [ -n "${ALLYE_CANONICAL_ARTIFACT_JSON:-}" ] && [ -n "${ALLYE_DISTRIBUTION_CONTEXT_JSON:-}" ]; then
      install_skills_to_disk "$target"
      return $?
    fi
    allye_install_one "$aj"
    return $?
  fi

  while IFS= read -r aj; do
    id=$(echo "$aj" | jq -r '.id')
    if allye_detect "$id"; then
      allye_install_one "$aj"
      any=1
    fi
  done < <(jq -c '.agents[]' "$ADAPTERS_FILE")

  if [ "$any" -eq 0 ]; then
    print_warning "No supported agents were detected."
  fi
}

allye_uninstall() {  # $1 = agent id
  local id="$1" aj path fmt key content array_path array_val plugin_added
  local bootstrap_kind bpath cmd bdir plugin_name enable_key
  local skills_source spath

  aj=$(allye_agent_json "$id")
  if [ -z "$aj" ]; then
    print_error "Unknown agent: $id"
    return 1
  fi

  # Physical removal remains API-bound and unavailable until a proven ownership
  # protocol supplies an explicit remove authorization. Never mutate local state.
  print_error "DISTRIBUTION_REMOVE_OWNERSHIP_UNAVAILABLE: physical uninstall is blocked; no local mutation was performed"
  return 1

  bootstrap_kind=$(echo "$aj" | jq -r '.bootstrap.kind // empty')
  [ "$bootstrap_kind" != "instructions" ] || validate_bootstrap_instructions_removal "$aj" || return 1
  revert_agent_config "$id"

  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  fmt=$(echo "$aj" | jq -r '.mcp.format')
  key=$(echo "$aj" | jq -r '.mcp.key')

  if [ -f "$path" ]; then
    case "$fmt" in
      json)
        content=$(cat "$path")
        plugin_added=$(echo "$content" | jq -r --arg key "$key" '(getpath(($key | split("."))) | ._allye_installer_plugin_added) == true')
        content=$(echo "$content" | jq --arg key "$key" 'delpaths([($key | split("."))])')
        array_path=$(echo "$aj" | jq -r '.mcp.array_merge.path // empty')
        if [ -n "$array_path" ] && [ "$plugin_added" = true ]; then
          array_val=$(echo "$aj" | jq -r '.mcp.array_merge.value')
          content=$(echo "$content" | jq --arg p "$array_path" --arg v "$array_val" \
            'setpath([$p]; ((getpath([$p]) // []) - [$v]))')
        fi
        printf '%s\n' "$content" | jq '.' > "$path"
        ;;
      toml)
        remove_mcp_toml_section "$path" "$key"
        ;;
      yaml-block)
        yaml_remove_block "$path" "  allye:"
        ;;
    esac
  fi

  bootstrap_kind=$(echo "$aj" | jq -r '.bootstrap.kind // empty')
  if [ "$bootstrap_kind" = "hook" ]; then
    bpath=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
    if [ -f "$bpath" ]; then
      cmd=$(echo "$aj" | jq -r '.bootstrap.hook_command' | sed "s#{{SCRIPT_DIR}}#$SCRIPT_DIR#g")
      content=$(cat "$bpath")
      content=$(echo "$content" | jq --arg cmd "$cmd" \
        '.hooks.SessionStart = ((.hooks.SessionStart // []) | map(select(.hooks[0].command != $cmd)))')
      printf '%s\n' "$content" | jq '.' > "$bpath"
    fi
  elif [ "$bootstrap_kind" = "instructions" ]; then
    remove_bootstrap_instructions "$aj" || return 1
  elif [ "$bootstrap_kind" = "plugin" ]; then
    bdir=$(expand_home "$(echo "$aj" | jq -r '.bootstrap.path')")
    plugin_name=$(basename "$bdir")
    rm -rf "$bdir"
    enable_key=$(expand_home "~/.hermes/config.yaml")
    if [ -f "$enable_key" ]; then
      yaml_remove_line "$enable_key" "    - $plugin_name"
    fi
  fi

  skills_source=$(echo "$aj" | jq -r '.skills.source')
  if [ "$skills_source" = "disk" ]; then
    spath=$(expand_home "$(echo "$aj" | jq -r '.skills.path')")
    rm -rf "$spath"
  fi

  print_success "$(echo "$aj" | jq -r '.label') uninstalled"
}

allye_status() {
  local aj id label path source installed status_text
  while IFS= read -r aj; do
    id=$(echo "$aj" | jq -r '.id')
    label=$(echo "$aj" | jq -r '.label')
    if [ "$id" = "pi" ]; then
      source=$(pi_package_source "$aj" 2>/dev/null || true)
      if ! allye_detect "$id"; then
        printf '  %-14s not detected           %s\n' "$label" "${source:-package source unavailable}"
      elif [ -n "$source" ] && pi_package_installed "$source"; then
        printf '  %-14s current (package)      %s\n' "$label" "$source"
      else
        printf '  %-14s not installed          %s\n' "$label" "${source:-package source unavailable}"
      fi
      continue
    fi
    path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")

    if ! allye_detect "$id"; then
      printf '  %-14s not detected           %s\n' "$label" "$path"
      continue
    fi

    installed=$(allye_installed_version "$path" 2>/dev/null || true)
    if [ -z "$installed" ]; then
      status_text="not installed"
    elif [ "$installed" = "$ALLYE_INSTALLER_VERSION" ]; then
      status_text="current (v$installed)"
    else
      status_text="outdated (v$installed)"
    fi
    printf '  %-14s %-22s %s\n' "$label" "$status_text" "$path"
  done < <(jq -c '.agents[]' "$ADAPTERS_FILE")
}
