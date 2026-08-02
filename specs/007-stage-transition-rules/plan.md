# Implementation Plan: Stage Transition Rules

**Branch**: `007-stage-transition-rules` | **Date**: 2026-08-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-stage-transition-rules/spec.md`

## Summary

Add lane-level required-field enforcement to the Kanban pipeline: `Opportunity` gains a `value`
column and a `custom_attributes` jsonb column; `PipelineStage` gains a `requires_deal_value` flag
and a many-to-one join to `opportunity_attribute`-model `CustomAttributeDefinition`s via a new
`PipelineStageRequiredField` model (one stage per field, account-unique). A model validation
blocks forward-only stage moves that leave a required field unset, surfaced client-side by a
proactive check before dispatch (opening `StageTransitionRequirementsModal`) and backed by a
structural `422` from the same validation if bypassed. The stage-aware creation form and a
per-card "complete fields" action reuse the same shared field-rendering component, non-blocking in
both cases. Everything lives in the existing `custom/` tree and reuses the existing
`CustomAttributeDefinition`/`components-next/CustomAttributes` infra; the only touches outside
`custom/`/`db/migrate/` are the pre-approved `attribute_model` enum addition plus the exclusion of
the new `opportunity_attribute?` value from the widget pre-chat custom-field sync callback guards
(both in `custom_attribute_definition.rb`, backend), and the `ATTRIBUTE_MODELS` constant addition
(frontend) — all called out explicitly in the spec's Context as the minimal core-file cost of
reuse.

## Technical Context

**Language/Version**: Ruby (Rails 7.1, matching the existing `custom/` tree), Vue 3 (Composition
API, `<script setup>`, matching `components-next/`)

**Primary Dependencies**: Rails (ActiveRecord, ActionController), Pundit (existing
`OpportunityPolicy`/`PipelineStagePolicy`), Vuex (existing `opportunities`/`pipelineStages`/
`customAttributes` store modules), existing `components-next/CustomAttributes/*` input components

**Storage**: PostgreSQL — two new columns on `matias_opportunities` (`custom_attributes` jsonb,
`value` decimal), one new column on `matias_pipeline_stages` (`requires_deal_value` boolean), one
new additive table `matias_pipeline_stage_required_fields`

**Testing**: RSpec (`docker compose exec rails bundle exec rspec ...`) for models/policy/
controllers; `pnpm test`/`pnpm eslint` (via `docker compose exec vite`) for the new Vue components
and store actions

**Target Platform**: Existing Chatwoot Rails monolith + Vue 3 dashboard, Docker/Podman Compose dev
stack

**Project Type**: Web application (Rails API + Vue dashboard, both touched)

**Performance Goals**: N/A beyond existing API conventions — the frontend proactive check and the
"complete fields" visibility check both reuse data already loaded into the `pipelineStages`/
`opportunities` stores (per FR-009/FR-013 of the spec, no new fetch is introduced for either)

**Constraints**: Zero edits to existing core tables (only additive columns on the fork's own
`matias_*` tables plus one new fork-owned table); the two enum/constant additions to
`CustomAttributeDefinition` and `ATTRIBUTE_MODELS` are the only edits to pre-existing core files,
and are additive (new enum value / new array entry), not restructuring

**Scale/Scope**: 1 new model (`PipelineStageRequiredField`), 1 new controller, 3 migrations, 2
existing models gain columns/validation, 1 existing controller gains permitted params + structured
422 response, 1 new Vue component (`OpportunityRequiredFieldsForm.vue`) reused across 3 call sites
(new `StageTransitionRequirementsModal.vue`, `OpportunityCreateModal.vue` extension,
`KanbanCard.vue` "complete fields" modal), 1 new settings-screen section
(`EditPipelineStage.vue`/`AddPipelineStage.vue`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)**: PASS. All new domain code
  (`PipelineStageRequiredField` model/policy/controller) lives under `custom/app/**`, mirroring
  the tree structure and `matias_` table-prefix convention already established by
  `custom/app/models/opportunity.rb` and `custom/app/models/pipeline_stage.rb`. The new join
  table `matias_pipeline_stage_required_fields` follows the same prefix. Three edits outside
  `custom/`/`db/migrate/`, all in two pre-existing core files:
  - `CustomAttributeDefinition#attribute_model` enum gaining `opportunity_attribute: 3` — strictly
    additive (new enum member), no reordering or removal of existing members.
  - `CustomAttributeDefinition`'s `update_widget_pre_chat_custom_fields`/
    `sync_widget_pre_chat_custom_fields` callback guards excluding `opportunity_attribute?` —
    a targeted, one-line exclusion so the new model value is never synced into the (conversation-
    only) widget pre-chat field list; it narrows an existing conditional rather than restructuring
    it, and changes behavior only for the newly-introduced enum value, so existing
    `conversation_attribute`/`contact_attribute`/`company_attribute` behavior is unaffected.
  - The frontend `ATTRIBUTE_MODELS` constant gaining `{ id: 3, key: 'OPPORTUNITY' }` — additive,
    new array entry.

  All three carry effectively zero upstream merge-conflict risk while avoiding a parallel,
  hand-rolled custom-field system. This tradeoff (reuse via minimal core touches vs. building a
  fully isolated duplicate custom-field system under `custom/`) is recorded in Complexity Tracking
  below per the constitution's decouple-over-couple rule.
- **II. Smallest Production-Ready Change**: PASS. Scope is capped to what the spec's functional
  requirements need: no multi-field-per-lane-per-priority ordering, no "sticky" required-forever
  concept, no bulk retroactive re-validation, no new automation action category — all explicitly
  out of scope per the spec.
- **III. Adhere to Established Conventions**: PASS. New Ruby code follows RuboCop conventions and
  existing `custom/app/**` patterns (Pundit policies, `belongs_to`/validation shape already used
  by `Opportunity`/`PipelineStage`). New Vue code uses Composition API + `<script setup>`,
  Tailwind-only styling, and reuses existing `components-next/CustomAttributes/*` input
  components rather than introducing new per-display-type inputs (FR-012 of spec).
- **IV. Safe, Reversible Change Management**: PASS. All three migrations are additive
  (`add_column`, `create_table`) with straightforward reversals; none alter or drop existing
  columns/tables.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (no Enterprise action needed). This is a
  personal-fork-only feature under `custom/`, extending the fork's own `Opportunity`/
  `PipelineStage` models, not a core OSS feature Enterprise would override. The two core-file
  touches (`CustomAttributeDefinition` enum, `ATTRIBUTE_MODELS` constant) are additive and
  model-agnostic — they don't change existing `conversation_attribute`/`contact_attribute`/
  `company_attribute` behavior, so no Enterprise counterpart is required. Documented here per the
  constitution's requirement to make this decision explicit.

## Project Structure

### Documentation (this feature)

```text
specs/007-stage-transition-rules/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── pipeline-stage-required-fields-api.md
│   └── opportunities-api-additions.md
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
└── app/
    ├── models/
    │   ├── opportunity.rb                          # +custom_attributes/value columns, +forward-move validation
    │   ├── pipeline_stage.rb                       # +requires_deal_value, +single-lane-exclusivity callback, +has_many required_fields
    │   └── pipeline_stage_required_field.rb         # NEW
    ├── policies/
    │   └── pipeline_stage_required_field_policy.rb  # NEW (mirrors pipeline_stage_policy.rb)
    └── controllers/api/v1/accounts/
        ├── opportunities_controller.rb              # +value/custom_attributes params, +422 structured error
        ├── pipeline_stages_controller.rb            # +requires_deal_value param, +required-field JSON embed
        └── pipeline_stage_required_fields_controller.rb  # NEW (create/destroy)

db/migrate/
├── <timestamp>_add_value_and_custom_attributes_to_matias_opportunities.rb
├── <timestamp>_add_requires_deal_value_to_matias_pipeline_stages.rb
└── <timestamp>_create_matias_pipeline_stage_required_fields.rb

config/routes.rb                                     # +nested resource under pipeline_stages

app/models/custom_attribute_definition.rb            # +opportunity_attribute: 3 enum member,
                                                       # +excludes opportunity_attribute? from the
                                                       # widget pre-chat sync callback guards
                                                       # (ONLY core-file edits, both in this file)

app/javascript/dashboard/routes/dashboard/settings/attributes/constants.js
                                                       # +{ id: 3, key: 'OPPORTUNITY' } (ONLY core edit)

app/javascript/dashboard/components-next/Opportunities/
├── KanbanBoard.vue                                   # dispatchMoveIfComplete gains proactive required-field check
├── KanbanCard.vue                                    # +"complete fields" action
├── OpportunityCreateModal.vue                        # +stage-aware required-fields section
├── OpportunityRequiredFieldsForm.vue                  # NEW (shared)
└── StageTransitionRequirementsModal.vue               # NEW

app/javascript/dashboard/routes/dashboard/settings/pipelineStages/
├── EditPipelineStage.vue                             # +lane-requirements config section
└── AddPipelineStage.vue                               # +lane-requirements config section (if applicable)

app/javascript/dashboard/store/modules/
├── pipelineStages/                                    # actions/getters extended for required-field JSON
└── opportunities/                                     # moveCard extended to bundle custom_attributes/value

spec/
├── models/ (opportunity_spec.rb, pipeline_stage_spec.rb, pipeline_stage_required_field_spec.rb)
├── policies/ (pipeline_stage_required_field_policy_spec.rb)
└── requests/api/v1/accounts/
    ├── opportunities_controller_spec.rb
    ├── pipeline_stages_controller_spec.rb
    └── pipeline_stage_required_fields_controller_spec.rb
```

**Structure Decision**: Follows the layout already established by
`specs/001-kanban-backend-core`: new domain logic isolated in `custom/app/**`, migrations under
the Rails-mandated `db/migrate/`, frontend additions under the existing
`components-next/Opportunities/` and `routes/dashboard/settings/pipelineStages/` directories. The
core-file edits (two in `CustomAttributeDefinition`, one in the frontend `ATTRIBUTE_MODELS`
constant) are called out explicitly since they are the only files this feature touches outside the
fork's isolated tree.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|---------------------------------------|
| Three edits to two pre-existing core files (`CustomAttributeDefinition#attribute_model` enum + its widget pre-chat sync callback guards, and the frontend `ATTRIBUTE_MODELS` constant) instead of keeping 100% of new code under `custom/` | Opportunity-level custom fields need to reuse the existing `CustomAttributeDefinition` model, its uniqueness/validation logic, its Attributes settings screen, and every existing per-display-type input component (`CheckboxAttribute`, `DateAttribute`, `ListAttribute`, `OtherAttribute`) — duplicating that infra under `custom/` would mean re-implementing a second custom-attribute system from scratch. The callback-guard exclusion is needed because, without it, every new `opportunity_attribute` definition would incorrectly get synced into the (conversation-only) widget pre-chat field list. | A fully isolated `custom/`-only custom-field system was rejected: Chatwoot's custom-attribute infra already solves definition CRUD, uniqueness, display-type rendering, and settings UI; forking it would violate Principle II (smallest production-ready change) far more than these targeted core edits violate Principle I. Both edits are provably narrow: the enum addition is a new member with zero impact on existing members, and the callback-guard exclusion only changes behavior for the newly-introduced enum value — `conversation_attribute`/`contact_attribute`/`company_attribute` behavior is unchanged either way. |
