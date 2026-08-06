# Data Model: Contact Panel Opportunities Section

No schema changes. This feature only adds a read filter and reuses the existing update path against entities that already exist (`custom/app/models/opportunity.rb`, `matias_opportunities` table). This document describes the entities as consumed by this feature, not new tables/migrations.

## Opportunity

Existing entity, read and updated (not created) by this feature.

| Field | Type | Notes for this feature |
|---|---|---|
| `id` | integer | Used as the edit-dialog's `opportunity-id` prop. |
| `contact_id` | integer, FK → Contact | New read filter dimension (FR-001); not editable by this feature. |
| `title` | string | Shown in list entry and editable in dialog (FR-007, FR-009). |
| `status` | enum: `open` / `won` / `lost` | Determines list badge (FR-007) and whether the dialog shows a stage selector or a reopen action (FR-013). |
| `pipeline_stage_id` | integer, FK → Pipeline Stage | Shown as current stage in list entry (FR-007); editable via dialog when `status == 'open'` (FR-009, FR-010, FR-011). |
| `value` (deal value) | decimal | Always editable in dialog; required only when destination stage requires it (FR-012). |
| `custom_attributes` | jsonb | Editable in dialog; required subset driven by destination stage's field config (FR-009, FR-010). |
| `assignee_id` | integer, FK → User | Persisted together with other fields on save (FR-015); no assignment UI/rule change in this feature (FR-017). |
| `created_at` | datetime | Drives most-recent-first ordering (FR-001, FR-004) and the "creation date" shown per entry (FR-007). |
| `current_stage_entered_at` | datetime | Source for "time spent in current stage" shown per entry (FR-007) — the same field `KanbanCard.vue`'s existing `isStale`/time-in-stage logic already reads (falls back to `created_at` when absent), extracted into `useOpportunityCardFields`. |

**Validation rules (existing, reused as-is)**:
- `validate_forward_stage_move_requirements`: only enforced when `pipeline_stage.position` of the new stage is greater than the current stage's position (a forward move) — satisfies FR-010/FR-011 without any new model code.
- `validate_closing_requirements`: unaffected by this feature; reopening only flips `status` to `open` (FR-014), it does not re-trigger closing validations.
- `missing_required_fields`: existing attr_accessor pattern surfaces 422 details (`custom_attribute_keys`, `requires_value`) — reused unchanged by the dialog's existing error-handling branch.

**State transitions relevant to this feature**:
- `won`/`lost` → `open`: triggered by the reopen action (FR-013, FR-014); a direct `status` update, no stage or other field changes bundled into that specific dispatch.
- `open`, current stage → `open`, new stage: triggered by the dialog's normal save (FR-009), subject to `validate_forward_stage_move_requirements` only for forward moves.

## Contact

Existing entity; unchanged by this feature. Used only as the filter key (`contact_id`) for the new list, and as the source of the currently-open conversation's contact for the panel section (FR-004, FR-005).

## Pipeline Stage

Existing entity; unchanged by this feature. Read to:
- Render the stage `<select>` options in the dialog, sorted by position (mirrors `OpportunityCreateModal.vue`'s use of `pipelineStages/stagesSortedByPosition`).
- Determine `requiredDefs`/`requiresDealValue` for whichever stage is currently selected in the dialog (FR-010, FR-012), via the existing `pipelineStages/stageById` getter and per-stage field configuration already used by the kanban board.
