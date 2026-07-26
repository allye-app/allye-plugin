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
    BEGIN { in_section = 0; done = 0; target_indent = -1 }
    {
      if (!done && $0 == target) {
        print
        in_section = 1
        target_indent = indent_of($0)
        next
      }
      if (in_section && !done) {
        is_blank = ($0 ~ /^[ \t]*$/)
        cur_indent = indent_of($0)
        if (!is_blank && cur_indent <= target_indent) {
          print insert
          in_section = 0
          done = 1
        }
      }
      print
    }
    END {
      if (in_section && !done) print insert
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

# ─── Verbs ──────────────────────────────────────────────────────────────────

allye_install_one() {  # $1 = adapter json
  local aj="$1" id label fmt skills_source bootstrap_kind interactive
  id=$(echo "$aj" | jq -r '.id')
  label=$(echo "$aj" | jq -r '.label')
  fmt=$(echo "$aj" | jq -r '.mcp.format')

  case "$fmt" in
    json) write_mcp_json "$aj" ;;
    toml) write_mcp_toml "$aj" ;;
    yaml-block) write_mcp_yaml_block "$aj" ;;
    *) print_error "Unknown mcp format for $id: $fmt"; return 1 ;;
  esac

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
