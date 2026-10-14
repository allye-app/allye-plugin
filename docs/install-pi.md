# Allye — Pi installation guide

Allye for Pi is the native package `allye-pi`. It:

- exposes the Bridge skill (`/bridge <mode>`) from the package's `skills/` directory;
- adds the Allye bootstrap (`bootstrap/allye.md`) to the system prompt;
- identifies the repository's project (it loads no startup or per-prompt memory context): when an in-process MCP bridge is available it resolves the git remote with `projects.project_resolve` and verifies any `.allye/project.json` claim against it, injecting "this repo = project X / app Y (team Z)", the ambiguous candidates, or the disagreement to ask the user about.

It never edits Pi's MCP configuration or reads credentials.

## Install the package

Resolve the version first, before any change. Run the resolve block, the npm check and the install in one shell session, so `VERSION` and `TAG` carry over. Only stable `vX.Y.Z` releases are accepted (no pre-release or build suffix), and `curl` and `jq` are required. The version is the one the user named, otherwise the latest GitHub release of `allye-app/allye-plugin`.

```bash
# Never put user text in this script unless it already matched ^v?[0-9]+\.[0-9]+\.[0-9]+$: write only the matched digits and dots (never the original text, never a value containing a quote).
RAW=''   # set to the version only if you checked the user's text as a whole against ^v?[0-9]+\.[0-9]+\.[0-9]+$ (digits, dots, optional leading v); otherwise leave empty
[ -n "$RAW" ] || RAW=$(curl -fsSL https://api.github.com/repos/allye-app/allye-plugin/releases/latest | jq -r '.tag_name // empty')
RAW="${RAW#v}"
if ! [[ "$RAW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "No valid release version: $RAW" >&2; return 1 2>/dev/null || exit 1; fi
VERSION="$RAW"; TAG="v$VERSION"
echo "Installing Allye $VERSION"
```

Tell the user the version. If no valid version resolves, stop and change nothing.

Check that this version exists on npm. The release tag can appear before the npm publish: if the command fails, report it and stop; never fall back to an unpinned install. Show the user the printed version and `dist.integrity`. The Git release tag is trusted as published.

```bash
: "${VERSION:?}" "${TAG:?}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
(cd "$HOME" && npm view allye-pi@"$VERSION" version dist.integrity)
```

The npm check above must already have passed before anything is removed. Then list the installed packages with `pi list`. If it shows another `allye-pi` source (unpinned npm, an older pinned npm, or the git source `git:github.com/allye-app/allye-plugin@vX.Y.Z`), confirm with the user and remove that exact source string as shown by `pi list` with `pi remove <source>`, so the pinned install replaces it instead of adding a second source. Do the removal just before the install. If the install then fails, tell the user to reinstall the previous version (the source string you removed) and report the failure. After the install, run `pi list` again and confirm exactly one `allye-pi` source (npm or git), at the pinned version.

Install the pinned version:

```bash
: "${VERSION:?}" "${TAG:?}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
pi install npm:allye-pi@"$VERSION"
```

From Git, at the release tag:

```bash
: "${VERSION:?}" "${TAG:?}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
pi install git:github.com/allye-app/allye-plugin@"$TAG"
```

From a local checkout, for development: `pi install /absolute/path/to/allye-plugin`.

To update, resolve the newer version as above (same shell, same checks) and re-run `pi install npm:allye-pi@"$VERSION"` with it (no `pi update`, which would not move a pinned version), then repeat the `pi list` check: exactly one `allye-pi` source. Remove with `pi remove <source>` using the source string shown by `pi list` (`npm:allye-pi@<version>` or the git source `git:github.com/allye-app/allye-plugin@<tag>`). Removing the package does not remove MCP configuration or OAuth credentials.

## Configure the MCP server

Recent Pi releases have a native MCP client (verified on Pi 0.99.1). Add the server and sign in:

```text
pi mcp add allye --url https://mcp.allye.app/mcp
pi mcp login allye
pi mcp list
```

Do not pass headers, bearer tokens or OAuth client ids: Pi discovers the OAuth endpoints and stores the credential.

On older Pi versions without `pi mcp`, install `pi-mcp-adapter` (`pi install npm:pi-mcp-adapter`), define one server named `allye` (`{"type": "http", "url": "https://mcp.allye.app/mcp"}` under `mcpServers`) in the effective source shown by `/mcp` — for example `~/.pi/agent/mcp.json` or `~/.config/mcp/mcp.json` — then run `/mcp-auth allye` and `/mcp reconnect allye`.

The extension resolves the repository's project only when `pi-mcp-adapter` exposes its in-process bridge. Otherwise it injects only the git remote and any unverified link claim, and the bootstrap tells the agent to call `projects.project_resolve` itself.

## Teams

The team follows the project: the extension never blocks work on team selection. A default team is needed only to create projects; `/allye-team <name|prefix|id>` sets it through the `team` tool (`team_set_default`). Set `ALLYE_PI_NATIVE_BOOTSTRAP=0` to skip the repository block (the bootstrap text and the Bridge skill stay available), or `ALLYE_PI_MCP=0` to disable MCP calls from the extension.

## Local development

From the repository root:

```text
npm install
npm run typecheck
npm run test:pi
pi -e ./packages/allye-pi/src/index.ts -p "Which Allye tools and Bridge modes are available?"
```

## Organization skills

`./install.sh install pi <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `$PI_CODING_AGENT_DIR/skills` when `PI_CODING_AGENT_DIR` is set, otherwise `~/.pi/agent/skills`. The value must be an absolute path; only the empty string means unset, a trailing `/` is stripped, and a relative value stops the Pi install before any request. Changing it changes the install target; copies left in the old directory are not migrated. The API sees runtime `pi` and the skill is installed as a plain directory, with no package receipt.

- Edited copies: `./install.sh install pi <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/pi/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/pi/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
