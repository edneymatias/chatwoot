# Phase 0 Research: Drag-to-Close Status Bar

No `NEEDS CLARIFICATION` markers remain in the Technical Context — this feature is small and scoped enough that the open questions were resolved directly during `/speckit-specify` (see spec.md Assumptions). The research below documents the resulting implementation-approach decisions for the one genuinely open technical question: how to make an existing SortableJS/`vuedraggable` card list also drop onto a non-list target without moving the card into a real array.

## Decision: Reuse the existing `vuedraggable` "kanban-cards" group for the drop zones

**Rationale**: `KanbanColumn.vue` already drives card movement between pipeline lanes via `vuedraggable` (`group="kanban-cards"`), and `KanbanBoard.vue` already has a working `onStatusChanged`/`setStatus` path (including the 422 `missing_required_fields` handling from the closing-required-fields feature). Adding the "Won"/"Lost" zones as two more drop targets in the *same* SortableJS group lets a card be picked up once and dropped either on another lane (existing stage-move behavior, unchanged) or on a zone (new status-change behavior) — a single, consistent drag session rather than two competing drag systems.

To avoid the card actually being spliced into a "Won" or "Lost" list (which would require reverting an array mutation and risks flicker), the zones use SortableJS's `move` guard (exposed by `vuedraggable`) to reject the array mutation while still allowing the `end` event to report which zone the pointer was released over. On a valid `end` over a zone, the component emits `status-changed` with the outcome and never touches `idsByStage`; on drop elsewhere, nothing is emitted and existing behavior (stage move or no-op) proceeds normally.

**Alternatives considered**:
- **Plain native HTML5 drag-and-drop (`dragover`/`drop`) events on separate target elements**: rejected — the card's drag origin is already a SortableJS-managed drag (started by `vuedraggable` in the column), and mixing a second, independent drag protocol on the same pointer session is unreliable (SortableJS captures the drag lifecycle) and would duplicate ghost/preview rendering logic that SortableJS already provides.
- **A dedicated Vuex "dragState" module**: rejected as unnecessary — the status bar's visibility only needs a local `ref` toggled by the drag start/end events already emitted by the SortableJS instance, propagated up through `KanbanColumn` → `KanbanBoard`. No cross-component or persisted state is required (constitution Principle II — smallest production-ready change).

## Decision: Status bar visibility is driven by drag start/end events, not a global store flag

**Rationale**: `vuedraggable` (SortableJS) already exposes `start`/`end` lifecycle events on the draggable list. `KanbanColumn.vue` can forward these as `drag-start`/`drag-end` emits to `KanbanBoard.vue`, which flips a local `isCardDragging` ref controlling whether `KanbanStatusBar.vue` renders. This keeps the state local to the component tree that needs it and avoids introducing global UI state for a purely presentational concern.

**Alternatives considered**: A Vuex UI flag (`ui/isDraggingCard`) was considered for consistency with other UI-flag patterns in the codebase, but rejected since nothing outside `KanbanBoard.vue`'s subtree needs this state — a local ref is simpler and satisfies Principle II.

## Decision: No new backend endpoint or contract

**Rationale**: The drop-to-close interaction ends up calling the same `opportunities/setStatus` action (`PATCH` to the existing opportunities update endpoint with `{ status }`), which already round-trips through the closing-required-fields validation (422 + `missing_required_fields`) introduced by the `010-closing-required-fields` feature. No request/response shape changes.

**Alternatives considered**: N/A — reusing the existing contract is the only option consistent with "smallest production-ready change" and avoids any backend work for what is a client-side interaction change.
