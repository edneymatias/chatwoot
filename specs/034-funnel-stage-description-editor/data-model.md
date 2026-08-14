# Data Model: Funnel Stage Rich Description & Kanban Info Panel

**Feature**: `034-funnel-stage-description-editor` | **Date**: 2026-08-14

## Entity: Pipeline Stage (`PipelineStage`, table `ichatr_pipeline_stages`)

Existing entity; this feature adds one field.

| Field | Type | Notes |
|---|---|---|
| `description` (new) | `text`, nullable | Sanitized HTML fragment produced by the stage description rich-text editor. `NULL`/empty/whitespace-only is treated as "no description" (per Edge Cases and FR-011). A structurally-empty editor document (e.g. Tiptap's `<p></p>` for an untouched/cleared editor) MUST be normalized to `null`/`''` at save time — see research.md R3a — rather than stored as non-blank markup, so this simple string-blankness rule holds true for every value actually persisted. No new DB-level validation is required beyond the existing model validations — the field is optional. |

All other existing fields (`name`, `position`, `requires_deal_value`, `total_display_mode`,
`accent_color`, `stale_after_days`, timestamps, `account_id`) are unchanged by this feature.

### Validation rules

- No presence/format validation on `description` at the model level — an empty/blank description
  is valid (FR-003, Edge Cases: whitespace-only treated as empty).
- No new uniqueness or state-transition rules; `description` is a plain descriptive attribute, not
  involved in the stage's `position`/`reorder_to!` or `requires_deal_value` exclusivity logic.

### Relationships

Unchanged — `description` is a scalar attribute on the existing `PipelineStage` record, not a new
association. No new tables.

### Serialization

`description` is included automatically by the controller's existing `render json: @pipeline_stage`
calls (default ActiveRecord `as_json`, already returns all columns) in `index`, `create`, and
`update` — no serializer changes required.
