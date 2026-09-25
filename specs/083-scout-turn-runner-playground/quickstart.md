# Quickstart: Scout V2 Turn Runner and Qualification Playbook (Playground)

Run inside the `rails` container (`AGENTS.md`):
`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec <path>` for specs,
or `docker compose exec rails bundle exec rails console` for the manual scenarios below.

## Prerequisites

- `scout_v2` feature flag entry exists in `config/features.yml` (`enabled: false` by default).
- `custom/playbooks/qualificacao.md` present and passing boot validation (brief 01's
  `Custom::ScoutV2::Playbook::Validator`, unchanged this phase — a broken file still fails boot,
  not a conversation).
- No migration to run — this feature adds no table/column (research.md D2).

## Scenario 1 — A v2 turn makes exactly one top-level LLM call and assembles the right prompt/tools (US1)

```ruby
account = Account.create!(name: "Quickstart")
account.enable_features('scout', 'scout_v2')
stage = PipelineStage.create!(account: account, name: "Aberto", position: 0)
scout = Scout.create!(account: account, name: "Scout", default_pipeline_stage: stage, qualified_stage: stage, unqualified_stage: stage)
field = CustomAttributeDefinition.create!(account: account, attribute_display_name: "Orçamento", attribute_key: "orcamento", attribute_model: :opportunity_attribute, attribute_display_type: :text)
scout.sync_required_attribute_ids!([field.id])

inbox = Inbox.create!(account: account, name: "WA", channel: Channel::Api.create!(account: account))
ScoutInbox.create!(scout: scout, inbox: inbox)
contact = Contact.create!(account: account, name: "Lead")
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
opportunity = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage,
  origin_conversation: conversation, active_conversation: conversation, title: "Deal", status: :open)

# Double the LLM client per the Independent Test wording — no live model call.
fake_response = OpenStruct.new(content: "Olá! Poderia me informar o orçamento disponível?")
fake_chat = instance_double(RubyLLM::Chat, with_instructions: nil, with_tool: nil, add_message: nil, ask: fake_response)
allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
allow(fake_chat).to receive(:with_tool).and_return(fake_chat)
allow(scout).to receive(:llm_chat).and_return(fake_chat)

result = Custom::ScoutV2::TurnRunner.new(scout: scout, conversation: conversation, message: "oi", message_history: []).perform
result[:reply]        # => "Olá! Poderia me informar o orçamento disponível?"
fake_chat             # with_instructions called once, containing qualificacao.md's body + "Orçamento"
                       # with_tool called exactly twice: search_knowledge_base + manage_opportunity
                       # ask called exactly once (FR-011, SC-001)

ScoutConversationState.for_conversation(conversation).active_playbook    # => "qualificacao"
ScoutConversationState.for_conversation(conversation).activation_reason  # => "state"
```

**Expected outcome**: exactly one `ask` call; assembled instructions contain `qualificacao`'s body
and the pending "Orçamento" field, never the v1 guardrails block; tool catalog is exactly
`[search_knowledge_base, manage_opportunity]`; `ScoutConversationState` persisted with
`active_playbook: "qualificacao"`, `activation_reason: "state"` — before `result` is returned.

## Scenario 2 — No playbook matches: minimal baseline prompt, no mutation tool (Edge Case #1, FR-019)

Same setup, but skip creating the `Opportunity` (so `opportunity_open` never matches).

```ruby
result = Custom::ScoutV2::TurnRunner.new(scout: scout, conversation: conversation, message: "oi", message_history: []).perform
# with_instructions called with the fallback constant only
# with_tool called exactly once: search_knowledge_base only
ScoutConversationState.for_conversation(conversation).active_playbook # => nil
```

## Scenario 3 — Playground turn reuses the same sandbox conversation across calls (US3, edge case #3)

```ruby
conversation = Custom::ScoutV2::PlaygroundConversation.for(scout)
conversation2 = Custom::ScoutV2::PlaygroundConversation.for(scout)
conversation.id == conversation2.id # => true — same conversation reused, no new Contact/Inbox created
conversation.inbox.scout.id == scout.id # => true — RoutingSnapshot::Builder's ctx.scout resolves correctly
```

Send two playground turns in sequence (real `manage_opportunity` tool call recorded via a
double'd `chat.ask` that returns a tool-call response, or by calling `execute` directly on a
constructed `ManageOpportunity` tool against `conversation`) and confirm:
- The `Opportunity` created by turn 1's `manage_opportunity` call is the same row turn 2's
  `RoutingSnapshot::Builder` reads back as `ctx.opportunity` (via `conversation.active_opportunity`).
- No `Message` row exists on `conversation` after either turn (`conversation.messages.count == 0`,
  research.md D3) — confirms no `Custom::ScoutListener`/`ProcessMessageJob` double-dispatch risk.

## Scenario 4 — Engine toggle takes effect on the very next message, no deployment (US1 Acceptance #5/#6, SC-003)

```ruby
account.disable_features('scout_v2')
# POST .../playground_messages now dispatches through Custom::Scout::PlaygroundRunner (v1, unchanged)

account.enable_features('scout_v2')
# next POST .../playground_messages dispatches through Custom::ScoutV2::TurnRunner — no restart
```

**Expected outcome**: dispatch branch read fresh on every request (`account.feature_enabled?`,
no caching) — confirms FR-005/SC-003 without any code deploy between the two calls.

## Scenario 5 — v1 accounts observe zero behavioral difference (FR-020, SC-004)

```ruby
account.disable_features('scout_v2') # default
```

Run the existing `Custom::Scout::PlaygroundRunner`/`AgentRunner`/`SystemPromptsService`/
`ResponseAuditor` spec suites unmodified — this feature makes no diff to those files
(research.md D8/D9, brief 03 §6), so their existing green suite is itself the regression proof.
