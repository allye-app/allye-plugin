# Bridge workflow

## Invariants

- The Allye server is the plan. Epic, spec, anchors, tasks, dependencies and statuses are read and written through MCP only; `.allye/missions/<slug>/` holds the local journal and crew findings (see `state-contract.md`).
- One `launch` = one spec, one repository, one branch, at most one PR.
- Multi-app work = one spec per app, all under the same epic, linked with `specs.spec_dependency_add` (e.g. the Web spec depends on the API spec). The cross-app contract (API shape, event format, shared types) is recorded as the same `[D-NN]` in every spec that shares it. A spec never carries work for another app's repository.
- Decisions recorded in the spec (`[D-NN]`, `[Q-NN] (resolved) …`) are binding inputs. Ask only about gaps that block execution; never re-ask an answered question.
- Crew members read Allye and make only the writes their role allows (`delegation.md` → Allye MCP access), reporting each one; the Mothership logs them and keeps the reserved calls (`team_switch`, `spec_submit`, `spec_approve`, `task_complete`, cancels, reopens). Only the Mothership commits, pushes or touches the git remote. Subagents get minimal sanitized packets and no credentials.
- No push or PR without `SHIELD_CLEAR` and `WATCHER_APPROVED` for the current reviewed point and an explicit human yes to the proposal.

## 1. Preflight and routing

Run Armorer first (`skills/bridge-armorer/SKILL.md`). Armorer probes Allye (`initialize`, `allye_health_check`; `skills.skill_list` for the optional team-skills check) — or uses the Mothership's probes when it cannot see the MCP tools — and checks the active team, delegation (parallel or sequential fallback, see `delegation.md`), whether subagents see the Allye MCP tools, the question channel, the native agent type for each crew role, and the repo toolchain needed by the verify commands. Its result is cached in `.allye/armorer.json` (git-ignored, written by the Mothership) keyed by plugin version + harness id + harness version.

- No active team → ask which, `team.team_switch`, rerun the check.
- Missing required capability → present Armorer's exact official command, wait for approval, run it, and have Armorer verify the post-condition. No verifiable command → blocked.
- Optional gaps (e.g. `gh`, outdated team skills) are reported and never block.
- Log the result (`preflight`) and use its role map for every dispatch.

Then classify the mode:

| Mode | Route | Writes code? | Server writes |
|---|---|---|---|
| `launch` | Recon → Strategist → Pilot slices with Copilot, Medic, Shield (Optimizer optional) → Medic, Shield, Watcher on the whole → `MISSION_COMPLETE` | Yes | task transitions, missing tasks/deps |
| `mission` | `launch` in a loop judged by exit conditions | Yes | as `launch` |
| `blueprint` | Recon + Architect in background, Mothership interviews → Architect authors spec(s) + thin tasks → challenge round → publish (`publish.md`) | No | epic/spec/tasks create, deps, `spec_submit` |
| `blueprint --auto` | Recon + Architect decide autonomously, choices as `[D-NN] (proposed)` → challenge round → publish | No | as `blueprint` |
| `dispatch` | Recon + Dispatcher, ≤3 questions → minimal spec + thin tasks → publish (no challenge round) | No | spec/tasks create, `spec_submit` |
| `repair` | Recon reproduces first (expected vs. observed) → Medic (`diagnose`) finds cause → (change) Strategist → Pilot → Copilot → Shield → final gates | Yes | bugfix spec if none, task transitions |
| `optimize` | Recon → Optimizer (`optimize` mode) proposals → user picks REMOVE_NOW/SIMPLIFY_NOW items (LATER never applied) → Pilot → Copilot → Shield → Watcher | Yes | tasks for approved items |
| `shield` | Shield (`final` mode on the target) → user confirms findings → Pilot fixes → Copilot → Shield again | Yes, if approved | optional |
| `inspect` | Medic, Optimizer when relevant, Shield, Watcher on the target diff | No | none |
| `survey` | Recon maps the codebase (its `guideCandidates` are the raw material) → Dispatcher writes/updates `docs/code-guide.md` → Mothership commits it only with the user's OK | Code guide only | none |

