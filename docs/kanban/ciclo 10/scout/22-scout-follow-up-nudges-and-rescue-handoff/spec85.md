# Fase 22 — Follow-up com Nudges e Handoff de Resgate por Inatividade

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §5, §9.1, §11 (Roadmap)
**Depends on**: Fase 09 (`bot_handoff!`/guarda de `pending?`, `Custom::Scout::HandoffService`), Fase 12
(Response Auditor — a correção da janela de corrida faz parte do escopo desta fase).
**Substitui**: a porção "`Scout::FollowUpJob`" da Fase 11
(`../11-follow-up-telemetry-e2e/spec69.md`, linhas 14-16; `spec60.md` §5 e §9.1). Generaliza "lead
parado em triagem, reengaja e nunca fecha" para "contato em silêncio em qualquer estágio aberto,
até 2 nudges, e no 3º silêncio faz handoff de resgate". A telemetria de tokens/cota e a suíte E2E da
Fase 11 continuam como item separado, fora do escopo aqui.

---

## Objetivo

Hoje, se o contato para de responder numa conversa `pending` com o Scout, nada acontece — a
conversa fica pendente indefinidamente até alguém notar manualmente. Esta fase adiciona um job
periódico que tenta reengajar o contato até 2 vezes e, se ainda assim não houver resposta, libera a
conversa para um humano e move a oportunidade para um estágio de resgate configurável.

## Contexto de investigação (por que este desenho)

O Captain (Enterprise, `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb`)
resolve um problema parecido — conversa `pending` parada além de um `inactivity_threshold_minutes`
— mas só tem um ponto de decisão: resolver ou transferir, nunca tenta reengajar antes. O cenário que
motivou esta fase (contato que simplesmente some) é diferente do que motivou a rejeição do
"job com verificação atrasada" em `../20-automatic-handoff-reevaluation/spec80.md` (aquele preview
tratava de o *modelo* esquecer de chamar `handover_to_human`, não de o *contato* ficar em silêncio)
— por isso reabrir esse mecanismo aqui é uma decisão nova, não uma reversão daquela.

O mecanismo de takeover humano já existe e é seguro, então este job não precisa reinventá-lo — só
respeitar `conversation.pending?` a cada execução: `custom/app/models/custom/message.rb`
(`mark_pending_conversation_as_open_for_human_response`) já vira `conversation.open!` assim que um
agente humano manda uma mensagem outgoing não-privada numa conversa `pending` com Scout ativo, e
tanto `ProcessMessageJob` quanto `AgentRunner` já rechecam `conversation_pending?` (leitura sem
cache) antes de agir.

## Decisões de desenho

1. **Tentativas fixas**: 2 nudges; na 3ª verificação sem resposta, faz o handoff de resgate. Não é
   configurável nesta fase.
2. **Determinístico, sem LLM** em nenhuma etapa (nem o nudge, nem a decisão final) — mesmo princípio
   já fixado em `spec80.md` para transições de negócio críticas.
3. **"Estágio de resgate" é uma configuração nova no Scout** (`rescue_stage_id`), não o
   `Opportunity#status` (`open/won/lost`, `opportunity.rb:21`). O Scout nunca marca a oportunidade
   como perdida por conta própria — só move para um estágio configurável onde um humano decide o
   próximo passo (inclusive marcar como `lost` manualmente, se for o caso).
4. **Contagem de tentativas é derivada do histórico de mensagens**, sem coluna nova de contador —
   evita drift de estado e migração desnecessária. Como a conversa só permanece `pending` enquanto
   nenhum humano respondeu, todas as mensagens outgoing não-privadas nesse trecho são do próprio
   Scout.
5. **Cadência escalonada e configurável, não um intervalo único fixo**: `follow_up_delay_hours`
   (campo único, `spec60.md` §9.1 original) nunca chegou a ser implementado — substituído aqui por
   `follow_up_delays_hours` (array), porque um atendimento comercial via WhatsApp não pode esperar
   24h para o primeiro sinal de vida. Cada posição do array é o tempo (em horas, desde a última
   mensagem visível) para disparar aquela etapa: `[2, 12, 24]` por padrão — nudge 1 em 2h de
   silêncio, nudge 2 se ainda em silêncio às 12h, handoff de resgate se ainda em silêncio às 24h. O
   teto de 24h para desistir permanece o mesmo da ideia original; o que muda é ter pontos de contato
   bem mais cedo em vez de só um em 24h.
6. **Indicador no card do Kanban**: badge "Scout" na oportunidade cuja conversa ativa está
   `pending` com o Scout aguardando resposta — lacuna real, não coberta pelo preview da Fase 15
   (que só cobre o sentido conversa→oportunidade).
7. **Corrige a janela de corrida do Response Auditor** (Fase 12) como parte desta fase, já que o
   escopo já mexe em `AgentRunner`.
