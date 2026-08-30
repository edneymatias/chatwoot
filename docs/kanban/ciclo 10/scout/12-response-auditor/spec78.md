# Fase 12 — Auditor de Resposta

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 08 (`08-system-prompt-guardrails/spec71.md`) — ponto único de interceptação
`AgentRunner#process_response` e o schema estruturado `{reasoning, response}`. Phase 02
(`02-native-tools-and-pipeline/spec63.md`) — tools cujo uso real precisa ser auditado.
**Precedido por**: `spec-preview.md` (mesma pasta) — registra a arquitetura de referência do
Captain (`V1ActionClassifier`/`V1FalsePromiseHandler`) e a condição original de avanço (telemetria
formal da Fase 11). Este documento substitui essa condição por evidência direta e adapta a
arquitetura a um sintoma que o Captain não cobre (ver seção "Diferenças em relação ao Captain").

## Contexto: evidência que motivou a saída do preview

Testes reais em produção (self-hosted dev stack) reproduziram, de forma consistente, um padrão que
o guardrail de prompt fixo da Fase 08 ("Anti-falsa-promessa") não cobre:

- **Afirmação retroativa de ação não executada** (oportunidade 9): o `reasoning`/`response` do
  modelo dizia repetidamente "atualizei a oportunidade", "avancei para o estágio Agendado", "já
  registrei a origem" — mas `manage_opportunity`/`move_opportunity_stage` só foram chamados **uma
  vez**, no início da conversa. `updated_at == created_at` no registro confirma que nada foi salvo
  depois. O guardrail "Anti-falsa-promessa" da Fase 08 só instrui contra promessa de trabalho
  **futuro** ("vou verificar e te aviso") — não cobre uma afirmação no passado sobre algo que nunca
  aconteceu.
- **Promessa de handoff não cumprida**: em outra conversa, o modelo escreveu "vou encaminhar para
  um atendente humano" sem chamar `handover_to_human` — a conversa ficou presa em `pending`
  indefinidamente, sem nota interna, sem transferência real.

