# Quickstart: validating Scout V2 Capabilities and Scheduling

Validation/run guide only. Design lives in [plan.md](./plan.md), [research.md](./research.md),
[data-model.md](./data-model.md) and [contracts/](./contracts/). All commands run in the containers
(AGENTS.md); rspec always with the `env -u FRONTEND_URL RAILS_ENV=test` prefix; targeted files only
(Principle IX).

```bash
RSPEC='docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec'
```

## 0. Prerequisites

1. Stack up: `docker compose up -d`.
2. Migration applied to a **clean** `chatwoot_dev` and `chatwoot_test`
   (`docker compose exec rails bundle exec rails db:migrate` and
   `… env RAILS_ENV=test bundle exec rails db:migrate`). Before committing `db/schema.rb`, confirm the
   diff contains only `capability_state` and no foreign objects; `spec/config/schema_spec.rb` fails on any
   `n8n` reference (AGENTS.md).
3. **Task 0 — vendor bodies** (blocks the client specs): capture one real response body per new
   endpoint into `custom/spec/fixtures/erp/younus/` (`find_person_found.json`, `find_person_none.json`,
   `find_person_multiple.json`, `free_slots.json`, `free_slots_empty.json`, `create_person.json`,
   `create_appointment.json`, plus a `sucesso: false` write). Reads: any account/company. Writes: only
   the test company/agenda. If the ERP host is unreachable from the container (it timed out at 85 s
   during planning), capture from the vendor's workflow/console and note the source in the fixture file. Anonymize personal data (names, phones, documents) before committing, keeping keys and envelope.
4. A test account with the `erp_integration` feature enabled and a `younus` hook holding all eight
   settings (`token` + seven identifiers) for the acceptance runs.

## 1. Acceptance scenario → test map

Entry point per claim (Constitution VI): **D** = direct call to the deciding class, **E** = effect
through the operation tool against WebMock ERP, **R** = `type: :request` playground spec /
job with real engine.

