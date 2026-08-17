# Implementation Plan: Kanban Drag Undo Toast

**Branch**: `041-kanban-drag-undo-toast` | **Date**: 2026-08-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/041-kanban-drag-undo-toast/spec.md`

## Summary

Implement an undo confirmation toast system for the Kanban board in the Opportunities module. When an open card is moved to another pipeline stage or dropped into the Won/Lost terminal status zones without interruption, a lightweight toast appears at the bottom of the board with an "Undo" action. The feature is 100% frontend, encapsulating state, 5-second countdowns, hover-pause/resume, and a 3-item FIFO cap inside a dedicated composable (`useKanbanUndoStack.js`) and UI component (`KanbanUndoToast.vue`). Card reversals reuse existing Vuex actions (`opportunities/moveCard` with `fromIndex` spatial tracking, and `opportunities/setStatus` restoring `status: 'open'`) with zero backend modifications.

## Technical Context

**Language/Version**: JavaScript (ES2022+), Vue 3 (Composition API `<script setup>`)  
**Primary Dependencies**: Vuex, vuedraggable, Tailwind CSS  
**Storage**: N/A (Pure frontend ephemeral state)  
**Testing**: Vitest (`app/javascript/dashboard/components-next/Opportunities/composables/specs/`)  
**Target Platform**: Linux containerized web environment (Docker/Podman)  
**Project Type**: Full-stack web application feature (custom frontend components)  
**Performance Goals**: Toast appearance < 50ms post-move, zero timer drift on pause/resume  
**Constraints**: Zero edits to core (`app/`) or `enterprise/` backend files; 100% Tailwind utility styling (no scoped/custom CSS); dual `en` and `pt_BR` i18n  
**Scale/Scope**: Up to 3 stacked undo toasts simultaneously visible on the active Kanban board  

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|---|---|---|
| **I. Upstream Compatibility First** | All additions are isolated in `components-next/Opportunities/` and local i18n files. Zero backend edits and zero upstream core/enterprise hard forks. | **PASS** |
| **II. Smallest Production-Ready Change** | Reuses existing `moveCard` and `setStatus` actions without introducing new backend endpoints or state machines. Minimal dedicated composable and toast component. | **PASS** |
| **III. Adhere to Established Conventions** | Follows ESLint rules, Tailwind utility tokens, `<script setup>` Composition API, and synchronous `en`/`pt-BR` localizations. | **PASS** |
| **IV. Safe, Reversible Change Management** | Purely frontend additions that can be toggled or reverted cleanly with zero database impact. | **PASS** |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | Frontend addition within the decoupled Kanban module; 100% compatible across OSS and Enterprise. | **PASS** |

## Project Structure

### Documentation (this feature)

```text
specs/041-kanban-drag-undo-toast/
├── plan.md              # Implementation Plan
├── research.md          # Phase 0 decisions & architecture
├── data-model.md        # Phase 1 ephemeral data structures
├── quickstart.md        # Phase 1 validation scenarios
├── contracts/           # Phase 1 component and composable contracts
│   └── component-contracts.md
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── spec.md              # Feature specification
```

### Source Code Layout

```text
# Frontend Components & Composables
app/javascript/dashboard/
├── components-next/Opportunities/
│   ├── KanbanBoard.vue                                     # Captures move completion, pushes toasts, handles undo
│   ├── KanbanColumn.vue                                    # Threads fromIndex on cardRemoved emit
│   ├── KanbanUndoToast.vue                                 # Toast stack UI component
│   └── composables/
│       ├── useKanbanUndoStack.js                           # Composable managing stack, timers, pause/resume
│       └── specs/
│           └── useKanbanUndoStack.spec.js                  # Vitest unit tests for composable
└── i18n/locale/
    ├── en/
    │   └── opportunities.json                              # English undo translations
    └── pt_BR/
        └── opportunities.json                              # Brazilian Portuguese undo translations
```

**Structure Decision**: Clean frontend isolation within `components-next/Opportunities/`, with dedicated composable and unit tests, requiring zero backend edits.

## Complexity Tracking

*No constitutional violations identified. Design adheres strictly to the decoupled extension model.*