Composed routes never skip preflight or gates. `repair`/`optimize`/`shield` changes that need tracking go through a spec: use the existing one when given, otherwise Dispatcher drafts a small one with its tasks (type `bugfix` for repair) and the normal publish step applies (`publish.md`).

## 2. Read-only preflight

Before creating a branch, editing code or changing any status:

1. Resolve the spec by its real key (`specs.spec_get` / `spec_context`); refuse placeholders.
2. Confirm status `approved` (or `in_progress` on resume). `draft`/`in_review` → stop and say what is missing; never approve on your own.
3. Confirm no open `[Q-NN]` or `[NEEDS CLARIFICATION]`.
4. Check the specs this one depends on (from `spec_context`/`spec_get`). If any is not `done`, warn — naming each dependency, its status and the shared `[D-NN]` contract — and stop unless the user says to proceed. Log the warning and the user's answer.
5. Confirm this repository is the spec's app (`projects.app_list`: `repository_url`, `default_branch`). A spec whose tasks touch another app's repo is a planning error: stop and route to Architect to split it.
6. Read repo instructions, conventions, the code guide (`docs/code-guide.md`), base branch, test/build commands and PR template.
7. Inspect `git status` and record pre-existing changes.
8. Check for an existing `.allye/missions/<slug>/` (resume) and that it belongs to this spec.

No server or git mutation happens in preflight.

### Dirty working tree

- Never discard, reset, stash, overwrite or move existing changes. Never create a worktree by default.
- Changes outside the mission scope: record them, exclude them from packets and from the reviewed diff, never stage them.
- Overlap or unclear ownership: stop before editing and ask the human to choose (proceed with them, organize them, or authorize another checkout).
- Never assign a pre-existing change to a subagent.

## 3. Planning, alone

Dispatch exactly one Strategist (`skills/bridge-strategist/SKILL.md`) and wait for it before any Pilot. It reads the spec, anchors, existing tasks (refs/files/verify) and coverage through MCP, and gets the decisions, Recon's map and the code guide in its packet. It returns a DAG: vertical slices mapped to tasks, dependencies by task key, seams, allowed/forbidden paths, verify commands derived from the repo's scripts, cross-slice contracts, frontiers, reviewers (`optimizerRequired`), risks and the aggregate validation. A spec that arrives with no tasks (created outside Bridge) is the only case where the Strategist creates tasks itself (`tasks.task_bulk_create`, thin, real keys back in the DAG).

Reject the plan and send it back when it has: a cycle; an orphan task (not reachable or not mapped to an anchor); an `[AC-NN]` with no task (cross-check with `specs.spec_coverage`); overlapping writers without an explicit order; work outside the spec. Then reconcile with the server: re-read `specs.spec_coverage`, fix dependencies on existing tasks with `task_update add_depends_on` yourself. Log `plan` and every write the Strategist reported.

Create the mission branch from the fixed base only after the plan is accepted.

## 4. Running the DAG

The Mothership owns the DAG and dispatches, in one batch, only the independent slices of the unblocked frontier (`tasks.task_next` / `task_list blocked=false` help, but the validated DAG decides). For each slice:

1. **Pilot** (`skills/bridge-pilot/SKILL.md`). It calls `tasks.task_start` on its own task, implements only its slice, red → green through the public seam when behavior is executable (mechanical changes use the real validation instead of artificial tests), and calls `tasks.task_submit` with the branch name when its validation is green. It may only run the verify commands in its packet and the repo's standard test/build commands.
2. **Copilot** (`skills/bridge-copilot/SKILL.md`). Reruns the slice's declared verify commands in the real checkout, independently of what the Pilot reported; confirms exit codes and that changed files stay within the allowed paths. A new or altered command, network or credential use, or out-of-scope file blocks the slice and returns to the Mothership.
3. **Reviews.** Medic (regressions, edge cases, tests) and Shield (security, correctness of trust boundaries) review the slice diff; Optimizer when the plan marks `optimizerRequired`. Reviewers get the diff, not credentials. Any blocking checker or reviewer calls `tasks.task_request_changes` on the slice with its findings.
4. **Corrections.** Any block → concrete findings back to the same Pilot with the round number. At most **2 correction rounds** per slice; then mark it blocked, keep evidence, and stop its descendants.
5. **Slice gate.** Advance descendants only when Copilot passed, Medic reports no blocking regression and Shield has no open CRITICAL/HIGH. Optimizer is advisory; a finding that reveals an objective defect is reclassified by the Mothership.
6. **Record.** Commit the slice locally (only in-scope files, never pre-existing changes), append to `log.md` (including every reported `mcpWrites`), write the crew files.

