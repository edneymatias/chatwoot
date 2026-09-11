# Implementation Plan: Scout Opportunity Value Estimation

**Branch**: `070-scout-opportunity-value-estimation` | **Date**: 2026-09-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/070-scout-opportunity-value-estimation/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Auto-fill `Opportunity#value` from an operator-configured interest→value table whenever a
Scout's designated "interest" qualification attribute is set on an Opportunity — either by
classifying the originating ad's own content (headline/body/name) right when the Opportunity is
created from a paid referral, or by the lead's own qualification answer during the conversation.
The value is looked up deterministically from a table the admin maintains; the model never
invents a number, and an interest option with no table entry is left unpriced (never zero). This
closes a real gap: `Reports::SalesForecastCalculator` already treats a missing value as `0.0`
(`custom/app/services/reports/sales_forecast_calculator.rb:113`), so every Scout-originated
opportunity today reports as worthless for forecasting purposes.

## Technical Context

**Language/Version**: Ruby 3.x, Rails 7.2.3.1 (per `Gemfile.lock` — verified during research; not
7.1 as the source design doc's migration snippet assumed), Vue 3 (Composition API, `<script
setup>`)

**Primary Dependencies**: `ruby_llm-schema` 0.3.0 and `ruby_llm` 1.15.0 (structured LLM output,
already used by `Custom::Scout::ActionClassifierSchema`; both pre-2.0 — see `research.md` for a
noted, non-blocking latent-debt caveat about a future `with_temperature`/`Schematist::Schema`
rename), `RubyLLM` chat client via `Scout#llm_chat`, `Integrations::LlmInstrumentation` concern,
Vuex store + `ScoutAPI` on the frontend

**Storage**: PostgreSQL — one new nullable FK column and one new `jsonb` column on the existing
`ichatr_scouts` table (fork-prefixed, per Constitution Principle I); no new tables

**Testing**: RSpec (`bundle exec rspec`) for backend services/model/tool specs; existing frontend
suite (`pnpm test`) only if a Vue unit test already exists for the touched settings tab (none is
required to be added — see spec's "Avoid writing specs unless explicitly asked")

**Target Platform**: Existing Chatwoot Rails monolith + Vue dashboard (self-hosted, containerized
dev per `CLAUDE.md`)

**Project Type**: Web application (Rails API backend + Vue dashboard frontend), fork-specific
feature isolated under `custom/` per Constitution Principle I

**Performance Goals**: N/A beyond existing Scout tool-call latency budget. Verified during
research: `manage_opportunity` executes inside `Custom::Scout::ProcessMessageJob` →
`Custom::Scout::AgentRunner#perform`, a debounced Sidekiq job, not a web request/webhook — so
there is no HTTP timeout at risk. The job already runs a second synchronous LLM call in the same
execution (`Custom::Scout::ActionClassifierService` via `ResponseAuditor`, after the main reply),
which is the real precedent for tolerating one more synchronous LLM call here.

**Constraints**: Must never assign a fabricated monetary value (spec FR-008); must not retroactively
recompute existing Opportunities' values when the table changes (FR-009); must not disclose the
value to the lead (FR-010); classification failures must be silent (treated as "not identified",
per Clarifications)

**Scale/Scope**: Backend: 1 migration, 1 model association, 2 new service classes, 1 new schema
class, 2 call sites inside the existing `manage_opportunity` tool. Frontend: extend the existing
Scout "Funnel" settings tab with an interest-attribute selector and a value-per-option table,
following the `required_custom_attribute_definition_ids` pattern already in
`ScoutFunnelTab.vue`/`ScoutsController`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. All new code lives under `custom/` (new services/
  schema) or extends the fork-owned `Scout` model/`ichatr_scouts` table (already fork-prefixed,
  not an upstream table) and the fork-owned `scouts_controller.rb`/`ScoutFunnelTab.vue`. No
  upstream/core file is touched except the migration (an allowed exception per the constitution,
  additive-only, new columns on a fork-owned table).
- **II. Smallest Production-Ready Change** — PASS. Reuses the exact `any_of`/`null` structured-
  output trick and `include Integrations::LlmInstrumentation` pattern already established by
  `Custom::Scout::ActionClassifierService`/`ActionClassifierSchema` instead of inventing a new
  classification mechanism. No speculative support for non-list attribute types or retroactive
  recompute (explicitly out of scope).
- **III. Adhere to Established Conventions** — PASS. Ruby follows existing service/schema shape;
  Vue settings tab extension follows the existing `ScoutFunnelTab.vue` Composition API + Vuex +
  `ScoutAPI` pattern; new user-facing strings added to `en.json`/`pt_BR.json` (frontend) — no
  backend-rendered strings are introduced by this feature (see i18n reference in
  `app/javascript/dashboard/i18n/locale/{en,pt_BR}/scout.json`).
- **IV. Safe, Reversible Change Management** — PASS. Migration is additive (`add_reference` with
  `on_delete: :nullify`, new `jsonb` column with a safe default `{}`); fully reversible; no
  destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS (no action needed). Scout/Opportunity are
  fork-only (`custom/`) concepts with no `enterprise/` equivalent. `CustomAttributeDefinition` is
  a core OSS model this feature only reads via a `belongs_to` from `Scout` — verified `enterprise/`
  *does* touch it, but only via `enterprise/app/models/enterprise/concerns/custom_attribute_definition.rb`,
  a `conversation_attribute`-only cleanup callback (clears `account.conversation_required_attributes`
  on destroy) that is orthogonal to this feature's `list`/`opportunity_attribute` usage — no
  mirroring needed.

No violations — Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/070-scout-opportunity-value-estimation/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_add_value_estimation_to_ichatr_scouts.rb   # add_reference + jsonb column, additive;
                                                             # ActiveRecord::Migration[7.0] and a
                                                             # separate add_foreign_key statement,
                                                             # matching this table's migration
                                                             # family (see research.md)

custom/app/models/
└── scout.rb                                                # + belongs_to :interest_attribute_definition

custom/app/services/custom/scout/
├── referral_interest_classifier_schema.rb                  # new — dynamic any_of/null enum schema
├── referral_interest_classifier_service.rb                 # new — LLM call over ad content
├── value_estimation_service.rb                             # new — deterministic table lookup + sync
└── tools/
    └── manage_opportunity.rb                                # + 2 call sites (create, update)

custom/app/controllers/api/v1/accounts/
└── scouts_controller.rb                                     # + interest_attribute_definition_id,
                                                               #   value_by_interest permitted params

app/javascript/dashboard/components-next/Scout/pageComponents/
└── ScoutFunnelTab.vue                                        # + interest attribute selector,
                                                               #   value-per-option inputs

app/javascript/dashboard/i18n/locale/en/scout.json
app/javascript/dashboard/i18n/locale/pt_BR/scout.json          # + new labels/hints, kept in sync

custom/spec/services/custom/scout/
├── referral_interest_classifier_service_spec.rb              # new
├── value_estimation_service_spec.rb                          # new
└── tools/manage_opportunity_spec.rb                           # + new examples

custom/spec/models/
└── scout_spec.rb                                              # + association/validation examples
```

**Structure Decision**: This is a fork-specific extension of an existing web application
(Rails API + Vue dashboard). It follows the same shape as every prior Scout phase: backend
services/schema under `custom/app/services/custom/scout/` (mirroring
`Custom::Scout::ActionClassifierService`/`ActionClassifierSchema`), a model change on the
fork-owned `Scout`/`ichatr_scouts`, two call sites inside the existing
`Custom::Scout::Tools::ManageOpportunity` tool, controller param whitelisting following the
existing `required_custom_attribute_definition_ids` precedent in `ScoutsController`, and a
frontend extension of the existing `ScoutFunnelTab.vue` settings tab rather than a new page. No
new top-level directories or new tables are introduced.

## Constitution Check (Post-Design Re-check)

*Re-checked after Phase 1 design (`data-model.md`, `contracts/scouts-api.md`, `quickstart.md`).*

No new violations introduced by design: the data model adds columns only to the fork-owned
`ichatr_scouts` table (Principle I), the API contract extends existing permitted/serialized
fields rather than adding endpoints (Principle II), and both follow directly from patterns already
in the codebase (`audience` jsonb column, `required_custom_attribute_definition_ids` param/response
pair) rather than introducing new ones (Principle III). Still PASS on all five principles.

## Complexity Tracking

*No Constitution Check violations — this section is not applicable.*
