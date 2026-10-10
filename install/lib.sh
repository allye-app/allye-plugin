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
unset _ALLYE_MV_T  # internal cache of the mv -T probe; never taken from the environment
TMPDIR="${TMPDIR:-/tmp}"
ADAPTERS_FILE="${ADAPTERS_FILE:-$SCRIPT_DIR/install/adapters.json}"
SKILL_TOOL="$SCRIPT_DIR/install/skill-tool.mjs"
SIDECAR=".allye-artifact.json"
ALLYE_API_URL="${ALLYE_API_URL:-https://api.allye.app}"
ALLYE_CORRELATION_ID="${ALLYE_CORRELATION_ID:-allye-installer-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')}"

# ─── Helpers ────────────────────────────────────────────────────────────────

XDG_TOKEN='${XDG_CONFIG_HOME:-~/.config}'

# Strip trailing slashes; "/" itself stays "/".
normalize_dir() {  # $1 = path
  local d="$1"
  while [ "${#d}" -gt 1 ] && [ "${d%/}" != "$d" ]; do d="${d%/}"; done
  printf '%s\n' "$d"
}

expand_home() {  # $1 = path, possibly starting with ~ or ${XDG_CONFIG_HOME:-~/.config}
  local p="$1" xdg
  case "$p" in
    "$XDG_TOKEN"*)
      xdg="${XDG_CONFIG_HOME:-}"
      case "$xdg" in /*) ;; *) xdg="$HOME/.config" ;; esac  # empty or relative = unset
      xdg="$(normalize_dir "$xdg")"
      [ "$xdg" != "/" ] || xdg=""
      p="$xdg${p#"$XDG_TOKEN"}" ;;
  esac
  case "$p" in
    "~/"*) printf '%s\n' "$HOME/${p#\~/}" ;;
    "~") printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

random_id() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n'; }

runtime_json() {  # $1 = runtime id -> adapter object, or empty
  jq -c --arg id "$1" '.runtimes[] | select(.id == $id)' "$ADAPTERS_FILE"
}

runtime_ids() { jq -r '.runtimes[].id' "$ADAPTERS_FILE"; }

# The adapter's home override (CODEX_HOME, PI_CODING_AGENT_DIR): only the empty
# string means unset; trailing "/" is stripped; a relative value is an error.
# Prints the normalised value (or nothing when unset); returns 1 when relative.
runtime_home_env() {  # $1 = runtime id
  local var val
  var=$(runtime_json "$1" | jq -r '.homeEnv // empty')
  [ -n "$var" ] || return 0
  val="${!var:-}"
  [ -n "$val" ] || return 0
  case "$val" in
    /*) normalize_dir "$val" ;;
    *) print_error "$var must be an absolute path (got '$val'); nothing was installed."; return 1 ;;
  esac
}

runtime_skills_dir() {  # $1 = runtime id
  local home
  home=$(runtime_home_env "$1") || return 1
  if [ -n "$home" ]; then
    [ "$home" = "/" ] && home=""
    printf '%s/skills\n' "$home"
    return
  fi
  expand_home "$(runtime_json "$1" | jq -r '.skillsDir')"
}

runtime_detected() {  # $1 = runtime id
  local rj cmd dir home
  rj=$(runtime_json "$1")
  [ -n "$rj" ] || return 1
  cmd=$(jq -r '.detect.command // empty' <<<"$rj")
  dir=$(jq -r '.detect.dir // empty' <<<"$rj")
  if [ -n "$cmd" ] && command -v "$cmd" >/dev/null 2>&1; then return 0; fi
  home=$(runtime_home_env "$1" 2>/dev/null) || home=""
  [ -z "$home" ] || dir="$home"
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

# ".allye." is reserved for the installer's own names (<slug>.allye.lock, .allye.previous.*).
valid_slug() { [[ "$1" =~ ^[a-z0-9][a-z0-9._-]{0,99}$ ]] && [[ "$1" != *..* ]] && [[ "$1" != *.allye.* ]]; }

# Hashes a tree without a subshell: sets TREE_HASH on success; on failure TREE_ERR holds the
# tool's message, which names the offending symlink or special file.
hash_tree() {  # $1 = dir
  local out
  if out=$(node "$SKILL_TOOL" tree-hash "$1" 2>&1); then TREE_HASH="$out"; TREE_ERR=""; return 0; fi
  TREE_HASH=""; TREE_ERR="$out"; return 1
}

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

# A bearer goes into a curl config on stdin: anything outside the token alphabet (a newline, a
# quote, a backslash) could inject config lines, so it is never sent.
BEARER_RE='^[A-Za-z0-9._~+/=-]+$'
valid_bearer() { local LC_ALL=C; [[ "$1" =~ $BEARER_RE ]]; }  # C: a range like a-z must not match é

# Ids that the API supplies and the installer puts in a URL path or query.
safe_id() { local LC_ALL=C; [[ "$1" =~ ^[A-Za-z0-9-]+$ ]]; }
safe_hash() { local LC_ALL=C; [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
bad_api_value() {  # $1 = what, $2 = value
  print_error "The API sent $1 '$(clean_text "$2")' that is not a valid identifier; nothing was installed."
  return 1
}

require_pat() {
  case "${ALLYE_PAT:-}" in
    pat_*|fnx_*)
      valid_bearer "$ALLYE_PAT" && return 0
      print_error "ALLYE_PAT holds characters a token never has (whitespace, quotes, backslashes or control characters); export it again exactly as Allye showed it." ;;
    "") print_error "ALLYE_PAT is not set. Create a Personal Access Token in Allye (Settings → API) and export ALLYE_PAT." ;;
    *) print_error "ALLYE_PAT does not look like an Allye Personal Access Token (expected the pat_ or fnx_ prefix)." ;;
  esac
  return 1
}

api_call() {
  local method="$1" path="$2" body="${3:-}" bearer="${4-${ALLYE_PAT:-}}" out
  local cfg
  local -a args=(--silent --show-error --max-time 30 -X "$method" -K -
    -H "Accept: application/json"
    -H "X-Allye-Channel: plugin"
    -H "X-Correlation-Id: $ALLYE_CORRELATION_ID"
    -H "X-Request-Id: allye-installer-$(random_id)"
    -w $'\n%{http_code}')
  # The bearer travels in a curl config on stdin (a builtin printf), never in argv, where any
  # local user could read it from the process list.
  cfg=""
  if [ -n "$bearer" ] && [ "$bearer" != "-" ]; then
    if ! valid_bearer "$bearer"; then
      API_STATUS=000; API_BODY=""
      print_error "Refusing to send a credential that holds characters outside the token alphabet; nothing was sent."
      return 1
    fi
    cfg=$(printf 'header = "Authorization: Bearer %s"' "$bearer")
  fi
  if [ -n "${ALLYE_TEAM_ID:-}" ]; then
    if ! [[ "$ALLYE_TEAM_ID" =~ ^[A-Za-z0-9-]{1,64}$ ]]; then
      API_STATUS=000; API_BODY=""
      print_error "Invalid team id; nothing was sent."
      return 1
    fi
    args+=(-H "X-Team-Id: $ALLYE_TEAM_ID")
  fi
  [ -z "$body" ] || args+=(-H "Content-Type: application/json" --data-binary "$body")
  if ! out=$(printf '%s\n' "$cfg" | curl "${args[@]}" "$ALLYE_API_URL$path" 2>&1); then
    API_STATUS=000; API_BODY=""
    print_error "Could not reach $ALLYE_API_URL ($method $path): $(clean_text "$(tail -n1 <<<"$out")")"
    return 1
  fi
  API_STATUS=$(tail -n1 <<<"$out")
  API_BODY=$(sed '$d' <<<"$out")
  [[ "$API_STATUS" == 2* ]]
}

# One line describing a non-2xx API response, using the API's code and hint when present,
# then a specific explanation for the codes users can act on.
api_error() {  # $1 = what was attempted
  local detail code
  detail=$(jq -r '
    def pick: .code // .error.code // .runtime_code // .failureCode // empty;
    def say: .message // .error.message // .diagnostic // .error // empty;
    def hint: .hint // .error.hint // empty;
    ([ (pick | tostring), (say | if type == "string" then . else tostring end) ] | map(select(length > 0)) | join(": "))
      + (hint | if type == "string" and length > 0 then " (hint: " + . + ")" else "" end)
  ' 2>/dev/null <<<"$API_BODY")
  [ -n "$detail" ] || detail=$(head -c 300 <<<"$API_BODY")
  print_error "$1 failed (HTTP $API_STATUS)${detail:+ — $(clean_text "$detail")}"
  if [ "$API_STATUS" = 401 ]; then print_error "  The PAT was rejected; create a new one in Allye (Settings → API)."; fi
  code=$(jq -r '.code // .error.code // empty' 2>/dev/null <<<"$API_BODY")
  case "$API_STATUS:$code" in
    409:DISTRIBUTION_NOT_AUTHORIZED)
      print_error "  You need view access to this skill (membership in the team that owns it, or being its author). Get access, then rerun; nothing was installed by this run." ;;
    410:MARKETPLACE_RETIRED)
      print_error "  This is a retired marketplace skill and is read-only; nothing was installed. Use an organization or team skill instead." ;;
    422:TEAM_SELECTION_REQUIRED)
      print_error "  The slug matches skills in several teams; rerun with --team <team> or use the skill id. Teams: $(clean_text "$(jq -r '[(.teams // .error.teams // [])[] | "\(.name) (\(.id))"] | join(", ")' <<<"$API_BODY")")" ;;
  esac
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

# Classes: missing | unmanaged | foreign | unhashable | owned-intact | owned-modified |
# owned-other-target-intact | owned-other-target-modified. Precedence: unmanaged > foreign >
# unhashable > other-target > intact/modified. other-target = a valid sidecar whose target is
# not $3 (the current runtime target; omit it to skip that check); intact = the tree hash
# equals the hash recorded in the sidecar. unhashable = a symlink or special file in the tree.
classify_target() {  # $1 = dest dir, $2 = skill id, $3 = current target (optional)
  local dest="$1" skill_id="$2" current="${3:-}" marker="$1/$SIDECAR" prefix=owned
  [ -e "$dest" ] || [ -L "$dest" ] || { echo missing; return; }
  if [ -L "$dest" ] || [ ! -d "$dest" ] || [ ! -f "$marker" ] || [ -L "$marker" ]; then echo unmanaged; return; fi
  jq -e . "$marker" >/dev/null 2>&1 || { echo unmanaged; return; }
  [ "$(jq -r '.skill_id' "$marker")" = "$skill_id" ] || { echo foreign; return; }
  hash_tree "$dest" || { echo unhashable; return; }
  if [ -n "$current" ] && [ "$(jq -r '.target // ""' "$marker")" != "$current" ]; then prefix=owned-other-target; fi
  [ "$TREE_HASH" = "$(jq -r '.canonical_hash' "$marker")" ] && echo "$prefix-intact" || echo "$prefix-modified"
}

# ─── Install one skill ──────────────────────────────────────────────────────

# Best effort: a failure report (including one sent with the PAT because no execution token
# exists yet) only ever prints a warning; it never changes the caller's error or exit code.
# Whether the real API accepts a PAT-bearing fail must be confirmed by the HML E2E (ALY-34.7).
report_failure() {  # $1 skill id, $2 operation id, $3 token or @pat (no token yet: use the PAT), $4 code, $5 diagnostic
  local body bearer="$3"
  [ "$bearer" != @pat ] || bearer="${ALLYE_PAT:-}"
  if ! valid_bearer "$bearer"; then
    print_warning "Could not record the failure on the API: no usable credential; the distribution stays pending until it expires."
    return 0
  fi
  body=$(jq -cn --arg code "$4" --arg diagnostic "$5" '{code:$code, diagnostic:$diagnostic}')
  if ! api_call POST "/api/skills/$1/distributions/$2/fail" "$body" "$bearer"; then
    if [ "$API_STATUS" = 409 ]; then
      print_warning "The API refused the failure report because the operation is no longer pending: the install may already be recorded there. Rerun the installer; it reinstalls the skill."
    else
      print_warning "Could not record the failure on the API (HTTP $API_STATUS); the distribution stays pending until it expires."
    fi
  fi
}

# The allye-opencode plugin only loads an allye-skills dir that is a real directory
# and not group/world-writable; refuse to install into one it would ignore.
# True when group or others can write to $1.
others_can_write() {  # $1 = path
  local bits
  bits=$(stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null) || return 0   # cannot tell: unsafe
  [[ "$bits" =~ ^[0-7]+$ ]] || return 0
  [ $(( 8#$bits & 8#022 )) -ne 0 ]
}

check_opencode_dir() {  # $1 = skills dir
  local d="$1"
  [ -e "$d" ] || [ -L "$d" ] || return 0
  if [ -L "$d" ]; then
    print_error "$d is a symlink; the OpenCode plugin ignores it. Replace it with a real directory, then retry."
    return 1
  fi
  if others_can_write "$d"; then
    print_error "$d is group- or world-writable; the OpenCode plugin ignores such a directory. Fix it with: chmod go-w $d"
    return 1
  fi
}

# ─── Reinstall of an edited copy: move-aside and backup lifecycle ──────────
# The edited folder is moved to a hidden same-device name next to the skill, the release is
# published, and only after complete succeeds is the hidden copy moved to
# ~/.allye/backups/<adapter-id>/ (D-22). On any failure before that it is moved back (D-29).
# These run with install_skill's and install_locked's locals in scope.

dev_of() { stat -c %d "$1" 2>/dev/null || stat -f %d "$1" 2>/dev/null; }

# Probes once whether this mv has -T (GNU). BSD/macOS mv does not; there mv -n is used.
mv_has_T() {
  local out
  if [ -z "${_ALLYE_MV_T:-}" ]; then
    out=$(mv -T "$TMPDIR/.allye-no-such-1" "$TMPDIR/.allye-no-such-2" 2>&1 || true)
    if grep -qiE 'illegal option|invalid option|unknown option|usage:' <<<"$out"; then _ALLYE_MV_T=no; else _ALLYE_MV_T=yes; fi
  fi
  [ "$_ALLYE_MV_T" = yes ]
}

# Moves a directory to a destination that must not exist, then asserts the destination is a
# directory and the source is gone. A genuine mv -T failure is never retried with another mv.
move_dir() {  # $1 = source, $2 = destination
  [ ! -e "$2" ] && [ ! -L "$2" ] || return 1
  if mv_has_T; then
    mv -T "$1" "$2" 2>/dev/null || return 1
  else
    mv -n "$1" "$2" 2>/dev/null || return 1
    # mv -n moves into a directory that appeared at the destination meanwhile: undo that.
    if [ -e "$2/${1##*/}" ]; then mv -n "$2/${1##*/}" "$1" 2>/dev/null || true; return 1; fi
  fi
  [ -d "$2" ] && [ ! -L "$2" ] && [ ! -e "$1" ] && [ ! -L "$1" ]
}

