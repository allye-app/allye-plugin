<p align="center">
  <strong>Allye Plugin</strong><br>
  <em>The Allye MCP and the Bridge skill for AI coding harnesses</em>
</p>

<p align="center">
  <a href="https://github.com/allye-app/allye-plugin/releases"><img src="https://img.shields.io/github/v/release/allye-app/allye-plugin" alt="Release"></a>
  <a href="https://github.com/allye-app/allye-plugin/blob/main/LICENSE"><img src="https://img.shields.io/github/license/allye-app/allye-plugin" alt="License"></a>
  <a href="https://www.npmjs.com/package/allye-opencode"><img src="https://img.shields.io/npm/v/allye-opencode?label=allye-opencode" alt="allye-opencode"></a>
  <a href="https://www.npmjs.com/package/allye-pi"><img src="https://img.shields.io/npm/v/allye-pi?label=allye-pi" alt="allye-pi"></a>
</p>

---

Allye keeps your projects, epics, specs and tasks on the server. This plugin connects your coding agent to it:

- **Allye MCP** (`https://mcp.allye.app/mcp`, OAuth 2.1) — `projects`, `epics`, `specs`, `tasks` and `team` tools, plus context, memory and your organization's skills.
- **Bridge** (`/bridge <mode>`) — a skill that designs specs with you and drives an approved spec to a reviewed branch and, with your approval, one PR, through a crew of specialized agents with security and review gates.
- **Bootstrap** — a short session-start note telling the agent that the MCP and Bridge are available, that the team follows the project (identified with `project_resolve`), and that a default team is only needed to create projects and for memory, todo and doc calls without a `team_id`.

