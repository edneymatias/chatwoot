# Data Model: Kanban Lane Visual Improvements

## Entity: PipelineStage (extended)

Existing model (`custom/app/models/pipeline_stage.rb`, table `matias_pipeline_stages`) gains two
new columns. No new table.

| Field | Type | Notes |
|---|---|---|
| `total_display_mode` | integer, enum | New. `value_sum: 0` (default), `count: 1`. Admin-configured per stage; controls whether the lane header shows a count or a summed value. |
| `accent_color` | string, nullable | New. No default — `nil`/unset means no header accent. Free-hex string (e.g. `#FF5733`), same trust model as `PipelineCardFieldConfig#color` — accepted as-is from a color-picker UI, no format validation. |

Existing fields (`name`, `description`, `position`, `requires_deal_value`, `account_id`) are
unchanged.

**Validation rules**: None added for the two new columns — `total_display_mode` uses Rails' enum
default-value guarantee (always one of the two known values); `accent_color` has no format
validation, consistent with `PipelineCardFieldConfig#color`'s existing precedent.

**State transitions**: None — both fields are simple admin-editable attributes with no lifecycle.

## Entity: Lane Aggregate (computed, not persisted)

Not a database entity — a computed, request-time result shape returned by the new aggregate
endpoint and merged into each stage's in-memory Vuex state.

| Field | Type | Notes |
|---|---|---|
| `pipeline_stage_id` | integer | Identifies which stage this aggregate belongs to. |
| `open_count` | integer | Count of that stage's `status: open` opportunities. Absent from the response (frontend defaults to `0`) when a stage has no open opportunities. |
| `open_value_sum` | decimal | Sum of `value` across that stage's `status: open` opportunities, excluding `nil` values per standard SQL `SUM` behavior. Absent from the response (frontend defaults to `0`) when a stage has no open opportunities. |

**Relationships**: Computed from `Opportunity` (`custom/app/models/opportunity.rb`, table
`matias_opportunities`) — `status: open` only, grouped by `pipeline_stage_id`. Not stored anywhere;
recomputed fresh on every fetch.

**Frontend representation**: Merged into the existing `pipelineStages` Vuex module's per-stage
entry (`state.byId[stageId]`) as `open_count`/`open_value_sum` fields, alongside the
already-fetched `total_display_mode`/`accent_color` attributes from `PipelineStage`'s own payload.
