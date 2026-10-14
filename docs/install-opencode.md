# Allye — OpenCode installation guide

You are an AI agent helping the user install Allye for OpenCode: the Allye MCP server and the `allye-opencode` plugin, which adds the Allye bootstrap and the Bridge skill. Preserve unrelated MCP servers, plugins and credentials.

## Step 1: Resolve the version

Run all the blocks of this guide in one shell session (or as one script): the version resolved here is used by every later block, and each later block starts with a guard that stops when `VERSION` is missing or malformed. Do this before any change. Set `RAW` only when you have checked the user's text as a whole against `^v?[0-9]+\.[0-9]+\.[0-9]+$` (digits, dots, optional leading `v`); otherwise leave it empty to use the latest release of `allye-app/allye-plugin`. Never paste user text into a command otherwise.

```bash
# Rule: never place user text in the script unless it already matched ^v?[0-9]+\.[0-9]+\.[0-9]+$; write only the matched digits and dots (never the original text, never a value containing a quote)
RAW=''   # set to the version only if you checked the user's text as a whole against ^v?[0-9]+\.[0-9]+\.[0-9]+$ (digits, dots, optional leading v); otherwise leave empty
[ -n "$RAW" ] || RAW=$(curl -fsSL https://api.github.com/repos/allye-app/allye-plugin/releases/latest | jq -r '.tag_name // empty')
RAW="${RAW#v}"
if ! [[ "$RAW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "No valid release version could be resolved" >&2; return 1 2>/dev/null || exit 1; fi
VERSION="$RAW"
echo "Installing Allye $VERSION"
```

Any failing block exits the shell session: stop and report to the user; do not continue with later blocks. Tell the user which version you are installing. If no valid version resolves, stop before any change and report it.

## Step 2: Check the package exists on npm

If this fails or prints nothing, stop before any change. This checks that the version exists and shows its `dist.integrity`; it is not a provenance or signature check. It runs from your home directory so a project `.npmrc` cannot redirect it. Show the user the printed `dist.integrity`:

```bash
: "${VERSION:?run the version step first}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
NPMV=$(cd "$HOME" && npm view allye-opencode@"$VERSION" version) && [ -n "$NPMV" ] || { echo "allye-opencode@$VERSION is not on npm" >&2; return 1 2>/dev/null || exit 1; }
echo "npm has allye-opencode@$NPMV"
(cd "$HOME" && npm view allye-opencode@"$VERSION" dist.integrity)
```

## Step 3: Configure the MCP server and the plugin

Merge the Allye entries into the user's OpenCode config and pin the plugin to `allye-opencode@$VERSION`. Unrelated MCP servers, plugins and settings are kept. Any other `allye-opencode` plugin entry (unpinned, another version, or array form `["allye-opencode", {...}]`) is replaced by the pin; an array-form entry keeps its options and only its first element is re-pinned. A rerun leaves exactly one `allye` MCP entry and one `allye-opencode@$VERSION` plugin entry.

Safety rules the block implements:

- If only `opencode.jsonc` exists (no `opencode.json`), it stops and reports; it never creates `opencode.json` next to it.
- The config is validated first: invalid JSON leaves the file byte-for-byte unchanged, nothing is backed up, and you report the parse error to the user.
- The config directory is `$XDG_CONFIG_HOME/opencode` when `XDG_CONFIG_HOME` is an absolute path other than `/`; an empty, relative or all-slash value counts as unset (trailing slashes are stripped first) and falls back to `~/.config/opencode`.
- A symlinked config is resolved (`readlink -f` needs GNU coreutils or macOS 12.3+), and the file mode is preserved. A dangling symlink at `opencode.json` stops the run.
- A `plugin` value that is not an array makes the transform fail, and the config is left unchanged.
- Close OpenCode before running this (a running OpenCode may rewrite the file). A shell killed mid-run can leave a `.opencode.json.XXXXXX` temp file (mode 600) in the config directory; delete it. An existing config is copied first (private, mode 600) to `~/.allye/backups/opencode/opencode.json.allye.backup.<UTC ts>`, and the new content is transformed from that copy into a temporary file in the same directory. If the copy fails, or the config changed since the copy, the config is left unchanged. The path is reported only after the config was replaced; on a failure after the backup, the message names the kept backup. A new config (none existed) is created private (mode 600). Backups accumulate in `~/.allye/backups/opencode/`; tell the user where they are so they can prune them.
- The pin replaces the existing `allye-opencode` entry in place (same position; appended only when absent). jq rewrites the file, so its formatting is normalised and large numbers or duplicate keys may be normalised too; the backup has the original bytes. Only the file mode is preserved, not ownership or group.
- This guide does not check for a downgrade: if the config pins a newer `allye-opencode@<version>`, it is replaced by the resolved version.
- The legacy `allye-mcp` MCP entry is dropped from the config; `opencode mcp logout allye-mcp` (which clears only that obsolete registration) runs only after the config was replaced, and a logout failure is reported to the user and is not fatal.
- An existing `allye` MCP entry is replaced with the Allye default (type, url, enabled); a differing previous entry is replaced and is recoverable from the backup.

