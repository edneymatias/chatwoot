---
feature: 074-erp-integration-foundation
loop: outside-in
profile: .specify/memory/tdd-profile.md
spec_criteria: 13
planned_at: 87a32161da
updated_at: 87a32161da
suite_baseline: red # Ruby full suite has pre-existing order-dependent failure in AgentBuilder; targeted Ruby baseline and full JS suite are clean green
---

# Test List: ERP Integration Foundation & Younus Setup

## Outer loop: acceptance behaviors

One per acceptance criterion in `spec.md`. Each stays red until the feature works
end to end through its real entry point.

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| A1  | An account with `erp_integration` disabled renders the integrations gallery without an "ERP" integration card | US1-AC1, FR-002 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js::renders without ERP card when category erp is absent` |
| A2  | An account with `erp_integration` disabled blocks direct navigation to `/settings/integrations/erp` and redirects to dashboard | US1-AC2, FR-002 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/integrations.routes.spec.js::redirects away when erp_integration is disabled` |
| A3  | An account with `erp_integration` enabled renders a unified "ERP" card in the integrations gallery | US1-AC3, FR-003 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js::renders unified ERP card when category erp is active` |
| A4  | Clicking the unified "ERP" card in the integrations gallery navigates to `/settings/integrations/erp` | US1-AC4, FR-004 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js::navigates to erp provider gallery on click` |
| A5  | Navigating to `/settings/integrations/erp` displays Younus as an available provider with its current connection status and configure action | US2-AC1, FR-005 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Erp/Index.spec.js::renders younus provider with connection status` |
| A6  | Opening the Younus configuration form renders required input fields for API Token and Company ID | US2-AC2, FR-006, FR-007 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/NewHook.spec.js::renders required token and id_empresa fields for younus` |
| A7  | Submitting the Younus configuration form with blank API Token or Company ID blocks submission on the client without sending a network request | US2-AC3, FR-007 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/NewHook.spec.js::blocks submission on empty credentials without network request` |
| A8  | Submitting invalid credentials (HTTP 401/403) synchronously returns HTTP 422 with localized "Invalid credentials" error and does not persist or enable the hook | US2-AC4, FR-008, FR-009 | example | DONE | `custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb::rejects invalid credentials with 422 and invalid credentials message` |
| A9  | Submitting credentials when remote ERP is unavailable (HTTP 503, network failure, or timeout > 5s) synchronously returns HTTP 422 with localized "Could not connect to ERP" error and does not persist or enable the hook | US2-AC5, FR-008, FR-010 | example | DONE | `custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb::rejects remote service failure with 422 and connection error message` |
| A10 | Submitting valid credentials persists the hook enabled, returns HTTP 200 with masked token (`••••••••`) and cleartext Company ID, and connected view displays Company ID in cleartext and token masked | US2-AC6, FR-008, FR-011 | example | DONE | `custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb::saves enabled hook with masked token and cleartext id_empresa` |
| A11 | Resolving provider identifier `younus` through the adapter factory returns an instance of `Erp::Younus::Adapter` conforming to the base ERP contract | US3-AC1, FR-013 | example | DONE | `custom/spec/services/erp/adapter_factory_spec.rb::resolves younus to Younus adapter conforming to base contract` |
| A12 | Resolving an unregistered provider identifier through the adapter factory raises `ArgumentError` naming the unsupported provider | US3-AC2, FR-013 | example | DONE | `custom/spec/services/erp/adapter_factory_spec.rb::raises ArgumentError for unregistered provider` |
| A13 | Invoking required contract methods (`self.erp_name`, `#test_connection`) on an adapter subclass that failed to implement them raises `NotImplementedError` naming the missing method | US3-AC3, FR-012, FR-014 | example | DONE | `custom/spec/services/erp/base_adapter_spec.rb::raises NotImplementedError for unimplemented contract methods` |

## Characterization baselines (existing untouched code)

| id   | behavior | traces | kind | state | test |
| ---- | --- | --- | --- | --- | --- |
| CB1  | `Integrations::App#active?` evaluates slack, linear, shopify, leadsquared, and notion per existing account feature flags and config | FR-015 | characterization | DONE | `spec/models/integrations/app_spec.rb` (16 passing examples) |
| CB2  | `Integrations::Hook` validates settings schema and manages lifecycle for slack, dialogflow, dyte, and openai hooks | FR-015 | characterization | DONE | `spec/models/integrations/hook_spec.rb` (34 passing examples) |

