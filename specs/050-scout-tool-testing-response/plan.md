# Implementation Plan: Scout External Tool Testing & Response Shaping

**Branch**: `050-scout-tool-testing-response` | **Date**: 2026-08-21 | **Spec**: [/specs/050-scout-tool-testing-response/spec.md](file:///home/matias/dev/chatwoot/specs/050-scout-tool-testing-response/spec.md)

**Input**: Feature specification from `/specs/050-scout-tool-testing-response/spec.md`

## Summary

Enable draft testing of external REST/webhook tools directly from the management modal with sample payloads, dynamic URL path parameters with strict Liquid template validation, automatic query parameter handling for `GET` requests (including JSON stringification of array/object values), and configurable Liquid response templates to shape and filter external tool outputs before returning them to AI agents.

The solution introduces a shared `Custom::Scout::Tools::HttpRequestExecutor` service, adds a `response_template` column to `ichatr_scout_tools`, implements a non-persisting `POST /api/v1/accounts/:account_id/scout_tools/test` endpoint, and enriches `ScoutToolModal.vue` with correct attribute bindings (`endpoint_url`, `auth_headers`), a response template editor, and an interactive test playground.

---

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.1.x) / JavaScript (Vue 3, Vite, Tailwind CSS)

**Primary Dependencies**: Liquid (template parsing with `error_mode: :strict`), SafeFetch (`lib/safe_fetch.rb` for SSRF-protected HTTP requests), JSONSchemer (payload schema validation for live agent tool executions), Axios (frontend API client)

**Storage**: PostgreSQL (`ichatr_scout_tools` table with new `response_template` text column)

**Testing**: RSpec (`custom/spec/services/custom/scout/tools/`, `custom/spec/models/scout_tool_spec.rb`, `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`), Vitest (`pnpm test`)

**Target Platform**: Linux container (Docker Compose with rootless Podman) / Modern Web Browsers

**Project Type**: Full-stack web service & SPA extension (Chatwoot fork customization under `custom/` and `app/javascript/`)

**Performance Goals**: Test request preview truncation capped at 500 characters; sub-second URL path resolution and Liquid template rendering overhead (<5ms); standard SafeFetch network timeouts (2s open, 20s read)

**Constraints**: Strict variable evaluation (no silent failures for undefined template variables); zero host toolchain dependency; full RuboCop (150-char) and ESLint compliance; synchronous `en`/`pt_BR` translations

**Scale/Scope**: Account-scoped tools used across multi-agent conversations; ad-hoc testing playground for operators

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

- [x] **I. Upstream Compatibility First**: All backend logic resides exclusively in the isolated `custom/` tree (`custom/app/services/custom/scout/tools/http_request_executor.rb`, `custom/app/models/scout_tool.rb`, `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb`). The database table `ichatr_scout_tools` uses the fork prefix. The route addition is isolated to `resources :scout_tools`. No core upstream files or tables are altered.
- [x] **II. Smallest Production-Ready Change**: Reuses existing `SafeFetch` and standard `Liquid::Template` without bespoke networking abstractions or speculative features. Reuses `ScoutToolModal.vue` for the testing interface.
- [x] **III. Adhere to Established Conventions**: Follows RuboCop rules (150-char max line length, compact class definitions), Vue 3 `<script setup>` Composition API, Tailwind utility classes only, and synchronous `en.json`/`pt_BR.json` translations.
- [x] **IV. Safe, Reversible Change Management**: Migration adds a nullable `response_template` text column to `ichatr_scout_tools` (additive and reversible).
- [x] **V. Dual-Tree Awareness**: Scout tools are fork-specific and decoupled from the enterprise Captain module. Checked and confirmed no naming or routing collision with `enterprise/`.

---

## Project Structure

### Documentation (this feature)

```text
specs/050-scout-tool-testing-response/
├── plan.md              # Implementation plan
├── research.md          # Phase 0 research and architectural decisions
├── data-model.md        # Phase 1 data models and sequence diagrams
├── quickstart.md        # Phase 1 verification and quickstart guide
└── contracts/           # Phase 1 API specifications
    ├── scout-tools-test-api.md
    └── scout-tools-crud-api.md
```

### Source Code Layout

```text
custom/
├── app/
│   ├── controllers/
│   │   └── api/
│   │       └── v1/
│   │           └── accounts/
│   │               └── scout_tools_controller.rb   # Add test action, permit response_template
│   ├── models/
│   │   └── scout_tool.rb                           # Add response_template attribute & helpers
│   ├── policies/
│   │   └── scout_tool_policy.rb                    # Add test? action policy
│   └── services/
│       └── custom/
│           └── scout/
│               └── tools/
│                   ├── http_request_executor.rb     # NEW: Shared executor for Liquid, query params, SafeFetch
│                   └── call_custom_api.rb          # Delegate execution to HttpRequestExecutor
└── spec/
    ├── controllers/
    │   └── api/
    │       └── v1/
    │           └── accounts/
    │               └── scout_tools_controller_spec.rb # Test action specs
    ├── models/
    │   └── scout_tool_spec.rb                      # Model specs including response_template
    └── services/
        └── custom/
            └── scout/
                └── tools/
                    ├── http_request_executor_spec.rb # NEW: Unit specs for executor
                    └── call_custom_api_spec.rb      # Updated tool specs

db/migrate/
└── 21260821120000_add_response_template_to_ichatr_scout_tools.rb # Add response_template column

config/
└── routes.rb                                        # Add post :test to resources :scout_tools

app/javascript/
├── dashboard/
│   ├── api/
│   │   └── scout.js                                 # Add testTool method
│   ├── components-next/
│   │   └── Scout/
│   │       └── pageComponents/
│   │           └── ScoutToolModal.vue               # Fix field mapping, add response template & test playground
│   └── i18n/
│       └── locale/
│           ├── en/
│           │   └── scout.json                       # English localization keys
│           └── pt_BR/
│               └── scout.json                       # Portuguese localization keys
```

**Structure Decision**: Selected standard isolated fork structure under `custom/` for backend logic, additive migration under `db/migrate/`, route declaration under `config/routes.rb`, and frontend updates under `app/javascript/dashboard/`.

---

## Complexity Tracking

*No constitution violations. All additions follow decoupled extension points.*
