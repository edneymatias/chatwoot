# Implementation Plan: Deal Card Customization

**Branch**: `012-deal-card-customization` | **Date**: 2026-08-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-deal-card-customization/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Admins configure up to 3 fields (deal custom attributes and/or the built-in "Deal Value") to
display as colored, value-only badges on every kanban deal card, account-wide. Backend adds two
new fork-scoped tables + models + admin-only controllers/policies under `custom/`: one for the
list of up to 3 configured card fields (following the exact shape of the existing
`PipelineClosingRequiredField` feature), and one singleton-per-account table for the account's
currency setting. The currency setting is surfaced in the same "Card Fields" settings tab for lack
of a more general pipeline-settings home today, but it is account-wide infrastructure intended to
eventually govern every monetary display in the pipeline (cards, future totals, future reports) —
this phase only wires it into the card badge. Frontend adds two Vuex modules, a new "Card Fields"
settings tab (reusing `ColorPicker.vue` for badge colors, plus a currency selector), and a new
badge row on `KanbanCard.vue` (reusing `Label.vue`'s color-badge pattern, and a small new
currency-formatting helper mirroring the existing `constants/billing.js` shape). Non-monetary
formatting reuses existing date/list/plain-value display conventions as-is.

## Technical Context

**Language/Version**: Ruby on Rails 7.1 (backend), Vue 3 + Vuex (frontend, Composition API with
`<script setup>`)

**Primary Dependencies**: Rails, Pundit (authorization), ActiveRecord; Vue 3, Vuex, `@lk77/vue3-color`
(via existing `ColorPicker.vue`), `@chatwoot/utils` (`getContrastingTextColor`, via existing
`Label.vue` pattern)

**Storage**: PostgreSQL — new tables `matias_pipeline_card_field_configs` and
`matias_pipeline_currency_settings`

**Testing**: RSpec (backend model/request specs, only if requested — repo convention is to avoid
writing specs unless explicitly asked); `pnpm test` / `pnpm eslint` and `bundle exec rubocop` as
mandatory lint/quality gates regardless

**Target Platform**: Web (existing Chatwoot dashboard, server-rendered Rails API + Vue SPA)

**Project Type**: Web application (Rails API backend + Vue frontend monolith)

**Performance Goals**: N/A — low-cardinality per-account config (max 3 rows), read once per board
load; no new perf-sensitive path

**Constraints**: Hard cap of 3 configured fields per account (enforced client- and server-side);
admin-only configuration; zero visual change to cards when no fields are configured; no new color
palette or currency-formatting infrastructure (reuse existing conventions only)

**Scale/Scope**: Single new table, single new controller/policy/model, one new Vuex module, one
new settings tab, one new card row — account-scoped, no multi-pipeline concept yet (see spec
Assumptions)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment |
|---|---|
| I. Upstream Compatibility First | **PASS** — new models/controllers/policies live under `custom/app/...`; both new tables use the `matias_` prefix; `Account`/`CustomAttributeDefinition` gain associations via the existing `Custom::Concerns::*` + `include_mod_with` extension point (one new concern module, one new one-line core wiring statement), not by editing core model bodies. Mirrors `PipelineClosingRequiredField` exactly for the field-config table, and the existing singular-resource pattern (`resource :branded_email_layout`/`saml_settings`) for the currency setting (see [research.md](research.md)). |
| II. Smallest Production-Ready Change | **PASS** — no new color palette, no reordering UI, no speculative multi-pipeline scoping (explicitly deferred per spec Assumptions), no generic key-value settings table for the currency setting (a dedicated small table instead). The one new currency-formatting helper is a small, structurally-copied duplicate of the existing `constants/billing.js` shape, scoped to exactly the two currencies already supported elsewhere in this fork — not a speculative general-purpose formatter. Reuses `ColorPicker.vue`, `Label.vue`, `ApiClient`, and the `PipelineStage#set_position` append pattern as-is. |
| III. Adhere to Established Conventions | **PASS** — Tailwind-only styling (badge inline `style` for the free-hex color is the pre-existing Labels exception, not a new one), Composition API `<script setup>`, PascalCase components, i18n for all new strings, Pundit policy, strong params. |
| IV. Safe, Reversible Change Management | **PASS** — purely additive migration (`create_table`), no destructive operations. |
| V. Dual-Tree Awareness (OSS + Enterprise) | **PASS** — confirmed no `enterprise/` code references `PipelineStage`/`Opportunity`/pipeline concepts today; this feature needs no Enterprise override or extension point. |

