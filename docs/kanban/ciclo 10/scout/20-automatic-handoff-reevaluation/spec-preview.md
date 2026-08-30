# Phase 20 — Reavaliação do Handoff Automático de Qualificação (Preview)

**Status**: Preview — problema real observado e diagnosticado; especificação completa e
implementação adiadas para o momento oportuno, a critério do operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 09 (`09-required-qualification-attributes/...`) — introduziu
`qualification_handoff_needed?`/`trigger_qualification_handoff` em `AgentRunner`, o mecanismo
questionado aqui. Fase 12 (`12-response-auditor/spec78.md`) — o outro mecanismo de handoff
(`ActionClassifierService`/`handover_to_human`), com o qual este mecanismo é comparado. Fase 18
(`18-funnel-outcome-stage-matching/spec-preview.md`) — evidência original que motivou a criação do
handoff automático (conversas 20/22: Scout confirmava agendamento sem nunca notificar um humano).

---

## Contexto: dois mecanismos de handoff distintos no Scout

1. **Handoff decidido pelo modelo** — o LLM chama `handover_to_human` (diretamente, ou reconsiderando
   durante o repair do `ResponseAuditor`), ou o `ActionClassifierService` (Fase 12) classifica a
   conversa como `handoff` a partir do histórico. Em ambos os casos, uma inteligência (o próprio
   modelo, ou um classificador dedicado lendo o diálogo) decide.
2. **Handoff automático mecânico** — `AgentRunner#qualification_handoff_needed?` /
   `#trigger_qualification_handoff` (Fase 09): dispara **sem nenhum julgamento de LLM**, no instante
   em que uma Oportunidade entra no `qualified_stage_id` configurado do Scout. É puramente
   determinístico — não lê o que o modelo acabou de responder, não avalia o momento da conversa.

## Evidência que motivou este preview

Conversa real (conta 1, Scout "Vitória", modelo `gpt-5.2`, conversation_id 43 / display_id 41,
2026-08-30 14:19–14:55 UTC, Oportunidade #28): lead confirma horário de avaliação (Ortodontia, via
Site, 31/08 às 14:30); todos os campos obrigatórios da Fase 09 já preenchidos
(`data_do_agendamento`, `origem_da_oportunidade`, `interesse`). No mesmo turno em que
`move_opportunity_stage` avança a Oportunidade para o estágio qualificado ("Agendado"), o modelo
também redige uma resposta perguntando **nome e telefone** do lead para finalizar o contato:

> *"Perfeito — confirmei que 14:30 na segunda-feira (31/08) está disponível e já registrei o
> agendamento na oportunidade #28 [...]. Pra finalizar, pode me confirmar seu nome e um telefone
> para contato?"*

`AgentRunner#process_audited_reply` despacha essa pergunta e, na sequência imediata (mesmo
timestamp, mesmo turno), `trigger_qualification_handoff` dispara — transferindo a conversa para um
humano **antes de o lead ter qualquer chance de responder à pergunta que acabou de ser feita**. O
lead digitou "Matias, 45999220122" alguns segundos depois, mas a conversa já tinha sido transferida.

## Comparação com o Captain

Pesquisa dedicada no código do Captain (`enterprise/app/services/captain/`,
`enterprise/app/jobs/captain/`, `enterprise/lib/captain/`) confirmou:

- **Captain não tem nenhum handoff mecânico análogo.** Toda transferência do Captain passa por
  julgamento de LLM — o modelo chama uma tool de handoff dedicada (V2,
  `enterprise/lib/captain/tools/handoff_tool.rb`), ou um classificador separado decide (V1,
  `Captain::Llm::AssistantActionClassifierService`), ou o modelo retorna o token
  `conversation_handoff` como sua própria resposta (V1 legado). Nenhuma tool comum (resolver,
  priorizar, etiquetar, tool HTTP customizada) dispara handoff como efeito colateral do próprio
  sucesso.
- Essa ausência **não é evidência de que o mecanismo do Scout esteja errado** — o Captain
  estruturalmente não tem conceito de Oportunidade/Kanban/estágio de funil configurável (mesma
  ressalva já registrada nas Fases 14 e 18), então não existe nada análogo a "estágio qualificado"
  a partir do qual disparar. A comparação é inconclusiva por falta de arquitetura equivalente, não
  por uma escolha deliberada do Captain de confiar só no LLM nesse cenário específico.
- Um padrão do Captain **é** diretamente aplicável e já foi normalizado no Scout como mitigação
  imediata, independente do resultado desta fase: em `enterprise/app/jobs/captain/conversation/message_builder.rb`,
  toda vez que um handoff é decidido (V1 ou V2), o texto redigido pelo modelo é **descartado por
  completo** — só a mensagem fixa de transferência é enviada (`create_handoff_message`). O Scout já
  seguia essa regra no caminho 1 (handoff direto via `handover_to_human`); a Fase 09
  (`trigger_qualification_handoff`) não seguia, e foi essa a causa mecânica do bug acima. Corrigido
  em 2026-08-30 (ver commit correspondente) alinhando o caminho 2 ao mesmo padrão.

