---
description: "Task list for ERP Contact Panel Data Card implementation"
---

# Tasks: ERP Contact Panel Data Card

**Input**: Design documents from `/specs/075-erp-contact-data-card/`
- `spec.md` (Clarifications, User Stories, FR-001 to FR-022, SC-001 to SC-011)
- `plan.md` (Architecture, Tech Stack, Whitelist, Formatting, Sub-objects)
- `data-model.md` (Contact, Integrations::Hook, Customer Record, Appointments, Financial, Invariants)
- `research.md` (Resolution Algorithm, Phone Normalization, Younus API, Masks, Footnotes, TDD Strategy)
- `contracts/` (`erp-proxy-api.md`, `younus-remote-api.md`, `erp-adapter-contract.md`, `erp-card-ui-contract.md`)
- `quickstart.md` (Verification Scenarios 1 to 12)
- `.specify/memory/constitution.md` (Principles I–IX, TDD Mandate)

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: Constitution Principle VI (Test-Driven Development, NON-NEGOTIABLE) and `plan.md` mandate test-first coverage for all behavioral changes across both RSpec (backend under `custom/spec/`) and Vitest (frontend under `app/javascript/`). Test tasks are MANDATORY: write tests first, prove they fail for the right reason, then implement.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g., `[US1]`, `[US2]`, `[US3]`; omitted for Setup, Foundational, and Polish phases)
- Include exact file paths in all descriptions
- Include verbatim constraints from `data-model.md` in task descriptions

## Path Conventions

Web application (Rails API backend + Vue 3 SPA frontend):
- Backend custom fork logic (isolated): `custom/app/services/erp/`, `custom/app/controllers/api/v1/accounts/integrations/`, `custom/spec/`
- Backend core routes & locales: `config/routes.rb`, `config/locales/`
- Frontend components & store: `app/javascript/dashboard/components/widgets/conversation/`, `app/javascript/dashboard/store/modules/`, `app/javascript/dashboard/composables/`, `app/javascript/dashboard/api/integrations/`
- Upstream sync tracking: `bin/sync-custom-module-hooks`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, API routing, frontend API client scaffolding, and base localization strings.

