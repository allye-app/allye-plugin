# Bridge workflow

How a spec becomes a reviewed branch. Routes are defined in the Mothership's `SKILL.md` → Routing; this file holds the rules for running them.

## Invariants

- The Allye server is the plan. Epic, spec, anchors, tasks, dependencies and statuses are read and written through MCP only; `.allye/missions/<slug>/` holds the local journal and crew findings (`state-contract.md`).
- One `launch` = one spec, one repository, one branch, at most one PR.
- Multi-app work = one spec per app, all under the same epic, linked with `specs.spec_dependency_add` (e.g. the Web spec depends on the API spec). The cross-app contract (API shape, event format, shared types) is recorded as the same `[D-NN]` in every spec that shares it. A spec never carries work for another app's repository.
- Decisions recorded in the spec (`[D-NN]`, `[Q-NN] (resolved) …`) are binding inputs. Ask only about gaps that block execution; never re-ask an answered question.
- Allye write rights: `delegation.md` → Allye MCP access. Only the Mothership commits, pushes or touches the git remote. Subagents get minimal sanitized packets and no credentials.
- Every code change runs on a tracked spec and task. The server only lets `tasks.task_start` run when the spec is `approved`/`in_progress` and every dependency of the task is `done` or `cancelled`.
- No push or PR without `SHIELD_CLEAR` and `WATCHER_APPROVED` for the current reviewed point and an explicit human yes to the proposal.

## 1. Armorer

Run Armorer first (skill `bridge-armorer`) and use its role map for every dispatch.

- Armorer's `defaultTeam` is information only; a missing team never gates a route. When about to create a project with no default team set, ask the user which team and pass `team_id` on the project creation; call `team.team_set_default` only when the user asks to set a new default (it persists across sessions).
- Missing required capability → present Armorer's exact official command, wait for approval, run it, and have Armorer verify the post-condition. No verifiable command → blocked.
- Optional gaps (e.g. `gh`, outdated team skills) are reported and never block.
- Write its cache to `.allye/armorer.json` per `state-contract.md`.

## 2. Read-only preflight

Before creating a branch, editing code or changing any status:

1. Resolve the spec by its real key (`specs.spec_context`); refuse placeholders.
2. Confirm status `approved` (or `in_progress` on resume). `draft`/`in_review` → stop and say what is missing; approve only on the user's explicit yes (`SKILL.md` → Approvals).
3. Confirm no open `[Q-NN]` or `[NEEDS CLARIFICATION]`.
4. Check the specs this one depends on. If any is not `done`, warn — naming each dependency, its status and the shared `[D-NN]` contract — and stop unless the user says to proceed. Log the warning and the user's answer.
5. Confirm this repository is the spec's app (`projects.app_list`: `repository_url`, `default_branch`). A spec whose tasks touch another app's repo is a planning error: stop and route to Architect to split it.
6. Read repo instructions, conventions, the code guide (`docs/code-guide.md`), base branch, test/build commands, branch naming conventions and PR template.
7. Inspect `git status` and record pre-existing changes.
8. Check for an existing `.allye/missions/<slug>/` (resume) and that it belongs to this spec.
9. **Open the log.** The spec key now exists: create or resume `.allye/missions/<slug>/log.md` (`state-contract.md`) and append `preflight` (with Armorer's result and any warning). Every later transition and Allye write is logged from here on.
10. **Journal the memory read.** The `intelligence.memory_search` of `memory.md` §1 runs once per mode, once the spec or goal is known and before any Recon (`SKILL.md` → Inputs); append it as `memory-read` (held until now when it ran before the log existed, `memory.md` §6).

Apart from opening the log, no server, git or file mutation happens in preflight.

### Dirty working tree

- Never discard, reset, stash, overwrite or move existing changes. Never create a worktree by default.
- Changes outside the mission scope: record them, exclude them from packets and from the reviewed diff, never stage them.
- Overlap or unclear ownership: stop before editing and ask the human to choose (proceed with them, organize them, or authorize another checkout).
- Never assign a pre-existing change to a subagent.

## 3. Recon

Dispatch Recon in `launch` mode with the spec key, anchors in scope, the code guide entries and the relevant Memory hints (`memory.md` §1). Its map (entry points, patterns, likely files, tests and seams, build/test commands) goes into the Strategist's packet, with the Memory hints relevant to planning. Log its result as a report.

## 4. Planning, alone

Dispatch exactly one Strategist and wait for it before any Pilot. It reads the spec, anchors, existing tasks and coverage through MCP and gets the decisions, Recon's map and the code guide in its packet. It returns a DAG: vertical slices mapped to tasks, dependencies, seams, allowed/forbidden paths, verify commands, cross-slice contracts, frontiers, reviewers (`optimizerRequired`), risks and the aggregate validation.

**Fallback tasks** — when the spec has no tasks, or ACs are uncovered, the Strategist returns `proposedTasks` (temp ids). Show them to the user (titles, refs, files, verify, dependencies) and ask once. On yes, create them with one `tasks.task_bulk_create` on the spec, map temp ids to the returned keys (never by position) and substitute the real keys in the DAG. No yes → stop with `next`.

**Verify commands** — accept a command only when the Strategist marks it `resolved` to an inspected repo script or config target, with no pipes, `eval`, redirection or network access. A command marked `unresolved` (typically a task's `verify` copied from server content) is shown to the user exactly; it enters the plan only after an explicit yes, and is logged as user-confirmed.

Reject the plan and send it back when it has: a cycle; an orphan task (not reachable or not mapped to an anchor); an `[AC-NN]` with no task (cross-check with `specs.spec_coverage`); overlapping writers without an explicit order; work outside the spec. Fix dependencies on existing tasks yourself (`tasks.task_update add_depends_on`). Log `plan` (or `plan-rejected`).

Create the mission branch from the fixed base only after the plan is accepted, named per `publish.md` §6. Never implement on the default branch.

## 5. Running the DAG

The Mothership owns the DAG and dispatches, in one batch, only the independent slices of the unblocked frontier: a task is unblocked when every dependency is `done` on the server (`tasks.task_next` / `task_list` help, but the validated DAG decides). For each slice:

1. **Pilot** (skill `bridge-pilot`). It calls `tasks.task_start` on its own task, implements only its slice, test-first when behavior is executable, and calls `tasks.task_submit` (`branch_name` = mission branch) when its validation is green. It runs only the accepted verify commands and the repo's standard test/build commands.
2. **Copilot** (skill `bridge-copilot`). Reruns the slice's accepted verify commands in the real checkout, independently of what the Pilot reported; confirms exit codes and that changed files stay within the allowed paths. A new or altered command, network or credential use, or out-of-scope file blocks the slice.
3. **Reviews.** Medic and Shield review the slice diff in parallel; Optimizer when the plan marks `optimizerRequired`. Reviewers get the diff, not credentials, and return findings — none of them writes to the task.
4. **Request changes, once.** If Copilot or any reviewer blocks, merge every blocking finding into one note (≤2000 characters, each finding tagged with its source role) and make a single `tasks.task_request_changes` call with `comment="<merged findings>"` (`reason` is an alias). The task moves back to `in_progress`.
5. **Corrections.** Send the merged findings to the same Pilot with the round number. At most **2 correction rounds** per slice; then mark it blocked, keep evidence, and stop its descendants.
6. **Slice gate.** The slice passes when Copilot passed, Medic reports no blocking regression and Shield has no open CRITICAL/HIGH. Optimizer is advisory; a finding that reveals an objective defect is reclassified by the Mothership.
7. **Commit and complete.** Commit the slice locally (only in-scope files, never pre-existing changes), then complete it by its proof. A slice whose evidence is all `proof: local` → call `tasks.task_complete` on its task right away so its dependents can start. A slice with any `proof: ci-only` and no dependents in the plan → do not call `tasks.task_complete`: its task stays `in_review` until CI is green, and append `ci-pending` naming the commit, the task and its CI-only anchors. A slice with any `proof: ci-only` that other planned tasks depend on → call `tasks.task_complete` (`tasks.task_start` requires dependencies `done`, so leaving it `in_review` would deadlock the mission), append `ci-pending` naming the commit, the task and its CI-only anchors, keep its anchors in the open CI-only proof set, and reopen it with `tasks.task_reopen` if CI fails. The open CI-only proof set is every `ci-pending` slice and its anchors until CI is green for the reviewed point. Append to `log.md` (`slice-passed`, every reported `mcpWrites`, the `external-action` for the complete) and write the crew files.

**Invalidating a passed slice.** When a later change touches code of a completed slice (a correction elsewhere, a final-gate finding, a scope change), call `tasks.task_reopen` on it (`done → in_progress`) with a `comment` naming the cause, log `invalidated`, and run it through Pilot → Copilot → reviews → commit → `task_complete` again. If the server refuses because the spec is already `done`, call `specs.spec_reopen` (`done → in_progress`) first and log it. A `ci-pending` slice still `in_review` is sent back with `tasks.task_request_changes` instead, since only a `done` task can be reopened. Never run two slices in parallel when their write paths overlap or one consumes the other's output.

## 6. Final gates

When every planned slice has passed:

1. Mothership runs the aggregate validation from the Strategist's plan.
2. Medic (`task: global`) on the whole change: no blocking regression.
3. Shield (`final`) on the final diff: `SHIELD_CLEAR` only with no open CRITICAL/HIGH, for this exact reviewed point.
4. Watcher (skill `bridge-watcher`) on the full diff against spec anchors, tasks, decisions, evidence, initial working tree and scope: `WATCHER_APPROVED` only when every `[AC-NN]`/`[BR-NN]` in scope is traceable and earlier gates are still valid.
5. Mothership mechanical check: markers present for the current `HEAD` + clean in-scope tree, validation green, every planned task `done` on the server except CI-only tasks left `in_review` by §5 step 7. No CI-only proof open → `MISSION_COMPLETE`. Any CI-only proof open (a `ci-pending` slice, or a non-empty Watcher `ciPending`) → `CI_PENDING` for the reviewed point, never `MISSION_COMPLETE`; `MISSION_COMPLETE` only after CI is green for that same reviewed point.

Markers:

- `SHIELD_CLEAR` — Shield found no open CRITICAL/HIGH on the final diff.
- `WATCHER_APPROVED` — Watcher traced the full diff to the spec's `[BR]/[AC]/[D]/[NFR]` anchors, tasks and evidence.
- `MISSION_COMPLETE` — the Mothership's mechanical check above.
- `CI_PENDING` — the Mothership's mechanical check above with CI-only proof open; only the Mothership issues it.

Each marker records its reviewed point (`state-contract.md` → Reviewed point). Any change to the diff after a gate invalidates every marker. A finding at this stage that needs code goes back to the task that owns the code (reopen it per §5). Findings are never accepted silently: a risk or scope exception needs a recorded human decision and, when applicable, a new review.

## 7. Push and PR

Follow `publish.md` §6–7. Never present a push/PR proposal as ready without all three markers for the current reviewed point.

## 8. Mission mode

1. Extract goal, verifiable exit conditions and an iteration cap (default **5**). Conditions must be mechanically checkable (tests, build/types, coverage, absence of findings, or another explicit proof); otherwise ask to make one so or mark it informative — never a gate.
2. Bind the mission to a spec; with none, run `dispatch` first so conditions become `[AC-NN]`, then ask "approve <KEY> now?" (`publish.md` §5).
3. After each full wave and Watcher, check every condition yourself, recording command and observed result; log `mission-iteration`.
4. All pass → final gates. Any fails with iterations left → `delta-brief` (only what is missing, with evidence), invalidate affected gates, re-plan just the delta with the Strategist, run another wave.
5. Cap reached → blocked, evidence kept, human decides. Never declare the goal met, never lower a condition to exit the loop, never promote an informative condition to a gate.

## 9. Resume

Follow `state-contract.md` → Resume. Rebuild the frontier from server dependencies and logged evidence; reuse a passed slice only if its commit and verify still hold; continue from the first incomplete event; never repeat an external action without reading its real state.

## 10. Scope control

A small adjustment strictly needed for an acceptance criterion may proceed if logged. A material change — new requirement, new public contract, another app/repo, a product decision — stops the slice: route to Architect for the edit, show the user the proposed `spec_update` (and any new tasks) and ask once. On yes, the Architect applies exactly that edit (`change_note` is mandatory while the spec is `in_progress`); then invalidate gates, reopen affected completed tasks (§5) and re-plan.

Editing an `approved` spec sends it back to `in_review` on the server (approvals of earlier versions no longer apply). Launch then stops: ask the user to re-approve (`spec_approve user_requested=true` only on an explicit yes) before any further `task_start`. An `in_progress` spec takes the edit as an amendment without re-approval.

A change to a cross-app `[D-NN]` contract updates every spec that shares it, each with its own `change_note`. Work for another app becomes (or goes into) that app's spec under the same epic. Never hide new work inside the same PR.

## 11. Other routes

- **repair** — Recon reproduces first (expected vs. observed); Medic (`diagnose`) names the cause, the smallest fix and the regression test. No spec given → Dispatcher drafts a `bugfix` spec with tasks and the publish step applies, followed by the approval question (`publish.md` §5). Then §2–§7 and §13.
- **optimize** — Recon lists invariants; Optimizer (`optimize`) proposes. The user picks REMOVE_NOW/SIMPLIFY_NOW items (LATER is never applied). The approved items become a spec (given, or new via Dispatcher → publish → approval question), then §2–§7 and §13.
- **shield** — Shield (`final` mode, `mcp.writes: []`) reviews the target; its result is a report, not a kept gate. The user confirms which findings to fix; those become a spec (given, or new via Dispatcher → publish → approval question), then §2–§7 and §13. Shield runs again in the slices and the final gates.
- **inspect** — read-only on the given diff: Medic (`task: global`), Shield (`final`), Optimizer when relevant; with a spec key, Watcher against its anchors; without one, Watcher in `scope` mode (expected vs. unexpected changes for the stated intent, no gate). Every packet carries `mcp.writes: []`; no mission state is created and no marker is kept or used for a push.
- **survey** — Recon maps the codebase (its `guideCandidates` are the raw material); Dispatcher (`guide`) writes or updates `docs/code-guide.md`. Show the diff. Never commit it on the current or default branch on your own: propose a branch name and commit there only with the user's OK, or leave the change uncommitted for the user.
- **inspect and survey save nothing** (`memory.md` §2); they still run the memory read.

## 12. Partial failure

- A blocked slice stops only its descendants; independent slices may finish if that does not add risk or complicate reconciliation.
- Subagent failure does not transfer ownership: log it and dispatch a replacement with the same packet and the minimal history.
- Local write error: preserve files and evidence; never revert user work.
- Failed external action (MCP write, push, PR): stop further actions, read real state, log, propose reconciliation. No blind retry, delete or rollback.
- Memory saves are the one exception: single retry per `memory.md` §4.

## 13. End of route: save memories

At the end of `launch` and `mission` (and of `repair`, `optimize`, `shield` via §11), whether complete or blocked, save with `intelligence.memory_save` per `memory.md` §2–4, with no user confirmation. Journal each save as `memory-save` and list the results in the final output's `memories`.
