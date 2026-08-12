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
  local aj="$1" path key entry content array_path array_val
  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  key=$(echo "$aj" | jq -r '.mcp.key')
  entry=$(echo "$aj" | jq -c '.mcp.entry' | sed "s#{{MCP_URL}}#$MCP_URL#g")
  entry=$(echo "$entry" | jq --arg m "$(allye_marker_string)" '. + {_allye_installer: $m}')

  mkdir -p "$(dirname "$path")"
  if [ -f "$path" ] && content=$(cat "$path") && echo "$content" | jq -e . >/dev/null 2>&1; then
    :
  else
    content='{}'
  fi

  content=$(echo "$content" | jq --argjson entry "$entry" --arg key "$key" \
    'setpath(($key | split(".")); $entry)')

  array_path=$(echo "$aj" | jq -r '.mcp.array_merge.path // empty')
  if [ -n "$array_path" ]; then
    array_val=$(echo "$aj" | jq -r '.mcp.array_merge.value')
    content=$(echo "$content" | jq --arg p "$array_path" --arg v "$array_val" \
      'setpath([$p]; ((getpath([$p]) // []) | if index($v) then . else . + [$v] end))')
  fi

  printf '%s\n' "$content" | jq '.' > "$path"
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

  awk -v pat='ALLYE_INSTALLER_VERSION=' -v hdr="[$key]" '
    $0 ~ pat { skip = 1; next }
    skip && $0 == hdr { next }
    skip && /^\[/ { skip = 0 }
    skip && $0 == "" { skip = 0; next }
    { print }
  ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"

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

# ─── Skills-to-disk (agents that read skills from a directory, not MCP) ────
# A skill goes to either the API (seeded in Steps 1-3, for agents that fetch
# over MCP) or disk, never both for the same agent — a stale on-disk copy
# shadowing a fresh seeded one would fail silently.

install_skills_to_disk() {  # $1 = agent id
  local id="$1" aj skills_path export_format count i skill slug source_file src dest_dir dest marker

  aj=$(allye_agent_json "$id")
  skills_path=$(expand_home "$(echo "$aj" | jq -r '.skills.path')")
  export_format=$(echo "$aj" | jq -r '.skills.export_format')
  marker="<!-- $(allye_marker_string) -->"

  mkdir -p "$skills_path"

  count=$(jq '.skills | length' "$SEED_FILE")
  for i in $(seq 0 $((count - 1))); do
    skill=$(jq -c ".skills[$i]" "$SEED_FILE")
    slug=$(echo "$skill" | jq -r '.slug')
    source_file=$(echo "$skill" | jq -r '.source_file')
    src="$SCRIPT_DIR/$source_file"

    if [ ! -f "$src" ]; then
      print_warning "Skipping $slug — source file not found: $source_file"
      continue
    fi

    case "$export_format" in
      claude)
        dest_dir="$skills_path/$slug"
        dest="$dest_dir/SKILL.md"
        mkdir -p "$dest_dir"
        awk -v marker="$marker" '
          { print }
          /^---$/ { seen++; if (seen == 2) print marker }
        ' "$src" > "$dest"
        ;;
      *)
        print_error "Unknown skills export_format: $export_format"
        return 1
        ;;
    esac
  done
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
# Pi already owns its MCP configuration through pi-mcp-adapter. The installer
# must not rewrite any MCP source; it only adds this repository as a Pi package
# in settings.json, preserving every existing package and setting.

ensure_pi_dependencies() {
  if [ -f "$SCRIPT_DIR/node_modules/pi-mcp-adapter/package.json" ]; then
    return 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    print_error "Pi runtime dependencies are missing and npm is not available."
    return 1
  fi
  print_step "Installing Pi runtime dependencies in the Allye checkout..."
  npm install --prefix "$SCRIPT_DIR" --omit=dev --no-audit --no-fund || {
    print_error "Could not install Pi runtime dependencies in $SCRIPT_DIR"
    return 1
  }
  if [ ! -f "$SCRIPT_DIR/node_modules/pi-mcp-adapter/package.json" ]; then
    print_error "Pi runtime dependency pi-mcp-adapter is still missing after npm install"
    return 1
  fi
}

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

