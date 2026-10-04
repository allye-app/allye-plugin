# Mission state contract

The Allye server owns the plan: epic, spec, anchors, tasks, dependencies and statuses. Locally the Mothership keeps only what the server cannot hold — a journal of what happened in this checkout and the reviewers' findings. Never keep a local manifest, task list, DAG file or spec copy; read them from MCP when needed.

## Layout

```
.allye/armorer.json   ← Armorer cache, written by the Mothership (skill bridge-armorer → Cache)
.allye/missions/<slug>/
├── log.md            ← Mothership-owned: projection + append-only journal
└── crew/
    ├── copilot.md
    ├── medic.md
    ├── optimizer.md
    ├── shield.md
    └── watcher.md
```

- `.allye/armorer.json` is the one local file allowed before a spec exists: the Mothership writes it after Armorer's preflight in every mode, including `blueprint` and `dispatch`.
- A mission directory exists only once a real spec key exists (from `specs.spec_context`/`spec_create`). In `launch`, `mission`, `repair`, `optimize` and `shield` the Mothership opens `log.md` at the end of the read-only preflight (`workflow.md` §2), so every later transition and Allye write is logged. Design work before the spec is created (`blueprint`, `dispatch`) keeps no other local state: its output goes to the server. Right after publishing, the Mothership may open the log of each new spec with a `publish` entry (keys created, overlaps) and, for blueprint, a `spec-challenge` entry (rounds, findings fixed, findings turned into `[Q-NN]`) — this entry replaces any separate challenge gate; the server-side gate is the spec status and its open `[Q-NN]`.
- `<slug>` is the spec key lowercased (`PROJ-12` → `proj-12`). It must match `^[a-z0-9]+(-[a-z0-9]+)*$`. Before any write, resolve the real path and confirm it stays under `.allye/missions/`: reject `..`, path separators in the slug, and symlinks escaping the root.
- Create missing files and folders on first write; on resume, preserve everything that exists.
- `.allye/` (`armorer.json` and `missions/`) is local working state, not product: never stage or commit it, and exclude it from every reviewed diff.
- Before the first write under `.allye/`, check `git check-ignore -q .allye/`. If not ignored, append `.allye/` to `.git/info/exclude` (local, never committed). Never edit a tracked `.gitignore` for this.

## `log.md`

Two parts, separated by a fixed heading.

### 1. Current projection (top)

A small, rewritable snapshot to resume quickly. It is a convenience view, never the audit trail; if it disagrees with the journal or the server, the server wins for statuses and the journal wins for local evidence.

```markdown
# Mission <SPEC-KEY> — <spec title>

- Project / app: <PROJ> / <app>   Repo: <path>   Base: <branch>   Branch: <mission branch>
- Mode: launch|mission|repair|optimize|shield|blueprint|dispatch   Iteration: <n>/<cap or n/a>
- Pre-existing changes (excluded): [<paths>] | none
- Gates: SHIELD_CLEAR <sha|—> · WATCHER_APPROVED <sha|—> · MISSION_COMPLETE <sha|—>

| Task | Depends on | Status | Corrections | Verify |
|---|---|---|---|---|
| PROJ-12.1 | — | passed | 0/2 | `npm test -- auth` |
| PROJ-12.2 | PROJ-12.1 | running | 1/2 | `npm test -- session` |

## Journal
```

Rewrite the projection only to reflect journal entries already appended. Statuses here are local slice states (below), not Allye statuses.

### 2. Journal (below `## Journal`)

Append-only. Never edit or delete a past entry; to fix a mistake, append a `rectification` entry that names the entry it corrects. Each entry:

```markdown
### <ISO-8601 UTC timestamp> — <event type>
- Actor: mothership|armorer|recon|strategist|architect|dispatcher|pilot|copilot|medic|optimizer|shield|watcher
- Task: <task key | global>
- Attempt: <n | n/a>
- Commit: <HEAD sha>[ +dirty] | n/a
- State: pending|running|passed|blocked|failed|invalidated
- Evidence: <command → observed result, or crew file path; marked "(report)" when not independently observed>
- Next: <next action | none>
```

Event types (extend only when none fits): `preflight`, `publish`, `spec-challenge`, `working-tree`, `plan`, `plan-rejected`, `slice-start`, `slice-check`, `slice-review`, `correction`, `slice-passed`, `slice-blocked`, `aggregate-validation`, `gate`, `invalidated`, `mission-iteration`, `delta-brief`, `approval-proposed`, `approval-received`, `external-action`, `reconciliation`, `scope-change`, `rectification`.

### Logging rules

