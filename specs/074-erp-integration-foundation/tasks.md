---
description: "Task list template for feature implementation"
---

# Tasks: ERP Integration Foundation & Younus Setup

**Input**: Design documents from `/specs/074-erp-integration-foundation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md, tdd/test-list.md

**Tests**: Constitution Principle VI (Test-Driven Development, NON-NEGOTIABLE) and plan.md commit to RSpec + Vitest test-first coverage for every behavior. Real entry points are covered by an RSpec request spec and Vitest router/component specs. Test tasks are MANDATORY: every behavior has a test task that MUST be observed failing first before its implementation task.

**Organization**: Tasks are grouped into logical execution phases and prioritized by user story (spec.md priorities P1/P1/P2) with strict TDD ordering (tests written and confirmed failing before their implementation). Every behavioral task carries its behavior identifier marker in brackets (e.g. `[U1]`, `[A1]`, `[CB1]`).

## Format: `[ID] [P?] [Story] [Behavior] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- **[Marker]**: Stable behavior marker(s) matching `tdd/test-list.md` (`[A1]..[A13]`, `[U1]..[U43]`, `[CB1]..[CB2]`)
- Every upstream-file edit (any file outside `custom/`) MUST add its MANIFEST entry to `bin/sync-custom-module-hooks` in the SAME task per AGENTS.md — this is called out explicitly in the task description, not deferred to Polish.

## Path Conventions

Web app (Rails JSON API backend + Vue 3 SPA frontend), per plan.md Project Structure:
- Backend core (upstream, extension points only): `app/models/integrations/`, `app/views/api/v1/models/`, `config/`
- Backend fork logic (isolated): `custom/app/services/erp/`, `custom/app/models/custom/integrations/`, `custom/spec/`
- Frontend core (upstream, extension points only): `app/javascript/dashboard/routes/dashboard/settings/integrations/`, `app/javascript/dashboard/featureFlags.js`, `app/javascript/dashboard/i18n/locale/`
- Sync manifest: `bin/sync-custom-module-hooks`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Register the account feature flag, the `younus` app catalog entry, and static icons that every later phase reads. No new gem dependencies (`httparty`, `json_schemer`, `webmock` already present in Gemfile/Gemfile.lock).

