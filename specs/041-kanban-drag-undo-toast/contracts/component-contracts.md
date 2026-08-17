# Component Contracts: Kanban Drag Undo Toast

**Feature Branch**: `041-kanban-drag-undo-toast`  
**Date**: 2026-08-17  
**Spec**: [spec.md](../spec.md)

## 1. Composable Contract: `useKanbanUndoStack.js`

**File**: `app/javascript/dashboard/components-next/Opportunities/composables/useKanbanUndoStack.js`

### Methods & Properties

```javascript
export function useKanbanUndoStack() {
  /**
   * Reactive array of active undo toast objects (max length 3).
   * @type {import('vue').Ref<Array<UndoToastItem>>}
   */
  const toasts = ref([]);

  /**
   * Push a new undoable action onto the stack.
   * If stack already has 3 items, the oldest item is dismissed immediately.
   * 
   * @param {Object} options
   * @param {string} options.message - Localized message to display.
   * @param {Function} options.onUndo - Reversal callback to execute when clicked.
   * @param {number} [options.timeout=5000] - Duration in ms before auto-dismissal.
   * @returns {string|number} - The assigned toast ID.
   */
  function pushToast({ message, onUndo, timeout = 5000 });

  /**
   * Executes the onUndo callback for the given toast ID and removes it from the stack.
   * @param {string|number} id
   */
  function undoToast(id);

  /**
   * Dismisses a toast without executing its undo callback.
   * @param {string|number} id
   */
  function dismissToast(id);

  /**
   * Pauses countdown timers for all active toasts in the stack (triggered on cursor hover).
   */
  function pauseAll();

  /**
   * Resumes countdown timers for all active toasts from their remaining duration (triggered on cursor leave).
   */
  function resumeAll();

  /**
   * Clears all active toasts and cancels all timeouts (e.g. on component unmount).
   */
  function clearAll();

  return {
    toasts,
    pushToast,
    undoToast,
    dismissToast,
    pauseAll,
    resumeAll,
    clearAll,
  };
}
```

---

## 2. Vue Component Contract: `KanbanUndoToast.vue`

**File**: `app/javascript/dashboard/components-next/Opportunities/KanbanUndoToast.vue`

### Props

| Prop | Type | Required | Description |
|---|---|---|---|
| `toasts` | `Array` | Yes | List of active toast items to render. |

### Emits

| Event | Payload | Description |
|---|---|---|
| `undo` | `id: string \| number` | Triggered when the user clicks the "Undo" / "Desfazer" action button on a toast. |
| `dismiss` | `id: string \| number` | Triggered if an individual toast is closed or dismissed. |
| `pause` | None | Triggered on `@mouseenter` of the toast stack container to pause timers. |
| `resume` | None | Triggered on `@mouseleave` of the toast stack container to resume timers. |

### Template Structure & Classes

- Outer Container: `fixed` or `absolute inset-x-0 bottom-4 flex flex-col items-center gap-2 pointer-events-none z-30` with `role="status"` and `aria-live="polite"`
- Toast Pill: `pointer-events-auto flex items-center justify-between gap-4 px-4 py-2 bg-n-solid-2/95 dark:bg-n-solid-2/90 backdrop-blur-md border border-n-weak rounded-xl shadow-lg text-n-slate-12 text-sm transition-all duration-200`
- Message: `font-medium truncate max-w-xs`
- Action Button: `<button type="button">` with `text-n-brand hover:underline font-semibold text-sm cursor-pointer`

---

## 3. Localization Contracts (`opportunities.json`)

### English (`app/javascript/dashboard/i18n/locale/en/opportunities.json`)

```json
{
  "OPPORTUNITIES": {
    "UNDO": {
      "MOVED_TO_STAGE": "Moved to {stage}",
      "MARKED_AS_WON": "Marked as Won",
      "MARKED_AS_LOST": "Marked as Lost",
      "ACTION": "Undo"
    }
  }
}
```

### Brazilian Portuguese (`app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`)

```json
{
  "OPPORTUNITIES": {
    "UNDO": {
      "MOVED_TO_STAGE": "Movido para {stage}",
      "MARKED_AS_WON": "Marcado como Ganha",
      "MARKED_AS_LOST": "Marcado como Perdida",
      "ACTION": "Desfazer"
    }
  }
}
```
