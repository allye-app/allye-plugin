#!/bin/bash
# ALY-85: the OpenCode install and update guides, executed. Their fenced bash blocks are
# extracted by heading and run in a sandbox (env -i, temp HOME and XDG_CONFIG_HOME, stubbed
# curl/npm/opencode): invalid JSON is left byte-identical, a mixed config converges to one
# allye MCP entry and one pinned allye-opencode plugin in place with options kept, rerun is
# byte-identical, backups are private and named .allye.backup., a jsonc-only config is
# refused, a failed backup changes nothing, a downgrade (or an uncomparable version) stops
# before any write, and a differing MCP entry never prints secrets.
# Offline. ALLYE_GATE_DOCS_ROOT (default: the repo) points at a copy of docs/ for the
# mutation check. Runnable alone; exits 0 or 1.
set -u
# shellcheck source=install/docs-gate/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DOCS_ROOT="${ALLYE_GATE_DOCS_ROOT:-$ROOT}"

# Stubs (PATH is prepended to the real PATH inside env -i).
BIN="$TMP/bin"; BINCP="$TMP/bincp"; BINSORT="$TMP/binsort"; mkdir -p "$BIN" "$BINCP" "$BINSORT"
cat >"$BIN/curl" <<'SH'
#!/bin/bash
[ "${FAKE_CURL:-ok}" = fail ] && exit 22
echo '{"tag_name":"v9.9.9"}'
SH
cat >"$BIN/npm" <<'SH'
#!/bin/bash
echo "npm $*" >>"${FAKE_LOG:-/dev/null}"
[ "${FAKE_NPM:-ok}" = missing ] && exit 1
ver="${2#allye-opencode@}"
if [ "${3:-}" = dist.integrity ]; then echo "sha512-FAKE"; else echo "$ver"; fi
SH
cat >"$BIN/opencode" <<'SH'
#!/bin/bash
echo "opencode $*" >>"${FAKE_LOG:-/dev/null}"
SH
cat >"$BINCP/cp" <<SH
#!/bin/bash
for a in "\$@"; do case "\$a" in *.allye.backup.*) exit 1 ;; esac; done
exec "$(command -v cp)" "\$@"
SH
cat >"$BINSORT/sort" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$BIN"/* "$BINCP/cp" "$BINSORT/sort"

# doc_block <file> <heading prefix>: the first bash block under that heading.
doc_block() {
  awk -v h="$2" 'index($0, h) == 1 {on=1; next} on && /^```bash$/ {inb=1; next} inb && /^```$/ {exit} inb {print}' "$1"
}

