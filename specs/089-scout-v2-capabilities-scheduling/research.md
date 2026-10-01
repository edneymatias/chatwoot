# Research: Scout V2 Capabilities and End-to-End Scheduling

Phase 0 of `/speckit.plan` for [spec.md](./spec.md). Resolved against the code in this repository
(paths are project-relative) and, for the ERP request shapes, against the four active `ScoutTool`
rows of the dev database (2026-09-30). The one thing that could not be observed — the vendor's
response bodies — is handled in §9. No `NEEDS CLARIFICATION` remains.

---

## §1 — Capability contract: declaration and hard input

**Decision**: a capability is a class under `Custom::ScoutV2::Capabilities` extending a small `Base`
DSL. Each declares its operations as `Operation` value objects (`Data.define(:name, :inputs,
:output)`); an input is `(name, type, required)` with type ∈ `string | date`; an output is
`(required_fields, shape)` with shape ∈ `record | list`.

```ruby
class Custom::ScoutV2::Capabilities::Scheduling < Custom::ScoutV2::Capabilities::Base
  capability_name 'scheduling'
  operation :list_slots do
    input  :date,    type: :date,   required: true
    input  :service, type: :string, required: false
    output required: %w[slot_id starts_at], shape: :list
  end
  operation :book do
    input  :slot_id, type: :string, required: true
    input  :notes,   type: :string, required: false
    output required: %w[appointment_id]
  end
end
```

`Operation#problems_for(inputs)` mirrors `Exits::PayloadValidator` (same file style, same Portuguese
messages): missing required → `campo 'x' ausente`, wrong type → `campo 'x' deve ser date (YYYY-MM-DD)`,
undeclared key → `campo 'x' não declarado`. A `date` is a `String` that `Date.iso8601` accepts —
syntactic only, past dates are valid (spec edge case). A `string` is a non-blank `String`, exactly
as the exit validator. Problems are joined into `{ error: "Dados inválidos para <tool>: …. Corrija e
chame novamente." }` returned as the tool result — the turn is not ended and nothing has left the
process (FR-003, SC-001). The DSL reuses `PayloadValidator` semantics by design rather than sharing
code: the exit validator validates a `Playbook::ExitDeclaration` (`fields` hash of type names),
capability inputs need `required?` and `date`; three similar checks beat a premature shared
abstraction (Principle II).

**Rationale**: provider-side schema enforcement of tool params is not reliable (the repo already
re-validates exit payloads server-side and coerces `hash` params for OpenAI); strictness therefore
lives in Ruby before the provider call. Reusing the `params_schema` mechanism of `ExitTool` lets one
generic tool class serve every operation.

**Alternatives considered**: RubyLLM `param` DSL per operation class (static; one class per
operation; couples contract to the tool class); JSON Schema validation via `JSONSchemer` (already a
dependency, but error messages would not name "the input and the expectation" in Portuguese without
post-processing).

## §2 — Registry, resolution and satisfaction

**Decision**: `Capabilities::Registry`:

- `PROVIDERS = { 'younus' => Erp::Younus::Adapter }` (one line to add a vendor later).
- `Registry.resolve(name, account:)` → `Resolution` (`Data.define(:capability, :provider)`;
  `#satisfied?` ⇔ `provider.present?`). Never raises for absent integrations.
- `Registry.satisfied_names(account:)` → the subset of `Catalog::KNOWN_NAMES` that resolve.
- Resolution rule (FR-007), evaluated **independently per capability**:
  1. the account has an enabled hook whose app has `category: erp` **and** `hook.feature_allowed?`
     (the `erp_integration` flag) — same category selection as `ErpController#fetch_hook` but without
     its `app_id == 'younus'` vendor fallback, because satisfaction is by category → `PROVIDERS`
     mapping;
  2. `PROVIDERS[hook.app_id]` exists and `provider_class.capability_settings` has the capability;
  3. every setting key listed for that capability is present (non-blank) in `hook.settings`, and every `id_*` key
     (`id_empresa` included) is digits only (`/\A\d+\z/`); `token` and `nr_convenio` only need to be non-blank.
     A malformed value is unsatisfied, never an exception.
  Otherwise `Resolution` with `provider: nil`.
