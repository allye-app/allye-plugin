# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Source of the **Allye** plugin — a methodology/workflow layer on top of the Allye MCP server, distributed to seven different AI coding agents (Claude Code, OpenCode, Cursor, Codex, Gemini CLI, Hermes Agent, Pi). There is no build step for the plugin itself; it's mostly Markdown (agents, skills) plus shell scripts, distributed via `install.sh` or the Claude Code plugin marketplace. The compiled adapters are `packages/allye-opencode` and `packages/allye-pi`.

## Commands

- No repo-wide build/lint/test — this is markdown + shell, not compiled (except the opencode package below).
- Bump version, sync files, commit, tag, and push a release: `./release.sh [major|minor|patch]` (default `patch`). In practice releases are automated by semantic-release on push to `main` (see `.releaserc.json` / `.github/workflows/auto-release.yml`), driven by Conventional Commits — `release.sh` is the manual fallback.
- Manual local install/update for testing: `./install.sh` (prompts for an Allye PAT, seeds skills via the API, detects and configures every installed agent). Also supports explicit verbs: `./install.sh status`, `./install.sh install <agent>`, `./install.sh uninstall <agent>`.

### `packages/allye-opencode` (bun, TypeScript)
- `bun install`
- `bun run generate` — regenerates `src/prompts/` from the canonical skill/agent markdown via `scripts/generate-prompts.ts`
- `bun run build` — runs `generate` then bundles with `bun build src/index.ts --outdir dist --target bun`
- `bun run typecheck` — `tsc --noEmit`
- Published to npm as `allye-opencode` automatically by CI when `package.json`'s version changes on `main` (see `publish-opencode` job in `.github/workflows/auto-release.yml`).

### `packages/allye-pi` (native Pi package adapter)
- `npm install` from the repository root installs the adapter's development dependencies; `./install.sh install pi` installs runtime dependencies into a clean checkout with `npm install --omit=dev`.
- `npm run typecheck` validates `packages/allye-pi/src/index.ts`.
- `npm run test:pi` covers mode tool filtering and the multi-team bootstrap gate.
- The root `package.json` is the Pi package manifest: it points Pi at the adapter extension and the canonical root `skills/` directory.
- The adapter uses the configured `pi-mcp-adapter` for Allye context, defaults to executor mode, and exposes Herdr only when `ALLYE_PI_MODE=orchestrator` is explicit.

## Architecture

### Two parallel distribution mechanisms

1. **Claude Code plugin** (native): `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` describe the plugin; Claude Code loads `agents/*.md` as subagents, `skills/*/SKILL.md` as on-demand skills, and `hooks/hooks.json` wires `hooks/session-start.sh` to `SessionStart`. `.mcp.json` configures the Allye MCP server itself (OAuth 2.1, HTTP transport, tenant-scoped URL).
2. **Other agents** (OpenCode, Cursor, Codex, Gemini CLI, Hermes Agent): each gets a per-agent manifest under `manifests/<agent>/` (e.g. `manifests/codex/AGENTS.md`, `manifests/cursor/.cursorrules`, `manifests/gemini/GEMINI.md`, `manifests/opencode/opencode.json`, `manifests/hermes/`) that bakes in the same workflow instructions in that agent's native format. The four paste-into-agent manifests are installed via the agent-assisted `docs/install-*.md` guides; Hermes's is installed by `install.sh` itself, since its shape (a Python plugin directory plus skills read from disk) needs real file writes, not a paste. OpenCode additionally gets a real plugin package (`packages/allye-opencode`) that registers 6 agents (Allye orchestrator-router, Plan, Orchestrator, Build, Review, Deliver) and injects Allye context via a system-prompt transform hook (`src/index.ts`, `src/context.ts`). Pi gets a native package adapter under `packages/allye-pi`; its root `package.json` points to the adapter and the canonical `skills/` directory.

`install.sh` is a thin dispatcher (`install.sh/lib.sh` sourced after PAT/skill-seeding) over `install/adapters.json` — one data entry per agent describing how to detect it, where its MCP config lives and in what format (`json` / `toml` / `yaml-block`), whether it fetches skills over MCP or reads them from a directory, and its bootstrap mechanism if any. Three verbs — `install [agent]`, `uninstall <agent>`, `status` — read that table; every writer is additive and idempotent (read, merge, write back), and a version-marker comment embedded in each file it writes (`ALLYE_INSTALLER_VERSION=N`) is what makes `status` a read instead of a registry. Adding another agent is an adapter entry plus, at most, reusing an existing format writer.

When editing workflow methodology, the canonical source is `skills/*/SKILL.md` — there is no separate synced/legacy copy. The old `skills/workflows/`, `skills/methodology/`, `skills/reference/`, and `skills/bootstrap/` directories were dead duplicates that drifted from the canonical files and have been deleted; each skill's `SKILL.md` is the single source of truth. Pi's adapter exposes this same root `skills/` directory through resource discovery; it does not copy or maintain a second skill tree.

### Runtime flow (Claude Code)

