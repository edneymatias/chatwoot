# Implementation Plan: Scout Custom Tool Authentication & Visual Parameter Builder

**Branch**: `051-scout-tool-auth-parameters` | **Date**: 2026-08-26 | **Spec**: [specs/051-scout-tool-auth-parameters/spec.md](file:///home/matias/Projects/chatwoot/specs/051-scout-tool-auth-parameters/spec.md)

**Input**: Feature specification from `/specs/051-scout-tool-auth-parameters/spec.md`

## Summary

Enhance the Scout custom tool configuration experience by replacing manual JSON headers and raw JSON Schema text areas with:
1. **Standardized HTTP Authentication Modes**: A dedicated dropdown for `None`, `Bearer Token`, `Basic Auth`, and `API Key`, with dynamic credential fields and secure ActiveRecord encryption at rest.
2. **Visual Parameter Builder**: An interactive list allowing operators to add, edit, reorder, and remove parameters, specifying the parameter name (with strict identifier validation, uniqueness enforced client- and server-side), type (`String`, `Number`, `Integer`, `Boolean`, `Array`, `Object`), semantic description for the LLM, and required status.
3. **Seamless Schema Compilation & Decompilation**: Automatically compiling visual parameters into standard JSON Schema for AI tool calling and decompiling existing JSON Schema when editing tools.
4. **Secret Masking & Safe Updates**: Masking secrets (`••••••••`) when editing tools while safely retaining existing encrypted credentials if unchanged.
5. **Interactive Testing Integration**: Pre-populating the test connection playground with sample values derived from the visual parameters and executing requests with formatted authentication headers.

---

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.1.x) / JavaScript (Vue 3 Composition API `<script setup>`, Vite, Tailwind CSS)

**Primary Dependencies**: Liquid (template parsing), SafeFetch (`lib/safe_fetch.rb` for SSRF-protected HTTP calls), Base64 (Basic Auth encoding), Axios (frontend API client)

**Storage**: PostgreSQL (`ichatr_scout_tools` table with new `auth_type` string column and encrypted `auth_headers`)

**Testing**: RSpec (`custom/spec/models/scout_tool_spec.rb`, `custom/spec/services/custom/scout/tools/http_request_executor_spec.rb`, `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`), Vitest / ESLint

**Target Platform**: Linux container (Docker Compose on rootless Podman) / Modern Web Browsers

**Project Type**: Full-stack web service & dashboard UI extension under `custom/` and `app/javascript/`

**Performance Goals**: Instant client-side JSON Schema compilation (<1ms); strict identifier regex validation without UI lag; sub-second test execution via `HttpRequestExecutor`

**Constraints**: Strict parameter identifier regex (`/^[a-zA-Z_][a-zA-Z0-9_]*$/`); no raw JSON fallback; full RuboCop (150-char max) and ESLint compliance; synchronous bilingual translations (`en`/`pt_BR`)

**Scale/Scope**: Account-scoped custom tools callable by AI agents in commercial conversations and configurable by admins and agents

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

- [x] **I. Upstream Compatibility First**: All backend logic is isolated in `custom/` (`custom/app/models/scout_tool.rb`, `custom/app/services/custom/scout/tools/http_request_executor.rb`, `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb`). Database table `ichatr_scout_tools` uses the custom fork prefix. No core upstream tables or models are touched.
- [x] **II. Smallest Production-Ready Change**: Reuses existing `HttpRequestExecutor` and `ScoutToolModal.vue` without premature abstractions or unnecessary dependencies.
- [x] **III. Adhere to Established Conventions**: Follows RuboCop rules (150-char max line length, compact class syntax), Vue 3 Composition API `<script setup>`, Tailwind utility classes only (no custom/scoped CSS), and synchronous `en.json`/`pt_BR.json` translations.
- [x] **IV. Safe, Reversible Change Management**: Migration adds a nullable/defaulted `auth_type` string column to `ichatr_scout_tools` (additive and reversible).
- [x] **V. Dual-Tree Awareness**: Scout custom tools are fork-specific and decoupled from the enterprise Captain module. Checked and confirmed no conflict with `enterprise/`.

---

## Project Structure

### Documentation (this feature)

```text
specs/051-scout-tool-auth-parameters/
├── plan.md              # Implementation plan
├── research.md          # Phase 0 research and architectural decisions
├── data-model.md        # Phase 1 data model and sequence diagrams
├── quickstart.md        # Phase 1 verification and quickstart guide
├── checklists/
│   └── requirements.md  # Requirements quality checklist
└── contracts/
    └── scout-tools-api.md # Phase 1 API specifications
```

### Source Code Layout

```text
custom/
├── app/
│   ├── controllers/
│   │   └── api/
│   │       └── v1/
│   │           └── accounts/
│   │               └── scout_tools_controller.rb   # Permit auth_type, handle masked credential updates & serialization
│   ├── models/
│   │   └── scout_tool.rb                           # Add auth_type validation, masked credentials representation, and backend parameter_schema name/uniqueness safeguard validation
│   └── services/
│       └── custom/
│           └── scout/
│               └── tools/
│                   └── http_request_executor.rb     # Support auth_type (Bearer, Basic, API Key, None) header assembly
└── spec/
    ├── controllers/
    │   └── api/
    │       └── v1/
    │           └── accounts/
    │               └── scout_tools_controller_spec.rb # Specs for auth_type, masked secrets, and testing
    ├── models/
    │   └── scout_tool_spec.rb                      # Specs for auth_type and encrypted auth_headers
    └── services/
        └── custom/
            └── scout/
                └── tools/
                    └── http_request_executor_spec.rb # Specs for Bearer, Basic, API Key header formatting

db/migrate/
└── 21260826180000_add_auth_type_to_ichatr_scout_tools.rb # Add auth_type column to ichatr_scout_tools

config/
└── locales/
    ├── en.yml                                        # Backend validation error messages (auth_type, parameter names)
    └── pt_BR.yml                                      # Portuguese backend validation error messages

app/javascript/
├── dashboard/
│   ├── components-next/
│   │   └── Scout/
│   │       └── pageComponents/
│   │           └── ScoutToolModal.vue               # Auth dropdown, dynamic credential inputs, visual parameter builder with reorder; legacy raw headers/schema textareas removed
│   └── i18n/
│       └── locale/
│           ├── en/
│           │   └── scout.json                       # English localization keys
│           └── pt_BR/
│               └── scout.json                       # Portuguese localization keys
```

**Structure Decision**: Selected standard isolated fork architecture with all custom backend models, controllers, and services in `custom/`, additive migration under `db/migrate/`, and frontend modal enhancements under `app/javascript/dashboard/`.

---

## Complexity Tracking

*No constitution violations. All additions follow decoupled extension points.*
