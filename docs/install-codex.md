# Allye — Codex CLI installation guide

You are an AI agent helping the user install Allye for OpenAI Codex CLI: the Allye MCP server, the Bridge skill and the Allye bootstrap in `AGENTS.md`. Preserve unrelated MCP servers, credentials, skills and instructions.

## Step 0: Resolve the version

Allye installs one release: the version the user named, else the latest release of `allye-app/allye-plugin`. Run this before any change. Steps 0, 2 and 3 run in one shell session: they share `VERSION`, `ALLYE_TMP` and `TS`, and each later block stops at once when `VERSION` is unset or malformed. Set `RAW` only after checking the user's text as a whole (every line, not the first) against `^v?[0-9]+\.[0-9]+\.[0-9]+$`; otherwise leave it empty.

```bash
# never place user text in the script unless it already matched ^v?[0-9]+\.[0-9]+\.[0-9]+$; write only the matched digits and dots (never the original text, never a value containing a quote)
RAW=''   # set to the version only if you checked the user's text as a whole against ^v?[0-9]+\.[0-9]+\.[0-9]+$ (digits, dots, optional leading v); otherwise leave empty
[ -n "$RAW" ] || RAW=$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL https://api.github.com/repos/allye-app/allye-plugin/releases/latest | jq -r '.tag_name // empty')
RAW="${RAW#v}"
if ! [[ "$RAW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "No valid release version: $RAW" >&2; return 1 2>/dev/null || exit 1; fi
VERSION="$RAW"
echo "Installing Allye $VERSION"
```

Tell the user the version. If no valid version resolves, stop here: nothing has changed.

## Step 1: Configure the MCP server

Add one server named `allye` through Codex's native MCP command:

```bash
codex mcp add allye --url https://mcp.allye.app/mcp
codex mcp get allye
```

If `allye` already exists with a different URL, fixed headers or fixed OAuth client metadata, replace that entry alone:

```bash
codex mcp logout allye
codex mcp remove allye
codex mcp add allye --url https://mcp.allye.app/mcp
```

Do not edit the credential store or remove unrelated MCP servers.

## Step 2: Install the Bridge skill

Copy the Bridge skill (and any `bridge-*` crew skills) into Codex's user skills directory, then the git docs templates and the docs-check script into `~/.codex/templates/git-docs` and `~/.codex/install/docs-check.mjs` (two levels above `~/.codex/skills/bridge`, where the Bridge resolves them). Everything comes from the release archive of the version resolved in Step 0 (`v$VERSION` tag), a single download over HTTPS into a private temporary directory (`ALLYE_TMP`). Release tags are trusted as published; the archive is not checksum-verified.

Replace an existing `~/.codex/skills/bridge*` skill, `~/.codex/templates/git-docs` and `~/.codex/install/docs-check.mjs` only when they are Allye's copies; otherwise ask the user. The script below checks them (an Allye skill is a directory whose `SKILL.md` has the line `name: <directory name>`; Allye's templates directory holds the `.allye-templates` marker this step writes and its `CLAUDE.md` starts with `@AGENTS.md`; Allye's script carries the docs-check header line; a symbolic link is never Allye's copy) and skips a foreign copy with a message.

The script works in two passes. It first checks the archive (its entries are relative, contain no `..` and no links, and the expected files exist) and copies everything it is going to replace to `~/.allye/backups/codex/<name>.allye.backup.<UTC timestamp>` (private directory); if any check or backup fails it stops with `~/.codex` unchanged. Only then does it replace. Report each backup path to the user (printed to stderr).

