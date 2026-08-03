# Tasks: Pipeline Stage Reordering

**Input**: Design documents from `/specs/009-pipeline-stage-reordering/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not explicitly requested by the spec as TDD. RSpec coverage is included in the Polish
phase (verification after implementation), matching this repo's convention of not writing specs
speculatively.

**Organization**: Tasks are grouped by user story (US1-US3, per spec.md priorities) to enable
independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps task to a specific user story for traceability
- All descriptions include exact file paths

## Path Conventions

Rails API + Vue dashboard (existing monorepo layout). All backend changes stay inside the existing
fork-specific `custom/app/**` tree; frontend changes stay inside the existing
`app/javascript/dashboard/**` files already owned by this feature. No new migrations, endpoints, or
core/upstream files are touched (see plan.md Constitution Check).

---

## Phase 1: Setup

No project-initialization work needed — this feature extends the existing `custom/` Kanban module
(pipeline stages already exist per `specs/001-kanban-backend-core`); all tooling (RuboCop, ESLint,
RSpec, `pnpm test`) is already configured. Proceed directly to Foundational.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The transactional renumbering logic that every user story depends on — nothing is
independently testable until stage positions are actually persisted and returned correctly.

**⚠️ CRITICAL**: No user story work should start until this phase is complete.

- [x] T001 Add a `reorder_to!(target_position)` instance method to `PipelineStage` in
  `custom/app/models/pipeline_stage.rb`: within a transaction, lock and load all of
  `account.pipeline_stages` ordered by current `position` (`.lock!`), remove `self` from its
  current index, reinsert it at `target_position - 1`, then persist `position = index + 1` for
  every stage in the resulting array whose position actually changed (per data-model.md's State
  transition: Reorder). Returns the freshly-ordered `ActiveRecord::Relation`/array of the account's
  stages.
- [x] T002 In `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb#update`: if
  `pipeline_stage_params[:position]` is present and differs from `@pipeline_stage.position`, call
  `@pipeline_stage.reorder_to!(...)` (from T001) instead of the plain `#update`, and render the
  returned full ordered list as a JSON array (same `include:` shape as `#index`) per
  contracts/pipeline-stage-update.md; otherwise keep the existing single-record `#update` behavior
  unchanged (FR-007 no-op case, and non-position updates).

**Checkpoint**: Backend now renumbers siblings atomically and returns the full ordered list when
`position` changes; non-reorder updates are untouched. User story implementation can now begin.

---

## Phase 3: User Story 1 - Reorder pipeline stages from settings (Priority: P1) 🎯 MVP

**Goal**: An admin drags a stage to a new position in Pipeline Stages settings and the new order is
saved permanently, with every other affected stage's position kept consistent.

**Independent Test**: Drag a stage to a different position in the Pipeline Stages settings list,
reload the page, confirm the stage stays in its new position and no other stage's position is
duplicated or missing (per quickstart.md §1).

### Implementation for User Story 1

- [x] T003 [US1] In `app/javascript/dashboard/store/modules/pipelineStages/actions.js`, update the
  `update` action: if `response.data` (or `response.data.payload`) is an Array, treat it as the full
  reordered stage list; otherwise treat it as a single stage object (existing behavior unchanged)
- [x] T004 [US1] Add a `SET_STAGES` mutation to
  `app/javascript/dashboard/store/modules/pipelineStages/mutations.js` that replaces `state.byId`
  and `state.allIds` from a given array of stages (mirrors `CLEAR_STAGES` + `ADD_MANY_STAGES` +
  `ADD_MANY_STAGES_ID` already used by `fetch`)
- [x] T005 [US1] Wire T003's array branch to commit `SET_STAGES` (T004) with the full list, and the
  object branch to keep committing `UPDATE_STAGE` as today, in
  `app/javascript/dashboard/store/modules/pipelineStages/actions.js`
- [x] T006 [US1] Verify `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/Index.vue`'s
  existing `onChange` handler (dispatches `pipelineStages/update` with `{ id, position: newIndex + 1 }`
  on `event.moved`) needs no further change beyond T003/T005 — its `watch` on
  `pipelineStages/stagesSortedByPosition` already resyncs the local `stages` ref once the store's
  full collection updates

**Checkpoint**: User Story 1 is fully functional and independently testable — dragging a stage in
settings persists a correct, gapless order that survives a reload.

---

## Phase 4: User Story 2 - Kanban board reflects the configured stage order (Priority: P2)

**Goal**: The Kanban board's columns always match the order configured in Pipeline Stages settings.

**Independent Test**: Reorder stages in settings, open the Kanban board, confirm columns appear
left-to-right in the newly configured order without any extra manual action (per quickstart.md §2).

### Implementation for User Story 2

- [x] T007 [US2] Confirm `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`'s
  existing `stages` computed (`store.getters['pipelineStages/stagesSortedByPosition']`) requires no
  code change — it already re-reads the shared `pipelineStages` store module, which is now correct
  as of Phase 2/US1; validate this manually per quickstart.md §2 (no file changes expected, but keep
  this task to explicitly verify no drift/edge case was missed, e.g. columns not re-sorting on
  store mutation)

**Checkpoint**: User Stories 1 and 2 together deliver the MVP — reordering in settings is both
persisted and visible everywhere stages are listed.

---

## Phase 5: User Story 3 - Reorder failures do not corrupt the pipeline (Priority: P3)

**Goal**: A failed reorder save reverts the settings screen's visual order and informs the admin,
without leaving any stage positions duplicated or inconsistent.

**Independent Test**: Simulate a failed save request during a drag-and-drop reorder, confirm the
list reverts to its last known-good order with an error message, and no stage ends up sharing a
position with another (per quickstart.md §3).

### Implementation for User Story 3

- [x] T008 [US3] Wrap the `store.dispatch('pipelineStages/update', ...)` call in
  `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/Index.vue`'s `onChange` handler
  in a try/catch: on failure, reset `stages.value` to
  `[...store.getters['pipelineStages/stagesSortedByPosition']]` (safe since a failed dispatch never
  commits `SET_STAGES`/`UPDATE_STAGE`) and call `useAlert(t('PIPELINE_STAGES_MGMT.REORDER.ERROR'))`
- [x] T009 [P] [US3] Add the `PIPELINE_STAGES_MGMT.REORDER.ERROR` key (e.g. "Couldn't reorder
  pipeline stages. Please try again.") to `app/javascript/dashboard/i18n/locale/en/opportunities.json`,
  alongside the existing `PIPELINE_STAGES_MGMT.DELETE.ERROR` key

**Checkpoint**: All three user stories are independently functional — reordering persists correctly
everywhere, and failures recover gracefully instead of corrupting stage order.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T010 Run `docker compose exec rails bundle exec rubocop -a` and
  `docker compose exec vite pnpm eslint:fix`; resolve any remaining offenses
- [x] T011 [P] Add RSpec coverage: `spec/models/pipeline_stage_spec.rb` (reorder renumbers siblings,
  gapless/unique positions, no-op when position unchanged, and that reordering one account's stages
  never changes another account's stage positions per FR-004) and
  `spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb` (array response on reorder,
  object response on non-reorder update, 422 rolls back the whole transaction, and two
  near-simultaneous reorder requests for the same account resolve to a consistent, non-duplicated
  position set per the concurrent-reorder edge case)
- [x] T012 Manually execute `quickstart.md` scenarios 1-5 end to end in the running dev stack
  (`docker compose up -d`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — skipped, nothing to do.
- **Foundational (Phase 2)**: No dependencies — start immediately. BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational (T001/T002) only. Delivers the core,
  independently testable capability.
- **User Story 2 (Phase 4)**: Depends on Foundational and US1 (T003-T005, since the Kanban board
  reads the same store module US1 fixes) — verification-only task, no new production code expected.
- **User Story 3 (Phase 5)**: Depends on Foundational (T002) and US1's `Index.vue`/store wiring
  (T003-T006) — adds a try/catch around the same dispatch path.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Parallel Opportunities

- T003 and T004 touch different files (`actions.js` vs `mutations.js`) and can be started in
  parallel, though T005 (wiring them together) depends on both.
- T009 (i18n key) is independent of T008 (handler logic) — different files, parallel.
- T011 (RSpec) can be written in parallel with T010 (lint) once implementation tasks are done.

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (backend renumbering + array response).
2. Complete Phase 3: User Story 1 (frontend store resync).
3. **STOP and VALIDATE**: run quickstart.md §1 — drag, reload, confirm order persisted correctly.
4. Deploy/demo if ready — this alone fixes the reported bug ("drag and drop doesn't reorder").

### Incremental Delivery

1. Foundational → ready.
2. US1 → MVP: reordering actually persists in settings.
3. US2 → confirm the Kanban board (which was already reading the same store data) now shows the
   correct order too, with no extra code.
4. US3 → failure-path safety net (revert + alert) on top of the same dispatch.
5. Polish → lint, RSpec coverage, full quickstart pass.

## Format Validation

All tasks above use `- [ ] T### [P?] [Story?] Description with file path`: Setup/Foundational/
Polish tasks omit the `[Story]` label; every Phase 3-5 task carries its `[US#]` label; every task
names its exact file path.
