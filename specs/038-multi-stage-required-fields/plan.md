# Implementation Plan: Multi-Stage Required Fields

**Branch**: `038-multi-stage-required-fields` | **Date**: 2026-08-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/038-multi-stage-required-fields/spec.md`

## Summary

Lift the account-wide restriction that a custom attribute can only be marked as a required
field on a single `PipelineStage`. The restriction is enforced in three places today — a unique
DB index, a model-level `validates :uniqueness` scoped to `account_id` alone, and "steal and
replace" logic in both write endpoints that silently destroys a requirement on any other stage
before creating it on the target stage — and all three must move from "unique per account" to
"unique per stage+account" together, or the destructive steal-and-replace controller logic would
keep silently removing the other stage's requirement even after the DB/model constraint is
loosened.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1), Vue 3 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails ActiveRecord, existing `custom/` fork module (`PipelineStageRequiredField`, `PipelineStage`, `Opportunity`), Vuex store `pipelineStages` module, existing `EditPipelineStage.vue` admin modal

**Storage**: PostgreSQL — `ichatr_pipeline_stage_required_fields` table (fork-prefixed, per constitution)

**Testing**: RSpec (`custom/spec/models`, `custom/spec/requests`) — `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/pipeline_stage_required_field_spec.rb custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb custom/spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb spec/models/opportunity_spec.rb`

**Target Platform**: Existing Chatwoot web dashboard (server-rendered API + Vue SPA)

**Project Type**: Web application (Rails API backend + Vue frontend), fork-specific module under `custom/`

**Performance Goals**: N/A — no new query patterns beyond existing per-account/per-stage lookups already indexed

**Constraints**: Must not touch `enterprise/` (no enterprise coupling found — confirmed via search); must not alter any upstream/core table; new index/migration must be additive per constitution Principle I

**Scale/Scope**: Single migration + model validation change + two controller methods + one i18n message pair (en/pt-BR); no new entities

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. All touched files (`custom/app/models/pipeline_stage_required_field.rb`,
  `custom/app/controllers/api/v1/accounts/pipeline_stage_required_fields_controller.rb`,
  `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`) already live in the
  fork's isolated `custom/` tree; no upstream/core files are edited. The one new migration is
  additive (new index replacing an old one on a fork-prefixed table) and does not touch any
  upstream table.
- **II. Smallest Production-Ready Change**: PASS. Scope is limited to relaxing one constraint
  (DB index, model validation scope, and the two controller methods that currently enforce the
  same constraint imperatively) plus the corresponding i18n string update. No unrelated
  refactor.
- **III. Adhere to Established Conventions**: PASS. Ruby/Rails and Vue changes follow existing
  patterns already used in the same files (RuboCop, strong params, i18n, Composition API already
  in place in `EditPipelineStage.vue`).
- **IV. Safe, Reversible Change Management**: PASS. Migration adds a new unique index and drops
  the old one; both are reversible in a `change` migration. No destructive data operations
  needed (no existing rows can violate the new, less restrictive constraint).
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. Confirmed via search — `PipelineStageRequiredField`
  has no references anywhere under `enterprise/`; no enterprise override or extension point is
  required.

No violations — Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/038-multi-stage-required-fields/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md         # Phase 1 output (/speckit-plan command)
├── contracts/            # Phase 1 output (/speckit-plan command)
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── models/
│   │   └── pipeline_stage_required_field.rb        # uniqueness scope change
│   └── controllers/api/v1/accounts/
│       ├── pipeline_stages_controller.rb            # remove cross-stage destroy_all in sync_required_attributes
│       └── pipeline_stage_required_fields_controller.rb  # remove cross-stage destroy_all in #create
├── spec/
│   ├── models/pipeline_stage_required_field_spec.rb
│   └── requests/api/v1/accounts/
│       ├── pipeline_stage_required_fields_controller_spec.rb
│       └── pipeline_stages_controller_spec.rb

db/migrate/
└── <new>_change_ichatr_pipeline_stage_req_fields_unique_index.rb  # drop (account_id, attr_id) unique index, add (account_id, stage_id, attr_id) unique index

config/locales/
├── en.yml       # errors.pipeline_stage_required_field.already_required wording update
└── pt_BR.yml    # same key, pt-BR wording update

app/javascript/dashboard/routes/dashboard/settings/pipelineStages/
└── EditPipelineStage.vue   # no functional change required (already lists all opportunity attributes unfiltered) — verify only

spec/models/opportunity_spec.rb   # add/extend coverage for FR-003/FR-004 (independent per-stage evaluation, filled-once behavior across multiple required stages)
```

**Structure Decision**: This is a targeted fix entirely inside the fork's existing `custom/`
module plus one core-required migration file (migrations must live under `db/migrate/` per
constitution's stated infrastructure exception) and the two existing locale files. No new
top-level structure, no new frontend components — the existing `EditPipelineStage.vue` admin
modal already presents all opportunity attributes unfiltered per stage (User Story 3 / FR-006 is
already satisfied by current UI; confirmed by reading the component — no cross-stage filtering
exists there today).

## Complexity Tracking

*No violations — table not needed.*
