# Allye — OMP (oh-my-pi) installation guide

OMP is a fork of Pi and reads the same package manifest (`omp`, falling back to `pi`, in `package.json`), so it uses the same `allye-pi` package: the Allye bootstrap, the Bridge skill (`/bridge <mode>`) and the repository-to-project identification. See [install-pi.md](install-pi.md) for what the extension does.

> Verified against OMP 18.4: plugin install from npm, the `pi` manifest fallback, the `before_agent_start`/`resources_discover` extension events, user skills in `~/.omp/agent/skills`, and the `/mcp add` command. End-to-end runs of the extension inside OMP are not yet covered by tests.

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

Before installing, list the installed plugins with `omp plugin list` and note any `allye-pi` entry. If an older unpinned or different-version `allye-pi` is present, follow the update rules below (confirm with the user, then `--force` or uninstall first) so the pinned install replaces it instead of adding a second copy. After the install, run `omp plugin list` again and confirm exactly one `allye-pi` entry, at the pinned version.

Install the pinned version:

```bash
: "${VERSION:?}" "${TAG:?}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; return 1 2>/dev/null || exit 1; }
omp plugin install allye-pi@"$VERSION"
```

To update, resolve the newer version as above (same shell, same checks) and re-run the install with it. If OMP says the plugin is already installed, first confirm the installed plugin is `allye-pi` (`omp plugin list`) and that the user agrees, then confirm `omp plugin install --help` lists `--force` and re-run with `--force`; if the flag is not listed, run `omp plugin uninstall allye-pi` and install the pinned version again. If the install fails after the uninstall, tell the user to reinstall the previous version and report the failure. Do not use `omp plugin upgrade`. Remove with `omp plugin uninstall allye-pi`.

## Configure the MCP server

OMP has a native MCP client (no `pi-mcp-adapter`). Add the server once, at user scope:

```text
/mcp add allye --scope user --url https://mcp.allye.app/mcp --transport http
```

If the `allye` server is not found in OMP's own `mcp.json` files (user and project), the `allye-pi` extension shows one notice with this command when a session starts. It only reads those files, never writes them, and servers defined in other tools' configs are not checked.

OMP also loads servers from a project `.mcp.json`. Do not add tokens or OAuth client metadata: OMP discovers the OAuth endpoints and opens the browser on first use.

Because OMP's MCP client is not the in-process `pi-mcp-adapter` bridge (as in OMP today), the extension does not resolve the project. It injects only the git remote and any unverified `.allye/project.json` claim; the bootstrap tells the agent to call `projects.project_resolve` itself. The team follows the project, so no team selection is needed.

## Confirm

Tell the user:

> Allye is installed for OMP: the `allye-pi` extension (bootstrap and Bridge) and the `allye` MCP server. Start a new OMP session and run `/bridge survey` (or another mode).

## Organization skills

`./install.sh install omp <skill>` (see the [README](../README.md#your-organizations-skills)) installs into `~/.omp/agent/skills`. OMP presents itself to the API as runtime `pi`, and the skill is installed as a plain directory, with no package receipt.

- Edited copies: `./install.sh install omp <skill> --reinstall` replaces your edited copy and keeps it at `~/.allye/backups/omp/<skill>.allye.backup.<UTC ts>`. A copy of the same release on the same target is already installed (a no-op); older-release copies are updated, and copies recorded for another target (after a hostname or skills-path change) are reinstalled when unchanged, while an edited one needs `--reinstall`. Foreign or unmanaged folders are never touched.
- Leftovers: if the installer reports a `.allye-backup.<skill>.*` entry in the skills directory, an earlier run kept your edited folder there. Move it into `~/.allye/backups/omp/` or delete it, then rerun.
- Any member with view access to a skill can install it. If the installer is too old for the API, upgrade the installer; there is nothing to ask an admin to reset. Until the allye-api PROD release the installer works only against HML. See the [README](../README.md#your-organizations-skills).
