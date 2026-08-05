# Phase 1 Data Model: Opportunity Attribute Report

No new tables or columns. This feature reads exclusively from existing data:

## Existing entities read (unmodified)

### `Opportunity` (`matias_opportunities`, fork-owned, Phase 1/21)

Relevant existing fields used by this feature:

| Field | Type | Used for |
|---|---|---|
| `status` | enum (`open`/`won`/`lost`) | Splitting open-pipeline aggregates from won/lost counts |
| `value` | numeric | Summing into `total_value` per row |
| `created_at` | datetime | `avg_time_to_close` calculation |
| `closed_at` | datetime, nullable (Phase 21) | Period filter for won/lost counts and `avg_time_to_close` |
| `custom_attributes` | jsonb | Read via `->>'#{attribute_key}'` to determine each opportunity's value for the selected attribute |
| `account_id` | bigint | Account scoping |

No new validations, callbacks, or associations are added to `Opportunity`.

### `CustomAttributeDefinition` (`custom_attribute_definitions`, core, unmodified)

Relevant existing fields:

| Field | Type | Used for |
|---|---|---|
| `id` | bigint | The `custom_attribute_definition_id` request param |
| `attribute_key` | string | The jsonb key read off each opportunity's `custom_attributes` |
| `attribute_model` | enum | Must be `opportunity_attribute` (FR-002/FR-008) |
| `attribute_display_type` | enum | Must be `list` (FR-002/FR-008) |
| `attribute_values` | jsonb array of strings | Defines the row set and row order (FR-006) |
| `attribute_display_name` | string | Shown in the attribute selector and response `definition` block |
| `account_id` | bigint | Ownership check (FR-002) |

No new validations are added to `CustomAttributeDefinition`.

## New response shape (not persisted — computed on demand)

### `AttributeValueRow` (per-value aggregation bucket)

One instance per entry in `definition.attribute_values`, plus exactly one synthetic instance for the "no value" bucket (`value: nil`), always last (FR-006).

| Field | Type | Computation |
|---|---|---|
| `value` | string \| `nil` | The attribute value this row represents; `nil` for the "no value" row |
| `opportunities_count` | integer | Count of `open` opportunities whose `custom_attributes->>'#{attribute_key}'` equals `value` (or is missing/unrecognized, for the `nil` row) — **not period-filtered** (FR-003) |
| `total_value` | decimal | Sum of `value` for the same open-opportunity set — **not period-filtered** (FR-003) |
| `won_count` | integer | Count of `won` opportunities with that attribute value, `closed_at` within the selected period (FR-004) |
| `won_value` | decimal | Sum of `value` for the same won-opportunity set (FR-004) |
| `lost_count` | integer | Count of `lost` opportunities with that attribute value, `closed_at` within the selected period (FR-004) |
| `lost_value` | decimal | Sum of `value` for the same lost-opportunity set (FR-004) |
| `avg_time_to_close` | float (days) \| `nil` | Average `(closed_at - created_at)` over `won` opportunities with that attribute value closed within the period; `nil` when zero such opportunities exist, to distinguish "no data" from "closed instantly" (FR-005) |

### Top-level response envelope

| Field | Type | Notes |
|---|---|---|
| `definition` | object `{ id, attribute_key, attribute_display_name }` | Echoes the selected attribute so the frontend can render the page title/column header without a second lookup |
| `rows` | `AttributeValueRow[]` | Ordered per FR-006: `attribute_values` order, then the "no value" row last |

## Validation rules (request-time, not persisted)

- `custom_attribute_definition_id` MUST resolve to a `CustomAttributeDefinition` belonging to `Current.account` (FR-002).
- That definition MUST have `attribute_model: opportunity_attribute` and `attribute_display_type: list` (FR-002/FR-008); otherwise the request is rejected with a 422 and a clear error body, matching the existing `{ error: "..." }` shape used by sibling kanban controllers (`opportunities_controller.rb`, `pipeline_closing_required_fields_controller.rb`) — no exception/record is persisted or mutated.
