# Data Model: Scout V2 Capabilities and End-to-End Scheduling

Persistent: one new column and six optional hook settings. Everything else is in-memory value
objects. Names are code names; spec terms in parentheses.

## 1. Persistent

### 1.1 `ichatr_scout_conversation_states.capability_state` (NEW)

| Column | Type | Default | Null |
|---|---|---|---|
| `capability_state` | `jsonb` | `{}` | not null |

Migration `db/migrate/21260930000000_add_capability_state_to_ichatr_scout_conversation_states.rb`
(`add_column … :jsonb, default: {}, null: false`; reversible via `change`). Fork-prefixed table, no core
table touched.

Shape (all keys optional; absent = nothing happened yet in this conversation):

```json
{
  "customer":      { "id": "123", "name": "Maria Silva" },
  "offered_slots": { "2026-10-15T14:30:00-03:00": "2026-10-15T14:30:00-03:00" },
  "booking":       { "appointment_id": "987", "starts_at": "2026-10-15T14:30:00-03:00" }
}
```

| Key | Entity (spec) | Written by | Read by | Rules |
|---|---|---|---|---|
| `customer` | Resolved Customer | `remember_customer!` after `find_by_phone` = found, or `create` succeeded | `Scheduling#book` (person id, title) | Replaced on each write. Never written for `ambiguous`/`not_found`/errors, nor for an answer without a readable id (FR-029). `id` is stringified (`Adapter#external_id_from`). |
| `offered_slots` | Offered Slots | `remember_slots!` after each successful `list_slots` | `Scheduling#book` (membership, start) | Merged, never cleared: earlier listings stay bookable. Key = `slot_id`, value = `starts_at`. Only slots with a parseable `starts_at` are stored. |
| `booking` | Booking | `remember_booking!` after `book` succeeded | `Scheduling#book` (rejects while present, FR-028), `Exits::Preconditions['booking']`, `Terminal` success message | Written once: a later `book` is rejected before any request while a booking exists. Written only when the answer carries `appointment_id`; an answer without it is a failed result (`contracts/capabilities.md` §1a), no booking is remembered and the exit stays rejected. |

`ScoutConversationState` additions (no other method changes):

```ruby
def remember_customer!(id:, name:)          # update!(capability_state: capability_state.merge('customer' => {...}))
def remember_slots!(slots)                  # slots: { slot_id => starts_at }
def remember_booking!(appointment_id:, starts_at:)
```

Lifecycle: one row per conversation (`for_conversation`), so a new conversation for the same contact
starts empty; a human hand-back keeps the row (harmless: `completed_playbooks` prevents re-pinning,
FR-023). Not cleared by terminal/transition/escalation exits.

### 1.2 ERP hook settings (`integrations_hooks.settings`, app `younus`) — no migration

| Key | New? | Required by schema | Needed by capability | Vendor field |
|---|---|---|---|---|
| `token` | no | yes | both (credential, header `token`; masked in API output; never recorded) | header |
| `id_empresa` | no | yes | both | `idEmpresa` |
| `id_usuario` | **yes** | no | `customer_registry` (create), `scheduling` (book) | `idUsuario` |
| `id_convenio` | **yes** | no | `customer_registry` (create), `scheduling` (book) | `idConvenio` |
| `nr_convenio` | **yes** | no | `customer_registry` (create) | `nrConvenio` |
| `id_origem_pessoa` | **yes** | no | `customer_registry` (create) | `idOrigempessoa` |
| `id_agenda` | **yes** | no | `scheduling` | `idAgenda` |
| `id_servico` | **yes** | no | `scheduling` | `idServico` |

Schema: `additionalProperties: false` stays; new keys are `string`; the five `id_*` new keys carry
`pattern: '^\d*$'`. "Present" for satisfaction means non-blank after the existing
`sanitize_erp_settings` strip; in addition every `id_*` value (`id_empresa` included, which has no schema
pattern so existing hooks stay valid) must be digits only (`/\A\d+\z/`), else the capability is unsatisfied
and the client never sees a non-numeric id. Satisfaction sets are in
[contracts/erp_provider.md](./contracts/erp_provider.md) §1.

## 2. In-memory value objects (`custom/app/services/custom/scout_v2/capabilities/`)

