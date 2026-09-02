# Phase 1 Data Model: Funnel Search Filters and Live Totals

No new tables or models. This feature only makes existing `Opportunity` columns discoverable
(search/filter) and changes how an existing aggregate endpoint queries/labels its response. One
additive index is introduced.

## Entity: Opportunity (existing — `custom/app/models/opportunity.rb`, table `ichatr_opportunities`)

Fields relevant to this feature (all already exist; verified live against `db/schema.rb:1110-1142`
— no column is added, renamed, or removed by this feature):

| Field | Type | Relevant behavior in this feature |
|---|---|---|
| `title` | `string` | Already searched (`ILIKE`); now also covered by the new trigram index alongside the campaign columns. |
| `campaign_name` | `string` | NEW: searchable (`ILIKE`, trigram-indexed) and filterable (`contains`/`does_not_contain`). |
| `campaign_adset_name` | `string` | NEW: searchable (`ILIKE`, trigram-indexed) and filterable (`contains`/`does_not_contain`). |
| `campaign_ad_name` | `string` | NEW: searchable (`ILIKE`, trigram-indexed) and filterable (`contains`/`does_not_contain`). |
| `campaign_platform` | `string` (free text today, only ever `'facebook'`/`'instagram'`) | NEW: searchable (`ILIKE`, not trigram-indexed — see research.md §1) and filterable (`equal_to`/`not_equal_to` against a fixed 2-option dropdown). |
| `created_at` | `datetime` | NEW: filterable (`is_greater_than`/`is_less_than`/`days_before`) — no backend change, generic column handling already supports it. |
| `updated_at` | `datetime` | NEW: filterable, same as `created_at`. |
| `status` | `integer` enum (`open`/`won`/`lost`) | Unchanged column; now correctly honored by `PipelineStageAggregatesController` (previously hardcoded to `open`). |
| `value` | `decimal` | Unchanged; now summed per the *filtered* scope in aggregates, not an unconditional `open`-only scope. |
| `pipeline_stage_id` | `bigint` (FK) | Unchanged; still the `GROUP BY` key for aggregates. |

**Validation rules**: None added — all fields already have whatever validation the existing
`Opportunity` model defines; this feature adds read-path (search/filter/aggregate) behavior only.

**State transitions**: None added — `status` transitions (open → won/lost) are unchanged; this
feature only makes the aggregate endpoint *responsive* to whichever status is currently selected.

## New Index

| Name | Table | Columns | Type | Excludes |
|---|---|---|---|---|
| `index_ichatr_opportunities_on_title_and_campaign_trgm` | `ichatr_opportunities` | `title`, `campaign_name`, `campaign_adset_name`, `campaign_ad_name` | GIN, `gin_trgm_ops` | `campaign_platform` (low-cardinality, matched via equality filter instead — see research.md §1) |

## Aggregate response shape (`PipelineStageAggregatesController#index`)

**Before** (current live behavior):
```json
[{ "pipeline_stage_id": 1, "open_count": 3, "open_value_sum": 1500.0 }]
```
Always computed with `status: :open` hardcoded; no other request params read.

**After**:
```json
[{ "pipeline_stage_id": 1, "count": 3, "value_sum": 1500.0 }]
```
Computed via `OpportunitiesFilter`, honoring `q`, `payload` (including a `status` filter condition
or `status=all`), and `custom_attributes` — the same params
`Api::V1::Accounts::OpportunitiesController#index` already accepts. `apply_status_filter`'s
existing default (`open` unless `status=all` or a `status` condition is present in `payload`) is
reused as-is, so a request with no status-related param keeps returning open-only totals — the
"no regression to the default view" requirement (spec.md FR-009/SC-004) is satisfied by reuse, not
by new conditional logic.

## Frontend state shape (`store/modules/pipelineStages` — `state.byId[stageId]`)

**Before**: `{ ...stage, open_count, open_value_sum }`

**After**: `{ ...stage, count, value_sum }`

No new state keys beyond the rename — `KanbanColumn.vue` and `OpportunitiesViewBar.vue` both read
directly off this same per-stage object (verified: `stage.open_count`/`stage.open_value_sum` today,
confirmed by Phase 0 research), so the rename is mechanical and exhaustive (both consumers are
covered above; a repo-wide search found no other reader of these two field names).
