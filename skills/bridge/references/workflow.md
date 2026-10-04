# Bridge workflow

## Invariants

- The Allye server is the plan. Epic, spec, anchors, tasks, dependencies and statuses are read and written through MCP only; `.allye/missions/<slug>/` holds the local journal and crew findings (see `state-contract.md`).
- One `launch` = one spec, one repository, one branch, at most one PR.
- Multi-app work = one spec per app, all under the same epic, linked with `specs.spec_dependency_add` (e.g. the Web spec depends on the API spec). The cross-app contract (API shape, event format, shared types) is recorded as the same `[D-NN]` in every spec that shares it. A spec never carries work for another app's repository.
- Decisions recorded in the spec (`[D-NN]`, `[Q-NN] … (resolved)`) are binding inputs. Ask only about gaps that block execution; never re-ask an answered question.
- The Mothership is the only process that calls Allye MCP tools, commits, pushes or touches the git remote. Subagents get minimal sanitized packets, no credentials, no external writes.
- No push or PR without `SHIELD_CLEAR` and `WATCHER_APPROVED` for the current reviewed point and an explicit human yes to the proposal.

## 1. Preflight and routing

Run Armorer first (`skills/bridge-armorer/SKILL.md`). The Mothership probes Allye (`initialize`, `allye_health_check`; `skills.skill_list` for the optional team-skills check) and passes the observed results; Armorer checks the active team, delegation (parallel or sequential fallback, see `delegation.md`), the question channel, the native agent type for each crew role, and the repo toolchain needed by the verify commands. Its result is cached in `.allye/armorer.json` (git-ignored, written by the Mothership) keyed by plugin version + harness id + harness version.

- No active team → ask which, `team.team_switch`, rerun the check.
- Missing required capability → present Armorer's exact official command, wait for approval, run it, and have Armorer verify the post-condition. No verifiable command → blocked.
- Optional gaps (e.g. `gh`, outdated team skills) are reported and never block.
- Log the result (`preflight`) and use its role map for every dispatch.

Then classify the mode:

| Mode | Route | Writes code? | Server writes |
|---|---|---|---|
| `launch` | Recon → Strategist → Pilot slices with Copilot, Medic, Shield (Optimizer optional) → Medic, Shield, Watcher on the whole → `MISSION_COMPLETE` | Yes | task transitions, missing tasks/deps |
| `mission` | `launch` in a loop judged by exit conditions | Yes | as `launch` |
| `blueprint` | Recon + Architect in background, Mothership interviews → confirmation → Strategist plans tasks | No | epic/spec/tasks create, `spec_submit` |
| `blueprint --auto` | Recon + Architect decide autonomously, choices as `[D-NN]` → confirmation → Strategist plans tasks | No | as `blueprint` |
| `dispatch` | Recon + Dispatcher, ≤3 questions → confirmation; code guide refreshed | Code guide only | spec/tasks create |
| `repair` | Recon reproduces → Medic finds cause → (change) Strategist → Pilot → Copilot → Shield → final gates | Yes | bugfix spec if none, task transitions |
| `optimize` | Recon → Optimizer proposals → user picks → Pilot → Copilot → Shield → Watcher | Yes | tasks for approved items |
| `shield` | Shield → user confirms findings → Pilot fixes → Copilot → Shield again | Yes, if approved | optional |
| `inspect` | Medic, Optimizer when relevant, Shield, Watcher on the target diff | No | none |
| `survey` | Recon → Dispatcher writes/updates the code guide | Code guide only | none |

Composed routes never skip preflight or gates. `repair`/`optimize`/`shield` changes that need tracking go through a spec: use the existing one when given, otherwise Dispatcher drafts a small one (type `bugfix` for repair) and the normal confirmation applies.

## 2. Read-only preflight

Before creating a branch, editing code or changing any status:

1. Resolve the spec by its real key (`specs.spec_get` / `spec_context`); refuse placeholders.
2. Confirm status `approved` (or `in_progress` on resume). `draft`/`in_review` → stop and say what is missing; never approve on your own.
3. Confirm no open `[Q-NN]` or `[NEEDS CLARIFICATION]`.
4. Check the specs this one depends on (from `spec_context`/`spec_get`). If any is not `done`, warn — naming each dependency, its status and the shared `[D-NN]` contract — and stop unless the user says to proceed. Log the warning and the user's answer.
5. Confirm this repository is the spec's app (`projects.app_list`: `repository_url`, `default_branch`). A spec whose tasks touch another app's repo is a planning error: stop and route to Architect to split it.
6. Read repo instructions, conventions, the code guide, base branch, test/build commands and PR template.
7. Inspect `git status` and record pre-existing changes.
8. Check for an existing `.allye/missions/<slug>/` (resume) and that it belongs to this spec.