| Class | Definition | Notes |
|---|---|---|
| `Operation` | `Data.define(:name, :inputs, :output)` | `inputs`: frozen `Array<Input>`; `Input = Data.define(:name, :type, :required)` (`type` ∈ `'string' \| 'date'`). `output = Output(required: [String], shape: :record \| :list)`. Methods: `problems_for(inputs)` → `[String]`, `deviations_for(data)` → `[String]` (declared required output fields missing from a record, or from any element of a list), `params_schema` → JSON-schema hash or `nil`. |
| `Base` | class-level DSL: `capability_name(name=nil)`, `operation(name, &block)`, `operations` (`{ 'list_slots' => Operation }`) | Instances are built with `(provider:, conversation:)`; operation implementations are instance methods named as the operation. |
| `Scheduling`, `CustomerRegistry` | capability classes | Contracts in [contracts/capabilities.md](./contracts/capabilities.md) §2–3. Names ∈ `Catalog::KNOWN_NAMES` (asserted by a spec so the two lists cannot drift; the catalog stays the single startup source, FR-027). |
| `Registry::Resolution` | `Data.define(:capability, :provider)` | `satisfied?` ⇔ `!provider.nil?`. |
| `CallRecord` | `Data.define(:capability, :operation, :inputs, :injected, :outcome, :error, :deviations)` | `#to_span_json`. `injected`: hash restricted to the seven identifier keys + `phone`; contains no token by construction (built from an allow-list, not from `settings`). `outcome`: `ok`, `invalid_input`, `precondition_failed`, `erp_error`. |
| `OperationTool` | `Custom::Scout::Tools::BaseTool` subclass | `name` = `"#{capability}_#{operation}"`; `params_schema` from the operation. |

Playbook/exit value object change:

| Class | Change |
|---|---|
| `Playbook::ExitDeclaration` | `Data.define(:name, :kind, :fields, :target, :stage, :precondition)`; `precondition:` defaults `nil`. `HANDOFF` unchanged (`nil`). |
| `Exits::Preconditions` | `REGISTRY = { 'booking' => Booking }`; `known?(name)`; each entry `#call(exit_tool)` → `nil` (met) or an error string. |

## 3. Relationships and flows

```text
Account ──has_many──▶ Integrations::Hook (app_id 'younus', category erp, enabled, feature erp_integration)
                          │ settings (token + 7 identifiers)
                          ▼
Capabilities::Registry.resolve(name, account:) ──▶ Resolution ──provider──▶ Erp::Younus::Adapter(hook)
                                                                                 │ Client(token, settings)
RoutingSnapshot#satisfied_capabilities ◀── Registry.satisfied_names(account:)    ▼
        │                                                              wfh.ichatr.com.br/webhook/*
        ▼
TurnScope#actions_for(playbook): requires all satisfied?
   ├─ yes → declared tools + OperationTools(requires) + declared exits
   └─ no  → declared tools only                      (Brief 06 degradation, unchanged)

OperationTool#execute
   1. Operation#problems_for(model inputs)      → { error } (outcome invalid_input)   [no request]
   2. Capability preconditions (contact phone / no prior booking / resolved customer / offered slot)
                                                → { error } (outcome precondition_failed) [no request]
   3. provider call (ids + token + phone injected inside Client)  → Erp::Error → { error } (erp_error)
   4. normalize → Operation#deviations_for → CallRecord → span attribute
   5. remember_* on ScoutConversationState (customer / offered_slots / booking)
   6. return data (model-visible; never ids/token)

Exit precondition 'booking': ExitTool#execute → Preconditions → capability_state['booking'] present?
   no → { error } (no state change, no completed_playbooks entry)
   yes → existing Terminal path → record_terminal_exit!(completed: 'agendamento') → message with start/reference
```

## 4. State transitions (per conversation, capability layer)

```text
(empty) ──find_by_phone found──────────────▶ customer
(empty) ──find_by_phone not_found──────────▶ (empty)           # not a failure: the playbook proceeds to create
(empty) ──find_by_phone ambiguous──────────▶ (empty)           # no person selected; counts toward the two-failure transfer (model-counted)
(empty|customer) ──create ok───────────────▶ customer
(any) ──list_slots ok (N slots)────────────▶ offered_slots ∪ N
(customer ∧ slot ∈ offered_slots) ──book ok▶ booking
(no customer | slot ∉ offered_slots) ──book▶ unchanged, error, no request
booking ──book─────────────────────────────▶ unchanged, error, no request (FR-028)
booking ──exit_agendado────────────────────▶ last_exit='agendado', completed += ['agendamento'], active_playbook=nil
no booking ──exit_agendado─────────────────▶ unchanged, error
```

Validation rules recap: inputs — required present, `date` ISO 8601 calendar date, `string`
non-blank, no undeclared keys; `book.slot_id` ∈ `offered_slots`; `book` requires `customer` and no `booking`;
customer-registry operations require a contact phone; `create.name` is the only model-authored
value that reaches the ERP as free text besides `notes`.
