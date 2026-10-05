# Spec anchor lint

The single checklist every spec and its tasks must pass before they leave the author and again right before the first Allye write. The Architect (`author`, `auto` and `publish` modes) and the Dispatcher (`spec` and `publish` modes) run it in their self-check; `publish.md` §4 requires it to pass for **all** specs of the confirmed list before anything is created. The checklist itself is offline: it reads only the drafted content; the server check below runs alongside it at the gate.

An **anchor definition** is a list item or heading whose text starts with `[KIND-NN]` (e.g. `- [D-01] …`, `### [AC-02] …`). Any other occurrence is an **inline reference** (e.g. "see [D-01]", "covers [AC-02]") and is always allowed. The server rejects a spec that defines the same id twice (`specs.spec_create` → `SPEC_DUPLICATE_ANCHOR`, "each anchor must appear once").

## Checklist

Run every item per spec; report each failure with the spec, the anchor or task and the line.

1. **Unique definitions** — each anchor id is defined exactly once in the spec. A shared contract `[D-NN]` defined under Contracts is never defined again under Decisions; elsewhere it appears only inline ("see [D-01]"), never at the start of a list item or heading.
2. **Well-formed ids** — every definition matches `[BR-NN]`, `[AC-NN]`, `[D-NN]`, `[NFR-NN]` or `[Q-NN]` with two or more digits (`[AC-01]`, not `[AC-1]`, `[ac-01]` or `[AC 01]`).
3. **Open items listed** — list every open `[Q-NN]` (no `(resolved)` marker) and every `[NEEDS CLARIFICATION]` explicitly in the output; each one blocks `specs.spec_submit`, so the spec stays `draft`.
4. **Task refs resolve** — every entry in a task's `refs` names an anchor defined in that task's own spec.
5. **AC coverage** — every `[AC-NN]` is referenced by at least one task's `refs`.
6. **Task notes size** — every task's `notes` is at most 2000 characters.
7. **Shared contracts match** — a `[D-NN]` shared across specs (multi-app) has the same number and identical text in every spec that shares it.

## Server check

At the `publish.md` gate, `specs.spec_validate` also runs per spec (content, `apps`, `epic` only when it already exists, tasks). It sees one spec at a time, so item 7 stays offline-only. Any `valid: false` → write nothing, as for a failed item; warnings and `submit_ready: false` are shown in the closing confirmation and keep the spec `draft`. If `spec_validate` is rejected as an unknown or unsupported action (by the server or the harness), the gate falls back to this checklist alone and records the fallback (`publish.md` §4).

## Outcome

- All items pass and, when the Server check ran, no report has `valid: false` (warnings and `submit_ready: false` never block; on the fallback the checklist alone decides) → the content may be returned (author/spec modes) or written (publish mode).
- Any other `spec_validate` error (403, 404, transport, other validation) is a failed read, not a fallback → in `publish` mode write nothing and return `blocked` (`publish.md` §4); in author/spec modes report it — the server check does not count as passed.
- Any item fails → fix it before returning; in `publish` mode, write nothing and return `blocked` with the failures. Never publish a subset of the specs to work around a failing one.