8. **Mensagem pública dedicada no handoff de resgate**: em vez de cair no texto fixo genérico de
   `scout.handoff` ("Transferindo para que outro agente dê assistência."), este caminho específico
   passa uma mensagem própria para `HandoffService#perform(message:)` — o cliente nunca deve ler algo
   que soe como "você não respondeu, por isso..."; o tom é de continuidade de cuidado, não de cobrança.
9. **Respeita horário comercial do inbox**: não é hipotético — o job roda a cada 30 min o dia
   inteiro, então vai eventualmente cair fora do expediente se nada o impedir. Reaproveita
   `Inbox#out_of_office?` (`OutOfOffisable`, core, já usado pelo Scout em
   `system_prompts_service.rb:88` para avisar o cliente durante uma conversa ao vivo — mas nunca
   usado até agora para bloquear envio automático de um job). Contas sem horário comercial
   configurado (`working_hours_enabled?` falso) não mudam de comportamento — `out_of_office?` já
   retorna `false` sempre nesse caso.

## Escopo

### 1. Migration — `rescue_stage_id` e `follow_up_delays_hours` no Scout

`rescue_stage_id` segue o mesmo padrão de `qualified_stage_id`/`unqualified_stage_id`
(`custom/app/models/scout.rb:9-11`); `follow_up_delays_hours` substitui o campo único planejado
originalmente (`follow_up_delay_hours`, `spec60.md` §9.1) — nunca chegou a ser implementado, então
não há dado existente para migrar:

```ruby
class AddRescueStageAndFollowUpDelaysToScouts < ActiveRecord::Migration[7.1]
  def change
    add_reference :ichatr_scouts, :rescue_stage, foreign_key: { to_table: :ichatr_pipeline_stages, on_delete: :nullify }, index: true
    add_column :ichatr_scouts, :follow_up_delays_hours, :jsonb, null: false, default: [2, 12, 24]
  end
end
```

### 2. `Scout` model

```ruby
belongs_to :rescue_stage, class_name: 'PipelineStage', optional: true

validate :follow_up_delays_hours_must_be_ascending_positive_integers

private

def follow_up_delays_hours_must_be_ascending_positive_integers
  values = follow_up_delays_hours
  return errors.add(:follow_up_delays_hours, 'must be a non-empty array') if values.blank?

  valid = values.all? { |v| v.is_a?(Integer) && v.positive? } && values == values.sort && values.uniq == values
  errors.add(:follow_up_delays_hours, 'must be strictly ascending positive integers') unless valid
end
```

`rescue_stage` é `optional: true`, mesmo espírito de `qualified_stage`/`unqualified_stage`: uma conta
sem esse campo configurado simplesmente não tem essa automação habilitada — o job pula essa conta
(ver item 4) em vez de falhar.

### 3. `Api::V1::Accounts::ScoutsController` — permitir os novos campos

```ruby
# custom/app/controllers/api/v1/accounts/scouts_controller.rb:67
allowed = %w[default_pipeline_stage_id qualified_stage_id unqualified_stage_id rescue_stage_id handover_team_id]
# ...
scout_source.permit(*allowed, follow_up_delays_hours: [], required_custom_attribute_definition_ids: [])
```

### 4. `Custom::Scout::FollowUpJob` (novo)

```ruby
# custom/app/jobs/custom/scout/follow_up_job.rb
class Custom::Scout::FollowUpJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Scout.where(enabled: true).find_each do |scout|
      next if scout.rescue_stage_id.blank?

      stalled_conversations(scout).find_each { |conversation| process_conversation(scout, conversation) }
    end
  end

  private

  def stalled_conversations(scout)
    # Earliest possible threshold (delays_hours.first) so a conversation shows up as soon as it's
    # due for its next step; process_conversation re-derives the exact threshold per conversation
    # from its own attempt count, since different conversations can be at different steps.
    cutoff = scout.follow_up_delays_hours.first.hours.ago
    Conversation.pending
                .where(inbox_id: scout.inboxes.select(:id))
                .where('last_activity_at < ?', cutoff)
  end

  def process_conversation(scout, conversation)
    return unless conversation_pending?(conversation)
    return if conversation.inbox.out_of_office? # tenta de novo no próximo ciclo, dentro do horário

    opportunity = open_opportunity_for(conversation)
    return if opportunity.blank?

    attempts = follow_up_attempts(conversation)
    threshold = scout.follow_up_delays_hours[attempts]
    return if threshold.blank? # already past the last configured step, handled on a prior run
    return unless conversation.last_activity_at < threshold.hours.ago

    return send_nudge(conversation) if attempts < scout.follow_up_delays_hours.size - 1

    perform_rescue_handoff(scout, conversation, opportunity)
  end

  def open_opportunity_for(conversation)
    Opportunity.joins(:opportunity_conversations)
               .where(opportunity_conversations: { conversation_id: conversation.id }, status: :open)
               .order(updated_at: :desc)
               .first
  end

  def follow_up_attempts(conversation)
    conversation.messages
                .where(message_type: :outgoing, private: false)
                .order(created_at: :desc)
                .take_while { |m| !m.incoming? }
                .count { |m| m.content_attributes['scout_follow_up'] }
  end

  def send_nudge(conversation)
    Messages::MessageBuilder.new(
      nil, conversation,
      { content: I18n.t('conversations.scout.follow_up_nudge', locale: conversation.language.presence || conversation.account.locale),
        message_type: 'outgoing', private: false, content_attributes: { scout_follow_up: true } }
    ).perform
  end

  def perform_rescue_handoff(scout, conversation, opportunity)
    opportunity.update!(pipeline_stage_id: scout.rescue_stage_id)
    Custom::Scout::HandoffService.new(scout: scout, conversation: conversation).perform(
      reason: 'Contato não respondeu após as tentativas de reengajamento.',
      message: I18n.t('conversations.scout.follow_up_handoff', locale: conversation.language.presence || conversation.account.locale)
    )
  end

  def conversation_pending?(conversation)
    status = Conversation.uncached { Conversation.where(id: conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end
end
```

