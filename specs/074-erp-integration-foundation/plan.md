# Implementation Plan: ERP Integration Foundation & Younus Setup

**Branch**: `074-erp-integration-foundation` | **Date**: 2026-09-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/074-erp-integration-foundation/spec.md`

## Summary

This feature establishes the pluggable ERP integration foundation for Chatwoot and delivers the first concrete provider: Younus ERP. It introduces an account-level feature flag (`erp_integration`), a unified "ERP" card in Settings > Integrations, an ERP provider selection gallery (`/settings/integrations/erp`), and a dedicated Younus configuration flow using Chatwoot's standard FormKit schema. 

Key technical decisions:
1. Reuses the existing `Integrations::Hook` model (`app_id: 'younus'`, `settings` JSONB) with zero database migrations.
2. Implements all ERP domain logic under `custom/app/services/erp/` (`Erp::BaseAdapter`, `Erp::AdapterFactory`, `Erp::Younus::Adapter`, `Erp::Younus::Client`, `Erp::Errors`), fully decoupled from upstream OSS files.
3. Extends `Integrations::Hook` and `Integrations::App` via `prepend_mod_with` in `custom/app/models/custom/integrations/`.
4. Enforces synchronous connection validation during `ActiveRecord validate` on save (matching the OpenAI API key validation pattern) with a 5-second HTTP timeout via HTTParty.
5. Securely conceals credentials by masking the API Token with dots (`••••••••`) in serialized responses while preserving the Company ID in cleartext.
6. Registers all core wiring points in `bin/sync-custom-module-hooks` MANIFEST to maintain 0 audit gaps.

## Technical Context

**Language/Version**: Ruby 3.4+ (MRI) / Rails 7.1+, Vue 3.4+ (Composition API with `<script setup>`)

**Primary Dependencies**: 
- Backend: `HTTParty` (HTTP client), `JSONSchemer` (schema validation), `WebMock` (spec mocking).
- Frontend: `@formkit/vue` (dynamic form generation), `vue-router` (routing & guards), `vue-i18n` (localization), `pico-search` (integration search).

**Storage**: PostgreSQL (`integrations_hooks` table via ActiveRecord). No new database migrations or schema alterations.

**Testing**: 
- Backend: RSpec (`custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb`, `custom/spec/services/erp/`, `custom/spec/models/custom/integrations/`, `spec/models/integrations/hook_spec.rb`).
- Frontend: Vitest (`app/javascript/dashboard/routes/dashboard/settings/integrations/`).
**Target Platform**: Linux containers running rootless Podman / Docker Compose (`rails` container on :3000, `vite` on :3036, `postgres` on :5432, `redis` on :6379).

**Project Type**: Web application (Rails JSON API backend + Vue 3 SPA frontend).

**Performance Goals**: 
- Synchronous connection validation executes and returns in under 5 seconds (enforced via HTTP client timeout).
- Zero latency impact on main settings gallery or existing integration hook executions.

**Constraints**: 
- 5-second network timeout on remote calls to `https://wfh.ichatr.com.br/webhook/pessoas`.
- Immediate validation feedback: HTTP 401/403 maps to "Invalid credentials", HTTP 503 / timeout / network failures map to "Could not connect to ERP".
- Sensitive credential masking: API token returned as `••••••••` in API payloads and UI.
- Upstream compatibility: All changes outside `custom/` must have MANIFEST entries in `bin/sync-custom-module-hooks`.

**Scale/Scope**: 
- 1 new account feature flag (`erp_integration`).
- 1 new app catalog entry (`younus` with `category: erp`).
- 1 new provider gallery view (`Erp/Index.vue`).
- 5 new service classes (`custom/app/services/erp/`).
- 2 model extensions (`custom/app/models/custom/integrations/`).
- Synchronous bilingual localization (English and Brazilian Portuguese).

## Constitution Check

*GATE: Evaluated pre-Phase 0 research, re-evaluated post-Phase 1 design.*

| Principle | Status | Compliance Details |
|---|---|---|
| **I. Upstream Compatibility First (NON-NEGOTIABLE)** | **PASS** | Domain logic is 100% isolated under `custom/app/services/erp/`. Model extensions use `prepend_mod_with` under `custom/app/models/custom/integrations/`. No new database tables. All core file edits (routes, apps.yml, features.yml, manifest) are tracked in `bin/sync-custom-module-hooks`. |
| **II. Smallest Production-Ready Change** | **PASS** | Reuses `Integrations::Hook` instead of creating new tables. Reuses `NewHook.vue` FormKit rendering instead of bespoke form components. Scope is read-only v1; no speculative CRM write abstractions. |
| **III. Adhere to Established Conventions** | **PASS** | Adheres to RuboCop rules (150-char line length), ESLint, Tailwind utility classes only, Vue 3 Composition API with `<script setup>`, PascalCase components, and synchronous i18n (`en.json`, `pt_BR.json`, `en.yml`, `pt_BR.yml`). |
| **IV. Safe, Reversible Change Management** | **PASS** | Changes are additive, non-destructive, and can be disabled instantly at runtime via the `erp_integration` account feature flag without affecting existing integrations. |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | **PASS** | Verified that `Integrations::Hook` and `Integrations::App` are core OSS concepts with no conflicting enterprise overrides in `enterprise/`. Extension points respect `ChatwootApp.extensions`. |
| **VI. Test-Driven Development (NON-NEGOTIABLE)** | **PASS** | All behaviors have explicit test contracts and will be implemented test-first using RSpec and Vitest. Real entry points are covered by an RSpec request spec (`custom/spec/requests/api/v1/accounts/integrations/hooks_spec.rb` testing POST synchronous validation, 200/422 status codes, and credential masking) and Vitest router/component specs per Principle VI. |