```bash
: "${VERSION:?run Step 0 first}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
allye_clean() {
  local td="${TMPDIR:-/tmp}"; td="${td%/}"
  case "${ALLYE_TMP:-}" in *..*|"$td"/tmp.*/*) ;; "$td"/tmp.*) if [ -d "$ALLYE_TMP" ] && [ ! -L "$ALLYE_TMP" ] && [ -O "$ALLYE_TMP" ] && [ -f "$ALLYE_TMP/.allye-tmp" ]; then rm -rf "$ALLYE_TMP"; fi ;; esac
  unset ALLYE_TMP
}
allye_backup() {
  local b="$HOME/.allye/backups/codex/$2.allye.backup.$TS"
  if [ -e "$b" ]; then b="$b-$$"; fi
  ( umask 077; cp -a "$1" "$b" ) || return 1
  if [ -L "$b" ]; then :; elif [ -d "$b" ]; then chmod -R go-rwx "$b"; else chmod 600 "$b"; fi
  echo "Backup: $b" >&2
}
allye_step2() {
  local td="${TMPDIR:-/tmp}" SRC T C dir dst name replace_t=yes replace_c=yes
  local -a todo=()
  td="${td%/}"
  if [ -n "${ALLYE_TMP:-}" ]; then allye_clean; fi
  ALLYE_TMP=$(mktemp -d "$td/tmp.XXXXXX") || return 1
  case "$ALLYE_TMP" in "$td"/tmp.*) ;; *) echo "Unexpected temp dir; nothing changed." >&2; unset ALLYE_TMP; return 1 ;; esac
  : >"$ALLYE_TMP/.allye-tmp" || { echo "Cannot write in the temp dir; nothing changed." >&2; rm -rf "$ALLYE_TMP"; unset ALLYE_TMP; return 1; }
  SRC="$ALLYE_TMP/allye-plugin-$VERSION"
  if ! curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL https://github.com/allye-app/allye-plugin/archive/refs/tags/v"$VERSION".tar.gz -o "$ALLYE_TMP/release.tar.gz"; then
    echo "Download of v$VERSION failed; nothing changed." >&2; allye_clean; return 1
  fi
  if ! tar -tzf "$ALLYE_TMP/release.tar.gz" >"$ALLYE_TMP/names" || ! tar -tvzf "$ALLYE_TMP/release.tar.gz" >"$ALLYE_TMP/types"; then
    echo "The archive of v$VERSION cannot be listed; nothing changed." >&2; allye_clean; return 1
  fi
  if grep -Eq '^/|(^|/)\.\.(/|$)' "$ALLYE_TMP/names" || grep -Eq '^[lh]' "$ALLYE_TMP/types"; then
    echo "The archive holds absolute or parent paths, or link entries; nothing changed." >&2; allye_clean; return 1
  fi
  if ! tar -xzf "$ALLYE_TMP/release.tar.gz" --no-same-owner -C "$ALLYE_TMP"; then
    echo "Extraction of v$VERSION failed; nothing changed." >&2; allye_clean; return 1
  fi
  if [ -n "$(find "$ALLYE_TMP" -type l -print -quit)" ]; then
    echo "The archive contains symbolic links; nothing changed." >&2; allye_clean; return 1
  fi
  if [ ! -d "$SRC/templates/git-docs" ] || [ -L "$SRC/templates/git-docs" ] || [ ! -f "$SRC/skills/bridge/SKILL.md" ] || [ ! -f "$SRC/install/docs-check.mjs" ] || [ ! -f "$SRC/manifests/codex/AGENTS.md" ] || [ ! -f "$SRC/templates/git-docs/CLAUDE.md" ]; then
    echo "The archive lacks an expected file; nothing changed." >&2; allye_clean; return 1
  fi
  TS=$(date -u +%Y%m%dT%H%M%SZ)
  { ( umask 077; mkdir -p "$HOME/.allye/backups/codex" ) && chmod 700 "$HOME/.allye/backups/codex"; } || { echo "Backup directory failed; nothing changed." >&2; allye_clean; return 1; }
  for dir in "$SRC"/skills/bridge*; do
    name=$(basename "$dir")
    [[ "$name" =~ ^bridge[A-Za-z0-9_-]*$ ]] || { echo "Unexpected skill directory name in the archive; nothing changed." >&2; allye_clean; return 1; }
    { [ -d "$dir" ] && [ ! -L "$dir" ]; } || { echo "A skill entry of the archive is not a directory; nothing changed." >&2; allye_clean; return 1; }
  done
  for dir in "$SRC"/skills/bridge*; do
    name=$(basename "$dir")
    dst="$HOME/.codex/skills/$name"
    if [ -L "$dst" ] || { [ -e "$dst" ] && { [ ! -d "$dst" ] || ! grep -Fxq "name: $name" "$dst/SKILL.md" 2>/dev/null; }; }; then
      echo "Skipped $dst: not Allye's $name skill. Ask the user before replacing it."
      continue
    fi
    if [ -e "$dst" ]; then
      allye_backup "$dst" "$name" || { echo "Backup of $name failed; ~/.codex is unchanged (backups already made stay under ~/.allye/backups/codex)." >&2; allye_clean; return 1; }
    fi
    todo+=("$name")
  done
  T="$HOME/.codex/templates/git-docs"
  if [ -L "$T" ] || { [ -e "$T" ] && { [ ! -f "$T/.allye-templates" ] || [ "$(head -n 1 "$T/CLAUDE.md" 2>/dev/null)" != "@AGENTS.md" ]; }; }; then
    echo "Skipped $T: not Allye's git docs templates. Ask the user before replacing it."
    replace_t=no
  elif [ -e "$T" ]; then
    allye_backup "$T" git-docs || { echo "Backup of git-docs failed; ~/.codex is unchanged (backups already made stay under ~/.allye/backups/codex)." >&2; allye_clean; return 1; }
  fi
  C="$HOME/.codex/install/docs-check.mjs"
  if [ -L "$C" ] || { [ -e "$C" ] && ! grep -Fxq "// docs-check: deterministic checks for a repository's git docs (no dependencies)." "$C"; }; then
    echo "Skipped $C: not Allye's docs-check script. Ask the user before replacing it."
    replace_c=no
  elif [ -e "$C" ]; then
    allye_backup "$C" docs-check.mjs || { echo "Backup of docs-check.mjs failed; ~/.codex is unchanged (backups already made stay under ~/.allye/backups/codex)." >&2; allye_clean; return 1; }
  fi
  mkdir -p "$HOME/.codex/skills" "$HOME/.codex/templates" "$HOME/.codex/install" || { echo "Cannot create the Codex directories; nothing changed." >&2; allye_clean; return 1; }
  for name in ${todo[@]+"${todo[@]}"}; do
    dir="$SRC/skills/$name"
    rm -rf "$HOME/.codex/skills/$name"
    cp -R "$dir" "$HOME/.codex/skills/" || { echo "Copy of $name failed after the backups above; restore from them." >&2; allye_clean; return 1; }
  done
  if [ "$replace_t" = yes ]; then
    rm -rf "$T"
    { cp -R "$SRC/templates/git-docs" "$HOME/.codex/templates/" && touch "$T/.allye-templates"; } || { echo "Copy of git-docs failed after the backups above; restore from them." >&2; allye_clean; return 1; }
  fi
  if [ "$replace_c" = yes ]; then
    cp "$SRC/install/docs-check.mjs" "$C" || { echo "Copy of docs-check.mjs failed after the backups above; restore from it." >&2; allye_clean; return 1; }
  fi
}
allye_step2 || { unset -f allye_step2 allye_backup allye_clean; return 1 2>/dev/null || exit 1; }
unset -f allye_step2 allye_backup allye_clean
```