- [X] T001 Configure backend proxy route `get 'data', to: 'erp#data'` under `namespace :integrations do resource :erp, only: []` in `config/routes.rb` and add matching MANIFEST entry in `bin/sync-custom-module-hooks`
- [X] T002 [P] Create Vitest unit spec in `app/javascript/dashboard/api/specs/integrations/erp.spec.js` testing ErpAPI ApiClient subclassing, accountScoped URL resolution, and get(contactId) dispatching `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`
- [X] T003 [P] Create frontend API client in `app/javascript/dashboard/api/integrations/erp.js` extending `ApiClient` with method `get(contactId)` dispatching `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`
- [X] T004 [P] Add backend error message localization keys (`errors.erp.service_unavailable`, `errors.erp.not_enabled`, `errors.erp.contact_not_found`) in `config/locales/en.yml` and `config/locales/pt_BR.yml`
- [X] T005 [P] Add frontend localization keys for card states, header, whitelist labels (Nome, CPF, RG, Prontuário, etc.), appointments (`ultimo`, `proximo`), financial (`devedor`, `parcelaVencida` as "Parcela vencida mais antiga", totals), audit footnotes, and empty states in `app/javascript/dashboard/i18n/locale/en/conversation.json` and `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Remote ERP client methods, base adapter primitives, store getters, and UI settings configuration that MUST be complete before ANY user story can be implemented.

**⚠️ CRITICAL**: In accordance with Constitution Principle VI (TDD), tests for foundational behavior MUST be written and confirmed failing before implementation code is written.

### Tests for Foundational Components (TDD - Write First)

- [X] T006 [P] Extend RSpec unit spec in `custom/spec/services/erp/younus/client_spec.rb` testing `find_by_id` (`GET /webhook/pessoa`) with query params `idEmpresa` and `idPessoa`, header `token`, parsed `dados[0]['json']` on success, nil on not found, mapped errors on 401/403/5xx/timeout/network/json-parse, and updating `search_by_phone` tests to expect `{ record: ..., multiple_matches: ... }`
- [X] T007 [P] Extend RSpec unit spec in `custom/spec/services/erp/younus/adapter_spec.rb` testing `find_by_id`, `search_by_phone`, `phone_from`, and `external_id_from` extracting identifiers from Younus payload contracts
- [X] T008 [P] Extend RSpec unit spec in `custom/spec/services/erp/base_adapter_spec.rb` testing `phone_matches?` against exact digit match, Brazil country code prefix `55` normalization (on contact and ERP record), and testing external ID helpers (`external_id_key`, `get_external_id`, `store_external_id`, `clear_external_id`)
- [X] T009 [P] Extend Vitest store spec in `app/javascript/dashboard/store/modules/specs/integrations/getters.spec.js` verifying `getEnabledErpIntegration` returns active ERP app record with enabled hook when active, and undefined when absent or disabled
- [X] T010 [P] Extend Vitest composable spec in `app/javascript/dashboard/composables/spec/useUISettings.spec.js` verifying `{ name: 'erp_data' }` is present in `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` immediately after `contact_attributes`, and `isContactSidebarItemOpen('is_erp_data_open', true)` returns `true` by default

### Implementation for Foundational Components

- [X] T011 [P] Implement `find_by_id(external_id)` and enhance `search_by_phone(phone)` in `custom/app/services/erp/younus/client.rb` querying `GET /webhook/pessoa` and `GET /webhook/pessoas`, returning structured responses with 5s timeout and mapped exceptions (`Erp::AuthenticationError` on 401/403, `Erp::ApiError` on 5xx/timeout)
- [X] T012 [P] Implement subclass primitives and memoized `client` helper in `custom/app/services/erp/younus/adapter.rb`: `find_by_id`, `search_by_phone`, `phone_from`, and `external_id_from`
- [X] T013 [P] Implement helper methods (`get_external_id`, `store_external_id`, `clear_external_id`, `external_id_key`) and `phone_matches?(contact, erp_data)` in `custom/app/services/erp/base_adapter.rb` extracting digits and normalizing prefix `55`
- [X] T014 [P] Add store getter `getEnabledErpIntegration` in `app/javascript/dashboard/store/modules/integrations.js` resolving enabled ERP integration and add matching MANIFEST entry in `bin/sync-custom-module-hooks`
- [X] T015 [P] Insert `{ name: 'erp_data' }` into `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` in `app/javascript/dashboard/composables/useUISettings.js`, update `isContactSidebarItemOpen(key, defaultValue = false)` to return `uiSettings.value[key] ?? defaultValue`, update `toggleSidebarUIState` to negate `!(uiSettings.value[key] ?? defaultValue)`, and add matching MANIFEST entry in `bin/sync-custom-module-hooks`

**Checkpoint**: Foundation ready - user story implementation can now begin.

---

## Phase 3: User Story 1 - Formatted Customer ERP Data Card in Contact Panel (Priority: P1) 🎯 MVP

**Goal**: When viewing a contact with a registered phone number in an account with an active ERP integration, render an "ERP Data" card in the contact panel immediately below contact attributes, expanded by default, displaying customer data with human-friendly labels, structured sections for personal info, appointments (`atendimentos`), and financial status (`financeiro`), localized dates and currency, strict exclusion of technical fields, Brazilian punctuation masks, birthday highlight, and audit footnotes.

**Independent Test**: Open a conversation with a contact whose phone number matches an ERP customer record. Verify that:
1. Technical IDs and internal flags (`idPessoa`, `idEmpresa`, `stPessoa`, etc.) are omitted.
2. Personal details appear with friendly labels (Nome, CPF, RG adjacent to CPF, address group, phones, email, prontuário).
3. Brazilian punctuation masks apply to CPF/CNPJ, CEP, and phone numbers, with safe fallback on irregular values.
4. Date of birth displays in the browser's locale without time, with a prominent birthday highlight badge if today is the contact's birthday.
5. Registration and update timestamps (`dtCadpessoa`, `dtUltaltpessoa`) appear at the bottom of the card as discreet footnotes in italics and smaller font.
6. Appointments (`atendimentos`) display the last and next visits with localized dates, highlighting whether the next visit is confirmed.
7. Financial summary (`financeiro`) displays debtor status with visual highlight when true, oldest overdue installment labeled as "Parcela vencida mais antiga", and localized currency amounts.
8. Multiple matching ERP records display the first record and an informational badge stating multiple records match.
9. Header refresh button re-fetches data on demand, and error states provide a "Retry" button.

### Tests for User Story 1 (TDD - Write First)

- [X] T016 [P] [US1] Create RSpec request spec in `custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb` testing `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`: returns 401 for unauthenticated requests, returns 404 with `{ error: 'ERP integration not found or not enabled' }` when account has no enabled ERP hook, returns 404 with `{ error: 'Contact not found' }` when contact does not exist, returns 200 with `{ status: 'found', data: <hash>, multiple_matches: false }` on single match, returns 200 with `{ status: 'found', data: <hash>, multiple_matches: true }` on multiple matches, and returns HTTP 503 with `{ error: <message> }` when adapter raises `Erp::AuthenticationError` or `Erp::ApiError`
- [X] T017 [P] [US1] Create Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing whitelist filtering and friendly labels: excludes 21 technical keys verbatim (`idPessoa`, `idEmpresa`, `pessoaTipo`, `tpPessoa`, `nmPaispessoa`, `idProfpessoa`, `idUsuario`, `idEspecpessoa`, `dtUltacesso`, `stTermo`, `stCadastro`, `stPessoa`, `idConvenio`, `nmConvenio`, `idPerfil`, `observacoes`, `origemPessoa`, `nrConselho`, `siglaConselho`, `ufConselho`, `indClientePadrao`), suppresses unmapped extra fields per strict whitelist policy, renders `nrFicha` with friendly label "Prontuário", and positions `nrRgpessoa` immediately adjacent to `nrCpfcnpjpessoa`
- [X] T018 [P] [US1] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing value formatting and masks: CPF `000.000.000-00` (11 digits), CNPJ `00.000.000/0000-00` (14 digits), CEP `00000-000` (8 digits), mobile `(00) 00000-0000` (11 digits), landline `(00) 0000-0000` (10 digits), safe fallback to raw value on irregular lengths, `dtNascpessoa` formatted in browser locale without time component (`DD/MM/YYYY`), and prominent birthday badge `erp-birthday-badge` (`🎂 Aniversariante hoje`) rendered when contact birth day and month match current calendar date
- [X] T019 [P] [US1] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing structured sub-objects and footnotes: `atendimentos` (`ultimo` with localized date/time, `comQuem`, `compareceu`; `proximo` with localized date/time, `comQuem`, and confirmation badge `erp-appointment-confirmed-badge` when `confirmado === true`, or friendly empty indicator when null); `financeiro` (debtor warning badge `erp-debtor-badge` when `devedor === true`, `parcelaVencida` labeled as "Parcela vencida mais antiga" with localized due date, `valor`, and `valorCorrigido` formatted as currency, `proximaParcela`, and totals `totalFinanceiro`, `totalRecebido`, `totalAberto`, `totalDevedor` formatted as currency); and audit footnotes (`erp-audit-footnotes`) rendering `dtCadpessoa` and `dtUltaltpessoa` as discreet timestamps in italics at the bottom of the card
- [X] T020 [P] [US1] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing card controls and lifecycle: loading spinner (`erp-loading-spinner`), multiple matches badge (`erp-multiple-matches-badge`), error alert with "Retry" button invoking `fetchErpData`, manual refresh method `fetchErpData` exposed via `defineExpose`, and discarding stale in-flight responses when `contactId` prop changes rapidly
- [X] T021 [P] [US1] Extend existing Vitest component spec in `app/javascript/dashboard/routes/dashboard/conversation/specs/ContactPanel.spec.js` verifying the "ERP Data" accordion section renders immediately below contact attributes only when `isErpIntegrationEnabled` is true, defaults to expanded, does not render when disabled, and header refresh button triggers `fetchErpData` on the card ref

### Implementation for User Story 1

- [X] T022 [US1] Create controller `custom/app/controllers/api/v1/accounts/integrations/erp_controller.rb` inheriting from `Api::V1::Accounts::Integrations::BaseController`, resolving active enabled ERP hook (`Current.account.hooks.enabled.find(&:erp_integration?)`), resolving contact (`Current.account.contacts.find_by(id: params[:contact_id])`), delegating to `Erp::AdapterFactory.build(hook).fetch_data(contact)`, and rescuing `Erp::AuthenticationError` and `Erp::ApiError` to log via `ChatwootExceptionTracker.new(e, account: Current.account).capture_exception` and render HTTP 503
- [X] T023 [US1] Implement formatting and masking utility functions (CPF/CNPJ mask, CEP mask, phone mask, localized date without time, birthday matching, localized currency formatter, and localized audit timestamp formatter) in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`
- [X] T024 [US1] Implement whitelist filtering and personal attributes section in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue` enforcing strict exclusion of 21 technical keys verbatim, suppression of unmapped or empty attributes, 22-item whitelist ordering, friendly labels (with `nrFicha` as "Prontuário" and RG adjacent to CPF), and prominent birthday badge
- [X] T025 [US1] Implement structured sections for appointments (`atendimentos` with last visit, next visit, confirmation badge, and null fallbacks) and financial status (`financeiro` with debtor warning badge, oldest overdue installment labeled as "Parcela vencida mais antiga", next installment, and currency totals) plus audit footnotes (`dtCadpessoa`, `dtUltaltpessoa`) at the bottom of the card in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`
- [X] T026 [US1] Implement multiple matches badge banner, loading spinner, error alert with "Retry" button, race-condition protection on contact switching, and expose `fetchErpData` via `defineExpose` in `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`
- [X] T027 [US1] Update `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` to compute `isErpIntegrationEnabled`, render `<AccordionItem>` for `element.name === 'erp_data' && isErpIntegrationEnabled` expanded by default via `isContactSidebarItemOpen('is_erp_data_open', true)`, provide header refresh icon button in slot `#button` invoking `erpDataCardRef.value?.fetchErpData()`, render `<ErpDataCard ref="erpDataCardRef" :contact-id="contactId" />`, and update MANIFEST entry in `bin/sync-custom-module-hooks`

