# Phase 37: Bulk Actions for Opportunities

**Status**: placeholder — pending brainstorm session

**Depends on**: Phase 8 (List View), the most natural surface for row selection; may also apply
to the Kanban board's cards.

## Quick Preview

Select multiple opportunities and act on them at once — likely from the list view, where rows are
already a natural unit to check off. Needs design for: which actions are supported (bulk stage
change, bulk assignee change, bulk delete, bulk status/won-lost), whether selection is list-view
only or also available on Kanban cards, how bulk stage/status changes interact with the existing
per-opportunity validation (required custom attributes, deal value requirements enforced via
`StageTransitionRequirementsModal.vue`/`ClosingRequirementsModal.vue`) when applied to many
opportunities that may not all satisfy the same requirements, and what feedback is shown for
partial failures (e.g. 8 of 10 succeed).