# Puts the edited folder back at its original path. Deletes nothing: when it cannot, it
# prints where the folder is.
restore_backup() {  # $1 = hidden staging path, $2 = original path
  if move_dir "$1" "$2"; then return 0; fi
  print_error "Could not move your edited copy back to $2. It is still at: $1 (nothing was deleted); move it back by hand."
  return 1
}

# Puts the previous release back at its path; when it cannot, prints where it is.
restore_previous() {
  move_dir "$previous" "$dest" && return 0
  print_error "Could not move the previous '$slug' back to $dest. It is still at: $previous (nothing was deleted); move it back by hand."
  return 1
}

# Re-classify (and re-hash) the folder right before it is moved to .allye.previous.*, and
# re-hash the moved copy: only the exact state seen at classification is ever swapped out.
swap_out_previous() {
  local current
  current=$(classify_target "$dest" "$skill_id" "$target")
  if [ "$current" != "$state" ]; then
    move_code=FOLDER_CHANGED; print_error "$dest changed while the install was running ($current); nothing was changed. Rerun the installer."; return 1
  fi
  [ "$state" != missing ] || return 0
  previous="$dest.allye.previous.$$"
  if ! move_dir "$dest" "$previous"; then
    previous=""; move_code=PUBLISH_FAILED; print_error "Could not move the previous '$slug' aside; nothing was changed."; return 1
  fi
  if ! hash_tree "$previous" || [ "$TREE_HASH" != "$pre_hash" ]; then
    move_code=FOLDER_CHANGED; print_error "$dest changed while it was being moved aside; putting it back."
    restore_previous && previous=""
    return 1
  fi
}

