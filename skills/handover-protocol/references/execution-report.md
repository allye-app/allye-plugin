# Handover: execution-report

**Emitted by:** `execution`
**Received by:** `orchestrator`
**Objetivo:** Devolver o resultado da implementação — o que o Orchestrator usa para decidir se dispara o Reviewer ou já cascateia status.

## Before emitting, confirm

- Every task's status is reported per acceptance criterion, not as a blanket "done" — the Orchestrator and the eventual Reviewer both need this granularity.
- Files changed are listed explicitly (not "various files") — the Reviewer dispatch depends on this list.
- Open questions are surfaced here rather than silently assumed away — this is the Executor's last chance to flag uncertainty before the chat ends.

## Template

```markdown
## 🔄 Allye Handover — execution-report
**Skill a carregar:** orchestrator

### Story implementada
{STORY-KEY} — {título}

### Tasks e status por critério de aceite
- {TASK-KEY}: {✅ concluída | ⚠️ parcial | ❌ bloqueada}
  - {critério 1}: {atendido | não atendido — por quê}
  - {critério 2}: {atendido | não atendido — por quê}

### Arquivos alterados
- {path} — {o que mudou}
- {path} — {o que mudou}

### Testes adicionados
{quais, o que cobrem, ou "Nenhum teste foi necessário — motivo"}

### Decisões novas tomadas durante a implementação
- {decisão} — {motivo}, ou "Nenhuma decisão nova"

### Dúvidas em aberto
{qualquer coisa que ficou sem resposta e precisa de decisão humana, ou "Nenhuma"}

---
Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
