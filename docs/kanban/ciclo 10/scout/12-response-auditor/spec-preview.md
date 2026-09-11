# Phase 11 — Auditor de Resposta (Preview)

**Status**: Preview — condicional a resultado da Fase 10, a ser especificado antes da implementação
**Master doc**: `docs/kanban/ciclo 9/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 07 (ponto único de interceptação da resposta final), Phase 10 (telemetria que
decide se esta fase entra em implementação).

---

## Esta fase é condicional, não garantida

Diferente das fases anteriores, a Fase 11 **não tem implementação garantida**. Ela só avança se a
telemetria coletada na Fase 10 mostrar, em produção, um dos dois sintomas abaixo:

- Handoffs para humano que deveriam ter acontecido mas não aconteceram (o modelo "insistiu" em
  responder sozinho quando deveria ter chamado `handover_to_human`).
- Promessas de trabalho futuro não cumpridas na mesma resposta ("vou verificar e te aviso", "vou
  encaminhar isso", etc.) sem chamada de tool correspondente.

Se a Fase 10 não evidenciar esses sintomas, esta fase permanece em preview indefinidamente — os
guardrails fixos no prompt (Fase 07) são considerados suficientes.

## Arquitetura identificada no Captain (referência)

Fonte: `enterprise/app/jobs/captain/conversation/{response_builder_job,v1_action_classifier,v1_false_promise_handler}.rb`
(read-only reference, não reaproveitado/copiado — mesma ressalva de licenciamento das fases
anteriores).

- **`Captain::Conversation::V1ActionClassifier`**: chamada de LLM separada
  (`Captain::Llm::AssistantActionClassifierService`) que classifica a resposta já gerada em
  `continue`/`handoff`, com lista fechada de `action_reason`, independente do que a resposta em si
  "disse". Roda em **toda** resposta quando o feature flag de conta está ativo — não é condicional
  a heurística.
- **`Captain::Conversation::V1FalsePromiseHandler`**: chamada separada
  (`Captain::Llm::AssistantFalsePromiseService`) que detecta promessa de trabalho futuro na
  resposta gerada. Se detectada, regenera a resposta com uma instrução de reparo injetada
  (mensagem de role `system`/interna, não visível ao cliente) e reverifica o resultado — caminho
  de pior caso custa até **4 chamadas de LLM extras** num único turno (classificador + detector +
  regeneração + reverificação).
- Ambos os flags são **por conta**, com fallback silencioso (`rescue StandardError` + log) para a
  resposta original em caso de falha do auditor — a auditoria nunca bloqueia a entrega da resposta
  principal.
- Ambos se acoplam ao pipeline em um único ponto: `ResponseBuilderJob#process_response`, que recebe
  `@response` já gerado e decide handoff/persistência antes de criar a `Message`. É esse seam que a
  Fase 07 do Scout precisa preservar.

## Escopo preliminar (a confirmar na especificação completa)

- Novo serviço análogo a `Captain::Llm::AssistantActionClassifierService` e/ou
  `Captain::Llm::AssistantFalsePromiseService`, adaptado ao domínio do Scout (decisão de handoff
  para `handover_to_human`, não para os tokens internos do Captain).
- Feature flag por Scout (ou por conta) para habilitar o auditor de forma incremental, seguindo o
  padrão do Captain — não habilitado por padrão.
- Hook único no pipeline de resposta do Scout (estabelecido na Fase 07) onde o auditor intercepta a
  resposta final antes da persistência da `Message`.
- Definir se o Scout precisa dos dois auditores (classificador + detector de falsa-promessa) ou
  apenas um, com base no sintoma real observado na telemetria da Fase 10 — não replicar os dois só
  porque o Captain tem os dois.

## Fora de escopo desta fase (preview)

- Implementação do(s) serviço(s) de auditoria — esta fase é só o registro da decisão adiada e da
  arquitetura de referência; a especificação completa só é escrita se a Fase 10 evidenciar a
  necessidade.
- Qualquer mudança no pipeline de geração de resposta do Scout além do que já foi garantido na
  Fase 07 (ponto único de interceptação).

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Telemetria da Fase 10 documentada como evidência da necessidade (link/dados anexados à
  especificação completa desta fase).
- Auditor roda no ponto único de interceptação da Fase 07, sem duplicar handoff nem persistir
  mensagem duas vezes.
- Falha do auditor nunca bloqueia a entrega da resposta principal (fallback silencioso, com log/
  rastreamento de exceção).

---

> **Nota**: Preview criado a partir da análise da arquitetura de auditoria do Captain
> (`Captain::Conversation::V1ActionClassifier`/`V1FalsePromiseHandler`). Esta fase só sai do status
> de preview se a telemetria da Fase 10 justificar — ver `07-system-prompt-guardrails/spec-preview.md`
> e `spec60.md` §11.
