---

description: "Task list for Kanban Lane Visual Improvements"

---

# Tasks: Kanban Lane Visual Improvements

**Input**: Design documents from `/specs/013-kanban-lane-visual-improvements/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/pipeline-stage-aggregates-api.md, quickstart.md

**Tests**: Not requested in the feature spec — no test tasks are included, per repo convention
(avoid writing specs unless explicitly asked). `pnpm eslint` and `bundle exec rubocop` remain
mandatory quality gates (see Polish phase).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing
of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Path Conventions

Web app (Rails + Vue monolith), per plan.md's Project Structure — the new aggregate controller
lives under `custom/app/...`, minimal core wiring in `config/routes.rb`, frontend under
`app/javascript/dashboard/...`.

---

## Phase 1: Setup

**Purpose**: No new tooling/dependencies are needed — this feature extends the existing
`PipelineStage` model, `pipelineStages` Vuex module, and `EditPipelineStage.vue`/`KanbanColumn.vue`
components already in the repo. Nothing to initialize.

*(No tasks — proceed directly to Foundational.)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The data model and aggregate API that every user story depends on, either directly
(US1 reads the aggregate; US2 and US3 write the two new columns) or transitively (nothing renders
correctly until the columns exist and are exposed by the existing stage payload).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T001 Create migration `db/migrate/<timestamp>_add_total_display_mode_and_accent_color_to_matias_pipeline_stages.rb` adding `total_display_mode` (integer, `null: false, default: 0`) and `accent_color` (string, nullable, no default) to `matias_pipeline_stages`, per data-model.md
- [X] T002 Run the migration and confirm schema.rb updates (`docker compose exec rails bundle exec rails db:migrate`)
- [X] T003 In `custom/app/models/pipeline_stage.rb`, add `enum total_display_mode: { value_sum: 0, count: 1 }` and confirm `accent_color` is accepted as a plain attribute (no format validation), per data-model.md
- [X] T004 In `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`, add `:total_display_mode` and `:accent_color` to the permitted params in `pipeline_stage_params` (`create`/`update` both use this method already, so one edit covers both actions)
- [X] T005 Create `Api::V1::Accounts::PipelineStageAggregatesController` in `custom/app/controllers/api/v1/accounts/pipeline_stage_aggregates_controller.rb` with an `index` action per contracts/pipeline-stage-aggregates-api.md: requires `stage_ids[]` (422 if missing/empty), runs `Current.account.opportunities.where(pipeline_stage_id: stage_ids, status: :open).group(:pipeline_stage_id)` with `count` and `sum(:value)`, merges into a `[{ pipeline_stage_id:, open_count:, open_value_sum: }]` array (stages with zero open opportunities simply absent), includes `Concerns::KanbanFeatureGuard` and `check_authorization` against `PipelineStage`, mirroring `PipelineStagesController`
- [X] T006 Add route in `config/routes.rb`: `resources :pipeline_stage_aggregates, only: [:index]`, alongside the existing `pipeline_stages` route
- [X] T007 [P] Create frontend API client `app/javascript/dashboard/api/pipelineStageAggregates.js` extending `ApiClient` with `accountScoped: true`, resource `pipeline_stage_aggregates`, overriding `get()` to accept and serialize a `stageIds` array as repeated `stage_ids[]` query params
- [X] T008 [P] In `app/javascript/dashboard/store/modules/pipelineStages/mutations.js`, add `SET_STAGE_AGGREGATES(state, { stageId, openCount, openValueSum })` (camelCase payload — the T009 action is responsible for mapping the API's snake_case `open_count`/`open_value_sum` fields to these camelCase args before committing) that merges the aggregate into `state.byId[stageId]` (no-op if the stage isn't present)
- [X] T009 In `app/javascript/dashboard/store/modules/pipelineStages/actions.js`, add `fetchAggregates: async ({ commit }, { stageIds }) => { ... }` that calls the T007 API client with `stageIds`, maps each returned entry's `open_count`/`open_value_sum` to `openCount`/`openValueSum` and dispatches `SET_STAGE_AGGREGATES` for it, and sets `openCount: 0, openValueSum: 0` for any requested `stageIds` absent from the response — no dedicated error handling: if the API call itself rejects, the action does not commit anything (all requested stages keep their existing `open_count`/`open_value_sum` untouched), leaving the failure to the existing global API error interceptor, per FR-011

**Checkpoint**: The two new `PipelineStage` columns exist and are admin-settable via the API, and
the aggregate endpoint + Vuex plumbing can be exercised directly (e.g. via `curl`/Vuex devtools) —
user story implementation can now begin.

---

## Phase 3: User Story 1 - Accurate lane totals (Priority: P1) 🎯 MVP

**Goal**: Every lane header shows an accurate, lane-wide total (value by default) of open
opportunities, independent of pagination, refreshed after any deal-affecting action, with no
loading indicator.

**Independent Test**: Load a lane with more open deals than fit in the first page of cards;
confirm the header total reflects the full lane. Move/create/close/reopen/edit a deal and confirm
only the affected lane's total updates, without a page reload.

### Implementation for User Story 1

- [X] T010 [US1] In `KanbanBoard.vue`'s `onMounted` hook, after `pipelineStages/fetch` resolves, dispatch `pipelineStages/fetchAggregates` with every stage's id from `stages.value`
- [X] T011 [US1] In `KanbanBoard.vue`'s `executeMoveCard`, on success, dispatch `pipelineStages/fetchAggregates` with `stageIds: [move.fromStageId, move.toStageId]`
- [X] T012 [US1] In `KanbanBoard.vue`'s `onStatusChanged`, on success, dispatch `pipelineStages/fetchAggregates` with `stageIds: [opportunity's pipeline_stage_id]` (read from `store.state.opportunities.byId[id]` before/after the status update, since the stage itself doesn't change)
- [X] T013 [US1] In `OpportunityCreateModal.vue`'s `submit()`, the existing `emit('created', opp)` (line 142) already fires before `onClose()` — in `KanbanBoard.vue`, add an `@created` handler on `<OpportunityCreateModal>` that dispatches `pipelineStages/fetchAggregates` with `stageIds: [opp.pipeline_stage_id]`
- [X] T014 [US1] In `OpportunityBackfillModal.vue`'s `submit()`, change the success path to `emit('updated', opportunity.value)` before `emit('close')` (mirroring `OpportunityCreateModal.vue`'s `created` event), and add `'updated'` to its `defineEmits` list; in `KanbanBoard.vue`, add an `@updated` handler on `<OpportunityBackfillModal>` that dispatches `pipelineStages/fetchAggregates` with `stageIds: [opportunity.pipeline_stage_id]`
- [X] T015 [US1] In `KanbanColumn.vue`, replace the `{{ cards.length }}` badge (lines 90-94) with a computed value: `stage.open_count ?? 0` when `stage.total_display_mode === 'count'`, otherwise a compact-formatted `stage.open_value_sum ?? 0` via `Intl.NumberFormat` (`notation: 'compact'`) combined with the currency resolved through `pipelineCurrencySetting/getCurrency` and `formatCurrencyAmount` from `dashboard/constants/pipelineCurrency` — render nothing (empty) until the first aggregate response arrives (no loading indicator, per FR-010), then update in place silently on every subsequent fetch

