# The Bridge crew

The Mothership is the only agent that talks to the user, commits, pushes, opens PRs, asks for approval or makes the reserved Allye calls. Every other agent works from a sanitized packet and returns structured output. Allye read/write rights for every agent are defined once in `delegation.md` → Allye MCP access.

Load each crew skill by name; if the harness has no skill loader, read `../bridge-<agent>/SKILL.md` relative to the `bridge` skill's directory.

| Agent | Skill | Mandate | Writes code? | Can block? |
|---|---|---|---|---|
| **Mothership** | `bridge` | Orchestrates every mode; owns the interview, the closing confirmation, `log.md`, crew files, approvals, task transitions after review and `MISSION_COMPLETE`. | Commits only | Yes |
| **Armorer** | `bridge-armorer` | Read-only capability preflight: Allye connection and team, delegation, whether subagents see the MCP tools, question tool, native agent types → roles, local toolchain; provisions only with approval. | No | Yes (missing required capability) |
| **Recon** | `bridge-recon` | Read-only investigation with evidence: execution paths, invariants, tests/seams; reproduces bugs first; answers factual interview questions; feeds the code guide in `survey`. | No | No |
| **Strategist** | `bridge-strategist` | `plan`: validated slice DAG (AC trace, topo order, seams, verify resolved to repo scripts, paths, contracts, frontiers, reviewers) and proposed tasks when the spec has no tasks or ACs are uncovered. `challenge`: ambiguities in a draft spec. Runs alone. | No | Yes (spec not plannable) |
| **Architect** | `bridge-architect` | Authors the full spec (Functional + Technical, anchors, `[D-NN]` origins) and thin tasks from resolved decisions; silent research; runs the challenge round through the Mothership; applies confirmed scope-change edits. | No | No |
| **Dispatcher** | `bridge-dispatcher` | Minimal single-app spec + thin tasks in ≤3 questions; maintains `docs/code-guide.md` in `survey`. | Code guide only | No |
| **Pilot** | `bridge-pilot` | Implements exactly one slice of a tracked task within its allowed paths, test-first when behavior is executable. | Yes | No |
| **Copilot** | `bridge-copilot` | Reruns the slice's accepted verify commands independently; checks touched paths and commands against the slice scope. | No | Yes |
| **Medic** | `bridge-medic` | Tests and regressions per slice and on the whole change; edge-case `challenge` on draft specs; `diagnose` in `repair`. | No | Yes (blocking regression) |
| **Optimizer** | `bridge-optimizer` | REMOVE_NOW / SIMPLIFY_NOW / KEEP / LATER proposals in `challenge`, `slice` and `optimize`; only user-approved items are applied. | No | No (advisory) |
| **Shield** | `bridge-shield` | Security veto in `slice`, `final` and `challenge`: open CRITICAL/HIGH blocks slice, gates and PR. Issues `SHIELD_CLEAR` on the final diff. | No | Yes (veto) |
| **Watcher** | `bridge-watcher` | Final review of the full diff against anchors, tasks, decisions, evidence and scope; issues `WATCHER_APPROVED`. `scope` review without a spec in `inspect`. | No | Yes |