## Inner loop: unit behaviors

Grouped by the component from `plan.md` that owns them. Each line names one
observable result.

### `config/features.yml` and `config/integration/apps.yml`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U1  | `Integrations::App.find(id: 'younus')` loads the app definition with `category: 'erp'`, `feature_flag: 'erp_integration'`, and `visible_properties: ['id_empresa', 'token']` | FR-005, FR-007 | example | DONE | `custom/spec/models/custom/integrations/app_spec.rb::loads younus app definition` |
| U2  | `config/features.yml` defines `erp_integration` account flag with `column: feature_flags_ext_1` and `enabled: false` | FR-001 | example | DONE | `custom/spec/models/custom/integrations/app_spec.rb::feature flag definition` |

### `custom/app/services/erp/errors.rb`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U3  | Defines `Erp::Error < StandardError`, `Erp::AuthenticationError < Erp::Error`, and `Erp::ApiError < Erp::Error` | FR-009, FR-010 | example | DONE | `custom/spec/services/erp/errors_spec.rb::inherits expected error hierarchies` |

### `custom/app/services/erp/base_adapter.rb`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U4  | `Erp::BaseAdapter#initialize` stores the hook instance and defaults settings to empty hash when hook settings are nil | FR-012 | example | DONE | `custom/spec/services/erp/base_adapter_spec.rb::initialization with hook` |
| U5  | `Erp::BaseAdapter.erp_name` raises `NotImplementedError` naming the class and method when not overridden | FR-012, FR-014 | example | DONE | `custom/spec/services/erp/base_adapter_spec.rb::raises NotImplementedError for erp_name` |
| U6  | `Erp::BaseAdapter#test_connection` raises `NotImplementedError` naming the class and method when not overridden | FR-012, FR-014 | example | DONE | `custom/spec/services/erp/base_adapter_spec.rb::raises NotImplementedError for test_connection` |

### `custom/app/services/erp/adapter_factory.rb`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U7  | `Erp::AdapterFactory.build(hook)` returns an `Erp::Younus::Adapter` instance when `hook.app_id` is `'younus'` | FR-013 | example | DONE | `custom/spec/services/erp/adapter_factory_spec.rb::builds younus adapter` |
| U8  | `Erp::AdapterFactory.build(hook)` raises `ArgumentError` with message `"Unsupported ERP provider: unknown_erp"` when `hook.app_id` is unregistered | FR-013 | example | DONE | `custom/spec/services/erp/adapter_factory_spec.rb::raises ArgumentError for unknown provider` |

### `custom/app/services/erp/younus/client.rb`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U9  | Issues `GET /webhook/pessoas` with header `token: <token>`, query params `idEmpresa: <id_empresa>`, and `nrTelcelpessoa: <phone>` | FR-008 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::issues GET with correct headers and query` |
| U10 | Sets default HTTP client network timeout to 5 seconds | FR-010 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::configures 5s timeout` |
| U11 | When remote API returns HTTP 200 with `sucesso: true`, returns parsed record data hash (`dados[0]['json']`) | FR-008 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::returns record hash on sucesso true` |
| U12 | When remote API returns HTTP 200 with `sucesso: false`, returns `nil` without raising an exception | FR-008 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::returns nil on sucesso false` |
| U13 | When remote API returns HTTP 401 or HTTP 403, raises `Erp::AuthenticationError` with message `'Invalid credentials'` | FR-009 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::raises AuthenticationError on 401 and 403` |
| U14 | When remote API returns HTTP 500..599, raises `Erp::ApiError` with status code information | FR-010 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::raises ApiError on 5xx server error` |
| U15 | When request exceeds 5s timeout (`Net::OpenTimeout`, `Net::ReadTimeout`, `Timeout::Error`), rescues and raises `Erp::ApiError, 'Connection timed out'` | FR-010 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::rescues timeouts and raises ApiError` |
| U16 | When network connection fails (`SocketError`, `Errno::ECONNREFUSED`), rescues and raises `Erp::ApiError, 'Network error'` | FR-010 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::rescues connection errors and raises ApiError` |
| U17 | When remote API returns HTTP 200 with malformed JSON body, rescues parser error and raises `Erp::ApiError, 'Malformed response from ERP'` | FR-010 | example | DONE | `custom/spec/services/erp/younus/client_spec.rb::rescues json parse error and raises ApiError` |

### `custom/app/services/erp/younus/adapter.rb`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U18 | `Erp::Younus::Adapter.erp_name` returns `'Younus'` | FR-012 | example | DONE | `custom/spec/services/erp/younus/adapter_spec.rb::returns erp_name Younus` |
| U19 | `Erp::Younus::Adapter#test_connection` invokes `client.search_by_phone('0')` and returns `true` on successful response | FR-008, FR-012 | example | DONE | `custom/spec/services/erp/younus/adapter_spec.rb::returns true on successful search` |
| U20 | `Erp::Younus::Adapter#test_connection` propagates `Erp::AuthenticationError` and `Erp::ApiError` when raised by client | FR-009, FR-010, FR-012 | example | DONE | `custom/spec/services/erp/younus/adapter_spec.rb::propagates client errors` |

