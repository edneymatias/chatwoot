# Research & Decisions: Kanban Drag Undo Toast

**Feature Branch**: `041-kanban-drag-undo-toast`  
**Date**: 2026-08-17  
**Spec**: [spec.md](./spec.md)

## 1. Technical Choices & Architecture Decisions

### Decision 1: Composable-Driven State Management (`useKanbanUndoStack.js`)

- **Decision**: Encapsulate the undo stack, timers, maximum item capacity (3), and pause/resume logic in a dedicated Vue 3 composable (`useKanbanUndoStack.js`) inside `app/javascript/dashboard/components-next/Opportunities/composables/`.
- **Rationale**: 
  - Separates time-management logic (FIFO queue, `setTimeout`, `remainingTime` delta calculations on hover) from presentation (`KanbanUndoToast.vue`) and board interaction (`KanbanBoard.vue`).
  - Keeps the composable 100% unit-testable in isolation using Vitest fake timers without mounting the full board.
  - Follows the established composable architecture pattern in `dashboard/components-next/Opportunities/composables/`.
- **Alternatives Considered**:
  - *Vuex store module*: Rejected because undo state is ephemeral, strictly local to the active Kanban board view, and does not require global cross-view persistence.
  - *Internal state inside KanbanUndoToast.vue*: Rejected because `KanbanBoard.vue` needs to push actions directly upon action completion without complex template refs or event bubbling.

### Decision 2: Spatial Index Threading for Column Reversal

- **Decision**: Capture `fromIndex` from vuedraggable's `removed.oldIndex` inside `KanbanColumn.vue`'s `onChange` handler and thread it through the `cardRemoved` event to `KanbanBoard.vue`'s `pendingMove` state.
- **Rationale**:
  - When moving a card between stages, `opportunities/moveCard` accepts `toIndex` to preserve or set the exact card rank in the destination column.
  - Reversing the move requires knowing both the origin `fromStageId` and `fromIndex` so the card returns to its exact previous position in the column rather than dropping to the end.
  - `vuedraggable` emits `event.removed.oldIndex` automatically when a card leaves a column.
- **Alternatives Considered**:
  - *Defaulting to index 0 on undo*: Rejected because it changes the user's prior ordering within the original column.

### Decision 3: Won/Lost Terminal Status Reversal

- **Decision**: Reversing a drop on the `KanbanStatusBar` (Won/Lost) re-dispatches `opportunities/setStatus` with `status: 'open'`.
- **Rationale**:
  - Only open cards can be dragged on the Kanban board (draggable filter excludes `.is-closed`).
  - Therefore, any card dropped onto Won or Lost was previously in the `open` status.
  - Reopening the opportunity via `setStatus({ id, status: 'open' })` restores the opportunity to its active state while preserving its current pipeline stage.

### Decision 4: Non-Colliding Bottom Toast Placement, Hover Pause & Accessibility

- **Decision**: Position `KanbanUndoToast.vue` in `absolute inset-x-0 bottom-4 pointer-events-none` with individual toasts having `pointer-events-auto`, ARIA live region (`role="status"`, `aria-live="polite"`), and wall-clock drift-free timer tracking.
- **Rationale**: 
  - `KanbanStatusBar.vue` is only rendered while `is-dragging` is active.
  - Undo toasts only appear *after* a drag ends and the move resolves.
  - Thus, the status bar and the undo toast stack never visually overlap or compete for clicks.
  - Hovering over the toast container captures `@mouseenter` to pause all active timers and `@mouseleave` to resume countdowns from their exact remaining milliseconds (`remainingTime = Math.max(0, endTime - Date.now())`).
  - Screen readers are notified via `aria-live="polite"` without interrupting ongoing user focus.

---

## 2. Dependencies & Best Practices

- **Vue 3 Composition API**: `<script setup>`, `ref`, `reactive`, `onBeforeUnmount` cleanup for timeouts.
- **Tailwind CSS Utility Tokens**: `bg-n-solid-2/95`, `backdrop-blur-md`, `border-n-weak`, `rounded-xl`, `shadow-lg`, `text-n-slate-12`.
- **i18n**: Synchronous localized strings under `OPPORTUNITIES.UNDO` in both `en` and `pt_BR`.
