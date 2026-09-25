# Phase 1 Data Model: Scout V2 Turn Runner and Qualification Playbook (Playground)

No migration, no new table, no new column. Every entity below is either a new stateless/thin
service class or a new file-based playbook — reusing brief 01/02's `Playbook`, `Catalog`,
`Router`, `RoutingSnapshot`, `RoutingSnapshot::Builder`, `ScoutConversationState` exactly as
delivered (research.md D1/D11).

## Turn (`Custom::ScoutV2::TurnRunner`)

Spec Key Entity "Turn." One instance per turn attempt, both surfaces.

| Member | Signature | Behavior |
|---|---|---|
| `.new` | `(scout:, conversation:, message:, message_history: nil)` | `message_history: nil` (inbox default) derives history from `conversation.messages`; an explicit array (always supplied by the playground dispatch point) is used verbatim — DB never queried for history in that case (research.md D4) |
| `#perform` | `() -> { reply: String, tool_calls: Array<Hash> }` | assembles context, consults router, builds prompt + tools, makes exactly one top-level `chat.ask`, persists routing state, returns the reply — never dispatches it (research.md D4) |

**`#perform` steps, in order** (FR-001, FR-006, FR-011, FR-012 in sequence):

1. Infra gate (research.md D10): `scout.quota_available? && ScoutAccountConfig.find_by(account_id:)&.api_key.present?`. On failure: inbox surface → `Custom::Scout::HandoffService.new(scout:, conversation:).perform(message: ...)`, return early with no LLM call; playground surface → return `{ reply: "Erro ao executar simulação: ...", tool_calls: [], error: "..." }`, no LLM call.
2. `catalog = Custom::ScoutV2::Playbook::Loader.load_all` (boot-validated already; loaded once per process the same way brief 01 already loads it — no new caching mechanism this phase).
3. `ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation:, catalog:, turn_transition_count: 0)` — `turn_transition_count` is always `0` this phase (no `TurnRunner`-internal transition mechanism exists yet — transitions are a later-phase exit outcome, brief 05).
4. `decision = Custom::ScoutV2::Router.call(ctx, catalog)`.
5. If `decision.playbook.present? && decision.playbook != ctx.active_playbook`: `ScoutConversationState.for_conversation(conversation).record_state_activation!(decision.playbook.name)` (research.md D11). Otherwise no write.
6. Build system instructions — `PromptAssembly` below.
7. Build tool catalog — `ToolCatalog` below.
8. `chat = scout.llm_chat.with_instructions(instructions)`; each tool `chat = chat.with_tool(wrapped_tool)` (`CallRecorder#wrap_tool`, reused unchanged from `Custom::Scout::Tools::CallRecorder`, `simulated: false` always — research.md D8).
9. Add history (from step 1's resolved `message_history`, via `chat.add_message`) then one call:
   `instrument_agent_session(params) { instrument_llm_call(params) { chat.ask(message) } }` — the
   single top-level LLM call (FR-011, SC-001). `instrument_*` reused unchanged from
   `Integrations::LlmInstrumentation` (already mixed into `AgentRunner`/`BaseTool`).
10. `reply = response&.content.to_s` (no `.with_schema`, research.md D9).
11. Return `{ reply:, tool_calls: recorded_tool_calls }` (`CallRecorder`, reused unchanged).

**FR-015 / Turn Trace tool instrumentation**: satisfied entirely by inheritance, not by anything
`TurnRunner` adds — every playbook tool subclasses `Custom::Scout::Tools::BaseTool`, whose
`#call` already wraps each invocation in `instrument_tool_call` (unchanged, generically verified
by `base_tool_spec.rb`). `CallRecorder#wrap_tool`/`recorded_tool_calls` above is a distinct,
unrelated mechanism — it populates the `tool_calls:` array in `#perform`'s own return value (read
by the playground UI), not the Langfuse trace.

**Instrumentation params** (`instrumentation_params`, mirrors `AgentRunner`'s private method shape
exactly, research.md D14):

| Field | Value |
|---|---|
| `span_name` | `'llm.scout_v2.turn_runner'` |
| `feature_name` | `'scout_v2_turn_runner'` |
| `model` | `ScoutAccountConfig.find_by(account_id: scout.account_id)&.model_name` |
| `metadata` | `{ scout_id:, playbook: decision.playbook&.name, activation_reason: (decision.playbook.present? ? 'state' : nil), unsatisfied_flags: {...} }.compact` |

`unsatisfied_flags` shape: `{ pending_fields: ctx.pending_fields, unmet_requires: (decision.playbook&.requires || []) - ctx.satisfied_capabilities }` — read-only, Langfuse-only, never written to `ScoutConversationState#unsatisfied_flags` (research.md D14).

## Prompt Assembly (`TurnRunner`-private, no new public class — research.md D5/D6)

| Playbook active? | Pending fields? | System instructions |
|---|---|---|
| No | — | `FALLBACK_INSTRUCTIONS` constant (one short paragraph — no Identity/Safety/Escalation layer this phase) |
| Yes | No | `playbook.body.strip` |
| Yes | Yes | `playbook.body.strip` + `"\n\n"` + pending-fields section (below) |

**Pending-fields section** — one line per `ctx.pending_fields` entry, resolved to a human label via
`CustomAttributeDefinition.where(attribute_model: :opportunity_attribute,
attribute_key: ctx.pending_fields).pluck(:attribute_key, :attribute_display_name,
:attribute_description).to_h`-style lookup (same primitive as
`Tools::BaseTool#custom_attribute_labels`, not the v1 `FunnelSectionBuilder`, research.md D6):