# Step 8-9: re-classify and re-hash, then move the edited folder aside. On failure nothing was
# moved (or it was moved back) and move_code names the reason for the fail POST.
move_aside_edited() {
  local current
  current=$(classify_target "$dest" "$skill_id" "$target")
  case "$current" in
    owned-modified|owned-other-target-modified) ;;
    *) move_code=FOLDER_CHANGED; print_error "$dest changed while the install was running ($current); nothing was changed. Rerun the installer."; return 1 ;;
  esac
  if ! hash_tree "$dest" || [ "$TREE_HASH" != "$local_hash" ]; then
    move_code=FOLDER_CHANGED; print_error "$dest changed while the install was running; nothing was changed. Rerun the installer."; return 1
  fi
  hidden="$skills_dir/.allye-backup.$slug.$(date -u +%Y%m%dT%H%M%SZ).$$"
  if ! move_dir "$dest" "$hidden"; then
    hidden=""; move_code=PUBLISH_FAILED; print_error "Could not move your edited copy of '$slug' aside; nothing was changed."; return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    print_error "$dest reappeared while your edited copy was being moved aside. Your edited copy is at: $hidden"
    hidden=""; move_code=PUBLISH_FAILED; return 1
  fi
  if ! hash_tree "$hidden" || [ "$TREE_HASH" != "$local_hash" ]; then
    move_code=FOLDER_CHANGED; print_error "$dest changed while it was being moved aside; putting it back."
    restore_backup "$hidden" "$dest" && hidden=""
    return 1
  fi
}

