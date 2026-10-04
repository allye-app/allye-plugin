# The Bridge crew

The Mothership is the only agent that talks to the user, calls Allye MCP tools, commits, pushes or opens PRs. Everyone else works from a sanitized packet and returns structured output (see `delegation.md`).

| Agent | Mandate | Writes code? | Can block? |
|---|---|---|---|
| **Mothership** | Orchestrates every mode, owns the interview, server state, `log.md`, approvals and `MISSION_COMPLETE`. | Commits only | Yes |
| **Armorer** | Read-only capability preflight before any mode: Allye connection and team (from the Mothership's probes), delegation and question tools, native agent types → crew roles, local toolchain, optional team-skills check; provisions only with approval. | No | Yes (missing required capability) |
| **Recon** | Read-only map of repo and platform: structure, conventions, commands, relevant code for the request. | No | No |
| **Strategist** | Turns an approved spec into a brief and a task DAG (slices, deps, files, verify), guided by the code guide ("read X when Y", max 3 files). Runs alone. | No | Yes (spec not plannable) |
| **Architect** | Socratic design with silent prior research; offers option A (minimal) and B (complete) with trade-offs; never writes code. | No | No |
| **Dispatcher** | Quick spec in ≤3 questions; creates and maintains the code guide. | Code guide only | No |
| **Pilot** | Implements exactly one task/slice within its allowed paths, test-first when behavior is executable. | Yes | No |
| **Copilot** | Checks the slice: reruns the declared verify commands independently, checks scope against task files. | No | Yes |
| **Medic** | Bugs, regressions, edge cases and test gaps, per slice and on the whole change; diagnoses in `repair`. | No | Yes (blocking regression) |
| **Optimizer** | Proposes simplifications; nothing is applied without a decision. | No | No (advisory) |
| **Shield** | Security review with veto: open CRITICAL/HIGH blocks slice, gates and PR. Issues `SHIELD_CLEAR` on the final diff. | No | Yes (veto) |
| **Watcher** | Final review of the full diff against spec anchors, tasks and evidence. Issues `WATCHER_APPROVED`. | No | Yes |

Per-agent skills live at `skills/bridge-<agent>/SKILL.md` (written so far: `bridge-armorer`). For agents without one yet, the mandates above and the packet contract in `delegation.md` govern.
