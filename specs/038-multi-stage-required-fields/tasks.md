# Tasks: Multi-Stage Required Fields

**Input**: Design documents from `/specs/038-multi-stage-required-fields/`  
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/pipeline-stage-required-fields-api.md), [quickstart.md](./quickstart.md)

**Organization**: Tasks are grouped by foundational infrastructure and user stories to enable incremental implementation and independent verification.

---

## Phase 1: Setup

**Purpose**: Prepare database migration and local environment.

- [X] T001 Generate additive migration file `db/migrate/21260817100000_change_ichatr_pipeline_stage_req_fields_unique_index.rb` to replace the account-scoped unique index on `ichatr_pipeline_stage_required_fields` with a stage+account-scoped unique index `idx_ichatr_pipeline_stage_req_fields_on_acc_stage_attr` on `[:account_id, :pipeline_stage_id, :custom_attribute_definition_id]`

---

## Phase 2: Foundational (Database & Model Uniqueness)

**Purpose**: Core database schema and model validation changes required for all user stories.

**⚠️ CRITICAL**: Must complete before user story write-path modifications.

- [X] T002 Execute database migration via `docker compose exec rails bundle exec rails db:migrate`
- [X] T003 [P] Update model validation in `custom/app/models/pipeline_stage_required_field.rb` to scope `custom_attribute_definition_id` uniqueness to `[:account_id, :pipeline_stage_id]`
- [X] T004 [P] Update locale string `errors.pipeline_stage_required_field.already_required` in `config/locales/en.yml` to `'is already required in this pipeline stage'`
- [X] T005 [P] Update locale string `errors.pipeline_stage_required_field.already_required` in `config/locales/pt_BR.yml` to `'já é obrigatório neste estágio do funil'`

**Checkpoint**: Database index and model validation now allow the same attribute across multiple stages while prohibiting same-stage duplicates.

---

## Phase 3: User Story 1 - Require the Same Custom Field in Multiple Stages (Priority: P1) 🎯 MVP

**Goal**: Allow sales managers to configure the same custom attribute as required across multiple stages in the same pipeline without cross-stage overwrites or "already required" errors.

**Independent Test**: Configure custom attribute X on Stage A, then configure attribute X on Stage B. Both configurations persist independently and neither is deleted.

### Tests for User Story 1

- [X] T006 [P] [US1] Update model specs in `custom/spec/models/pipeline_stage_required_field_spec.rb` to assert uniqueness scoped to `[:account_id, :pipeline_stage_id]` with the updated i18n message
- [X] T007 [P] [US1] Extend request specs in `custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb` to test creating a required field on Stage B when Stage A already requires it, and asserting 422 when attempting duplicate creation on the same stage
- [X] T008 [P] [US1] Extend request specs in `spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb` to verify batch sync (`required_custom_attribute_definition_ids`) on Stage B preserves Stage A's required fields

### Implementation for User Story 1

- [X] T009 [US1] Remove cross-stage `destroy_all` in `PipelineStagesController#sync_required_attributes` in `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`
- [X] T010 [US1] Remove cross-stage `destroy_all` in `PipelineStageRequiredFieldsController#create` in `custom/app/controllers/api/v1/accounts/pipeline_stage_required_fields_controller.rb`

**Checkpoint**: User Story 1 is fully functional and testable. Multi-stage required fields can be created and updated without stealing across stages.

---

## Phase 4: User Story 2 - Field Filled Once is Not Re-Requested on Later Required Stages (Priority: P2)

**Goal**: Ensure opportunities moving through successive stages that require the same custom attribute are not re-prompted once the attribute is populated.

**Independent Test**: Create an opportunity, advance it through Stage A (populating required attribute X), and advance it into Stage B (which also requires attribute X). The second transition succeeds immediately.

### Tests for User Story 2

- [X] T011 [US2] Add unit and transition specs in `spec/models/opportunity_spec.rb` verifying forward movement across multiple stages requiring the same custom attribute (passes when value present, blocks when value missing, skips on backward moves)

**Checkpoint**: User Story 2 transition behavior is verified and covered against regressions.

---

## Phase 5: User Story 3 - Manage Per-Stage Required Fields in UI (Priority: P3)

**Goal**: Ensure the pipeline stage settings modal renders all opportunity custom attributes as available and selectable without cross-stage exclusions.

**Independent Test**: Open the stage edit modal for Stage B when Stage A already has required attributes; confirm all attributes are available to select.

### Verification for User Story 3

- [X] T012 [US3] Verify `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue` and `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue` display all opportunity custom attributes without client-side cross-stage filtering

**Checkpoint**: UI configuration verified end-to-end.

---

## Phase 6: Polish & Quality Gates

**Purpose**: Validate full test suite, linting, sync hooks, and quickstart scenarios.

- [X] T013 [P] Run targeted RSpec test suite: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/pipeline_stage_required_field_spec.rb custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb spec/models/opportunity_spec.rb`
- [X] T014 [P] Run global backend RuboCop check: `docker compose exec rails bundle exec rubocop`
- [X] T015 [P] Run frontend ESLint check: `docker compose exec vite pnpm eslint`
- [X] T016 Verify sync custom module hooks via `docker compose exec rails ruby bin/sync-custom-module-hooks --check && docker compose exec rails ruby bin/sync-custom-module-hooks --audit`
- [X] T017 Execute manual validation scenarios from `specs/038-multi-stage-required-fields/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Migration creation.
- **Foundational (Phase 2)**: DB migration execution + Model & i18n updates (BLOCKS Phase 3+).
- **User Story 1 (Phase 3)**: Controller updates + tests (MVP).
- **User Story 2 (Phase 4)**: Opportunity transition specs (depends on Phase 2 & 3).
- **User Story 3 (Phase 5)**: Frontend verification (depends on Phase 3).
- **Polish (Phase 6)**: Final quality checks & quickstart validation.

### Parallel Opportunities

- **Phase 2**: T003, T004, T005 can execute in parallel after T002.
- **Phase 3**: T006, T007, T008 (test definitions) can be created in parallel.
- **Phase 6**: T013, T014, T015 can run in parallel.

---

## Implementation Strategy

### MVP First (Phase 1 to Phase 3)
1. Generate and run the database migration.
2. Update the model uniqueness scope and i18n strings.
3. Remove controller cross-stage deletions.
4. Run User Story 1 RSpec tests to confirm multi-stage configuration works without errors.

### Incremental Verification
1. Add Opportunity transition specs (User Story 2) to ensure no regressions in Kanban card movement.
2. Verify Settings UI (User Story 3).
3. Execute RuboCop, ESLint, and sync hooks checks (Phase 6).
