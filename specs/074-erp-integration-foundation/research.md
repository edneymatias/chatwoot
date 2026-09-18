# Research & Technical Decisions: ERP Integration Foundation & Younus Setup

**Feature**: 074-erp-integration-foundation
**Date**: 2026-09-17
**Status**: Completed

## 1. Storage & Persistence Mechanism

### Decision
Reuse the existing `Integrations::Hook` model (`integrations_hooks` table) with `app_id: 'younus'`, `hook_type: :account`, and `allow_multiple_hooks: false`. No new database tables or schema migrations will be created.

### Rationale
- Chatwoot's existing integration ecosystem (Slack, Notion, Shopify, Dyte, LeadSquared CRM) utilizes `Integrations::Hook` to persist per-account integration settings, status (`enabled` vs `disabled`), and credentials inside the `settings` JSONB column.
- `Integrations::Hook` already supports account-level uniqueness scopes, lifecycle callbacks, authorization checks, and feature-flag gating (`ensure_feature_enabled`).
- Zero database migrations minimizes risk, prevents table name collisions with future upstream Chatwoot updates, and ensures 100% upstream compatibility.

### Alternatives Considered
- **Dedicated `erp_integrations` table**: Rejected because it introduces schema overhead, requires redundant CRUD controllers, policies, and serializers, and diverges from Chatwoot's unified integration hooks paradigm without providing tangible benefits.
- **Storing credentials in `Account#custom_attributes`**: Rejected because custom attributes are intended for contact/conversation metadata, lack encryption support, and cannot be managed via Chatwoot's standard integration settings UI.

---

## 2. Decoupled Code Architecture & Module Isolation

### Decision
Place all new ERP business logic under `custom/` following the repository's established overlay architecture:
- Core ERP services under `custom/app/services/erp/`:
  - `Erp::BaseAdapter` (`custom/app/services/erp/base_adapter.rb`): Abstract provider contract.
  - `Erp::AdapterFactory` (`custom/app/services/erp/adapter_factory.rb`): Factory resolving provider identifiers to adapters.
  - `Erp::Error`, `Erp::AuthenticationError`, `Erp::ApiError` (`custom/app/services/erp/errors.rb`): Unified exception hierarchy.
  - `Erp::Younus::Adapter` (`custom/app/services/erp/younus/adapter.rb`): Concrete Younus adapter.
  - `Erp::Younus::Client` (`custom/app/services/erp/younus/client.rb`): HTTParty API client.
- Extensions to existing models via `prepend_mod_with`:
  - `Custom::Integrations::Hook` (`custom/app/models/custom/integrations/hook.rb`): Adds `erp_integration?`, `sanitize_erp_settings`, `validate_erp_credentials`, and `masked_settings`.
  - `Custom::Integrations::App` (`custom/app/models/custom/integrations/app.rb`): Enforces `erp_integration` feature flag gating when `category == 'erp'`.

### Rationale
- Complies strictly with Constitution Principle I (Upstream Compatibility First) and AGENTS.md guidelines.
- Eager load paths in `config/application.rb` already include `custom/app/**` and `custom/lib`.
- Keeps fork-specific business logic completely decoupled from upstream files, preventing merge conflicts during future upstream syncs.

### Alternatives Considered
- **Interleaving ERP classes directly in `app/services/erp/` and `app/models/integrations/hook.rb`**: Rejected because editing core OSS files directly increases merge conflict surface on upstream releases.

---

## 3. Credential Validation Pattern (Synchronous on Save)

### Decision
Validate credentials synchronously during the ActiveRecord validation lifecycle (`validate :validate_erp_credentials, if: :validate_erp_credentials?`) inside `Custom::Integrations::Hook`.
If validation fails:
- HTTP 401/403: Add `errors.add(:base, I18n.t('errors.erp.invalid_credentials'))` ("Invalid credentials" / "Credenciais inválidas").
- HTTP 503 / Network Error / Timeout: Add `errors.add(:base, I18n.t('errors.erp.connection_error'))` ("Could not connect to ERP" / "Não foi possível conectar ao ERP").