**Checkpoint**: At this point, User Story 1 (MVP) is fully functional and testable independently.

---

## Phase 4: User Story 2 - Contact Link Caching and Automatic Invalidation/Recovery (Priority: P1)

**Goal**: Reuse cached external identifier (`contact.additional_attributes['external']["#{erp_name.downcase}_id"]`) on subsequent views for fast direct lookup (`find_by_id`); verify remote record's phone matches contact phone (`phone_matches?`); if phone mismatches or ID lookup returns nil, automatically clear cached identifier (`clear_external_id`), execute single phone search fallback (`search_by_phone`), cache newly resolved ID on contact, and update display; normalize phone numbers by extracting digits and stripping country code `55` prefix.

**Independent Test**: Load a contact's ERP card a second time with unchanged phone to verify direct ID lookup without phone search; change contact phone number or remote record to verify phone mismatch invalidates cached ID, executes single phone search fallback, and updates cache with new customer ID.

### Tests for User Story 2 (TDD - Write First)

- [X] T028 [P] [US2] Extend RSpec unit spec in `custom/spec/services/erp/base_adapter_spec.rb` testing `fetch_data(contact)` resolution flow: invokes `find_by_id` and bypasses phone search when cached ID exists and phone matches; clears cached ID and invokes single `search_by_phone` fallback when cached ID phone mismatches; clears cached ID and invokes single `search_by_phone` fallback when `find_by_id` returns nil; clears cached ID and returns `{ status: 'not_found' }` when fallback search returns nil; caches first record ID and returns `multiple_matches: true` when phone search returns multiple records; and propagates exceptions on external failure

