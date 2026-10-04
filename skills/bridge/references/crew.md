# The Bridge crew

The Mothership is the only agent that talks to the user, commits, pushes, opens PRs, asks for approval or makes the reserved Allye calls (`team_switch`, `spec_submit`, `spec_approve`, `task_complete`, cancels, reopens). Every other agent works from a sanitized packet, uses the Allye MCP only as its role allows, and returns structured output (see `delegation.md`).

| Agent | Skill | Mandate | Writes code? | Allye writes | Can block? |
|---|---|---|---|---|---|
| **Mothership** | `skills/bridge/SKILL.md` | Orchestrates every mode; owns the interview, the closing confirmation, `log.md`, crew files, approvals and `MISSION_COMPLETE`. | Commits only | Reserved calls + anything outside a role | Yes |
| **Armorer** | `skills/bridge-armorer/SKILL.md` | Read-only capability preflight: Allye connection and team, delegation, whether subagents see the MCP tools, question tool, native agent types → roles, local toolchain; provisions only with approval. | No | None | Yes (missing required capability) |
| **Recon** | `skills/bridge-recon/SKILL.md` | Read-only investigation with evidence: execution paths, invariants, tests/seams; reproduces bugs first; answers factual interview questions; feeds the code guide in `survey`. | No | None | No |
| **Strategist** | `skills/bridge-strategist/SKILL.md` | `plan`: validated slice DAG (AC trace, topo order, seams, verify from repo scripts, paths, contracts, frontiers, reviewers). `challenge`: ambiguities in a draft spec. Runs alone. | No | `task_bulk_create` only for a spec reaching launch without tasks | Yes (spec not plannable) |
| **Architect** | `skills/bridge-architect/SKILL.md` | Authors the full spec (Functional + Technical, anchors, `[D-NN]` origins) and thin tasks from resolved decisions; silent research; runs the challenge round through the Mothership. | No | Epic/specs/tasks/spec deps it authored, after the closing confirmation | No |
| **Dispatcher** | `skills/bridge-dispatcher/SKILL.md` | Minimal single-app spec + thin tasks in ≤3 questions; maintains `docs/code-guide.md` in `survey`. | Code guide only | Spec/tasks it authored, after the closing confirmation | No |
| **Pilot** | `skills/bridge-pilot/SKILL.md` | Implements exactly one slice within its allowed paths, test-first when behavior is executable. | Yes | `task_start`, `task_update` (notes), `task_submit` on its own task | No |
| **Copilot** | `skills/bridge-copilot/SKILL.md` | Reruns the slice's declared verify commands independently; checks touched paths and commands against the slice scope. | No | `task_request_changes` on the slice | Yes |
| **Medic** | `skills/bridge-medic/SKILL.md` | Tests and regressions per slice and on the whole change; edge-case `challenge` on draft specs; `diagnose` in `repair`. | No | `task_request_changes` on the slice | Yes (blocking regression) |
| **Optimizer** | `skills/bridge-optimizer/SKILL.md` | REMOVE_NOW / SIMPLIFY_NOW / KEEP / LATER proposals in `challenge`, `slice` and `optimize`; only user-approved items are applied. | No | None | No (advisory) |
| **Shield** | `skills/bridge-shield/SKILL.md` | Security veto in `slice`, `final` and `challenge`: open CRITICAL/HIGH blocks slice, gates and PR. Issues `SHIELD_CLEAR` on the final diff. | No | `task_request_changes` on the slice | Yes (veto) |
| **Watcher** | `skills/bridge-watcher/SKILL.md` | Final review of the full diff against anchors, tasks, decisions, evidence and scope. Issues `WATCHER_APPROVED`. | No | None | Yes |

All Allye writes are reported in `mcpWrites` and logged by the Mothership. When subagents cannot see the MCP tools, the Mothership makes those calls on their behalf.
