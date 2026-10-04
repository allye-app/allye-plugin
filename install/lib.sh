# Allye skills installer — shared library (sourced by install.sh and the tests).
#
# Installs the organization's skills, stored in Allye's Skills section, into a
# developer's harness through the API's governed distribution flow:
#
#   1. read the skill and its approved release          GET  /api/skills/:id | /resolve/:slug
#   2. download and verify the canonical artifact       GET  /api/skills/:id/releases/:rid/artifact
#   3. open a distribution for this machine's target    POST /api/skills/:id/distributions/request|update
#   4. obtain and verify the signed execution token     POST .../distributions/:op/execution-context
#                                                       GET  /api/skills/distribution-execution/jwks
#   5. preflight with the execution token               POST .../distributions/:op/preflight
#   6. publish the verified tree, then report evidence  POST .../distributions/:op/complete | fail
#
# Requires bash, curl, jq and node >= 18. Authenticates with a Personal Access
# Token (ALLYE_PAT); the API does not accept the MCP OAuth grant on these routes.

ALLYE_INSTALLER_VERSION=2
ADAPTERS_FILE="${ADAPTERS_FILE:-$SCRIPT_DIR/install/adapters.json}"
SKILL_TOOL="$SCRIPT_DIR/install/skill-tool.mjs"
SIDECAR=".allye-artifact.json"
ALLYE_API_URL="${ALLYE_API_URL:-https://api.allye.app}"
ALLYE_CORRELATION_ID="${ALLYE_CORRELATION_ID:-allye-installer-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')}"

# ─── Helpers ────────────────────────────────────────────────────────────────

expand_home() {  # $1 = path, possibly starting with ~
  case "$1" in
    "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
    "~") printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

random_id() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n'; }

runtime_json() {  # $1 = runtime id -> adapter object, or empty
  jq -c --arg id "$1" '.runtimes[] | select(.id == $id)' "$ADAPTERS_FILE"
}

runtime_ids() { jq -r '.runtimes[].id' "$ADAPTERS_FILE"; }

runtime_skills_dir() {  # $1 = runtime id
  if [ "$1" = "pi" ] && [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
    printf '%s/skills\n' "$PI_CODING_AGENT_DIR"
    return
  fi
  expand_home "$(runtime_json "$1" | jq -r '.skillsDir')"
}

runtime_detected() {  # $1 = runtime id
  local rj cmd dir
  rj=$(runtime_json "$1")
  [ -n "$rj" ] || return 1
  cmd=$(jq -r '.detect.command // empty' <<<"$rj")
  dir=$(jq -r '.detect.dir // empty' <<<"$rj")
  if [ -n "$cmd" ] && command -v "$cmd" >/dev/null 2>&1; then return 0; fi
  [ -n "$dir" ] && [ -d "$(expand_home "$dir")" ]
}

# Logical, per-machine distribution target. The API ledger is keyed by
# (skill, runtime, target), so it must differ per developer machine and per
# skills directory. Only a digest leaves the machine, never the hostname/path.
runtime_target() {  # $1 = runtime id
  local digest
  digest=$(printf '%s|%s|%s' "$(uname -n)" "$(id -u)" "$(runtime_skills_dir "$1")" | sha256sum | cut -c1-16)
  printf '%s:%s:%s\n' "$(runtime_json "$1" | jq -r '.apiRuntime')" "$1" "$digest"
}

valid_slug() { [[ "$1" =~ ^[a-z0-9][a-z0-9._-]{0,99}$ ]] && [[ "$1" != *..* ]]; }

tree_hash() { node "$SKILL_TOOL" tree-hash "$1"; }

# ─── API transport ──────────────────────────────────────────────────────────
# api_call METHOD PATH [BODY_JSON] [BEARER]   (BEARER "-" sends no Authorization)
# Sets API_STATUS (HTTP code) and API_BODY (raw JSON). Returns 0 on 2xx.

check_api_url() {
  if ! node -e '
    let u; try { u = new URL(process.argv[1]); } catch { process.exit(1); }
    const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(u.hostname);
    if (u.username || u.password || u.search || u.hash || (u.pathname !== "/" && u.pathname !== "")) process.exit(1);
    if (u.protocol !== "https:" && !(u.protocol === "http:" && loopback)) process.exit(1);
  ' "$ALLYE_API_URL"; then
    print_error "ALLYE_API_URL must be an https:// origin without credentials or path (http:// is accepted only for localhost): $ALLYE_API_URL"
    return 1
  fi
}

require_pat() {
  case "${ALLYE_PAT:-}" in
    pat_*|fnx_*) return 0 ;;
    "") print_error "ALLYE_PAT is not set. Create a Personal Access Token in Allye (Settings → API) and export ALLYE_PAT." ;;
    *) print_error "ALLYE_PAT does not look like an Allye Personal Access Token (expected the pat_ or fnx_ prefix)." ;;
  esac
  return 1
}