### Implementation for User Story 2

- [X] T029 [US2] Implement complete 6-step resolution algorithm in `Erp::BaseAdapter#fetch_data(contact)` in `custom/app/services/erp/base_adapter.rb`: (1) return `not_found` if `contact.phone_number.blank?`, (2) if cached ID exists invoke `find_by_id(cached_id)`, (3) if found and `phone_matches?(contact, record)` return `{ status: 'found', data: record, multiple_matches: false }`, (4) if ID lookup fails or phone mismatches call `clear_external_id(contact)` and `search_by_phone(contact.phone_number)`, (5) if found by phone call `store_external_id(contact, external_id_from(first_record))` and return `{ status: 'found', data: first_record, multiple_matches: multiple_matches }`, (6) if not found return `{ status: 'not_found' }`
- [X] T030 [US2] Implement safe JSONB attribute storage in `custom/app/services/erp/base_adapter.rb` ensuring `contact.additional_attributes['external'] ||= {}` before storing or deleting `"#{erp_name.downcase}_id"` under `contact.additional_attributes['external']` and calling `contact.save!`

**Checkpoint**: At this point, User Stories 1 AND 2 are fully functional and integrated.

---

## Phase 5: User Story 3 - Friendly Empty State for Contacts Not Found in ERP (Priority: P2)

