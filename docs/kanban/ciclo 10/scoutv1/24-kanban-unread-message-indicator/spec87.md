# Fase 24 — Indicador de Mensagem Não Lida no Card do Kanban

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 22 (`22-scout-follow-up-nudges-and-rescue-handoff/spec85.md`) — reaproveita e
generaliza o mecanismo de broadcast em tempo real do badge "Scout" (`Opportunity#broadcast_scout_badge_refresh`,
`Custom::Concerns::Conversation#refresh_linked_opportunities_scout_badge`), implementado como parte
daquela fase.

> **Nota de escopo**: esta feature não é exclusiva do Scout — é um indicador genérico do Kanban
> ("esta oportunidade tem mensagem não lida na conversa vinculada"). Fica registrada aqui, dentro da
> pasta do Scout, porque sua implementação está diretamente acoplada à infraestrutura de broadcast
> em tempo real que a Fase 22 acabou de criar para o badge "Scout" — não porque dependa de nenhuma
> lógica do Scout em si.

---

## Objetivo

Hoje, um agente olhando o quadro Kanban não tem nenhum sinal visual de que uma oportunidade tem
mensagem nova não lida na conversa vinculada — precisa abrir cada card pra descobrir. Adicionar um
indicador visual (ponto piscante, bem lento) no card, que aparece quando há mensagem não lida na
`active_conversation` e desaparece assim que ela é lida — em tempo real, sem precisar recarregar o
board.

## Contexto de investigação (por que este desenho)

- O core do Chatwoot já tem tudo que precisamos pra saber "tem mensagem não lida": `Conversation#unread_incoming_messages`
  (`app/models/conversation.rb:204`, baseado em `agent_last_seen_at` vs. timestamp das mensagens) —
  mesmo mecanismo que já alimenta os badges de não lida da caixa de entrada padrão. Não precisa de
  nenhuma lógica nova de "o que conta como não lida".
- A Fase 22, ao implementar o badge "Scout" em tempo real, já resolveu o problema mais difícil desta
  fase: como notificar o card do Kanban de uma mudança que não toca o registro da `Opportunity`
  diretamente. O mecanismo (`custom/app/models/custom/concerns/conversation.rb`):
  ```ruby
  after_commit :refresh_linked_opportunities_scout_badge, on: :update, if: :saved_change_to_status?

  def refresh_linked_opportunities_scout_badge
    opportunities.find_each(&:broadcast_scout_badge_refresh)
  end
  ```
  e em `Opportunity`:
  ```ruby
  def broadcast_scout_badge_refresh
    ActionCableBroadcastJob.perform_later(["account_#{account_id}"], 'opportunity_updated', as_json)
  end
  ```
  Isso bypassa deliberadamente `broadcast_opportunity_updated`/o barramento Wisper (que também é o
  que `Custom::AutomationRuleListener` escuta pra automation rules de "oportunidade atualizada") —
  motivo pelo qual não dá pra simplesmente re-salvar a Opportunity para disparar seu
  `after_commit` padrão.
- **O que muda nesta fase**: "mensagem não lida" muda de estado por dois eventos que o mecanismo
  atual não cobre:
  1. Mensagem nova incoming chega — não toca `Conversation#status` nem `agent_last_seen_at`, só o
     conjunto de mensagens. O `after_commit` atual (guardado por `saved_change_to_status?`) não
     dispara.
  2. Agente lê a conversa — atualiza `Conversation#agent_last_seen_at`, não `status`. Também não
     dispara o guard atual.
- Confirmado: `Message.include_mod_with('Concerns::Message')` já existe no core
  (`app/models/message.rb:464`) — ou seja, um `Custom::Concerns::Message` (seguindo exatamente a
  mesma convenção de `Custom::Concerns::Conversation`) já seria automaticamente incluído em
  `Message`, sem precisar tocar em nenhum arquivo core. Nunca existiu esse arquivo antes; esta fase
  cria o primeiro.
- `unread_incoming_messages` retorna um Array (via `.last(10)`, já limitado a 10 por design do
  core) — usar `.any?`, não `.exists?` (que não existe em Array).

## Decisões de desenho

1. **Reaproveitar e generalizar o mecanismo de broadcast da Fase 22**, não duplicar um segundo
   pipeline de broadcast paralelo. Isso implica um pequeno rename honesto, já que o método deixa de
   servir só o badge do Scout:
   - `Opportunity#broadcast_scout_badge_refresh` → `Opportunity#broadcast_kanban_badges_refresh`.
   - `Custom::Concerns::Conversation#refresh_linked_opportunities_scout_badge` →
     `#refresh_linked_opportunities_kanban_badges`.
   - O payload transmitido continua sendo `as_json` inteiro (já que outras mudanças de campo se
     beneficiam do mesmo broadcast) — nenhuma mudança de formato, só de nome.
2. **Dois gatilhos de `after_commit`, não um só**: leitura da conversa (`agent_last_seen_at`) entra
   como uma condição adicional no `after_commit` já existente em `Custom::Concerns::Conversation`;
   mensagem nova precisa de um gatilho próprio em `Message`, porque nenhuma coluna da própria
   `Conversation` muda quando uma mensagem chega.
3. **Ponto piscante, não pílula de texto** — decisão já fechada na conversa: badges de estado
   (Scout) continuam como pílula com texto; indicador de notificação/urgência (não lida) é um ponto,
   convenção universal, sem precisar de rótulo pra ser entendido.
