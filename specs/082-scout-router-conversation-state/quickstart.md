# Quickstart: Scout Deterministic Router and Conversation Routing State

Validation guide for this feature once implemented. Assumes the container stack is already up
(`docker compose up -d`) per `AGENTS.md`. Scenarios 1–2 use only in-memory objects (no DB, no LLM —
the epic's own cut-line, SC-001). Scenarios 3–5 use real factory-backed records to exercise the
persisted `ScoutConversationState`.

## Prerequisites

- `docker compose up -d` (services: `rails`, `postgres` at minimum for scenarios 3–5; scenarios
  1–2 need no database).
- Migration applied: `docker compose exec rails bundle exec rails db:migrate` (creates
  `ichatr_scout_conversation_states`).

## Scenario 1 — The router picks the highest-priority match, entirely in memory (US1 + US2)

```sh
docker compose exec rails bundle exec rails runner '
  low = Custom::ScoutV2::Playbook.new(name: "pausa", title: "Pausa", priority: 10,
    trigger: "t", when_state: [["opportunity_open", nil]], file_path: "pausa.md")
  high = Custom::ScoutV2::Playbook.new(name: "qualificacao", title: "Qualificação", priority: 50,
    trigger: "t", when_state: [["opportunity_open", nil]], file_path: "qualificacao.md")
  catalog = Custom::ScoutV2::Playbook::Catalog.new([low, high])

  ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: Opportunity.new(status: "open"))
  decision = Custom::ScoutV2::Router.call(ctx, catalog)

  raise "expected qualificacao" unless decision.playbook.name == "qualificacao"
  raise "expected confidence 1.0" unless decision.confidence == 1.0
  puts "OK: router picked #{decision.playbook.name} with confidence #{decision.confidence}, no DB/LLM involved"
'
```

**Expected outcome**: prints `OK: router picked qualificacao with confidence 1.0, no DB/LLM
involved`. No exception, no query log (nothing in this scenario touches the database).

## Scenario 2 — Continuity, interruption, and "nothing matches" in one table (US2)

```sh
docker compose exec rails bundle exec rails runner '
  active = Custom::ScoutV2::Playbook.new(name: "agendamento", title: "A", priority: 20,
    trigger: "t", when_state: [], file_path: "a.md")
  higher = Custom::ScoutV2::Playbook.new(name: "duvida_urgente", title: "B", priority: 30,
    trigger: "t", when_state: [["opportunity_open", nil]], file_path: "b.md")
  lower = Custom::ScoutV2::Playbook.new(name: "nota", title: "C", priority: 5,
    trigger: "t", when_state: [["opportunity_open", nil]], file_path: "c.md")
  open_opp = Opportunity.new(status: "open")

  # Continuity: nothing new matches active_playbook itself, it just stays.
  ctx_continuity = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, active_playbook: active)
  d1 = Custom::ScoutV2::Router.call(ctx_continuity, Custom::ScoutV2::Playbook::Catalog.new([active]))
  raise "expected continuity" unless d1.playbook.name == "agendamento"

  # Interruption: higher-priority match beats the active one.
  d2 = Custom::ScoutV2::Router.call(ctx_continuity, Custom::ScoutV2::Playbook::Catalog.new([active, higher]))
  raise "expected interruption" unless d2.playbook.name == "duvida_urgente"

  # Non-strict winner: lower priority than active never displaces it.
  d3 = Custom::ScoutV2::Router.call(ctx_continuity, Custom::ScoutV2::Playbook::Catalog.new([active, lower]))
  raise "expected active to remain" unless d3.playbook.name == "agendamento"

  # Nothing matches, no active playbook: no state-based answer.
  ctx_none = Custom::ScoutV2::RoutingSnapshot.new(opportunity: Opportunity.new(status: "lost"))
  d4 = Custom::ScoutV2::Router.call(ctx_none, Custom::ScoutV2::Playbook::Catalog.new([higher]))
  raise "expected nil" unless d4.playbook.nil? && d4.confidence.nil?

  puts "OK: continuity, interruption, non-strict-winner, and no-match all resolved correctly"
'
```

**Expected outcome**: prints `OK: continuity, interruption, non-strict-winner, and no-match all
resolved correctly`.

## Scenario 3 — `RoutingSnapshot::Builder` assembles a real snapshot from a real conversation (US1)

```sh
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rails runner '
  account = Account.create!(name: "Quickstart")
  stage = PipelineStage.create!(account: account, name: "Qualificado", position: 1)
  scout = Scout.create!(account: account, name: "Scout", qualified_stage_id: stage.id)
  inbox = Inbox.create!(account: account, name: "WA", channel: Channel::Api.create!(account: account))
  ScoutInbox.create!(scout: scout, inbox: inbox)
  contact = Contact.create!(account: account, name: "Lead")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  opportunity = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage,
    origin_conversation: conversation, active_conversation: conversation, title: "Deal")

  catalog = Custom::ScoutV2::Playbook::Catalog.new([])
  snapshot = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: catalog)

  raise "expected contact" unless snapshot.contact == contact
  raise "expected scout" unless snapshot.scout == scout
  raise "expected opportunity" unless snapshot.opportunity == opportunity
  raise "expected qualified role" unless snapshot.opportunity_stage_role == :qualified
  raise "expected no active playbook on first turn" unless snapshot.active_playbook.nil?
  puts "OK: snapshot assembled from real records, stage_role=#{snapshot.opportunity_stage_role}"
'
```

**Expected outcome**: prints `OK: snapshot assembled from real records, stage_role=qualified`.

## Scenario 4 — Transition cap: two hand-offs succeed, a third is refused and recorded (US3)

```sh
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rails runner '
  account = Account.create!(name: "Quickstart")
  inbox = Inbox.create!(account: account, name: "WA", channel: Channel::Api.create!(account: account))
  contact = Contact.create!(account: account, name: "Lead")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  state = ScoutConversationState.create!(account: account, conversation: conversation)

  raise "1st should succeed" unless state.record_transition!("passo_2", turn_transition_count: 0) == true
  raise "2nd should succeed" unless state.record_transition!("passo_3", turn_transition_count: 1) == true
  raise "3rd should be refused" unless state.record_transition!("passo_4", turn_transition_count: 2) == false

  state.reload
  raise "active_playbook should be passo_3, not passo_4" unless state.active_playbook == "passo_3"
  raise "transition_count should be 2 (cumulative), not 3" unless state.transition_count == 2
  raise "limit-reached marker should be set" unless state.handoff_limit_reached_at.present?
  puts "OK: cap enforced, active_playbook=#{state.active_playbook}, transition_count=#{state.transition_count}"
'
```

**Expected outcome**: prints `OK: cap enforced, active_playbook=passo_3, transition_count=2`.

## Scenario 5 — Terminal exit clears the active playbook and survives reactivation (US3)

```sh
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rails runner '
  account = Account.create!(name: "Quickstart")
  inbox = Inbox.create!(account: account, name: "WA", channel: Channel::Api.create!(account: account))
  contact = Contact.create!(account: account, name: "Lead")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

  state.record_state_activation!("agendamento")
  state.record_terminal_exit!("agendado")
  state.reload
  raise "active_playbook should be cleared" unless state.active_playbook.nil?
  raise "last_exit should be agendado" unless state.last_exit == "agendado"

  # Reactivating later must not touch last_exit.
  state.record_state_activation!("agendamento")
  state.reload
  raise "last_exit must survive reactivation" unless state.last_exit == "agendado"
  puts "OK: terminal exit recorded and survives a later reactivation"
'
```

**Expected outcome**: prints `OK: terminal exit recorded and survives a later reactivation`.

## Running the permanent test suite (what actually gates merge)

```sh
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout_v2/routing_snapshot_spec.rb \
  custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb \
  custom/spec/services/custom/scout_v2/router_spec.rb \
  custom/spec/services/custom/scout_v2/predicates/evaluator_spec.rb \
  custom/spec/services/custom/scout_v2/predicates/opportunity_open_spec.rb \
  custom/spec/services/custom/scout_v2/predicates/pending_required_fields_spec.rb \
  custom/spec/models/scout_conversation_state_spec.rb
```

**Expected outcome**: all examples green — covering, per spec.md's acceptance scenarios: in-memory
snapshot construction (US1), real-DB snapshot assembly (US1), the full router decision table
including continuity/interruption/non-strict-winner/no-match/trigger-only-never-wins (US2), and
every US3 scenario (state activation, interruption, transition hand-off, the 2-per-turn cap and its
refusal marker, a clean two-hand-off turn leaving the marker unset, a retry's fresh turn-scoped
count, terminal exit, and reactivation leaving a prior `last_exit` untouched). Zero LLM calls, zero
network requests anywhere in this suite (SC-001).

## Cleanup

Scenarios 3–5 create real `Account`/`Conversation`/`Opportunity`/`ScoutConversationState` records.
Run them only against the `test` environment (as shown, via `RAILS_ENV=test`) so nothing lands in
`chatwoot_dev` — per `AGENTS.md`'s dev-DB contamination warning, never run throwaway data-creating
scripts like these against `chatwoot_dev`.