No server or git mutation happens in preflight.

### Dirty working tree

- Never discard, reset, stash, overwrite or move existing changes. Never create a worktree by default.
- Changes outside the mission scope: record them, exclude them from packets and from the reviewed diff, never stage them.
- Overlap or unclear ownership: stop before editing and ask the human to choose (proceed with them, organize them, or authorize another checkout).
- Never assign a pre-existing change to a subagent.

## 3. Planning, alone

Dispatch exactly one Strategist and wait for it before any Pilot. It receives the spec content and anchors, existing tasks with refs/files/verify, the decisions, Recon's map and the code guide. It returns a brief and a DAG: vertical slices mapped to tasks, dependencies by task key (or temp id for new tasks), expected files, the verify command per slice, risks, reviewers needed, and the initial frontier.

Reject the plan and send it back when it has: a cycle; an orphan task (not reachable or not mapped to an anchor); an `[AC-NN]` with no task (cross-check with `specs.spec_coverage`); overlapping writers without an explicit order; work outside the spec. Then reconcile with the server: create missing tasks with `tasks.task_bulk_create` (thin: refs, files, verify, notes ≤2000 chars), fix dependencies with `task_update add_depends_on`. Log `plan`.

Create the mission branch from the fixed base only after the plan is accepted.

## 4. Running the DAG

The Mothership owns the DAG and dispatches, in one batch, only the independent slices of the unblocked frontier (`tasks.task_next` / `task_list blocked=false` help, but the validated DAG decides). For each slice:

1. **Pilot.** `tasks.task_start`, then dispatch. The Pilot implements only its slice, red → green through the public interface when behavior is executable; mechanical changes use the real validation instead of artificial tests. It may only run the verify commands in its packet and the repo's standard test/build commands.
2. **Copilot.** Reruns the slice's declared verify commands in the real checkout, independently of what the Pilot reported; confirms exit codes and that changed files stay within the allowed paths. A new or altered command, network or credential use, or out-of-scope file blocks the slice and returns to the Mothership.
3. **Reviews.** Medic (regressions, edge cases, tests) and Shield (security, correctness of trust boundaries) review the slice diff; Optimizer when the plan asks for it. Reviewers get the diff, not credentials.
4. **Corrections.** Any block → concrete findings back to the same Pilot with the round number. At most **2 correction rounds** per slice; then mark it blocked, keep evidence, and stop its descendants.
5. **Slice gate.** Advance descendants only when Copilot passed, Medic reports no blocking regression and Shield has no open CRITICAL/HIGH. Optimizer is advisory; a finding that reveals an objective defect is reclassified by the Mothership.
6. **Record.** Commit the slice locally (only in-scope files, never pre-existing changes), `tasks.task_submit` with `branch_name`, append to `log.md`, write the crew files.

Changing code of an already-passed slice invalidates its checks: `tasks.task_request_changes`, rerun its gate. Never run two slices in parallel when their write paths overlap or one consumes the other's output.

## 5. Final review and gates

When every planned slice has passed:

1. Mothership runs the aggregate validation from the Strategist's plan.
2. Medic on the whole change: no blocking regression.
3. Shield on the final diff: `SHIELD_CLEAR` only with no open CRITICAL/HIGH, for this exact reviewed point.
4. Watcher on the full diff against spec anchors, tasks, decisions, evidence, initial working tree and scope: `WATCHER_APPROVED` only when every `[AC-NN]`/`[BR-NN]` in scope is traceable and earlier gates are still valid.
5. Mothership mechanical check: markers present for the current `HEAD` + clean in-scope tree, validation green, projection matches server → `MISSION_COMPLETE`, then `tasks.task_complete` for each passed task.

Any later change to the diff invalidates all three markers. Findings are never accepted silently: a risk or scope exception needs a recorded human decision and, when applicable, a new review.

## 6. Push and PR

Present one exact proposal: branch, remote, commits, PR title/base/body/draft-or-ready, validation results, gates with their commit, resolved findings, residual risks, and what is explicitly not included (merge, deploy, reviewers). A yes authorizes only that list, in that order. After the PR exists, record it on the tasks (`tasks.task_update pr_url`). Refuse the PR if a gate does not match the current reviewed point.

Never deploy. Merge to `develop`/`main` only when the person commanding the chat explicitly asks.

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
