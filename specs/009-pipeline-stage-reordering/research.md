# Phase 0 Research: Pipeline Stage Reordering

No `NEEDS CLARIFICATION` markers remain in the Technical Context — this feature reuses an existing endpoint, existing model, and existing settings screen, all already inspected in the current codebase. The items below record the decisions made and why, per the research task format.

## Decision: Renumber siblings server-side on the existing `PATCH .../pipeline_stages/:id` endpoint (no new bulk-reorder endpoint)

**Rationale**: The settings screen (`Index.vue`) already sends `{ id, position: newIndex + 1 }` for the single moved stage on every `vuedraggable` `@change` event (`event.moved`). Extending the existing `PipelineStage` model/controller to renumber affected siblings when `position` changes is the smallest change that fixes the actual bug (FR-001, FR-002) without altering the frontend's interaction contract.

**Alternatives considered**:
- *New bulk `PATCH /pipeline_stages/reorder` endpoint accepting the full ordered ID list*: more robust to certain edge cases, but requires a new controller action, new route, and a frontend rewrite of the drag handler — more surface area than the bug warrants (violates Constitution Principle II, Smallest Production-Ready Change).
- *`acts_as_list` gem*: solves generic list-reordering, but adds a new dependency for a single, already-small model; the manual renumber-in-transaction logic needed here is a handful of lines.

## Decision: Renumbering algorithm — remove-and-reinsert, then resequence 1..N within a transaction

**Rationale**: Given an account's stages ordered by current `position`, remove the moved stage from its old index, reinsert it at the new target index, then reassign `position = index + 1` to every stage in the resulting array. Wrapping the whole read-modify-write in a single transaction (with `lock!`/`FOR UPDATE` on the account's stage rows) guarantees the result is always unique, sequential, and gapless (FR-002, SC-003), including under near-simultaneous reorder requests (edge case: "later save wins, no duplicate positions").

**Alternatives considered**:
- *Only update the moved record's position, leave others untouched*: this is the current (broken) behavior — rejected, it's the bug being fixed.
- *Fractional/sparse positioning (e.g., position = average of neighbors)*: avoids renumbering every sibling on each move, but the spec explicitly calls for "sequential and gapless" (FR-002), and stage lists are small enough that a full resequence per move has no meaningful performance cost — added complexity isn't justified.

## Decision: Reorder response returns the full, freshly-ordered stage list; frontend resyncs its whole collection from it

**Rationale**: FR-003 requires every screen reading pipeline stages (settings list, Kanban board columns) to reflect the persisted order. Since Vuex holds the `pipelineStages` module as shared state, the simplest way to guarantee both consumers see correct data — without a second network round trip — is for the reorder response to include every stage whose position changed (in practice, the full account list), and for the frontend `update` action to replace its full `byId`/`allIds` collection from that payload, the same way `fetch` already does.

**Alternatives considered**:
- *Return only the moved stage, have frontend re-dispatch `fetch` after every drag*: works, but doubles network calls on every single-stage move and reintroduces a race between the optimistic local reorder and the refetch — rejected as unnecessary overhead for a same-payload fix.
- *Return only the moved stage, leave siblings' cached positions stale until next natural `fetch`*: this is what would happen with the smallest possible controller change, but it leaves the Kanban board (in the same SPA session) working from cached-stale `position` values until it's remounted — fails FR-003's "no manual refresh workaround required" success criterion (SC-002).

## Decision: Failure handling — revert the settings screen's local list and show an existing-style alert; no change to Kanban board or other screens

**Rationale**: User Story 3 / FR-006 only requires the *screen where the reorder was attempted* to recover gracefully. The settings `Index.vue` already imports `useAlert`; wrapping the existing `onChange` dispatch in try/catch and, on failure, resetting the local `stages` ref back to `store.getters['pipelineStages/stagesSortedByPosition']` (which was never mutated, since the failed dispatch's `commit` never ran) is sufficient and matches the existing error-handling pattern already used for delete (`onDelete`).

**Alternatives considered**:
- *Optimistic-update-then-rollback with a dedicated "previous order" snapshot ref*: more robust for rapid successive drags, but not needed — the existing `stages` ref is only mutated by `vuedraggable`'s own `v-model`, and resetting it from the (unmutated) store getter after a failed dispatch is sufficient and consistent with the current single-drag-at-a-time UX.
