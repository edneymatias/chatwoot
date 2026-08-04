# Phase 0 Research: Stage Dwell-Time Tracking

No `NEEDS CLARIFICATION` markers remain in the Technical Context — all
technical decisions follow directly from established patterns already in
this fork's `custom/` tree (Phases 1, 6, 12–13). This document records those
decisions for traceability.

## Decision: New table name and ownership

**Decision**: `matias_opportunity_stage_changes`, model `OpportunityStageChange`
under `custom/app/models/`, created via a plain additive Rails migration under
`db/migrate/`.

**Rationale**: Matches the existing `matias_`-prefixed table convention
(`matias_opportunities`, `matias_pipeline_stages`, `matias_pipeline_stage_required_fields`,
etc.) so the table can never collide with a same-named upstream table if
Chatwoot ships this feature natively later (constitution Principle I).
`db/migrate/` is the one constitution-sanctioned exception to "isolate
everything in `custom/`" — infrastructure Rails hard-requires to live in a
fixed shared location — and this migration is purely additive (new table,
new nullable column), so it satisfies that exception's conditions.

**Alternatives considered**: A JSON column of transition history on
`Opportunity` itself — rejected because the funnel report phase (queued
next) needs indexed, queryable per-stage aggregates
(`[to_stage_id, changed_at]`), which a JSON blob can't support efficiently.

## Decision: Recording transitions via ActiveRecord callbacks

**Decision**: `after_create` and `after_update, if: :pipeline_stage_id_changed?`
callbacks directly on the existing `Opportunity` model (`custom/app/models/opportunity.rb`).

**Rationale**: `Opportunity` is already a fork-owned model living entirely in
`custom/` — it is not an upstream/core file, so editing its body directly is
direct ownership, not a coupling risk. The existing model already uses this
same callback pattern (`after_commit :broadcast_opportunity_updated`,
validations via `if: :pipeline_stage_id_changed?`), so this is a consistent
extension rather than a new pattern.

**Alternatives considered**: A service object invoked explicitly by every
call site that changes `pipeline_stage_id` — rejected because it would
require every future call site (including ones not yet written, e.g. bulk
import, API-driven stage moves) to remember to invoke it; a model callback
makes the invariant ("every stage change is recorded") impossible to forget.

## Decision: Dwell time computed at read time, not stored

**Decision**: No `current_stage_entered_at` column on `Opportunity`; "time
in current stage" is always derived as
`Time.current - opportunity.stage_changes.order(changed_at: :desc).first.changed_at`.

**Rationale**: Matches FR-002/FR-004 in the spec — avoids a second source of
truth that could drift from the transition log, and avoids any need to
keep a denormalized column in sync on every transition write.

**Alternatives considered**: Denormalized `current_stage_entered_at` on
`Opportunity` for query performance — rejected as premature; kanban board
opportunity volumes here are small (single account, currently zero
opportunities) and the derived query is a single indexed lookup
(`[opportunity_id, changed_at]`), not a scan.

## Decision: `stale_after_days` on `PipelineStage`, no separate settings model

**Decision**: Single nullable `integer` column `stale_after_days` added
directly to `matias_pipeline_stages`, following the exact pattern of
`accent_color`/`total_display_mode` added in Phase 15.

**Rationale**: `requires_deal_value`, `total_display_mode`, `accent_color`,
and now `stale_after_days` are all simple per-stage scalar settings already
managed the same way (column on `PipelineStage`, permitted in
`pipeline_stage_params`, edited in `EditPipelineStage.vue`'s settings block).
Introducing a separate settings table for one more scalar would be
inconsistent with the established convention and adds a join for no benefit.

**Alternatives considered**: A generic key-value settings table for all
per-stage config — rejected as over-engineering for a single nullable
integer column, and inconsistent with how the three existing per-stage
settings are already modeled.

## Decision: Badge implementation reuses existing time/color primitives

**Decision**: `KanbanCard.vue`'s new dwell-time badge uses the existing
`dynamicTime`/`shortTimestamp` helpers from `shared/helpers/timeHelper.js`
(already used for the card's `created_at` display) and the existing
`n-amber-*` (alert) / neutral `n-slate-*` Tailwind badge tokens already used
elsewhere in the dashboard (e.g. `CallStatusBadge.vue`) and for the status
badge on this same card, rather than introducing new color tokens or a new
relative-time utility.

**Rationale**: Constitution Principle III (Adhere to Established Conventions)
and the spec's explicit instruction to reuse "existing badge color tokens
already used for status."

**Alternatives considered**: A dedicated amber token for the "approaching
staleness" state — out of scope; spec only defines two states (neutral,
alert), not a three-state amber/red escalation.
