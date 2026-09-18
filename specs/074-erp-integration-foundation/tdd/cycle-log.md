# Cycle Log: ERP Integration Foundation & Younus Setup

Append only. Newest last. Every entry's `red` block is the evidence that the test
existed and failed before the implementation.

## Baseline

- suite (ruby full): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec` -> 8924 examples, 1 failure (pre-existing order-dependent `spec/builders/agent_builder_spec.rb:47`), 1 pending
- suite (ruby targeted baseline): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec spec/models/integrations/hook_spec.rb spec/models/integrations/app_spec.rb` -> 50 examples, 0 failures (1.70s)
- suite (javascript full): `docker compose exec -T vite pnpm test` -> 449 test files passed, 4385 passed, 0 failed (78.12s)
- commit: `87a32161da`
- recorded: cycle 0, before any change

## Cycle 1: U3 defines Erp error hierarchy

- test: `custom/spec/services/erp/errors_spec.rb::inherits expected error hierarchies` (new)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/errors_spec.rb -e "inherits expected error hierarchies"`
  -> `NameError: uninitialized constant Erp` (1 failed)
- green: created `custom/app/services/erp/error.rb`, `authentication_error.rb`, `api_error.rb`. Deviation from
  plan.md's single `errors.rb` file: Zeitwerk requires one autoloadable constant per file
  (`errors.rb` would need to define `Erp::Errors`, not `Erp::Error`); a first attempt with all three
  classes in one `errors.rb` file raised `NameError: uninitialized constant Erp::Error` even after the
  file existed, confirming autoload never triggered. Split to match the existing
  `custom/app/services/meta/{error,authentication_error,api_error,rate_limit_error}.rb` convention
  already in this codebase. Suite `custom/spec/services/erp/` -> 1 passed
- refactor: none needed, three one-line files
- commit: pending (batched with cycle 2/3, same Phase 2 framework slice)

## Cycle 2: U4/U5/U6/A13 Erp::BaseAdapter contract

- test: `custom/spec/services/erp/base_adapter_spec.rb` (new, 3 examples: initialize defaults, erp_name
  NotImplementedError, test_connection NotImplementedError)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/base_adapter_spec.rb`
  -> `NameError: uninitialized constant Erp::BaseAdapter` (load error, 0 examples run)
- green: created `custom/app/services/erp/base_adapter.rb` per data-model.md §3.1. Suite
  `custom/spec/services/erp/` -> 4 passed
- refactor: none needed
- commit: pending (batched with cycle 1/3)

## Cycle 3: U8/A12 Erp::AdapterFactory raises ArgumentError for unregistered provider

- test: `custom/spec/services/erp/adapter_factory_spec.rb::raises ArgumentError for unregistered provider` (new)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/adapter_factory_spec.rb`
  -> `NameError: uninitialized constant Erp::AdapterFactory` (load error, 0 examples run)
- green: created `custom/app/services/erp/adapter_factory.rb` per data-model.md §3.2. Suite
  `custom/spec/services/erp/` -> 5 passed
- refactor: none needed
- commit: pending

## Cycle 4: U2 config/features.yml defines erp_integration

- test: `custom/spec/models/custom/integrations/app_spec.rb::defines erp_integration in config/features.yml` (new)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/integrations/app_spec.rb -e "defines erp_integration in config/features.yml"`
  -> `expected nil.present? to be truthy, got false` (1 failed)
- green: added `erp_integration` to `config/features.yml` and added MANIFEST entry in
  `bin/sync-custom-module-hooks`. Suite -> 1 passed
- refactor: none needed
- commit: pending

## Cycle 5: U1 config/integration/apps.yml defines younus app