*Verdict: GATES PASSED with 0 violations. No exemptions required.*

## Project Structure

### Documentation (this feature)

```text
specs/074-erp-integration-foundation/
├── plan.md              # This implementation plan
├── research.md          # Phase 0 technical decisions
├── data-model.md        # Phase 1 entity schema & relationships
├── quickstart.md        # Phase 1 validation & test execution guide
├── contracts/           # Phase 1 interface contracts
│   ├── apps-api.md
│   ├── hooks-api.md
│   └── younus-remote-api.md
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# Backend Core Configuration & Upstream Patches
config/
├── features.yml                                   # Registers erp_integration account feature flag
└── integration/
    └── apps.yml                                   # Registers younus integration with category: erp

app/
├── models/integrations/
│   ├── hook.rb                                    # Adds Integrations::Hook.prepend_mod_with
│   └── app.rb                                     # Adds Integrations::App.prepend_mod_with
└── views/api/v1/models/
    └── _hook.json.jbuilder                        # Uses masked_settings to conceal token

# Fork-Isolated Domain Services & Model Overlays (Principle I)
custom/
├── app/
│   ├── models/custom/integrations/
│   │   ├── hook.rb                                # Custom::Integrations::Hook (validation & masking)
│   │   └── app.rb                                 # Custom::Integrations::App (feature flag gating)
│   └── services/erp/
│       ├── base_adapter.rb                        # Erp::BaseAdapter (abstract contract)
│       ├── adapter_factory.rb                     # Erp::AdapterFactory (provider resolver)
│       ├── errors.rb                              # Erp::AuthenticationError, Erp::ApiError
│       └── younus/
│           ├── adapter.rb                         # Erp::Younus::Adapter
│           └── client.rb                          # Erp::Younus::Client (HTTParty)
└── spec/
    ├── requests/api/v1/accounts/integrations/
    │   └── hooks_spec.rb                          # RSpec request spec for POST hooks (200, 422, token masking)
    ├── models/custom/integrations/
    │   ├── app_spec.rb                            # RSpec coverage for app feature gating
    │   └── hook_spec.rb                           # RSpec coverage for hook validation & masking
    └── services/erp/
        ├── base_adapter_spec.rb                   # RSpec coverage for abstract base contract
        ├── adapter_factory_spec.rb                # RSpec coverage for provider resolution
        └── younus/
            ├── client_spec.rb                     # RSpec coverage for WebMock HTTP client tests
            └── adapter_spec.rb                    # RSpec coverage for adapter contract tests
# Frontend Application (Vue 3 / Vite)
app/javascript/dashboard/
├── featureFlags.js                                # Adds FEATURE_FLAGS.ERP_INTEGRATION
├── routes/dashboard/settings/integrations/
│   ├── integrations.routes.js                     # Registers /settings/integrations/erp route
│   ├── Index.vue                                  # Groups category: erp into unified ERP card
│   ├── SingleIntegrationHooks.vue                 # Displays cleartext Company ID & masked token
│   └── Erp/
│       └── Index.vue                              # ERP provider gallery (lists Younus)
└── i18n/locale/
    ├── en/
    │   ├── integrations.json                      # English UI strings (INTEGRATION_SETTINGS.ERP)
    │   └── integrationApps.json                   # English app metadata (INTEGRATION_APPS.ERP)
    └── pt_BR/
        ├── integrations.json                      # Portuguese UI strings (INTEGRATION_SETTINGS.ERP)
        └── integrationApps.json                   # Portuguese app metadata (INTEGRATION_APPS.ERP)

# Localization (Backend)
config/locales/
├── en.yml                                         # English backend validation messages
└── pt_BR.yml                                      # Portuguese backend validation messages

# Static Assets
public/dashboard/images/integrations/
├── erp.png                                        # ERP gallery light icon
├── erp-dark.png                                   # ERP gallery dark icon
├── younus.png                                     # Younus integration light icon
└── younus-dark.png                                # Younus integration dark icon

# Synchronization & Upstream Gap Prevention
bin/
└── sync-custom-module-hooks                       # MANIFEST entries for modified upstream files (features.yml, apps.yml, hook.rb, app.rb, _hook.json.jbuilder, featureFlags.js, integrations.routes.js, Index.vue, SingleIntegrationHooks.vue, and locale JSON files/exclusions)

**Structure Decision**: 
A decoupled web application architecture was selected. All fork-specific ERP business logic lives strictly under `custom/` following the existing `enterprise/` overlay convention. Core upstream files are touched only at minimal extension points (`prepend_mod_with`, configuration declarations, and route tables), all of which are tracked in `bin/sync-custom-module-hooks` MANIFEST to guarantee 0 upstream sync gaps.

## Complexity Tracking

> No constitution violations. Table is empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *None* | N/A | N/A |
