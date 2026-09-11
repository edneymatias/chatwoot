# Fase 16 — Ativação do Scout em Qualquer Canal

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §5, §8
**Depends on**: Phase 02 (Ferramentas Nativas & Pipeline — `Custom::ScoutListener`,
`Custom::Scout::ProcessMessageJob`), Phase 10 (Handoff Automático em Intervenção Humana —
`custom/app/models/custom/message.rb`, mesmo ponto de extensão `Message.prepend_mod_with('Message')`
usado aqui para `Inbox`).

> Esta fase nasceu de um bug encontrado ao testar o MVP ponta a ponta: conectar um Scout a uma
> inbox de Website Widget e iniciar uma conversa não engajava o bot. Investigação sistemática
> encontrou duas causas raiz independentes — ambas precisam ser corrigidas juntas, senão o sintoma
> persiste mesmo corrigindo só uma.

## Goal

Fazer o Scout funcionar em **qualquer tipo de inbox/canal**, não só WhatsApp — restrição que nunca
foi um requisito de produto. WhatsApp só é especial no escopo de atribuição de campanha (CTWA/Meta
Referral, seção 2 do spec60), porque atributos de anúncio (criativo, `ctwa_clid`, headline) só
existem fisicamente nesse canal — isso já é tratado de forma condicional dentro das tools
(`find_referral_message`/`Custom::ReferralAttributionService`, que simplesmente não encontram nada
em canais sem referral, sem precisar de nenhum gate explícito). Não há razão para o pipeline
principal do Scout — debounce, disparo de resposta, handoff — ser restrito a um canal.

## Causa raiz (achada via `superpowers:systematic-debugging`)

### 1. `Custom::ScoutListener` só processa mensagens de inbox WhatsApp

`custom/app/listeners/custom/scout_listener.rb:10`:
```ruby
return unless inbox&.channel_type == 'Channel::Whatsapp'
```
Esse listener é o **único** ponto de entrada que dispara `Custom::Scout::ProcessMessageJob`
(confirmado — nenhum outro lugar no código chama esse job). A restrição é deliberada e testada
(`custom/spec/listeners/custom/scout_listener_spec.rb`, teste `'ignores non-WhatsApp inboxes'`),
mas ficou de uma fase inicial de testes focada em WhatsApp e nunca foi generalizada.

### 2. Conversa nova nunca vira `pending` em nenhum canal, nem WhatsApp

Mais fundo que o primeiro — bloquearia qualquer canal, WhatsApp incluso, num cenário real (não
testado até agora porque as specs existentes forçam `status: :pending` direto na factory,
mascarando o problema). Toda a pipeline do Scout exige `conversation.status == 'pending'`
(`ScoutListener`, `ProcessMessageJob`, `AgentRunner`). Quem decide se uma conversa nasce `pending`
é `Conversation#determine_conversation_status` (`app/models/conversation.rb:293`), que só chama
`set_active_bot_conversation` **se `inbox.active_bot?` for true** — e `Inbox#active_bot?`
(`app/models/inbox.rb:180`) só olha `agent_bot_inbox`/hooks Dialogflow, mecanismo legado
completamente desconectado de `ScoutInbox`. Conectar um Scout a uma inbox
(`Api::V1::Accounts::Scouts::ScoutInboxesController#create`) só cria a linha pivô — nunca toca
nisso, então toda conversa nova numa inbox com Scout nasce `open` (default do schema), nunca
`pending`.

**Não vamos usar o mecanismo legado (Dialogflow/`agent_bot_inbox`) como base** — nosso mecanismo
precisa ser o mesmo já usado pelo Captain para o problema idêntico, não uma dependência do sistema
de bot antigo. Referência exata: `enterprise/app/models/enterprise/inbox.rb:11-17`:
```ruby
def active_bot?
  super || captain_active?
end

def captain_active?
  captain_assistant.present? && more_responses?
end
```
Via `Inbox.prepend_mod_with('Inbox')`, já existente em `app/models/inbox.rb:288` — ponto de
extensão livre, sem `custom/app/models/custom/inbox.rb` ainda.

## Scope

1. **`Custom::ScoutListener#message_created`**: remover o gate de `channel_type ==
   'Channel::Whatsapp'` — processa incoming/pública em qualquer canal, contanto que a inbox tenha
   Scout habilitado.
2. **Novo `custom/app/models/custom/inbox.rb`** (via `Inbox.prepend_mod_with('Inbox')`, mesmo
   padrão do Captain): `active_bot?` → `super || scout_active?`, onde `scout_active?` checa
   `scout&.enabled?` (sem tocar em `agent_bot_inbox`/Dialogflow).
3. Atualizar `custom/spec/listeners/custom/scout_listener_spec.rb`: o teste `'ignores non-WhatsApp
   inboxes'` deixa de fazer sentido como está — precisa virar o oposto (processa normalmente em
   inbox de outro canal, ex. Email ou Website Widget) ou ser removido, dependendo do que a
   suite cobrir depois do ajuste.
4. Nova spec para `Custom::Inbox#active_bot?` (`custom/spec/models/custom/inbox_spec.rb` ou
   equivalente): conversa criada numa inbox com `ScoutInbox` habilitado nasce `pending`; conversa
   em inbox sem Scout, ou com Scout desabilitado, mantém o comportamento atual (`open`, a menos
   que `agent_bot_inbox` legado esteja ativo — `super` preserva isso).

## Out of scope

- Qualquer ajuste em `Custom::ReferralAttributionService`/lógica de atribuição de campanha — já é
  condicional por natureza (não encontra referral fora de WhatsApp/Meta, sem precisar de gate).
- Migrar ou desativar o mecanismo legado `agent_bot_inbox`/Dialogflow — `super ||` preserva o
  comportamento existente para quem ainda usa isso; não estamos removendo, só adicionando ao lado.
- Qualquer mudança na Fase 15 (indicadores visuais, ainda em preview) — fora do escopo desta fase.

## Acceptance criteria

- Uma conversa nova, numa inbox de **qualquer canal** (Website Widget, Email, etc.) com um Scout
  habilitado vinculado, nasce com `status: pending`.
- Uma mensagem incoming pública nessa conversa dispara `Custom::Scout::ProcessMessageJob` via
  `Custom::ScoutListener`, independente do `channel_type` da inbox.
- Inbox sem Scout vinculado, ou com Scout desabilitado, mantém o comportamento atual sem mudança
  (conversa nasce `open`, a menos que o mecanismo legado `agent_bot_inbox` esteja ativo).
- Handoff automático em intervenção humana (Fase 10, `custom/app/models/custom/message.rb`)
  continua funcionando sem alteração — ele já depende só de `conversation.pending?` +
  `inbox.scout&.enabled?`, agnóstico a canal.
- Teste manual de ponta a ponta: inbox de Website Widget conectada a um Scout habilitado, iniciar
  conversa pelo widget, Scout responde.
