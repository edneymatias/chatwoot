# Phase 09 — Handoff Automático em Intervenção Humana

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §4.2, §7
**Depends on**: Phase 02 (Ferramentas Nativas & Pipeline — `bot_handoff!`, `HandoffService`).
**Ver também**: Fase 15 (preview) — `../15-scout-visibility-indicators/spec-preview.md`, escopo
visual (badge, link de Kanban, indicadores comparativos) movido para lá.

> ⚠️ **Revisão** (segunda passada de brainstorming): o escopo original desta fase incluía um badge
> de status e um link para o card do Kanban, além do botão manual de Pausar/Retomar (já cortado
> numa revisão anterior — ver histórico de revisões abaixo). Nesta passada, o escopo visual inteiro
> foi movido para a Fase 15, para permitir testar o MVP do produto (Scout conectado a conversas,
> sem colidir com atendimento humano) sem bloquear em decisões de UI ainda não amadurecidas —
> inclusive uma ideia nova (indicador comparando resultado do Scout com SDRs humanos) que precisa
> de brainstorming próprio. Esta fase fica reduzida a um único mecanismo de backend.
>
> Revisão anterior (mantida para histórico): o escopo original também incluía um campo
> `auto_pause_on_human_message` em `Scout` que nunca foi implementado. Comparando com como o
> Captain (upstream, `enterprise/`) trata esse cenário — não é uma flag de pausa reversível, é uma
> transição de status síncrona (`Message#mark_pending_conversation_as_open_for_human_response`) —
> o mecanismo abaixo espelha fielmente esse mecanismo já comprovado.

## Goal

Impedir que o Scout responda por cima de um atendente humano que já interveio manualmente numa
conversa que o Scout ainda considerava `pending` — mesmo mecanismo que o Captain (upstream) já usa
para o problema equivalente. Sem isso, o MVP do produto não pode ser testado com segurança: o Scout
poderia gerar uma resposta colidindo com a de um humano que acabou de responder.

## Scope

- **Detecção automática de intervenção humana**: quando um atendente humano envia uma resposta
  pública (não nota privada) numa conversa ainda `pending` de uma inbox com Scout habilitado, a
  conversa é reaberta (`status: open`) de forma síncrona, **antes** de qualquer resposta do Scout
  já enfileirada/debounced poder ser enviada.

## Out of scope

- **Qualquer elemento visual novo na conversa** (badge de status, link para o Kanban, indicador
  comparativo IA vs. SDR humano) — movido para a Fase 15 (preview). A seção "Oportunidades" já
  existente no painel de contato (`ContactOpportunities.vue`) permanece como está; nenhuma mudança
  nela faz parte desta fase.
- **Controle manual de Pausar/Retomar por conversa** — sem equivalente no Captain; cortado desta
  fase (revisão anterior).
- Sem bulk pause/resume — não que isso ainda se aplique, dado o corte acima, mas mantido registrado
  por já constar no escopo original.

## Acceptance criteria

- Quando um atendente humano envia uma resposta pública numa conversa `pending` de uma inbox com
  Scout, a conversa é reaberta de forma síncrona antes que qualquer resposta do Scout já
  enfileirada possa ser enviada — sem resposta duplicada/colidente do Scout após a intervenção
  humana.
- Conversas sem Scout na inbox, ou com Scout desabilitado, não têm nenhuma mudança de
  comportamento.
- Notas privadas (não públicas) de um humano não disparam a reabertura — só respostas públicas ao
  cliente.

## Abordagem técnica

`custom/app/models/custom/message.rb` (novo — via `Message.prepend_mod_with('Message')`, o mesmo
ponto de extensão que o Enterprise já usa para o Captain): sobrescreve
`mark_pending_conversation_as_open_for_human_response`, chama `super` (encadeia com a checagem do
Captain, se presente) e replica a mesma regra para o Scout: resposta pública de humano
(`sender_type == 'User'`), conversa `pending`, inbox com Scout habilitado → `conversation.open!`.

Nenhuma mudança de frontend, nenhum novo endpoint, nenhum novo campo de banco.
