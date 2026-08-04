# Tasks: Stage Dwell-Time Tracking

**Input**: Design documents from `/specs/014-stage-dwell-time-tracking/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not included — the feature spec did not request automated tests, and
this fork's convention (per `CLAUDE.md`) is to avoid writing specs unless
explicitly asked. `quickstart.md` provides the manual validation scenarios.

**Organization**: Tasks are grouped by user story (US1/US2/US3, matching
spec.md priorities P1/P2/P3) so each story is independently implementable,
testable, and deliverable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an
  incomplete task)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths are exact and relative to the repository root

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Data layer that every user story reads from. No separate
project-init "Setup" phase is needed — this feature extends the existing
`custom/` tree and dashboard app directly; there is nothing to scaffold.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete —
all three stories read "time in current stage," which only exists once
transitions are being recorded.

- [X] T001 [P] Create migration `db/migrate/<timestamp>_create_matias_opportunity_stage_changes.rb`: table `matias_opportunity_stage_changes` with `account_id` (FK `accounts`, not null), `opportunity_id` (FK `matias_opportunities`, not null), `from_stage_id` (FK `matias_pipeline_stages`, nullable), `to_stage_id` (FK `matias_pipeline_stages`, not null), `changed_at` (datetime, not null), timestamps; indexes on `[opportunity_id, changed_at]` and `[to_stage_id, changed_at]` (per data-model.md)
- [X] T002 [P] Create migration `db/migrate/<timestamp>_add_stale_after_days_to_matias_pipeline_stages.rb`: `add_column :matias_pipeline_stages, :stale_after_days, :integer` (nullable, no default — matches the `accent_color`/`total_display_mode` migration pattern in `db/migrate/20260804024740_add_total_display_mode_and_accent_color_to_matias_pipeline_stages.rb`)
- [X] T003 Run `docker compose exec rails bundle exec rails db:migrate` and verify `db/schema.rb` reflects both changes (depends on T001, T002)
- [X] T004 Create `custom/app/models/opportunity_stage_change.rb`: `OpportunityStageChange < ApplicationRecord` with `self.table_name = 'matias_opportunity_stage_changes'`, `belongs_to :account`, `belongs_to :opportunity`, `belongs_to :from_stage, class_name: 'PipelineStage', optional: true`, `belongs_to :to_stage, class_name: 'PipelineStage'` (depends on T003)
- [X] T005 In `custom/app/models/opportunity.rb`: add `has_many :stage_changes, class_name: 'OpportunityStageChange', dependent: :destroy`, and two callbacks — `after_create` writing `{ account_id:, opportunity_id: id, from_stage_id: nil, to_stage_id: pipeline_stage_id, changed_at: created_at }`, and `after_update, if: :pipeline_stage_id_changed?` writing `{ account_id:, opportunity_id: id, from_stage_id: pipeline_stage_id_before_last_save, to_stage_id: pipeline_stage_id, changed_at: Time.current }` (depends on T004)

**Checkpoint**: Every opportunity create/stage-move now has a queryable
transition history (`opportunity.stage_changes.order(changed_at: :desc).first.changed_at`
always resolves). All three user stories can now build on this.

---

## Phase 2: User Story 1 - See how long a lead has been stuck in its stage (Priority: P1) 🎯 MVP

**Goal**: Kanban card shows a badge with time elapsed since the opportunity's
most recent stage change (not its creation date, not affected by non-stage edits).

**Independent Test**: Move an opportunity into a stage, wait, view the kanban
board — the card shows a dwell-time badge reflecting time since the last
stage change.

- [X] T006 [US1] In `custom/app/models/opportunity.rb`, add `'current_stage_entered_at' => stage_changes.order(changed_at: :desc).first&.changed_at&.to_i` to the `as_json` merge hash (alongside the existing `created_at`/`contact`/`assignee` keys) (depends on T005)
- [X] T007 [US1] In `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, add a dwell-time badge next to the existing `created_at` badge, rendering `shortTimestamp(dynamicTime(opportunity.current_stage_entered_at))` when `opportunity.current_stage_entered_at` is present, reusing the already-imported `dynamicTime`/`shortTimestamp` helpers and the existing `text-xs text-n-slate-10` neutral badge styling (depends on T006)

**Checkpoint**: User Story 1 is fully functional and testable independently —
run quickstart.md Scenarios 1 & 2.

---

## Phase 3: User Story 2 - Configure a staleness threshold per stage (Priority: P2)

**Goal**: Account admins can set (or leave unset) a per-stage "stale after N
days" threshold from the pipeline stage settings.

**Independent Test**: In pipeline stage settings, set a threshold on one
stage and leave another's empty; confirm both persist independently and no
alert exists for the stage left empty.

