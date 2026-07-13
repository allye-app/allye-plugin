---
name: handover-protocol
description: The shared contract for handing off context between Allye workflow phases as copy-pasted chat text. Use when a phase skill is ending and needs to brief a fresh chat for the next phase (Planning, Technical Planning, Orchestrator, Executor), or when a fresh chat opens with a pasted handover and needs to detect which skill to load.
version: "1.0"
category: methodology
---

# Handover Protocol

A handover is how context moves between Allye workflow phases without carrying a chat's full history forward. Each phase runs in its own fresh, lean-context conversation; when it finishes, it emits a handover — a block of chat text the user reads, approves, and pastes as the first message of the next chat. The next chat's bootstrap detects the marker and loads the right skill automatically.

**A handover is never saved as a memory or a file.** The Allye doc and work items it references are the durable record — the handover text itself is a disposable transport vehicle, copied by hand in both directions (including Orchestrator ↔ Executor's correction loop).

<!-- adapted from humanlayer/humanlayer create_handoff/resume_handoff (Apache-2.0) — the discipline that a handoff must be complete enough that the receiving chat needs nothing else -->

## 1. The shared marker

Every handover starts with the same one-line marker and ends with the same reminder. Everything between them is specific to the handover's type — see §2.

```markdown
## 🔄 Allye Handover — {tipo}
**Skill a carregar:** {skill-slug}

...corpo específico do tipo — ver references/{tipo}.md...

---
Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```

The bootstrap skill (`using-allye`) scans the first message of every fresh conversation for the `## 🔄 Allye Handover` line. When found, it parses `{tipo}` and `Skill a carregar`, loads that skill directly, and skips its own phase-detection heuristic. See `using-allye`'s "Handover detection" step.

## 2. The catalog

Six types. Each is a distinct handoff with its own objective and field set — not a generic form filled in differently. Full templates live in `references/`.

| Tipo | Transição | Objetivo | Template |
|---|---|---|---|
| `discovery-to-planning` | Sandbox → Planning | Transformar a direção aprovada em estrutura de entregáveis | `references/discovery-to-planning.md` |
| `planning-to-technical` | Planning → Tech Planning | Detalhar tecnicamente os squares aprovados | `references/planning-to-technical.md` |
| `technical-to-orchestration` | Tech Planning → Orchestrator | Conduzir a entrega da feature planejada | `references/technical-to-orchestration.md` |
| `story-execution` | Orchestrator → Executor | Implementar exatamente uma story | `references/story-execution.md` |
| `execution-report` | Executor → Orchestrator | Devolver o resultado da implementação | `references/execution-report.md` |
| `correction` | Orchestrator → Executor | Corrigir achados específicos do review | `references/correction.md` |

**Reviewer never receives a handover.** It's the one role invoked via the `Agent` tool with a constructed prompt (story + tasks + files changed), dispatched by the Orchestrator — not by a pasted handover.

## 3. Writing a good handover (mandatory checklist)

<!-- adapted from humanlayer/humanlayer create_handoff (Apache-2.0) and EveryInc/compound-engineering-plugin artifact_readiness contracts (MIT) -->

Before emitting any handover, confirm:

- **Concrete keys, not vague pointers.** "The story we discussed" is not acceptable — write the actual `STORY-KEY`. The receiving chat has zero memory of this conversation.
- **Locked decisions are carried forward, verbatim.** If a decision was locked in this phase, restate it in the handover — don't make the next chat re-derive or, worse, re-litigate it.
- **Scope matches the type.** `story-execution` carries exactly one story; `correction` carries only the failed findings, not the whole story again. Padding a handover with everything "just in case" defeats the purpose of a lean next chat.
- **The reminder line is never dropped.** Every handover ends with the "stop and ask" line — it's the single most important sentence in this whole protocol.

## 4. Auto-detection (implemented in `using-allye`)

Detection logic lives in `using-allye`'s bootstrap (checked before its phase-detection table), not duplicated here — see `skills/using-allye/SKILL.md` §2. This skill defines the *contract*; `using-allye` implements the *routing*.
