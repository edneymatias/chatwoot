---
name: identificacao
title: Identificação do contato
priority: 30
when_state:
  - contact_identity_incomplete
  - playbook_not_completed: identificacao
trigger: >
  O contato ainda não informou como quer ser chamado ou não tem telefone registrado.
tools: [update_contact]
exits:
  identificado:
    kind: transition
    target: qualificacao
---

Se o contato possui identificador provisório, não use o nome registrado para se dirigir a ele.
Pergunte cada dado faltante uma única vez ao longo da conversa.
Se faltarem nome e telefone, pergunte primeiro o nome e depois o telefone em mensagens separadas; nunca os dois na mesma mensagem.
Assim que o contato responder qualquer dado, registre imediatamente com a ferramenta update_contact.
Assim que todos os dados faltantes tiverem sido solicitados uma vez (seja respondidos, recusados ou ignorados), chame exit_identificado sem esperar a resposta no mesmo turno.
