# Fase 20 — Mensagem de Handoff Natural e Contextual

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 09 (`09-required-qualification-attributes/...`) — `qualification_handoff_needed?`/
`trigger_qualification_handoff`, o mecanismo generalizado por esta fase. Phase 08
(`08-system-prompt-guardrails/spec71.md`) — `SystemPromptsService#guardrails_section`, onde a nova
diretriz é adicionada.
**Precedido por**: `spec-preview.md` (mesma pasta) — registrava a pergunta original ("manter,
atrasar ou eliminar o handoff mecânico?") e a normalização de 2026-08-30 (descartar o texto do
modelo em qualquer handoff, só a mensagem fixa). Este documento **substitui** a direção do preview:
a decisão sobre qual mecanismo decide o handoff fica como está (mecanismo mecânico mantido, ver
"Decisão sobre o mecanismo" abaixo) — o problema real é a qualidade da mensagem que o cliente vê, não
quem decide transferir.

---

## Objetivo

Hoje, toda transferência para humano — seja decidida pelo modelo (`handover_to_human`) ou disparada
mecanicamente (Fase 09, oportunidade entra no estágio qualificado) — mostra ao cliente exatamente a
mesma frase fixa (`I18n.t('conversations.scout.handoff')`, "Transferindo para que outro agente dê
assistência."), independente do motivo. Isso quebra o tom natural que o resto da conversa já tem
(reforçado pela Fase 18). Esta fase faz o texto do próprio modelo virar a mensagem pública de
transferência — nunca as duas juntas, nunca descartado por padrão — sem reabrir o bug "pergunta e
transfere" que motivou a normalização de 2026-08-30.

## Decisão sobre o mecanismo (fecha a pergunta do preview original)

O mecanismo mecânico (`OpportunityStageTransitionService#handle_post_save_handoff`,
`AgentRunner#qualification_handoff_needed?`) **permanece** — não é substituído por rede de segurança
atrasada nem eliminado. Ele é determinístico e nunca "esquece": está amarrado ao evento em si (a
oportunidade entrou no estágio qualificado), não a julgamento de LLM que pode falhar — exatamente
por isso foi criado (evidência original da Fase 18, conversas 20/22: Scout confirmava agendamento
sem nunca avisar um humano, cenário sem rastro nenhum). Trocar por confiar 100% no LLM
reintroduziria esse risco documentado sem nenhum ganho — a mensagem seca não vem de qual mecanismo
decide, vem de `HandoffService` sempre usar o mesmo texto fixo nos dois caminhos.

## Por que o texto do modelo é descartado hoje

Quando `handover_to_human` é chamado durante o tool-calling, `HandoffService` dispara a mensagem
pública **na hora**, dentro da própria execução da tool — antes de existir qualquer resposta final
estruturada (`chat.ask()` só termina de gerar `response`/`reasoning` depois que todas as tools já
rodaram). `AgentRunner#process_response` retorna assim que `handover_tool.handoff_executed` é
`true`, sem nunca fazer o parsing. O mecanismo mecânico tem o mesmo problema por um motivo diferente:
o texto do turno pode conter uma pergunta de qualificação (o bug original), então foi descartado por
segurança.

## Escopo

### 1. Nova diretriz de prompt — `SystemPromptsService#guardrails_section`

Estende o bullet "Fallback para humano" existente:

```ruby
'- Fallback para humano: Se você não souber a resposta, se o contexto for insuficiente ou se o lead solicitar atendimento humano, ' \
'utilize a ferramenta `handover_to_human`. Quando o turno for terminar em transferência para humano — seja por chamar ' \
'`handover_to_human`, seja porque a oportunidade acabou de ser movida para o estágio qualificado — sua resposta final deve ser ' \
'uma mensagem natural de encerramento: confirme o que foi registrado e explique que um humano vai continuar o atendimento a ' \
'partir daqui. Nunca faça uma pergunta nessa resposta — o cliente não terá a chance de respondê-la antes da transferência.'
```

Isso substitui a estratégia de descartar o texto por uma instrução explícita sobre o que escrever
nesse momento específico — a defesa contra "pergunta e transfere" passa a ser o modelo saber que está
encerrando, não a plataforma censurar o que ele disse.

### 2. `Custom::Scout::Tools::HandoverToHuman` — sinaliza em vez de executar

```ruby
class Custom::Scout::Tools::HandoverToHuman < Custom::Scout::Tools::BaseTool
  description 'Transfers the conversation to a human agent or team and stops AI responses'

  param :assignee_id, type: :integer, desc: 'ID of the specific human agent to assign', required: false
  param :team_id, type: :integer, desc: 'ID of the team to assign', required: false
  param :reason, type: :string, desc: 'Explanation of why the conversation is being transferred to a human', required: false

  attr_reader :handoff_needed, :handoff_assignee_id, :handoff_team_id, :handoff_reason

  def name
    'handover_to_human'
  end

  def execute(assignee_id: nil, team_id: nil, reason: nil)
    if playground?
      return "[Simulado] Atendimento transferido para humano#{reason.present? ? " (Motivo: #{reason})" : ''}."
    end

    @handoff_needed = true
    @handoff_assignee_id = assignee_id
    @handoff_team_id = team_id
    @handoff_reason = reason

    'A transferência será confirmada após sua resposta final. Escreva agora uma mensagem natural de encerramento, sem perguntas.'
  end
end
```

`handoff_executed` é removido (renomeado para `handoff_needed`, mesmo nome já usado por
`ManageOpportunity`/`MoveOpportunityStage` via `OpportunityStageTransitionService#handoff_needed`) —
os dois mecanismos passam a ser detectáveis pelo mesmo duck-type em `AgentRunner`.

### 3. `AgentRunner` — generaliza a detecção de handoff, sempre faz o parsing primeiro

```ruby
def generate_and_process_response
  tools = build_tools
  chat = setup_chat(tools)
  history = conversation_messages
  last_user_message = history.reverse.find(&:incoming?) || history.last
  add_history_to_chat(chat, history, last_user_message)
  response = execute_chat(chat, last_user_message)
  process_response(response, tools, chat: chat)
end

def process_response(response, tools, chat: nil)
  return unless conversation_pending?

  parsed = parse_structured_response(response&.content)
  return perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.') if parsed.blank?

  process_audited_reply(parsed[:response], tools, chat)
end

def process_audited_reply(reply_text, tools, chat)
  if @scout.feature_response_auditor?
    audit_result = Custom::Scout::ResponseAuditor.new(scout: @scout, conversation: @conversation).audit(
      chat: chat, response_text: reply_text, message_history: audit_message_history(chat), recorded_tool_calls: recorded_tool_calls
    )
    return if handle_auditor_non_proceed(audit_result)

    reply_text = audit_result[:reply]
  end

  handoff_tool = handoff_requested_tool(tools)
  return trigger_handoff(handoff_tool, reply_text) if handoff_tool

  dispatch_outgoing_reply(reply_text)
end

def handoff_requested_tool(tools)
  tools.find { |tool| tool.respond_to?(:handoff_needed) && tool.handoff_needed }
end

def trigger_handoff(tool, reply_text)
  Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).perform(
    message: reply_text,
    assignee_id: handoff_param(tool, :handoff_assignee_id),
    team_id: handoff_param(tool, :handoff_team_id),
    reason: handoff_param(tool, :handoff_reason) || 'Oportunidade movida para o estágio qualificado'
  )
end

def handoff_param(tool, method_name)
  tool.respond_to?(method_name) ? tool.public_send(method_name) : nil
end
```

`build_tools` passa a retornar só a lista de tools (não mais a tupla `[tools, handover]`) — nenhum
outro ponto do `AgentRunner` precisava da referência isolada ao `handover`. `qualification_handoff_needed?`
e `trigger_qualification_handoff` são removidos, substituídos pelos três métodos genéricos acima, que
atendem os dois mecanismos (`ManageOpportunity`/`MoveOpportunityStage` continuam expondo só
`handoff_needed`, sem os três atributos extras — `handoff_param` retorna `nil` nesse caso e
`trigger_handoff` cai no reason/assignee/team padrão, comportamento idêntico ao atual).

### 4. `Custom::Scout::HandoffService` — mensagem pública customizável

```ruby
def perform(assignee_id: nil, team_id: nil, reason: nil, message: nil)
  assign_team_and_user(assignee_id, team_id)
  handed_off = perform_handoff(message)
  create_transfer_note(reason) if handed_off
  generate_contact_memory if @scout.feature_memory?

  'Conversation transferred to human queue successfully.'
end

private

def perform_handoff(message)
  status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
  return false unless status == 'pending' || status == Conversation.statuses[:pending]

  send_public_handoff_message(message)
  @conversation.bot_handoff!
  true
end

def send_public_handoff_message(message)
  content = message.presence || I18n.t('conversations.scout.handoff', locale: conversation_locale)
  Messages::MessageBuilder.new(nil, @conversation, { content: content, message_type: 'outgoing', private: false }).perform
end
```

Fallback pro texto fixo só quando `message` vier em branco — mesmo princípio "fail closed" já usado
em `parse_structured_response`.

## Fora de escopo desta fase

- **`AgentRunner#perform_fail_safe_handoff`** (quota esgotada, erro não tratado, falha de parsing)
  continua usando sempre a mensagem fixa — não há resposta confiável do modelo nesses casos, é
  exatamente o cenário onde o texto fixo é a escolha certa.
- **`Custom::Scout::ResponseAuditor#execute_handoff`** (handoff decidido pelo `ActionClassifierService`,
  Fase 12) continua usando a mensagem fixa (`HandoffService.perform(reason: reason)`, sem `message:`)
  — esse handoff é uma decisão independente do texto que o modelo escreveu no turno (o classificador
  lê o histórico da conversa, não a resposta rascunhada), então reaproveitar o texto do modelo ali
  seria incoerente (ele pode não saber que a conversa vai ser transferida por esse caminho). Fica
  registrado aqui como decisão explícita, não esquecimento.
- Qualquer mudança na decisão de **qual** mecanismo dispara handoff — ver "Decisão sobre o
  mecanismo" acima; o mecanismo mecânico permanece como está.
- Sanitização/validação do texto do modelo antes de usá-lo como mensagem pública (ex: checar se
  termina em "?") — regra hardcoded e frágil, vai contra o princípio já estabelecido no projeto de
  não usar pattern-matching sobre linguagem natural; a defesa é a diretriz de prompt (item 1).

## Testes

- `custom/spec/services/custom/scout/tools/handover_to_human_spec.rb`: `execute` fora do playground
  não chama mais `HandoffService` diretamente — só seta os atributos (`handoff_needed`,
  `handoff_assignee_id`, `handoff_team_id`, `handoff_reason`) e retorna a string de instrução ao
  modelo.
- `custom/spec/services/custom/scout/handoff_service_spec.rb`: novo `it` confirmando que `message:`
  quando presente vira o conteúdo da mensagem pública; `it` confirmando que `message` em branco/nil
  cai no texto fixo do `I18n`.
- `custom/spec/services/custom/scout/agent_runner_spec.rb`: cenário de handoff via
  `handover_to_human` — a mensagem pública final deve ser o `response` parseado do modelo, não o
  texto fixo. Cenário de handoff mecânico (estágio qualificado) — mesma verificação. Cenário onde o
  `ActionClassifierService` decide handoff (Fase 12) — mensagem pública continua sendo o texto fixo
  (comportamento preservado, ver Fora de escopo).
- `custom/spec/services/custom/scout/system_prompts_service_spec.rb`: novo `it` confirmando a
  presença da diretriz estendida em "Fallback para humano".
- Verificação comportamental (mesmo padrão da Fase 18/`spec79.md`): replay via
  `Custom::Scout::PlaygroundRunner` da conversation_id 43/display_id 41 (a evidência original do
  preview) para conferir que a mensagem final não repete mais o texto fixo genérico.

## Critérios de aceite

- Uma conversa que termina em handoff (via `handover_to_human` direto, ou via qualificação de
  estágio) mostra ao cliente o texto que o próprio modelo escreveu naquele turno — nunca o texto
  fixo e o texto do modelo juntos.
- Se o parsing da resposta falhar, ou a resposta vier vazia, a mensagem pública cai no texto fixo do
  `I18n` — nenhuma regressão de robustez.
- Nenhuma resposta que resulta em handoff termina em pergunta (reforçado pela diretriz de prompt,
  verificado via replay comportamental).
- O handoff disparado pelo `ActionClassifierService` (Fase 12) continua mostrando o texto fixo —
  comportamento inalterado, documentado como decisão, não regressão.
- `perform_fail_safe_handoff` (falhas de sistema) continua sempre usando o texto fixo.
- Nenhuma mudança na decisão de qual mecanismo dispara handoff — mecânico e por julgamento de LLM
  continuam coexistindo como hoje.
