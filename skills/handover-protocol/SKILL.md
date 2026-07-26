---
name: handover-protocol
description: The shared contract for handing off context between Allye workflow phases as copy-pasted chat text. Use when a phase skill is ending and needs to brief a fresh chat for the next phase (Planning, Technical Planning, Orchestrator, Executor), or when a fresh chat opens with a pasted handover and needs to detect which skill to load.
version: "1.3"
category: methodology
---

# Handover Protocol

A handover is how context moves between Allye workflow phases without carrying a chat's full history forward. Each phase runs in its own fresh, lean-context conversation; when it finishes, it emits a handover — a block of chat text the user reads, approves, and pastes as the first message of the next chat. The next chat's bootstrap detects the marker and loads the right skill automatically.

**A handover is never saved as a memory or a file.** The Allye doc and work items it references are the durable record — the handover text itself is a disposable transport vehicle, copied by hand in both directions (including Orchestrator ↔ Executor's correction loop).

<!-- adapted from humanlayer/humanlayer create_handoff/resume_handoff (Apache-2.0) — the discipline that a handoff must be complete enough that the receiving chat needs nothing else -->

## 1. The shared marker

Every handover starts with the same one-line marker and ends with the same reminder. Everything between them is specific to the handover's type — see §2.

```markdown
## 🔄 Allye Handover — {type}
**Skill to load:** {skill-slug}

...type-specific body — see references/{type}.md...

---
If anything is unclear, STOP and ask — don't proceed on a guess.
```

The bootstrap skill (`using-allye`) scans the first message of every fresh conversation for the `## 🔄 Allye Handover` line. When found, it parses `{type}` and `Skill to load`, loads that skill directly, and skips its own phase-detection heuristic. See `using-allye`'s "Handover detection" step.

**Templates in this skill and in `references/` are written in English — that's the source, not the output.** When actually generating a handover for the user, follow the plugin's language principle same as everywhere else: respond in the user's language. Section headers (`### Objective`, `### Required reading`, etc.) and body prose get written in whatever language the conversation is in — a Portuguese-speaking user gets `### Objetivo`, `### Leitura obrigatória`, and so on. **Only two things stay fixed in every language**, because auto-detection parses them literally: the `## 🔄 Allye Handover — {type}` marker line and the `**Skill to load:**` field name. Never translate those two.

## 2. The catalog

Six types. Each is a distinct handoff with its own objective and field set — not a generic form filled in differently. Full templates live in `references/`.

| Type | Transition | Objective | Template |
|---|---|---|---|
| `discovery-to-planning` | Sandbox → Planning | Turn the approved direction into a deliverable structure | `references/discovery-to-planning.md` |
| `planning-to-technical` | Planning → Tech Planning | Technically detail the approved squares | `references/planning-to-technical.md` |
| `technical-to-orchestration` | Tech Planning → Orchestrator | Drive delivery of the planned scope (feature, or a whole epic) | `references/technical-to-orchestration.md` |
| `story-execution` | Orchestrator → Executor | Implement exactly one story | `references/story-execution.md` |
| `execution-report` | Executor → Orchestrator | Return the implementation result | `references/execution-report.md` |
| `correction` | Orchestrator → Executor | Fix specific review findings | `references/correction.md` |

**Neither reviewer axis ever receives a handover.** `reviewer-standards` and `reviewer-spec` are both invoked<!-- opencode-exclude:start --> via the `Agent` tool<!-- opencode-exclude:end --> with a constructed prompt (story + tasks + files changed), dispatched by the Orchestrator — not by a pasted handover.

<!-- opencode-exclude:start -->
**Executor is reachable both ways.** In manual mode it receives `story-execution`/`correction` handovers as documented above. In automatic mode (Orchestrator's choice, offered per story) it's dispatched via the `Agent` tool instead, the same way the reviewer axes are — see `agents/executor.md`. Either way the content is the same; only the transport differs.
<!-- opencode-exclude:end -->

## 3. Writing a good handover (mandatory checklist)

<!-- adapted from humanlayer/humanlayer create_handoff (Apache-2.0) and EveryInc/compound-engineering-plugin artifact_readiness contracts (MIT) -->

Before emitting any handover, confirm:

- **Concrete keys, not vague pointers.** "The story we discussed" is not acceptable — write the actual `STORY-KEY`. The receiving chat has zero memory of this conversation.
- **References carry an explicit read instruction, not just keys.** The handover must tell the receiver to actually fetch and read what it lists — work items via `work_get`/`work_children` (the entire subtree under the parent, when the handover is scoped to a parent item like a feature or epic), docs via `doc_get`. A key list without a "read all of this" instruction invites skimming, and the receiving chat has no other way to know reading is mandatory.
- **Locked decisions are carried forward, verbatim.** If a decision was locked in this phase, restate it in the handover — don't make the next chat re-derive or, worse, re-litigate it.
- **Scope matches the type.** `story-execution` carries exactly one story; `correction` carries only the failed findings, not the whole story again. Padding a handover with everything "just in case" defeats the purpose of a lean next chat.
- **The reminder line is never dropped.** Every handover ends with the "stop and ask" line — it's the single most important sentence in this whole protocol.
<!-- adapted from mattpocock/skills triage AGENT-BRIEF (MIT) — durability of handoff artifacts -->
- **Name interfaces and contracts, not file paths and line numbers.** Write "the `SkillConfig`
  type gains an optional `schedule` field", never "open `src/types/skill.ts` and edit line 42."
  A handover can be read hours later, by a different agent, in a worktree where the tree has
  already moved — a line number is wrong by then and a contract is not. The one exception is a
  snippet that encodes a decision more precisely than prose can (a schema, a state machine, a
  type shape); include it, trimmed to the decision.

## 4. Auto-detection (implemented in `using-allye`)

Detection logic lives in `using-allye`'s bootstrap (checked before its phase-detection table), not duplicated here — see `skills/using-allye/SKILL.md` §2. This skill defines the *contract*; `using-allye` implements the *routing*.