| Spec scenario | Example lives in | Kind |
|---|---|---|
| US1-AS1/2/3 (missing/mistyped/optional input, no request) | `capabilities/operation_tool_spec.rb` (assert `a_request(...)` **not** made + error text); full-turn `playground_scheduling_spec.rb` (T037d) | E / R |
| US1-AS4 (output deviation returned + recorded) | `operation_tool_spec.rb` (finished-span attribute via in-memory exporter) + `playground_scheduling_spec.rb` trace context | E / R |
| US1-AS5/6/7, FR-006/007 (resolve, unsatisfied, independence) | `capabilities/registry_spec.rb` (real `Account`/`Integrations::Hook` rows; disabled hook, flag off, missing key, other vendor, one capability only) | D |
| US2-AS1 (no identifier/credential/phone in inputs) | `operation_spec.rb` (`params_schema` of all four operations) | D |
| US2-AS2–5 (requests carry configured ids/phone) | `erp/younus/client_spec.rb` + `operation_tool_spec.rb` with distinctive setting values, `with(query:/body:)`; full-turn `playground_scheduling_spec.rb` (T037e) | E / R |
| US2-AS6 (missing identifier → unsatisfied, 0 requests) | `registry_spec.rb` + `playground_scheduling_spec.rb` degraded context (`a_request(:any, /wfh/)` never made) | D / R |
| US2-AS7 (no contact phone) | `customer_registry_spec.rb` | E |
| US2-AS8 (book precondition: offered slot, resolved customer) | `scheduling_spec.rb` | E |
| US2-AS11 / FR-028 (second `book` rejected, 0 requests; `book` answered without id → failed result, nothing remembered) | `scheduling_spec.rb` | E |
| US2-AS9 (record has identifiers/phone, never the token) | `operation_tool_spec.rb` span attribute (`not_to include(token)`) | E |
| US2-AS10 (contact-data card unchanged) | existing `erp_controller_spec.rb` + `hook_spec.rb` (run unchanged) + new `app_spec` visible-properties expectation | R |
| US3-AS1 (pinned by transition, same turn) | `playground_scheduling_spec.rb` (scripted qualification → scheduling) | R |
| US3-AS2 (no pending step/notice, exits + operations offered, unsatisfied items empty) | `playbook/content_builder_spec.rb` + `turn_scope_spec.rb` (shipped catalog) + request spec reading `unsatisfied_flags` | D / R |
| US3-AS3–7 (find/create, ≤3 options, book, nearest date, no-slot) | `playground_scheduling_spec.rb` scripted turns; prompt/actions contract per step | R |
| US3-AS8 (handoff paths) | `playground_scheduling_spec.rb` + `process_message_job_spec.rb` (real transfer) | R |
| US3-AS9 / FR-021 (`exit_agendado` without booking rejected) | `exits/exit_tool_spec.rb` (state unchanged, `completed_playbooks` unchanged, later booking still works) | D |
| US3-AS10 / FR-023 / SC-007 (not re-pinned, incl. after hand-back) | `process_message_job_spec.rb` | R |
| US3-AS11 / FR-020 (no phone → handoff, 0 requests) | `content_builder_spec.rb` (notice) + `playground_scheduling_spec.rb` (0 ERP requests, handoff with phone-missing reason) | D / R |
| US3-AS12 / FR-015 (ERP failure → failed result; credential rejection definitive, others say outcome unknown and not to repeat; transfer) | `operation_tool_spec.rb` (401 vs 500/timeout: request count 1 + message text) + request spec | E / R |
| US3-AS13 / FR-025 (degraded account = Brief 06) | existing 088 degraded examples, unchanged, plus `unmet_requires` listing only unsatisfied capabilities | R |
| US3-AS14 / SC-010 | manual playground pass (§4) | manual |
| FR-005 (resolution keyed by capability name, per account) | `registry_spec.rb` (two accounts, same name, different outcome); playbook/integration decoupling is structural, no source-text test (Constitution VII) | D |
| FR-004/SC-008 (deviation never breaks the turn) | `operation_tool_spec.rb` + trace context | E / R |
| FR-016/FR-029 (ambiguous never picked; registration or single match without id → failed result, nothing remembered) | `customer_registry_spec.rb` | E |
| FR-022 (exit records start + reference) | `exit_tool_spec.rb` (message + `capability_state`) | D |
| FR-024 (no policy step/need, 4 markers) | `playbook/catalog_spec.rb` (cutover) | D |
| FR-027 (catalog single source) | `validator_spec.rb` (existing unknown-capability example) + `capabilities/base_spec.rb` (names ⊆ catalog) | D |

## 2. Targeted runs

```bash
# capability layer + ERP
$RSPEC custom/spec/services/custom/scout_v2/capabilities/ custom/spec/services/erp/

# exits / playbook grammar / snapshot / scope / model / content
$RSPEC custom/spec/services/custom/scout_v2/exits/ \
       custom/spec/services/custom/scout_v2/playbook/ \
       custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb \
       custom/spec/services/custom/scout_v2/turn_scope_spec.rb \
       custom/spec/services/custom/scout_v2/unsatisfied_items_spec.rb \
       custom/spec/models/scout_conversation_state_spec.rb \
       custom/spec/models/custom/integrations/

# acceptance
$RSPEC custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb \
       custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb \
       custom/spec/jobs/custom/scout/process_message_job_spec.rb \
       custom/spec/requests/api/v1/accounts/integrations/
```

Expected: the new specs first **fail for the right reason** (missing column / constant / tool), then
pass after their slice; every existing example passes except the intentional cutovers of
[research.md §11](./research.md), which are edited in the same slice as `agendamento.md`.

Lint gates for touched files: `docker compose exec rails bundle exec rubocop <paths>`; MANIFEST:
`docker compose exec rails ruby bin/sync-custom-module-hooks --check` → 0 `missing` (the `younus`
entry now matches the edited `apps.yml`), then `… --audit` → 0 gaps (fast-forward `develop` first).

## 3. Smoke (no ERP, no LLM)

In a rails console (development) with a hook configured for a real account:

```ruby
acct = Account.find(1)
Custom::ScoutV2::Capabilities::Registry.satisfied_names(account: acct)
# => ["scheduling", "customer_registry"] with all identifiers; [] after blanking one; one name when only one set is complete
```

Then blank `id_agenda` on the hook and re-run: expect `["customer_registry"]` only — the capabilities
are evaluated independently.

