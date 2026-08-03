# Phase 1 Data Model: Drag-to-Close Status Bar

This feature introduces **no new entities, fields, or state transitions**. It changes only how an existing state transition is triggered by the user.

## Existing entity referenced: Opportunity

| Field | Type | Notes |
|---|---|---|
| `status` | enum: `open` \| `won` \| `lost` | Already exists on `custom/app/models/opportunity.rb`. This feature changes the UI trigger for `open → won` and `open → lost` transitions (drag-to-drop instead of a button click); it does not add new values or change validation rules. |
| `pipeline_stage_id` | reference | Unaffected by a status-only change — per FR-005, the card's lane never changes as a result of this interaction. |

## Existing transition rules (unchanged, reused)

- `open → won` / `open → lost`: allowed, subject to closing-required-fields validation (`010-closing-required-fields`) if configured for the account. Already enforced server-side and surfaced client-side via the existing `onStatusChanged` 422 handling in `KanbanBoard.vue`.
- `won|lost → open` (reopen): allowed, unguarded by closing requirements (per `010-closing-required-fields` User Story 3) — remains a direct button click, not part of this feature's drag interaction.

## New transient UI state (not persisted)

| State | Owner | Purpose |
|---|---|---|
| `isCardDragging` | `KanbanBoard.vue` (local ref) | Controls whether `KanbanStatusBar.vue` (and its "Won"/"Lost" drop zones) is rendered. True only between a card drag's `start` and `end` events. |

No Vuex store schema changes, no database migration, no API request/response shape changes.