Without `~/.codex/templates/git-docs` and `~/.codex/install/docs-check.mjs`, Bridge reports docs-check as `unresolved` and never improvises a substitute.

## Step 3: Install the bootstrap in AGENTS.md

The bootstrap is `manifests/codex/AGENTS.md` from the same archive (still extracted at `ALLYE_TMP`). It is written to `~/.codex/AGENTS.md` between `<!-- allye:begin -->` and `<!-- allye:end -->`; a rerun replaces only the text between those markers, so the file holds exactly one Allye section and the user's own text stays unchanged. If `~/.codex/AGENTS.md` is a symbolic link, the file it points to is the one updated. The existing file is copied (mode 600) to `~/.allye/backups/codex/AGENTS.md.allye.backup.<UTC timestamp>` first and the copy is checked before anything changes (report the path); the new file is written next to it and moved into place only when complete. The script removes `ALLYE_TMP` when it ends or stops, except when it refuses an `ALLYE_TMP` it does not recognise (not the directory Step 2 made for this user, nested, or containing `..`): then it leaves it alone.

If the file has an older Allye section without markers, the script changes nothing and prints the matching lines. Show them to the user; only after the user confirms, remove that old section from `~/.codex/AGENTS.md` (the backup is already made), then run Steps 2 and 3 of this guide again.