### `custom/app/models/custom/integrations/app.rb`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U21 | `Integrations::App#active?(account)` returns `false` for category `'erp'` app when `account.feature_enabled?('erp_integration')` is `false` | FR-002 | example | DONE | `custom/spec/models/custom/integrations/app_spec.rb::inactive when erp_integration is false` |
| U22 | `Integrations::App#active?(account)` returns `true` for category `'erp'` app when `account.feature_enabled?('erp_integration')` is `true` | FR-003 | example | DONE | `custom/spec/models/custom/integrations/app_spec.rb::active when erp_integration is true` |
| U23 | `Integrations::App#active?(account)` delegates to `super` for non-erp apps, preserving existing behavior for slack, linear, shopify, etc. | FR-015 | example | DONE | `custom/spec/models/custom/integrations/app_spec.rb::preserves behavior for non-erp apps` |

### `custom/app/models/custom/integrations/hook.rb`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U24 | Strips leading and trailing whitespace from string values in `settings` (`token`, `id_empresa`) prior to validation when `erp_integration?` is true | FR-008 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::strips whitespace from settings` |
| U25 | Preserves special characters (hyphens, underscores, dots) in `token` and `id_empresa` values without alteration | FR-008 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::preserves special characters in settings` |
| U26 | Triggers synchronous connection validation on save for enabled ERP hooks when settings change or hook is newly created | FR-008 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::validates credentials on save` |
| U27 | When adapter raises `Erp::AuthenticationError`, save halts and adds localized `errors.erp.invalid_credentials` to `errors[:base]` | FR-009 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::adds invalid credentials error on auth failure` |
| U28 | When adapter raises `Erp::ApiError` or standard connection errors, save halts and adds localized `errors.erp.connection_error` to `errors[:base]` | FR-010 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::adds connection error on api failure` |
| U29 | Skips synchronous connection validation when hook is disabled or when an existing hook update does not touch `settings` or `status` | FR-008 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::skips validation when settings unchanged or disabled` |
| U30 | `#masked_settings` returns a hash with `token` masked as `'••••••••'` and `id_empresa` in cleartext for ERP hooks | FR-011 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::masked_settings masks token and keeps id_empresa` |
| U31 | Non-ERP hooks (e.g., slack, dyte, dialogflow) bypass ERP validation rules and whitespace sanitization entirely | FR-015 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::non-erp hooks bypass erp validation` |

### `app/views/api/v1/models/_hook.json.jbuilder`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U32 | Uses `hook.masked_settings` when available so serialized `settings.token` is masked as `'••••••••'` in API JSON responses | FR-011 | example | DONE | `custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb::serializes masked token in response` |

### `app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U33 | Registers child route `erp` pointing to `Erp/Index.vue` with name `settings_integrations_erp` and administrator permission check | FR-004 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/integrations.routes.spec.js::route configuration` |
| U34 | `beforeEnter` route guard checks `accounts/isFeatureEnabledonAccount` for `FEATURE_FLAGS.ERP_INTEGRATION` and redirects to dashboard when false | FR-002 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/integrations.routes.spec.js::guard redirection` |

