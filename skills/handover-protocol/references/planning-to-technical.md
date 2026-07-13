# Handover: planning-to-technical

**Emitted by:** `product-planning`
**Received by:** `technical-planning`
**Objetivo:** Detalhar tecnicamente os squares (Features) e quadradinhos (Stories) aprovados na fase de negócio.

## Before emitting, confirm

- Every Epic/Feature/Story key is real (created via `work_create`/`work_bulk_create` or found via `work_list`) — never a placeholder key.
- Reused items and newly created items are explicitly distinguished — the next chat should never have to guess which is which.
- The `Doc:` line is filled in: if a Discovery Doc exists upstream (from a `discovery-to-planning` handover), carry its reference here; if none, write "Nenhum doc adicional" explicitly — don't leave the line out.
- Any key business decision made during Product Planning (scope cuts, explicit user choices, priorities — the ones saved as planning memories) is restated here, not just implied by the work item descriptions. This section is best-effort and often short or empty: most locked decisions come later, from Technical Planning's own Discussion Phase — don't pad it.

## Template

```markdown
## 🔄 Allye Handover — planning-to-technical
**Skill a carregar:** technical-planning

### Objetivo
{qual story ou conjunto de stories será detalhado tecnicamente agora}

### Leitura obrigatória
- Doc: {título e referência do Discovery Doc, ou "Nenhum doc adicional"}
- Epic: {KEY} — {título} ({reusado | criado})
- Feature(s): {KEY} — {título} ({reusado | criado})
- Story(ies) a planejar agora: {KEY} — {título} ({reusado | criado})

### Decisões de negócio travadas
- {decisão 1} — {motivo}
- {decisão 2} — {motivo}
{ou "Nenhuma decisão de negócio travada além das descrições dos itens"}

### Protótipos
{referência, ou "Nenhum protótipo foi feito"}

### Contexto adicional
{}

---
Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
