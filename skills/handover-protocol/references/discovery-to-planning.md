# Handover: discovery-to-planning

**Emitted by:** `sandbox` (once approved by the user)
**Received by:** `product-planning`
**Objetivo:** Transformar a direção aprovada durante o Sandbox em estrutura de entregáveis (squares/quadradinhos → Epic/Feature/Story).

## Before emitting, confirm

- A Discovery Doc was created in Allye (`doc_create`, location confirmed with the user against `doc_full_tree`) — this handover references it, it does not duplicate its content.
- Every path that was explored and abandoned is listed with *why* — the next chat should never accidentally re-propose a rejected direction.
- Research findings (if any) are summarized with enough detail to act on, not just "found some stuff."

## Template

```markdown
## 🔄 Allye Handover — discovery-to-planning
**Skill a carregar:** product-planning

### Objetivo
{uma frase: qual produto/objetivo está sendo planejado}

### Discovery Doc
- Título: {título do doc}
- Referência no Allye: {doc id ou caminho na árvore}

### Direção aprovada
{síntese do que foi decidido no Sandbox — o quê e por quê}

### Caminhos explorados e rejeitados
- {caminho A} — rejeitado porque {motivo}
- {caminho B} — rejeitado porque {motivo}

### Achados de pesquisa
{resumo do que deep-search / code-analyzer trouxeram, com fonte — "Nenhuma pesquisa foi feita" se não houve}

### Protótipos
{referência de artifacts gerados, ou "Nenhum protótipo foi feito"}

### Contexto adicional
{qualquer coisa mais que o próximo chat precisa saber}

---
Se algo não estiver claro, PARE e pergunte — não prossiga chutando.
```
