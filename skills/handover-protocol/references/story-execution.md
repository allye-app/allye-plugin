# Handover: story-execution

**Emitted by:** `orchestrator`
**Received by:** `execution`
**Objetivo:** Implementar exatamente **uma** story — nunca uma feature inteira. This is the scoping rule the whole Orchestrator/Executor loop depends on.

## Before emitting, confirm

- Exactly one story is named — if the Orchestrator is tempted to hand off two stories "to save a round trip," it must not; that's a feature-level handover in disguise.
- Every task under that story is listed with its acceptance criteria copied in (not just linked) — the Executor's chat has no other context.
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

### Tasks (nesta wave)
- {TASK-KEY} — {título} — {critérios de aceite resumidos}
- {TASK-KEY} — {título} — {critérios de aceite resumidos}

### Decisões travadas aplicáveis
- {decisão} — {motivo}

### Padrões de código aplicáveis
{convenções descobertas via skill_list que devem ser seguidas, ou "Nenhum padrão de time encontrado — seguir convenções existentes no código"}

### Expectativa de TDD
{se aplica Red-Green-Refactor e por quê, ou por que não se aplica}

---
Leia SÓ essa story e essas tasks — nada além disso. Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
