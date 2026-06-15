# 1.0.0 (2026-06-15)


### Bug Fixes

* add hard boundary preventing Fenix Plan from implementing ([8d0c196](https://github.com/allye-app/allye-plugin/commit/8d0c1963afef6f843f8f95a8498725028e7d9ed5))
* add MCP reconnect step to fenix-setup ([31048d9](https://github.com/allye-app/allye-plugin/commit/31048d9c31249a9a788749d4673114c84db08309))
* add update instructions inline with each installation step ([002816f](https://github.com/allye-app/allye-plugin/commit/002816faad17a0277d1b08751faa3213c649fde0))
* correct .mcp.json description in README ([61c8cb9](https://github.com/allye-app/allye-plugin/commit/61c8cb9fd346876ba2ee2fc385cb4ab92ed73bd4))
* correct OpenCode update instructions ([37767f4](https://github.com/allye-app/allye-plugin/commit/37767f42ae32e8b8adb3407d8f010fcd031281c2))
* correct repo URLs and sync version to 1.17.2 ([e35c226](https://github.com/allye-app/allye-plugin/commit/e35c226294a6705b16961697516a2f2644b80c70))
* **hook:** update session-start.sh to support OAuth mode (was editing wrong file) ([f2c7ad9](https://github.com/allye-app/allye-plugin/commit/f2c7ad98411528fb392065d775b5e025203956c0))
* migrate all platform install/update docs from PAT to OAuth ([2c50abb](https://github.com/allye-app/allye-plugin/commit/2c50abbb1f5372c590b024a77087116725f866c2))
* **opencode:** update install guide and config to use OAuth instead of PAT ([d91ae03](https://github.com/allye-app/allye-plugin/commit/d91ae0364cd92e4fb44ee73ed0b06be5d152acbc))
* remove .mcp.json from plugin, setup configures MCP for all scopes ([6fb8fd0](https://github.com/allye-app/allye-plugin/commit/6fb8fd083815c4839e824fb5e929b0f9426957f8)), closes [#9427](https://github.com/allye-app/allye-plugin/issues/9427)
* remove seed step from install guides ([6140c34](https://github.com/allye-app/allye-plugin/commit/6140c3477f59f9dfa1d8be3a0a0dca8f2bb65de5))
* retrigger CI for npm publish with updated token ([3a65e1a](https://github.com/allye-app/allye-plugin/commit/3a65e1a30f4bde4e9337d97a95a5b938b8094dc9))
* setup now creates project-level .mcp.json for reliable env var resolution ([fe9d5d5](https://github.com/allye-app/allye-plugin/commit/fe9d5d5e529f50eb22129e7764b0995292093475)), closes [#9427](https://github.com/allye-app/allye-plugin/issues/9427)
* setup uses claude mcp add for local scope, direct config for global ([a587eaf](https://github.com/allye-app/allye-plugin/commit/a587eaf66c327f4a75089b52826f4ba44ac1d8d3)), closes [#9427](https://github.com/allye-app/allye-plugin/issues/9427)
* **setup:** make OAuth the assertive default — do not ask for PAT unless user requests it ([9953384](https://github.com/allye-app/allye-plugin/commit/995338442ec3ee51f2ba05bf416459c4c0a63384))
* trigger CI for initial npm publish ([fa74904](https://github.com/allye-app/allye-plugin/commit/fa7490492032423f677a92d8f962443e9f14c0a1))
* update Fenix account URL to app.fenix.devshire.app ([fa0d671](https://github.com/allye-app/allye-plugin/commit/fa0d671bec36a4b7553dc1450d001baef3612acb))
* update setup skill to document fnx_ token prefix ([3632013](https://github.com/allye-app/allye-plugin/commit/3632013a35d675df4b06ba17ba6403032abbef63))


### Features

* add agent-assisted update guides for all platforms ([ebad2f2](https://github.com/allye-app/allye-plugin/commit/ebad2f2d31d876b0bde77c7bf222012fe849db64))
* add fenix-opencode multi-agent plugin and Claude Code subagents ([c3c764c](https://github.com/allye-app/allye-plugin/commit/c3c764c6eb6fb4009c4e82b381746f38d8e4b581))
* add planning best practices from real usage feedback ([c923282](https://github.com/allye-app/allye-plugin/commit/c92328230ef93322e191489ed49f27d6ba08cd1c))
* add project-aware skill discovery and language detection to all agents ([a7528ac](https://github.com/allye-app/allye-plugin/commit/a7528ac8c2fa5246ca8b6a486f0d891791dc5fc7))
* add semantic-release for automated versioning ([54f766c](https://github.com/allye-app/allye-plugin/commit/54f766ca5c53cb52b0ef703f34c5bbe2a9685831))
* add structured handoff flow from Plan to Build agent ([9df37a9](https://github.com/allye-app/allye-plugin/commit/9df37a96ef4e65157d8c41ffd4c813e29d5a20ea))
* auto-detect plugin scope in fenix-setup for multi-tenant support ([f99f226](https://github.com/allye-app/allye-plugin/commit/f99f226e5cb86649a0956213e49b27c9208b3629))
* auto-generate tenant slug for multi-account OAuth isolation ([89599c2](https://github.com/allye-app/allye-plugin/commit/89599c2de9fdadaac79a2b900a2839ea72b74898))
* auto-inject user context via system prompt transform ([8882db2](https://github.com/allye-app/allye-plugin/commit/8882db2a23b198e00768b524f28c25ffe9d42a73))
* auto-publish fenix-opencode to npm on release ([933582b](https://github.com/allye-app/allye-plugin/commit/933582bf38e7fefbdb508985178b851cb8d4e6bd))
* improve session hook and bootstrap flow ([86ed910](https://github.com/allye-app/allye-plugin/commit/86ed910d238cbb0755cbc65d195daf30c1fb15ad))
* **oauth:** OAuth for ALL platforms — zero PAT ([c3b70bc](https://github.com/allye-app/allye-plugin/commit/c3b70bcbc69215f7baa773c64ef61f9069d9e7a8))
* **oauth:** update plugin for OAuth 2.1 authentication (TEMA-1234) ([3eb3330](https://github.com/allye-app/allye-plugin/commit/3eb3330dee5d1b930422a7e64ef70dea1afbb494))
* **opencode:** configure static OAuth client_id in manifest ([b22cf49](https://github.com/allye-app/allye-plugin/commit/b22cf4945dee2378757a752575687de9b9b61627))
* **opencode:** switch to OAuth — remove static auth headers ([c86a12e](https://github.com/allye-app/allye-plugin/commit/c86a12eb9ca85012397860e9fe99878c3915f8c3))
* rewrite README with user-focused documentation ([db71e49](https://github.com/allye-app/allye-plugin/commit/db71e494281aa40f64b38fe018479dd095997b0b))
* support multi-team skill seeding in install guides ([c1d3c26](https://github.com/allye-app/allye-plugin/commit/c1d3c26bdc7a3215339e0df4f666ecdbb9e9e2b2))
* update install flow and docs for multi-agent system ([fbfef94](https://github.com/allye-app/allye-plugin/commit/fbfef9449e97b952e5bd53eb54ad9b399b572543))
* update README with updating guide, skill discovery, and language support ([fe10e39](https://github.com/allye-app/allye-plugin/commit/fe10e395fce59651dafa2eb028163b1eadd9148a))

# Changelog