Notas de implementação:
- `take_while { |m| !m.incoming? }` para no primeiro incoming ao percorrer do mais recente pro mais
  antigo — isolando só as mensagens outgoing do trecho de silêncio atual.
- `perform_rescue_handoff` move o estágio **antes** de chamar `HandoffService`, para que a nota
  privada de transferência (que já referencia `Oportunidade ##{opp.id} - #{opp.title}`, ver
  `handoff_service.rb:62-67`) reflita o estágio já atualizado.
- `HandoffService#perform_handoff` já recheca `pending?` (sem cache) imediatamente antes de mandar a
  mensagem pública e chamar `bot_handoff!` (`handoff_service.rb:28-29`) — proteção extra contra o
  contato ou um humano agirem entre o `stalled_conversations` scan e a execução deste método.

### 5. `config/schedule.yml`

```yaml
# executed every 30 minutes
# checks for Scout conversations stalled waiting on the contact and sends
# follow-up nudges, escalating to a rescue handoff after 2 unanswered attempts
custom_scout_follow_up_job:
  cron: '*/30 * * * *'
  class: 'Custom::Scout::FollowUpJob'
  queue: scheduled_jobs
```

### 6. Correção da janela de corrida no Response Auditor

`custom/app/services/custom/scout/agent_runner.rb#process_audited_reply` — hoje, quando o auditor
está ativo, a chamada de LLM do auditor acontece depois do último recheck de `conversation_pending?`
(linha 77) e antes do dispatch, sem recheck entre os dois. Adiciona um recheck logo após o auditor
responder, cobrindo tanto `dispatch_outgoing_reply` (que hoje não tem nenhum guard) quanto
`trigger_handoff` (que já é protegido internamente por `HandoffService`, mas o recheck aqui evita a
chamada desnecessária):

```ruby
def process_audited_reply(reply_text, tools, chat)
  tool = handoff_requested_tool(tools)

  if @scout.feature_response_auditor?
    audit_result = Custom::Scout::ResponseAuditor.new(
      scout: @scout, conversation: @conversation, handoff_already_flagged: tool.present?
    ).audit(
      chat: chat, response_text: reply_text, message_history: audit_message_history(chat), recorded_tool_calls: recorded_tool_calls,
      available_tool_names: tools.map(&:name)
    )
    return if handle_auditor_non_proceed(audit_result)

    reply_text = audit_result[:reply]
    return unless conversation_pending?
  end

  return trigger_handoff(tool, reply_text) if tool.present?

  dispatch_outgoing_reply(reply_text)
end
```

### 7. i18n — mensagem de nudge e mensagem dedicada de handoff de resgate

`config/locales/en.yml` (ao lado de `scout.handoff`, linha 312-313):

```yaml
scout:
  handoff: 'Transferring to another agent for further assistance.'
  follow_up_nudge: "Hi! Just checking in — are you still there? I'm here whenever you're ready to continue."
  follow_up_handoff: "I'm connecting you with one of our team members so you get the attention you deserve — feel free to write back anytime, someone will follow up with you here."
```

`config/locales/pt_BR.yml` (linha 294-295):

```yaml
scout:
  handoff: 'Transferindo para que outro agente dê assistência.'
  follow_up_nudge: 'Oi! Só confirmando se você ainda está por aí — sigo por aqui assim que puder continuar.'
  follow_up_handoff: 'Vou te transferir para um de nossos consultores, que vai continuar seu atendimento com todo cuidado. Pode responder por aqui quando quiser — alguém vai falar com você em breve!'
```