- [X] T008 [US2] In `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`, add `:stale_after_days` to the `pipeline_stage_params` permitted list (depends on T003)
- [X] T009 [P] [US2] In `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`, add a `staleAfterDays` ref (initialized from `props.stage.stale_after_days || ''` in `onMounted`), a numeric input in the same settings block as `requiresDealValue`/`totalDisplayMode`/`accentColor`, and include `stale_after_days: staleAfterDays.value === '' ? null : Number(staleAfterDays.value)` in the `pipelineStages/update` dispatch payload in `submit`
- [X] T010 [P] [US2] Add `STALE_AFTER_DAYS_LABEL` and `STALE_AFTER_DAYS_HELP` keys under `PIPELINE_STAGES_MGMT.FORM` in `app/javascript/dashboard/i18n/locale/en/opportunities.json`, and wire them into the new input's label/help text in `EditPipelineStage.vue`

**Checkpoint**: User Story 2 is fully functional and testable independently
of US1/US3 — run quickstart.md Scenario 3.

---

## Phase 4: User Story 3 - Alert styling for stale opportunities (Priority: P3)

**Goal**: The dwell-time badge switches to an alert (amber) style when an
opportunity's time in its current stage exceeds its stage's configured
`stale_after_days`, and never does so when the stage has no threshold set.

**Independent Test**: With a stage's threshold configured, view one
opportunity past the threshold and one within it — only the exceeded one
shows the alert-styled badge; an opportunity in an unconfigured stage never
does, regardless of dwell time.

- [X] T011 [US3] In `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, add a computed `isStale` that returns `false` when `currentStage.value?.stale_after_days` is not set, otherwise compares `getDayDifferenceFromNow(new Date(), opportunity.current_stage_entered_at)` (from `shared/helpers/timeHelper.js`) against `currentStage.value.stale_after_days`; apply `bg-n-amber-3 text-n-amber-11` to the dwell-time badge from T007 when `isStale` is true, keeping the current `text-n-slate-10` styling otherwise (depends on T007, T008)

**Checkpoint**: All three user stories are independently functional — run
quickstart.md Scenario 4.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T012 [P] Run `docker compose exec vite pnpm eslint:fix` on touched `.vue` files and `docker compose exec rails bundle exec rubocop -a` on touched `.rb` files
- [X] T013 Walk through all four `quickstart.md` scenarios end-to-end against the running dev stack

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 1)**: No dependencies — start immediately. BLOCKS all user stories.
- **User Story 1 (Phase 2)**: Depends on Foundational only.
- **User Story 2 (Phase 3)**: Depends on Foundational only (independent of US1).
- **User Story 3 (Phase 4)**: Depends on Foundational, and functionally builds on the badge markup from US1 (T007) and the permitted param from US2 (T008) — implement after both, even though US2's *settings UI* (T009/T010) is not required for US3 to work.
- **Polish (Phase 5)**: Depends on all desired user stories being complete.

### Within Each Phase

- T001/T002 (migrations) are parallel — different files.
- T003 must follow both migrations.
- T004 (model) follows T003; T005 (callbacks) follows T004.
- T009/T010 (US2 frontend + i18n) are parallel — different files — but both follow T008.

### Parallel Opportunities

- T001 and T002 together.
- Once Foundational (Phase 1) is done, US1 (Phase 2) and US2 (Phase 3) can be built in parallel by different people — they touch disjoint files (`opportunity.rb`+`KanbanCard.vue` vs `pipeline_stages_controller.rb`+`EditPipelineStage.vue`+i18n).
- US3 (Phase 4) needs both US1's badge markup and US2's permitted param, so it should start last even though it's a small change.

---

## Parallel Example: Foundational Phase

```bash
Task: "Create migration for matias_opportunity_stage_changes table in db/migrate/<timestamp>_create_matias_opportunity_stage_changes.rb"
Task: "Create migration adding stale_after_days to matias_pipeline_stages in db/migrate/<timestamp>_add_stale_after_days_to_matias_pipeline_stages.rb"
```

## Parallel Example: User Story 2

```bash
Task: "Add stale-after-days numeric input to app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue"
Task: "Add STALE_AFTER_DAYS_LABEL/HELP i18n keys to app/javascript/dashboard/i18n/locale/en/opportunities.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Foundational (T001-T005)
2. Complete Phase 2: User Story 1 (T006-T007)
3. **STOP and VALIDATE**: run quickstart.md Scenarios 1 & 2
4. This alone delivers the spec's primary, directly-visible value (SC-001)

### Incremental Delivery

1. Foundational → transition history recording works
2. + User Story 1 → dwell-time badge visible (MVP!)
3. + User Story 2 → staleness threshold configurable (no visible board change yet)
4. + User Story 3 → alert styling makes the threshold from US2 visible on the board
5. + Polish → lint/rubocop clean, full quickstart re-verified

### Task Count Summary

- Foundational: 5 tasks (T001-T005)
- User Story 1 (P1): 2 tasks (T006-T007)
- User Story 2 (P2): 3 tasks (T008-T010)
- User Story 3 (P3): 1 task (T011)
- Polish: 2 tasks (T012-T013)
- **Total**: 13 tasks
