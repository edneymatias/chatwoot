# Quickstart & Validation: Kanban Drag Undo Toast

**Feature Branch**: `041-kanban-drag-undo-toast`  
**Date**: 2026-08-17  
**Spec**: [spec.md](./spec.md)

## Validation Prerequisites

1. Running local container environment (`docker compose up -d`).
2. Kanban board with opportunities seeded across multiple stages (`http://localhost:3000/app/accounts/1/opportunities`).

---

## Scenario 1: Undoing Stage-to-Stage Drag Moves

1. Open the Kanban board.
2. Drag an opportunity card from Column 1 (e.g. "Leads Recebidos") to Column 2 (e.g. "Tentando Contato") at a specific position (e.g. index 1).
3. **Verify**: An undo toast appears at the bottom of the board: `"Movido para Tentando Contato"` with a `"Desfazer"` link.
4. Click `"Desfazer"` within 5 seconds.
5. **Verify**:
   - The toast disappears immediately.
   - The card is moved back to "Leads Recebidos" at its exact original position (index 1).

---

## Scenario 2: Undoing Won / Lost Terminal Status Drop

1. Drag an open opportunity card down to the bottom status bar and drop it onto **"Ganha"** (or **"Perdida"**).
2. **Verify**: The card is updated and an undo toast appears: `"Marcado como Ganha"` (or `"Marcado como Perdida"`) with a `"Desfazer"` link.
3. Click `"Desfazer"`.
4. **Verify**:
   - The opportunity status returns to `"open"`.
   - The card remains in its current pipeline stage as an open card.

---

## Scenario 3: Hover Pause & Precise Timer Resume

1. Drag a card between two stages to trigger an undo toast (5-second countdown).
2. After ~2 seconds, place the mouse cursor directly over the toast pill.
3. Keep the cursor hovering for 10 seconds.
4. **Verify**: The toast does NOT disappear while hovered.
5. Move the cursor away from the toast.
6. **Verify**: The toast stays visible for the remaining ~3 seconds and then disappears automatically.

---

## Scenario 4: 3-Item Capacity & Oldest Eviction

1. Perform 4 rapid drag-and-drop card moves in quick succession (within 2 seconds).
2. **Verify**:
   - Exactly 3 toast items are visible in the stack.
   - The oldest toast (from move 1) was evicted to make room for move 4.

---

## Scenario 5: Required Fields Modal Exemption

1. Drag a card to a stage that has configured required custom fields (or drop onto Won with required closing fields).
2. When the required fields modal opens, click **"Cancelar"**.
3. **Verify**: The card snaps back to its original column and **no** undo toast is emitted.

---

## Automated Test Suites

```bash
# Frontend Unit Tests for Composable and Board
docker compose exec vite pnpm test app/javascript/dashboard/components-next/Opportunities/composables/specs/useKanbanUndoStack.spec.js

# Frontend Lint
docker compose exec vite pnpm eslint
```