- Setting keys per capability (Younus): `scheduling` → `id_empresa id_agenda id_servico id_usuario
  id_convenio` (list needs company/schedule/service; book adds user and agreement);
  `customer_registry` → `id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa` (find needs
  only company, create needs the rest). `token` is required by both (it is `required` by the schema, so
  always present on a valid hook, but it is listed so a hand-edited row cannot satisfy).
- The provider is `Erp::Younus::Adapter.new(hook)`; `Erp::AdapterFactory` is **not** used (brief §3,
  FR-026 leaves it unchanged).

**Rationale**: FR-005/006/007. Selecting the hook by category (not `younus`) means a future ERP vendor
needs only a `PROVIDERS` entry and a `capability_settings` — no playbook, no registry rule change.
`Integrations::Hook#feature_allowed?` is public and already the gate `validate_erp_credentials?` uses,
so an account whose `erp_integration` flag was switched off resolves unsatisfied on the next turn
(edge case "integration disabled between two turns" is covered by `hooks.enabled` + the flag,
evaluated at each `RoutingSnapshot::Builder.call`).

**Alternatives considered**: resolving through `Erp::AdapterFactory.build` (raises `ArgumentError`
for unsupported vendors — the exact "raise on absence" the spec forbids); storing a
`capabilities` array on the hook (config that can drift from what the code implements).

## §3 — Exposing operations to the model

**Decision**: one generic `Capabilities::OperationTool < Custom::Scout::Tools::BaseTool` per
(capability, operation), built in `TurnScope#actions_for`:

```ruby
capability_tools = playbook.requires.flat_map { |cap| Capabilities::Registry.tools_for(cap, scout:, conversation:, scope: self) }
tools + capability_tools + exits     # only when requires_satisfied
```

Names: `scheduling_list_slots`, `scheduling_book`, `customer_registry_find_by_phone`,
`customer_registry_create` (`"#{capability}_#{operation}"`, snake_case, valid for Gemini/OpenAI).
`params_schema` is built from the operation's inputs (`date` → `{type: 'string', format: 'date'}`);
an operation with no inputs (`find_by_phone`) returns `nil` like `ExitTool` does for no fields.
The model-facing descriptions never mention any identifier, credential or phone (FR-008).

Scoping (FR-018) falls out of `actions_for`: it is called only for the playbook being made active
(routing decision, `open_playbook#activate_procedure!`, transition target), the existing
`requires_satisfied` early return already withholds exits, and capability tools are added on the
satisfied side of that same branch. A situational takeover uses `replace_with_baseline!` with the
takeover playbook's declared tools only, so capability tools disappear during an interruption
takeover (spec edge case) with no new code. Unsatisfied accounts: no capability tools are registered
(the Brief 06 degradation keeps declared *tools* but there are none for `agendamento`).

**Rationale**: reuses the wrap/guard/record path every other tool goes through (`TurnScope#wrap`
→ `guard_tool` for `ended?` + `CallRecorder#wrap_tool` for `tool_calls`), so a capability call after
an ended turn returns `TURN_ENDED_ERROR` and playground `tool_calls` include capability calls for free.

**Alternatives considered**: one tool per capability with an `operation` argument (a model-produced
discriminator; weaker per-operation schemas); registering tools from `Tools::Registry` by name
(that registry is a static name→class map validated at boot against `playbook.tools`; capability
tools are per-account and derived from `requires`, which is already boot-validated).

## §4 — Conversation-scoped facts: where "resolved customer", "offered slots" and "booking" live

**Decision**: one additive column `capability_state jsonb default {}, null: false` on
`ichatr_scout_conversation_states`, three keys (data-model.md). `ScoutConversationState` gains
`remember_customer!(id:, name:)`, `remember_slots!(slots)` (merges into the offered map, so earlier
listings stay bookable — spec edge case), `remember_booking!(appointment_id:, starts_at:)`. Read
through `state.capability_state['customer']` etc.

**Rationale**: the facts must survive across turns (offer in turn N, book in N+1) and across the
Sidekiq job boundary of inbox turns; `recorded_tool_calls` is per-turn and playground history carries
only message text. The state row is already per conversation, so a new conversation for the same
contact starts empty (matches "in this conversation" for FR-013/014/021) and needs no cleanup; a hand-back
keeps them, which is harmless because `completed_playbooks` prevents re-pinning. Brief 08 (typed
memory) may later absorb this; the column is deliberately narrow and internal.

