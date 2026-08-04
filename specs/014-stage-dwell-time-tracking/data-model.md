# Phase 1 Data Model: Stage Dwell-Time Tracking

## OpportunityStageChange (new)

**Table**: `matias_opportunity_stage_changes`

Represents a single stage transition for one opportunity. Append-only —
never updated or deleted by application code once written.

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `id` | bigint | no | primary key |
| `account_id` | bigint (FK -> `accounts`) | no | denormalized from opportunity for query/index locality, consistent with sibling `matias_*` tables |
| `opportunity_id` | bigint (FK -> `matias_opportunities`) | no | |
| `from_stage_id` | bigint (FK -> `matias_pipeline_stages`) | yes | null only on an opportunity's very first (creation) transition |
| `to_stage_id` | bigint (FK -> `matias_pipeline_stages`) | no | |
| `changed_at` | datetime | no | when the transition occurred; `created_at` on the opportunity for the initial row, `Time.current` for subsequent moves |
| `created_at` / `updated_at` | datetime | no | standard Rails timestamps |

**Indexes**:
- `[opportunity_id, changed_at]` -- powers "most recent transition for this opportunity" (dwell-time lookup)
- `[to_stage_id, changed_at]` -- powers the funnel report's future per-stage aggregates (out of scope for this phase, but the index is part of this phase's schema per FR-001)

**Relationships**:
- `belongs_to :account`
- `belongs_to :opportunity`
- `belongs_to :from_stage, class_name: 'PipelineStage', optional: true`
- `belongs_to :to_stage, class_name: 'PipelineStage'`

**Validation rules**: `opportunity_id`, `to_stage_id`, `changed_at` required
(`account_id` set automatically from the opportunity, not user-supplied).
No uniqueness constraint -- an opportunity may transition through the same
stage more than once over its lifetime (e.g. moved forward then back).

**Lifecycle**: Rows are created exclusively by two `Opportunity` model
callbacks (see below); never created, updated, or destroyed through any
controller action or API endpoint directly.

**State transitions (of the parent `Opportunity`, captured by this table)**:
1. `Opportunity#create` -> one row: `from_stage_id: nil, to_stage_id: pipeline_stage_id, changed_at: created_at`.
2. `Opportunity#update` where `pipeline_stage_id` changed -> one row:
   `from_stage_id: pipeline_stage_id_before_last_save, to_stage_id: pipeline_stage_id, changed_at: Time.current`.
3. `Opportunity#update` where `pipeline_stage_id` did NOT change -> no row
   written, regardless of what else changed on the record.

## PipelineStage (extended)

**Table**: `matias_pipeline_stages` (existing)

New column:

| Field | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `stale_after_days` | integer | yes | `nil` | Number of days an opportunity may dwell in this stage before its kanban badge switches to the alert style. `nil` = never flagged stale. Set explicitly per stage by the account, same pattern as `accent_color`/`requires_deal_value`/`total_display_mode`. |

New association:
- `has_many :stage_changes_in, class_name: 'OpportunityStageChange', foreign_key: :to_stage_id` — not implemented this phase (no task creates it); documented here as the natural extension point for the future funnel-report phase, which will consume it for per-stage aggregates. This phase's UI reads dwell time off the opportunity side instead.

## Opportunity (extended, no schema change)

No new columns. New derived (non-persisted) concept:

- **time in current stage** = `Time.current - stage_changes.order(changed_at: :desc).first.changed_at`
  Always resolvable with no nil-handling, because every opportunity has at
  least one `OpportunityStageChange` row from the moment it's created (FR-002).

New association:
- `has_many :stage_changes, class_name: 'OpportunityStageChange', dependent: :destroy`
