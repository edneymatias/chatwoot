# Phase 6: Card Info Enrichment & Lane Ordering

**Status**: placeholder — pending brainstorm session

## Quick Preview

Two related, smaller-scope changes to `KanbanCard.vue` and the `opportunities` store/API:

1. **Card content**: add contact avatar, confirm/keep contact name (already present),
   a link to the origin conversation (distinct from the drawer in Phase 5 — likely the
   same click target, needs reconciling), and the opportunity's creation date.
2. **Lane ordering**: newest Opportunity in a lane appears at the top of the column,
   not the bottom. Needs a decision on whether "newest" means `created_at` or
   `updated_at`/last-stage-move, and whether ordering is a backend `ORDER BY` change,
   a frontend sort, or both (interacts with the existing paginated per-stage fetch and
   the optimistic `MOVE_CARD`/`PREPEND_ID_TO_STAGE` mutations).