**Alternatives considered**: deriving from persisted messages/tool calls (inbox tool calls are not
persisted; playground history is text-only); Redis with TTL (a booking fact must be as durable as
`completed_playbooks`); three columns (one migration either way; a single jsonb avoids schema churn
per new capability fact).

## §5 — Slot identity

**Decision**: `slot_id` is the slot's start instant as ISO 8601 with offset (e.g.
`2026-10-15T14:30:00-03:00`), produced by the provider's normalization. `Scheduling#list_slots`
stores `{ slot_id => starts_at }` (equal string, kept as a map so membership is O(1) and a future vendor
with opaque ids fits unchanged); `book` accepts a `slot_id` only if it is a key of `offered_slots`
(FR-014) and sends the mapped `starts_at` as `dtIniAgenda` — never the model's value. The start text
in the *model-facing* list is what natural-language options are built from. The `-03:00` offset is fixed (Brasília, no DST) per the spec Assumption; see plan Risks.

**Rationale**: the vendor endpoint returns times, not identifiers (`horarios-livres` takes
`data, idAgenda, idEmpresa, idServico` and the booking takes `dtIniAgenda`); a synthetic id equal to
the start is stable across repeated listings, so "slots from earlier listings remain bookable" holds
with no id bookkeeping. Membership validation — not the id's opacity — is what prevents the model from
booking an invented time.

**Alternatives considered**: random/sequential ids per listing (breaks re-listing: the same time gets
a different id, and the model may carry an old one).

## §6 — Injection of identifiers, phone and the `service` input

**Decision**:
- All seven identifiers and the token come from `hook.settings` inside `Erp::Younus::Client`
  (new `settings:` kwarg); no capability/tool method takes them as arguments (FR-008/009). The
  request key mapping (from the four `ScoutTool` schemas): `idEmpresa←id_empresa`,
  `idUsuario←id_usuario`, `idConvenio←id_convenio`, `nrConvenio←nr_convenio`,
  `idOrigempessoa←id_origem_pessoa`, `idAgenda←id_agenda`, `idServico←id_servico`. Settings are
  strings; the client sends numeric ids as integers (`Integer(value)` on ids the vendor schema types as
  `number`; `nrConvenio` as string), a non-numeric id never reaches the client, because the registry (§2) treats any non-digit `id_*` value (`id_empresa` included) as unsatisfied, so `Integer()` cannot raise.
  Non-numeric ids are rejected at settings save time by the schema pattern `^\d*$` on the five id keys
  (`nr_convenio` stays free text), so the UI cannot save one for the five new keys either.
- The phone comes from `conversation.contact.phone_number`, normalized by
  `Erp::BaseAdapter#normalize_phone_digits` (made public — visibility only — and called as `provider.normalize_phone_digits`; the same normalization the contact-data card uses); blank
  → the customer-registry operation returns `{ error: 'O contato não tem telefone registrado…' }`
  before any request (FR-011). `create` sends the name the model passed (the only model-provided
  field), the contact phone, and the configured ids.
- `scheduling_list_slots.service` is accepted (contract, FR-002) and recorded in the call record but
  **not sent**: with this vendor the service is the configured `id_servico`, and letting the model
  influence it would reopen the hallucination surface FR-008/009 close (spec Assumptions). The tool
  description says it is informational.
