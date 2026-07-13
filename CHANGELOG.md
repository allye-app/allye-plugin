## [1.2.4](https://github.com/allye-app/allye-plugin/compare/v1.2.3...v1.2.4) (2026-07-13)


### Bug Fixes

* distinguish confirmed status categories from team-configurable status names ([1b600d1](https://github.com/allye-app/allye-plugin/commit/1b600d120b9f052765c7ccb0ffcda18040322e85))
* pass active team to Reviewer's dispatch prompt ([862a247](https://github.com/allye-app/allye-plugin/commit/862a2477972f35e344789921b8484fdfd3a33073))
* product-planning/technical-planning work_items calls against the real source ([0cf6766](https://github.com/allye-app/allye-plugin/commit/0cf6766150de7eba89c37f33f0267c3d30f753f9))
* remove fabricated Entity Linking feature, stale memory claims ([b50ba68](https://github.com/allye-app/allye-plugin/commit/b50ba686be019754f5db99c4e63b87efed787b2a))
* skill_list only returns metadata, add the missing skill_get follow-up ([4b4c45d](https://github.com/allye-app/allye-plugin/commit/4b4c45d08e4cb921c518d1a2da41da50fffb9825))
* tools-quickref field names and parameters against the real allye-mcp source ([5a4a34f](https://github.com/allye-app/allye-plugin/commit/5a4a34f298719fc16438fcb1fa7965038c70c6e9))
* work_get(key:) should be work_get(work_key:) ([42e4267](https://github.com/allye-app/allye-plugin/commit/42e42672017565b9c42bd32627136723390f7a98))

## [1.2.3](https://github.com/allye-app/allye-plugin/compare/v1.2.2...v1.2.3) (2026-07-13)


### Bug Fixes

* cross-platform parity — stale counts, missing slug notes, non-portable handovers ([ade8bd0](https://github.com/allye-app/allye-plugin/commit/ade8bd0796b526a2c00cb1980a3c54ebaf10a3ad))
* filter Claude-Code-only automatic-Executor text out of the OpenCode-generated prompt ([394dc20](https://github.com/allye-app/allye-plugin/commit/394dc205f239a517836bea92e0245fa98aa833fe))
* install.sh was entirely PAT-based against the deprecated /jsonrpc endpoint ([11237fe](https://github.com/allye-app/allye-plugin/commit/11237fe3ff07a6f0f33073234866c2af184924ea))
* memory_save vocabulary mismatch, stale save protocol, broken tool calls ([66340f6](https://github.com/allye-app/allye-plugin/commit/66340f6c58c1a6e9093c0a4cb8cbcde972a3bc39))
* rewrite reviewer agent to match the non-interactive dispatch contract ([662e6b6](https://github.com/allye-app/allye-plugin/commit/662e6b652260e4be859993cf73aadfa59d6d5c01))
* story-execution handover self-contradicted on scope, Discovery Doc reference was silently dropped ([c853f78](https://github.com/allye-app/allye-plugin/commit/c853f782f420e3f33b6737604f2daf81cdd2991c))
* task done-status flow and correction-round rule were internally contradictory ([8dc5c09](https://github.com/allye-app/allye-plugin/commit/8dc5c0936940be51fbbc923b5e38dfd475c019a9))

## [1.2.2](https://github.com/allye-app/allye-plugin/compare/v1.2.1...v1.2.2) (2026-07-13)


### Bug Fixes

* move AskUserQuestion preference into using-allye as a global rule ([487221c](https://github.com/allye-app/allye-plugin/commit/487221c4fd32385fcf7f6d6b39898658ad94bccd))

## [1.2.1](https://github.com/allye-app/allye-plugin/compare/v1.2.0...v1.2.1) (2026-07-13)


### Bug Fixes

* restore language-detection instruction, missing from Claude Code and 3 other platforms ([b31dc82](https://github.com/allye-app/allye-plugin/commit/b31dc829af4143495a7e730515f0f2fc2e94f15f))

# [1.2.0](https://github.com/allye-app/allye-plugin/compare/v1.1.1...v1.2.0) (2026-07-13)


### Features

* **sandbox:** prefer AskUserQuestion tool for enumerable forks ([a9b5c9d](https://github.com/allye-app/allye-plugin/commit/a9b5c9d9830738f1277d4ebba11bae229787c8b0))

## [1.1.1](https://github.com/allye-app/allye-plugin/compare/v1.1.0...v1.1.1) (2026-07-13)


### Bug Fixes

* OAuth 2.1 is the auth mechanism on every platform, not just Claude Code ([423cb49](https://github.com/allye-app/allye-plugin/commit/423cb49f375a6f2ad4d04525d91ac0d092eaf5a0))

# [1.1.0](https://github.com/allye-app/allye-plugin/compare/v1.0.3...v1.1.0) (2026-07-13)


### Bug Fixes

* correct /allye-setup slash command to /allye:setup after skill rename ([ed1e543](https://github.com/allye-app/allye-plugin/commit/ed1e5433fbd39edce6014190893faf2fe2fc00b5))
* correct tools-quickref against the real allye-mcp source, add gotchas section ([c7f8053](https://github.com/allye-app/allye-plugin/commit/c7f8053181320db53114ad06533be959e6820ac7))
* remove dead bootstrap fallback, sync session-start hook copies ([a2f98e5](https://github.com/allye-app/allye-plugin/commit/a2f98e588c3540abba435f209f89ff5f05acf838))
* repoint allye-opencode generate-prompts.ts at renamed skill dirs ([a860067](https://github.com/allye-app/allye-plugin/commit/a8600678a22d016b74ec76f88c99dfa9167c91e9))
* repoint seed-skills.json source_file paths to renamed dirs, fix tools-quickref path bug ([eb80cef](https://github.com/allye-app/allye-plugin/commit/eb80cef136b1c305421658615a01726aa3b5634b))
* resolve handover skill-slug mismatch, bring README up to date with guided workflow ([599f80f](https://github.com/allye-app/allye-plugin/commit/599f80fc9c756261821d9b2fcf963753a43c5ab9))


### Features

* add automatic Executor mode to Orchestrator ([b3c35fd](https://github.com/allye-app/allye-plugin/commit/b3c35fdc2f4b6c1a4a0c7386f40422b199dfbcf4))
* add code-analyzer research subagent ([2cf2024](https://github.com/allye-app/allye-plugin/commit/2cf2024d44c105c35d98ac8cd103bc7cbe50b813))
* add correction handover template ([a33afa4](https://github.com/allye-app/allye-plugin/commit/a33afa4c528dc16efd2796d31e945d393bcd046b))
* add deep-search research subagent ([d51c1d9](https://github.com/allye-app/allye-plugin/commit/d51c1d9a01d0a970d5fb797bdb6b62cb43e14475))
* add discovery-to-planning handover template ([48954b1](https://github.com/allye-app/allye-plugin/commit/48954b1e5d3c0df7f5def774457a44d2b9afd44b))
* add execution-report handover template ([0f706c0](https://github.com/allye-app/allye-plugin/commit/0f706c021238fd6b9a13a713b0f4778d63c115c1))
* add handoff sections to Build, Review, Deliver OpenCode agents ([1bd8fde](https://github.com/allye-app/allye-plugin/commit/1bd8fde2d09ae698c9cff2e58b40812afab9ebdc))
* add handover auto-detection step to using-allye bootstrap ([aa8fbe5](https://github.com/allye-app/allye-plugin/commit/aa8fbe5b57786bce34a204c0642fa7265c86557a))
* add handover-protocol skill (marker spec + 6-type catalog) ([e83bdcf](https://github.com/allye-app/allye-plugin/commit/e83bdcfab0ef391654b6063eb360256320211fad))
* add handover-protocol, sandbox, orchestrator to OpenCode's skill sources ([69de01a](https://github.com/allye-app/allye-plugin/commit/69de01a2b3f604bbb0e73f448c67ea53edf7fb11))
* add Orchestrator role to OpenCode agent picker ([e083480](https://github.com/allye-app/allye-plugin/commit/e0834806856f733e9731e9304ad7154d980cd185))
* add orchestrator skill (assignee, dispatch loop, correction escalation, cascade) ([31c46d5](https://github.com/allye-app/allye-plugin/commit/31c46d51c093037e2939ebbcd9e4080d909b79e1))
* add sandbox skill (ask-don't-decide discipline, research dispatch, Discovery Doc) ([c003a2e](https://github.com/allye-app/allye-plugin/commit/c003a2e516fc519b9291c385d8a926335091042f))
* add technical-to-orchestration handover template ([fc57191](https://github.com/allye-app/allye-plugin/commit/fc5719194d2dc63f3616eb1b8c81f096c071e726))
* generalize allye-plan.ts handoff onto the shared marker format, target Orchestrator ([eef3d98](https://github.com/allye-app/allye-plugin/commit/eef3d98d7b500720df724b45d5383fbbbae911c0))
* register handover-protocol skill for backend seeding ([fe4a9e3](https://github.com/allye-app/allye-plugin/commit/fe4a9e3a1b0f9cd8f32ea243e61f7c49ff193e95))
* register orchestrator skill for backend seeding ([16b9832](https://github.com/allye-app/allye-plugin/commit/16b9832a4bf175d29721155fd79570f9034bbc8a))
* register sandbox skill for backend seeding ([14846c1](https://github.com/allye-app/allye-plugin/commit/14846c1a769a5a162f934a836eb966c3cdfb0a6a))
* route Orchestrator in using-allye's phase detection ([e55f6ec](https://github.com/allye-app/allye-plugin/commit/e55f6ec5d1b412e157880d3e5591098d56716a2f))
* route Sandbox in using-allye's phase detection ([123fae6](https://github.com/allye-app/allye-plugin/commit/123fae626192d5aa392aec8bfefd1d45b19aec69))
* route Sandbox/Orchestrator and handover detection in single-agent manifests ([908ae22](https://github.com/allye-app/allye-plugin/commit/908ae2206d79b5cac7a759878f45115fe0d14ef1))
* wire execution into handover catalog, scope to single story, strengthen ask-don't-assume and verification-before-completion ([e24d571](https://github.com/allye-app/allye-plugin/commit/e24d571df044bd21a70a719cf8439edb23c5907d))
* wire product-planning into handover catalog, add squares vocabulary and story-quality guidance ([95f4eea](https://github.com/allye-app/allye-plugin/commit/95f4eea0fca29366e5ad3e739877acd7e73c4056))
* wire technical-planning into handover catalog and orchestrator, add mandatory architecture gray area and task right-sizing ([fddc9ba](https://github.com/allye-app/allye-plugin/commit/fddc9ba0faa7ff63237c193e222ad68c8cf8312c))

## [1.0.3](https://github.com/allye-app/allye-plugin/compare/v1.0.2...v1.0.3) (2026-06-15)


### Bug Fixes

* update devshire URLs to allye.app domain ([6f5da20](https://github.com/allye-app/allye-plugin/commit/6f5da20096310db310633fd5248747e3b5eea71d))

## [1.0.2](https://github.com/allye-app/allye-plugin/compare/v1.0.1...v1.0.2) (2026-06-15)


### Bug Fixes

* correct MCP server host to mcp.allye.app ([f84891d](https://github.com/allye-app/allye-plugin/commit/f84891df39468a55466b19031b4895063a637b5a))

## [1.0.1](https://github.com/allye-app/allye-plugin/compare/v1.0.0...v1.0.1) (2026-06-15)


### Bug Fixes

* complete fenix→allye rebrand of agent files and bootstrap skill ([6e321d5](https://github.com/allye-app/allye-plugin/commit/6e321d5d26067c65dfc4dab5ab58f02d03340d12))

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
