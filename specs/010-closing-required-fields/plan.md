# Implementation Plan: Closing Required Fields (Win/Loss)

**Branch**: `010-closing-required-fields` | **Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-closing-required-fields/spec.md`

## Summary

Add a second, outcome-based (won/lost) required-attribute mechanism for closing opportunities,
independent of the existing per-stage forward-move mechanism (`PipelineStageRequiredField`). A new
`PipelineClosingRequiredField` model/table maps `(account, custom_attribute_definition, outcome)`.
`Opportunity` gains a validation that runs only when `status_changed?` into `won`/`lost`, reusing
the existing `missing_required_fields` error contract already returned by the `update` action. The
frontend reuses `OpportunityRequiredFieldsForm.vue` inside a new `ClosingRequirementsModal.vue`,
wired into the existing `onStatusChanged` handler in `KanbanBoard.vue` (which today calls
`opportunities/setStatus` with no error handling) the same way `StageTransitionRequirementsModal`
is wired into `executeMoveCard`. Admin configuration is a new settings screen (or tab) listing two
attribute pickers ("required for won" / "required for lost"), reusing the same attribute-selection
UI pattern already built for stage required fields in `EditPipelineStage.vue`.

## Technical Context

**Language/Version**: Ruby 3.x / Rails 7.1 (backend), Vue 3 Composition API / Vuex (frontend) — matches existing `custom/` tree and `app/javascript/dashboard`.

**Primary Dependencies**: ActiveRecord (Postgres), Pundit (policies), Vuex store modules, `vue-i18n`. No new dependencies.

**Storage**: PostgreSQL — new table `matias_pipeline_closing_required_fields`, additive migration only.

**Testing**: RSpec (`bundle exec rspec`) for model/request specs mirroring `custom/spec/models/pipeline_stage_required_field_spec.rb` and `custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb`; `pnpm test` (Vitest) for any new Vue component specs, following existing conventions (avoid writing specs unless explicitly asked per project guidelines — specs listed here are for parity with the existing sibling feature, to be confirmed with the user before writing).

**Target Platform**: Web (Chatwoot dashboard), server-rendered API consumed by Vue SPA.

**Project Type**: Web application (Rails API + Vue SPA) — existing monorepo structure, fork-specific code isolated under `custom/`.

**Performance Goals**: N/A beyond existing request/response latency norms for this admin-scale feature (single-digit rows per account).

**Constraints**: Must not touch upstream/core files for the validation trigger point; extend `Opportunity` (already a fork-owned model under `custom/app/models/opportunity.rb`) directly rather than via `prepend_mod_with`, since it's fork-owned, not upstream. Must not alter `PipelineStageRequiredField`'s existing uniqueness constraint (explicitly out of scope, deferred to parked Phase 18).

**Scale/Scope**: Per-account configuration, low cardinality (a handful of required attributes per outcome per account); no scale concerns.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. New table is namespaced (`matias_` prefix), new model/controller/policy live under `custom/`, wiring into `Opportunity` is a direct edit to an already fork-owned file (not an upstream file), and the new validation is additive (a new `validate :validate_closing_requirements, on: :update, if: :status_changed?` alongside the existing forward-move validation, not a replacement). Frontend changes touch `KanbanBoard.vue` (fork-owned, under `components-next/Opportunities/`) with a small, additive edit to `onStatusChanged`, mirroring the existing `executeMoveCard` try/catch pattern — no upstream file touched.
- **II. Smallest Production-Ready Change**: PASS. Reuses the existing `missing_required_fields` error contract, the existing `OpportunityRequiredFieldsForm.vue`, and the existing attribute-picker UI pattern from `EditPipelineStage.vue`, rather than inventing new UI primitives. No speculative deal-value-based closing requirements (explicitly out of scope per spec Assumptions).
- **III. Adhere to Established Conventions**: PASS. Follows existing model/controller/policy shape 1:1 with `PipelineStageRequiredField`; Vue components use Composition API + `<script setup>`; new UI strings go through i18n (`en.yml` / `en.json`).
- **IV. Safe, Reversible Change Management**: PASS. Purely additive migration; no destructive schema changes.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. `custom/` tree is fork-specific and outside the `enterprise/` overlay; no enterprise-tree changes anticipated since Kanban/Opportunities is not an enterprise feature area today. Flagged for verification in Phase 1 (no enterprise override of `Opportunity`/`OpportunitiesController` currently exists — confirmed via `research.md`).

No violations requiring Complexity Tracking.

**Post-Design Re-check** (after Phase 1 artifacts below): Still PASS on all five principles. Design
artifacts confirmed no enterprise-tree Opportunities code exists (Principle V), no new response
contract was introduced (the existing `missing_required_fields` 422 shape is reused verbatim,
Principle II), and the one deviation from the sibling model — deleting by the join row's own `id`
rather than by `custom_attribute_definition_id` (see `contracts/closing-required-fields-api.md`) —
is a necessary, minimal adaptation forced by the outcome dimension, not scope creep.

## Project Structure

### Documentation (this feature)

```text
specs/010-closing-required-fields/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── closing-required-fields-api.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_create_matias_pipeline_closing_required_fields.rb   # new, additive

custom/app/models/
├── opportunity.rb                          # extend: new validate_closing_requirements
└── pipeline_closing_required_field.rb      # new model

custom/app/controllers/api/v1/accounts/
└── pipeline_closing_required_fields_controller.rb   # new, mirrors pipeline_stage_required_fields_controller.rb

custom/app/policies/
└── pipeline_closing_required_field_policy.rb        # new, mirrors pipeline_stage_required_field_policy.rb

custom/spec/models/
└── pipeline_closing_required_field_spec.rb          # new (only if user confirms specs are wanted)

custom/spec/requests/api/v1/accounts/
└── pipeline_closing_required_fields_controller_spec.rb  # new (only if user confirms specs are wanted)

config/routes.rb                             # extend: new nested/top-level resource for closing required fields

app/javascript/dashboard/
├── components-next/Opportunities/
│   ├── ClosingRequirementsModal.vue         # new, mirrors StageTransitionRequirementsModal.vue
│   └── KanbanBoard.vue                      # extend: onStatusChanged gains try/catch + modal wiring
├── routes/dashboard/settings/pipelineStages/
│   └── ClosingRequiredFields.vue            # new settings screen/tab for won/lost attribute pickers
├── store/modules/
│   ├── opportunities/actions.js             # extend: setStatus accepts optional custom_attributes
│   └── pipelineStages/ (or new pipelineClosingRequiredFields/ module)  # new actions for closing config CRUD
├── api/
│   └── pipelineClosingRequiredFields.js     # new API client, mirrors pipelineStages.js required-field methods
└── i18n/locale/en.json                      # extend: new strings for closing requirements UI

en.yml                                        # extend: backend validation message strings (if any new ones needed)
```

**Structure Decision**: Existing web application layout (Rails API + Vue SPA) is unchanged. All
new backend code lives under the fork-owned `custom/` tree, mirroring the sibling
`PipelineStageRequiredField` feature file-for-file (model, controller, policy, specs). All new
frontend code lives alongside the existing Opportunities/Kanban components and the pipeline stages
settings screen — no new top-level directories.

## Complexity Tracking

*No Constitution Check violations — section not applicable.*
