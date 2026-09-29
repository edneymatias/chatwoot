---
name: qualificacao
title: Qualificação comercial do lead
priority: 10
when_state:
  - in_qualification
  - playbook_not_completed: qualificacao
trigger: >
  Lead em prospecção, com ou sem oportunidade criada, com dados de qualificação a coletar ou já
  coletados e ainda não confirmados. Crie a oportunidade só quando houver interesse comercial.
tools: [manage_opportunity]
exits:
  qualificado:
    kind: transition
    target: agendamento
    stage: qualified
  desqualificado:
    kind: terminal
    stage: unqualified
    fields:
      motivo: string
---

## Diretrizes de Qualificação

1. Se não houver oportunidade em aberto, crie uma oportunidade com `manage_opportunity` assim que o lead demonstrar interesse comercial, nunca antes.
2. Durante a conversa, pergunte apenas pelos campos pendentes listados abaixo, fazendo uma pergunta por mensagem.
3. Durante a qualificação, não invente perguntas adicionais que não estejam nos campos pendentes.
4. Conforme o lead responder, registre cada resposta imediatamente com `manage_opportunity`.
5. Se uma informação já foi coletada, não pergunte de novo.
6. Caso o lead compartilhe detalhes extras espontaneamente, reconheça brevemente o que foi dito sem desviar o foco da qualificação.
7. Se o lead não tiver perfil ou recusar a proposta, encerre com exit_desqualificado informando o motivo (o estágio desqualificado direciona para a fila de revisão humana, nunca como fechamento do negócio).
8. Se o cliente solicitar atendimento humano ou houver necessidade que você não possa atender, acione exit_handoff.
9. Regra importante de segurança: nunca retorne uma oportunidade que já atingiu o estágio qualificado para etapas anteriores.
10. Quando todos os dados pendentes forem coletados e confirmados pelo cliente, acione exit_qualificado e siga no mesmo turno com as instruções retornadas pelo desfecho.
