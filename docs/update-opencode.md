# Allye — OpenCode update guide

You are an AI agent helping the user update the `allye-opencode` plugin. The plugin is pinned in `opencode.json` as `allye-opencode@<version>`; updating means moving that pin to a newer release. Do not run an unpinned package update.

## Step 1: Resolve the version

Run all the blocks of this guide in one shell session (or as one script): the version resolved here is used by every later block, and each later block starts with a guard that stops when `VERSION` is missing or malformed. Do this before any change. Set `RAW` only when you have checked the user's text as a whole against `^v?[0-9]+\.[0-9]+\.[0-9]+$` (digits, dots, optional leading `v`); otherwise leave it empty to use the latest release of `allye-app/allye-plugin`. Never paste user text into a command otherwise.

```bash
# Rule: never place user text in the script unless it already matched ^v?[0-9]+\.[0-9]+\.[0-9]+$; write only the matched digits and dots (never the original text, never a value containing a quote)
RAW=''   # set to the version only if you checked the user's text as a whole against ^v?[0-9]+\.[0-9]+\.[0-9]+$ (digits, dots, optional leading v); otherwise leave empty
[ -n "$RAW" ] || RAW=$(curl -fsSL https://api.github.com/repos/allye-app/allye-plugin/releases/latest | jq -r '.tag_name // empty')
RAW="${RAW#v}"
if ! [[ "$RAW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "No valid release version could be resolved" >&2; return 1 2>/dev/null || exit 1; fi
VERSION="$RAW"
echo "Updating Allye to $VERSION"
```

Any failing block exits the shell session: stop and report to the user; do not continue with later blocks. Tell the user which version you are updating to. If no valid version resolves, stop before any change and report it.

## Step 2: Check the package exists on npm

If this fails or prints nothing, stop before any change. This checks that the version exists and shows its `dist.integrity`; it is not a provenance or signature check. It runs from your home directory so a project `.npmrc` cannot redirect it. Show the user the printed `dist.integrity`:

```bash
: "${VERSION:?run the version step first}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
NPMV=$(cd "$HOME" && npm view allye-opencode@"$VERSION" version) && [ -n "$NPMV" ] || { echo "allye-opencode@$VERSION is not on npm" >&2; return 1 2>/dev/null || exit 1; }
echo "npm has allye-opencode@$NPMV"
(cd "$HOME" && npm view allye-opencode@"$VERSION" dist.integrity)
```

## Step 3: Pin the new version

Safety rules the block implements:

- If there is no `opencode.json` (or only `opencode.jsonc`), it stops and reports to the user (a jsonc config must be migrated or edited by hand); it never creates a second config next to `opencode.jsonc`.
- The config is validated first: invalid JSON leaves the file byte-for-byte unchanged, nothing is backed up, and you report the parse error.
- The config directory is `$XDG_CONFIG_HOME/opencode` when `XDG_CONFIG_HOME` is an absolute path other than `/`; an empty, relative or all-slash value counts as unset (trailing slashes are stripped first) and falls back to `~/.config/opencode`.
- A symlinked config is resolved (`readlink -f` needs GNU coreutils or macOS 12.3+), and the file mode is preserved. A dangling symlink at `opencode.json` stops the run.
- A `plugin` value that is not an array makes the transform fail, and the config is left unchanged.
- Close OpenCode before running this (a running OpenCode may rewrite the file). A shell killed mid-run can leave a `.opencode.json.XXXXXX` temp file (mode 600) in the config directory; delete it. The existing config is copied first (private, mode 600) to `~/.allye/backups/opencode/opencode.json.allye.backup.<UTC ts>`, and the new content is transformed from that copy into a temporary file in the same directory. If the copy fails, or the config changed since the copy, the config is left unchanged. The path is reported only after the config was replaced; on a failure after the backup, the message names the kept backup. Backups accumulate in `~/.allye/backups/opencode/`; tell the user where they are so they can prune them.
- The pin replaces the existing `allye-opencode` entry in place (same position; appended only when absent). jq rewrites the file, so its formatting is normalised and large numbers or duplicate keys may be normalised too; the backup has the original bytes. Only the file mode is preserved, not ownership or group.
- If the configured pin is newer than `$VERSION`, the block stops before any write (also when the versions cannot be compared, e.g. a `sort` without `-V`); only after the user confirms the downgrade, set `ALLYE_ALLOW_DOWNGRADE=1` and rerun. After a write, the backup is the rollback.
- Any other `allye-opencode` plugin entry (unpinned, another version, or array form `["allye-opencode", {...}]`) is replaced by the pin; an array-form entry keeps its options and only its first element is re-pinned. The config ends with exactly one `allye-opencode@$VERSION` plugin entry; unrelated entries are untouched.
- The `allye` MCP entry is set only when it is missing; when it differs from the Allye default it is left as is and the block reports it, so tell the user. The legacy `allye-mcp` entry is dropped, and `opencode mcp logout allye-mcp` runs after the config was replaced when it was present; a logout failure is reported to the user and is not fatal. The `MCP entry` line prints only booleans, the JSON type of `enabled` and the extra key names, never values (a url or headers may carry secrets).