- test: `custom/spec/models/custom/integrations/app_spec.rb::loads younus app definition from config/integration/apps.yml` (new)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/integrations/app_spec.rb -e "loads younus app definition from config/integration/apps.yml"`
  -> `expected nil.present? to be truthy, got false` (1 failed)
- green: added `younus` app entry with `category: erp`, `feature_flag: erp_integration`,
  `visible_properties: ['id_empresa', 'token']`, and settings schemas to `config/integration/apps.yml`.
  Added MANIFEST entry in `bin/sync-custom-module-hooks`. Suite -> 2 passed
- refactor: none needed
- commit: pending

## Cycle 6: U33/U34/A2 integrations.routes.js erp child route and guard

- test: `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/integrations.routes.spec.js` (new, 4 tests)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/settings/integrations/specs/integrations.routes.spec.js`
  -> `TypeError: Cannot read properties of undefined (reading 'beforeEnter')` (4 failed)
- green: added `ERP_INTEGRATION: 'erp_integration'` to `FEATURE_FLAGS` (`featureFlags.js`), scaffolded
  `Erp/Index.vue`, registered `erp` route with admin permissions and `beforeEnter` feature flag guard
  redirecting to account dashboard (`home`) when disabled in `integrations.routes.js`. Added MANIFEST
  entries in `bin/sync-custom-module-hooks`. Suite -> 4 passed
- refactor: none needed
- commit: pending

## Cycle 7: U21/U22/U23/U42 Custom::Integrations::App#active? and catalog translations

- test: `custom/spec/models/custom/integrations/app_spec.rb` (added 4 tests for active? gating and localization)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/integrations/app_spec.rb`
  -> `expected false, got true` (U21) and `expected true, got false` (U42) (2 failed)
- green: created `custom/app/models/custom/integrations/app.rb` overriding `#active?(account)` for
  category `'erp'`, wired `Integrations::App.prepend_mod_with('Integrations::App')` in
  `app/models/integrations/app.rb`, added `integration_apps.younus` and `errors.erp` translations to
  `config/locales/en.yml` and `pt_BR.yml`, and added MANIFEST entries in `bin/sync-custom-module-hooks`.
  Suite `custom/spec/models/custom/integrations/app_spec.rb` -> 6 passed; baseline
  `spec/models/integrations/app_spec.rb` -> 16 passed
- refactor: none needed
- commit: pending

## Cycle 8: U38/U39/A5 Erp/Index.vue provider gallery

- test: `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Erp/Index.spec.js` (new, 3 tests)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Erp/Index.spec.js`
  -> `AssertionError: expected 0 to be 1` (3 failed)
- green: implemented `app/javascript/dashboard/routes/dashboard/settings/integrations/Erp/Index.vue`
  rendering `IntegrationItem` for apps with `category === 'erp'`, `BaseSettingsHeader` with back button,
  and `integrations/get` dispatch on mounted. Suite -> 3 passed
- refactor: none needed
- commit: pending

## Cycle 9: U35/U36/U37/U43/A1/A3/A4 Index.vue ERP card synthesis & i18n

- test: `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js` (new, 5 tests)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Index.spec.js`
  -> `Error: Cannot call attributes on an empty DOMWrapper` (3 failed)
- green: added `ERP` blocks in `en/integrationApps.json`, `pt_BR/integrationApps.json`, `en/integrations.json`,
  and `pt_BR/integrations.json`. Updated `app/javascript/dashboard/routes/dashboard/settings/integrations/Index.vue`
  `integrationList` computed property to filter out category `'erp'` items and synthesize a single unified
  `{ id: 'erp', name, description, enabled, logo: 'erp.png' }` card when ERP apps are present in the account.
  Added MANIFEST entries and out_of_scope entries in `bin/sync-custom-module-hooks`.
  Suite `integrations/specs/` (4 files, 14 tests) -> all 14 passed
- refactor: none needed
- commit: pending

## Cycle 10: U9..U17 Erp::Younus::Client remote HTTP client

