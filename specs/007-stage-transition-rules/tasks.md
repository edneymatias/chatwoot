# Tasks: Stage Transition Rules

**Input**: Design documents from `/specs/007-stage-transition-rules/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not explicitly requested by the spec as TDD. RSpec/Vue test tasks are included in the
Polish phase (verification after implementation, per plan.md's `spec/` scope), not as pre-implementation
gates. The one exception is T026, which adds a targeted regression test for User Story 3's
independent-test criterion (see Phase 5).

**Organization**: Tasks are grouped by user story (US1-US5, per spec.md priorities) to enable
independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps task to a specific user story for traceability
- All descriptions include exact file paths

## Path Conventions

Rails API + Vue dashboard (existing monorepo layout). New domain code under `custom/app/**`;
migrations under `db/migrate/`; frontend under `app/javascript/dashboard/`. Two pre-existing core
files are touched (three edits total, called out explicitly per plan.md):
`app/models/custom_attribute_definition.rb` (enum addition + widget pre-chat callback-guard
exclusion) and `app/javascript/dashboard/routes/dashboard/settings/attributes/constants.js`
(constant addition).

---

## Phase 1: Setup

No project-initialization work needed — this feature extends the existing `custom/` Kanban module
established in `specs/001-kanban-backend-core`; all tooling (RuboCop, ESLint, RSpec, `pnpm test`)
is already configured. Proceed directly to Foundational.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema, core-file additions, and shared model/policy scaffolding that every user story
depends on.

**⚠️ CRITICAL**: No user story work should start until this phase is complete.

- [ ] T001 [P] Migration: add `custom_attributes` (jsonb, default `{}`) and `value` (decimal)
  columns to `matias_opportunities` in
  `db/migrate/<timestamp>_add_value_and_custom_attributes_to_matias_opportunities.rb`
- [ ] T002 [P] Migration: add `requires_deal_value` (boolean, default `false`) column to
  `matias_pipeline_stages` in
  `db/migrate/<timestamp>_add_requires_deal_value_to_matias_pipeline_stages.rb`
- [ ] T003 [P] Migration: create `matias_pipeline_stage_required_fields` table
  (`account_id`, `pipeline_stage_id`, `custom_attribute_definition_id`, timestamps) with a unique
  index on `(account_id, custom_attribute_definition_id)` in
  `db/migrate/<timestamp>_create_matias_pipeline_stage_required_fields.rb`
- [ ] T004 Add `opportunity_attribute: 3` to the `attribute_model` enum in
  `app/models/custom_attribute_definition.rb` (core-file edit 1 of 2 in this file)
- [ ] T005 In the same file, exclude `opportunity_attribute?` from the
  `update_widget_pre_chat_custom_fields` (`after_update`) and `sync_widget_pre_chat_custom_fields`
  (`after_destroy`) callback guards in `app/models/custom_attribute_definition.rb` (core-file edit
  2 of 2 in this file, per research.md §1 validated follow-up — required, not optional)
- [ ] T006 [P] Add `{ id: 3, key: 'OPPORTUNITY' }` to `ATTRIBUTE_MODELS` in
  `app/javascript/dashboard/routes/dashboard/settings/attributes/constants.js` (ONLY core-file
  frontend touch)
- [ ] T007 Create `PipelineStageRequiredField` model in
  `custom/app/models/pipeline_stage_required_field.rb`: `belongs_to :account`,
  `belongs_to :pipeline_stage`, `belongs_to :custom_attribute_definition`; validates the
  definition's `attribute_model == 'opportunity_attribute'`
- [ ] T008 [P] Create `PipelineStageRequiredFieldPolicy` in
  `custom/app/policies/pipeline_stage_required_field_policy.rb`, mirroring
  `custom/app/policies/pipeline_stage_policy.rb`
- [ ] T009 Add nested `resources :required_fields, only: [:create, :destroy], controller:
  'pipeline_stage_required_fields'` inside the existing `resources :pipeline_stages` block in
  `config/routes.rb`
- [ ] T010 Extend `PipelineStage` in `custom/app/models/pipeline_stage.rb`:
  `has_many :pipeline_stage_required_fields, dependent: :destroy`,
  `has_many :required_custom_attribute_definitions, through: :pipeline_stage_required_fields,
  source: :custom_attribute_definition`, and a `before_save` callback that unsets
  `requires_deal_value` on every other stage in the account when set to `true` on the current
  record (per research.md §2)

**Checkpoint**: Schema, enum, model, policy, and route scaffolding exist. User story
implementation can now begin.

---

## Phase 3: User Story 1 - Sales rep is guided to complete required info before advancing a deal (Priority: P1) 🎯 MVP

**Goal**: Forward stage moves with missing required fields are blocked and the rep is prompted to
fill them; satisfied moves proceed immediately. Backward/lateral moves are never blocked, even
before US3 is implemented — this story's own tasks (T018) already carry that direction check, so
it is not a P2-only concern.

**Independent Test**: Configure one stage with a required field (see US2 for the config UI, or
seed via Rails console per quickstart.md §1-2), drag a card lacking it into that stage, confirm
the rep is prompted and blocked until filled, confirm the card moves once submitted. Also confirm
dragging that same card into an earlier stage never prompts and completes immediately (FR-006).

### Implementation for User Story 1

- [ ] T011 [US1] Add forward-move required-field validation to `Opportunity` in
  `custom/app/models/opportunity.rb`: `on: :update, if: :pipeline_stage_id_changed?`, compares
  `pipeline_stage_id_was`'s position against the new stage's position, skips entirely if not
  strictly greater, otherwise checks each destination-stage `PipelineStageRequiredField`'s
  `attribute_key` is present in `custom_attributes` (key-presence, not truthiness — see
  data-model.md's field-presence rule) and `value` is present if `requires_deal_value`; adds a
  structured error and populates a `missing_required_fields` accessor
- [ ] T012 [US1] Permit `value`/`custom_attributes` params on `create`/`update` and build the
  structured `422` body (`missing_required_fields: { custom_attribute_keys:, requires_value: }`)
  from `Opportunity#missing_required_fields` in
  `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`
- [ ] T013 [US1] Add `requires_deal_value` and `required_custom_attribute_definitions` (id,
  attribute_key, attribute_display_name, attribute_display_type) to the `#index`/`#show` JSON in
  `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`
- [ ] T014 [US1] Extend the `pipelineStages` Vuex module (`getters`/`actions`) in
  `app/javascript/dashboard/store/modules/pipelineStages/` to expose the new
  `required_custom_attribute_definitions`/`requires_deal_value` fields per stage
- [ ] T015 [US1] Extend the `opportunities` Vuex module's `moveCard` action and `byId` map in
  `app/javascript/dashboard/store/modules/opportunities/` to send/store `custom_attributes`/`value`
- [ ] T016 [P] [US1] Create shared `OpportunityRequiredFieldsForm.vue` in
  `app/javascript/dashboard/components-next/Opportunities/OpportunityRequiredFieldsForm.vue`,
  reusing existing `components-next/CustomAttributes/*` per-display-type input components
- [ ] T017 [US1] Create `StageTransitionRequirementsModal.vue` in
  `app/javascript/dashboard/components-next/Opportunities/StageTransitionRequirementsModal.vue`
  (follows `OpportunityCreateModal.vue`'s `woot-modal` convention), embedding
  `OpportunityRequiredFieldsForm.vue`, showing the destination stage's required fields as required
  and every earlier stage's required fields as optional editable context (FR-009)
- [ ] T018 [US1] Extend `dispatchMoveIfComplete` in
  `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue` with, in order: (1) a
  direction/position guard — compare the destination stage's `position` against the origin stage's
  `position` and, when the destination is not strictly greater (backward or lateral move), dispatch
  `opportunities/moveCard` immediately with no required-field lookup and no modal (FR-006); (2) for
  forward moves only, look up the destination stage's (and all earlier stages') required fields
  against the dragged opportunity's current `custom_attributes`/`value`, and if unsatisfied, open
  `StageTransitionRequirementsModal` instead of dispatching `opportunities/moveCard`. The direction
  guard MUST ship as part of this task so backward/lateral moves are never blockable at any point
  in the MVP (US1+US2), not only once US3 (Phase 5) lands.
- [ ] T019 [US1] Wire the modal's submit handler to `update` the opportunity's `value`/
  `custom_attributes` then dispatch `opportunities/moveCard`; wire cancel to revert the card to its
  original stage with no API call
- [ ] T020 [US1] Handle the second retry path from FR-008: if the `opportunities/moveCard` dispatch
  wired in T019 (or any other forward-move dispatch, e.g. a stale-data race where the proactive
  check in T018 passed but the backend validation added in T011 still rejects it) receives a `422`
  with a `missing_required_fields` body, catch it in
  `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`, revert the card's
  optimistic position, and (re)open `StageTransitionRequirementsModal` pre-filled with whatever
  `value`/`custom_attributes` the user had already entered plus the server-reported missing fields

**Checkpoint**: User Story 1 is fully functional and independently testable (given at least one
manually-seeded required field), including both FR-008 retry paths (proactive-check catch and
backend-rejection catch) and the backward/lateral short-circuit.

---

## Phase 4: User Story 2 - Sales manager defines what information is required at each stage (Priority: P1)

**Goal**: Managers can assign/reassign required custom fields and the deal-value flag per stage,
with single-lane-exclusivity enforced.

**Independent Test**: Open a stage's settings, assign a field and the deal value as required, save,
confirm the requirement now shows up when attempting to move a card into that stage (per US1).

### Implementation for User Story 2

- [ ] T021 [US2] Create `PipelineStageRequiredFieldsController` (`create`/`destroy`) in
  `custom/app/controllers/api/v1/accounts/pipeline_stage_required_fields_controller.rb`:
  `create` deletes any existing row for that `custom_attribute_definition_id` in the account before
  creating the new one (the "reassignment steals it" semantics, atomic within the request)
- [ ] T022 [US2] Permit `requires_deal_value` on `PipelineStage#update` in
  `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`
- [ ] T023 [P] [US2] Add a lane-requirements config section (checkbox list of
  `opportunity_attribute`-model definitions plus a "requires deal value" toggle) to
  `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`
- [ ] T024 [P] [US2] Add the same lane-requirements config section to
  `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue`
- [ ] T025 [US2] Add `pipelineStages` store actions for assigning/unassigning a required field
  (calling the `required_fields` create/destroy endpoints) in
  `app/javascript/dashboard/store/modules/pipelineStages/actions.js`

**Checkpoint**: User Stories 1 and 2 together deliver the MVP — configurable, enforced
required-field gating end to end, including both retry paths and the backward/lateral guard.

---

## Phase 5: User Story 3 - Rep is never blocked when moving a deal backward (Priority: P2)

**Goal**: Add explicit regression coverage confirming backward/lateral moves never trigger
validation or a proactive-check network lookup. The behavior itself already ships as part of the
MVP: the direction guard added in T018 (US1) enforces this from the very first release, per this
finding's remediation (backward-move safety cannot be a P2-only add-on since it's core to FR-006).
This phase exists to lock that behavior in with a dedicated test rather than to add new production
code.

**Independent Test**: Drag a card with missing required fields into an earlier stage; confirm no
prompt appears and the move completes immediately. Confirm this passes even with only T011-T020
(US1) implemented, before any Phase 5 task runs.

### Implementation for User Story 3

- [ ] T026 [US3] Add a component test asserting `dispatchMoveIfComplete`'s direction guard (T018)
  dispatches `opportunities/moveCard` immediately without opening `StageTransitionRequirementsModal`
  or performing a required-field lookup, for both a strictly-backward move and a lateral
  (same-position) move, in
  `app/javascript/dashboard/components-next/Opportunities/specs/KanbanBoard.spec.js`

**Checkpoint**: Backend enforcement (T011) and client-side enforcement (T018) both already skip
validation for non-forward moves as of the MVP; this task adds the automated regression coverage
that proves it.

---

## Phase 6: User Story 4 - Deal creator sees relevant fields without being forced to fill them (Priority: P2)

**Goal**: The creation form surfaces the selected starting stage's required fields as optional,
non-blocking context.

**Independent Test**: Start creating an opportunity, select a stage with required fields, confirm
those fields render on the form, confirm the opportunity can still be saved without filling them.

### Implementation for User Story 4

- [ ] T027 [US4] Extend `OpportunityCreateModal.vue` in
  `app/javascript/dashboard/components-next/Opportunities/OpportunityCreateModal.vue` to render
  `OpportunityRequiredFieldsForm.vue` for the currently-selected starting stage's required fields,
  re-rendering when the stage selection changes
- [ ] T028 [US4] Include `value`/`custom_attributes` (if filled) in the creation payload dispatched
  from `OpportunityCreateModal.vue`; no backend change needed since the validation added in T011 is
  scoped `on: :update` only (creation is exempt per FR-010)

**Checkpoint**: Creation flow surfaces expectations without ever blocking.

---

## Phase 7: User Story 5 - Rep can backfill missing information without moving the deal (Priority: P3)

**Goal**: Cards sitting in a stage with unmet requirements (via backward move or reconfiguration)
expose a manual "complete fields" action.

**Independent Test**: Put a card into a stage with unmet requirements, confirm a "complete fields"
action is visible, opens the missing fields, and updates the deal in place without changing its
stage; confirm the action is hidden once requirements are satisfied.

### Implementation for User Story 5

- [ ] T029 [US5] Add a computed property to
  `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` that determines whether
  the card's current stage has any unmet required field/deal-value, using the same
  `pipelineStages`/`opportunities` store data as T018
- [ ] T030 [US5] Add the "complete fields" action button (visible only when T029's computed is
  true) to `KanbanCard.vue`, opening a modal that reuses `OpportunityRequiredFieldsForm.vue`;
  submit calls `opportunities/updateOpportunity` (value/custom_attributes only, no
  `pipeline_stage_id` change) and closes the modal

**Checkpoint**: All five user stories are independently functional and testable.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T031 [P] Add new user-facing strings (modal titles/labels, "complete fields" action,
  "Opportunity" attribute-model option) to `app/javascript/dashboard/i18n/locale/en/*.json`
- [ ] T032 Run `docker compose exec rails bundle exec rubocop -a` and
  `docker compose exec vite pnpm eslint:fix`; resolve any remaining offenses
- [ ] T033 [P] Add/update RSpec coverage: `spec/models/opportunity_spec.rb`,
  `spec/models/pipeline_stage_spec.rb`, `spec/models/pipeline_stage_required_field_spec.rb`,
  `spec/requests/api/v1/accounts/opportunities_controller_spec.rb`,
  `spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb`,
  `spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb`
- [ ] T034 Manually execute `quickstart.md` scenarios 1-9 end to end in the running dev stack
  (`docker compose up -d`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: No dependencies — start immediately. BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational only. Fully testable on its own with
  manually-seeded required-field data (no config UI needed). Includes both the direction guard and
  the backend-422-retry handling (T018/T020), so its independent test already covers backward-move
  safety and the full FR-008 retry contract without needing US3.
- **User Story 2 (Phase 4)**: Depends on Foundational only, independent of US1's files, but
  US1 + US2 together are the true MVP (spec.md notes US2 exists to feed US1's enforcement).
- **User Story 3 (Phase 5)**: Depends on Foundational and US1 (specifically T018, which already
  implements the direction guard). This phase adds regression-test coverage for behavior that
  ships with US1, rather than adding new production code.
- **User Story 4 (Phase 6)**: Depends on Foundational and T016 (`OpportunityRequiredFieldsForm.vue`
  from US1); otherwise independent of US2/US3/US5.
- **User Story 5 (Phase 7)**: Depends on Foundational, T013/T014 (stage requirement data) and T016
  (shared form component) from US1; independent of US2/US3/US4.
- **Polish (Phase 8)**: Depends on all desired user stories being complete.

### Parallel Opportunities

- T001, T002, T003 (migrations) — different files, run in parallel.
- T006 (frontend constant) is independent of the backend Foundational tasks — parallel with T004/T005/T007-T010.
- T008 (policy) is independent of T007 (model) in terms of file, but logically follows it — safe to
  parallelize since it only mirrors an existing policy shape.
- T016 (`OpportunityRequiredFieldsForm.vue`) has no dependency on T011-T015 and can be built in
  parallel with the backend tasks of US1.
- T023/T024 (Edit/Add pipeline stage config sections) — different files, parallel.
- T031/T033 in Polish — different files, parallel.

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 2: Foundational.
2. Complete Phase 3: User Story 1 (core enforcement + modal + both FR-008 retry paths + the
   backward/lateral direction guard).
3. Complete Phase 4: User Story 2 (config UI, so US1's enforcement has real data to act on).
4. **STOP and VALIDATE**: run quickstart.md scenarios 1-6, including a backward-move check.
5. Deploy/demo if ready — this is the feature's core value per spec.md, and it already ships safe
   for backward moves without needing Phase 5.

### Incremental Delivery

1. Foundational → ready.
2. US1 + US2 → MVP: managers configure requirements, reps are guided/blocked accordingly, and
   backward moves are already never blocked.
3. US3 → dedicated regression test locking in the backward-move guarantee already shipped in US1.
4. US4 → creation form surfaces expectations non-blockingly.
5. US5 → backfill safety net for backward-move/reconfiguration edge cases.
6. Polish → i18n, lint, specs, full quickstart pass.

## Format Validation

All tasks above use `- [ ] T### [P?] [Story?] Description with file path`: Setup/Foundational/
Polish tasks omit the `[Story]` label; every Phase 3-7 task carries its `[US#]` label; every task
names its exact file path.

## Phase 9: Convergence
- [X] T035 CRITICAL: Review and remove `PipelineStageRequiredFields.vue` and generic `EditOpportunityModal.vue` per plan: config sections and backfill modal (unrequested)
- [X] T036 Add component test asserting `dispatchMoveIfComplete` direction guard dispatches immediately for backward/lateral moves in `app/javascript/dashboard/components-next/Opportunities/specs/KanbanBoard.spec.js` per US3/T026 (missing)
- [X] T037 Add a computed property to determine if the card's current stage has any unmet required field/deal-value in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` per US5/T029 (missing)
- [X] T038 Add the "complete fields" action button (visible only when unmet requirements exist) opening a backfill modal in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` per US5/T030 (missing)
- [X] T039 Add a lane-requirements config section (checkbox list of opportunity_attribute definitions + "requires deal value" toggle) to `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue` per US2/T023 (partial)
- [X] T040 Add the same lane-requirements config section to `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue` per US2/T024 (partial)
- [X] T041 Add RSpec coverage in `spec/models/pipeline_stage_required_field_spec.rb` per Polish/T033 (partial)
- [X] T042 Add RSpec coverage in `spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb` per Polish/T033 (partial)

## Phase 10: Convergence
- [X] T043 Render earlier-stage fields as genuinely optional without a required asterisk in StageTransitionRequirementsModal.vue by passing them to optionalCustomAttributeDefinitions per FR-009 (partial)
- [X] T044 Review and justify or revert the inclusion of all opportunity attributes in OpportunityBackfillModal.vue (rather than strictly required ones) per plan: OpportunityBackfillModal scope (unrequested)

## Phase 11: Convergence
- [X] T045 Delete existing PipelineStageRequiredField records for the given custom_attribute_definition_id across the account before creating the new one in `PipelineStageRequiredFieldsController#create` per FR-003/SC-003 (missing)
- [X] T046 Hide the generic edit/complete fields button in `KanbanCard.vue` when there are no unmet requirements per FR-013 (contradicts)
- [X] T047 Restrict `OpportunityBackfillModal.vue` to only render fields required by the card's current stage, removing the inclusion of all other opportunity attributes per FR-013 (contradicts)