api_call() {
  local method="$1" path="$2" body="${3:-}" bearer="${4:-${ALLYE_PAT:-}}" out
  local -a args=(--silent --show-error --max-time 30 -X "$method"
    -H "Accept: application/json"
    -H "X-Allye-Channel: plugin"
    -H "X-Correlation-Id: $ALLYE_CORRELATION_ID"
    -H "X-Request-Id: allye-installer-$(random_id)"
    -w $'\n%{http_code}')
  [ -z "$bearer" ] || [ "$bearer" = "-" ] || args+=(-H "Authorization: Bearer $bearer")
  [ -z "${ALLYE_TEAM_ID:-}" ] || args+=(-H "X-Team-Id: $ALLYE_TEAM_ID")
  [ -z "$body" ] || args+=(-H "Content-Type: application/json" --data-binary "$body")
  if ! out=$(curl "${args[@]}" "$ALLYE_API_URL$path" 2>&1); then
    API_STATUS=000; API_BODY=""
    print_error "Could not reach $ALLYE_API_URL ($method $path): $(tail -n1 <<<"$out")"
    return 1
  fi
  API_STATUS=$(tail -n1 <<<"$out")
  API_BODY=$(sed '$d' <<<"$out")
  [[ "$API_STATUS" == 2* ]]
}

