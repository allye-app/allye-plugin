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

#### Pinned preferences at session start (Claude Code only, optional)

Pair this install with your Allye account and every new, cleared or compacted session starts with the preferences you pinned in Allye, shown to the agent as quoted data, not instructions. Pairing is a second `SessionStart` hook, separate from the offline bootstrap hook.

```
/allye:hooks pair      # connects this install to your account
/allye:hooks unpair    # deletes the local credential, no network call
```

- **What it does.** `pair` creates a random secret on your machine, asks the Allye MCP (through your existing OAuth connection) for a one-time pairing code, and exchanges the code for a hook credential. It prints `Paired <device> as <email> in <organization>`: check that the account and organization are yours. A rule that allows every Allye MCP tool also approves the pairing call without a prompt, so that check is your only gate. If they are not yours, run `unpair` and revoke the device.
- **What leaves the machine.** Only the device name, the client kind (`claude-code`), a challenge (a hash of the secret), the pairing code and, on each session start, the credential as an authorization header. Never repository, file, conversation or environment content.
- **Where the credential lives.** `${CLAUDE_PLUGIN_DATA}/hook-credential.json` (`~/.claude/plugins/data/<plugin id>/`), mode 0600 in a 0700 directory. Claude Code removes it when the plugin is uninstalled from its last place. To keep the agent from reading it, add `Read(~/.claude/plugins/data/allye*/hook-credential.json)` (adjust to your plugin data directory) to `permissions.deny` in your user-level `~/.claude/settings.json`.
- **Supported API origins.** `pair` uses `https://api.allye.app`. `ALLYE_API_URL` is accepted only as `https://api.allye.app`, `https://api.zeta.allye.app` (HML) or `http://localhost:<port>` / `http://127.0.0.1:<port>` (local development).
- **Session start.** The hook makes one short request and prints the preferences, or one hint line when the credential is rejected, unsafe or the account is inactive. It is silent when you are not paired, offline or the API is unavailable. It needs `curl` and `jq`.
- **Before uninstalling.** Run `/allye:hooks unpair`, then revoke the device in Allye → Settings → Devices; unpair only deletes local files, so the credential keeps working on the server until revoked. Pair again before the expiry date shown at pairing.

### Codex, OpenCode

Paste into the agent. The install and update guides install one pinned release: the latest GitHub release unless you name a version. They check that it exists, never download from a branch, and keep a timestamped backup of any config they rewrite (`opencode.json`, `~/.codex/AGENTS.md`, `~/.codex/skills/bridge*`) under `~/.allye/backups/<harness>/`.

```
Install Allye following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-codex.md
Install Allye following: https://raw.githubusercontent.com/allye-app/allye-plugin/main/docs/install-opencode.md
```

### Pi, OMP

```bash
pi install npm:allye-pi@<version>          # Pi
omp plugin install allye-pi@<version>      # OMP
```

Use a pinned `<version>` (the guides resolve it for you). Then add the `allye` MCP server as described in [install-pi.md](docs/install-pi.md) or [install-omp.md](docs/install-omp.md).

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

Who can install, where skills go, how edited, deleted and moved copies are handled, and the API errors are in [docs/org-skills.md](docs/org-skills.md).

## Repository layout

```
bootstrap/allye.md          shared bootstrap text (single source)
skills/bridge/              the Bridge skill and its references
skills/bridge-*/            the crew skills (Armorer, Recon, Strategist, Architect, Dispatcher,
                            Pilot, Navigator, Copilot, Medic, Optimizer, Shield, Watcher)
agents/bridge-*.md          native crew subagents (Claude Code; OpenCode registers them from here):
                            load the matching crew skill under a per-role tool allowlist
hooks/                      Claude Code SessionStart hooks (bootstrap, pinned preferences) and
                            the pairing script behind /allye:hooks
.claude-plugin/, .mcp.json  Claude Code plugin and marketplace manifests
manifests/codex/AGENTS.md   Codex copy of the bootstrap (synced)
manifests/opencode/         sample OpenCode config
packages/allye-opencode/    OpenCode plugin (npm: allye-opencode)
packages/allye-pi/          Pi/OMP extension (npm: allye-pi, root package.json)
install.sh, install/        organization skills installer and its tests
scripts/sync-bootstrap.sh   copies the bootstrap to manifests/codex/AGENTS.md
docs/                       per-harness install and update guides, organization skills details
```

## Development

```bash
npm install
npm test            # bootstrap, hooks (npm run test:hooks), crew agents, skills, installer and docs gate, Pi and OpenCode tests (offline)
npm run typecheck   # Pi extension
cd packages/allye-opencode && bun install && bun run typecheck && bun run build
```

After editing `bootstrap/allye.md`, run `scripts/sync-bootstrap.sh`.

## Releases

Releases are automated by semantic-release on every push to `main` (Conventional Commits). It bumps the version in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `packages/allye-opencode/package.json`, `package.json` and `package-lock.json`, updates `CHANGELOG.md`, tags and creates the GitHub release. CI then publishes `allye-opencode` and `allye-pi` to npm when their version changed. `./release.sh [major|minor|patch]` is the manual fallback.

## License

MIT, see [LICENSE](LICENSE).