Changing code of an already-passed slice invalidates its checks: the Mothership calls `tasks.task_request_changes`, then the slice goes through its gate again. Never run two slices in parallel when their write paths overlap or one consumes the other's output.

## 5. Final review and gates

When every planned slice has passed:

1. Mothership runs the aggregate validation from the Strategist's plan.
2. Medic (`task: global`) on the whole change: no blocking regression.
3. Shield (`final` mode) on the final diff: `SHIELD_CLEAR` only with no open CRITICAL/HIGH, for this exact reviewed point.
4. Watcher (`skills/bridge-watcher/SKILL.md`) on the full diff against spec anchors, tasks, decisions, evidence, initial working tree and scope: `WATCHER_APPROVED` only when every `[AC-NN]`/`[BR-NN]` in scope is traceable and earlier gates are still valid.
5. Mothership mechanical check: markers present for the current `HEAD` + clean in-scope tree, validation green, projection matches server → `MISSION_COMPLETE`, then `tasks.task_complete` for each passed task.

Any later change to the diff invalidates all three markers. Findings are never accepted silently: a risk or scope exception needs a recorded human decision and, when applicable, a new review.

## 6. Push and PR

Present one exact proposal: branch, remote, commits, PR title/base/body/draft-or-ready, validation results, gates with their commit, resolved findings, residual risks, and what is explicitly not included (merge, deploy, reviewers). A yes authorizes only that list, in that order. After the PR exists, record it on the tasks (`tasks.task_update pr_url`). Refuse the PR if a gate does not match the current reviewed point.

Never deploy. Merge into any branch only when the person commanding the chat explicitly asks.

## 7. Mission mode

1. Extract goal, verifiable exit conditions and iteration cap (default 5). If a condition is not mechanically checkable, ask to make it so or mark it informative (never a gate).
2. Bind the mission to a spec; with none, run `dispatch` first so conditions become `[AC-NN]`.
3. After each full wave and Watcher, check every condition yourself and log `mission-iteration`.
4. Fail with iterations left → `delta-brief` (only what is missing, with evidence), invalidate affected gates, re-plan just the delta with the Strategist, run another wave.
5. Cap reached → blocked, evidence kept, human decides. Never lower a condition to exit.

## 8. Resume

Follow `state-contract.md` → Resume. Rebuild the frontier from server dependencies and logged evidence; reuse a passed slice only if its commit and verify still hold; continue from the first incomplete event; never repeat an external action without reading its real state.

## 9. Partial failure

- A blocked slice stops only its descendants; independent slices may finish if that does not add risk or complicate reconciliation.
- Subagent failure does not transfer ownership: log it and dispatch a replacement with the same packet and the minimal history.
- Local write error: preserve files and evidence; never revert user work.
- Failed external action (MCP write, push, PR): stop further actions, read real state, log, propose reconciliation. No blind retry, delete or rollback.

## 10. Scope control

A small adjustment strictly needed for an acceptance criterion may proceed if logged. A material change — new requirement, new public contract, another app/repo, a product decision — stops the slice: route to Architect, then update the spec (`specs.spec_update` with a `change_note`, mandatory while `in_progress`), invalidate gates, and re-plan. A change to a cross-app `[D-NN]` contract updates every spec that shares it, each with its own `change_note`. Work for another app becomes (or goes into) that app's spec under the same epic. Never hide new work inside the same PR.