# One line describing a non-2xx API response, using the API's code when present.
api_error() {  # $1 = what was attempted
  local detail
  detail=$(jq -r '
    def pick: .code // .error.code // .runtime_code // .failureCode // empty;
    def say: .message // .error.message // .diagnostic // .error // empty;
    [ (pick | tostring), (say | if type == "string" then . else tostring end) ] | map(select(length > 0)) | join(": ")
  ' 2>/dev/null <<<"$API_BODY")
  [ -n "$detail" ] || detail=$(head -c 300 <<<"$API_BODY")
  print_error "$1 failed (HTTP $API_STATUS)${detail:+ — $detail}"
  if [ "$API_STATUS" = 401 ]; then print_error "  The PAT was rejected; create a new one in Allye (Settings → API)."; fi
  if jq -e '(.code // .error.code) == "TEAM_SELECTION_REQUIRED"' >/dev/null 2>&1 <<<"$API_BODY"; then
    print_error "  Choose a team with --team <id> (or ALLYE_TEAM_ID). Teams: $(jq -r '[(.teams // .error.teams // [])[] | "\(.name) (\(.id))"] | join(", ")' <<<"$API_BODY")"
  fi
}

api_data() { jq -c '.data // .' <<<"$API_BODY"; }

# ─── Skill lookup ───────────────────────────────────────────────────────────

# Prints the skill object (with .release) for a UUID or slug.
fetch_skill() {  # $1 = skill id or slug
  local ref="$1" skill
  if [[ "$ref" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    api_call GET "/api/skills/$ref" || { api_error "Reading skill $ref"; return 1; }
    skill=$(api_data)
  else
    valid_slug "$ref" || { print_error "'$ref' is neither a skill id nor a valid slug"; return 1; }
    api_call GET "/api/skills/resolve/$ref" || { api_error "Resolving skill '$ref'"; return 1; }
    if jq -e '.conflict == true' >/dev/null <<<"$(api_data)"; then
      print_error "Skill '$ref' exists in several teams; choose one with --team <id> or install it by id."
      return 1
    fi
    skill=$(api_data | jq -c '.selected // empty')
    [ -n "$skill" ] || { print_error "No skill with slug '$ref' is visible to you."; return 1; }
  fi
  printf '%s\n' "$skill"
}

# ─── Local ownership ────────────────────────────────────────────────────────
# Each installed skill directory carries a sidecar with its API identity. A
# directory is only replaced when it is ours and still byte-identical to the
# release we installed; anything else is preserved.

classify_target() {  # $1 = dest dir, $2 = skill id -> missing|owned-intact|owned-modified|foreign|unmanaged
  local dest="$1" skill_id="$2" marker="$1/$SIDECAR" actual
  [ -e "$dest" ] || { echo missing; return; }
  if [ -L "$dest" ] || [ ! -d "$dest" ] || [ ! -f "$marker" ] || [ -L "$marker" ]; then echo unmanaged; return; fi
  jq -e . "$marker" >/dev/null 2>&1 || { echo unmanaged; return; }
  [ "$(jq -r '.skill_id' "$marker")" = "$skill_id" ] || { echo foreign; return; }
  actual=$(tree_hash "$dest" 2>/dev/null) || { echo owned-modified; return; }
  [ "$actual" = "$(jq -r '.canonical_hash' "$marker")" ] && echo owned-intact || echo owned-modified
}

# ─── Install one skill ──────────────────────────────────────────────────────

report_failure() {  # $1 skill id, $2 operation id, $3 token, $4 code, $5 diagnostic
  local body
  body=$(jq -cn --arg code "$4" --arg diagnostic "$5" '{code:$code, diagnostic:$diagnostic}')
  api_call POST "/api/skills/$1/distributions/$2/fail" "$body" "$3" \
    || print_warning "Could not record the failure on the API (HTTP $API_STATUS); the distribution stays pending until it expires."
}

install_skill() {  # $1 = runtime id, $2 = skill id or slug
  local runtime="$1" ref="$2" rj skill skill_id slug release_id version expected_hash skills_dir dest state
  local tmp target api_runtime allow_exp request_path body op status context token stage previous="" marker observed rc=1
  rj=$(runtime_json "$runtime")
  api_runtime=$(jq -r '.apiRuntime' <<<"$rj")
  allow_exp=$(jq -r '.allowExperimental' <<<"$rj")

  skill=$(fetch_skill "$ref") || return 1
  skill_id=$(jq -r '.id' <<<"$skill")
  slug=$(jq -r '.slug // empty' <<<"$skill")
  valid_slug "$slug" || { print_error "Skill $skill_id has no usable slug ('$slug'); it cannot be named on disk."; return 1; }
  if ! jq -e '.release.release_id and .release.canonical_hash' >/dev/null <<<"$skill"; then
    print_error "Skill '$slug' has no approved release; ask its maintainers to publish one."
    return 1
  fi
  release_id=$(jq -r '.release.release_id' <<<"$skill")
  version=$(jq -r '.release.version // "?"' <<<"$skill")
  expected_hash=$(jq -r '.release.canonical_hash | ascii_downcase' <<<"$skill")
  skills_dir=$(runtime_skills_dir "$runtime")
  dest="$skills_dir/$slug"

  state=$(classify_target "$dest" "$skill_id")
  case "$state" in
    owned-intact)
      if [ "$(jq -r '.release_id' "$dest/$SIDECAR")" = "$release_id" ]; then
        print_success "$slug $version is already installed for $runtime"
        return 0
      fi ;;
    missing) ;;
    owned-modified) print_error "$dest was edited locally since it was installed; move your changes away, then retry."; return 1 ;;
    foreign) print_error "$dest belongs to another Allye skill; remove or rename it, then retry."; return 1 ;;
    *) print_error "$dest already exists and was not installed by Allye; it was left untouched."; return 1 ;;
  esac

  tmp=$(mktemp -d) || return 1
  mkdir -p "$skills_dir" || { rm -rf "$tmp"; return 1; }
  if ! mkdir "$dest.allye.lock" 2>/dev/null; then
    print_error "Another install of '$slug' is running (lock $dest.allye.lock); retry when it finishes, or remove the lock if no install is running."
    rm -rf "$tmp"; return 1
  fi
  stage=$(mktemp -d "$skills_dir/.allye-stage.XXXXXX")

  # 2. Download and verify the release bytes before touching the ledger.
  if ! api_call GET "/api/skills/$skill_id/releases/$release_id/artifact?canonicalHash=$expected_hash"; then
    api_error "Downloading '$slug' $version"; cleanup_install; return 1
  fi
  printf '%s' "$API_BODY" > "$tmp/artifact.json"
  jq -cn --arg s "$skill_id" --arg r "$release_id" --arg h "$expected_hash" '{skill_id:$s, release_id:$r, canonical_hash:$h}' > "$tmp/expected.json"
  if ! node "$SKILL_TOOL" stage-artifact "$tmp/artifact.json" "$tmp/expected.json" "$stage" >/dev/null 2>"$tmp/err"; then
    print_error "Refusing '$slug' $version: $(cat "$tmp/err")"; cleanup_install; return 1
  fi

  # 3. Open the distribution for this machine (update when we own an older release).
  target=$(runtime_target "$runtime")
  body=$(jq -cn --arg s "$skill_id" --arg r "$release_id" --arg rt "$api_runtime" --arg v "$(jq -r '.contractVersion' "$ADAPTERS_FILE")" \
    --argjson exp "$allow_exp" --arg t "$target" --arg k "$target:$release_id:$(random_id)" \
    '{skillId:$s, releaseId:$r, runtime:$rt, runtimeVersion:$v, allowExperimental:$exp, target:$t, idempotencyKey:$k}')
  request_path=request
  if [ "$state" = owned-intact ]; then
    request_path=update
    body=$(jq -c --arg b "$(jq -r '.release_id' "$dest/$SIDECAR")" --arg o "$(jq -r '.canonical_hash' "$dest/$SIDECAR")" '. + {baseReleaseId:$b, observedHash:$o}' <<<"$body")
  fi
  if ! api_call POST "/api/skills/$skill_id/distributions/$request_path" "$body"; then
    api_error "Requesting the $runtime distribution of '$slug'"; cleanup_install; return 1
  fi
  op=$(api_data | jq -r '.operationId // .distributionId // empty')
  status=$(api_data | jq -r '.status')
  case "$status" in
    pending) ;;
    noop) print_error "The API already records '$slug' $version as installed for this machine ($runtime), but $dest does not hold it. Ask an Allye admin to reset the distribution, then retry."; cleanup_install; return 1 ;;
    *) print_error "The API answered '$status' for '$slug' on $runtime: $(api_data | jq -r '[.failureCode, .diagnostic] | map(select(.)) | join(" — ")')"; cleanup_install; return 1 ;;
  esac

  # 4. Signed execution token, verified against the API's JWKS.
  if ! api_call POST "/api/skills/$skill_id/distributions/$op/execution-context"; then
    api_error "Obtaining the execution token for '$slug'"; cleanup_install; return 1
  fi
  context=$(api_data)
  token=$(jq -r '.executionToken' <<<"$context")
  printf '%s' "$context" > "$tmp/context.json"
  if ! jq -e --arg s "$skill_id" --arg r "$release_id" --arg h "$expected_hash" --arg rt "$api_runtime" --arg t "$target" --arg op "$op" \
      '.operationId == $op and .skillId == $s and .releaseId == $r and (.expectedHash|ascii_downcase) == $h and .runtime == $rt and .target == $t' \
      "$tmp/context.json" >/dev/null; then
    print_error "The execution context for '$slug' does not match the requested release; nothing was installed."
    report_failure "$skill_id" "$op" "$token" CONTEXT_MISMATCH "Execution context differs from the requested release"; cleanup_install; return 1
  fi
  if ! api_call GET "/api/skills/distribution-execution/jwks" "" "-"; then
    api_error "Fetching the API signing keys"; report_failure "$skill_id" "$op" "$token" JWKS_UNAVAILABLE "Installer could not fetch the JWKS"; cleanup_install; return 1
  fi
  printf '%s' "$API_BODY" > "$tmp/jwks.json"
  if ! node "$SKILL_TOOL" verify-token "$tmp/context.json" "$tmp/jwks.json" 2>"$tmp/err"; then
    print_error "Refusing '$slug': $(cat "$tmp/err")"
    report_failure "$skill_id" "$op" "$token" TOKEN_INVALID "$(cat "$tmp/err")"; cleanup_install; return 1
  fi

  # 5. Preflight with the execution token.
  if ! api_call POST "/api/skills/$skill_id/distributions/$op/preflight" "" "$token"; then
    api_error "Preflight of '$slug'"; report_failure "$skill_id" "$op" "$token" PREFLIGHT_REJECTED "Preflight was rejected"; cleanup_install; return 1
  fi
  if ! api_data | jq -e --arg op "$op" --arg h "$expected_hash" '.operationId == $op and .status == "pending" and (.expectedHash|ascii_downcase) == $h' >/dev/null; then
    print_error "Preflight of '$slug' did not confirm a pending operation for this release."
    report_failure "$skill_id" "$op" "$token" PREFLIGHT_MISMATCH "Preflight response does not match"; cleanup_install; return 1
  fi

  # 6. Publish the verified tree with its provenance sidecar.
  jq -n --arg skill "$skill_id" --arg slug "$slug" --arg release "$release_id" --arg version "$version" --arg hash "$expected_hash" \
    --argjson origin "$(jq -c '.origin // null' "$tmp/context.json")" --arg runtime "$runtime" --arg target "$target" --arg op "$op" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg installer "allye-installer/$ALLYE_INSTALLER_VERSION" \
    '{skill_id:$skill, slug:$slug, release_id:$release, version:$version, canonical_hash:$hash, origin:$origin,
      runtime:$runtime, target:$target, operation_id:$op, installed_at:$at, installer:$installer}' > "$stage/$SIDECAR"
  if [ -e "$dest" ]; then
    previous="$dest.allye.previous.$$"
    mv "$dest" "$previous" || { print_error "Could not move the previous '$slug' aside; nothing was changed."; report_failure "$skill_id" "$op" "$token" PUBLISH_FAILED "Could not replace the previous tree"; cleanup_install; return 1; }
  fi
  if ! mv "$stage" "$dest"; then
    [ -z "$previous" ] || mv "$previous" "$dest"
    print_error "Could not publish '$slug' into $skills_dir; the previous state was restored."
    report_failure "$skill_id" "$op" "$token" PUBLISH_FAILED "Could not publish the tree"; cleanup_install; return 1
  fi
  observed=$(tree_hash "$dest" 2>/dev/null || true)
  body=$(jq -cn --arg h "$observed" --arg v "allye-installer/$ALLYE_INSTALLER_VERSION ($runtime)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{observedHash:$h, runtimeVersion:$v, verifiedAt:$at}')
  if [ "$observed" != "$expected_hash" ] || ! api_call POST "/api/skills/$skill_id/distributions/$op/complete" "$body" "$token"; then
    [ "$observed" = "$expected_hash" ] && api_error "Recording the installation of '$slug'" || print_error "Published tree of '$slug' does not match its release hash."
    rm -rf "$dest"
    [ -z "$previous" ] || mv "$previous" "$dest"
    report_failure "$skill_id" "$op" "$token" COMPLETION_REJECTED "Installation evidence was not accepted; the previous state was restored"
    cleanup_install; return 1
  fi
  [ -z "$previous" ] || rm -rf "$previous"
  cleanup_install
  print_success "$slug $version installed for $runtime → $dest"
}

