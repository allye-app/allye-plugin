# Handover: planning-to-technical

**Emitted by:** `product-planning`
**Received by:** `technical-planning`
**Objetivo:** Detalhar tecnicamente os squares (Features) e quadradinhos (Stories) aprovados na fase de negócio.

## Before emitting, confirm

- Every Epic/Feature/Story key is real (created via `work_create`/`work_bulk_create` or found via `work_list`) — never a placeholder key.
- Reused items and newly created items are explicitly distinguished — the next chat should never have to guess which is which.
- Every locked business decision from the Discussion is restated here, not just implied by the work item descriptions.

## Template

```markdown
## 🔄 Allye Handover — planning-to-technical
**Skill a carregar:** technical-planning

### Objetivo
{qual story ou conjunto de stories será detalhado tecnicamente agora}

### Leitura obrigatória
- Epic: {KEY} — {título} ({reusado | criado})
- Feature(s): {KEY} — {título} ({reusado | criado})
- Story(ies) a planejar agora: {KEY} — {título} ({reusado | criado})

### Decisões de negócio travadas
- {decisão 1} — {motivo}
- {decisão 2} — {motivo}

### Protótipos
{referência, ou "Nenhum protótipo foi feito"}

### Contexto adicional
{}

---
Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
