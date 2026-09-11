# Fase 17 — Observabilidade do Scout e Aviso de Handoff ao Cliente

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §4.2, §6
**Depends on**: Phase 02 (Ferramentas Nativas & Pipeline — `AgentRunner`, `Custom::Scout::Tools::*`,
`HandoffService`).

> Fase nascida de um teste real do MVP: a primeira conversa via Website Widget caiu em fail-safe
> logo cedo, e não havia como saber o que tinha acontecido além de uma nota privada genérica
> ("Falha ao interpretar resposta estruturada do modelo") — nem rede, nem prompt, nem qual foi a
> resposta crua do modelo. Investigação encontrou dois gaps distintos, os dois resolvidos
> reaproveitando mecanismos que o Captain já usa.

## Goal

Dar visibilidade real (não só uma string de motivo genérica) sobre o que acontece dentro de uma
execução do Scout — chamadas de LLM, chamadas de tool, erros — e garantir que o cliente nunca fique
sem nenhuma mensagem quando o Scout sai da conversa, em qualquer um dos dois caminhos de handoff.

## Contexto e causa raiz

### 1. Nenhuma instrumentação de LLM/tools no Scout

O Chatwoot core já tem uma pipeline completa de observabilidade pronta para isso —
`lib/integrations/llm_instrumentation.rb` (`instrument_llm_call`, `instrument_tool_call`,
`instrument_agent_session`) exportando spans via OpenTelemetry para o **Langfuse** (plataforma de
observabilidade de LLM, UI própria com prompt/resposta/tool calls/erros/latência por trace), gated
por `ChatwootApp.otel_enabled?` (checa `InstallationConfig` — `OTEL_PROVIDER`, `LANGFUSE_*`). O
Captain já usa essa mesma infra (`enterprise/app/services/captain/assistant/agent_runner_service.rb`,
`lib/captain/tool_instrumentation.rb`). `Custom::Scout::AgentRunner` e `Custom::Scout::Tools::*`
não usam nada disso hoje — zero instrumentação.

### 2. Cliente nunca recebe mensagem quando o Scout sai da conversa, em nenhum dos dois caminhos

- **Fail-safe** (`AgentRunner#perform_fail_safe_handoff`): cria só nota privada, nunca mensagem
  pública.
- **Handoff explícito** (`Custom::Scout::Tools::HandoverToHuman` → `HandoffService#perform`):
  também só cria nota privada. Pior ainda — `AgentRunner#process_response` tem
  `return if handover_tool.handoff_executed`, que pula `dispatch_outgoing_reply` **antes** de
  qualquer verificação — a resposta natural que o modelo gerou na mesma resposta estruturada
  (que poderia servir de despedida) é descartada, nunca chega ao cliente.

Confirmado contra a referência: `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb#perform_handoff`
(o fail-safe de esgotamento de cota do Captain) cria uma mensagem **pública** ("Transferring to
another agent for further assistance.") antes de `conversation.bot_handoff!`. O Scout nunca fez o
equivalente, em nenhum dos dois caminhos.

## Scope

### 17a — Instrumentação Langfuse/OTel

- `Custom::Scout::AgentRunner`: `include Integrations::LlmInstrumentation`; envolver a chamada
  principal (`chat.ask`, em `execute_chat`) com `instrument_agent_session`/`instrument_llm_call`,
  mesmo padrão usado por `enterprise/app/services/captain/assistant/agent_runner_service.rb`.
- `Custom::Scout::Tools::BaseTool` (ponto único, herdado por todas as tools): envolver a execução
  de cada tool com `instrument_tool_call`, mesmo padrão de `Captain::ToolInstrumentation` — é isso
  que vai capturar erro de rede ao chamar uma tool externa (`CallCustomApi`), que foi o gatilho
  original desta fase.
- Nenhuma UI nova, nenhum endpoint novo — reaproveita a UI do Langfuse (externa) via a mesma
  configuração que o Captain já usa.

### 17b — Mensagem pública no handoff (os dois caminhos)

- `AgentRunner#perform_fail_safe_handoff`: além da nota privada existente, criar uma mensagem
  pública (`Messages::MessageBuilder`, `message_type: 'outgoing', private: false`) avisando o
  cliente da transferência, antes de `conversation.bot_handoff!`.
- `Custom::Scout::HandoffService#perform`: mesma coisa — mensagem pública antes de
  `conversation.bot_handoff!` (dentro de `perform_handoff`, ou logo antes).
- Texto fixo, traduzível (`en.yml`/`pt_BR.yml`, conforme convenção do projeto para strings
  voltadas ao usuário) — não configurável por Scout nesta fase, mesmo texto estático que o Captain
  usa hoje para o caso equivalente.

## Out of scope

- Qualquer UI de debug própria do Chatwoot (painel interno, endpoint de inspeção) — a solução é
  usar o Langfuse já existente, não construir um substituto.
- Investigar/corrigir a causa raiz da falha de parsing específica que motivou esta fase (por que o
  modelo retornou uma resposta que não bateu com o schema esperado) — fora de escopo aqui; a
  instrumentação da 17a já deixa essa informação visível pra uma investigação futura, se precisar.
- Tornar o texto da mensagem de handoff configurável por Scout — texto fixo por enquanto, mesmo
  padrão do Captain.
- `tokens_consumed`/`messages_processed`/`Scout::FollowUpJob` — isso é `spec69.md` (Fase 11),
  telemetria agregada de produto, problema diferente deste.

## Acceptance criteria

- Com `OTEL_PROVIDER`/`LANGFUSE_*` configurados, uma conversa do Scout gera traces no Langfuse
  cobrindo: a chamada principal de LLM (prompt/resposta) e cada chamada de tool (nome, argumentos,
  resultado ou erro) — incluindo o caso de uma tool externa (`CallCustomApi`) falhando por erro de
  rede.
- Sem `OTEL_PROVIDER`/`LANGFUSE_*` configurados, nenhuma mudança de comportamento (mesmo
  `return yield unless otel_enabled?` de sempre — zero custo/risco quando desligado).
- Fail-safe: cliente recebe uma mensagem pública de transferência antes da conversa reabrir para
  fila humana.
- Handoff explícito (`handover_to_human`): cliente recebe uma mensagem pública de transferência —
  hoje não recebe nenhuma mensagem nesse caminho.
- Notas privadas continuam sendo criadas nos dois casos, sem alteração — a mensagem pública é
  adicional, não substitui o registro interno.
