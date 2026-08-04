# Phase 11: Stage Dwell-Time Tracking

**Depends on**: Phase 1 (backend core), Phase 6 (card ordering/fields), Phase 14 (deal card customization — card layout/badge conventions)

## Context

Neither `created_at` nor `updated_at` on `Opportunity` answer "how long has
this lead been in its current stage": `created_at` is total age, not
time-in-current-stage; `updated_at` is bumped on any attribute change, not
just a stage move. No stage-transition tracking exists anywhere in `custom/`
today.

This phase adds that tracking, and is a prerequisite for the funnel report
module (queued right after this phase): the report's most valuable charts
(average time-in-stage, stage-to-stage conversion) need real transition
history, not just a snapshot of the current stage.

There is no production data to preserve — the account this is being built
against has zero opportunities recorded. No backfill/migration-of-existing-data
concern applies.

## Data model

**FR-001**: New table `matias_opportunity_stage_changes`: `account_id`,
`opportunity_id`, `from_stage_id` (nullable — null on the opportunity's
initial transition), `to_stage_id`, `changed_at`. Indexes on
`[opportunity_id, changed_at]` and `[to_stage_id, changed_at]` (the latter
used by the funnel report's per-stage aggregates).

**FR-002**: `Opportunity` gains two callbacks:
- `after_create`, recording an initial transition (`from_stage_id: nil`,
  `to_stage_id: pipeline_stage_id`, `changed_at: created_at`).
- `after_update, if: :pipeline_stage_id_changed?`, recording a transition
  (`from_stage_id: pipeline_stage_id_before_last_save`,
  `to_stage_id: pipeline_stage_id`, `changed_at: Time.current`).

Every opportunity always has at least one transition row, so "time in
current stage" is always `Time.current - opportunity.stage_changes.order(changed_at: :desc).first.changed_at`
with no special-cased nil handling.

**FR-003**: `PipelineStage` gains `stale_after_days` (integer, nullable).
Defaults to `nil` (no alert) both at the DB level and when a new lane is
created — the natural dwell time varies too much per stage (e.g. "Agendado"
may legitimately sit for 1-2 weeks awaiting an appointment date, while
"Tentando contato" should turn over in a day or two), so a single generic
default would be actively misleading. Each stage's threshold is set
explicitly by the account, same pattern as `accent_color` and
`requires_deal_value`.

## Backend API

**FR-004**: `Api::V1::Accounts::PipelineStagesController#pipeline_stage_params`
permits `:stale_after_days` alongside the existing fields. No new endpoints
needed — dwell time itself is derived, not stored/edited directly.

## Frontend

**FR-005**: `EditPipelineStage.vue` gains a numeric input for
"stale after N days" (empty = no alert), in the same settings block as
`requires_deal_value`, `total_display_mode`, and `accent_color`.

**FR-006**: `KanbanCard.vue` shows a small badge with the time in the
current stage (e.g. "há 5 dias", pluralized via i18n). When the stage's
`stale_after_days` is set and exceeded, the badge switches from its neutral
style to an alert style (amber/red), reusing the existing badge color
tokens already used for status.

## Out of scope

- The funnel report itself (separate phase, consumes this table's data).
- Backfill/migration of historical stage data (no existing opportunities).
- Configuring dwell-time alerts anywhere other than the Kanban card (no
  notifications, no digest emails).