- [X] T001 [P] [U2] Add `erp_integration` feature flag to `config/features.yml` (append at end of file, per its "New flags MUST set `column: feature_flags_ext_1`" rule): `name: erp_integration`, `display_name: ERP Integration`, `enabled: false`, `column: feature_flags_ext_1`. Add the matching MANIFEST entry (`file`, `anchor`: current last entry `delayed_automations` block, `insert`: new `erp_integration` block) to `bin/sync-custom-module-hooks`. — FR-001
- [X] T002 [P] [U1] Add a `younus` entry to `config/integration/apps.yml` following the existing `leadsquared`/`dyte` entries' shape: `id: younus`, `logo: younus.png`, `i18n_key: younus`, `hook_type: account`, `allow_multiple_hooks: false`, `category: erp`, `feature_flag: erp_integration`, `visible_properties: ['id_empresa', 'token']`, `settings_json_schema` requiring `token`/`id_empresa` strings with `additionalProperties: false`, and `settings_form_schema` with two required text fields (`token` labeled "API Token", `id_empresa` labeled "Company ID") — exact shapes in data-model.md §2.1/§2.2 and contracts/apps-api.md §3.1. Add the MANIFEST entry. — FR-005, FR-007
- [X] T003 [P] [U33] Add `ERP_INTEGRATION: 'erp_integration'` to the `FEATURE_FLAGS` object in `app/javascript/dashboard/featureFlags.js`. Add the MANIFEST entry. — FR-001
- [X] T004 [P] Add placeholder light/dark integration icons to `public/dashboard/images/integrations/`: `erp.png`, `erp-dark.png`, `younus.png`, `younus-dark.png` (new files, no MANIFEST entry needed — they don't overwrite any upstream asset). — supports FR-003, FR-005 rendering in `IntegrationItem.vue`/`SingleIntegrationHooks.vue`

**Checkpoint**: Feature flag, app catalog entry, and frontend flag constant exist. No behavior changes yet — nothing reads them until Phase 3+.

---

## Phase 2: Foundational & Extensible ERP Framework (Priority: P2 / Blocking Prerequisite)

**Purpose**: The abstract ERP provider contract and factory that User Story 2 (concrete Younus adapter) and User Story 3 (extensibility) build on. Following Constitution Principle VI (TDD), tests are created first, proven to fail against absent classes, then implemented. Entirely new files under `custom/app/services/erp/` and `custom/spec/services/erp/`.

**⚠️ CRITICAL**: User Story 2 cannot implement synchronous credential validation without these classes.

### Tests for Provider Framework (TDD - Write First)

- [X] T039 [P] [US3] [U3] RSpec `custom/spec/services/erp/errors_spec.rb`: verifies error classes `Erp::Error < StandardError`, `Erp::AuthenticationError < Erp::Error`, and `Erp::ApiError < Erp::Error` are defined and inherit correctly per data-model.md §3.4. (Watch fail before T007 exists per Principle VI). — FR-009, FR-010
- [X] T005 [P] [US3] [U4] [U5] [U6] [A13] RSpec `custom/spec/services/erp/base_adapter_spec.rb`: `Erp::BaseAdapter#initialize` stores hook and settings; a subclass that does not override `test_connection` raises `NotImplementedError` naming the missing method when called; a subclass that does not override `self.erp_name` raises `NotImplementedError` naming the missing method when called — matching quickstart.md Scenario 7. (Watch fail before T008 exists per Principle VI). — FR-012, FR-014
- [X] T006 [P] [US3] [U7] [U8] [A11] [A12] RSpec `custom/spec/services/erp/adapter_factory_spec.rb`: `Erp::AdapterFactory.build(hook)` returns an `Erp::Younus::Adapter` instance for `hook.app_id == 'younus'`; raises `ArgumentError` with message `"Unsupported ERP provider: #{app_id}"` for an unregistered `app_id` (e.g. `'unknown_erp'`), matching quickstart.md Scenario 7. (Watch fail before T009 exists per Principle VI). — FR-013

### Implementation for Provider Framework

- [X] T007 [P] [US3] [U3] Create `custom/app/services/erp/errors.rb` defining `Erp::Error < StandardError`, `Erp::AuthenticationError < Erp::Error`, `Erp::ApiError < Erp::Error` (research.md §2, data-model.md §3.4). (Turns T039 green). — supports FR-009, FR-010
- [X] T008 [P] [US3] [U4] [U5] [U6] [A13] Create `custom/app/services/erp/base_adapter.rb`: `Erp::BaseAdapter` with `initialize(hook)` storing `@hook = hook`, `@settings = hook.settings || {}`; `self.erp_name` raising `NotImplementedError` naming the class/method when not overridden; instance method `test_connection` raising `NotImplementedError` naming the class/method when not overridden (data-model.md §3.1). (Turns T005 green). — FR-012, FR-014
- [X] T009 [P] [US3] [U7] [U8] [A11] [A12] Create `custom/app/services/erp/adapter_factory.rb`: `Erp::AdapterFactory.build(hook)` — `case hook.app_id` `when 'younus'` returns `Erp::Younus::Adapter.new(hook)`, `else` raises `ArgumentError, "Unsupported ERP provider: #{hook.app_id}"` (data-model.md §3.2). Constant reference to `Erp::Younus::Adapter` is lazily resolved by Ruby and does not require that class to exist yet. (Turns T006 green). — FR-013

### Outer-Loop Acceptance Verification for User Story 3

- [X] T041 [US3] [A11] [A12] [A13] Verify outer-loop acceptance tests A11 (factory returns Younus adapter), A12 (factory raises ArgumentError on unknown provider), and A13 (base contract raises NotImplementedError on unimplemented methods) pass and are green. — FR-012, FR-013, FR-014

**Checkpoint**: Provider contract + factory exist, are tested test-first, and are independently loadable. User Story 2 can now build the concrete Younus adapter on top of them.

---

## Phase 3: User Story 1 - Account-Level ERP Integration Feature Enablement (Priority: P1) 🎯 MVP (part 1/2)

**Goal**: Super Admins gate ERP visibility per account via the `erp_integration` flag; enabled accounts see a unified "ERP" card in Settings > Integrations that navigates to a provider selection gallery listing Younus.

**Independent Test**: Toggle `erp_integration` for an account in Super Admin; verify the "ERP" card appears/disappears in Settings > Integrations and that `/settings/integrations/erp` is reachable only when enabled.

### Characterization Baseline (TDD - Brownfield)

- [X] T044 [P] [US1] [CB1] Run existing `spec/models/integrations/app_spec.rb` to confirm characterization baseline for `Integrations::App#active?` (slack, linear, shopify, leadsquared, notion) passes unmodified before adding custom extensions. — FR-015
### Tests for User Story 1 (TDD - Write First)

- [X] T010 [P] [US1] [U1] [U2] [U21] [U22] [U23] [U42] RSpec `custom/spec/models/custom/integrations/app_spec.rb`: `Integrations::App.find(id: 'younus').active?(account)` returns `false` when `account.feature_enabled?('erp_integration')` is `false`, `true` when enabled; verify a non-erp app (e.g. `slack`) is unaffected by the override (still resolves through the original `active?` case logic); verifies app catalog translations exist. (Watch fail before T014/T015 per Principle VI). — FR-002, FR-003, FR-015, FR-016
- [X] T011 [P] [US1] [U35] [U36] [U37] [U43] [A1] [A3] [A4] Vitest `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js` (extend or create): with a mocked `integrations/getAppIntegrations` store list containing a `category: 'erp'` app, asserts a single synthesized "ERP" card renders (not the raw Younus entry) and links to `/settings/integrations/erp`; asserts no ERP card renders when no `category: 'erp'` app is present in the list; verifies card enabled status derived from hooks. — FR-003, FR-004, FR-016
- [X] T012 [P] [US1] [U38] [U39] [A5] Vitest `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Erp/Index.spec.js`: given a `category: 'erp'` app (Younus) in the store, renders it with its logo/name and a "Configure" action; renders the not-connected status when it has no hooks; renders header with back button navigating to `settings_applications`. — FR-004, FR-005, FR-006

- [X] T013 [P] [US1] [U33] [U34] [A2] Vitest `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/integrations.routes.spec.js`: `beforeEnter` guard on the `erp` route redirects away when `accounts/isFeatureEnabledonAccount` is `false` for `FEATURE_FLAGS.ERP_INTEGRATION`, and allows navigation when `true`. — FR-002, FR-004

- [X] T014 [P] [US1] [U21] [U22] [U23] Create `custom/app/models/custom/integrations/app.rb`: `module Custom::Integrations::App` overriding `#active?(account)` — when `params[:category] == 'erp'`, return `account.feature_enabled?(params[:feature_flag])` (guard for blank `feature_flag`); otherwise call `super`. Follows the `custom/app/models/custom/conversation.rb` pattern (bare module, no explicit `prepend`). — FR-002, FR-003, FR-015
- [X] T015 [US1] [U21] [U22] [U23] Add `Integrations::App.prepend_mod_with('Integrations::App')` at the end of `app/models/integrations/app.rb`, mirroring `AutomationRules::ActionService.prepend_mod_with(...)` in `app/services/automation_rules/action_service.rb`. Add the MANIFEST entry (anchor: file's closing `end`). (depends on T014; turns T010 green). — FR-002, FR-003
- [X] T017 [P] [US1] [U38] [U39] [A5] Create `app/javascript/dashboard/routes/dashboard/settings/integrations/Erp/Index.vue`: `SettingsLayout` + `BaseSettingsHeader` (title `$t('INTEGRATION_SETTINGS.ERP.HEADER')`, `back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"` returning to `settings_applications`), body renders `IntegrationItem` for every entry in `integrations/getAppIntegrations` with `category === 'erp'` (reuses the existing enabled/disabled `Label` and "Configure" routing from `IntegrationItem.vue` — no new status-badge logic needed). (Turns T012 green). — FR-004, FR-005, FR-006
- [X] T016 [P] [US1] [U33] [U34] [A2] In `app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js`, import `Erp/Index.vue` and add a `{ path: 'erp', name: 'settings_integrations_erp', component: ErpIndex, meta: { featureFlag: FEATURE_FLAGS.ERP_INTEGRATION, permissions: ['administrator'] }, beforeEnter: ... }` route in the same `children` array as `slack`/`notion`/`shopify`, placed before the catch-all `:integration_id` route; guard checks `store.getters['accounts/isFeatureEnabledonAccount'](accountId, FEATURE_FLAGS.ERP_INTEGRATION)` and redirects to the account dashboard when disabled. Add the MANIFEST entry. (Turns T013 green). — FR-002, FR-004
- [X] T018 [US1] [U35] [U36] [U37] [A1] [A3] [A4] In `app/javascript/dashboard/routes/dashboard/settings/integrations/Index.vue`, change `integrationList`/`filteredIntegrationList` computed logic to exclude individual apps with `category === 'erp'` from the grid and, when at least one `category === 'erp'` app is present (i.e. the account has `erp_integration` visible per T014/T015's `active?` gating), splice in one synthesized card: `{ id: 'erp', name: t('INTEGRATION_APPS.ERP.NAME'), description: t('INTEGRATION_APPS.ERP.DESCRIPTION'), enabled: <true if any erp app has hooks>, logo: 'erp.png' }` so `IntegrationItem`'s existing `actionURL` computed (`/settings/integrations/${id}`) routes to the new `erp` path unchanged. Add the MANIFEST entry. (Turns T011 green). — FR-003, FR-004
- [X] T019 [P] [US1] [U43] Add `"ERP": { "NAME": "ERP", "DESCRIPTION": "..." }` under `INTEGRATION_APPS` in `app/javascript/dashboard/i18n/locale/en/integrationApps.json`, and `"ERP": { "HEADER": "ERP Integrations" }` under `INTEGRATION_SETTINGS` in `app/javascript/dashboard/i18n/locale/en/integrations.json` (sibling to the existing `SHOPIFY` block). Add both files to MANIFEST or `out_of_scope` in `bin/sync-custom-module-hooks`. — FR-016
- [X] T020 [P] [US1] [U43] Mirror T019 with Brazilian Portuguese copy in `app/javascript/dashboard/i18n/locale/pt_BR/integrationApps.json` and `pt_BR/integrations.json`. Add both files to MANIFEST or `out_of_scope` in `bin/sync-custom-module-hooks`. — FR-016

### Outer-Loop Acceptance Verification for User Story 1

- [X] T042 [US1] [A1] [A2] [A3] [A4] Verify outer-loop acceptance tests A1 (ERP card absent when disabled), A2 (redirect when disabled), A3 (unified ERP card visible when enabled), and A4 (ERP card click navigates to `/settings/integrations/erp`) pass and are green. — FR-002, FR-003, FR-004

**Checkpoint**: With `erp_integration` enabled, Settings > Integrations shows one "ERP" card; clicking it opens `/settings/integrations/erp` listing Younus as "Disabled"/not configured. With the flag disabled, the card and route are inaccessible. Fully testable without any Younus backend logic (Phase 4).

---

## Phase 4: User Story 2 - Younus Credential Setup with Live Validation & Masking (Priority: P1) 🎯 MVP (part 2/2)

**Goal**: An administrator picks Younus, enters API Token + Company ID, and the system synchronously validates against the live Younus API before persisting — rejecting invalid credentials, rejecting unreachable/erroring services, and on success storing the hook enabled with the token masked. In the connected view, the Company ID is displayed in cleartext and the API Token is masked with dots (`••••••••`).

**Independent Test**: From the ERP provider gallery, open the Younus form and submit blank / invalid / unreachable-service / valid credential payloads; verify synchronous validation blocks or allows the save accordingly and updates connection state; verify connected hook view renders cleartext Company ID and masked token.

### Characterization Baseline (TDD - Brownfield)

- [X] T045 [P] [US2] [CB2] Run existing `spec/models/integrations/hook_spec.rb` to confirm characterization baseline for `Integrations::Hook` validations and lifecycle (slack, dyte, dialogflow, openai) passes unmodified before adding custom extensions. — FR-015
### Tests for User Story 2 (TDD - Write First)

- [X] T022 [P] [US2] [U9] [U10] [U11] [U12] [U13] [U14] [U15] [U16] [U17] RSpec `custom/spec/services/erp/younus/client_spec.rb` using WebMock against `stub_request(:get, %r{wfh\.ichatr\.com\.br/webhook/pessoas})`: covers `sucesso: true` (returns `dados[0]['json']`), `sucesso: false` (returns `nil`, no exception), `401`/`403` (raises `Erp::AuthenticationError`), `503`/`5xx` (raises `Erp::ApiError`), `Net::OpenTimeout`/`Net::ReadTimeout`/`Timeout::Error` (raises `Erp::ApiError, 'Connection timed out'`), `SocketError`/`Errno::ECONNREFUSED` (raises `Erp::ApiError, 'Network error'`), malformed JSON body (raises `Erp::ApiError, 'Malformed response from ERP'`) — per contracts/younus-remote-api.md §2. (Watch fail before T026 exists per Principle VI). — FR-008, FR-0…
- [X] T023 [P] [US2] [U18] [U19] [U20] RSpec `custom/spec/services/erp/younus/adapter_spec.rb`: `test_connection` returns `true` when the client call succeeds (both found and not-found bodies); propagates `Erp::AuthenticationError`/`Erp::ApiError` raised by the client; confirms it calls `search_by_phone('0')`. (Watch fail before T027 exists per Principle VI). — FR-008, FR-009, FR-010, FR-012
- [X] T024 [P] [US2] [U24] [U25] [U26] [U27] [U28] [U29] [U30] [U31] [U41] RSpec `custom/spec/models/custom/integrations/hook_spec.rb`: blank `token`/`id_empresa` fails `validate_settings_json_schema` without any HTTP request (`WebMock.disable_net_connect!` stays untouched); a stubbed `401`/`403` blocks save and sets `errors[:base]` to `I18n.t('errors.erp.invalid_credentials')`; a stubbed `503`/timeout blocks save and sets `errors[:base]` to `I18n.t('errors.erp.connection_error')`; a stubbed valid `200` response saves the hook `enabled`, strips leading/trailing whitespace from `token`/`id_empresa` before persisting while preserving special characters, and `masked_settings['token'] == '••••••••'` while `masked_settings['id_empresa']` stays cleartext; a disabled hook or an update that doesn't touch `settings`/`status` skips validation; non-ERP hooks bypass ERP validation. (Watch fail before T030/T031 per Principle VI). — FR-008 through FR-011, FR-015, FR-016
- [X] T040 [P] [US2] [A6] [A7] Vitest `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/NewHook.spec.js`: verifies that opening the Younus configuration modal renders required FormKit input fields for API Token (`token`) and Company ID (`id_empresa`), and that submitting with blank inputs triggers client-side validation errors and blocks submission without dispatching any network request. (Watch fail before T002/T017 per Principle VI). — FR-006, FR-007
- [X] T025 [P] [US2] [U40] [A10] Vitest `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/SingleIntegrationHooks.spec.js`: when an integration has a connected hook (`hasConnectedHooks: true`), asserts that `SingleIntegrationHooks.vue` renders the configured properties — Company ID in cleartext and API Token masked as `••••••••` — alongside the Disconnect button. (Watch fail before T033 per Principle VI). — FR-011
- [X] T021 [P] [US2] [U32] [A8] [A9] [A10] RSpec request spec `custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb`: exercises real API entry points `POST /api/v1/accounts/:account_id/integrations/hooks` (200 success with token masked as `••••••••` in serialized JSON response, 422 with `Invalid credentials` error message on 401/403, 422 with `Could not connect to ERP` error message on 503/timeout, 422 when `erp_integration` feature flag is disabled) and `GET /api/v1/accounts/:account_id/integrations/apps` (returns `younus` app in catalog when flag is enabled, omits `younus` when flag is disabled) per Constitution Principle VI. (Watch fail before T030/T031/T032 per Principle VI). — FR-002, FR-008 through FR-011

### Implementation for User Story 2

- [X] T026 [P] [US2] [U9] [U10] [U11] [U12] [U13] [U14] [U15] [U16] [U17] Create `custom/app/services/erp/younus/client.rb`: `Erp::Younus::Client` including `HTTParty`, `base_uri 'https://wfh.ichatr.com.br'`, 5-second timeout; `initialize(token:, id_empresa:)`; `search_by_phone(phone:)` issuing `GET /webhook/pessoas` with query `{ idEmpresa: @id_empresa, nrTelcelpessoa: phone }` and header `{ 'token' => @token, 'Content-Type' => 'application/json' }`; status/body handling exactly per contracts/younus-remote-api.md §2 (401/403 → `Erp::AuthenticationError`; 5xx → `Erp::ApiError`; timeouts/network errors rescued and re-raised as `Erp::ApiError`; 200 with `sucesso: true` → `dados.dig(0, 'json')`; `sucesso: false` → `nil`; malformed JSON → `Erp::ApiError`). (depe…
- [X] T027 [US2] [U18] [U19] [U20] Create `custom/app/services/erp/younus/adapter.rb`: `Erp::Younus::Adapter < Erp::BaseAdapter`; `self.erp_name` returns `'Younus'`; `test_connection` builds `Erp::Younus::Client.new(token: @settings['token'], id_empresa: @settings['id_empresa'])`, calls `client.search_by_phone('0')`, returns `true` unless an exception propagates. (depends on T008, T026; turns T023 green). — FR-008, FR-012
- [X] T028 [US2] [U41] [U42] Add `errors: … erp: { invalid_credentials: 'Invalid credentials', connection_error: 'Could not connect to ERP' }` (sibling block to the existing `errors.openai` block at `config/locales/en.yml:186-187`) and an `integration_apps.younus` block (sibling to `integration_apps.openai` at `config/locales/en.yml:433-436`) with `name: 'Younus'`, `short_description`, `description` matching contracts/apps-api.md's copy. Add both MANIFEST entries. — FR-009, FR-010, FR-016
- [X] T029 [P] [US2] [U41] [U42] Mirror T028 in `config/locales/pt_BR.yml` (sibling to `errors.openai` at `config/locales/pt_BR.yml:168-169` and `integration_apps.openai` at `config/locales/pt_BR.yml:415-418`): `errors.erp.invalid_credentials: 'Credenciais inválidas'`, `errors.erp.connection_error: 'Não foi possível conectar ao ERP'`, plus the Portuguese `integration_apps.younus` block. Add both MANIFEST entries. — FR-016
- [X] T030 [US2] [U24] [U25] [U26] [U27] [U28] [U29] [U30] [U31] Create `custom/app/models/custom/integrations/hook.rb`: `module Custom::Integrations::Hook` adding `erp_integration?` (`app_id == 'younus'`), `before_validation :sanitize_erp_settings` (strips whitespace from string values in `settings` when `erp_integration?`), `validate :validate_erp_credentials, if: :validate_erp_credentials?` where `validate_erp_credentials? = erp_integration? && enabled? && (new_record? || will_save_change_to_settings? || will_save_change_to_status?)`, resolving `Erp::AdapterFactory.build(self).test_connection` and translating `Erp::AuthenticationError` → `errors.add(:base, I18n.t('errors.erp.invalid_credentials'))`, `Erp::ApiError`/`StandardError` → `errors.add(:base, I18…
- [X] T031 [US2] [U24] [U25] [U26] [U27] [U28] [U29] [U30] [U31] Add `Integrations::Hook.prepend_mod_with('Integrations::Hook')` at the end of `app/models/integrations/hook.rb`. Add the MANIFEST entry. (depends on T030). — FR-008 through FR-011
- [X] T032 [US2] [U32] [A10] In `app/views/api/v1/models/_hook.json.jbuilder`, replace the raw `resource.settings` read with `resource.respond_to?(:masked_settings) ? resource.masked_settings : resource.settings` before filtering by `visible_properties`. Add the MANIFEST entry. (depends on T030; turns T021 green). — FR-011
- [X] T033 [US2] [U40] [A10] Update `app/javascript/dashboard/routes/dashboard/settings/integrations/SingleIntegrationHooks.vue`: below the description, when `hasConnectedHooks` is true, render a configuration details section displaying the configured `visible_properties` / `settings` (e.g. `Company ID: {{ integration.hooks[0].settings.id_empresa }}` and `API Token: {{ integration.hooks[0].settings.token }}`). Add the MANIFEST entry. (Turns T025 green). — FR-011
- [X] T034 [US2] [U31] [CB2] Run the existing `spec/models/integrations/hook_spec.rb` (openai/slack/dyte suites) unmodified and confirm all still pass — proves `Custom::Integrations::Hook`'s `erp_integration?`-gated callbacks/validations don't affect non-younus hooks. (Characterization regression defense). — FR-015

### Outer-Loop Acceptance Verification for User Story 2

- [X] T043 [US2] [A5] [A6] [A7] [A8] [A9] [A10] Verify outer-loop acceptance tests A5 (Younus rendered with status in ERP gallery), A6 (API Token and Company ID fields rendered), A7 (blank inputs blocked on client), A8 (invalid credentials rejected with 422), A9 (service failure rejected with 422), and A10 (valid credentials save enabled hook with masked token and cleartext company ID) pass and are green. — FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011

**Checkpoint**: MVP complete. An administrator can enable the flag (US1), open the Younus form, get accurate synchronous accept/reject feedback with correct masking over the wire, and see cleartext Company ID and masked token on the connected settings card (US2), with zero behavior change to existing integrations.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Verify zero regressions and zero upstream-sync gaps across the whole feature.

- [X] T035 Run `docker compose exec rails ruby bin/sync-custom-module-hooks --check` and `--audit`; resolve any gap left by T001, T002, T003, T015, T016, T018, T019, T020, T028, T029, T031, T032, T033's MANIFEST entries or exclusions until both report 0 gaps (quickstart.md §3.4).
- [X] T036 [P] Run `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/integrations/ custom/spec/services/erp/ custom/spec/models/custom/integrations/ spec/models/integrations/hook_spec.rb` and `docker compose exec rails bundle exec rubocop` — full suite green, 0 RuboCop offenses.
- [X] T037 [P] Run `docker compose exec vite pnpm test` and `docker compose exec vite pnpm eslint` — full suite green, 0 ESLint errors.
- [X] T038 Manually walk quickstart.md Scenarios 1–7 in the running dev stack, confirming feature gating, connection validation, masking, framework extensibility, and that the Slack/Notion/Shopify/CRM cards in Settings > Integrations are visually and functionally unchanged (SC-005).


---

## Phase 6: TDD Remediation

**Purpose**: Address non-blocking findings identified during `/speckit-tdd-verify` audit.

- [X] T046 [P] [Finding 1] Refactor `custom/spec/services/erp/base_adapter_spec.rb:11-12,16` to eliminate implementation coupling (`instance_variable_get` on `@hook` and `@settings`), verifying initialization through subclass collaborator behavior. Command: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/base_adapter_spec.rb`.
- [X] T047 [P] [Finding 2] Refactor `custom/spec/services/erp/younus/client_spec.rb:32` to assert timeout behavior via simulated delay/timeout rather than inspecting `default_options[:timeout]`. Command: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/younus/client_spec.rb`.
---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T001–T004 can start immediately, all in parallel.
- **Foundational & Framework (Phase 2)**: Independent of Setup (different files) but logically precedes User Story 2. T039, T005, T006 (tests) precede T007–T009 (implementation) per TDD; T041 verifies outer loop.
- **User Story 1 (Phase 3)**: Depends only on Setup (T001, T002, T003 for the flag/catalog entry/frontend constant it gates on). Does NOT depend on Foundational (Phase 2) or User Story 2. T044 (characterization baseline) and T010–T013 (tests) precede T014–T020 (implementation) per TDD; T042 verifies outer loop.
- **User Story 2 (Phase 4)**: Depends on Setup (T002 for the app catalog entry/schema) and Foundational (T007–T009). Does NOT depend on User Story 1's frontend work. T045 (characterization baseline) and T021–T025, T040 (tests) precede T026–T034 (implementation) per TDD; T043 verifies outer loop.
- **Polish (Phase 5)**: Depends on all of Phases 1–4 being complete.

### User Story Dependencies

- **User Story 1 (P1)**: No dependency on US2/US3. Independently testable once Setup is done — the Younus card will show as "Disabled" with no backend adapter required.
- **User Story 2 (P1)**: No dependency on US1's frontend work. Independently testable via RSpec request specs (T021) and CLI (quickstart.md Scenarios 4–6) once Setup + Foundational are done.
- **User Story 3 (P2)**: Framework contract and factory are built and tested test-first in Phase 2 (T005, T006, T008, T009, T039, T041). Verified end-to-end in Phase 5 (T038 / quickstart.md Scenario 7).

### Within Each User Story

- Tests are written first and MUST fail before their paired implementation task:
  - Phase 2: T039 ↔ T007, T005 ↔ T008, T006 ↔ T009, verified by T041
  - Phase 3: T010 ↔ T014/T015, T011 ↔ T018, T012 ↔ T017, T013 ↔ T016, verified by T042
  - Phase 4: T022 ↔ T026, T023 ↔ T027, T024 ↔ T030/T031, T040 ↔ T002/T017, T025 ↔ T033, T021 ↔ T030/T031/T032, regression guarded by T034, verified by T043
- Within US1: `app.rb` module (T014) before its `prepend_mod_with` wiring (T015); route (T016) and gallery component (T017) feed Index.vue grouping (T018).
- Within US2: error classes (T007) → client (T026) → adapter (T027) → hook model (T030) → `prepend_mod_with` wiring (T031) and jbuilder masking (T032); `SingleIntegrationHooks.vue` (T033).

### Parallel Opportunities

- All Setup tasks (T001–T004) in parallel.
- Foundational tests (T005, T006, T039) in parallel, then foundational classes (T007, T008, T009) in parallel.
- Once Setup completes, User Story 1 and User Story 2 can proceed in parallel (different files end-to-end).
- Polish tasks T036 and T037 (backend vs. frontend suites) run in parallel.

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2 — both P1)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational & Framework
3. Complete Phase 3 (US1) and Phase 4 (US2) — in parallel if staffed, sequentially otherwise
4. **STOP and VALIDATE**: Run quickstart.md Scenarios 1–6 end-to-end
5. Deploy/demo — this is the full MVP (US1 provides UI access; US2 provides Younus connection, synchronous validation, masking, and connected credentials view).

### Incremental Delivery

1. Setup + Foundational → foundation & provider contract ready and verified
2. US1 → verify flag gating/navigation independently (backend adapter not required)
3. US2 → verify synchronous validation independently via RSpec request spec (T021) and CLI (frontend route not required)
4. Combine US1 + US2 → full MVP demo
5. Polish → manifest audit, full suites, regression walkthrough

---

## Notes

- [P] tasks = different files, no dependencies.
- [Story] label maps task to specific user story for traceability.
- [Marker] label maps task to specific behavior id in `tdd/test-list.md`.
- `NewHook.vue`, `IntegrationHooks.vue`, `MultipleIntegrationHooks.vue`, and the `POST/DELETE /integrations/hooks` + `GET /integrations/apps` controllers are all reused unmodified. `SingleIntegrationHooks.vue` is updated via T033 to render configured hook properties (cleartext Company ID and masked token) when connected.
- Every task touching a file outside `custom/` embeds its own `bin/sync-custom-module-hooks` MANIFEST entry — do not defer this to Polish; Polish (T035) only audits for gaps, it does not add first-time entries.
- Commit after each task or logical group.
- Stop at either Phase 3 or Phase 4 checkpoint to validate that story independently before combining.
