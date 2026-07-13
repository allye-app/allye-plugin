# Handover: correction

**Emitted by:** `orchestrator`
**Received by:** `execution` (the same Executor chat/session that produced the original implementation, when possible)
**Objetivo:** Corrigir achados específicos do review — este handover é deliberadamente estreito. It never re-briefs the whole story; that would defeat the point of a lean, targeted correction pass.

## Before emitting, confirm

- Only the ❌ findings are included — ✅ and ⚠️ items are not corrections, don't pad this handover with them.
- The correction round number is tracked — per spec §6.4, the Orchestrator escalates to the human after the **3rd** failed round on the same task instead of emitting a 4th correction handover.
- Each finding is quoted from the Reviewer's actual output, not paraphrased — paraphrasing risks losing precision about what exactly needs to change.

## Template

```markdown
## 🔄 Allye Handover — correction
**Skill a carregar:** execution

### Objetivo
Corrigir os achados de review abaixo em {STORY-KEY} — nada além disso.

### Achados a corrigir (❌ apenas)
- {TASK-KEY}: "{achado do reviewer, citado literalmente}"
- {TASK-KEY}: "{achado do reviewer, citado literalmente}"

### Rodada de correção
Esta é a {N}ª tentativa de correção nesta story.
{Se N for igual a 3, o Orchestrator não deveria estar emitindo este handover — deveria ter escalado para o usuário em vez disso. Ver skills/orchestrator.}

---
Corrija SÓ o que está listado acima — não refaça a story inteira. Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
