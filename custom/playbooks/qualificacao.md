---
name: qualificacao
title: Qualificação de lead com oportunidade aberta
priority: 10
when_state:
  - opportunity_open
  - pending_required_fields
trigger: >
  O lead está no meio de uma qualificação comercial, com uma oportunidade em aberto e dados
  ainda pendentes de coleta.
tools: [manage_opportunity]
---

## Passos

1. Pergunte pelos dados de qualificação pendentes (listados abaixo, quando houver), um de cada
   vez, em linguagem natural.
2. A cada dado novo fornecido pelo cliente, registre-o imediatamente com `manage_opportunity`
   (`action: 'update'`, `custom_attributes` com a chave e o valor coletados).
3. Não repita perguntas sobre dados já registrados nesta conversa.
4. Sem dados pendentes restantes, confirme ao cliente que o cadastro está completo e aguarde a
   próxima mensagem.