**[Create a free Allye account →](https://allye.app/)**

## Bridge modes

| Mode | What it does |
|---|---|
| `launch <spec>` | Drive an approved spec to a reviewed branch and, with approval, one PR |
| `mission "<goal>"` | Repeat launch waves until verifiable exit conditions pass |
| `blueprint` | Interview, then create the epic, spec and tasks after one confirmation |
| `blueprint --auto` | Same without the interview; every choice is recorded as a decision |
| `dispatch` | Quick spec in three questions or fewer, then create the spec and tasks |
| `repair` | Reproduce, diagnose and fix a bug through the gated flow |
| `optimize` | Propose simplifications; apply only the approved ones |
| `shield` | Security review; fix only confirmed findings you approve |
| `inspect` | Read-only review of a diff |
| `survey` | Map the codebase and create or update the code guide |

## Supported harnesses

| Harness | MCP | Bridge | Bootstrap | Guide |
|---|---|---|---|---|
| Claude Code | plugin `.mcp.json` | plugin skill (`/allye:bridge`) | `SessionStart` hook | below |
| Codex | `codex mcp add` | `~/.codex/skills/bridge` | `~/.codex/AGENTS.md` | [install](docs/install-codex.md) · [update](docs/update-codex.md) |
| OpenCode | `opencode.json` | `allye-opencode` plugin | `allye-opencode` plugin | [install](docs/install-opencode.md) · [update](docs/update-opencode.md) |
| Pi | `pi mcp add` | `allye-pi` package | `allye-pi` extension | [install](docs/install-pi.md) |
| OMP (oh-my-pi) | `/mcp add` | `allye-pi` package | `allye-pi` extension | [install](docs/install-omp.md) |

Every harness uses one server named `allye`. Tenant selection happens during OAuth consent; the harness owns client registration, token storage and refresh.

### Claude Code

```
/plugin marketplace add allye-app/allye-plugin
/plugin install allye
/reload-plugins
```

Then open `/plugin`, find the Allye MCP server, click **Connect** and sign in. Update with `/plugin update allye` and `/reload-plugins`.

### Codex, OpenCode

Paste into the agent:

```
Install Allye following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-codex.md
Install Allye following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-opencode.md
```

### Pi, OMP

```bash
pi install npm:allye-pi          # Pi
omp plugin install allye-pi      # OMP
```

Then add the `allye` MCP server as described in [install-pi.md](docs/install-pi.md) or [install-omp.md](docs/install-omp.md).

## Your organization's skills

`install.sh` installs the skills your organization keeps in Allye's **Skills** section (per tenant and team) into a harness on your machine. It is not needed to install this plugin.

```bash
export ALLYE_PAT=pat_...                    # Allye → Settings → API
./install.sh list --scope team              # approved skills you can see
./install.sh install claude team-standards  # claude | codex | opencode | pi | omp
./install.sh install claude team-standards --reinstall   # replace an edited copy (kept as a backup)
./install.sh status                         # offline integrity check
```

Each install downloads the skill's approved release, verifies every file and the canonical hash, opens a distribution for this machine, verifies the API-signed execution token, publishes the files into the harness's user skills directory with a provenance sidecar, and records the result on the API. The API decides which runtimes may receive skills; the installer reports its decision rather than working around it. Requires `bash`, `curl`, `jq` and Node.js 18+. The installer speaks compatibility contract `1.1.0`.

Until the allye-api PROD release that supports contract `1.1.0`, the installer works only against HML (`ALLYE_API_URL` pointing at the HML API). Against PROD it fails with `409 RUNTIME_INCOMPATIBLE` or an execution-context error about a missing signing key, and changes nothing.

### Who can install

Any member with view access to a skill can install it: any tenant member for an organization skill, members of the skill's team for a team skill, the author for a personal skill. Each person's installs are recorded separately. The installer needs no team for the install itself; use `--team <id>` (or `ALLYE_TEAM_ID`) only when a skill slug matches skills in several teams, so the slug can be resolved (or pass the skill id instead). If view access is lost while an install is in progress, the API answers `409`, the installer rolls the swap back and tells you to get access and rerun.

### Where skills go

| Runtime | Skills directory |
|---|---|
| `claude` | `~/.claude/skills` |
| `codex` | `$CODEX_HOME/skills` when `CODEX_HOME` is set, otherwise `~/.codex/skills` |
| `opencode` | `${XDG_CONFIG_HOME:-~/.config}/opencode/allye-skills` |
| `pi` | `$PI_CODING_AGENT_DIR/skills` when set, otherwise `~/.pi/agent/skills` |
| `omp` | `~/.omp/agent/skills` |

`CODEX_HOME` and `PI_CODING_AGENT_DIR` must be absolute paths; only the empty string means unset, a trailing `/` is stripped (`/` itself stays `/`), and a relative value stops that runtime's install before any request (other runtimes are unaffected). An empty or relative `XDG_CONFIG_HOME` is treated as unset. OpenCode does not discover this directory by itself: the `allye-opencode` plugin adds it to `skills.paths` when it is a real directory (not a symlink) owned by you and not group- or world-writable, so restart OpenCode after the first install creates it. The installer refuses to install into an `allye-skills` directory that is a symlink or group/world-writable (fix with `chmod go-w <dir>`); it does not check ownership, so the plugin additionally ignores a directory that is not owned by you. OMP presents itself to the API as runtime `pi`; Pi and OMP skills are installed as plain directories, with no package receipt.

Changing `CODEX_HOME` or `PI_CODING_AGENT_DIR` changes the install target, and the installer does not migrate skills left in the old directory (for example `~/.codex/skills`). Those copies stay where they are; a copy found under the new directory is handled as in the next section.

### Edited, deleted and moved copies

| State of `<skills dir>/<name>` | What the installer does |
|---|---|
| Missing (first install or deleted) | Installs it again; the API records a reinstall when it already had an install for this machine |
| Unchanged copy of the same release | Reports "already installed"; nothing is sent |
| Unchanged copy of an older release | Updates it |
| Edited by you | Refuses and changes nothing; rerun with `--reinstall` |
| Not installed by the installer, or installed from another skill | Never touched, with or without `--reinstall` |
| Contains a symlink or special file | Refuses and names the entry; with or without `--reinstall` |

`--reinstall` replaces an edited copy with the approved release and keeps your edited folder at `~/.allye/backups/<adapter-id>/<name>.allye.backup.<UTC ts>` (`.<pid>` is appended if that name exists), outside every skills directory so no harness loads it. Backup directories are created with mode 0700, and the installer refuses to keep backups in a `~/.allye`, `backups` or `backups/<id>` that is a symlink, owned by someone else or group/world-writable (it changes nothing; fix the directory and rerun). The installer prints the path; backups are never overwritten or deleted, and `./install.sh status` does not list them. If anything fails before the install is recorded, your edited folder is put back.

A copy records the machine and skills path it was installed for (as a digest; the hostname and path never leave the machine). After a hostname change, a different home or a changed `CODEX_HOME`, `PI_CODING_AGENT_DIR` or `XDG_CONFIG_HOME`, existing copies are "other-target": an unchanged one is reinstalled automatically here with no backup, while an edited one needs `--reinstall`.

If an earlier run could not finish moving your edited folder (a failed restore, a failed backup move, or a killed run), it leaves `<skills dir>/.allye-backup.<name>.<UTC ts>.<pid>`. The installer then refuses to install `<name>`, prints each such path and sends nothing. Move the folder into `~/.allye/backups/<adapter-id>/` to keep it, or delete it, then rerun.

### Errors

- `409 DISTRIBUTION_NOT_AUTHORIZED`: you need view access to the skill (team membership or authorship); get access and rerun.
- `410 MARKETPLACE_RETIRED`: the skill is a retired, read-only marketplace skill; nothing was installed. Use an organization or team skill.
- `422 TEAM_SELECTION_REQUIRED`: the slug matches skills in several teams; rerun with `--team <team>` or use the skill id.
- `409 RUNTIME_INCOMPATIBLE`: the API has no `1.1.0` profile, which is the case on PROD before the allye-api release. Use HML or wait for that release; there is nothing to reset and no admin to ask.
- `400` mentioning a request field such as `idempotencyKey` or `target`: the API and the installer disagree on the request shape. Upgrade the installer; there is nothing to reset and no admin to ask.

## Repository layout

```
bootstrap/allye.md          shared bootstrap text (single source)
skills/bridge/              the Bridge skill and its references
skills/bridge-*/            the crew skills (Armorer, Recon, Strategist, Architect, Dispatcher,
                            Pilot, Copilot, Medic, Optimizer, Shield, Watcher)
agents/bridge-*.md          native crew subagents (Claude Code; OpenCode registers them from here):
                            load the matching crew skill under a per-role tool allowlist
hooks/                      Claude Code SessionStart hook
.claude-plugin/, .mcp.json  Claude Code plugin and marketplace manifests
manifests/codex/AGENTS.md   Codex copy of the bootstrap (synced)
manifests/opencode/         sample OpenCode config
packages/allye-opencode/    OpenCode plugin (npm: allye-opencode)
packages/allye-pi/          Pi/OMP extension (npm: allye-pi, root package.json)
install.sh, install/        organization skills installer and its tests
scripts/sync-bootstrap.sh   copies the bootstrap to manifests/codex/AGENTS.md
docs/                       per-harness install and update guides
```

## Development

```bash
npm install
npm test            # bootstrap, hook, crew agents, installer and Pi extension tests (offline)
npm run typecheck   # Pi extension
cd packages/allye-opencode && bun install && bun run typecheck && bun run build
```

After editing `bootstrap/allye.md`, run `scripts/sync-bootstrap.sh`.

## Releases

Releases are automated by semantic-release on every push to `main` (Conventional Commits). It bumps the version in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `packages/allye-opencode/package.json`, `package.json` and `package-lock.json`, updates `CHANGELOG.md`, tags and creates the GitHub release. CI then publishes `allye-opencode` and `allye-pi` to npm when their version changed. `./release.sh [major|minor|patch]` is the manual fallback.

## License

MIT, see [LICENSE](LICENSE).
