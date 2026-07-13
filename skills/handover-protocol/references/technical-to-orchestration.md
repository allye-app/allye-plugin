# Handover: technical-to-orchestration

**Emitted by:** `technical-planning`
**Received by:** `orchestrator`
**Objetivo:** Conduzir a entrega da feature planejada — este é o handover mais "carregado": o Orchestrator não tem contexto de negócio nem de arquitetura além do que está aqui.

## Before emitting, confirm

- The full reading list is spelled out — doc, epic, feature, every story, every task, grouped by wave. "Read the feature" is not acceptable; list the actual keys.
- Every locked architecture/stack decision is restated — the Orchestrator must never re-open these while dispatching Executor.
- Wave structure matches what Technical Planning actually produced (don't invent an ordering here — copy it).

## Template

```markdown
## 🔄 Allye Handover — technical-to-orchestration
**Skill a carregar:** orchestrator

### Objetivo
Conduzir a entrega de {FEATURE-KEY} — {título da feature}

### Leitura obrigatória
- Doc: {título e referência, ou "Nenhum doc adicional"}
- Epic: {EPIC-KEY}
- Feature: {FEATURE-KEY}
- Stories e tasks por wave:
  - {STORY-KEY} — {título}
    - Wave 1: {TASK-KEY}, {TASK-KEY}
    - Wave 2: {TASK-KEY}
  - {STORY-KEY} — {título}
    - Wave 1: {TASK-KEY}

### Decisões de arquitetura travadas
- {decisão} — {motivo}
- {decisão} — {motivo}

### Contexto adicional
{}

---
Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