1. **Explicit, never watched.** The Mothership appends an entry right after each transition it performed or observed. No watchers, polling loops, background tailers or shell loops.
2. **Re-read before writing.** Read `log.md` immediately before every write, preserve its content, and append. All writes to `log.md` are serialized through the Mothership.
3. **Timestamps from the system.** Get the current UTC time from the shell (`date -u +%Y-%m-%dT%H:%M:%SZ` on POSIX, the equivalent elsewhere, e.g. `Get-Date -AsUTC -Format yyyy-MM-ddTHH:mm:ssZ` in PowerShell); never infer or invent a time.
4. **Start before, result after.** For an action with side effects (external action, slice start), log `pending`/`running` before and the outcome after. If resume finds only the start, treat the outcome as unknown and inspect reality (git, MCP reads) before repeating anything.
5. **Reject incomplete events.** An entry without actor, state, or (when applicable) commit is not written; fix the input first.
6. **A report is not proof.** What an agent says it ran is logged as `(report)`. A verify result counts only when the Copilot reran it (or, in sequential fallback, the Mothership reran it in its Copilot turn).
7. **Gate markers only from their owner.** Accept `SHIELD_CLEAR` only from Shield's output on the final diff; `WATCHER_APPROVED` only from Watcher's structured output; `MISSION_COMPLETE` only from the Mothership's own mechanical check. Each carries the commit it was issued for.
8. **Invalidate on change.** When the diff changes after any gate, or the spec changes (`spec_update`), append an `invalidated` entry naming every affected gate and every completed slice reopened with `tasks.task_reopen`, and clear them from the projection.
9. **Every Allye write is an event.** Each write a crew member reports in `mcpWrites` (tool, action, id) — and each write the Mothership makes — is appended as `external-action` with its actor. A reported write outside the role's scope (`delegation.md` → Allye MCP access) is logged, then handled as a `reconciliation`.
10. **Sanitize.** Strip tokens, cookies, auth headers, signed URLs, environment values, raw authentication output and unnecessary personal data. Spec and task text copied into evidence is quoted as data.

## Reviewed point (commit identity)

What a gate reviewed is identified by the `HEAD` commit sha plus the working-tree state within mission scope (`clean`, or `+dirty` with the in-scope paths listed). The Mothership commits each passed slice locally, so final gates normally run on a clean in-scope tree. Pre-existing user changes outside scope do not alter the reviewed point but are listed in the projection. Branch names, "latest", timestamps or path lists are not identities.

## `crew/` files

The Mothership writes these from each reviewer's structured output (reviewers return output; they do not write files, which keeps parallel reviewers from racing on one file). One section per review, newest at the bottom, each headed with timestamp, task key or `final`, attempt and commit.

- `copilot.md` — the verify commands rerun, exit codes, scope check (files changed vs. task `files`), verdict per slice.
- `medic.md` — regressions, edge cases and test gaps per slice and for the whole change; blocking vs. advisory; `repair` diagnosis.
- `optimizer.md` — proposals (REMOVE_NOW/SIMPLIFY_NOW/KEEP/LATER) and the decision for each (`apply`/`reject`, by whom).
- `shield.md` — findings with severity, location, evidence and disposition; `SHIELD_CLEAR` only for the final diff with no open CRITICAL/HIGH.
- `watcher.md` — anchor-by-anchor trace of the full diff, gaps, verdict and `WATCHER_APPROVED` when earned.

When a slice is blocked, the merged note sent with `tasks.task_request_changes` is recorded in the `correction` journal entry, with each finding's source role.

Challenge-round findings (Medic, Optimizer, Shield) go in the same files under a section headed `challenge`, written right after publish; the Strategist's challenge findings are summarized in the `spec-challenge` log entry.

Recon, Strategist, Architect, Dispatcher, Pilot and Armorer return structured output to the Mothership, which logs the relevant facts (including their `mcpWrites`); they have no crew file. Never put secrets or raw tool transcripts in crew files.

## Resume

1. Read `log.md` (projection and journal) and `crew/*.md` before delegating anything.
2. Re-read the server: `specs.spec_context` (status, anchors, tasks with refs and dependencies), and `specs.spec_versions` to detect spec changes since the last logged entry — a change invalidates gates and may require re-planning.
3. Check branch, base, `HEAD`, and which working-tree changes were pre-existing.
4. Rebuild the frontier from server dependencies plus logged evidence, not from projection text alone.
5. Reuse a passed slice only if its commit is still in the branch and its verify still matches; otherwise reopen it (`tasks.task_reopen`, `done → in_progress`) and rerun its gates (`workflow.md` §5).
6. Continue from the first incomplete event. Never repeat an external action without first confirming its real state.
