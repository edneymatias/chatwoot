# Implementation Plan: Account-Level LLM Configuration

**Branch**: `047-account-llm-config` | **Date**: 2026-08-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/047-account-llm-config/spec.md`

## Summary

Consolidate per-Scout LLM provider settings (provider, model, API key) into a single, shared, account-level configuration model `ScoutAccountConfig` (table `ichatr_scout_account_configs`). Administrators manage this configuration from a dedicated settings page in the Scout workspace (`dashboard/scout/pages/ScoutSettings.vue`), reachable via an expandable sidebar submenu (**Agentes**, **Configurações**, **Ferramentas**). All Scouts in the account automatically inherit these credentials for LLM interactions via `Scout#llm_chat`, and Scout creation/tool management is gated until valid credentials are saved and verified.

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.1), JavaScript / Vue 3 (Vite, Pinia/Vuex, Tailwind CSS)

**Primary Dependencies**: RubyLLM, ActiveSupport::EncryptedAttribute (`encrypts`), ActiveRecord

**Storage**: PostgreSQL (`ichatr_scout_account_configs` table with unique index on `account_id`)

**Testing**: RSpec (`rspec custom/spec/...`), Vitest (`pnpm test`), RuboCop, ESLint

**Target Platform**: Web application (Chatwoot fork running in rootless Podman containers)

**Project Type**: Web service (Rails backend + Vue 3 SPA frontend)

**Performance Goals**: Sub-50ms lookup overhead for account configuration caching/retrieval; credential verification on save completing within standard HTTP request timeout.

**Constraints**:
- Zero edits to core `app/models/account.rb` (queries go through `ScoutAccountConfig.find_by(account_id:)`).
- All custom tables prefixed with `ichatr_`.
- Encrypted storage for API keys at rest.
- Synchronous `en.json` and `pt_BR.json` frontend translation updates.
- Tailwind CSS utility classes only (no custom/scoped CSS).

**Scale/Scope**: 1 configuration record per account; supports all Scouts within the tenant.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Principle I: Upstream Compatibility First**: Custom code isolated under `custom/`, tables prefixed with `ichatr_`, no edits to `app/models/account.rb`.
- [x] **Principle II: Smallest Production-Ready Change**: Minimal necessary data model, no speculative provider mixing, drops obsolete columns cleanly.
- [x] **Principle III: Adhere to Established Conventions**: Follows RuboCop line length, Tailwind CSS rules, Composition API with `<script setup>`, synchronous `pt_BR` and `en` i18n.
- [x] **Principle IV: Safe, Reversible Change Management**: Non-destructive migration for existing tables (pre-launch Scout data), standard Rails migration rollbacks.
- [x] **Principle V: Dual-Tree Awareness (OSS + Enterprise)**: Scout is a custom overlay module; contracts and routes checked for consistency.

## Project Structure

### Documentation (this feature)

```text
specs/047-account-llm-config/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── scout-account-config-api.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── controllers/api/v1/accounts/
│   │   ├── scout_account_configs_controller.rb  # [NEW] Singular resource controller
│   │   ├── scouts_controller.rb                 # [MODIFIED] Drop per-scout LLM params & add gating
│   │   └── scouts/
│   │       └── provider_settings_controller.rb  # [REMOVED] Superseded by scout_account_configs_controller
│   ├── models/
│   │   ├── scout_account_config.rb              # [NEW] Encrypted account LLM config model
│   │   └── scout.rb                             # [MODIFIED] Uses ScoutAccountConfig in llm_chat
│   ├── policies/
│   │   ├── scout_account_config_policy.rb       # [NEW] Admin-only authorization
│   │   └── scout_policy.rb                      # [MODIFIED] Remove obsolete provider settings actions
│   └── services/custom/scout/
│       └── agent_runner.rb                      # [MODIFIED] Checks account config presence
db/migrate/
└── 21260821000001_create_ichatr_scout_account_configs.rb # [NEW] Migration for config table & drops scout columns

app/javascript/dashboard/
├── api/scout.js                                 # [MODIFIED] Account config API endpoints
├── components-next/sidebar/Sidebar.vue          # [MODIFIED] Submenu for Scout (Agentes, Configurações, Ferramentas)
├── routes/dashboard/scout/
│   ├── scout.routes.js                          # [MODIFIED] Adds scout_settings route
│   └── pages/
│       ├── ScoutSettings.vue                    # [NEW] Account LLM settings form page
│       └── ScoutList.vue                        # [MODIFIED] Removes LLM inputs & adds gating
├── routes/dashboard/settings/scout/             # [REMOVED] Obsolete settings route directory
└── i18n/locale/
    ├── en/scout.json                            # [MODIFIED] Submenu & settings strings
    └── pt_BR/scout.json                         # [MODIFIED] Submenu & settings strings
```

**Structure Decision**: Web application layout integrating custom backend domain models under `custom/app/` with dashboard frontend Vue components under `app/javascript/dashboard/`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*(No constitution violations. All changes comply 100% with isolation and architectural standards).*
