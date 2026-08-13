---
name: agent-runtime
description: Contract for driving an external agent runtime — spawning real agent processes in panes, dispatching work to them, and collecting results. Use when the session hook reported a runtime and work is about to be dispatched in parallel.
version: "1.0"
category: methodology
---

# Agent Runtime

An **agent runtime** owns real agent processes the human can watch, attach to, and take
over. This skill defines what the plugin needs from one, so the Orchestrator can drive
any runtime that satisfies the contract rather than one specific tool.

Load this only when a compatible runtime is actually detected and the user benefits from delegation. Without one, continue locally or use another available subagent mechanism; never let the absence or degradation of a runtime block delivery.

Concrete commands for the runtimes we implement live in `references/`.

For Herdr, the Pi adapter exposes `workspace` and `tab` creation in addition to
`spawn`, and returns an execution ID from `dispatch`. The caller must retain this
ID, use `status`/`wait`, collect the result, and only then request ownership-guarded
`cleanup`. `mark_intervened` records human takeover and permanently blocks automatic
cleanup for that execution. This file is the
contract; the reference is the implementation.

<!-- adapted from ogulcancelik/herdr SKILL.md (Apache-2.0) — the primitive vocabulary and the safety rules -->

## The five primitives

### 1. detect

Answer two questions, not one: does the tool exist, and **is this session running inside
it**. A binary on `PATH` says nothing about the second.

A runtime that fails any part of detection is **absent**, never **broken**. A version
mismatch, an unreachable server, a missing environment variable — each means fall back to
asking the user manual-or-automatic. A degraded runtime must never block delivery.

### 2. spawn

Produce an isolated execution location and return a **stable identifier** for it. The
location must be a shell at an interactive prompt with nothing running in the foreground,
and creating it must not steal the human's focus.

<HARD-GATE>
**Wait for the shell; do not merely inspect it.** A pane created a moment ago is often
still running the shell's startup — a banner, a version manager, a greeting. Dispatching
into it fails. Poll for a bare shell with a bound, and treat a pane still busy after the
bound as a problem to report rather than one to keep waiting on.
</HARD-GATE>

### 3. dispatch

Deliver the briefing and **confirm it was accepted**.

<HARD-GATE>
Confirmation is part of the primitive, not an optional check. Sending text to an agent
that is idle can leave it sitting in the input box unsubmitted — the agent looks dispatched
and is not. After dispatching, read the agent's state back. If it has not moved to a
working state, submit explicitly and read it again.
</HARD-GATE>

### 4. wait

Block until the agent's lifecycle state settles. **Always with a timeout** — an unbounded
wait on a stalled agent hangs the whole delivery.

<HARD-GATE>
A settled state does not prove completion. "Idle" can mean finished, or an API error
mid-turn, or a question sitting unanswered on screen. An "unknown" state proves nothing at
all.

Runtime state is **evidence**. The verdict comes from `collect`.
</HARD-GATE>

**`wait` is not how the Orchestrator blocks — it is how the runtime's lifecycle becomes an
event in whatever system the Orchestrator actually lives in.** Run it as a background job
of the host harness so its completion arrives as a notification. Polling the agent's state
by hand works and is wrong: it makes every check an arbitrary interruption, and a finished
agent sits unnoticed until the next one. **A dispatch without a wait registered is a story
nobody is listening for**, so registering it is the closing step of `dispatch`, not a
separate thing to remember.

A future runtime satisfies this primitive only if its wait can be bridged that way.

### 5. collect

Read the result **from Allye**:

- `work_children(id: "{story uuid}")` — the real status of every task
- `memory_search("Review {STORY-KEY}")` — the review findings
- `memory_search("Implementation {TASK-KEY}")` — what was done and why

The terminal is for human observation and for diagnosing a stuck agent. It is never the
source of the result, for three reasons that hold regardless of what the terminal can show:

- A record in Allye is structured and machine-readable; a transcript is prose to be parsed.
- The Orchestrator can read it from a pane it never created, and after that pane is closed.
- It works identically for every runtime, including those with no output-read primitive at
  all — which is most of the category.

There is also a documented failure mode where full-screen agents render on the terminal's
alternate screen and those rows never reach scrollback, making a long report unrecoverable.
**Treat that as a caveat, not the reason.** It did not reproduce in testing on 2026-07-26,
and a design justified by a failure that does not reproduce is one experiment away from
being abandoned for the wrong reason.

An agent that has settled but left no trace in Allye has produced an **incomplete report**.
Treat it the way §5 of `orchestrator` already treats one: ask for more, do not wave it
through.

## The obligation on the dispatched side

When a managed work item exists, the dispatched agent should leave a durable trace in
Allye before settling: task statuses and an implementation/review memory as applicable.
For an explicitly approved no-task path, return a durable result through the host session
or another agreed channel and do not invent work items merely to satisfy this contract.

This keeps Allye authoritative when it is in scope while allowing local, low-risk work
to complete without a mandatory work-item workflow.

## Teardown

Destroy only what you created, and only after the work it held is merged and verified or
the user explicitly authorizes cleanup. Never close a pane, tab, workspace, or session the
plugin did not create. Never stop the runtime's server.

## Implementations

- Herdr — `references/herdr.md`