**Checkpoint**: Lane header totals are accurate and update surgically after every deal-affecting
action, with the default "total value" display mode. (Per-lane display-mode switching is US3; lane
color is US2 — neither blocks this checkpoint.)

---

## Phase 4: User Story 2 - Per-lane color accent (Priority: P2)

**Goal**: An admin can set an optional color accent on a lane's header bottom border, with zero
effect on card rendering, and clear it back to unset.

**Independent Test**: Set a color on one lane via its settings and confirm only that lane's header
border changes; everything else on the board (including that lane's own cards) is visually
unchanged. Clear the color and confirm the header returns to its default border.

### Implementation for User Story 2

- [X] T016 [US2] In `EditPipelineStage.vue`, add an `accentColor` ref initialized from `props.stage.accent_color` in `onMounted`, render a `ColorPicker.vue` (`dashboard/components-next/colorpicker/ColorPicker.vue`, same component used by Phase 14's `CardFieldConfig.vue`) bound to it with a way to clear it back to `null`/empty, and include `accent_color: accentColor.value || null` in the `pipelineStages/update` dispatch payload in `submit()`
- [X] T017 [US2] In `KanbanColumn.vue`'s header container (`div.flex.items-center.justify-between.p-3.border-b.border-n-weak`, line 82), add `:style="stage.accent_color ? { borderBottomColor: stage.accent_color } : {}"` layered on top of the existing `border-b border-n-weak` class, changing only the border color when `accent_color` is set and leaving today's `border-n-weak` appearance untouched when it isn't
- [X] T018 [P] [US2] Add new i18n strings for the accent color field (label, clear-color action) to `app/javascript/dashboard/i18n/locale/en/opportunities.json`, following the existing `PIPELINE_STAGES_MGMT.FORM`/`PIPELINE_STAGES_MGMT.REQUIREMENTS` key structure

**Checkpoint**: Admins can set and clear a lane's color accent end-to-end; the board shows it only
on the affected header, with no change anywhere else.

---

## Phase 5: User Story 3 - Choosing what a lane's total shows (Priority: P3)

**Goal**: An admin can switch a lane's header between "count" and "total value" display, with
"total value" as the default when unset.

**Independent Test**: Change a lane's display choice from value to count (or vice versa) and
confirm only that lane's header changes to the new format, never showing both at once.

### Implementation for User Story 3

- [X] T019 [US3] In `EditPipelineStage.vue`, add a `totalDisplayMode` ref initialized from `props.stage.total_display_mode || 'value_sum'` in `onMounted`, render a select/radio with the two options ("Total value" default, "Count"), and include `total_display_mode: totalDisplayMode.value` in the `pipelineStages/update` dispatch payload in `submit()`
- [X] T020 [P] [US3] Add new i18n strings for the lane header display select (label, "Total value"/"Count" option labels) to `app/javascript/dashboard/i18n/locale/en/opportunities.json`, following the same key structure as T018

**Checkpoint**: All three user stories now work end-to-end — accurate surgical-refresh totals,
optional per-lane color, and admin-chosen count/value display, all independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final quality gates across all three stories

- [X] T021 [P] Run `docker compose exec rails bundle exec rubocop -a` and fix any offenses in touched Ruby files
- [X] T022 [P] Run `docker compose exec vite pnpm eslint --fix` and fix any offenses in touched JS/Vue files
- [X] T023 Walk through `quickstart.md` end-to-end in a running dev stack (all 4 scenarios: accurate value total, count mode, color accent, zero-state/closed-deal exclusion) and fix any discrepancies found

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: No dependencies — start immediately. BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Phase 2 only.
- **User Story 2 (Phase 4)**: Depends on Phase 2 only — does NOT depend on Phase 3.
- **User Story 3 (Phase 5)**: Depends on Phase 2 only — does NOT depend on Phase 3 or 4.
- **Polish (Phase 6)**: Depends on all three user story phases being complete.

### Within Phase 2 (Foundational)

- T001 → T002 (migrate after creating the migration)
- T002 → T003, T004 (model/controller changes need the columns to exist to be exercised, though
  the edits themselves can be written in parallel with T002 running)
- T003 → T005 (aggregate controller queries `Opportunity`, unaffected by T003 directly, but T005
  should land after the table has the columns it will eventually read via the stage payload)
- T005 → T006 (route wires to the controller)
- T007, T008 can be written in parallel ([P]) — different files
- T007, T008 → T009 (action uses both the API client and the mutation)

### Within Phase 3 (US1)

- T010, T011, T012, T013, T014 all touch `KanbanBoard.vue` (and, for T014, also
  `OpportunityBackfillModal.vue`) — sequence these edits, don't run them concurrently
- T009 (Foundational) → all of T010-T015 (they dispatch `fetchAggregates`)
- T015 is independent of T010-T014 (different file, `KanbanColumn.vue`) and can be written in
  parallel with them

### Within Phase 4 (US2)

- T016 and T017 touch different files and can be written in parallel ([P] in spirit, though not
  marked since T017 also touches `KanbanColumn.vue`, shared with T015 in Phase 3 — sequence
  relative to T015, not concurrent)
- T018 can be written in parallel with T016/T017

### Within Phase 5 (US3)

- T019 touches `EditPipelineStage.vue`, the same file as T016 — sequence the two edits, don't run
  them concurrently
- T020 can be written in parallel with T019

### Parallel Opportunities

- T007, T008 (frontend API client + Vuex mutation, different files)
- T015 (US1, `KanbanColumn.vue` badge) in parallel with T010-T014 (US1, `KanbanBoard.vue`/
  `OpportunityBackfillModal.vue`)
- T018, T020 (i18n additions) in parallel with their respective story's other tasks
- T021, T022 (Polish lint passes) in parallel

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Frontend, in parallel once T006 (route) lands:
Task: "Create app/javascript/dashboard/api/pipelineStageAggregates.js"
Task: "Add SET_STAGE_AGGREGATES mutation to app/javascript/dashboard/store/modules/pipelineStages/mutations.js"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (columns, aggregate API, Vuex plumbing)
2. Complete Phase 3: User Story 1 (accurate, surgically-refreshed lane totals)
3. **STOP and VALIDATE**: Confirm lane totals are accurate and update after mutations, independent
   of pagination
4. This alone is the core problem the feature exists to fix — color (US2) and display-mode choice
   (US3) are refinements on top

### Incremental Delivery

1. Foundational → columns + aggregate API + Vuex ready, testable via API calls directly
2. Add User Story 1 → accurate lane totals end-to-end (MVP!)
3. Add User Story 2 → admins can set/clear a lane color accent
4. Add User Story 3 → admins can switch a lane between count/value display
5. Run Polish phase → lint + quickstart validation

### Suggested MVP Scope

Foundational + User Story 1 alone delivers the highest-priority fix (accurate totals) and is
independently demoable/shippable; User Stories 2 and 3 can follow as separate increments without
touching US1's code paths again.

---

## Notes

- No test tasks included — not requested in the spec; lint gates (T021, T022) and manual
  quickstart validation (T023) are the quality bar for this change
- Commit after each task or logical group
- Verify SC-004 (unconfigured/no-color lanes remain visually identical) as part of T023
- T014's addition of an `'updated'` event to `OpportunityBackfillModal.vue` is a small, targeted
  change (mirroring the existing `'created'` event on `OpportunityCreateModal.vue`) needed only so
  `KanbanBoard.vue` can distinguish a successful value edit from a modal cancel — no other behavior
  of that modal changes

## Phase 7: Convergence

- [X] T024 Dispatch `pipelineStages/fetchAggregates` after a deal's value is edited via the Opportunity Drawer (or general update) to keep lane totals accurate without a reload per FR-006 (missing)
- [X] T025 Review and either justify or revert the unrequested 3px bottom border thickness (`border-b-[3px]`) in `KanbanColumn.vue` per T017 / SC-004 (unrequested)
  - *Justification: User explicitly requested this UI change in the prompt: "aumenta a espessura da linha para uns 2 ou 3 pixeis a mais... falo da linha da borda inferior do quadro do titulo das lanes."*
- [X] T026 Review and either justify or remove the unrequested `_prefix: true` addition to the `total_display_mode` enum in `pipeline_stage.rb` per T003 (unrequested)
  - *Justification: Required to fix `ArgumentError`. ActiveRecord already defines a `count` class method, so creating an enum with a `count` key without a prefix raises a fatal 500 error.*
