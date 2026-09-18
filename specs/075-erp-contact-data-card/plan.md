# Implementation Plan: ERP Contact Panel Data Card

**Branch**: `075-erp-contact-data-card` | **Date**: 2026-09-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/075-erp-contact-data-card/spec.md` (including 2026-09-18 field filtering, formatting, and sub-objects clarifications).

---

## Summary

Phase 02 of the ERP Integration implements an automatic, read-only "ERP Data" card in the agent dashboard contact panel (`ContactPanel.vue`). When an agent views a conversation with a contact in an account with an active ERP integration (e.g., Younus), customer data is fetched by phone number via a backend proxy endpoint (`GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=:contact_id`).

The backend resolution flow (`Erp::BaseAdapter#fetch_data`) caches the resolved external person identifier in `contact.additional_attributes['external']['younus_id']` for direct lookup (`find_by_id`), automatically invalidating and recovering via a single phone search (`search_by_phone`) if the cached record's phone number mismatches or if direct lookup fails. Phone comparison strips non-digits and handles country code prefix variations (Brazil `55`).

The frontend (`ErpDataCard.vue`) renders a curated, human-friendly presentation enforcing a strict whitelist:
1. Technical IDs and internal flags are excluded (`idPessoa`, `idEmpresa`, `pessoaTipo`, `tpPessoa`, `nmPaispessoa`, `idProfpessoa`, `idUsuario`, `idEspecpessoa`, `dtUltacesso`, `stTermo`, `stCadastro`, `stPessoa`, `idConvenio`, `nmConvenio`, `idPerfil`, `observacoes`, `origemPessoa`, `nrConselho`, `siglaConselho`, `ufConselho`, `indClientePadrao`).
2. Whitelisted business fields are displayed with friendly localized labels (e.g. `nrFicha` as "Prontuário", RG positioned adjacent to CPF) and standard Brazilian punctuation masks (CPF/CNPJ, CEP, phone).
3. Date of birth (`dtNascpessoa`) is formatted in the browser locale without time, with a prominent highlight when today is the contact's birthday.
4. Audit timestamps (`dtCadpessoa`, `dtUltaltpessoa`) appear at the bottom of the card as discreet footnotes in italics and smaller font.
5. Structured sections for appointments (`atendimentos` with last and next visits, highlighting next confirmed visit) and financial status (`financeiro` with debtor highlight, oldest overdue installment `parcelaVencida` clearly labeled, and localized currency totals).
6. Card header provides manual refresh, error states provide retry, multiple phone matches are flagged with an informative badge, and friendly localized empty states are presented when contacts have no phone or are unregistered in the ERP.

---

## Technical Context

**Language/Version**: Ruby 3.3+ (Rails 7.1 backend) / JavaScript & Vue 3 (Composition API `<script setup>` with Vite frontend)

**Primary Dependencies**:
- Backend: Rails 7.1, HTTParty (HTTP client), RSpec (testing)
- Frontend: Vue 3, Vuex, Tailwind CSS, Vitest (testing)

**Storage**: PostgreSQL (`contacts.additional_attributes` jsonb, `integrations_hooks.settings` jsonb)

**Testing**:
- Backend: RSpec (`custom/spec/services/erp/`, `custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb`)
- Frontend: Vitest (`app/javascript/dashboard/components/widgets/conversation/specs/ErpDataCard.spec.js`, `app/javascript/dashboard/composables/spec/useUISettings.spec.js`, `app/javascript/dashboard/store/modules/specs/integrations/getters.spec.js`, `app/javascript/dashboard/api/specs/integrations/erp.spec.js`, `app/javascript/dashboard/routes/dashboard/conversation/specs/ContactPanel.spec.js`)

**Target Platform**: Linux container environment (rootless Podman / Docker Compose)

**Project Type**: Web Application (Rails backend + Vue 3 SPA frontend)

**Performance Goals**: Contact panel card render in < 2 seconds under normal network conditions; cached ID lookup eliminating redundant phone searches; 0 blocking on conversation views.

**Constraints**:
- Container-based development only (`docker compose exec rails ...`, `docker compose exec vite ...`).
- Decoupled fork architecture: custom models/controllers/services under `custom/`.
- No direct schema migrations or table modifications.
- Strict whitelist frontend rendering: all unmapped or null attributes omitted from view.
- Standard Brazilian formatting masks applied to CPF/CNPJ, CEP, and phone numbers.
- Manifest tracking in `bin/sync-custom-module-hooks` for any upstream wiring points (`config/routes.rb`, `ContactPanel.vue`, `useUISettings.js`, `integrations.js`).
- Strict TDD discipline per Constitution Principle VI.

