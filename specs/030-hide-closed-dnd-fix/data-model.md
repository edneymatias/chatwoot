# Phase 1 Data Model: Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug

No schema changes. This feature only changes the *default query scope* and *drag-target layout*
around the existing `Opportunity` entity — no new fields, tables, or relationships are introduced.

## Opportunity (existing, unchanged shape)

| Attribute | Type | Notes |
|---|---|---|
| `status` | enum (`open`, `won`, `lost`) | Determines default board/list visibility per this feature. Unaffected by drag-and-drop fix except that it's the *only* attribute a won/lost drop should change. |
| `pipeline_stage_id` | reference | Records where in the pipeline the deal currently sits (or last sat, once closed). Must remain unchanged by a won/lost drag-and-drop drop, per FR-006/FR-008. |
| `contact_id` | reference | Used by `fetchForContact` to scope a contact's full opportunity history, independent of the new default. |

## State Transitions

No new state transitions are introduced. The existing `status` transitions (`open → won`,
`open → lost`) already exist via `opportunities/setStatus`; this feature only guards that a
transition triggered by drag-and-drop cannot be accompanied by an unintended, simultaneous
`pipeline_stage_id` change (previously possible due to the drag-and-drop bug described in
[research.md](./research.md#decision-3-drag-and-drop-layout-fix-approach)).

```text
        (existing, unchanged)
  open ───────────────► won
   │
   └──────────────────► lost

  pipeline_stage_id: changes only via explicit column-to-column drag or edit,
                      NEVER as a side effect of a status-only (won/lost) drop.
```

## Query Scope (new default, not a schema change)

| Context | Status scope applied |
|---|---|
| Kanban board / List view, no filter | `open` only (new default) |
| Kanban board / List view, `status=all` or explicit status filter | as requested (existing behavior, unchanged) |
| Contact profile opportunity history panel (`fetchForContact`) | `all` (explicit override, new) |
