# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Source of the **Allye** plugin — a methodology/workflow layer on top of the Allye MCP server, distributed to seven different AI coding agents (Claude Code, OpenCode, Cursor, Codex, Gemini CLI, Hermes Agent, Pi). There is no build step for the plugin itself; it's mostly Markdown (agents, skills) plus shell scripts, distributed via `install.sh` or the Claude Code plugin marketplace. The compiled adapters are `packages/allye-opencode` and `packages/allye-pi`.

## Commands

- No repo-wide build/lint/test — this is markdown + shell, not compiled (except the opencode package below).
- Bump version, sync files, commit, tag, and push a release: `./release.sh [major|minor|patch]` (default `patch`). In practice releases are automated by semantic-release on push to `main` (see `.releaserc.json` / `.github/workflows/auto-release.yml`), driven by Conventional Commits — `release.sh` is the manual fallback.
- `./install.sh status` is the local inspection command. Shared runtime `install` operations are fail-closed without an API-backed ownership artifact, and `uninstall` is intentionally blocked; do not report either blocked path as a successful mutation.

### `packages/allye-opencode` (bun, TypeScript)
- `bun install`
- `bun run generate` — regenerates `src/prompts/` from the canonical skill/agent markdown via `scripts/generate-prompts.ts`
- `bun run build` — runs `generate` then bundles with `bun build src/index.ts --outdir dist --target bun`
- `bun run typecheck` — `tsc --noEmit`
- Published to npm as `allye-opencode` automatically by CI when `package.json`'s version changes on `main` (see `publish-opencode` job in `.github/workflows/auto-release.yml`).

### `packages/allye-pi` (native Pi package adapter)
- `npm install` from the repository root installs the adapter's development dependencies. Production users install the adapter through Pi's native `pi install npm:allye-pi`; the repository installer does not write Pi's MCP configuration.
- `npm run typecheck` validates `packages/allye-pi/src/index.ts`.
- `npm run test:pi` covers startup bootstrap loading, adaptive capability filtering, wait delivery, and the multi-team bootstrap gate.
- The root `package.json` is the Pi package manifest: it points Pi at the adapter extension and the canonical root `skills/` directory.
- The adapter uses the configured `pi-mcp-adapter` for Allye context, exposes an adaptive toolkit, and enables Herdr only when the optional `HERDR_ENV=1` capability is present.

## Architecture

### Two parallel distribution mechanisms

1. **Claude Code plugin** (native): `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` describe the plugin; Claude Code loads `agents/*.md` as subagents, `skills/*/SKILL.md` as on-demand skills, and `hooks/hooks.json` wires `hooks/session-start.sh` to `SessionStart`. `.mcp.json` declares the `allye` server at the canonical `https://mcp.allye.app/mcp`; Claude owns OAuth registration, credentials, and refresh.
2. **Other agents** (OpenCode, Cursor, Codex, Gemini CLI, Hermes Agent): each gets a per-agent manifest under `manifests/<agent>/` and an agent-assisted `docs/install-*.md` guide. OpenCode additionally gets `packages/allye-opencode`, which registers six workflow agents but does not read credentials or call MCP outside OpenCode's native connection. Pi uses the native `allye-pi` package and the user's existing pi-mcp-adapter config.

`install/adapters.json` is the canonical registry of target config shapes. The current `install.sh` distribution boundary rejects shared config writes without an API-backed ownership artifact and rejects physical uninstall. Preserve that fail-closed behavior: update source templates and native setup guides rather than adding a bypassing writer.

When editing workflow methodology, the canonical source is `skills/*/SKILL.md` — there is no separate synced/legacy copy. The old `skills/workflows/`, `skills/methodology/`, `skills/reference/`, and `skills/bootstrap/` directories were dead duplicates that drifted from the canonical files and have been deleted; each skill's `SKILL.md` is the single source of truth. Pi's adapter exposes this same root `skills/` directory through resource discovery; it does not copy or maintain a second skill tree.

### Runtime flow (Claude Code)

1. `SessionStart` fires → `hooks/session-start.sh` runs. It tries to fetch the `using-allye` skill fresh from the Allye API (`GET /api/skills/export`), falling back to the local `skills/using-allye/SKILL.md` if the API call fails or no PAT/OAuth is configured. The result is injected as `additionalContext`.
2. That bootstrap skill teaches the agent to: check for a pasted **Handover** marker first (see below) and route directly off it if present; otherwise select the smallest useful playbook, use optional context and capabilities proportionally, obtain consent before consequential changes, verify the result, and persist durable state when useful.
3. Workflow playbooks run directly in the main conversation by default so they can ask questions when needed. Optional subagents handle bounded research, review, or execution when the runtime supports them and delegation is useful; local execution remains valid when it does not.
4. Every skill lives directly under `skills/<name>/SKILL.md`, bare-named with no `allye-` prefix — **16 skills** in total: `sandbox`, `handover-protocol`, `product-planning`, `technical-planning`, `orchestrator`, `execution`, `review`, `delivery`, `memory-protocol`, `tdd-workflow`, `tools-quickref`, `setup`, `using-allye`, `verification-loop`, `agent-runtime`, `branch-landing` — Claude Code already namespaces plugin skills as `allye:<skill>`, so the prefix was redundant. The Allye backend API still references eight of the original ten (all but `using-allye` and the removed `board-progression`) by their `allye-*` slugs (see `seed/seed-skills.json`'s `slug` field) — an intentionally separate, unchanged identifier from the directory name; every skill added since (`handover-protocol`, `sandbox`, `orchestrator`, `verification-loop`, `agent-runtime`, `branch-landing`) uses a bare slug from the start, no legacy prefix to preserve.

### Adaptive toolkit

The toolkit offers composable playbooks for discovery, product/technical planning, execution, review, delivery, memory, verification, and optional delegation. Users may traverse checkpoints in the order useful for their intent and risk; meaningful work can use handovers and tracked tasks, while small local changes may remain in-session without creating specs or tasks.

Optional research, review, and execution subagents may be used when the current runtime supports them and delegation is beneficial. Herdr provides an optional runtime capability for isolated panes and agent lifecycle events; without it, work continues locally or through other available mechanisms.

**The Handover Catalog** (`skills/handover-protocol/`) is the shared contract: a handover is chat text only (never saved as a memory or file), always starting with a `## 🔄 Allye Handover — {type}` marker `using-allye` auto-detects. Six named types, each with its own objective and field set (not one generic template) — see `skills/handover-protocol/references/*.md`: `discovery-to-planning`, `planning-to-technical`, `technical-to-orchestration`, `story-execution`, `execution-report`, `correction`.

Design spec: `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md`. Extended by `docs/allye/specs/2026-07-26-agent-runtime-and-verification-design.md`, which adds story-parallel delivery over an agent-runtime contract, the verification loop, and phase-to-agent routing; its execution notes live in `docs/allye/notes/2026-07-26-execution-retrospective.md`. Implementation plans (all executed): `docs/allye/plans/2026-07-12-guided-delivery-workflow-0{1..6}-*.md`.

### OAuth connection

Every runtime uses one server named `allye` at `https://mcp.allye.app/mcp`. Tenant selection is part of consent, not the URL. The host runtime performs discovery, dynamic client registration, token storage, and refresh; plugin code must not read or print tokens, add fixed bearer headers or client IDs, or implement a parallel login flow.