When an error is added, ActiveRecord halts the save, returns HTTP 422 Unprocessable Entity, and Chatwoot's `RequestExceptionHandler#render_record_invalid` surfaces `{ message: "..." }`, which `NewHook.vue` displays directly via `useAlert`.

### Rationale
- Direct precedent exists in `Integrations::Hook#validate_openai_api_key` using `Integrations::Openai::KeyValidator.valid?`.
- Avoids creating ad hoc "test connection" endpoints or background jobs.
- Immediate feedback ensures that broken or invalid configurations cannot be saved in an `enabled` state.

### Alternatives Considered
- **Asynchronous validation via Sidekiq job**: Rejected because administrators need synchronous confirmation before the modal closes. An async job could lead to race conditions where the UI shows the integration as connected before validation fails.
- **Separate "Test Connection" button**: Rejected because Chatwoot's standard `NewHook.vue` FormKit component does not provide a pre-save test button. Validating on save matches the platform-wide pattern (e.g., OpenAI, Cloudflare).

---

## 4. Younus API Client Specification

### Decision
Implement `Erp::Younus::Client` using `HTTParty` with:
- `base_uri 'https://wfh.ichatr.com.br'`
- Default network timeout of 5 seconds (`default_timeout 5`)
- Endpoint: `GET /webhook/pessoas?idEmpresa=<id_empresa>&nrTelcelpessoa=<phone>`
- Headers: `{ 'token' => @token, 'Content-Type' => 'application/json' }`
- Response mappings:
  - `401`, `403` → Raise `Erp::AuthenticationError`
  - `503`, `5xx`, or timeout (`Net::OpenTimeout`, `Net::ReadTimeout`, `Timeout::Error`) → Raise `Erp::ApiError`
  - `200` with JSON body:
    - If `sucesso: true` → Returns array/record from `dados`
    - If `sucesso: false` → Returns `nil` (person not found, but authentication succeeded)
    - If non-JSON or invalid schema → Raise `Erp::ApiError`

### Rationale
- Accurately models Younus API behavior as specified in `spec94.md` and clarified in the feature spec.
- The 5-second timeout complies with FR-010 and the clarification session.
- Pre-sanitizing credentials (`strip` on `token` and `id_empresa`) prevents trailing/leading whitespace errors.
- `Erp::Younus::Adapter#test_connection` calls `client.search_by_phone('0')`. Since `"0"` is an invalid phone number, the Younus API returns HTTP 200 with `sucesso: false` if authenticated, confirming connectivity without querying real patient/person data.

### Alternatives Considered
- **Using Faraday or Typhoeus**: Rejected because `HTTParty` is already the standard client across Chatwoot (`Crm::Leadsquared::Api::BaseClient`, WhatsApp, Freshdesk, Instagram).

---

## 5. Frontend Navigation, Grouping, and Provider Selection

### Decision
1. **Metadata**: Add `category: 'erp'` to ERP apps in `config/integration/apps.yml`.
2. **Gallery Grouping**: In `Integrations/Index.vue`, filter out individual apps with `category === 'erp'`. When the `erp_integration` feature flag is enabled for the account, render a single synthesized "ERP" card (`id: 'erp'`).
3. **Dedicated Provider Selection View**: Route `/settings/integrations/erp` to `app/javascript/dashboard/routes/dashboard/settings/integrations/Erp/Index.vue`:
   - Lists all apps with `category === 'erp'` (currently Younus).
   - Shows current status (Connected / Not Configured).
   - Clicking "Configure" routes to `accounts/:accountId/settings/integrations/younus` (`IntegrationHooks.vue`).