## A pergunta em aberto para esta fase

Com a normalização acima aplicada, o sintoma imediato ("pergunta e transfere") já não deve mais
ocorrer. A pergunta desta fase é mais profunda: **vale manter o mecanismo 2 (handoff mecânico,
sem julgamento de LLM) ou ele deveria ser eliminado, deixando toda decisão de handoff — inclusive
a de "a Oportunidade acabou de qualificar, hora de acionar um humano" — a cargo do LLM (mecanismo
1), como o Captain faz por arquitetura?**

Tensão a resolver:

- **A favor de eliminar o mecanismo 2** — hoje ele é a única fonte de handoffs que não passam por
  nenhum julgamento contextual, e foi a causa raiz de pelo menos dois bugs reais nesta sessão de
  debugging (este, e indiretamente o padrão "estágio avança mas resposta já tinha saído" descrito
  na Fase 18). Unificar tudo no mecanismo 1 simplificaria o sistema para um único caminho de
  decisão, já reforçado nesta sessão com o gate de dupla confirmação (`ResponseAuditor#handoff_confirmed?`,
  ver Fase 12) contra alucinação.
- **Contra eliminar** — o mecanismo 2 foi criado especificamente para resolver a evidência original
  da Fase 18 (conversation_id 20 e 22): o Scout confirmava um agendamento ao cliente mas nunca
  chamava `move_opportunity_stage` nem avisava um humano — ninguém da equipe ficava sabendo do
  agendamento. Se a decisão de "avisar um humano quando qualificar" passar a depender só do LLM
  lembrar de chamar `handover_to_human` no mesmo turno em que qualifica, o risco de regressão para
  esse cenário original (silêncio total, sem card certo no Kanban, sem handoff) volta a existir —
  e é um cenário mais grave que "pergunta e transfere", porque não deixa rastro nenhum.

## Escopo preliminar (a confirmar na especificação completa)

- Levantar se dá para confiar a decisão ao LLM sem reintroduzir o risco acima — por exemplo,
  adicionar um lembrete explícito no `funnel_section`/`guardrails_section` para sempre chamar
  `handover_to_human` no mesmo turno em que uma Oportunidade entra no estágio qualificado, e então
  medir taxa de conformidade real antes de remover o mecanismo mecânico (não remover às cegas).
- Alternativa intermediária: manter um mecanismo de rede de segurança, mas não mais como transferência
  imediata e incondicional — por exemplo, um job com verificação atrasada que só dispara o handoff
  mecânico se, depois de um tempo, o LLM ainda não tiver chamado `handover_to_human` por conta
  própria (rede de segurança, não caminho principal).
- Reavaliar se `qualification_handoff_needed?`/`trigger_qualification_handoff` deveriam ser
  removidos por completo do `AgentRunner` caso a alternativa acima (ou o caminho 100% LLM) se prove
  suficientemente confiável em teste.
- Este preview é sobre a fase de **decisão** de handoff automático; não inclui revisitar a
  normalização de mensagem já aplicada em 2026-08-30 (essa fica valendo independente do resultado).

## Fora de escopo desta fase (preview)

- Qualquer mudança de código agora — este documento só registra a reavaliação para tratamento
  futuro, a critério do operador.
- A normalização "descartar o texto do modelo quando o handoff automático dispara" — já aplicada
  como fix imediato de código em 2026-08-30, independente do resultado desta fase.
- Revisitar o mecanismo 1 (handoff decidido pelo modelo) em si — já reforçado nesta sessão (Fase 12)
  com o gate de dupla confirmação; não é o alvo desta fase.

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Uma decisão explícita e documentada sobre se `qualification_handoff_needed?`/
  `trigger_qualification_handoff` permanecem, são substituídos por uma rede de segurança atrasada,
  ou são removidos em favor do julgamento do LLM.
- Se removidos ou substituídos: uma conversa onde o lead qualifica (todos os campos obrigatórios
  preenchidos, estágio configurado como qualificado) continua resultando, de forma confiável e
  testada, em um humano sendo notificado e a Oportunidade no estágio certo — sem regressão para o
  cenário original da Fase 18 (silêncio total).
- Nenhuma regressão no comportamento já corrigido nesta sessão (dupla confirmação do
  `ActionClassifierService`, normalização de mensagem no handoff automático).

---

> **Nota**: Preview criado a partir do diagnóstico da conversation_id 43 (display_id 41,
> Oportunidade #28, 2026-08-30) e de pesquisa dedicada confirmando que o Captain não tem handoff
> mecânico análogo (arquitetura sem conceito de Oportunidade/Kanban), mas segue um padrão
> diretamente aplicável — nunca enviar o texto do modelo junto de um handoff — já normalizado no
> Scout como fix imediato de código na mesma data, independente do resultado desta fase. Tratamento
> completo da questão de fundo (manter, atrasar ou eliminar o handoff automático mecânico) adiado
> para o momento oportuno, a critério do operador — ver `spec60.md` §11.