# Used by install_skill; relies on its locals through dynamic scoping.
cleanup_install() {
  [ -z "${stage:-}" ] || rm -rf "$stage"
  [ -z "${tmp:-}" ] || rm -rf "$tmp"
  rmdir "$dest.allye.lock" 2>/dev/null || true
}

# ─── Verbs ──────────────────────────────────────────────────────────────────

allye_list() {  # [scope] [query]
  local scope="${1:-}" query="${2:-}" path="/api/skills?officialOnly=true&limit=100"
  [ -z "$scope" ] || path+="&scope=$scope"
  [ -z "$query" ] || path+="&query=$(jq -rn --arg q "$query" '$q|@uri')"
  api_call GET "$path" || { api_error "Listing skills"; return 1; }
  jq -r '
    (.data // .) as $page | ($page.data // $page) as $items
    | if ($items | length) == 0 then "  (no approved skills are visible to you)"
      else $items[] | "  \(.slug // "-")\t\(.release.version // "no release")\t\(.scope)\t\(.name)\t\(.id)" end
  ' <<<"$API_BODY" | column -t -s $'\t'
}

allye_install() {  # $1 = runtime, $2... = skill ids or slugs
  local runtime="$1" ok=0 failed=0 ref
  shift
  [ -n "$(runtime_json "$runtime")" ] || { print_error "Unknown runtime '$runtime'. Supported: $(runtime_ids | paste -sd' ')"; return 2; }
  [ "$#" -gt 0 ] || { print_error "Name at least one skill (slug or id). Run './install.sh list' to see them."; return 2; }
  runtime_detected "$runtime" || print_warning "$runtime was not detected on this machine; installing into $(runtime_skills_dir "$runtime") anyway."
  for ref in "$@"; do
    if install_skill "$runtime" "$ref"; then ok=$((ok + 1)); else failed=$((failed + 1)); fi
  done
  echo ""
  echo "  $ok installed or up to date, $failed failed"
  [ "$failed" -eq 0 ]
}

allye_status() {  # offline: what is installed, and is it intact?
  local id label dir marker any slug state
  while IFS= read -r id; do
    label=$(runtime_json "$id" | jq -r '.label')
    dir=$(runtime_skills_dir "$id")
    if ! runtime_detected "$id"; then printf '  %-16s not detected\n' "$label"; continue; fi
    any=0
    for marker in "$dir"/*/"$SIDECAR"; do
      [ -f "$marker" ] || continue
      any=1
      slug=$(basename "$(dirname "$marker")")
      state=$(classify_target "$(dirname "$marker")" "$(jq -r '.skill_id' "$marker")")
      [ "$state" = owned-intact ] && state=intact || state="modified locally"
      printf '  %-16s %-28s %-10s %s\n' "$label" "$slug" "$(jq -r '.version' "$marker")" "$state"
    done
    [ "$any" = 1 ] || printf '  %-16s no Allye skills installed in %s\n' "$label" "$dir"
  done < <(runtime_ids)
}