```
Campos pendentes para esta oportunidade:
- <attribute_display_name> (chave: <attribute_key>)<: attribute_description, se houver>
```

`FALLBACK_INSTRUCTIONS` (edge case: no playbook matches and none is active, FR-019):

```
Nenhum procedimento específico está ativo para esta conversa. Responda à mensagem do cliente da
melhor forma possível, use a base de conhecimento quando for útil, e aguarde a próxima mensagem.
```

FR-008 is satisfied structurally: neither branch ever references
`Custom::Scout::SystemPromptsService`/`guardrails_section`/`FunnelSectionBuilder`.

## Tool Catalog (`TurnRunner`-private constant — research.md D7/D8)

```ruby
TOOL_CLASSES = { 'manage_opportunity' => Custom::Scout::Tools::ManageOpportunity }.freeze
```

| Tool | Always offered? | Construction |
|---|---|---|
| `Custom::Scout::Tools::SearchKnowledgeBase` | yes (FR-009) | `.new(scout, conversation, playground: false)` |
| `TOOL_CLASSES.fetch(name)` for each `name` in `playbook.tools` | only while that playbook is active | `.new(scout, conversation, playground: false)` (research.md D8) |

`move_opportunity_stage`, `handover_to_human`, `call_custom_api` never appear in `TOOL_CLASSES` —
FR-010 is satisfied by construction, not filtering.

## Qualification Playbook (`custom/playbooks/qualificacao.md`)

Spec Key Entity "Qualification Playbook." One new file, validated by brief 01's already-delivered
`Loader`/`Validator` at boot — no loader/validator code changes.

```yaml
---
name: qualificacao
title: Qualificação de lead com oportunidade aberta
priority: 10
when_state:
  - opportunity_open
  - pending_required_fields
trigger: >
  O lead está no meio de uma qualificação comercial, com uma oportunidade em aberto e dados
  ainda pendentes de coleta.
tools: [manage_opportunity]
---

## Passos

1. Pergunte pelos dados de qualificação pendentes (listados abaixo, quando houver), um de cada
   vez, em linguagem natural.
2. A cada dado novo fornecido pelo cliente, registre-o imediatamente com `manage_opportunity`
   (`action: 'update'`, `custom_attributes` com a chave e o valor coletados).
3. Não repita perguntas sobre dados já registrados nesta conversa.
4. Sem dados pendentes restantes, confirme ao cliente que o cadastro está completo e aguarde a
   próxima mensagem.
```

**Fields deliberately absent** (brief 01 US1: absent-optional fields load as empty collections,
never validation errors): `requires` (zero capabilities, brief 03 §4 decision 4), `needs`, `exits`
(brief 03 §4 decision 5 — no outcome/ending referenced, FR-017). `priority: 10` is the only value
that matters this phase (exactly one playbook exists — no collision, no tie to arbitrate).

## Sandbox Conversation Resolver (`Custom::ScoutV2::PlaygroundConversation`)

Not a spec Key Entity itself — the concrete resolution step "a playground conversation" (spec
User Story 1/3 language) requires, per research.md D1/D2.

| Member | Signature | Behavior |
|---|---|---|
| `.for` | `(scout) -> Conversation` | find-or-create, idempotent, real DB records only |

Resolution, all via existing associations — no new query pattern:

1. `contact = Contact.find_or_create_by!(account: scout.account, identifier: "scoutv2-playground-scout-#{scout.id}") { |c| c.name = "Scout Playground (#{scout.name})" }`.
2. If `contact.contact_inboxes.first` is present, reuse its `inbox`. Otherwise, in one transaction:
   `channel = Channel::Api.create!(account: scout.account)`;
   `inbox = Inbox.create!(account: scout.account, name: "Scout Playground — #{scout.name}", channel: channel)`;
   `ScoutInbox.create!(scout: scout, inbox: inbox)` (research.md D3 — needed for `RoutingSnapshot::Builder`'s `conversation.inbox&.scout` resolution; safe because D3 guarantees no real `Message` is ever created on it, so `Custom::ScoutListener` never fires for it);
   `contact_inbox = ContactInbox.create!(contact:, inbox:, source_id: SecureRandom.uuid)`.
3. `contact.conversations.find_by(inbox: inbox) || Conversation.create!(account: scout.account, inbox:, contact:, contact_inbox:, status: :open)`.

## Feature Flag (New-Execution-Path Account Setting, `scout_v2`)

Spec Key Entity "New-Execution-Path Account Setting." Research.md D12 — one `config/features.yml`
entry + one `bin/sync-custom-module-hooks` MANIFEST entry. No new Ruby class; checked via
`account.feature_enabled?('scout_v2')` (upstream `Featurable` concern, already used identically
for `captain_integration_v2`).

## Dispatch Points (unchanged shape, one new branch each — research.md D13)

| File | Change |
|---|---|
| `custom/app/jobs/custom/scout/process_message_job.rb` | `process_debounce`: `if scout.account.feature_enabled?('scout_v2')` → build+dispatch via `TurnRunner`; `else` → existing `AgentRunner.new(...).perform` line, unchanged |
| `custom/app/controllers/api/v1/accounts/scouts/playground_messages_controller.rb` | `#create`: `if Current.account.feature_enabled?('scout_v2')` → `Custom::ScoutV2::PlaygroundConversation.for(@scout)` + `TurnRunner.new(...).perform`, render the hash directly; `else` → existing `PlaygroundRunner.new(...).perform` line, unchanged |