4. **Configuration Modal**: Clicking "Connect" on `SingleIntegrationHooks.vue` opens `NewHook.vue`, which dynamically renders the FormKit fields (`API Token` and `Company ID`) from `apps.yml`.
5. **Route Guard**: Add a `beforeEnter` navigation guard to `/settings/integrations/erp` in `integrations.routes.js` that checks `store.getters['accounts/isFeatureEnabledonAccount'](accountId, FEATURE_FLAGS.ERP_INTEGRATION)` and redirects to the account dashboard if disabled.

### Rationale
- Satisfies FR-001 through FR-006 and all US1/US2 acceptance scenarios.
- Adding future ERP providers requires only a new entry in `apps.yml` with `category: erp` and an adapter; no changes to `Erp/Index.vue` or routing will be needed.
- Reuses existing FormKit rendering in `NewHook.vue` and lifecycle in `IntegrationHooks.vue`.

### Alternatives Considered
- **Listing Younus directly on the main Integrations gallery**: Rejected because the business requirement explicitly mandates a unified "ERP" card leading to a provider selection screen to support multiple ERP providers (e.g. Simples Dental) in future iterations.

---

## 6. Credential Concealment & Masking

### Decision
1. In `_hook.json.jbuilder`, replace sensitive keys (specifically `token`) with `'••••••••'` when serializing hook settings:
   ```ruby
   hook_settings = resource.respond_to?(:masked_settings) ? resource.masked_settings : resource.settings
   settings = (hook_settings || {}).select { |key, _| visible_properties.include?(key.to_s) }
   ```
2. In `Custom::Integrations::Hook#masked_settings`:
   Return a copy of `settings` where `'token'` is masked with `'••••••••'`.
3. In `SingleIntegrationHooks.vue` and `Erp/Index.vue`:
   When a hook is connected (`hasConnectedHooks` is true), render the configured properties:
   - Company ID (`id_empresa`): displayed in cleartext.
   - API Token (`token`): displayed as `'••••••••'`.

### Rationale
- Satisfies FR-011 and US2 Acceptance Scenario 6.
- Prevents cleartext credentials from leaking across the network on GET requests.
- Matches Chatwoot's credential masking conventions across the application (e.g., ScoutToolModal, WebhookForm).

### Alternatives Considered
- **Frontend-only masking**: Rejected because returning the cleartext token over HTTP GET exposes secret keys to the browser network tab unnecessarily.
- **Never showing the token at all**: Rejected because the user clarification explicitly requires displaying the token masked with dots alongside the cleartext Company ID.

---

## 7. Upstream Sync Safety & Manifest Registration

### Decision
All core file modifications will be registered in `bin/sync-custom-module-hooks` MANIFEST:
- `config/features.yml`: Add `erp_integration` entry.
- `config/integration/apps.yml`: Add `younus` app entry with `category: erp`.
- `app/models/integrations/hook.rb`: Add `Integrations::Hook.prepend_mod_with('Integrations::Hook')`.
- `app/models/integrations/app.rb`: Add `Integrations::App.prepend_mod_with('Integrations::App')`.
- `app/views/api/v1/models/_hook.json.jbuilder`: Add `masked_settings` support.
- `app/javascript/dashboard/featureFlags.js`: Add `ERP_INTEGRATION: 'erp_integration'`.
- `app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js`: Add `erp` route.
- `app/javascript/dashboard/routes/dashboard/settings/integrations/Index.vue`: Add ERP grouping logic.
- `app/javascript/dashboard/routes/dashboard/settings/integrations/SingleIntegrationHooks.vue`: Add connected settings display.
- Locale files (`en/settings.json`, `pt_BR/settings.json`, `en.yml`, `pt_BR.yml`).

### Rationale
- Strict requirement in AGENTS.md ("Every accepted direct-upstream edit MUST get a MANIFEST entry in `bin/sync-custom-module-hooks`").
- Allows `bin/sync-custom-module-hooks --check` and `--audit` to pass with 0 gaps.