# sandbox_guard <home>: abort the whole gate unless HOME and the config dir resolve under $TMP.
sandbox_guard() {
  local root home real sub
  root=$(cd "$TMP" && pwd -P)
  home=$(cd "$1" 2>/dev/null && pwd -P) || home=""
  case "$home" in
    "$root"/*) ;;
    *) echo "$NAME: sandbox guard: HOME '$1' is outside $TMP; aborting" >&2; kill -s TERM $$; exit 1 ;;
  esac
  for sub in .config .config/opencode .allye; do
    if [ -e "$1/$sub" ] || [ -L "$1/$sub" ]; then
      real=$(readlink -f "$1/$sub")
      case "$real" in
        "$root"/*) ;;
        *) echo "$NAME: sandbox guard: $1/$sub resolves to $real, outside $TMP; aborting" >&2; kill -s TERM $$; exit 1 ;;
      esac
    fi
  done
}

N=0
# og <guide: install|update> <home> <version> [ENV=value...]
# Runs Step 1 (version, RAW set to <version>), Step 2 (npm) and Step 3 (write) of the
# guide as one script. Sets OUT, RC and LOG.
og() {
  local g="$1" h="$2" v="$3" f line
  shift 3
  f="$DOCS_ROOT/docs/$g-opencode.md"
  N=$((N + 1))
  {
    while IFS= read -r line; do
      case "$line" in "RAW=''"*) printf 'RAW=%q\n' "$v" ;; *) printf '%s\n' "$line" ;; esac
    done < <(doc_block "$f" '## Step 1:')
    doc_block "$f" '## Step 2:'
    doc_block "$f" '## Step 3:'
  } >"$TMP/run$N.sh"
  [ -s "$TMP/run$N.sh" ] || fail "$g: guide blocks not found"
  sandbox_guard "$h"
  LOG="$TMP/log$N"; : >"$LOG"
  RC=0
  OUT=$(env -i PATH="$BIN:$PATH" HOME="$h" XDG_CONFIG_HOME="$h/.config" TMPDIR="$h/t" FAKE_LOG="$LOG" "$@" bash -u "$TMP/run$N.sh" 2>&1) || RC=$?
}
# og_verify <guide> <home> <version>: update Step 4.
og_verify() {
  local f="$DOCS_ROOT/docs/update-opencode.md"
  N=$((N + 1))
  doc_block "$f" '## Step 4:' >"$TMP/run$N.sh"
  [ -s "$TMP/run$N.sh" ] || fail "update: Step 4 block not found"
  sandbox_guard "$2"
  RC=0
  OUT=$(env -i PATH="$BIN:$PATH" HOME="$2" XDG_CONFIG_HOME="$2/.config" VERSION="$3" bash -u "$TMP/run$N.sh" 2>&1) || RC=$?
}
newhome() { local h; h=$(mktemp -d "$TMP/home.XXXXXX"); mkdir -p "$h/.config/opencode" "$h/t"; echo "$h"; }
sum() { cksum <"$1"; }
backups() { find "$1/.allye/backups/opencode" -type f -name 'opencode.json.allye.backup.*' 2>/dev/null | wc -l | tr -d ' '; }

MIXED='{"$schema":"https://opencode.ai/config.json","theme":"system","mcp":{"x":{"type":"local","command":["x"]},"allye-mcp":{"type":"remote","url":"https://old"}},"plugin":["foo","allye-opencode","baz","allye-opencode@1.0.0",["allye-opencode@2.0.0",{"a":1}],"bar"]}'

for G in install update; do
  # Version step: valid forms, refusal of junk, npm existence.
  h=$(newhome); C="$h/.config/opencode/opencode.json"; echo '{"plugin":[]}' >"$C"
  og $G "$h" 'v2.8.0'; [ "$RC" -eq 0 ] || fail "$G: version v2.8.0 refused: $OUT"
  jq -e '.plugin == ["allye-opencode@2.8.0"]' "$C" >/dev/null || fail "$G: v-prefixed version not pinned without v"
  for bad in '1.0' $'2.8.0\nrm -rf x' "2.8.0'; touch $TMP/pwn; '" 'main'; do
    h=$(newhome); C="$h/.config/opencode/opencode.json"; echo '{"plugin":[]}' >"$C"; before=$(sum "$C")
    og $G "$h" "$bad"
    [ "$RC" -ne 0 ] || fail "$G: junk version accepted: $bad"
    [ "$before" = "$(sum "$C")" ] || fail "$G: junk version changed the config"
    [ ! -e "$TMP/pwn" ] || fail "$G: junk version executed"
    [ ! -e "$h/.allye" ] || fail "$G: junk version made a backup dir"
  done
  h=$(newhome); C="$h/.config/opencode/opencode.json"; echo '{"plugin":[]}' >"$C"; before=$(sum "$C")
  og $G "$h" '2.8.0' FAKE_NPM=missing
  [ "$RC" -ne 0 ] && [ "$before" = "$(sum "$C")" ] || fail "$G: version missing on npm did not stop before any change"
  h=$(newhome); echo '{"plugin":[]}' >"$h/.config/opencode/opencode.json"
  og $G "$h" '' FAKE_CURL=fail
  [ "$RC" -ne 0 ] || fail "$G: failed release lookup accepted"
  h=$(newhome); echo '{"plugin":[]}' >"$h/.config/opencode/opencode.json"
  og $G "$h" ''
  [ "$RC" -eq 0 ] && grep -q '9.9.9' <<<"$OUT" || fail "$G: latest release not used when RAW is empty: $OUT"

  # (a) invalid JSON: unchanged, refused, no ~/.allye.
  h=$(newhome); C="$h/.config/opencode/opencode.json"; printf '{bad,\n' >"$C"; before=$(sum "$C")
  og $G "$h" '2.8.0'
  [ "$RC" -ne 0 ] || fail "$G (a): invalid JSON accepted"
  [ "$before" = "$(sum "$C")" ] || fail "$G (a): invalid JSON changed"
  [ ! -e "$h/.allye" ] || fail "$G (a): invalid JSON made ~/.allye"
  grep -qi 'not valid JSON' <<<"$OUT" || fail "$G (a): parse error not reported: $OUT"
  ls -A "$h/.config/opencode" | grep -q '^\.opencode\.json\.' && fail "$G (a): temp file left"

  # (b)+(c) mixed config converges; backup private and named; rerun byte-identical.
  h=$(newhome); C="$h/.config/opencode/opencode.json"; echo "$MIXED" >"$C"; chmod 640 "$C"
  og $G "$h" '2.8.0'
  [ "$RC" -eq 0 ] || fail "$G (b): run failed: $OUT"
  jq -e '.plugin == ["foo",["allye-opencode@2.8.0",{"a":1}],"baz","bar"]' "$C" >/dev/null || fail "$G (b): plugin not pinned in place with options kept: $(jq -c .plugin "$C")"
  jq -e '(.mcp | has("allye-mcp") | not) and .mcp.allye == {"type":"remote","url":"https://mcp.allye.app/mcp","enabled":true} and .mcp.x.command == ["x"] and .theme == "system" and ."$schema" != null' "$C" >/dev/null || fail "$G (b): mcp/unrelated entries wrong: $(jq -c . "$C")"
  [ "$(stat -c %a "$C")" = 640 ] || fail "$G (b): config mode not preserved"
  [ "$(grep -c 'opencode mcp logout allye-mcp' "$LOG")" -eq 1 ] || fail "$G (b): legacy logout not called once"
  bp=$(sed -n 's/^Backup: //p' <<<"$OUT" | head -n 1)
  case "$bp" in "$h/.allye/backups/opencode/opencode.json.allye.backup."*) ;; *) fail "$G (c): backup path not reported: $OUT" ;; esac
  [ -f "$bp" ] || fail "$G (c): reported backup missing"
  [ "$(stat -c %a "$bp")" = 600 ] || fail "$G (c): backup mode is not 600"
  [ "$(stat -c %a "$h/.allye/backups/opencode")" = 700 ] || fail "$G (c): backup dir mode is not 700"
  [ "$(echo "$MIXED" | jq -S -c .)" = "$(jq -S -c . "$bp")" ] || fail "$G (c): backup is not the original config"
  s1=$(sum "$C")
  og $G "$h" '2.8.0'
  [ "$RC" -eq 0 ] && [ "$s1" = "$(sum "$C")" ] || fail "$G (b): rerun same version is not byte-identical (rc $RC)"
  [ "$(backups "$h")" -eq 2 ] || fail "$G (b): rerun did not add exactly one backup (have $(backups "$h"))"
  og $G "$h" '2.9.0'
  jq -e '.plugin == ["foo",["allye-opencode@2.9.0",{"a":1}],"baz","bar"]' "$C" >/dev/null || fail "$G (b): newer version did not replace the pin: $(jq -c .plugin "$C")"
  [ "$(jq -c '[.mcp | keys[] | select(. == "allye")] | length' "$C")" = 1 ] || fail "$G (b): not exactly one allye entry"

  # (d) jsonc only: refused, no opencode.json created.
  h=$(newhome); echo '{}' >"$h/.config/opencode/opencode.jsonc"
  og $G "$h" '2.8.0'
  [ "$RC" -ne 0 ] || fail "$G (d): jsonc-only accepted"
  [ ! -e "$h/.config/opencode/opencode.json" ] || fail "$G (d): opencode.json created next to jsonc"

  # (e) failed backup leaves the config unchanged.
  h=$(newhome); C="$h/.config/opencode/opencode.json"; echo "$MIXED" >"$C"; before=$(sum "$C")
  sandbox_guard "$h"
  N=$((N + 1)); RC=0
  { while IFS= read -r line; do case "$line" in "RAW=''"*) printf "RAW='2.8.0'\n" ;; *) printf '%s\n' "$line" ;; esac; done < <(doc_block "$DOCS_ROOT/docs/$G-opencode.md" '## Step 1:')
    doc_block "$DOCS_ROOT/docs/$G-opencode.md" '## Step 2:'; doc_block "$DOCS_ROOT/docs/$G-opencode.md" '## Step 3:'; } >"$TMP/run$N.sh"
  OUT=$(env -i PATH="$BINCP:$BIN:$PATH" HOME="$h" XDG_CONFIG_HOME="$h/.config" FAKE_LOG="$TMP/l" bash -u "$TMP/run$N.sh" 2>&1) || RC=$?
  [ "$RC" -ne 0 ] || fail "$G (e): failed backup accepted"
  [ "$before" = "$(sum "$C")" ] || fail "$G (e): failed backup changed the config"
  ls -A "$h/.config/opencode" | grep -q '^\.opencode\.json\.' && fail "$G (e): temp file left"
done

# Update-only: (f) downgrade, (g) secrets, verify step.
h=$(newhome); C="$h/.config/opencode/opencode.json"; echo '{"plugin":["allye-opencode@2.9.0"]}' >"$C"; before=$(sum "$C")
og update "$h" '2.0.0'
[ "$RC" -ne 0 ] && [ "$before" = "$(sum "$C")" ] && [ ! -e "$h/.allye" ] || fail "update (f): downgrade not blocked before any write"
og update "$h" '2.0.0' ALLYE_ALLOW_DOWNGRADE=1
[ "$RC" -eq 0 ] && jq -e '.plugin == ["allye-opencode@2.0.0"]' "$C" >/dev/null || fail "update (f): confirmed downgrade not applied: $OUT"
og update "$h" '2.5.0'
[ "$RC" -eq 0 ] && jq -e '.plugin == ["allye-opencode@2.5.0"]' "$C" >/dev/null || fail "update (f): upgrade failed: $OUT"
og_verify update "$h" '2.5.0'
[ "$RC" -eq 0 ] && grep -q 'OK: configured pin is allye-opencode@2.5.0' <<<"$OUT" || fail "update Step 4: did not confirm the pin: $OUT"
og_verify update "$h" '2.6.0'
[ "$RC" -ne 0 ] || fail "update Step 4: wrong pin accepted"

# sort -V unavailable: fail closed.
h=$(newhome); C="$h/.config/opencode/opencode.json"; echo '{"plugin":["allye-opencode@2.0.0"]}' >"$C"; before=$(sum "$C")
f="$DOCS_ROOT/docs/update-opencode.md"; N=$((N + 1)); RC=0
{ while IFS= read -r line; do case "$line" in "RAW=''"*) printf "RAW='3.0.0'\n" ;; *) printf '%s\n' "$line" ;; esac; done < <(doc_block "$f" '## Step 1:')
  doc_block "$f" '## Step 2:'; doc_block "$f" '## Step 3:'; } >"$TMP/run$N.sh"
sandbox_guard "$h"
OUT=$(env -i PATH="$BINSORT:$BIN:$PATH" HOME="$h" XDG_CONFIG_HOME="$h/.config" FAKE_LOG="$TMP/l" bash -u "$TMP/run$N.sh" 2>&1) || RC=$?
[ "$RC" -ne 0 ] && [ "$before" = "$(sum "$C")" ] && [ ! -e "$h/.allye" ] || fail "update (f): failing sort did not stop before any write"
RC=0
OUT=$(env -i PATH="$BINSORT:$BIN:$PATH" HOME="$h" XDG_CONFIG_HOME="$h/.config" FAKE_LOG="$TMP/l" ALLYE_ALLOW_DOWNGRADE=1 bash -u "$TMP/run$N.sh" 2>&1) || RC=$?
[ "$RC" -eq 0 ] && jq -e '.plugin == ["allye-opencode@3.0.0"]' "$C" >/dev/null || fail "update (f): confirmation did not override a failing sort: $OUT"

# (g) differing mcp.allye: left as is, no secret values printed.
h=$(newhome); C="$h/.config/opencode/opencode.json"
echo '{"mcp":{"allye":{"type":"remote","url":"https://mcp.allye.app/mcp?token=URLSECRET","enabled":true,"headers":{"Authorization":"HDRSECRET"}}},"plugin":[]}' >"$C"
og update "$h" '2.8.0'
[ "$RC" -eq 0 ] || fail "update (g): run failed: $OUT"
! grep -q 'URLSECRET\|HDRSECRET' <<<"$OUT" || fail "update (g): secret values printed"
jq -e '.mcp.allye.headers.Authorization == "HDRSECRET"' "$C" >/dev/null || fail "update (g): differing entry was modified"

finish