`follow_up_handoff` é deliberadamente diferente do texto fixo genérico de `scout.handoff` — evita
qualquer formulação que soe como cobrança ("você não respondeu..."); o tom é de continuidade de
cuidado, reforçando que a conversa segue no mesmo lugar.

### 8. Indicador no card do Kanban — badge "Scout"

`custom/app/models/opportunity.rb#as_json` — novo campo derivado:

```ruby
'scout_engaged' => scout_engaged?,
```

```ruby
def scout_engaged?
  active_conversation&.pending? && active_conversation.inbox&.scout&.enabled? || false
end
```

`app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` — badge ao lado do badge de
status (linha 119-128), condicionado a `opportunity.scout_engaged`:

```vue
<span
  v-if="opportunity.scout_engaged"
  class="text-[10px] px-1.5 py-0.5 rounded-full font-medium bg-n-blue-3 text-n-blue-11"
>
  {{ $t('OPPORTUNITIES.BOARD.SCOUT_BADGE') }}
</span>
```

`app/javascript/dashboard/i18n/locale/en/opportunities.json` (dentro de `BOARD`, ao lado de
`STATUS`, linha 8-12) e o equivalente em `pt_BR/opportunities.json`:

```json
"SCOUT_BADGE": "Scout"
```

## Fora de escopo

- Telemetria de tokens/cota e suíte E2E ponta-a-ponta da Fase 11 (`spec69.md`) — continuam como
  item separado, ainda não implementado.
- Número de tentativas configurável (fixo em 2 nesta fase).
- Badge de status do Scout no header da própria conversa e link conversa→oportunidade (Fase 15,
  ainda em preview, escopo diferente — direção oposta ao badge do Kanban desta fase).
## Testes

- `custom/spec/jobs/custom/scout/follow_up_job_spec.rb`: conversa `pending` parada há mais do
  primeiro valor de `follow_up_delays_hours` com 0 nudges anteriores recebe o 1º nudge (mensagem com
  `content_attributes['scout_follow_up'] == true`); com 1 nudge anterior recebe o 2º; com 2 nudges
  anteriores, a oportunidade é movida para `rescue_stage_id` e a conversa recebe `bot_handoff!`.
  Cenário: `rescue_stage_id` ausente → conta é pulada, nenhum nudge enviado. Cenário: contato
  responde entre o scan e a execução (conversa não mais `pending`) → nenhuma ação. Cenário: só há
  oportunidade `won`/`lost` associada → conversa ignorada. Cenário: inbox fora do horário comercial
  (`out_of_office?` true) → nenhum nudge/handoff disparado nesta rodada, tentativa não avança.
- `custom/spec/services/custom/scout/agent_runner_spec.rb`: novo cenário — auditor ativo, humano
  responde durante a chamada do auditor (conversa deixa de ser `pending`) → nem `dispatch_outgoing_reply`
  nem `trigger_handoff` são chamados.
- `custom/spec/models/scout_spec.rb`: validação de `rescue_stage` (associação opcional, `on_delete: :nullify`).
- `custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb`: `rescue_stage_id` é aceito nos
  parâmetros permitidos.
- `spec/configs/schedule_spec.rb`: cobre a validação genérica de `config/schedule.yml` — conferir que
  a nova entrada passa sem ajuste adicional.
- Frontend: teste de `KanbanCard.vue` renderizando o badge "Scout" quando `scout_engaged: true` e
  omitindo quando `false`/ausente.

## Critérios de aceite

- Uma conversa `pending` com Scout, sem resposta do contato pelo 1º valor de `follow_up_delays_hours`
  (padrão: 2h), recebe uma mensagem de reengajamento (nudge 1).
- Se ainda sem resposta ao atingir o 2º valor (padrão: 12h de silêncio), recebe o nudge 2.
- Se ainda sem resposta ao atingir o 3º valor (padrão: 24h de silêncio), a oportunidade é movida
  para o estágio de resgate configurado no Scout e a conversa é liberada para atendimento humano
  (mensagem pública dedicada de handoff, sem tom de cobrança, + nota privada com o motivo).
- Se o contato responder a qualquer momento, ou um humano assumir a conversa, nenhuma ação adicional
  do job ocorre a partir daí.
- Contas sem `rescue_stage_id` configurado não são afetadas por este job.
- Nenhum nudge ou handoff de resgate é enviado fora do horário comercial configurado no inbox; a
  tentativa é reavaliada normalmente no próximo ciclo, já dentro do horário.
- O card da oportunidade no Kanban mostra o badge "Scout" enquanto a conversa ativa estiver
  `pending` com o Scout, e deixa de mostrar assim que houver handoff (humano ou automático).
- Um humano que responde durante a janela do Response Auditor não gera mais uma resposta duplicada
  ou um handoff incorreto do Scout.