### `app/javascript/dashboard/routes/dashboard/settings/integrations/Index.vue`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U35 | Filters out individual apps with `category === 'erp'` from direct gallery display and injects one synthesized "ERP" card when at least one ERP app is active | FR-003 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js::synthesizes erp card` |
| U36 | Synthesized ERP card shows `enabled: true` when any active ERP app has connected hooks, and `enabled: false` otherwise | FR-003 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js::card enabled status from hooks` |
| U37 | Synthesized ERP card uses action URL `/settings/integrations/erp` | FR-004 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js::card actionURL` |

### `app/javascript/dashboard/routes/dashboard/settings/integrations/Erp/Index.vue`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U38 | Renders an `IntegrationItem` card for each app in `integrations/getAppIntegrations` where `category === 'erp'`, displaying its logo, name, and status | FR-005 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Erp/Index.spec.js::renders erp providers` |
| U39 | Header renders back button navigating back to `settings_applications` | FR-004, FR-005 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Erp/Index.spec.js::header back button` |

### `app/javascript/dashboard/routes/dashboard/settings/integrations/SingleIntegrationHooks.vue`

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U40 | When `hasConnectedHooks` is true, renders configuration details displaying Company ID in cleartext and API Token masked with dots (`••••••••`) | FR-011 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/SingleIntegrationHooks.spec.js::renders cleartext company id and masked token` |

### Localization (Backend & Frontend)

| id  | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U41 | Backend validation keys `errors.erp.invalid_credentials` and `errors.erp.connection_error` present in `en.yml` and `pt_BR.yml` | FR-016 | example | DONE | `custom/spec/models/custom/integrations/hook_spec.rb::localized error translations exist` |
| U42 | App catalog keys `integration_apps.younus` present in `en.yml` and `pt_BR.yml` | FR-016 | example | DONE | `custom/spec/models/custom/integrations/app_spec.rb::localized app translations exist` |
| U43 | Frontend UI translation keys `INTEGRATION_APPS.ERP` and `INTEGRATION_SETTINGS.ERP` present in `en/` and `pt_BR/` JSON files | FR-016 | example | DONE | `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js::frontend i18n keys exist` |

## Invariants and edge cases still to place

- Concurrent refresh / duplicate hooks: `allow_multiple_hooks: false` is enforced by ActiveRecord uniqueness validation on `[:account_id, :app_id]`.
- Feature flag revocation: If `erp_integration` is revoked for an account with an existing hook, the hook remains safely stored in PostgreSQL, but frontend routes and settings cards become inaccessible until re-enabled.
- Special character preservation: API tokens with dashes, underscores, and dots are preserved during whitespace sanitization.

## Out of scope

- Outbound data sync from Chatwoot to ERP: Phase 01 is read-only foundation; outbound CRM writes are out of scope.
- Contact panel ERP data rendering: Displaying customer/financial data in conversation views is deferred to Phase 02 (Feature 075 / spec95).
- Additional ERP providers (e.g. Simples Dental): Pluggable framework supports future providers, but only Younus is implemented in this phase.
- Custom UI/scoped CSS styling: Tailwind utility classes and existing Design System components must be used exclusively per repo conventions.

## Verification commands

Copied verbatim from `.specify/memory/tdd-profile.md` at planning time:

### Ruby (RSpec)
- Single test: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file} -e "{name}"`
- Single file: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file}`
- Targeted suite: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/integrations/ custom/spec/services/erp/ custom/spec/models/custom/integrations/ spec/models/integrations/hook_spec.rb`
- Full suite: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec`
- RuboCop: `docker compose exec -T rails bundle exec rubocop`

### JavaScript/Vue (Vitest)
- Single test: `docker compose exec -T vite env TZ=UTC pnpm vitest run {file} -t "{name}"`
- Single file: `docker compose exec -T vite env TZ=UTC pnpm vitest run {file}`
- Full suite: `docker compose exec -T vite pnpm test`
- ESLint: `docker compose exec -T vite pnpm eslint`
- Manifest audit: `docker compose exec -T rails ruby bin/sync-custom-module-hooks --check && docker compose exec -T rails ruby bin/sync-custom-module-hooks --audit`