Essas duas conversas substituem a condição original do preview ("telemetria da Fase 11 evidenciar
em produção") — evidência direta e reproduzível de comportamento real é justificativa mais forte
que uma métrica agregada ainda não implementada.

## Diferenças em relação ao Captain (adaptações necessárias)

A arquitetura de referência (`enterprise/app/services/captain/llm/assistant_action_classifier_service.rb`,
`assistant_false_promise_service.rb`, `enterprise/lib/captain/assistant_false_promise_schema.rb`) foi lida
por completo para este desenho (read-only, mesma ressalva de licenciamento das fases anteriores — não
reaproveitada/copiada como texto de produto). Duas diferenças relevantes, identificadas na leitura:

1. **Grounding em tool calls reais.** O detector de falsa-promessa do Captain
   (`AssistantFalsePromiseService#detect`) é **puramente textual** — recebe só o histórico da
   conversa e o texto da resposta (`AssistantResponseInspectionHelpers#assistant_response_inspection_prompt`),
   nunca a lista de tool calls executadas. Isso funciona para o sintoma que o Captain audita
   (promessa de trabalho futuro, detectável só pelo texto), mas **não teria capturado o bug real
   observado no Scout** — um juiz puramente semântico não tem como saber se `manage_opportunity`
   foi de fato chamado ou não. O detector do Scout precisa receber a lista real de tool calls do
   turno como contexto adicional, e sua categoria de decisão precisa cobrir afirmação retroativa
   ("já fiz X"), não só promessa futura.
2. **Modelo único por conta.** O detector do Captain fixa um modelo específico
   (`DETECTOR_MODEL = 'gpt-5.2'`), independente do que o assistente principal usa. O Scout não pode
   fazer isso — a Fase 06 já estabeleceu que uma conta usa um único provedor/chave
   (`ScoutAccountConfig`). Os dois auditores do Scout usam `@scout.llm_chat(temperature: 0.0)`, o
   mesmo provedor configurado da conta.

## Rastreamento de tool calls do turno (pré-requisito para o detector)

`Custom::Scout::PlaygroundRunner#execute_and_record` (linhas 70-93) já resolve esse problema para o
modo de simulação: embrulha `execute` de cada tool e grava `{tool_name:, arguments:, result:}` numa
lista por execução. Em vez de introduzir um segundo mecanismo (ex: inspecionar
`chat.messages`/`RubyLLM::ToolCall` diretamente), esta fase **extrai esse padrão** para um módulo
compartilhado (ex: `Custom::Scout::Tools::CallRecorder`, incluído tanto por `AgentRunner` quanto por
`PlaygroundRunner`), usado para instrumentar as tools de produção durante o turno. O
`AgentRunner` passa a manter `@recorded_tool_calls` (lista, escopo por turno) da mesma forma que o
`PlaygroundRunner` já mantém `recorded_tool_calls`.

## Escopo

### 1. `Custom::Scout::ActionClassifierService`

Nova classe, uma chamada de LLM independente do texto da resposta. Recebe histórico da conversa
(mesmo formato usado em `SystemPromptsService`/telemetria) e decide `continue`/`handoff` via
`with_schema`. Reasons adaptados ao domínio comercial do Scout (não copia os reasons de suporte do
Captain): pedido explícito de atendimento humano, oferta de humano aceita, frustração/loop
repetido, assunto fora do escopo comercial travado na Fase 08, entre outros a fechar na
implementação. Roda sempre que a flag está ligada e a conversa segue `pending`.

Se `action == 'handoff'`: chama `Custom::Scout::HandoffService#perform(reason: action_reason)` —
o mesmo caminho que o tool `handover_to_human` usaria se o modelo o tivesse chamado. Não é tratado
como falha de sistema (mensagem "📋 Transferência", não "⚠️ [IA Pausada]").

### 2. `Custom::Scout::ClaimConsistencyService`

Nova classe (adaptação do `AssistantFalsePromiseService` do Captain — não é uma porta 1:1, ver
seção de diferenças acima). Recebe histórico da conversa, o texto da resposta gerada, e a lista de
tool calls reais do turno (`@recorded_tool_calls`). Decide via `with_schema`:

- `safe` — resposta consistente com o que foi de fato executado.
- `false_promise` — promete trabalho futuro sem tool call correspondente (mesma categoria do
  Captain).
- `false_completed_action` — **categoria nova**: afirma que uma ação já foi executada/concluída
  (atualização de oportunidade, mudança de estágio, envio de algo) sem a tool call correspondente
  aparecer na lista real do turno.

### 3. Orquestração — `Custom::Scout::ResponseAuditor`

Nova classe que encapsula os dois auditores e o laço de regenerar-e-reverificar, chamada uma única
vez a partir de `AgentRunner#process_response` (Fase 08), depois do parsing bem-sucedido e antes de
`dispatch_outgoing_reply` — sem novo ponto de criação de mensagem, conforme já garantido pela Fase
08. Mantém o `AgentRunner` enxuto, mesmo princípio já aplicado à extração do
`SystemPromptsService`.

Fluxo (mesma ordem do `ResponseBuilderJob` do Captain: classificador de ação sempre primeiro,
detector de consistência depois, só se a conversa ainda está pendente):

```
ActionClassifier (se pending)
  → handoff? → HandoffService.perform, encerra o turno.
ClaimConsistency (se pending e sem handoff)
  → inconsistente (false_promise | false_completed_action)?
    → chat.ask(repair_instruction)   # mesmo objeto chat: histórico, tools e schema já carregados;
                                       # o modelo pode de fato chamar a tool agora, não só reescrever o texto
    → ActionClassifier de novo (se pending)
    → ClaimConsistency de novo (reverificação) → ainda inconsistente?
        → AgentRunner#perform_fail_safe_handoff (mesmo caminho de falha já usado na Fase 08)
```

A instrução de reparo é uma mensagem interna (nunca visível ao cliente), reutilizando o mesmo
`chat` (com tools e schema já registrados) em vez de reconstruir um novo histórico do zero como o
Captain faz — simplificação possível porque o `AgentRunner` já mantém um único objeto `chat` vivo
por turno.

Pior caso: até 4 chamadas de LLM extras num único turno (classificador + detector + regeneração +
reverificação), mesma ordem de grandeza estimada no preview original para a arquitetura do Captain.

### 4. Feature flag

Nova coluna booleana em `ichatr_scouts` (migration em `db/migrate`, mesmo padrão de
`feature_memory`): `feature_response_auditor`, default `false`. Um único flag liga os dois
auditores juntos — não replica os dois flags independentes por conta que o Captain usa
(`captain_v1_action_classifier`, `captain_false_promise_harness_enabled`).

### 5. Falha do próprio auditor

Herda o critério de aceite já registrado no preview original: falha de qualquer chamada do auditor
(exceção, resposta inválida do schema) é capturada (`rescue StandardError`,
`ChatwootExceptionTracker`, log), e a resposta original segue para o cliente **sem auditoria** —
a auditoria nunca é o motivo de uma resposta não ser entregue. Isso é diferente de "auditor detectou
inconsistência", que aciona o fluxo de handoff acima.

### 6. Quota e telemetria

As chamadas extras do auditor consomem tokens reais do provedor, capturados pela telemetria de
tokens da Fase 11 (via `instrument_llm_call`, já usado em `AgentRunner`/tools). Não incrementam
`responses_quota`/`responses_consumed` — esse contador continua medindo só a resposta final
entregue ao cliente, incrementado uma vez por turno em `dispatch_outgoing_reply`, como hoje.

## Fora de escopo desta fase

- `PlaygroundRunner` não roda os dois auditores — só o `AgentRunner` de produção. A extração do
  mecanismo de rastreamento de tool calls (`CallRecorder`) é compartilhada porque simplifica o
  código, não porque o Playground precisa auditar respostas nesta fase.
- UI para visualizar resultados de auditoria (histórico de classificações, taxa de handoff
  forçado). Por ora, mesmo padrão da Fase 08: só logado (`Rails.logger.info`/`.warn`), sem
  persistência estruturada nova.
- Ajuste fino dos `action_reason`/decisões dos schemas além do necessário para os dois sintomas
  documentados — a lista final de reasons é fechada na implementação, mas não é redesenhada como
  taxonomia genérica de suporte (o Captain tem 12 reasons pensados pra FAQ/suporte; o Scout não
  precisa replicar todos).
- Qualquer mudança na quota de respostas (`responses_quota`) para refletir o custo real de LLM do
  auditor — groundwork de billing não é escopo desta fase (mesma ressalva já registrada na Fase 11,
  `11-follow-up-telemetry-e2e/spec69.md`).

## Critérios de aceite

- Com a flag desligada (default), o comportamento é idêntico ao de hoje — nenhuma chamada extra de
  LLM, nenhuma mudança de fluxo.
- Com a flag ligada: uma resposta que afirma uma ação de oportunidade/estágio concluída sem a tool
  call correspondente no turno é detectada como `false_completed_action`, o sistema tenta
  regenerar com instrução de reparo, e reverifica o resultado.
- Com a flag ligada: uma resposta que promete encaminhar para humano sem chamar
  `handover_to_human` é detectada, regenerada, e — se persistir — cai no fail-safe handoff
  (`perform_fail_safe_handoff`), nunca fica presa em `pending` indefinidamente.
- Com a flag ligada: o classificador de ação identifica pedido explícito de atendimento humano
  mesmo quando o texto da resposta do modelo não sinaliza handoff, e aciona
  `HandoffService#perform` (não o caminho de fail-safe).
- Falha de qualquer chamada do auditor (exceção, schema inválido) nunca impede a entrega da
  resposta original ao cliente — é logada e a auditoria é pulada nesse turno.
- Nenhum novo ponto de criação de `Message` fora de `AgentRunner#process_response`/os dois
  serviços de handoff já existentes (`HandoffService`, `perform_fail_safe_handoff`).
- `responses_consumed` não é incrementado mais de uma vez por turno, independente de quantas
  chamadas de auditor/regeneração ocorreram.
