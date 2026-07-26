# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Source of the **Allye** plugin — a methodology/workflow layer on top of the Allye MCP server, distributed to five different AI coding agents (Claude Code, OpenCode, Cursor, Codex, Gemini CLI). There is no build step for the plugin itself; it's mostly Markdown (agents, skills) plus shell scripts, distributed via `install.sh` or the Claude Code plugin marketplace. The one compiled piece is `packages/allye-opencode` (a TypeScript/bun package published to npm).

## Commands

- No repo-wide build/lint/test — this is markdown + shell, not compiled (except the opencode package below).
- Bump version, sync files, commit, tag, and push a release: `./release.sh [major|minor|patch]` (default `patch`). In practice releases are automated by semantic-release on push to `main` (see `.releaserc.json` / `.github/workflows/auto-release.yml`), driven by Conventional Commits — `release.sh` is the manual fallback.
- Manual local install/update for testing: `./install.sh` (prompts for an Allye PAT, seeds skills via the API, detects and configures installed agents).

### `packages/allye-opencode` (bun, TypeScript)
- `bun install`
- `bun run generate` — regenerates `src/prompts/` from the canonical skill/agent markdown via `scripts/generate-prompts.ts`
- `bun run build` — runs `generate` then bundles with `bun build src/index.ts --outdir dist --target bun`
- `bun run typecheck` — `tsc --noEmit`
- Published to npm as `allye-opencode` automatically by CI when `package.json`'s version changes on `main` (see `publish-opencode` job in `.github/workflows/auto-release.yml`).

## Architecture

### Two parallel distribution mechanisms

1. **Claude Code plugin** (native): `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` describe the plugin; Claude Code loads `agents/*.md` as subagents, `skills/*/SKILL.md` as on-demand skills, and `hooks/hooks.json` wires `hooks/session-start.sh` to `SessionStart`. `.mcp.json` configures the Allye MCP server itself (OAuth 2.1, HTTP transport, tenant-scoped URL).
2. **Other agents** (OpenCode, Cursor, Codex, Gemini CLI): each gets a per-agent manifest under `manifests/<agent>/` (e.g. `manifests/codex/AGENTS.md`, `manifests/cursor/.cursorrules`, `manifests/gemini/GEMINI.md`, `manifests/opencode/opencode.json`) that bakes in the same workflow instructions in that agent's native format. These manifests are installed via the agent-assisted `docs/install-*.md` guides (paste-into-agent instructions), not by `install.sh` — `install.sh` only configures MCP connections, the Claude Code hook/env, and the OpenCode plugin array. OpenCode additionally gets a real plugin package (`packages/allye-opencode`) that registers 6 agents (Allye orchestrator-router, Plan, Orchestrator, Build, Review, Deliver) and injects Allye context via a system-prompt transform hook (`src/index.ts`, `src/context.ts`).

When editing workflow methodology, the canonical source is `skills/*/SKILL.md` — there is no separate synced/legacy copy. The old `skills/workflows/`, `skills/methodology/`, `skills/reference/`, and `skills/bootstrap/` directories were dead duplicates that drifted from the canonical files and have been deleted; each skill's `SKILL.md` is the single source of truth.

### Runtime flow (Claude Code)

