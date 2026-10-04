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
- **Bootstrap** — a short session-start note telling the agent that the MCP and Bridge are available and that it must ask you for a team when none is active.

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
./install.sh status                         # offline integrity check
```

Each install downloads the skill's approved release, verifies every file and the canonical hash, opens a distribution for this machine, verifies the API-signed execution token, publishes the files into the harness's user skills directory with a provenance sidecar, and records the result on the API. Local edits and directories it did not install are never overwritten. The API decides which runtimes may receive skills and who may distribute them; the installer reports its decision rather than working around it. Use `--team <id>` (or `ALLYE_TEAM_ID`) when you belong to several teams. Requires `bash`, `curl`, `jq` and Node.js 18+.

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

MIT
