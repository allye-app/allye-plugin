# Handover: story-execution

**Emitted by:** `orchestrator`
**Received by:** `execution`
**Objetivo:** Implementar exatamente **uma** story — nunca uma feature inteira, e sempre a story **inteira**: todas as suas tasks, de todas as waves, em um único dispatch. This is the scoping rule the whole Orchestrator/Executor loop depends on: one dispatch = one whole story. There is no per-wave handover and no follow-up "next wave" handover — the Executor works through the waves in order and reports back once, when the story is done.

## Before emitting, confirm

- Exactly one story is named — if the Orchestrator is tempted to hand off two stories "to save a round trip," it must not; that's a feature-level handover in disguise.
- **Every** task under that story is listed — all of them, across all waves, not just the first wave — with its acceptance criteria copied in **full** (not summarized, not just linked). The Executor's chat has no other context and will never receive a second handover for the rest of the story.
- Tasks are grouped by wave so the Executor knows the execution order, but the wave grouping is ordering information only — it never shrinks the scope of the dispatch.
- Applicable code standards were discovered (`skill_list`) and are named here, not left for the Executor to rediscover.

## Template

```markdown
## 🔄 Allye Handover — story-execution
**Skill a carregar:** execution

### Objetivo
Implementar {STORY-KEY} — {título da story}

### Story
- Chave: {STORY-KEY}
- Critérios de aceite: {copiados da descrição da story}

### Tasks (todas as tasks da story, agrupadas por wave)
- Wave 1:
  - {TASK-KEY} — {título}
    - Critérios de aceite: {copiados na íntegra da descrição da task}
  - {TASK-KEY} — {título}
    - Critérios de aceite: {copiados na íntegra da descrição da task}
- Wave 2:
  - {TASK-KEY} — {título}
    - Critérios de aceite: {copiados na íntegra da descrição da task}

### Decisões travadas aplicáveis
- {decisão} — {motivo}

### Padrões de código aplicáveis
{convenções descobertas via skill_list que devem ser seguidas, ou "Nenhum padrão de time encontrado — seguir convenções existentes no código"}

### Expectativa de TDD
{se aplica Red-Green-Refactor e por quê, ou por que não se aplica}

---
Leia SÓ essa story e essas tasks — nada além disso. Execute as waves na ordem listada. Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