1. `SessionStart` fires → `hooks/session-start.sh` runs. It tries to fetch the `using-allye` skill fresh from the Allye API (`GET /api/skills/export`), falling back to the local `skills/using-allye/SKILL.md` if the API call fails or no PAT/OAuth is configured. The result is injected as `additionalContext`.
2. That bootstrap skill teaches the orchestrator to: check for a pasted **Handover** marker first (see below) and route directly off it if present; otherwise search memories, detect the workflow phase heuristically, load the matching phase skill on demand (never all at once), respect hard gates (no code without tasks, no skipping the planning discussion phase, no false "done", TDD when applicable), and save session-state memories before ending.
3. Every phase runs as a skill loaded directly into the main conversation thread by default (not a dispatched subagent), because most phases need to pause and ask the human questions — dispatched subagents can't. The plugin ships four subagents for the roles that genuinely don't need to ask: `agents/reviewer.md` (always dispatched), `agents/deep-search.md` and `agents/code-analyzer.md` (bounded research, dispatched from Sandbox or Technical Planning), and `agents/executor.md` (Orchestrator's opt-in automatic mode — see §4 of the `orchestrator` skill; it halts and reports instead of guessing when a task turns out to be underspecified, since it can't ask either).
4. Every skill lives directly under `skills/<name>/SKILL.md`, bare-named with no `allye-` prefix (`sandbox`, `handover-protocol`, `product-planning`, `technical-planning`, `orchestrator`, `execution`, `review`, `delivery`, `memory-protocol`, `tdd-workflow`, `board-progression`, `tools-quickref`, `setup`, `using-allye`) — Claude Code already namespaces plugin skills as `allye:<skill>`, so the prefix was redundant. The Allye backend API still references nine of the original ten (all but `using-allye`) by their `allye-*` slugs (see `seed/seed-skills.json`'s `slug` field) — an intentionally separate, unchanged identifier from the directory name; the three new skills (`handover-protocol`, `sandbox`, `orchestrator`) use bare slugs from the start, no legacy prefix to preserve.

### Guided delivery workflow

Six phases, connected by handovers instead of one continuous conversation — each phase runs in a fresh, lean-context chat: **Sandbox** (`skills/sandbox/`, open-ended ideation and research, never creates a work item — `<HARD-GATE>` enforced) → **Product Planning** (squares/quadradinhos → Epic/Feature/Story, reuse-or-create discipline) → **Technical Planning** (discussion phase, mandatory architecture gray areas, task waves) → **Orchestrator** (`skills/orchestrator/`, assignee management, correction loop with a 3-strike human-escalation rule, continuous status cascade) → **Executor** — dispatched to one story at a time, **manual** (`skills/execution/`, fresh chat, can ask questions) or **automatic** (`agents/executor.md`, dispatched via the `Agent` tool, halts and reports instead of guessing — Orchestrator asks which mode per story) → **Reviewer** (`agents/reviewer.md`, always dispatched via the `Agent` tool, since review never needs to ask anything). Story close-out (`skills/delivery/`) verifies every task is done, closes the story, and closes the parent feature when all its stories are complete. Epic close-out is the Orchestrator's (`skills/orchestrator/` §8) and is always a deliberate, manual step — it announces completion and asks, never auto-runs `delivery`.

`skills/sandbox/` can also dispatch two bounded, question-free research subagents — `agents/deep-search.md` (multi-source web research) and `agents/code-analyzer.md` (clones a public repo under the session scratchpad, analyzes, reports, deletes unconditionally) — also available from Technical Planning.

**The Handover Catalog** (`skills/handover-protocol/`) is the shared contract: a handover is chat text only (never saved as a memory or file), always starting with a `## 🔄 Allye Handover — {type}` marker `using-allye` auto-detects. Six named types, each with its own objective and field set (not one generic template) — see `skills/handover-protocol/references/*.md`: `discovery-to-planning`, `planning-to-technical`, `technical-to-orchestration`, `story-execution`, `execution-report`, `correction`.

Design spec: `docs/superpowers/specs/2026-07-12-guided-delivery-workflow-design.md`. Implementation plans (all executed): `docs/superpowers/plans/2026-07-12-guided-delivery-workflow-0{1..6}-*.md`.

### Multi-tenant OAuth

The plugin supports multiple Allye accounts across projects: `ALLYE_TENANT_SLUG` (auto-derived from the working directory name if unset) is interpolated into the MCP server URL in `.mcp.json`, giving each project directory its own OAuth session. `scripts/oauth-login.sh` implements the PKCE browser-based OAuth flow used outside Claude Code's native OAuth UI (e.g. CI/manual setup); `ALLYE_PAT` remains a fallback auth path for non-interactive contexts.