# The backups location must be under an absolute $HOME, and none of its components may be a
# symlink, a non-directory, owned by someone else or group/world-writable.
check_backups_root() {  # $1 = adapter id
  local c
  case "${HOME:-}" in /*) ;; *) print_error "HOME must be an absolute path to keep a backup of your edited copy (got '${HOME:-}'); nothing was changed."; return 1 ;; esac
  for c in "$HOME/.allye" "$HOME/.allye/backups" "$HOME/.allye/backups/$1"; do
    if [ -L "$c" ] || { [ -e "$c" ] && { [ ! -d "$c" ] || [ ! -O "$c" ]; }; }; then
      print_error "$c is a symlink, not a directory or not owned by you; the installer will not keep backups there. Fix it, then retry; nothing was changed."
      return 1
    fi
    if [ -e "$c" ] && others_can_write "$c"; then
      print_error "$c is group- or world-writable; the installer will not keep backups there. Fix it with: chmod go-w $c. Nothing was changed."
      return 1
    fi
  done
}

# Step 11, after complete succeeded: move the hidden copy into the backups dir, verify it,
# rename its sidecar. Any failure keeps the hidden copy and returns non-zero.
finalize_backup() {
  local root="$HOME/.allye/backups/$runtime" dir c; local -a created=()
  dir="$root/$slug.allye.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  check_backups_root "$runtime" || { backup_not_moved "the backups location is not safe"; return 1; }
  for c in "$HOME/.allye" "$HOME/.allye/backups" "$root"; do
    if [ ! -e "$c" ] && [ ! -L "$c" ]; then created+=("$c"); fi
  done
  if ! (umask 077; mkdir -p "$root") 2>/dev/null; then
    backup_not_moved "cannot create $root"; return 1
  fi
  for c in "${created[@]}"; do chmod 700 "$c" 2>/dev/null || true; done
  if [ -e "$dir" ] || [ -L "$dir" ]; then dir="$dir.$$"; fi
  if [ -e "$dir" ] || [ -L "$dir" ]; then backup_not_moved "no free backup name in $root"; return 1; fi
  if [ "$(dev_of "$hidden")" = "$(dev_of "$root")" ]; then
    if move_dir "$hidden" "$dir"; then hidden=""; else backup_not_moved "cannot move it into $root" "$dir"; return 1; fi
  else
    if ! cp -a "$hidden" "$dir" 2>/dev/null; then backup_not_moved "cannot copy it into $root" "$dir"; return 1; fi
  fi
  if ! hash_tree "$dir" || [ "$TREE_HASH" != "$local_hash" ]; then
    backup_not_moved "the backup copy did not verify" "$dir"; return 1
  fi
  if [ -n "$hidden" ]; then rm -rf "$hidden"; hidden=""; fi   # the verified source of a cross-device copy
  if [ -e "$dir/$SIDECAR" ]; then mv -n "$dir/$SIDECAR" "$dir/.allye-artifact.backup.json" 2>/dev/null || true; fi
  chmod 700 "$dir" 2>/dev/null || true
  echo "  Your edited copy was kept at: $dir"
}

backup_not_moved() {  # $1 = reason, $2 = partial copy path (optional)
  local where=""
  [ -z "$hidden" ] || where="$hidden"
  [ -z "${2:-}" ] || [ ! -e "$2" ] || where="${where:+$where and }$2"
  print_error "$slug $version installed, backup not moved ($1). Your edited copy is still at: $where. Move it into ~/.allye/backups/$runtime/ by hand."
}

# The lock is held: say whether the pid it records is alive; a dead or missing pid looks stale.
# The lock is never removed here.
lock_pid_report() {  # $1 = lock dir, $2 = slug
  local lock="$1" pid="" why="no pid was recorded"
  [ ! -f "$lock/pid" ] || pid=$(head -n1 "$lock/pid" 2>/dev/null)
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -lt 2 ]; then
    why="the recorded pid ($pid) is not a real install"
  elif [[ "$pid" =~ ^[0-9]+$ ]]; then
    if kill -0 "$pid" 2>/dev/null; then
      print_error "Another install of '$2' is running (lock $lock, pid $pid is running); retry when it finishes."
      return 0
    fi
    why="pid $pid is not running"
  fi
  # printf %q quotes any character in the path, so the command can be pasted as shown.
  local cmd; printf -v cmd 'rm -f %q && rmdir %q' "$lock/pid" "$lock"
  print_error "Another install of '$2' holds $lock, but $why: the lock looks stale (a run in its first instants may not have written its pid yet). If no install is running, remove it with: $cmd and rerun. The installer never removes it by itself."
}

install_skill() {  # $1 = runtime id, $2 = skill id or slug
  local runtime="$1" ref="$2" rj skill skill_id slug release_id version expected_hash skills_dir dest state
  local tmp="" target api_runtime allow_exp stage="" hidden="" lock_held=0 created_dir=0 published=0 rc
  rj=$(runtime_json "$runtime")
  api_runtime=$(jq -r '.apiRuntime' <<<"$rj")
  allow_exp=$(jq -r '.allowExperimental' <<<"$rj")

  skill=$(fetch_skill "$ref") || return 1
  skill_id=$(jq -r '.id' <<<"$skill")
  safe_id "$skill_id" || { bad_api_value "skill id" "$skill_id"; return 1; }
  slug=$(jq -r '.slug // empty' <<<"$skill")
  valid_slug "$slug" || { print_error "Skill $skill_id has no usable slug ('$(clean_text "$slug")'); it cannot be named on disk."; return 1; }
  if ! jq -e '.release.release_id and .release.canonical_hash' >/dev/null <<<"$skill"; then
    print_error "Skill '$slug' has no approved release; ask its maintainers to publish one."
    return 1
  fi
  release_id=$(jq -r '.release.release_id' <<<"$skill")
  safe_id "$release_id" || { bad_api_value "release id" "$release_id"; return 1; }
  version=$(jq -r '.release.version // "?"' <<<"$skill" | LC_ALL=C tr -d '[:cntrl:]')
  version=$(clean_text "$version")   # also C1 and bidi/format characters; the cleaned string is the version stored and sent, by design
  expected_hash=$(jq -r '.release.canonical_hash | ascii_downcase' <<<"$skill")
  safe_hash "$expected_hash" || { bad_api_value "release hash" "$expected_hash"; return 1; }
  skills_dir=$(runtime_skills_dir "$runtime") || return 1
  dest="$skills_dir/$slug"
  target=$(runtime_target "$runtime")
  if [ "$runtime" = opencode ]; then check_opencode_dir "$skills_dir" || return 1; fi

  [ -d "$skills_dir" ] || created_dir=1
  if [ "$runtime" = opencode ]; then
    # Created 0755 whatever the umask (the OpenCode plugin ignores a group/world-writable dir).
    (umask 022; mkdir -p "$skills_dir") || return 1
  else
    mkdir -p "$skills_dir" || return 1
  fi
  # The lock comes before the leftover check and the classification (D-30).
  trap 'on_install_signal' INT TERM HUP   # before the lock, so a signal never leaves it behind
  if ! mkdir "$dest.allye.lock" 2>/dev/null; then
    trap - INT TERM HUP
    lock_pid_report "$dest.allye.lock" "$slug"
    return 1
  fi
  # Set right after the mkdir. A signal in the few instructions between the mkdir and this
  # assignment (the trap is already armed) leaves the lock behind: a residual window the
  # stale-lock message below covers.
  lock_held=1
  printf '%s\n' "$$" > "$dest.allye.lock/pid" 2>/dev/null || true
  install_locked; rc=$?
  trap - INT TERM HUP
  cleanup_install
  return "$rc"
}

# Deletes $dest only when it is the tree this run published (not a symlink, sidecar operation_id
# equal to $op); anything else at the path belongs to the user. Uses dest and op by dynamic scoping.
remove_published_tree() {
  if [ -n "${op:-}" ] && [ ! -L "$dest" ] && [ "$(jq -r '.operation_id // empty' "$dest/$SIDECAR" 2>/dev/null)" = "$op" ]; then
    rm -rf "$dest"
  else
    print_error "$dest is not the tree this run published; it was left untouched."
  fi
}

# INT/TERM/HUP during an install: release what this run took, put the previous release back when
# the signal came between the move-aside and the publish, and say where an edited copy is. The
# hidden copy is never deleted; the next run reports it (D-35).
on_install_signal() {
  trap - INT TERM HUP
  print_error "Interrupted."
  # published=1 and the stage gone: $dest holds the tree this run published (the move may have
  # completed just before the flag was read, or not at all: then the stage is still there).
  if [ "${published:-0}" = 1 ] && { [ -z "${stage:-}" ] || [ ! -e "$stage" ]; }; then
    # Published but complete not confirmed: put the user's state back, best-effort tell the API.
    remove_published_tree
    published=0
    [ -z "${previous:-}" ] || ! [ -e "$previous" ] || restore_previous || true
    print_error "The API may now be ahead of your disk (it may have recorded this install before the interruption); rerun the installer to reconcile."
    report_failure "$skill_id" "$op" "$token" INTERRUPTED "The install was interrupted before it was recorded; the previous state was restored"
  fi
  # Whatever else is missing at $dest: put the previous release or the edited copy back.
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    if [ -n "${previous:-}" ] && [ -e "$previous" ]; then restore_previous || true; fi
    if [ -n "${hidden:-}" ] && [ -e "$hidden" ]; then restore_backup "$hidden" "$dest" && hidden="" || true; fi
  fi
  if [ -n "${hidden:-}" ] && [ -e "$hidden" ]; then
    print_error "Your edited copy of '$slug' is kept at: $hidden. Move it into ~/.allye/backups/$runtime/ or delete it before the next install of '$slug'."
  fi
  cleanup_install
  exit 130
}

# Runs with the lock held; relies on install_skill's locals through dynamic scoping and never
# releases anything itself: install_skill calls cleanup_install on every exit path.
install_locked() {
  local request_path body op status context token previous="" observed leftover reinstall_kind="" local_hash="" pre_hash="" origin move_code=PUBLISH_FAILED
  local -a leftovers=()

  # A previous release left by a killed run is reported, never touched (NFR-02 covers finished runs).
  for leftover in "$dest".allye.previous.*; do
    if [ -e "$leftover" ] || [ -L "$leftover" ]; then
      print_warning "A previous copy of '$slug' was left at $leftover by an earlier run that did not finish; check it, move it back or delete it if no install is running."
    fi
  done

  # D-35: a .allye-backup.<name>.* entry is a user's edited folder an earlier run kept here.
  # Exactly .allye-backup.<slug>.<UTC YYYYMMDDTHHMMSSZ>.<pid>: another slug that merely starts
  # with this one (foo vs foo.bar) is not a leftover of this skill.
  for leftover in "$skills_dir/.allye-backup.$slug".*; do
    if { [ -e "$leftover" ] || [ -L "$leftover" ]; } && [[ "${leftover#"$skills_dir/.allye-backup.$slug."}" =~ ^[0-9]{8}T[0-9]{6}Z\.[0-9]+$ ]]; then
      leftovers+=("$leftover")
    fi
  done
  if [ "${#leftovers[@]}" -gt 0 ]; then
    print_error "An earlier run kept an edited copy of '$slug' next to your skills; nothing was changed and the installer will not touch '$slug' until it is dealt with:"
    for leftover in "${leftovers[@]}"; do print_error "  $leftover"; done
    print_error "  Move each into ~/.allye/backups/$runtime/ to keep it, or delete it, then rerun."
    return 1
  fi

  # Classify (BR-01, D-23): foreign, unmanaged and unhashable trees are never touched.
  state=$(classify_target "$dest" "$skill_id" "$target")
  case "$state" in
    missing) reinstall_kind=missing ;;
    owned-intact)
      if [ "$(jq -r '.release_id' "$dest/$SIDECAR")" = "$release_id" ]; then
        print_success "$slug $version is already installed for $runtime"
        return 0
      fi ;;
    owned-other-target-intact)
      print_step "$dest was recorded for another location or machine and is unchanged; reinstalling '$slug' here."
      reinstall_kind=missing ;;
    owned-modified|owned-other-target-modified)
      if [ "$state" = owned-modified ]; then
        print_error "$dest no longer matches the release that was installed; it was left untouched."
      else
        print_error "$dest was recorded for another location or machine and has been edited since; it was left untouched."
      fi
      if [ "${ALLYE_REINSTALL:-0}" != 1 ]; then
        print_error "  To replace it, rerun with --reinstall: your edited copy is kept under ~/.allye/backups/$runtime/."
        return 1
      fi
      hash_tree "$dest"   # classify_target just hashed this tree successfully
      local_hash="$TREE_HASH"
      check_backups_root "$runtime" || return 1
      reinstall_kind=modified ;;
    unhashable)
      hash_tree "$dest" || true
      print_error "Refusing $dest: ${TREE_ERR:-it holds an entry that cannot be hashed}. Move or remove that entry, then retry; nothing was changed."
      return 1 ;;
    foreign) print_error "$dest belongs to another Allye skill; --reinstall never replaces it. Move or rename it, then retry."; return 1 ;;
    *) print_error "$dest already exists and was not installed by Allye; --reinstall never replaces it. It was left untouched."; return 1 ;;
  esac

  case "$state" in *-intact) pre_hash=$(jq -r '.canonical_hash' "$dest/$SIDECAR") ;; esac

  # A stage left by a killed run (or a concurrent install of another skill) is reported, never touched.
  for leftover in "$skills_dir"/.allye-stage.*; do
    if [ -e "$leftover" ]; then
      print_warning "$skills_dir holds .allye-stage.* entries (for example $leftover): a killed install may have left them; delete them if no install is running."
      break
    fi
  done

  tmp=$(mktemp -d) || return 1
  stage=$(mktemp -d "$skills_dir/.allye-stage.XXXXXX") || return 1

  # 2. Download and verify the release bytes before touching the ledger.
  if ! api_call GET "/api/skills/$skill_id/releases/$release_id/artifact?canonicalHash=$expected_hash"; then
    api_error "Downloading '$slug' $version"; return 1
  fi
  printf '%s' "$API_BODY" > "$tmp/artifact.json"
  jq -cn --arg s "$skill_id" --arg r "$release_id" --arg h "$expected_hash" '{skill_id:$s, release_id:$r, canonical_hash:$h}' > "$tmp/expected.json"
  if ! node "$SKILL_TOOL" stage-artifact "$tmp/artifact.json" "$tmp/expected.json" "$stage" >/dev/null 2>"$tmp/err"; then
    print_error "Refusing '$slug' $version: $(clean_text "$(cat "$tmp/err")")"; return 1
  fi

  # 3. Open the distribution for this machine: update when we own an older release, otherwise
  # a request, which carries `reinstall` when the local copy is missing or edited (D-05, D-21).
  body=$(jq -cn --arg s "$skill_id" --arg r "$release_id" --arg rt "$api_runtime" --arg v "$(jq -r '.contractVersion' "$ADAPTERS_FILE")" \
    --argjson exp "$allow_exp" --arg t "$target" --arg k "$target:$release_id:$(random_id)" \
    '{skillId:$s, releaseId:$r, runtime:$rt, runtimeVersion:$v, allowExperimental:$exp, target:$t, idempotencyKey:$k}')
  request_path=request
  case "$reinstall_kind" in
    missing) body=$(jq -c '. + {reinstall:{observedLocalState:"missing"}}' <<<"$body") ;;
    modified) body=$(jq -c --arg h "$local_hash" '. + {reinstall:{observedLocalState:"modified", observedLocalHash:$h}}' <<<"$body") ;;
    *)
      request_path=update
      body=$(jq -c --arg b "$(jq -r '.release_id' "$dest/$SIDECAR")" --arg o "$(jq -r '.canonical_hash' "$dest/$SIDECAR")" '. + {baseReleaseId:$b, observedHash:$o}' <<<"$body") ;;
  esac
  if ! api_call POST "/api/skills/$skill_id/distributions/$request_path" "$body"; then
    api_error "Requesting the $runtime distribution of '$slug'"; return 1
  fi
  op=$(api_data | jq -r '.operationId // .distributionId // empty')
  status=$(api_data | jq -r '.status')
  if [ "$status" = pending ]; then safe_id "$op" || { bad_api_value "operation id" "$op"; return 1; }; fi
  case "$status" in
    pending) ;;
    noop) print_error "The API records '$slug' $version as already installed for this machine ($runtime), but $dest does not hold a usable copy, and this API did not accept the reinstall. Upgrade the installer, or contact the operator of your Allye API."; return 1 ;;
    *) print_error "The API answered '$(clean_text "$status")' for '$slug' on $runtime: $(clean_text "$(api_data | jq -r '[.failureCode, .diagnostic] | map(select(.)) | join(" — ")')")"; return 1 ;;
  esac
  origin=$(api_data | jq -r '.origin // empty')
  if [ "$origin" = "api:reinstall" ]; then
    print_step "The API recorded this install as a reinstall of '$slug' on this machine."
  fi

  # 4. Signed execution token, verified against the API's JWKS.
  if ! api_call POST "/api/skills/$skill_id/distributions/$op/execution-context"; then
    api_error "Obtaining the execution token for '$slug'"
    report_failure "$skill_id" "$op" @pat EXECUTION_CONTEXT_FAILED "The execution token could not be issued"; return 1
  fi
  context=$(api_data)
  token=$(jq -r '.executionToken' <<<"$context")
  printf '%s' "$context" > "$tmp/context.json"
  if ! jq -e --arg s "$skill_id" --arg r "$release_id" --arg h "$expected_hash" --arg rt "$api_runtime" --arg t "$target" --arg op "$op" \
      '.operationId == $op and .skillId == $s and .releaseId == $r and (.expectedHash|ascii_downcase) == $h and .runtime == $rt and .target == $t' \
      "$tmp/context.json" >/dev/null; then
    print_error "The execution context for '$slug' does not match the requested release; nothing was installed."
    report_failure "$skill_id" "$op" "$token" CONTEXT_MISMATCH "Execution context differs from the requested release"; return 1
  fi
  if ! api_call GET "/api/skills/distribution-execution/jwks" "" "-"; then
    api_error "Fetching the API signing keys"; report_failure "$skill_id" "$op" "$token" JWKS_UNAVAILABLE "Installer could not fetch the JWKS"; return 1
  fi
  printf '%s' "$API_BODY" > "$tmp/jwks.json"
  if ! node "$SKILL_TOOL" verify-token "$tmp/context.json" "$tmp/jwks.json" 2>"$tmp/err"; then
    print_error "Refusing '$slug': $(clean_text "$(cat "$tmp/err")")"
    report_failure "$skill_id" "$op" "$token" TOKEN_INVALID "$(LC_ALL=C tr -d '[:cntrl:]' < "$tmp/err")"; return 1
  fi

  # 5. Preflight with the execution token.
  if ! api_call POST "/api/skills/$skill_id/distributions/$op/preflight" "" "$token"; then
    api_error "Preflight of '$slug'"; report_failure "$skill_id" "$op" "$token" PREFLIGHT_REJECTED "Preflight was rejected"; return 1
  fi
  if ! api_data | jq -e --arg op "$op" --arg h "$expected_hash" '.operationId == $op and .status == "pending" and (.expectedHash|ascii_downcase) == $h' >/dev/null; then
    print_error "Preflight of '$slug' did not confirm a pending operation for this release."
    report_failure "$skill_id" "$op" "$token" PREFLIGHT_MISMATCH "Preflight response does not match"; return 1
  fi

  # 6. Publish the verified tree with its provenance sidecar.
  jq -n --arg skill "$skill_id" --arg slug "$slug" --arg release "$release_id" --arg version "$version" --arg hash "$expected_hash" \
    --argjson origin "$(jq -c '.origin // null' "$tmp/context.json")" --arg runtime "$runtime" --arg target "$target" --arg op "$op" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg installer "allye-installer/$ALLYE_INSTALLER_VERSION" \
    '{skill_id:$skill, slug:$slug, release_id:$release, version:$version, canonical_hash:$hash, origin:$origin,
      runtime:$runtime, target:$target, operation_id:$op, installed_at:$at, installer:$installer}' > "$stage/$SIDECAR"
  if [ "$reinstall_kind" = modified ]; then
    move_aside_edited || { report_failure "$skill_id" "$op" "$token" "$move_code" "Your edited copy was not replaced"; return 1; }
  else
    swap_out_previous || { report_failure "$skill_id" "$op" "$token" "$move_code" "The previous tree was not replaced"; return 1; }
  fi
  published=1   # set before the move: a signal right after it must still roll the publish back
  if ! move_dir "$stage" "$dest"; then
    published=0
    [ -z "$previous" ] || restore_previous || true
    [ -z "$hidden" ] || ! restore_backup "$hidden" "$dest" || hidden=""
    print_error "Could not publish '$slug' into $skills_dir; the previous state was restored."
    report_failure "$skill_id" "$op" "$token" PUBLISH_FAILED "Could not publish the tree"; return 1
  fi
  if hash_tree "$dest"; then observed="$TREE_HASH"; else observed=""; fi
  body=$(jq -cn --arg h "$observed" --arg v "allye-installer/$ALLYE_INSTALLER_VERSION ($runtime)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{observedHash:$h, runtimeVersion:$v, verifiedAt:$at, installKind:"directory"}')
  if [ "$observed" != "$expected_hash" ] || ! api_call POST "/api/skills/$skill_id/distributions/$op/complete" "$body" "$token"; then
    [ "$observed" = "$expected_hash" ] && api_error "Recording the installation of '$slug'" || print_error "Published tree of '$slug' does not match its release hash."
    remove_published_tree
    published=0   # $dest no longer holds this run's tree: a signal below must not delete what is restored
    [ -z "$previous" ] || restore_previous || true
    [ -z "$hidden" ] || ! restore_backup "$hidden" "$dest" || hidden=""
    report_failure "$skill_id" "$op" "$token" COMPLETION_REJECTED "Installation evidence was not accepted; the previous state was restored"
    return 1
  fi
  published=0
  [ -z "$previous" ] || rm -rf "$previous"
  print_success "$slug $version installed for $runtime → $dest"
  if [ "$runtime" = opencode ] && [ "$created_dir" = 1 ]; then
    echo "  Created $skills_dir: restart OpenCode to load it."
  fi
  if [ -n "$hidden" ]; then finalize_backup || return 1; fi
}

# Used by install_skill on every exit path once it started; relies on its locals through
# dynamic scoping. The lock is only removed when this run took it.
cleanup_install() {
  [ -z "${stage:-}" ] || rm -rf "$stage"
  [ -z "${tmp:-}" ] || rm -rf "$tmp"
  if [ "${lock_held:-0}" = 1 ]; then rm -f "$dest.allye.lock/pid"; rmdir "$dest.allye.lock" 2>/dev/null || true; fi
}

# ─── Verbs ──────────────────────────────────────────────────────────────────

allye_list() {  # [scope] [query]
  local scope="${1:-}" query="${2:-}" path="/api/skills?officialOnly=true&limit=100"
  [ -z "$scope" ] || path+="&scope=$(jq -rn --arg s "$scope" '$s|@uri')"
  [ -z "$query" ] || path+="&query=$(jq -rn --arg q "$query" '$q|@uri')"
  api_call GET "$path" || { api_error "Listing skills"; return 1; }
  jq -r '
    def clean: tostring | explode | map(select(. > 31 and (. < 127 or . > 159) and ((. >= 8203 and . <= 8207) | not) and ((. >= 8232 and . <= 8238) | not) and ((. >= 8294 and . <= 8297) | not))) | implode;   # no ASCII or C1 controls, no bidi/format characters
    (.data // .) as $page | ($page.data // $page) as $items
    | if ($items | length) == 0 then "  (no approved skills are visible to you)"
      else $items[] | "  \(.slug // "-" | clean)\t\(.release.version // "no release" | clean)\t\(.scope | clean)\t\(.name | clean)\t\(.id | clean)" end
  ' <<<"$API_BODY" | column -t -s $'\t'
}

allye_install() {  # $1 = runtime, $2... = skill ids or slugs
  local runtime="$1" ok=0 failed=0 ref
  shift
  [ -n "$(runtime_json "$runtime")" ] || { print_error "Unknown runtime '$runtime'. Supported: $(runtime_ids | paste -sd' ')"; return 2; }
  [ "$#" -gt 0 ] || { print_error "Name at least one skill (slug or id). Run './install.sh list' to see them."; return 2; }
  runtime_skills_dir "$runtime" >/dev/null || return 2
  runtime_detected "$runtime" || print_warning "$runtime was not detected on this machine; installing into $(runtime_skills_dir "$runtime") anyway."
  for ref in "$@"; do
    if install_skill "$runtime" "$ref"; then ok=$((ok + 1)); else failed=$((failed + 1)); fi
  done
  echo ""
  echo "  $ok installed or up to date, $failed failed"
  [ "$failed" -eq 0 ]
}

allye_status() {  # offline: what is installed, and is it intact?
  local id label dir marker any slug state target
  while IFS= read -r id; do
    label=$(runtime_json "$id" | jq -r '.label')
    dir=$(runtime_skills_dir "$id" 2>/dev/null) || { printf '  %-16s invalid home override (must be absolute)\n' "$label"; continue; }
    if ! runtime_detected "$id"; then printf '  %-16s not detected\n' "$label"; continue; fi
    any=0
    target=$(runtime_target "$id")
    for marker in "$dir"/*/"$SIDECAR"; do
      [ -f "$marker" ] || continue
      any=1
      slug=$(clean_text "$(basename "$(dirname "$marker")")")
      state=$(classify_target "$(dirname "$marker")" "$(jq -r '.skill_id' "$marker")" "$target")
      case "$state" in
        owned-intact) state=intact ;;
        owned-other-target-intact) state="intact (other target)" ;;
        unhashable) state="cannot be hashed" ;;
        *) state="modified locally" ;;
      esac
      printf '  %-16s %-28s %-10s %s\n' "$label" "$slug" "$(clean_text "$(jq -r '.version' "$marker")")" "$state"
    done
    [ "$any" = 1 ] || printf '  %-16s no Allye skills installed in %s\n' "$label" "$dir"
  done < <(runtime_ids)
}
