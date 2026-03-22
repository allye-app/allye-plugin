## [1.14.1](https://github.com/fenix-assistant/fenix-plugin/compare/v1.14.0...v1.14.1) (2026-03-22)


### Bug Fixes

* **hook:** update session-start.sh to support OAuth mode (was editing wrong file) ([f2c7ad9](https://github.com/fenix-assistant/fenix-plugin/commit/f2c7ad98411528fb392065d775b5e025203956c0))

# [1.14.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.13.4...v1.14.0) (2026-03-22)


### Features

* **oauth:** update plugin for OAuth 2.1 authentication (TEMA-1234) ([3eb3330](https://github.com/fenix-assistant/fenix-plugin/commit/3eb3330dee5d1b930422a7e64ef70dea1afbb494))

## [2.0.0] — OAuth 2.1 Support (2026-03-19)

### Features

* **OAuth 2.1 authentication** — Plugin now uses OAuth by default. No PAT required for interactive use (Claude Code, Claude Desktop).
* **New `.mcp.json`** — Clean format: `{ "fenix": { "type": "http", "url": "https://fenix-mcp.devshire.app/mcp" } }`
* **Streamable HTTP transport** — New `/mcp` endpoint replaces deprecated `/jsonrpc`
* **PAT fallback** — PAT still works for CI/CD and headless environments

### Breaking Changes

* MCP endpoint changed from `/jsonrpc` to `/mcp` (old endpoint still works but is deprecated)
* `.mcp.json` format changed to root-key style (no `mcpServers` wrapper)
* OAuth is now the default auth method — PAT setup only needed for CI/CD

### Migration

For interactive users (Claude Code/Desktop): **No action needed.** The plugin handles OAuth automatically.

For CI/CD users: Continue using PAT. Run `/fenix-setup` and choose "PAT setup" to configure.

## [1.13.4](https://github.com/fenix-assistant/fenix-plugin/compare/v1.13.3...v1.13.4) (2026-03-17)


### Bug Fixes

* remove .mcp.json from plugin, setup configures MCP for all scopes ([6fb8fd0](https://github.com/fenix-assistant/fenix-plugin/commit/6fb8fd083815c4839e824fb5e929b0f9426957f8)), closes [#9427](https://github.com/fenix-assistant/fenix-plugin/issues/9427)

## [1.13.3](https://github.com/fenix-assistant/fenix-plugin/compare/v1.13.2...v1.13.3) (2026-03-17)


### Bug Fixes

* setup uses claude mcp add for local scope, direct config for global ([a587eaf](https://github.com/fenix-assistant/fenix-plugin/commit/a587eaf66c327f4a75089b52826f4ba44ac1d8d3)), closes [#9427](https://github.com/fenix-assistant/fenix-plugin/issues/9427)

## [1.13.2](https://github.com/fenix-assistant/fenix-plugin/compare/v1.13.1...v1.13.2) (2026-03-17)


### Bug Fixes

* add MCP reconnect step to fenix-setup ([31048d9](https://github.com/fenix-assistant/fenix-plugin/commit/31048d9c31249a9a788749d4673114c84db08309))

## [1.13.1](https://github.com/fenix-assistant/fenix-plugin/compare/v1.13.0...v1.13.1) (2026-03-17)


### Bug Fixes

* setup now creates project-level .mcp.json for reliable env var resolution ([fe9d5d5](https://github.com/fenix-assistant/fenix-plugin/commit/fe9d5d5e529f50eb22129e7764b0995292093475)), closes [#9427](https://github.com/fenix-assistant/fenix-plugin/issues/9427)

# [1.13.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.12.0...v1.13.0) (2026-03-17)


### Features

* auto-detect plugin scope in fenix-setup for multi-tenant support ([f99f226](https://github.com/fenix-assistant/fenix-plugin/commit/f99f226e5cb86649a0956213e49b27c9208b3629))

# [1.12.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.11.1...v1.12.0) (2026-03-16)


### Features

* add structured handoff flow from Plan to Build agent ([9df37a9](https://github.com/fenix-assistant/fenix-plugin/commit/9df37a96ef4e65157d8c41ffd4c813e29d5a20ea))

## [1.11.1](https://github.com/fenix-assistant/fenix-plugin/compare/v1.11.0...v1.11.1) (2026-03-16)


### Bug Fixes

* add hard boundary preventing Fenix Plan from implementing ([8d0c196](https://github.com/fenix-assistant/fenix-plugin/commit/8d0c1963afef6f843f8f95a8498725028e7d9ed5))

# [1.11.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.10.0...v1.11.0) (2026-03-16)


### Features

* add planning best practices from real usage feedback ([c923282](https://github.com/fenix-assistant/fenix-plugin/commit/c92328230ef93322e191489ed49f27d6ba08cd1c))

# [1.10.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.9.2...v1.10.0) (2026-03-16)


### Features

* add agent-assisted update guides for all platforms ([ebad2f2](https://github.com/fenix-assistant/fenix-plugin/commit/ebad2f2d31d876b0bde77c7bf222012fe849db64))

## [1.9.2](https://github.com/fenix-assistant/fenix-plugin/compare/v1.9.1...v1.9.2) (2026-03-16)


### Bug Fixes

* correct OpenCode update instructions ([37767f4](https://github.com/fenix-assistant/fenix-plugin/commit/37767f42ae32e8b8adb3407d8f010fcd031281c2))

## [1.9.1](https://github.com/fenix-assistant/fenix-plugin/compare/v1.9.0...v1.9.1) (2026-03-16)


### Bug Fixes

* add update instructions inline with each installation step ([002816f](https://github.com/fenix-assistant/fenix-plugin/commit/002816faad17a0277d1b08751faa3213c649fde0))

# [1.9.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.8.0...v1.9.0) (2026-03-16)


### Features

* update README with updating guide, skill discovery, and language support ([fe10e39](https://github.com/fenix-assistant/fenix-plugin/commit/fe10e395fce59651dafa2eb028163b1eadd9148a))

# [1.8.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.7.4...v1.8.0) (2026-03-16)


### Features

* add project-aware skill discovery and language detection to all agents ([a7528ac](https://github.com/fenix-assistant/fenix-plugin/commit/a7528ac8c2fa5246ca8b6a486f0d891791dc5fc7))

## [1.7.4](https://github.com/fenix-assistant/fenix-plugin/compare/v1.7.3...v1.7.4) (2026-03-16)


### Bug Fixes

* remove seed step from install guides ([6140c34](https://github.com/fenix-assistant/fenix-plugin/commit/6140c3477f59f9dfa1d8be3a0a0dca8f2bb65de5))

## [1.7.3](https://github.com/fenix-assistant/fenix-plugin/compare/v1.7.2...v1.7.3) (2026-03-16)


### Bug Fixes

* update setup skill to document fnx_ token prefix ([3632013](https://github.com/fenix-assistant/fenix-plugin/commit/3632013a35d675df4b06ba17ba6403032abbef63))

## [1.7.2](https://github.com/fenix-assistant/fenix-plugin/compare/v1.7.1...v1.7.2) (2026-03-16)


### Bug Fixes

* retrigger CI for npm publish with updated token ([3a65e1a](https://github.com/fenix-assistant/fenix-plugin/commit/3a65e1a30f4bde4e9337d97a95a5b938b8094dc9))

## [1.7.1](https://github.com/fenix-assistant/fenix-plugin/compare/v1.7.0...v1.7.1) (2026-03-16)


### Bug Fixes

* trigger CI for initial npm publish ([fa74904](https://github.com/fenix-assistant/fenix-plugin/commit/fa7490492032423f677a92d8f962443e9f14c0a1))

# [1.7.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.6.0...v1.7.0) (2026-03-16)


### Features

* auto-publish fenix-opencode to npm on release ([933582b](https://github.com/fenix-assistant/fenix-plugin/commit/933582bf38e7fefbdb508985178b851cb8d4e6bd))

# [1.6.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.5.0...v1.6.0) (2026-03-15)


### Features

* rewrite README with user-focused documentation ([db71e49](https://github.com/fenix-assistant/fenix-plugin/commit/db71e494281aa40f64b38fe018479dd095997b0b))

# [1.5.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.4.0...v1.5.0) (2026-03-15)


### Features

* update install flow and docs for multi-agent system ([fbfef94](https://github.com/fenix-assistant/fenix-plugin/commit/fbfef9449e97b952e5bd53eb54ad9b399b572543))

# [1.4.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.3.0...v1.4.0) (2026-03-15)


### Features

* auto-inject user context via system prompt transform ([8882db2](https://github.com/fenix-assistant/fenix-plugin/commit/8882db2a23b198e00768b524f28c25ffe9d42a73))

# [1.3.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.2.0...v1.3.0) (2026-03-15)


### Features

* add fenix-opencode multi-agent plugin and Claude Code subagents ([c3c764c](https://github.com/fenix-assistant/fenix-plugin/commit/c3c764c6eb6fb4009c4e82b381746f38d8e4b581))

# [1.2.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.1.1...v1.2.0) (2026-03-15)


### Features

* support multi-team skill seeding in install guides ([c1d3c26](https://github.com/fenix-assistant/fenix-plugin/commit/c1d3c26bdc7a3215339e0df4f666ecdbb9e9e2b2))

## [1.1.1](https://github.com/fenix-assistant/fenix-plugin/compare/v1.1.0...v1.1.1) (2026-03-14)


### Bug Fixes

* correct .mcp.json description in README ([61c8cb9](https://github.com/fenix-assistant/fenix-plugin/commit/61c8cb9fd346876ba2ee2fc385cb4ab92ed73bd4))

# [1.1.0](https://github.com/fenix-assistant/fenix-plugin/compare/v1.0.0...v1.1.0) (2026-03-14)


### Features

* improve session hook and bootstrap flow ([86ed910](https://github.com/fenix-assistant/fenix-plugin/commit/86ed910d238cbb0755cbc65d195daf30c1fb15ad))

# 1.0.0 (2026-03-14)


### Features

* add semantic-release for automated versioning ([54f766c](https://github.com/fenix-assistant/fenix-plugin/commit/54f766ca5c53cb52b0ef703f34c5bbe2a9685831))
