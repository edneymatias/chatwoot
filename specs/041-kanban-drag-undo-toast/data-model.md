# Data Model: Kanban Drag Undo Toast

**Feature Branch**: `041-kanban-drag-undo-toast`  
**Date**: 2026-08-17  
**Spec**: [spec.md](./spec.md)

## 1. Frontend Ephemeral State Structures

This feature involves purely frontend ephemeral state managed via Vue 3 reactivity in `useKanbanUndoStack.js`. No database migrations or persistent schemas are required.

### `UndoToastItem`

Represents an individual active undo notification in the board stack.

| Field | Type | Description |
|---|---|---|
| `id` | `string` / `number` | Unique identifier generated at creation time (`Date.now() + Math.random()`). |
| `message` | `string` | Localized notification message (e.g. `"Movido para Negociação"` or `"Marcado como Ganha"`). |
| `onUndo` | `Function` | Callback executed when the user clicks "Undo" / "Desfazer". |
| `timeout` | `number` | Total lifetime in milliseconds before auto-dismiss (default: `5000`). |
| `remainingTime` | `number` | Remaining milliseconds of active countdown. Updated upon pause. |
| `startedAt` | `number` | High-precision timestamp (`Date.now()`) when the current countdown period began. |
| `timerId` | `NodeJS.Timeout` / `number` | Reference to the active browser timeout. Cleared on pause, eviction, or undo. |

---

### `UndoStackState`

Maintained within the `useKanbanUndoStack` composable instance.

| Field | Type | Constraints / Default | Description |
|---|---|---|---|
| `toasts` | `Ref<Array<UndoToastItem>>` | Maximum capacity: 3 items (FIFO eviction) | Reactive list of active toast items displayed in the UI. |
| `isPaused` | `Ref<boolean>` | Default: `false` | Tracks whether the user is currently hovering over the toast stack container. |

---

## 2. Event Payload Interfaces

### `cardRemoved` (Emitted by `KanbanColumn.vue`)

Threaded from `vuedraggable`'s `removed` event to `KanbanBoard.vue`.

```typescript
interface CardRemovedPayload {
  opportunity: Opportunity;
  stageId: number;
  fromIndex: number; // captured from event.removed.oldIndex
}
```

### `pendingMove` (Maintained in `KanbanBoard.vue`)

Temporarily stored during a drag interaction before dispatching the move action.

```typescript
interface PendingMove {
  opportunity: Opportunity;
  fromStageId: number;
  fromIndex: number;
}
```