**Goal**: When viewing a contact with a phone number that does not exist in the ERP, display a clear, friendly empty state explaining that no record was found and suggesting registration in the ERP; when viewing a contact with no phone number, immediately display an empty state explaining that a phone number is required to search the ERP, bypassing external API requests entirely; ensure all UI copy is localized in English and Brazilian Portuguese.

**Independent Test**: Open conversation for a contact with an unregistered phone number and verify empty state suggesting ERP registration; open conversation for a contact with no phone number and verify immediate empty state with zero network requests dispatched; verify all text renders in active locale (`en` and `pt_BR`).

### Tests for User Story 3 (TDD - Write First)

- [X] T031 [P] [US3] Extend RSpec unit spec in `custom/spec/services/erp/base_adapter_spec.rb` testing that `fetch_data(contact)` immediately returns `{ status: 'not_found' }` without invoking `find_by_id` or `search_by_phone` when `contact.phone_number.blank?`
- [X] T032 [P] [US3] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` testing empty state for contact without phone (`erp-no-phone-state` with zero API requests dispatched) and empty state for contact with phone returning `{ status: 'not_found' }` (`erp-not-found-state` displaying friendly registration suggestion)
- [X] T033 [P] [US3] Extend Vitest component spec in `app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js` and RSpec request spec in `custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb` verifying all labels, empty states, badges, and errors exist in English and Brazilian Portuguese locales

### Implementation for User Story 3

- [X] T034 [US3] In `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`, add immediate guard checking `contact.phone_number`: if blank, bypass API call and set state to `no_phone`; if API returns `{ status: 'not_found' }`, set state to `not_found` with localized title and description suggesting registration in the ERP
- [X] T035 [P] [US3] Verify and audit complete localization key parity across `config/locales/en.yml`, `config/locales/pt_BR.yml`, `app/javascript/dashboard/i18n/locale/en/conversation.json`, and `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` for empty states, missing phone notices, multiple matches badge, friendly labels, appointments, and financial sections

**Checkpoint**: All user stories (US1, US2, US3) are independently functional and fully tested.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification, linting, upstream manifest tracking, and end-to-end scenario validation across all stories.

- [X] T036 Run `bin/sync-custom-module-hooks --check` and `bin/sync-custom-module-hooks --audit` to verify 100% manifest tracking and 0 gaps for all modified upstream files (`config/routes.rb`, `useUISettings.js`, `ContactPanel.vue`, and `app/javascript/dashboard/store/modules/integrations.js`)
- [X] T037 [P] Run backend RuboCop check via `docker compose exec rails bundle exec rubocop custom/app/ custom/spec/` to ensure 0 offenses across all new and modified Ruby files
- [X] T038 [P] Run frontend ESLint check via `docker compose exec vite pnpm eslint app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue app/javascript/dashboard/api/integrations/erp.js app/javascript/dashboard/store/modules/integrations.js` to ensure 0 errors
- [X] T039 Run backend RSpec suite for custom ERP services and requests via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/ custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb`
- [X] T040 Run frontend Vitest suite via `docker compose exec vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js app/javascript/dashboard/composables/spec/useUISettings.spec.js app/javascript/dashboard/store/modules/specs/integrations/getters.spec.js app/javascript/dashboard/api/specs/integrations/erp.spec.js app/javascript/dashboard/routes/dashboard/conversation/specs/ContactPanel.spec.js`
- [X] T041 Validate end-to-end quickstart scenarios 1 through 12 from `quickstart.md` ensuring complete system integration, SC-001 response timing (< 2 seconds under normal conditions), and proper error resilience

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 - BLOCKS all user stories
- **User Story 1 (Phase 3 - MVP)**: Depends on Foundational completion - can start immediately after Phase 2
- **User Story 2 (Phase 4)**: Depends on Foundational completion and integrates with US1 resolution logic
- **User Story 3 (Phase 5)**: Depends on US1 component and US2 adapter resolution completion
- **Polish (Phase 6)**: Depends on completion of all user story phases