write_pi_package() {  # $1 = adapter json
  local aj="$1" path source content
  path=$(pi_expand_path "$(echo "$aj" | jq -r '.package.settings_path')")
  source=$(echo "$aj" | jq -r '.package.source' | sed "s#{{SCRIPT_DIR}}#$SCRIPT_DIR#g")

  mkdir -p "$(dirname "$path")"
  if [ -f "$path" ]; then
    if ! content=$(cat "$path") || ! echo "$content" | jq -e . >/dev/null 2>&1; then
      print_error "Pi settings file is not valid JSON: $path"
      print_error "Refusing to overwrite it; repair it and re-run the installer."
      return 1
    fi
  else
    content='{}'
  fi

  content=$(echo "$content" | jq --arg source "$source" '
    .packages = ((.packages // []) |
      if (map(if type == "string" then . else (.source // "") end) | index($source))
      then . else . + [$source] end)')
  printf '%s\n' "$content" | jq '.' > "$path"
}

pi_package_source() {  # $1 = adapter json -> resolved source
  echo "$1" | jq -r '.package.source' | sed "s#{{SCRIPT_DIR}}#$SCRIPT_DIR#g"
}

pi_package_installed() {  # $1 = adapter json
  local aj="$1" path source
  path=$(pi_expand_path "$(echo "$aj" | jq -r '.package.settings_path')")
  source=$(pi_package_source "$aj")
  [ -f "$path" ] || return 1
  jq -e --arg source "$source" '
    any((.packages // [])[]?; (type == "string" and . == $source) or
      (type == "object" and .source == $source))' "$path" >/dev/null 2>&1
}

allye_install_pi() {  # $1 = adapter json
  local aj="$1" mcp_source
  ensure_pi_dependencies || return 1
  write_pi_package "$aj" || return 1
  if mcp_source=$(pi_mcp_source_with_allye "$aj"); then
    print_success "Allye MCP detected at $mcp_source"
  else
    print_warning "Pi package installed, but no supported MCP source contains an Allye server"
    print_warning "Checked project .mcp.json/.pi/mcp.json and supported global Pi/shared MCP paths."
    print_warning "Configure the Allye server with pi-mcp-adapter before starting work."
  fi
  print_success "Pi configured (canonical skills + adapter package)"
}

allye_uninstall_pi() {  # $1 = adapter json
  local aj="$1" path source content
  path=$(pi_expand_path "$(echo "$aj" | jq -r '.package.settings_path')")
  source=$(pi_package_source "$aj")
  [ -f "$path" ] || return 0
  content=$(cat "$path")
  if echo "$content" | jq -e . >/dev/null 2>&1; then
    echo "$content" | jq --arg source "$source" '
      .packages = ((.packages // []) | map(select(((type == "string" and . == $source) or
        (type == "object" and .source == $source)) | not)))' | jq '.' > "$path"
  fi
}

# ─── Verbs ──────────────────────────────────────────────────────────────────

allye_install_one() {  # $1 = adapter json
  local aj="$1" id label fmt skills_source bootstrap_kind interactive
  id=$(echo "$aj" | jq -r '.id')
  label=$(echo "$aj" | jq -r '.label')
  if [ "$id" = "pi" ]; then
    allye_install_pi "$aj"
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
      print_warning "$target is not detected on this machine — skipping"
      return 1
    fi
    allye_install_one "$aj"
    return 0
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
  local id="$1" aj path fmt key content array_path array_val
  local bootstrap_kind bpath cmd bdir plugin_name enable_key
  local skills_source spath

  aj=$(allye_agent_json "$id")
  if [ -z "$aj" ]; then
    print_error "Unknown agent: $id"
    return 1
  fi

  if [ "$id" = "pi" ]; then
    allye_uninstall_pi "$aj"
    print_success "$(echo "$aj" | jq -r '.label') uninstalled"
    return 0
  fi

  revert_agent_config "$id"

  path=$(expand_home "$(echo "$aj" | jq -r '.mcp.path')")
  fmt=$(echo "$aj" | jq -r '.mcp.format')
  key=$(echo "$aj" | jq -r '.mcp.key')

  if [ -f "$path" ]; then
    case "$fmt" in
      json)
        content=$(cat "$path")
        content=$(echo "$content" | jq --arg key "$key" 'delpaths([($key | split("."))])')
        array_path=$(echo "$aj" | jq -r '.mcp.array_merge.path // empty')
        if [ -n "$array_path" ]; then
          array_val=$(echo "$aj" | jq -r '.mcp.array_merge.value')
          content=$(echo "$content" | jq --arg p "$array_path" --arg v "$array_val" \
            'setpath([$p]; ((getpath([$p]) // []) - [$v]))')
        fi
        printf '%s\n' "$content" | jq '.' > "$path"
        ;;
      toml)
        awk -v pat='ALLYE_INSTALLER_VERSION=' -v hdr="[$key]" '
          $0 ~ pat { skip = 1; next }
          skip && $0 == hdr { next }
          skip && /^\[/ { skip = 0 }
          skip && $0 == "" { skip = 0; next }
          { print }
        ' "$path" > "$path.allye.tmp" && mv "$path.allye.tmp" "$path"
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
  local aj id label path installed status_text
  while IFS= read -r aj; do
    id=$(echo "$aj" | jq -r '.id')
    label=$(echo "$aj" | jq -r '.label')
    if [ "$id" = "pi" ]; then
      path=$(pi_expand_path "$(echo "$aj" | jq -r '.package.settings_path')")
      if ! allye_detect "$id"; then
        printf '  %-14s not detected           %s\n' "$label" "$path"
      elif pi_package_installed "$aj"; then
        printf '  %-14s current (package)      %s\n' "$label" "$path"
      else
        printf '  %-14s not installed          %s\n' "$label" "$path"
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