1. `SessionStart` fires → `hooks/session-start.sh` runs. It tries to fetch the `using-allye` skill fresh from the Allye API (`GET /api/skills/export`), falling back to the local `skills/using-allye/SKILL.md` if the API call fails or no PAT/OAuth is configured. The result is injected as `additionalContext`.
2. That bootstrap skill teaches the orchestrator to: check for a pasted **Handover** marker first (see below) and route directly off it if present; otherwise search memories, detect the workflow phase heuristically, load the matching phase skill on demand (never all at once), respect hard gates (no code without tasks, no skipping the planning discussion phase, no false "done", TDD when applicable), and save session-state memories before ending.
3. Every phase runs as a skill loaded directly into the main conversation thread by default (not a dispatched subagent), because most phases need to pause and ask the human questions — dispatched subagents can't. The plugin ships five subagents for the roles that genuinely don't need to ask: `agents/reviewer-standards.md` and `agents/reviewer-spec.md` (both always dispatched, in parallel, findings never merged — only the go/no-go decision combines them), `agents/deep-search.md` and `agents/code-analyzer.md` (bounded research, dispatched from Sandbox or Technical Planning), and `agents/executor.md` (Orchestrator's opt-in automatic mode — see §4 of the `orchestrator` skill; it halts and reports instead of guessing when a task turns out to be underspecified, since it can't ask either).
4. Every skill lives directly under `skills/<name>/SKILL.md`, bare-named with no `allye-` prefix — **17 skills** in total: `sandbox`, `handover-protocol`, `product-planning`, `technical-planning`, `orchestrator`, `execution`, `review`, `delivery`, `memory-protocol`, `tdd-workflow`, `board-progression`, `tools-quickref`, `setup`, `using-allye`, `verification-loop`, `agent-runtime`, `branch-landing` — Claude Code already namespaces plugin skills as `allye:<skill>`, so the prefix was redundant. The Allye backend API still references nine of the original ten (all but `using-allye`) by their `allye-*` slugs (see `seed/seed-skills.json`'s `slug` field) — an intentionally separate, unchanged identifier from the directory name; every skill added since (`handover-protocol`, `sandbox`, `orchestrator`, `verification-loop`, `agent-runtime`, `branch-landing`) uses a bare slug from the start, no legacy prefix to preserve.

### Guided delivery workflow

Six phases, connected by handovers instead of one continuous conversation — each phase runs in a fresh, lean-context chat: **Sandbox** (`skills/sandbox/`, open-ended ideation and research, never creates a work item — `<HARD-GATE>` enforced) → **Product Planning** (squares/quadradinhos → Epic/Feature/Story, reuse-or-create discipline) → **Technical Planning** (discussion phase, mandatory architecture gray areas, task waves) → **Orchestrator** (`skills/orchestrator/`, assignee management, correction loop with a 3-strike human-escalation rule, continuous status cascade) → **Executor** → **Reviewer** (`agents/reviewer-standards.md` + `agents/reviewer-spec.md`, both always dispatched in parallel via the `Agent` tool, since review never needs to ask anything — findings are never merged, only the go/no-go decision combines them). Story close-out (`skills/delivery/`) verifies every task is done, closes the story, and closes the parent feature when all its stories are complete. Epic close-out is the Orchestrator's (`skills/orchestrator/` §8) and is always a deliberate, manual step — it announces completion and asks, never auto-runs `delivery`.

**Delivery is parallel-capable, not just serial.** The Orchestrator resolves its dispatch mode from what the session hook detected (`skills/agent-runtime/`): with a detected runtime (Herdr), it can drive several independent stories at once, each in its own git worktree and its own real agent process the human can watch and take over, merging and tearing down one story at a time as review clears (`skills/orchestrator/` §4.2, §7.1). **Without a detected runtime, everything degrades to the existing modes** — Executor dispatched to one story at a time, either **manual** (`skills/execution/`, fresh chat, can ask questions) or **automatic** (`agents/executor.md`, dispatched via the `Agent` tool, halts and reports instead of guessing — Orchestrator asks which mode per story).

`skills/sandbox/` can also dispatch two bounded, question-free research subagents — `agents/deep-search.md` (multi-source web research) and `agents/code-analyzer.md` (clones a public repo under the session scratchpad, analyzes, reports, deletes unconditionally) — also available from Technical Planning.

**The Handover Catalog** (`skills/handover-protocol/`) is the shared contract: a handover is chat text only (never saved as a memory or file), always starting with a `## 🔄 Allye Handover — {type}` marker `using-allye` auto-detects. Six named types, each with its own objective and field set (not one generic template) — see `skills/handover-protocol/references/*.md`: `discovery-to-planning`, `planning-to-technical`, `technical-to-orchestration`, `story-execution`, `execution-report`, `correction`.

Design spec: `docs/allye/specs/2026-07-12-guided-delivery-workflow-design.md`. Extended by `docs/allye/specs/2026-07-26-agent-runtime-and-verification-design.md`, which adds story-parallel delivery over an agent-runtime contract, the verification loop, and phase-to-agent routing; its execution notes live in `docs/allye/notes/2026-07-26-execution-retrospective.md`. Implementation plans (all executed): `docs/allye/plans/2026-07-12-guided-delivery-workflow-0{1..6}-*.md`.

### Multi-tenant OAuth

The plugin supports multiple Allye accounts across projects: `ALLYE_TENANT_SLUG` (auto-derived from the working directory name if unset) is interpolated into the MCP server URL in `.mcp.json`, giving each project directory its own OAuth session. `scripts/oauth-login.sh` implements the PKCE browser-based OAuth flow used outside Claude Code's native OAuth UI (e.g. CI/manual setup); `ALLYE_PAT` remains a fallback auth path for non-interactive contexts.