**Scale/Scope**: Account-scoped integration; 1 active ERP per account; conversation-level on-demand queries; localized in English (`en`) and Brazilian Portuguese (`pt_BR`).

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evaluation |
|---|---|---|
| **I. Upstream Compatibility First** | **PASS** | Logic lives under `custom/app/services/erp/` and `custom/app/controllers/api/v1/accounts/integrations/erp_controller.rb`. Core file hooks (`routes.rb`, `ContactPanel.vue`, `useUISettings.js`, `integrations.js`) are minimal and tracked in `bin/sync-custom-module-hooks`. No changes to core schema or database migrations. |
| **II. Smallest Production-Ready Change** | **PASS** | Extends existing `Erp::BaseAdapter` and `Erp::Younus::Adapter` from Phase 01. Follows direct precedent of `ShopifyOrdersList.vue` and `Crm::BaseProcessorService`. No speculative background jobs, websockets, or outbound ERP writes. |
| **III. Adhere to Established Conventions** | **PASS** | Follows RuboCop 150-char line limit, compact module definitions, Tailwind utility classes only, Vue Composition API `<script setup>`, and synchronized English/Portuguese i18n (`en.json`, `pt_BR.json`, `en.yml`, `pt_BR.yml`). |
| **IV. Safe, Reversible Change Management** | **PASS** | Purely additive changes; fully reversible; no destructive database operations. |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | **PASS** | ERP integrations are account-level integrations shared across editions. Handled via `Current.account` and `Integrations::Hook` without enterprise divergence. |
| **VI. Test-Driven Development (NON-NEGOTIABLE)** | **PASS** | Test plan covers RSpec unit tests (`Erp::BaseAdapter`, `Erp::Younus::Adapter`, `Erp::Younus::Client`), RSpec request specs (`ErpController`), and Vitest component/store specs (`ErpDataCard.vue`, `integrations.js`, `useUISettings.js`). |
| **VII. Observable Behavior and Mutation Resistance** | **PASS** | Assertions validate actual HTTP responses, database attribute mutations on contacts, and rendered DOM elements in the card (badges, masked fields, empty states). Mocks are restricted to remote HTTP calls to the external Younus API. |
| **VIII. Pragmatic Test-First by Functional Slice** | **PASS** | Delivered in cohesive functional slices: (1) backend resolution and proxy endpoint, (2) frontend store and UI settings, (3) frontend card component with whitelist, formatting, appointments, and financial sub-objects. |
| **IX. Surgical Execution Scope and Decoupled Global Gates** | **PASS** | Iterative test runs target only the specific spec file being modified (`bundle exec rspec custom/spec/...` and `pnpm vitest run ...`). Full suite runs reserved for pre-release validation. |

---

## Project Structure

### Documentation (this feature)

```text
specs/075-erp-contact-data-card/
├── spec.md              # Feature specification with clarifications
├── plan.md              # Implementation plan (this document)
├── research.md          # Phase 0 research findings and architectural decisions
├── data-model.md        # Phase 1 entity definitions and state transitions
├── quickstart.md        # Phase 1 validation and verification guide
├── tasks.md             # Phase 2 implementation task list
└── contracts/           # Phase 1 interface contracts
    ├── erp-proxy-api.md        # HTTP contract for GET /api/v1/.../integrations/erp/data
    ├── younus-remote-api.md    # Remote Younus webhook API contract
    ├── erp-adapter-contract.md # Internal Ruby adapter contract
    └── erp-card-ui-contract.md # Frontend component UI and display contract
```

### Source Code (repository root)

```text
# Backend (custom domain tree)
custom/
├── app/
│   ├── controllers/
│   │   └── api/
│   │       └── v1/
│   │           └── accounts/
│   │               └── integrations/
│   │                   └── erp_controller.rb   # Proxy controller for ERP data
│   └── services/
│       └── erp/
│           ├── base_adapter.rb                 # Resolution algorithm, cache, phone match
│           └── younus/
│               ├── adapter.rb                  # Younus adapter primitives (find_by_id, search_by_phone)
│               └── client.rb                   # Younus HTTP client (/webhook/pessoa & /pessoas)
└── spec/
    ├── requests/
    │   └── api/
    │       └── v1/
    │           └── accounts/
    │               └── integrations/
    │                   └── erp_controller_spec.rb # Request spec for proxy endpoint
    └── services/
        └── erp/
            ├── base_adapter_spec.rb            # Resolution algorithm and phone matching tests
            └── younus/
                ├── adapter_spec.rb             # Adapter primitive tests
                └── client_spec.rb              # Remote client HTTP and timeout tests

# Frontend (Dashboard Vue app)
app/javascript/dashboard/
├── api/
│   └── integrations/
│       └── erp.js                             # API client extending ApiClient
├── components/
│   └── widgets/
│       └── conversation/
│           ├── ErpDataCard.vue                 # Customer data card with whitelist, formatting, sub-objects
│           └── specs/
│               └── ErpDataCard.spec.js         # Vitest component tests (all states, sub-objects, masks)
├── composables/
│   ├── useUISettings.js                        # Default order & open state support
│   └── spec/
│       └── useUISettings.spec.js               # Updated settings tests
├── routes/
│   └── dashboard/
│       └── conversation/
│           └── ContactPanel.vue                # Accordion integration below contact attributes
└── store/
    └── modules/
        ├── integrations.js                     # getEnabledErpIntegration store getter
        └── specs/
            └── integrations/
                └── getters.spec.js             # Extended store getter tests

# Locales & Upstream Sync Tracking
config/
├── routes.rb                                   # Integrations erp proxy route
└── locales/
    ├── en.yml                                  # Backend error messages (EN)
    └── pt_BR.yml                               # Backend error messages (PT-BR)
app/javascript/dashboard/i18n/locale/
├── en/
│   └── conversation.json                       # Frontend labels, statuses, empty states, sub-objects (EN)
└── pt_BR/
    └── conversation.json                       # Frontend labels, statuses, empty states, sub-objects (PT-BR)
bin/sync-custom-module-hooks                    # MANIFEST tracking for routes, ContactPanel, useUISettings, integrations.js
```

**Structure Decision**:
- All new backend logic is cleanly namespaced under `custom/app/` to ensure 100% upstream isolation per Constitution Principle I.
- Frontend component resides under `app/javascript/dashboard/components/widgets/conversation/ErpDataCard.vue`, matching sibling widgets like `ShopifyOrdersList.vue`.
- Core file hook points (`config/routes.rb`, `ContactPanel.vue`, `useUISettings.js`, `integrations.js`) are tracked in `bin/sync-custom-module-hooks`.

---

## Complexity Tracking

> No violations of the Constitution exist; all principles and guidelines are strictly respected.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *None* | N/A | N/A |
