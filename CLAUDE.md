# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The **Allye plugin**: it connects AI coding harnesses to the Allye MCP server and ships the **Bridge** skill (`/bridge <mode>`), the orchestrator that designs specs and drives approved specs to reviewed branches. Supported harnesses: **Claude Code, Codex, OpenCode, Pi and OMP** (oh-my-pi, a Pi fork). Nothing else is supported; do not add Cursor, Gemini CLI or Hermes back.

The repo also holds `install.sh`, which is **not** the plugin installer: it installs an organization's own skills, stored in Allye's Skills section, into a harness through the API's governed distribution flow.

## Single sources

- `bootstrap/allye.md` — the session-start text for every harness (Allye MCP tools, team-follows-the-project rule and `project_resolve`, Bridge modes). Keep it under 40 lines, English, and free of work items, boards and sprints. After editing it run `scripts/sync-bootstrap.sh` (it refreshes `manifests/codex/AGENTS.md`); `test/test-bootstrap.sh` fails while the copy is stale.
- `skills/bridge/` and the crew skills `skills/bridge-*/` — the Bridge skill (the Mothership) and one skill per crew agent; `skills/bridge/references/crew.md` lists them. Claude Code loads them as plugin skills, Pi/OMP through the `allye-pi` package, OpenCode through the `allye-opencode` package (copied at build time), Codex by copying them into `~/.codex/skills/`.
- `agents/bridge-<role>.md` — one native crew subagent per crew skill (Claude Code plugin agents, dispatched as `allye:bridge-<role>`). Each only loads its skill and sets the role's tool allowlist; behavior lives in the skill, Allye rights in `skills/bridge/references/delegation.md`. The description is copied verbatim from the skill. `test/test-agents.mjs` enforces the pairing, the description, and that read-only roles get no Edit/Write. OpenCode registers equivalent subagents from these files; Codex, Pi and OMP use a generic worker plus the skill.

## How each harness gets the bootstrap

| Harness | Mechanism |
|---|---|
| Claude Code | `hooks/hooks.json` → `hooks/session-start.sh` prints `bootstrap/allye.md` as `additionalContext` (offline, no credentials) |
| Codex | `manifests/codex/AGENTS.md` (synced copy), merged into `~/.codex/AGENTS.md` by `docs/install-codex.md` |
| OpenCode | `packages/allye-opencode`: `experimental.chat.system.transform` adds the bootstrap; the `config` hook adds the bundled skills path, the org `allye-skills` dir (real directory, not a symlink, owned by the user, not group/world-writable) via `skills-paths.ts`, and registers the crew subagents generated from `agents/*.md` |
| Pi, OMP | `packages/allye-pi/src/index.ts`: `before_agent_start` adds the bootstrap, `resources_discover` exposes `skills/`, optional project resolution through the MCP bridge (no startup or per-prompt memory context), and `/allye-team` to set the default team |

## Commands

- `npm test` — offline: bootstrap checks, hook test, crew agent checks (`npm run test:agents`), skills checks (`npm run test:skills`: CI workflow and LICENSE checks), installer tests (loopback fake API), Pi extension tests and OpenCode tests (`npm run test:opencode`). Individually: `npm run test:bootstrap`, `npm run test:agents`, `npm run test:skills`, `npm run test:installer`, `npm run test:pi`, `npm run test:opencode`.
- `npm run typecheck` — Pi extension.
- `packages/allye-opencode`: `bun install`, `bun run typecheck`, `bun run build` (`scripts/prepare.ts` copies the bootstrap, `skills/bridge*` and the crew agents from `agents/*.md` into the package first; the copies are gitignored).
- `./install.sh list|install <runtime> <skill>... [--reinstall]|status` — organization skills installer for claude, codex, opencode, pi and omp (needs `ALLYE_PAT`; `status` is offline).

## Installer contract (install.sh, install/)

`install/lib.sh` orchestrates; `install/skill-tool.mjs` does hashing, artifact verification and RS256 token verification; `install/adapters.json` maps runtimes to API runtimes and user skills directories. The flow per skill: resolve skill → `GET .../releases/:rid/artifact?canonicalHash=` and verify every file and the canonical hash → `POST .../distributions/request` (or `update` from the installed release) with `runtimeVersion` = the contract version `1.1.0` and a per-machine `target` → `POST .../execution-context` → verify the token against `GET /api/skills/distribution-execution/jwks` → `POST .../preflight` → publish with a `.allye-artifact.json` sidecar → `POST .../complete` (or `.../fail` and restore). Targets: Codex `$CODEX_HOME/skills` (else `~/.codex/skills`), OpenCode `${XDG_CONFIG_HOME:-~/.config}/opencode/allye-skills` (registered by the `allye-opencode` plugin), Pi `$PI_CODING_AGENT_DIR/skills`, OMP `~/.omp/agent/skills`; `CODEX_HOME` and `PI_CODING_AGENT_DIR` are normalised (empty = unset, trailing `/` stripped, relative = error for that adapter) and Pi/OMP install as API runtime `pi`, `installKind` `directory`. A missing folder, or an intact copy recorded for another target (hostname or path change), is reinstalled without a flag (`reinstall {missing}`, no backup); an edited copy needs `--reinstall`, which keeps it at `~/.allye/backups/<adapter-id>/<name>.allye.backup.<UTC ts>`. A `.allye-backup.<name>.*` entry in a skills dir (leftover of a failed run) makes the installer refuse that skill until the user moves or deletes it. Keep it fail-closed: never overwrite a modified (without `--reinstall`), foreign or unmanaged directory, never bypass an API refusal (compatibility matrix, authorization), never write MCP or harness configuration from the installer.

## OAuth connection

Every harness uses one server named `allye` at `https://mcp.allye.app/mcp`. Tenant selection is part of OAuth consent, not the URL. The harness performs discovery, client registration, token storage and refresh; plugin code must not read or print tokens, add fixed bearer headers or client IDs, or implement a parallel login flow.

## Releases

semantic-release on push to `main` (Conventional Commits) bumps `.claude-plugin/*.json`, `packages/allye-opencode/package.json`, `package.json` and `package-lock.json`, and writes `CHANGELOG.md` (generated — never edit it by hand). CI publishes `allye-opencode` and `allye-pi` to npm when their versions change, via npm trusted publishing (OIDC, no token): each package trusts `allye-app/allye-plugin` `auto-release.yml`. `./release.sh` is the manual fallback.

Breaking changes need a `BREAKING CHANGE:` footer in the commit body: the default analyzer ignores the `!` shorthand (`feat!:`).