### User Story Dependencies

- **User Story 1 (P1)**: Core MVP delivery. Can proceed immediately after Foundational Phase 2.
- **User Story 2 (P1)**: Extends resolution and caching in `Erp::BaseAdapter` and adapter primitives. Can be tested independently via unit specs before or in parallel with US1 UI integration.
- **User Story 3 (P2)**: Empty state refinements in frontend component and adapter short-circuit. Can proceed once US1 component and US2 adapter foundation exist.

### Within Each Phase (TDD Discipline)

- Unit/component test tasks marked with `[P]` MUST be written and confirmed failing before implementation tasks.
- Foundational tests (T006–T010) run before foundational implementation (T011–T015).
- Request/component tests (T016–T021) run before controller/component implementation (T022–T027).
- Adapter caching tests (T028) run before resolution implementation (T029–T030).
- Empty state tests (T031–T033) run before empty state implementation (T034–T035).

### Parallel Opportunities

- Phase 1: T002, T003, T004, T005 can run in parallel with T001 (with T002 preceding T003).
- Phase 2: Tests T006, T007, T008, T009, T010 can run in parallel; implementations T011, T012, T013, T014, T015 can run in parallel once tests fail.
- Phase 3: Tests T016, T017, T018, T019, T020, T021 can be written in parallel.
- Phase 4: Test T028 precedes T029, T030.
- Phase 5: Tests T031, T032, T033 can run in parallel.
- Phase 6: T037, T038 can run in parallel.

---

## Parallel Example: User Story 1

```bash
# Launch test creation for User Story 1 together:
Task: "Create RSpec request spec in custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb"
Task: "Create Vitest component spec in app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js testing whitelist filtering and friendly labels"
Task: "Extend Vitest component spec in app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js testing value formatting and masks"
Task: "Extend Vitest component spec in app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js testing structured sub-objects and footnotes"
Task: "Extend Vitest component spec in app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js testing card controls and lifecycle"
Task: "Extend existing Vitest component spec in app/javascript/dashboard/routes/dashboard/conversation/specs/ContactPanel.spec.js"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (routes, API client, locales)
2. Complete Phase 2: Foundational (TDD tests T006–T010 -> implementations T011–T015)
3. Complete Phase 3: User Story 1 (TDD tests T016–T021 -> controller, `ErpDataCard.vue`, `ContactPanel.vue` integration)
4. **STOP and VALIDATE**: Verify User Story 1 end-to-end with an active ERP account (customer data renders below contact attributes, expanded by default, aligned key-value pairs, friendly labels, masks, birthday badge, appointments, financial status, footnotes, header refresh works, error retry works, rapid contact switches do not leak stale data).

### Incremental Delivery

1. Setup + Foundational -> Foundation ready and tested.
2. User Story 1 -> Deliver MVP formatted customer data display in contact panel.
3. User Story 2 -> Add caching, phone verification, and stale link recovery.
4. User Story 3 -> Add friendly empty states for unregistered contacts and contacts without phone.
5. Polish -> Linting, manifest check, full suite run, and quickstart scenario validation.

---

## Notes

- Every task strictly follows `- [ ] [TaskID] [P?] [Story?] Description with file path`.
- Upstream files (`config/routes.rb`, `useUISettings.js`, `ContactPanel.vue`, `app/javascript/dashboard/store/modules/integrations.js`) MUST maintain entries in `bin/sync-custom-module-hooks`.
- No direct database schema modifications or migrations are performed.
- All strings are synchronized across English and Brazilian Portuguese.
