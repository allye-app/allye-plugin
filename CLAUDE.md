# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The **Allye plugin**: it connects AI coding harnesses to the Allye MCP server and ships the **Bridge** skill (`/bridge <mode>`), the orchestrator that designs specs and drives approved specs to reviewed branches. Supported harnesses: **Claude Code, Codex, OpenCode, Pi and OMP** (oh-my-pi, a Pi fork). Nothing else is supported; do not add Cursor, Gemini CLI or Hermes back.

The repo also holds `install.sh`, which is **not** the plugin installer: it installs an organization's own skills, stored in Allye's Skills section, into a harness through the API's governed distribution flow.

## Single sources

- `bootstrap/allye.md` — the session-start text for every harness (Allye MCP tools, active-team rule, Bridge modes). Keep it under 40 lines, English, and free of work items, boards and sprints. After editing it run `scripts/sync-bootstrap.sh` (it refreshes `manifests/codex/AGENTS.md`); `test/test-bootstrap.sh` fails while the copy is stale.
- `skills/bridge/` and the crew skills `skills/bridge-*/` — the Bridge skill (the Mothership) and one skill per crew agent; `skills/bridge/references/crew.md` lists them. Claude Code loads them as plugin skills, Pi/OMP through the `allye-pi` package, OpenCode through the `allye-opencode` package (copied at build time), Codex by copying them into `~/.codex/skills/`.

## How each harness gets the bootstrap

| Harness | Mechanism |
|---|---|
| Claude Code | `hooks/hooks.json` → `hooks/session-start.sh` prints `bootstrap/allye.md` as `additionalContext` (offline, no credentials) |
| Codex | `manifests/codex/AGENTS.md` (synced copy), merged into `~/.codex/AGENTS.md` by `docs/install-codex.md` |
| OpenCode | `packages/allye-opencode`: `experimental.chat.system.transform` adds the bootstrap; the `config` hook adds the bundled skills path |
| Pi, OMP | `packages/allye-pi/src/index.ts`: `before_agent_start` adds the bootstrap, `resources_discover` exposes `skills/`, optional MCP context preload and the multi-team gate (`/allye-team`) |

## Commands

- `npm test` — offline: bootstrap checks, hook test, installer tests (loopback fake API) and Pi extension tests. Individually: `npm run test:bootstrap`, `npm run test:installer`, `npm run test:pi`.
- `npm run typecheck` — Pi extension.
- `packages/allye-opencode`: `bun install`, `bun run typecheck`, `bun run build` (`scripts/prepare.ts` copies the bootstrap and `skills/bridge*` into the package first; the copies are gitignored).
- `./install.sh list|install <runtime> <skill>...|status` — organization skills installer (needs `ALLYE_PAT`; `status` is offline).

## Installer contract (install.sh, install/)

`install/lib.sh` orchestrates; `install/skill-tool.mjs` does hashing, artifact verification and RS256 token verification; `install/adapters.json` maps runtimes to API runtimes and user skills directories. The flow per skill: resolve skill → `GET .../releases/:rid/artifact?canonicalHash=` and verify every file and the canonical hash → `POST .../distributions/request` (or `update` from the installed release) with `runtimeVersion` = the contract version `1.0.0` and a per-machine `target` → `POST .../execution-context` → verify the token against `GET /api/skills/distribution-execution/jwks` → `POST .../preflight` → publish with a `.allye-artifact.json` sidecar → `POST .../complete` (or `.../fail` and restore). Keep it fail-closed: never overwrite a modified or unmanaged directory, never bypass an API refusal (compatibility matrix, authorization), never write MCP or harness configuration from the installer.

## OAuth connection

Every harness uses one server named `allye` at `https://mcp.allye.app/mcp`. Tenant selection is part of OAuth consent, not the URL. The harness performs discovery, client registration, token storage and refresh; plugin code must not read or print tokens, add fixed bearer headers or client IDs, or implement a parallel login flow.

## Releases

semantic-release on push to `main` (Conventional Commits) bumps `.claude-plugin/*.json`, `packages/allye-opencode/package.json`, `package.json` and `package-lock.json`, and writes `CHANGELOG.md` (generated — never edit it by hand). CI publishes `allye-opencode` and `allye-pi` to npm when their versions change. `./release.sh` is the manual fallback.

Breaking changes need a `BREAKING CHANGE:` footer in the commit body: the default analyzer ignores the `!` shorthand (`feat!:`).