4. **Animação bem lenta**, via classe Tailwind com valor arbitrário de duração (`animate-pulse
   [animation-duration:3s]`) — ainda é utility class, não CSS solto, respeita a regra do projeto de
   "Tailwind only".

## Escopo

### 1. `Opportunity` — campo derivado e rename

```ruby
# custom/app/models/opportunity.rb
def as_json(options = {})
  super(options).merge(
    # ...campos existentes...
    'has_unread_messages' => has_unread_messages?
  ).merge(campaign_json)
end

def has_unread_messages?
  active_conversation&.unread_incoming_messages&.any? || false
end

# Pushes a fresh 'opportunity_updated' payload straight to the account's ActionCable channel so the
# Kanban card's "Scout" badge and unread-message dot (derived from scout_engaged?/has_unread_messages?)
# update in real time. Deliberately bypasses `broadcast_opportunity_updated`/`dispatch_event`'s Wisper
# bus — see Custom::Concerns::Conversation for why.
def broadcast_kanban_badges_refresh
  ActionCableBroadcastJob.perform_later(["account_#{account_id}"], 'opportunity_updated', as_json)
end
```

### 2. `Custom::Concerns::Conversation` — segundo gatilho

```ruby
# custom/app/models/custom/concerns/conversation.rb
after_commit :refresh_linked_opportunities_kanban_badges, on: :update,
             if: -> { saved_change_to_status? || saved_change_to_agent_last_seen_at? }

private

def refresh_linked_opportunities_kanban_badges
  opportunities.find_each(&:broadcast_kanban_badges_refresh)
end
```

### 3. `Custom::Concerns::Message` (novo arquivo)

```ruby
# custom/app/models/custom/concerns/message.rb
module Custom::Concerns::Message
  extend ActiveSupport::Concern

  included do
    after_commit :refresh_linked_opportunities_kanban_badges, on: :create, if: -> { incoming? && !private? }
  end

  private

  # A new incoming message doesn't touch the Conversation's own broadcastable columns (status,
  # agent_last_seen_at), so Custom::Concerns::Conversation's after_commit never fires here — the
  # Kanban card's unread-message dot would stay stale until something else changes the conversation.
  # Push a fresh broadcast for each linked opportunity directly from the message.
  def refresh_linked_opportunities_kanban_badges
    conversation.opportunities.find_each(&:broadcast_kanban_badges_refresh)
  end
end
```

Nenhuma mudança em `app/models/message.rb` — `Message.include_mod_with('Concerns::Message')`
(linha 464) já existe no core e passa a encontrar este arquivo automaticamente.

### 4. `KanbanCard.vue` — ponto piscante

Perto do badge de status (linha 119-140 da versão atual), condicionado a
`opportunity.has_unread_messages`:

```vue
<span
  v-if="opportunity.has_unread_messages"
  v-tooltip.top="$t('OPPORTUNITIES.BOARD.UNREAD_TOOLTIP')"
  class="size-2 rounded-full bg-n-ruby-9 animate-pulse [animation-duration:3s]"
/>
```

### 5. i18n

`app/javascript/dashboard/i18n/locale/en/opportunities.json` (dentro de `BOARD`, ao lado de
`SCOUT_BADGE`) e o equivalente em `pt_BR`:

```json
"UNREAD_TOOLTIP": "Unread message"
```
```json
"UNREAD_TOOLTIP": "Mensagem não lida"
```

## Fora de escopo

- Contagem de mensagens não lidas (número no badge) — só presença/ausência (booleano), igual ao
  pedido original.
- Qualquer mudança em como `unread_incoming_messages`/`agent_last_seen_at` são calculados no core —
  reaproveitados como estão.
- Aplicar o mesmo indicador em outros lugares da UI (lista de oportunidades, drawer) — escopo restrito
  ao card do Kanban, conforme pedido.

## Testes

- `custom/spec/models/opportunity_spec.rb`: `has_unread_messages?` retorna `true` quando a
  `active_conversation` tem mensagem incoming após `agent_last_seen_at`; `false` quando não há
  conversa ativa, quando não há mensagem incoming, ou quando todas já foram lidas.
- `custom/spec/models/custom/concerns/conversation_spec.rb`: novo `it` confirmando que atualizar
  `agent_last_seen_at` dispara `broadcast_kanban_badges_refresh` nas oportunidades vinculadas (além
  do `saved_change_to_status?` já coberto pela Fase 22).
- `custom/spec/models/custom/concerns/message_spec.rb` (novo): mensagem incoming não-privada criada
  dispara o broadcast para as oportunidades da conversa; mensagem outgoing ou privada não dispara.
- `app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js`: ponto piscante
  renderizado quando `has_unread_messages: true`, ausente quando `false`/ausente.

## Critérios de aceite

- Uma oportunidade cuja conversa ativa tem mensagem incoming não lida mostra o ponto piscante no
  card do Kanban.
- O ponto desaparece assim que a conversa é marcada como lida (`agent_last_seen_at` atualizado) —
  em tempo real, sem recarregar o board.
- O ponto aparece assim que uma nova mensagem incoming chega numa conversa já visível no board — em
  tempo real, sem recarregar o board.
- O badge "Scout" continua como pílula de texto, sem alteração visual — só o indicador de não lida
  usa o ponto piscante.
- A animação do ponto é visivelmente mais lenta que o `animate-pulse` padrão do Tailwind.
