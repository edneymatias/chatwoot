# Phase 15: Kanban Lane Visual Improvements

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 1 (backend core — `PipelineStage`), Phase 6 (card
info and ordering)

## Quick Preview

Visual improvements to `KanbanColumn.vue`/the board overall:

- **Color per lane**: `PipelineStage` has no color attribute today —
  needs a new column (migration under `db/migrate/`, no core-file touch)
  plus wiring through the pipeline stage settings UI
  (`AddPipelineStage.vue`/`EditPipelineStage.vue`) and the column header.
- **Total in negotiation per lane**: a running total (value and/or count)
  of open opportunities shown in each lane's column header — likely
  summing `Opportunity.value` for opportunities with `status: open` in
  that stage, scoped to what's currently loaded vs. a dedicated aggregate
  query (`KanbanColumn.vue` paginates cards, so the total probably can't
  just sum what's rendered).

Open questions for the brainstorm: does the lane total need a backend
aggregate endpoint (to avoid depending on pagination state), or is an
approximation from loaded cards acceptable initially? Does lane color
affect anything besides the column header (e.g. the card's left border,
consistent with `requires_deal_value` styling), and does it interact with
the "unmet requirements" grayscale/dashed styling already on
`KanbanCard.vue`?