- `book`: `idPessoa` from `capability_state.customer.id` (FR-013); `nmTitulo` = the customer's name
  from state, truncated to 100 chars (the old tool's rule); `observacoes` = `"Agendado por Scout: <notes>"`
  (the old tool's format, notes optional → `"Agendado por Scout"`); `dtIniAgenda` from the offered map.

**Rationale**: matches every acceptance scenario of Story 2 and reuses the old tools' proven field
semantics; the schema `pattern` follows the repo's rule to validate at the boundary and keep the
client free of coercion guesses.

## §7 — `exit_agendado` precondition and the exit outcome

**Decision**: a new optional exit key `precondition: booking` (Loader `ALLOWED_EXIT_KEYS` +
`precondition`; `ExitDeclaration` gains `precondition:` defaulting to `nil`). `Exits::Preconditions::REGISTRY`
maps `'booking'` → a callable `(exit_tool) -> error_string_or_nil` reading
`ScoutConversationState.for_conversation(conversation).capability_state['booking']`.
`DependencyRules` (not the class-length-limited Validator) reports an unknown precondition name and a
precondition on a non-terminal exit at boot. `ExitTool#execute` calls it **before**
`PayloadValidator`/dispatch: on failure it returns `{ error: 'Você ainda não realizou nenhum agendamento
nesta conversa. Chame scheduling_book antes de exit_agendado, ou transfira com exit_handoff.' }` —
no `record_terminal_exit!`, no `completed`, turn not ended (FR-021, AS 3.9).

Outcome (FR-022): `agendado` declares **no fields** — the booked start is data the system holds, so the
model is no longer asked to produce `inicio` (it was the last model-produced ERP-adjacent value).
On success `Terminal` returns `"Desfecho 'agendado' registrado. Início: <starts_at>. Referência:
<appointment_id>. Escreva agora sua resposta final…"`; the values are the stored `booking` entry, they
appear in the exit's recorded `tool_calls` result and the tool span, and stay readable from
`capability_state['booking']` on the conversation row. `last_exit`/`completed_playbooks` are
written by the existing `record_terminal_exit!` unchanged.

**Rationale**: FR-023 keeps kinds, priority, conditions and the completed mechanism as delivered; a
declarative key keeps the check visible in the playbook file and boot-validated instead of a
`playbook name == 'agendamento'` branch in Ruby. "The assertion checks bookings, not wording" (edge
case) is exactly what reading state does.

**Alternatives considered**: hard-coding `agendamento`/`agendado` in `Terminal` (hidden coupling, dies
with the next playbook that needs a guard); keeping `inicio` as a model field and cross-checking it
(the model would still author a value the system already has; the brief's `opportunity_id` field has
no meaning here — the spec records start + reference instead); a new column for the outcome (state
already holds it).

## §8 — Capability call record (trace)

**Decision**: every `OperationTool#execute` builds a `Capabilities::CallRecord` (`Data.define(:capability,
:operation, :inputs, :injected, :outcome, :error, :deviations)`) and sets
`langfuse.observation.metadata.capability_call` (constant `ATTR_LANGFUSE_OBSERVATION_METADATA`) on the
current span, which inside `BaseTool#call → instrument_tool_call` is the tool's own span. `inputs` =
what the model supplied; `injected` = `{ id_empresa:, id_usuario:, …, phone: }` actually sent (the
configured ids and the normalized phone, from the request builder — never the token); `outcome` ∈
`ok | invalid_input | precondition_failed | erp_error | unsatisfied`; `deviations` = declared output
fields missing from the normalized answer. Only the model-visible `data`/`error` is returned as the
tool result. With OTel disabled no span exists and nothing is recorded, same as every other tool's trace.

**Rationale**: FR-004/FR-017/SC-008; the tool span is where `arguments` and `result` already land, so
a Langfuse reader sees input, injected ids and outcome side by side. The credential never enters
`CallRecord` because `injected` is built from an explicit allow-list of the seven identifiers + phone.

**Alternatives considered**: adding a key to `recorded_tool_calls` (playground UI would render ids in
chat-visible tool output and the runner's `execute_and_record` would need a change); a trace-level
array on the agent span (needs the runner to aggregate — `TurnRunner` is at the class-length limit).

## §9 — Vendor requests and unobserved responses

**Known (from the `ScoutTool` rows and the existing client)**:

| Operation | Vendor call | Query / body keys |
|---|---|---|
| find_by_phone | `GET /webhook/pesquisar-pessoa` | `idEmpresa`, `nrTelcelpessoa` |
| create | `POST /webhook/incluir-cliente` | `nmPessoa`, `idEmpresa`, `idUsuario`, `idConvenio`, `nrConvenio`, `idOrigempessoa`, `nrTelcelpessoa` |
| list_slots | `GET /webhook/horarios-livres` | `data` (YYYY-MM-DD), `idAgenda`, `idEmpresa`, `idServico` |
| book | `POST /webhook/incluir-agendamento` | `idAgenda`, `idEmpresa`, `idServico`, `idUsuario`, `idConvenio`, `idPessoa`, `nmTitulo`, `dtIniAgenda` (`YYYY-MM-DDTHH:mm:ss-03:00`), `observacoes` |

Auth header `token`, `Content-Type: application/json`, base `https://wfh.ichatr.com.br` — the same as
`Erp::Younus::Client`.

**Not observable**: response bodies. A probe from the `rails` container of `pesquisar-pessoa` timed
out after 85 s (`Net::ReadTimeout`), so the envelope of the new endpoints is unverified. The existing
`/webhook/pessoas` returns `{sucesso:, mensagem:, dados:[{json: {...}}]}` with `cd_pessoa`,
`nm_pessoa`; the new client methods parse with the same envelope helper and fall back to "deviation"
rather than raising on unknown shapes.

**Decision**:
1. **Task 0 of the implementation** captures a real body per endpoint (read endpoints directly; the
   two writes only against the test company/agenda, spec Assumptions) into
   `custom/spec/fixtures/erp/younus/*.json` and writes the client specs against those fixtures. Parsers
   are written after the fixtures, not before.
2. Adapter normalization is total: whatever the vendor sends is mapped to the contract shape with
   `nil` for what it cannot find, and the missing declared fields become `deviations` (FR-004). A
   list-endpoint body that yields zero parseable slots returns `[]` (the model then offers the nearest
   date per the playbook) — the distinction between "empty day" and "vendor error" is the HTTP status /
   `sucesso: false` handling below, not payload guessing.
3. Failure mapping (FR-015, no retry): HTTP 401/403 → `Erp::AuthenticationError`; timeout, network,
   5xx, malformed body → `Erp::ApiError` (all existing client behavior); for the two POSTs a
   `sucesso: false` envelope also raises `Erp::ApiError` (a write that the ERP declined must not look
   like success). `OperationTool` rescues `Erp::Error` only and returns `{ error: … }` with outcome
   `erp_error`. The text depends on the class: a credential rejection is definitive; everything else
   warns that a write's outcome may be unknown and forbids repeating it. Three no-identifier answers
   (booking, registration, single-match lookup) get their own text; the single table is
   `contracts/capabilities.md` §1a. Any other exception propagates (fail loudly).
4. Ambiguity (FR-016): `find_by_phone` with `multiple_matches` → `{ status: 'ambiguous' }`, no person
   remembered; found → `{ status: 'found', name: }` and `remember_customer!`; none →
   `{ status: 'not_found' }`. Counting two ambiguous lookups toward transfer (a `not_found` is not a failure: it leads to create; an ERP failure is not counted, it transfers at once) is playbook guidance; no
   counter in code (the model counts, exactly like the existing two-attempt rule).

## §10 — ERP hook settings and the MANIFEST

**Decision**: extend the `younus` block of `config/integration/apps.yml` with six optional string
properties (`id_usuario`, `id_convenio`, `nr_convenio`, `id_origem_pessoa`, `id_agenda`,
`id_servico`) in `settings_json_schema.properties` (`required` stays `['token','id_empresa']`,
`additionalProperties: false`; the five id-like keys get `pattern: '^\d*$'` so a cleared optional field saved as `''` stays valid), matching
`settings_form_schema` items (`validation` omitted → optional) and `visible_properties` (so the hook
JSON returns them and the edit form is repopulated; the token stays masked by
`Custom::Integrations::Hook#masked_settings`). The same text goes into the `insert:` of the MANIFEST
entry in `bin/sync-custom-module-hooks` (the `younus` block is fork text injected at the
`transcript_activity_score` anchor), so `--check` stays green and `apply` cannot resurrect the old
block. The pt-BR/en locale files need no change: `settings_form_schema` labels are literals like the
existing `API Token` / `Company ID`.

**Rationale**: FR-010 (optional → contact-data-card-only accounts stay valid, AS 2.10). No frontend
code: `NewHook.vue` renders `formItems` from the schema. `Custom::Integrations::Hook#sanitize_erp_settings`
already strips whitespace on every string value, including the new ones. `validate_erp_credentials`
(`test_connection` → `search_by_phone('0')`) is unchanged.

**Existing hooks**: the integration screen has create and delete but no edit form
(`NewHook.vue`, `SingleIntegrationHooks.vue` emits only `add`/`delete`), so an account with an
existing hook enters the new identifiers by deleting and recreating the hook in the same screen
(FR-010 "entered through the existing integration settings screen" holds) or through the existing
`PATCH …/integrations/hooks/:id` API. Building an edit form is out of scope; until identifiers are
entered the capabilities stay unsatisfied and Brief 06 degradation applies.

**Edge**: adding `visible_properties` changes `custom/spec/models/custom/integrations/app_spec.rb`'s
`eq(%w[id_empresa token])` expectation — a contract change, updated in the same commit.

## §11 — `agendamento.md` rewrite and spec cutovers

**Decision**: front-matter loses `needs: [politica_reagendamento]`; the `agendado` exit loses `fields`
and gains `precondition: booking`; body step 6 (policy) is deleted and steps renumbered; four
`[[depends: …]]` markers remain (`customer_registry`, `scheduling` ×3) and none for
`politica_reagendamento`. New body content (Portuguese, model-facing): call `customer_registry_find_by_phone`
first; on `not_found` confirm the name the lead gave and call `customer_registry_create`; after two
`ambiguous` lookups call `exit_handoff` (an ERP failure transfers at once); ask the preferred day and call
`scheduling_list_slots`; present at most three of the returned times in natural language and never a
time not returned; book only a `slot_id` that was returned; call `exit_agendado` only after
`scheduling_book` succeeded; empty day → offer the nearest date (list the next days, at most three, in order; none free → `exit_sem_horario` stating no availability); all declined →
`exit_sem_horario` with `motivo`; contact has no phone (block "Dados de contato faltando: - telefone"
is already rendered for procedures whose conditions include `contact_identity_incomplete` — for
`agendamento` the phone-missing case is stated in the body instead) → `exit_handoff` in the same turn
stating the phone is missing, without asking for it and without any `customer_registry_*` call; any
tool returning an error or the ERP failing → do not promise, `exit_handoff` in the same turn; never
state rescheduling/cancellation rules (defer to the knowledge-base interruption). `when_state`,
`priority`, `trigger`, `requires` and exit kinds are unchanged (FR-023).

How the guidance knows the contact has no phone (FR-020 — "without any customer-registry call"):
`agendamento` does not list `contact_identity_incomplete`, so the 088 contact-gaps block is not
rendered for it, and its `when_state` cannot change (FR-023). Instead `Playbook::ContentBuilder`
gains one more context block: for a playbook whose `requires` includes `customer_registry`, when the
conversation contact has a blank `phone_number`, it appends `PHONE_MISSING_NOTICE` — "O contato não
tem telefone registrado. Não chame ferramentas customer_registry_*, não peça o telefone ao cliente e
chame exit_handoff neste mesmo turno informando que o telefone está ausente." The block is rendered on
every appearance of the guidance (pinned, opened, transition target — the qualification turn that
transitions into `agendamento` gets it through `Transition`'s existing `content_for`). The
code-enforced backstop is the tool's own pre-request error (FR-011), so even a model that ignores the
block cannot reach the ERP or obtain a phone from the lead. Placing the rule on the `requires`
declaration (not on the playbook name) keeps it generic for any future `customer_registry` consumer.

**Cutovers (contract changes, not re-pins)** — the 088 examples that assert the *old* body:
`playbook/catalog_spec.rb` (L198 `needs`, L204 `fields == {inicio}`, L218 policy marker count),
`playground_first_cut_catalog_spec.rb` (L667 marker scan, L873/L914 `unmet_needs`),
`unsatisfied_items_spec.rb` / `turn_scope_spec.rb` / `content_builder_spec.rb` shipped-catalog
examples (use `agendamento` with `politica_reagendamento` as satisfied fact). Examples that use
`politica_reagendamento` on a **constructed** playbook (`loader_spec`, `content_builder_spec` L204,
`scout_conversation_state_spec` L315, `routing_snapshot_spec`) exercise the generic business-fact
mechanism, which FR-024 keeps, and stay as they are.

## §12 — What is deliberately not built

- No provider abstraction beyond `PROVIDERS` + `capability_settings` (one vendor).
- No sourcing of `politica_reagendamento`; catalog entry and mechanism untouched.
- No output blocking, no retry, no backoff, no circuit breaker (FR-004/FR-015).
- No `ScoutTool`-as-provider, no removal of `call_custom_api` code (v1 still uses it; v2 simply never
  references it — FR-026).
- No new UI, no i18n keys, no controller/route.
- No playground reset endpoint (088 risk carried forward; quickstart §4 has the console snippet).