```bash
: "${VERSION:?run the version step first}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
X="${XDG_CONFIG_HOME:-}"
case "$X" in /*) ;; *) X="" ;; esac
while [ "${X%/}" != "$X" ]; do X="${X%/}"; done
[ -n "$X" ] || X="$HOME/.config"
DIR="$X/opencode"
CFG="$DIR/opencode.json"
if [ -L "$CFG" ] && [ ! -e "$CFG" ]; then echo "opencode.json is a dangling symlink; left unchanged" >&2; exit 1; fi
[ -e "$CFG" ] || { echo "No opencode.json in $DIR: report this to the user; a jsonc config must be migrated or edited by hand" >&2; exit 1; }
CFG=$(readlink -f "$CFG") || { echo "could not resolve opencode.json; left unchanged" >&2; exit 1; }
[ -f "$CFG" ] || { echo "opencode.json is not a regular file; left unchanged" >&2; exit 1; }
jq -e . "$CFG" >/dev/null || { echo "opencode.json is not valid JSON; left unchanged" >&2; exit 1; }
CUR=$(jq -r 'try ([(.plugin // [])[] | (if type == "array" then .[0] else . end) | select(type == "string" and startswith("allye-opencode@"))] | first // "" | ltrimstr("allye-opencode@")) catch ""' "$CFG")
if [[ "$CUR" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$CUR" != "$VERSION" ] && [ "${ALLYE_ALLOW_DOWNGRADE:-}" != 1 ]; then
  LOW=$(printf '%s\n%s\n' "$CUR" "$VERSION" | sort -V | head -n 1)
  if [ "$LOW" != "$CUR" ]; then
    echo "Configured allye-opencode@$CUR is newer than $VERSION, or the versions could not be compared: treating this as a downgrade. Nothing was changed. Ask the user; only if they confirm, set ALLYE_ALLOW_DOWNGRADE=1 and rerun this block." >&2
    exit 1
  fi
fi
BD="$HOME/.allye/backups/opencode"
( umask 077; mkdir -p "$BD" )
chmod 700 "$BD"
B="$BD/opencode.json.allye.backup.$(date -u +%Y%m%dT%H%M%SZ)"
[ -e "$B" ] && B="$B-$$"
( umask 077; cp "$CFG" "$B" ) || { echo "backup failed; left unchanged" >&2; exit 1; }
chmod 600 "$B"
LEGACY=$(jq -r 'try ((.mcp // {}) | has("allye-mcp")) catch false' "$B")
MCP_STATE=$(jq -r 'try (if .mcp.allye == null then "missing" elif .mcp.allye == {"type":"remote","url":"https://mcp.allye.app/mcp","enabled":true} then "same" else "differs" end) catch "differs"' "$B")
TMP=$(mktemp "$(dirname "$CFG")/.opencode.json.XXXXXX")
jq --arg v "$VERSION" '
  def isa: if type == "string" then (. == "allye-opencode" or startswith("allye-opencode@"))
           elif type == "array" then (.[0] | type == "string" and (. == "allye-opencode" or startswith("allye-opencode@")))
           else false end;
  {"type":"remote","url":"https://mcp.allye.app/mcp","enabled":true} as $e
  | .mcp = (.mcp // {})
  | del(.mcp["allye-mcp"])
  | (if .mcp.allye == null then .mcp.allye = $e else . end)
  | .plugin = ((.plugin // []) as $p
      | if ($p | type) != "array" then error("plugin is not an array") else . end
      | ("allye-opencode@" + $v) as $pin
      | ($p | map(isa) | index(true)) as $i
      | (([$p[] | select(type == "array" and isa)] | first // null) as $a
          | if $a == null then $pin else ($a | .[0] = $pin) end) as $new
      | if $i == null then $p + [$pin]
        else [ $p | to_entries[] | select((.value | isa | not) or .key == $i) | if .key == $i then $new else .value end ] end)
' "$B" > "$TMP" || { rm -f "$TMP" "$B"; echo "Could not transform the config; left unchanged" >&2; exit 1; }
cmp -s "$CFG" "$B" || { rm -f "$TMP"; echo "opencode.json changed while this ran; left unchanged. Backup kept at $B. Close OpenCode and rerun" >&2; exit 1; }
chmod "$(stat -c %a "$CFG" 2>/dev/null || stat -f %Lp "$CFG")" "$TMP"
mv "$TMP" "$CFG" || { rm -f "$TMP"; echo "could not write the config; backup kept at $B" >&2; exit 1; }
echo "Backup: $B"
case "$MCP_STATE" in
  missing) echo "MCP entry allye: was missing, set to https://mcp.allye.app/mcp" ;;
  same) echo "MCP entry allye: already correct, unchanged" ;;
  differs) echo "MCP entry allye: differs from the Allye default and was left as is. Shape only, no values: $(jq -c 'try (.mcp.allye | {typeOk: (.type == "remote"), urlOk: (.url == "https://mcp.allye.app/mcp"), enabled: (.enabled | type), extraKeys: (keys - ["type","url","enabled"])}) catch "not an object"' "$CFG"). Ask the user to inspect the entry in the file themselves." ;;
esac
if [ "$LEGACY" = true ]; then opencode mcp logout allye-mcp || echo "Could not log out the legacy allye-mcp; tell the user" >&2; fi
```