```bash
: "${VERSION:?run Step 0 first}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
: "${TS:?run Step 2 first}" "${ALLYE_TMP:?run Step 2 first}"
allye_clean() {
  local td="${TMPDIR:-/tmp}"; td="${td%/}"
  case "${ALLYE_TMP:-}" in *..*|"$td"/tmp.*/*) ;; "$td"/tmp.*) if [ -d "$ALLYE_TMP" ] && [ ! -L "$ALLYE_TMP" ] && [ -O "$ALLYE_TMP" ] && [ -f "$ALLYE_TMP/.allye-tmp" ]; then rm -rf "$ALLYE_TMP"; fi ;; esac
  unset ALLYE_TMP
}
allye_abort() { rm -f "$NEW" "$OUT"; allye_clean; echo "$1" >&2; return 1; }
allye_step3() {
  local td="${TMPDIR:-/tmp}" SRC DEST DIR NEW="" OUT="" B BEG END
  td="${td%/}"
  case "$ALLYE_TMP" in *..*|"$td"/tmp.*/*) echo "ALLYE_TMP is nested or contains '..'; AGENTS.md is unchanged." >&2; return 1 ;; "$td"/tmp.*) ;; *) echo "ALLYE_TMP is not the temporary directory of Step 2; AGENTS.md is unchanged." >&2; return 1 ;; esac
  [ -d "$ALLYE_TMP" ] && [ ! -L "$ALLYE_TMP" ] && [ -O "$ALLYE_TMP" ] && [ -f "$ALLYE_TMP/.allye-tmp" ] || { echo "ALLYE_TMP is not the directory Step 2 made for you; AGENTS.md is unchanged." >&2; return 1; }
  SRC="$ALLYE_TMP/allye-plugin-$VERSION/manifests/codex/AGENTS.md"
  [ -f "$SRC" ] || { echo "ALLYE_TMP holds no v$VERSION archive; AGENTS.md is unchanged." >&2; return 1; }
  DEST="$HOME/.codex/AGENTS.md"
  if [ -L "$DEST" ]; then DEST=$(readlink -f "$DEST") || allye_abort "Cannot resolve the ~/.codex/AGENTS.md link; AGENTS.md is unchanged." || return 1; fi
  [ -n "$DEST" ] || allye_abort "Cannot resolve ~/.codex/AGENTS.md; AGENTS.md is unchanged." || return 1
  DIR=$(dirname "$DEST")
  mkdir -p "$DIR" || allye_abort "Cannot create $DIR; AGENTS.md is unchanged." || return 1
  NEW=$(mktemp "$DIR/AGENTS.md.XXXXXX") || allye_abort "Cannot write in $DIR; AGENTS.md is unchanged." || return 1
  { echo '<!-- allye:begin -->'; cat "$SRC"; echo '<!-- allye:end -->'; } >"$NEW"
  if [ ! -e "$DEST" ]; then
    mv "$NEW" "$DEST" || allye_abort "Cannot write $DEST; AGENTS.md is unchanged." || return 1
  else
    { ( umask 077; mkdir -p "$HOME/.allye/backups/codex" ) && chmod 700 "$HOME/.allye/backups/codex"; } || allye_abort "Backup directory failed; AGENTS.md is unchanged." || return 1
    B="$HOME/.allye/backups/codex/AGENTS.md.allye.backup.$TS"
    if [ -e "$B" ]; then B="$B-$$"; fi
    ( umask 077; cp -p "$DEST" "$B" ) || allye_abort "Backup of AGENTS.md failed; AGENTS.md is unchanged." || return 1
    chmod 600 "$B"
    echo "Backup: $B" >&2
    BEG=$(grep -Fxc '<!-- allye:begin -->' "$DEST" || true)
    END=$(grep -Fxc '<!-- allye:end -->' "$DEST" || true)
    OUT=$(mktemp "$DIR/AGENTS.md.XXXXXX") || allye_abort "Cannot write in $DIR; AGENTS.md is unchanged." || return 1
    cp -p "$DEST" "$OUT" || allye_abort "Cannot prepare the new AGENTS.md; AGENTS.md is unchanged." || return 1
    if [ "$BEG" = 1 ] && [ "$END" = 1 ] && [ "$(grep -Fnx '<!-- allye:begin -->' "$DEST" | cut -d: -f1)" -lt "$(grep -Fnx '<!-- allye:end -->' "$DEST" | cut -d: -f1)" ]; then
      NEWFILE="$NEW" awk '$0 == "<!-- allye:begin -->" { while ((getline l < ENVIRON["NEWFILE"]) > 0) print l; skip = 1; next } skip && $0 == "<!-- allye:end -->" { skip = 0; next } !skip { print }' "$DEST" >"$OUT" || allye_abort "Replacing the Allye section failed; AGENTS.md is unchanged." || return 1
    elif [ "$BEG" = 0 ] && [ "$END" = 0 ]; then
      if grep -qiE '^#+ .*allye' "$DEST"; then
        echo "Unmarked Allye section in $DEST; AGENTS.md is unchanged. Show these lines to the user and replace only after the user confirms:"
        grep -niE '^#+ .*allye' "$DEST"
        allye_abort "After the user confirms, remove that section and run Steps 2 and 3 of this guide again." || return 1
      fi
      { cat "$DEST"; printf '\n'; cat "$NEW"; } >"$OUT" || allye_abort "Appending the Allye section failed; AGENTS.md is unchanged." || return 1
    else
      allye_abort "Malformed Allye markers in $DEST; AGENTS.md is unchanged. Ask the user." || return 1
    fi
    if [ "$(grep -Fxc '<!-- allye:begin -->' "$OUT")" != 1 ] || [ "$(grep -Fxc '<!-- allye:end -->' "$OUT")" != 1 ]; then
      allye_abort "The new AGENTS.md does not hold exactly one Allye section; AGENTS.md is unchanged." || return 1
    fi
    mv "$OUT" "$DEST" || allye_abort "Cannot write $DEST; AGENTS.md is unchanged." || return 1
    rm -f "$NEW"
  fi
  allye_clean
  unset TS
}
allye_step3 || { unset -f allye_step3 allye_abort allye_clean; return 1 2>/dev/null || exit 1; }
unset -f allye_step3 allye_abort allye_clean
```

## Step 4: Authenticate

```bash
codex mcp login allye
```

The browser opens for consent. Codex owns client registration, token storage and refresh; no bearer header or client ID belongs in `config.toml`.

## Step 5: Confirm

Tell the user:

> Allye is configured for Codex: the `allye` MCP server, the Bridge skill and the Allye bootstrap in `~/.codex/AGENTS.md`.
>
> Start a new Codex session and run `/bridge survey` (or another mode) to begin. The agent identifies the repository's project with `project_resolve`; it asks for a team only when it needs to create a project and you have no default team.

## Organization skills and CODEX_HOME

`./install.sh install codex <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `$CODEX_HOME/skills` when `CODEX_HOME` is set, otherwise `~/.codex/skills`. `CODEX_HOME` must be an absolute path; only the empty string means unset, a trailing `/` is stripped (`/` itself stays `/`, so skills go to `/skills`), and a relative value stops the Codex install before any request. Detection also checks `$CODEX_HOME`.

Setting or changing `CODEX_HOME` re-keys the install target, because the target includes the skills directory. Skills installed earlier under `~/.codex/skills` are not migrated or touched; a copy found under the new directory is treated as missing or "other-target".

- Edited copies: `./install.sh install codex <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/codex/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/codex/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
