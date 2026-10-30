# Hook test harness

Helpers and the runner of `hooks/test-live-report.sh`, `hooks/test-allye-hooks.sh`, `hooks/test-session-preferences.sh`
and `hooks/test-session-start.sh`. Nothing here is product code: it only runs the real `hooks/*.sh` in a sandbox.

- `parallel.sh` — the section runner (below), sourced by the three big suites.
- `fake-hooks-api.mjs` — the loopback fake of the Allye API (one per case, started and killed by pid).
- `fake-owner.mjs` — the fake Claude Code process the session watcher cases watch.
- `shims/` — logging shims for the tools the hooks call (`jq`, `date`, `curl`, ...). Every shim except `date`, `curl` and
  `stat` is a symlink to `_wrap.sh`, which takes the tool name from `$0`: one bash per call and no `dirname`/`env` fork
  (these were about half of a hook run).
- `measure-latency.sh` — latency measurement for the live reporter.

## Running

```
bash hooks/test-live-report.sh                      # every group, at most 4 workers, output per group
bash hooks/test-live-report.sh --list               # group ids and rough serial seconds
bash hooks/test-live-report.sh --group taskkey      # one group (or --group a,b), in this process
bash hooks/test-live-report.sh --only 'watcher'     # sections whose name matches a regex (LIVE_TEST_SECTIONS does the same)
bash hooks/test-live-report.sh --serial             # the whole file in one process, as before
bash hooks/test-live-report.sh --jobs 2             # fewer workers (never more than 4: the machine rule)
LIVE_TEST_PROFILE=1 bash hooks/test-live-report.sh --group label   # time in hook runs, wait_idle and new_case
```

`hooks/test-allye-hooks.sh` and `hooks/test-session-preferences.sh` take the same options.

## How it works

The suites are one long bash file: a preamble (helpers, sandbox), sections (`echo "== NAME =="`), a tally. Each case already
has its own sandbox, so cases are independent; what ties sections together is helper functions and variables defined in
earlier sections. Comment markers in the file turn it into units that can run alone:

| Marker | Meaning |
|---|---|
| `#@group <id> <seconds> [shards=N]` | the sections up to the next marker form one group; the seconds only order the queue (longest first); `shards=N` runs the group N times and each run takes every Nth item (`pt_mine INDEX`) |
| `#@always` … `#@end` | a helper block kept in every worker (without `#@end`, until the next section) |
| `#@keepnext` | the next section runs in every worker (the final "no leftover process" checks), but only the worker of group `final` counts it |
| `#@tally` | the final tally, kept in every worker |

The runner (`pt_dispatch`) cuts the unselected groups out of a copy of the file with awk and runs the copies with bash. When a
section starts using a helper from another group, the worker fails with `command not found`/`unbound variable`: wrap the
definition in `#@always`/`#@end` or move the section into that group. The total number of checks is unchanged (2394 in the
live suite at the time of writing, tail checks counted once).

Safety: at most 4 workers; every worker has its own sandbox root (`mktemp -d`), its own fake API per case and removes both at
exit; the orchestrator records the pid of every worker it starts, kills only those on EXIT/INT/TERM and holds no lock file
descriptor, so nothing it starts inherits one. Tests sandbox `HOME` and `XDG_*`; the real `~/.claude` is never read.

## What made it faster, and what was researched

Profile of the live suite (serial, 12 min before ALY-263, 29.5 min after): per hook run ~0.27 s (about 30 shim calls of
~6.8 ms each, 4 forks per call), `wait_idle` ~15% (the 2 s delayed-flush sleeper), `new_case` ~10% (node start + 50 ms
poll), the rest assertions.

1. **Parallel groups, max 4 workers** (bats `--jobs` / GNU parallel style, but section-granular because the cases of a
   section share helpers and the suite has no bats dependency).
2. **Wake the delayed-flush sleeper instead of waiting for it** (`wake_sleepers` in `wait_idle`): the sleeper only sleeps
   ≤ 2 s and then runs; ending its `sleep` child (found through `flush.wait`, `/proc/<pid>/task/*/children`, `comm = sleep`)
   makes it run that code at once. Sections that assert real elapsed time set `FAST_IDLE=0` (delayed tool flush). This
   replaces fixed sleeps with an event: "the flush finished".
3. **Cheaper shims** (see above) and a 10 ms instead of 50 ms readiness poll for the fake API port file.
4. Considered and not done: one long-lived fake API reset per case (the cases read and write control files in their own
   `api` dir and keep in-memory counters; the saving is ~10% of the work and it would let a stray late request of one case
   reach the next); shellspec/bats (no new dependencies, the assertions are plain `check` calls); tmpfs (`/tmp` already is).

Sources consulted: bats-core `--jobs` and `--no-parallelize-within-files` docs (parallelism needs independent files/tests and
a local `parallel`), GNU parallel `--jobs`/`--halt`, shellspec parallel execution, and the usual guidance for fast shell
suites: fewer forks per assertion (builtins over `cat`/`dirname`/`env`), event-driven waits over `sleep`, per-worker
sandboxes, and a longest-first queue.

## Adding a case

Put it in the section it belongs to; use only helpers of its group or `#@always` ones. Add a new section to an existing group,
or start a group with `#@group`. After adding, run the group alone (`--group ID`) and the whole file once.