```bash
: "${VERSION:?run the version step first}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
X="${XDG_CONFIG_HOME:-}"
case "$X" in /*) ;; *) X="" ;; esac
while [ "${X%/}" != "$X" ]; do X="${X%/}"; done
[ -n "$X" ] || X="$HOME/.config"
DIR="$X/opencode"
CFG="$DIR/opencode.json"
if [ ! -e "$CFG" ] && [ -e "$DIR/opencode.jsonc" ]; then
  echo "Found opencode.jsonc but no opencode.json: not creating a second config. Report this to the user and stop; a jsonc config must be migrated or edited by hand." >&2
  exit 1
fi
if [ -L "$CFG" ] && [ ! -e "$CFG" ]; then echo "opencode.json is a dangling symlink; left unchanged" >&2; exit 1; fi
mkdir -p "$DIR" || { echo "could not create $DIR" >&2; exit 1; }
if [ -e "$CFG" ]; then
  CFG=$(readlink -f "$CFG") || { echo "could not resolve opencode.json; left unchanged" >&2; exit 1; }
  [ -f "$CFG" ] || { echo "opencode.json is not a regular file; left unchanged" >&2; exit 1; }
fi
B=""
SEED=""
if [ -f "$CFG" ]; then
  jq -e . "$CFG" >/dev/null || { echo "opencode.json is not valid JSON; left unchanged" >&2; exit 1; }
  BD="$HOME/.allye/backups/opencode"
  ( umask 077; mkdir -p "$BD" )
  chmod 700 "$BD"
  B="$BD/opencode.json.allye.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  [ -e "$B" ] && B="$B-$$"
  ( umask 077; cp "$CFG" "$B" ) || { echo "backup failed; left unchanged" >&2; exit 1; }
  chmod 600 "$B"
  SRC="$B"
else
  SEED=$(mktemp); SRC="$SEED"
  echo '{"$schema": "https://opencode.ai/config.json"}' > "$SRC"
fi
LEGACY=$(jq -r 'try ((.mcp // {}) | has("allye-mcp")) catch false' "$SRC")
TMP=$(mktemp "$(dirname "$CFG")/.opencode.json.XXXXXX")
jq --arg v "$VERSION" '
  def isa: if type == "string" then (. == "allye-opencode" or startswith("allye-opencode@"))
           elif type == "array" then (.[0] | type == "string" and (. == "allye-opencode" or startswith("allye-opencode@")))
           else false end;
  .mcp = (.mcp // {})
  | del(.mcp["allye-mcp"])
  | .mcp.allye = { "type": "remote", "url": "https://mcp.allye.app/mcp", "enabled": true }
  | .plugin = ((.plugin // []) as $p
      | if ($p | type) != "array" then error("plugin is not an array") else . end
      | ("allye-opencode@" + $v) as $pin
      | ($p | map(isa) | index(true)) as $i
      | (([$p[] | select(type == "array" and isa)] | first // null) as $a
          | if $a == null then $pin else ($a | .[0] = $pin) end) as $new
      | if $i == null then $p + [$pin]
        else [ $p | to_entries[] | select((.value | isa | not) or .key == $i) | if .key == $i then $new else .value end ] end)
' "$SRC" > "$TMP" || { rm -f "$TMP" "$SEED"; [ -z "$B" ] || rm -f "$B"; echo "Could not transform the config; left unchanged" >&2; exit 1; }
rm -f "$SEED"
if [ -n "$B" ]; then
  cmp -s "$CFG" "$B" || { rm -f "$TMP"; echo "opencode.json changed while this ran; left unchanged. Backup kept at $B. Close OpenCode and rerun" >&2; exit 1; }
  chmod "$(stat -c %a "$CFG" 2>/dev/null || stat -f %Lp "$CFG")" "$TMP"
fi
mv "$TMP" "$CFG" || { rm -f "$TMP"; echo "could not write the config${B:+; backup kept at $B}" >&2; exit 1; }
[ -z "$B" ] || echo "Backup: $B"
if [ "$LEGACY" = true ]; then opencode mcp logout allye-mcp || echo "Could not log out the legacy allye-mcp; tell the user" >&2; fi
```

Report the backup path to the user when one was created.

The `allye` entry intentionally has no headers or fixed OAuth client metadata.

## Step 4: Authenticate

Restart OpenCode, then:

```bash
opencode mcp auth allye
opencode mcp list
```

OpenCode owns discovery, client registration, token storage and refresh.

## Step 5: Confirm

Tell the user:

> Allye is configured for OpenCode:
> - the `allye` MCP server at `https://mcp.allye.app/mcp`, using native OAuth;
> - the `allye-opencode@{version}` plugin, pinned to that release, which adds the Allye bootstrap and the Bridge skill (`/bridge <mode>`).
>
> Restart OpenCode to load the plugin. The agent identifies the repository's project with `project_resolve`; it asks for a team only when it needs to create a project and you have no default team.

## Organization skills

`./install.sh install opencode <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `${XDG_CONFIG_HOME:-~/.config}/opencode/allye-skills`. An empty or relative `XDG_CONFIG_HOME` counts as unset. OpenCode does not discover this directory natively: the `allye-opencode` plugin adds it to `skills.paths` when it is a real directory (not a symlink) owned by you and not group- or world-writable. The installer refuses to install into a symlinked or group/world-writable one (fix with `chmod go-w <dir>`); it does not check ownership, so the plugin additionally ignores a directory that is not owned by you. When the install creates the directory, the installer prints a notice: restart OpenCode to load it.

- Edited copies: `./install.sh install opencode <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/opencode/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/opencode/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