Report the backup path (it is the rollback copy) and the MCP entry line to the user.

## Step 4: Verify

```bash
: "${VERSION:?run the version step first}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
X="${XDG_CONFIG_HOME:-}"
case "$X" in /*) ;; *) X="" ;; esac
while [ "${X%/}" != "$X" ]; do X="${X%/}"; done
[ -n "$X" ] || X="$HOME/.config"
DIR="$X/opencode"
CFG=$(readlink -f "$DIR/opencode.json") || { echo "could not resolve opencode.json" >&2; exit 1; }
N=$(jq -r '[(.plugin // [])[] | (if type == "array" then .[0] else . end) | select(type == "string" and (. == "allye-opencode" or startswith("allye-opencode@")))] | join(",")' "$CFG")
if [ "$N" = "allye-opencode@$VERSION" ]; then echo "OK: configured pin is $N"; else echo "Pin mismatch: configured '$N', expected allye-opencode@$VERSION" >&2; exit 1; fi
```

It must print `OK: configured pin is allye-opencode@<VERSION>`: exactly one Allye plugin entry, equal to the `$VERSION` from Step 1. Earlier versions registered six Allye agents (Allye, Plan, Orchestrator, Build, Review, Deliver); they disappear after the update, replaced by the Bridge skill.

## Step 5: Confirm

> Allye plugin updated to version **{version}** (pinned as `allye-opencode@{version}`; previous config saved at {backup path}). Restart OpenCode to load it.