No violations. Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/012-deal-card-customization/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── pipeline-card-field-configs-api.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
├── <timestamp>_create_matias_pipeline_card_field_configs.rb
└── <timestamp>_create_matias_pipeline_currency_settings.rb

custom/app/models/
├── pipeline_card_field_config.rb
├── pipeline_currency_setting.rb
└── custom/concerns/
    ├── account.rb                        # add has_many :pipeline_card_field_configs,
    │                                      # has_one :pipeline_currency_setting
    └── custom_attribute_definition.rb    # NEW concern, has_many :pipeline_card_field_configs

custom/app/controllers/api/v1/accounts/
├── pipeline_card_field_configs_controller.rb
└── pipeline_currency_settings_controller.rb

custom/app/policies/
├── pipeline_card_field_config_policy.rb
└── pipeline_currency_setting_policy.rb

app/models/custom_attribute_definition.rb   # append one line:
                                             # CustomAttributeDefinition.include_mod_with('Concerns::CustomAttributeDefinition')

config/routes.rb                            # add: resources :pipeline_card_field_configs,
                                             #   only: [:index, :create, :update, :destroy]
                                             # add: resource :pipeline_currency_setting,
                                             #   only: [:show, :update]

app/javascript/dashboard/
├── api/
│   ├── pipelineCardFieldConfigs.js
│   └── pipelineCurrencySetting.js         # singleton API client (show/update, no id)
├── constants/
│   └── pipelineCurrency.js                # NEW — SUPPORTED_PIPELINE_CURRENCIES,
│                                           # getCurrencyConfig, formatCurrencyAmount
│                                           # (structurally mirrors constants/billing.js)
├── store/modules/
│   ├── pipelineCardFieldConfigs/
│   │   ├── actions.js
│   │   ├── mutations.js
│   │   ├── getters.js
│   │   └── index.js
│   └── pipelineCurrencySetting/
│       ├── actions.js
│       ├── mutations.js
│       ├── getters.js
│       └── index.js
├── components-next/Opportunities/
│   ├── KanbanBoard.vue                   # dispatch pipelineCardFieldConfigs/fetch and
│   │                                      # pipelineCurrencySetting/fetch on mount
│   └── KanbanCard.vue                    # add configured-fields badge row, incl. currency
│                                          # formatting for deal_value / currency-type badges
└── routes/dashboard/settings/pipelineStages/
    ├── Index.vue                         # add "Card Fields" tab, placed first
    └── CardFieldConfig.vue               # NEW, styled after ClosingRequiredFields.vue,
                                           # includes the currency selector

app/javascript/dashboard/i18n/locale/en/
└── (relevant locale file, e.g. opportunities.json or a pipeline-stages-mgmt locale) — new strings
```

**Structure Decision**: Web application monolith (existing Rails + Vue structure). All new
fork-specific backend code goes under `custom/app/...` per Constitution Principle I; core Rails
files (`app/models/custom_attribute_definition.rb`, `config/routes.rb`) receive only the minimal
one-line/one-block wiring additions already established for sibling features. Frontend additions
follow the existing `pipelineClosingRequiredFields` module/component shape under
`app/javascript/dashboard/`.

## Complexity Tracking

> Not applicable — no Constitution Check violations.