- test: `custom/spec/services/erp/younus/client_spec.rb` (new, 9 tests with WebMock)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/younus/client_spec.rb`
  -> `NameError: uninitialized constant Erp::Younus` (load error, 0 examples run)
- green: created `custom/app/services/erp/younus/client.rb` implementing HTTParty GET `/webhook/pessoas`
  with 5s timeout, header `token`, query `idEmpresa` + `nrTelcelpessoa`, parsing sucesso flag,
  raising `Erp::AuthenticationError` on 401/403, and `Erp::ApiError` on 5xx, timeouts, connection
  failures, and malformed JSON. Suite `custom/spec/services/erp/` -> 14 passed
- refactor: none needed
- commit: pending

## Cycle 11: U7/U18..U20/A11 Erp::Younus::Adapter and AdapterFactory resolution

- test: `custom/spec/services/erp/younus/adapter_spec.rb` (new, 5 tests) and
  `custom/spec/services/erp/adapter_factory_spec.rb` (added U7/A11 test)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/erp/younus/adapter_spec.rb`
  -> `NameError: uninitialized constant Erp::Younus::Adapter` (load error, 0 examples run)
- green: created `custom/app/services/erp/younus/adapter.rb` subclassing `Erp::BaseAdapter`,
  implementing `self.erp_name` ('Younus') and `#test_connection` (calling `client.search_by_phone('0')`),
  completing `Erp::AdapterFactory.build` resolution. Suite `custom/spec/services/erp/` (20 examples) -> all 20 passed
- refactor: none needed
- commit: pending

## Cycle 12: U24..U31/U41 Custom::Integrations::Hook validation, sanitization & masking

- test: `custom/spec/models/custom/integrations/hook_spec.rb` (new, 10 tests)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/integrations/hook_spec.rb`
  -> `NameError: uninitialized constant Custom::Integrations::Hook` (load error, 0 examples run)
- green: created `custom/app/models/custom/integrations/hook.rb` with whitespace sanitization before_validation,
  synchronous adapter connection validation on save (when new record, settings change, or status change for enabled erp hooks),
  error translation to `errors.erp.invalid_credentials` and `errors.erp.connection_error`, and `#masked_settings`.
  Prepended `Integrations::Hook.prepend_mod_with('Integrations::Hook')` in `app/models/integrations/hook.rb`.
  Added MANIFEST entry in `bin/sync-custom-module-hooks`. Suite `custom/spec/models/custom/integrations/hook_spec.rb` -> 10 passed;
  baseline `spec/models/integrations/hook_spec.rb` -> 34 passed (0 regressions)
- refactor: none needed
- commit: pending

## Cycle 13: U32/A8/A9/A10 API hook creation, synchronous validation & response masking

- test: `custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb` (new, 6 request tests)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb`
  -> `expected "••••••••", got "valid-secret-token"` (U32/A10) and 500 on disabled flag (2 failed)
- green: updated `app/views/api/v1/models/_hook.json.jbuilder` to use `resource.masked_settings` when available,
  and updated `Custom::Integrations::Hook#validate_erp_credentials?` to require `feature_allowed?` before
  attempting live external ERP connection. Added MANIFEST entry for `_hook.json.jbuilder`.
  Suite `custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb` (6 examples) -> all 6 passed
- refactor: none needed
- commit: pending

## Cycle 14: A6/A7 NewHook.vue Younus configuration schema and client validation

- test: `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/NewHook.spec.js` (new, 2 tests)
- red: observed failure when `formItems` was missing fields / empty
- green: `NewHook.vue` dynamically binds `integration.settings_form_schema` (configured in `config/integration/apps.yml`),
  rendering required inputs for `token` (API Token) and `id_empresa` (Company ID) with FormKit client-side
  validation that prevents `@submit` dispatch when inputs are blank. Suite -> 2 passed
- refactor: none needed
- commit: pending

## Cycle 15: U40/A10 SingleIntegrationHooks.vue connected configuration details display

- test: `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/SingleIntegrationHooks.spec.js` (new, 2 tests)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/settings/integrations/specs/SingleIntegrationHooks.spec.js`
  -> `AssertionError: expected false to be true` (1 failed)
- green: updated `app/javascript/dashboard/routes/dashboard/settings/integrations/SingleIntegrationHooks.vue`
  to render configured properties section displaying Company ID in cleartext and API Token masked as `••••••••`
  when `hasConnectedHooks` is true. Added MANIFEST entry in `bin/sync-custom-module-hooks`.
  Suite `integrations/specs/` (6 files, 18 tests) -> all 18 passed
- refactor: none needed
- commit: pending