## 4. Manual playground pass (SC-010, US3-AS14) — real ERP writes

Use a **test company/agenda** (spec Assumptions).

1. Hook settings: enter the seven identifiers through Settings → Integrations → Younus (delete and
   recreate the hook if it pre-dates this feature — there is no edit form). Confirm the hook JSON
   returns the new keys and a masked token.
2. Reset the sandbox state for the scout (088 risk carried forward) and give the sandbox contact a phone:

   ```ruby
   scout = Scout.find(<id>)
   conv  = Custom::ScoutV2::PlaygroundConversation.for(scout)
   conv.contact.update!(phone_number: '+55<test number>')
   ScoutConversationState.where(conversation_id: conv.id).delete_all
   ```
3. In the Scout playground run the scripted lead: qualify → (same turn) scheduling → answer the day →
   pick an offered time → confirm. Expect: ≤ 3 times, natural language, appointment visible in the ERP,
   turn ends with `exit_agendado` reporting start + reference.
4. Open the Langfuse trace: each `scheduling_*`/`customer_registry_*` tool span carries
   `capability_call` with `injected` equal to the hook's identifiers (and the normalized phone), no token.
5. Repeat for: empty day → nearest date (≤ 3 following days probed) → decline all (`exit_sem_horario` + `motivo`); ask for a
   person (`exit_handoff`); sandbox contact without phone (handoff naming the missing phone, no ERP
   request in the ERP logs); wrong `token` in the hook (handoff, no booking promise).
6. Send another message after each outcome: scheduling is not pinned, no times offered.
7. Regression: open the contact panel of a real contact — the ERP data card renders as before.

## 5. Deliberate-mutant checks (Principle VII)

Each mutation must turn at least one named example red.

| Mutation in production code | Example that must fail |
|---|---|
| `Operation#problems_for` stops flagging a missing required input | `operation_tool_spec` (US1-AS1: request made / no error) |
| `date` type accepts any string | `operation_tool_spec` (US1-AS2) |
| Client sends `idEmpresa` (or any identifier) from an argument instead of `settings` | `client_spec` distinctive-value examples |
| Token added to `CallRecord#injected` | `operation_tool_spec` (US2-AS9) |
| `Registry` drops the `feature_allowed?` check / the non-blank check | `registry_spec` |
| `Registry` resolves both capabilities from one shared check | `registry_spec` (independence) |
| `Scheduling#book` skips the offered-slot membership check | `scheduling_spec` (US2-AS8) |
| `Scheduling#book` skips the customer precondition | `scheduling_spec` |
| `remember_slots!` replaces instead of merging | `scheduling_spec` (earlier listing stays bookable) |
| `Preconditions['booking']` always passes | `exit_tool_spec` (US3-AS9) |
| `ExitTool` runs the precondition after dispatch | `exit_tool_spec` (state unchanged assertion) |
| `actions_for` registers capability tools even when `requires` unsatisfied | `turn_scope_spec` |
| `actions_for` registers capability tools for takeover playbooks | `turn_scope_spec` / `open_playbook_spec` |
| `find_by_phone` picks the first of several matches | `customer_registry_spec` (FR-016) |
| `OperationTool` retries on `Erp::ApiError` | `operation_tool_spec` (request count = 1) |
| `OperationTool` rescues `StandardError` broadly | `operation_tool_spec` (non-ERP exception propagates) |
| `ContentBuilder` omits `PHONE_MISSING_NOTICE` | `content_builder_spec` |
| Snapshot builder returns `[]` again | `builder_spec` + `playground_scheduling_spec` |
| `Scheduling#book` ignores an already remembered booking | `scheduling_spec` (FR-028) |
| `create` returns `created` and/or remembers a customer when the answer has no id | `customer_registry_spec` (FR-029) |
| `find_by_phone` returns `not_found` for a single match without a readable id | `customer_registry_spec` (FR-029) |
| `book` returns the data (or remembers a booking) when `appointment_id` is missing | `scheduling_spec` (FR-028) |
| `OperationTool` gives `AuthenticationError` the "outcome unknown" text, or a timeout the definitive text | `operation_tool_spec` (FR-015) |
