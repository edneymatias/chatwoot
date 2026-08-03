# Implementation Plan: Drag-to-Close Status Bar

**Branch**: `011-drag-to-close-status-bar` | **Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-drag-to-close-status-bar/spec.md`

## Summary

Replace the direct "Won"/"Lost" buttons on `KanbanCard.vue` with a drag-to-close interaction: while a card is being dragged, a status bar with two drop zones ("Won"/"Lost") appears; dropping a card on a zone marks it won/lost while it stays in its current pipeline lane. This is a frontend-only change — it reuses the existing `opportunities/setStatus` Vuex action and `onStatusChanged` handler on `KanbanBoard.vue` (already wired for the buttons and already handling the closing-required-fields 422 response), and the existing `vuedraggable`/SortableJS `"kanban-cards"` drag group already used for card-to-column moves. No backend or API contract changes are needed.

## Technical Context

**Language/Version**: Vue 3 (Composition API, `<script setup>`), ES2022 JS

**Primary Dependencies**: `vuedraggable` (SortableJS wrapper, already used in `KanbanColumn.vue`), Vuex (`opportunities` and `pipelineStages` store modules, unchanged)

**Storage**: N/A — no schema or model changes; reuses the existing `status` enum (`open`/`won`/`lost`) on `custom/app/models/opportunity.rb`

**Testing**: `pnpm test` (Vitest) for any component-level assertions; manual verification via `quickstart.md`. Per project convention, no new specs are written unless explicitly requested.

**Target Platform**: Web dashboard SPA (existing Chatwoot fork frontend)

**Project Type**: Web application (single frontend project inside the existing Chatwoot monolith — `app/javascript/dashboard`)

**Performance Goals**: N/A — standard UI responsiveness for a drag interaction; no new network calls beyond the existing `PATCH` used by `setStatus`

**Constraints**: Must reuse the existing `setStatus` action / `status-changed` event chain unchanged (including its 422 `missing_required_fields` handling) rather than introducing a parallel status-update path; must not alter `idsByStage` on a status-only change

**Scale/Scope**: One new Vue component (`KanbanStatusBar.vue`) plus targeted edits to `KanbanCard.vue`, `KanbanColumn.vue`, and `KanbanBoard.vue`; two new i18n label keys at most (existing `STATUS`/`ACTIONS` keys are reused where possible)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. `components-next/Opportunities/*` is a fork-specific feature tree (kanban/opportunities is not part of stock Chatwoot), so these edits don't touch shared upstream files. No core file renames/restructuring.
- **II. Smallest Production-Ready Change**: PASS. No new store actions, no backend/API changes, no new Vuex modules — the plan reuses `setStatus`/`onStatusChanged` as-is and adds only the minimal UI needed for the drop zones.
- **III. Adhere to Established Conventions**: PASS. Composition API + `<script setup>`, Tailwind-only styling, i18n for all labels, PascalCase component names — consistent with sibling components in the same directory.
- **IV. Safe, Reversible Change Management**: PASS. Purely additive/local file edits; no destructive or hard-to-reverse operations involved.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS / N/A. The opportunities/kanban feature lives under `custom/` (this fork's own tree), not `app/`, and has no corresponding `enterprise/` overlay to keep in sync.

No violations — Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/011-drag-to-close-status-bar/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/javascript/dashboard/components-next/Opportunities/
├── KanbanBoard.vue          # MODIFIED — track drag-in-progress state, render KanbanStatusBar, keep onStatusChanged
├── KanbanColumn.vue         # MODIFIED — emit drag start/end so KanbanBoard can show/hide the status bar;
│                             #        disable dragging for already-won/lost cards (FR-011)
├── KanbanCard.vue           # MODIFIED — remove "Mark as Won"/"Mark as Lost" buttons; keep "Reopen"
├── KanbanStatusBar.vue      # NEW — renders the "Won"/"Lost" drop zones, shares the "kanban-cards" drag group,
│                             #        emits `status-changed` on a valid drop without mutating idsByStage
└── ClosingRequirementsModal.vue  # UNCHANGED — already invoked by KanbanBoard.onStatusChanged on 422

app/javascript/dashboard/i18n/locale/en/opportunities.json  # MODIFIED — reuse existing BOARD.STATUS.WON/LOST
                                                              #            labels for the drop-zone text; no backend en.yml changes needed
```

**Structure Decision**: Single-project web frontend change inside the existing Chatwoot dashboard SPA (`app/javascript/dashboard`). No backend, migration, or API surface changes — everything needed (status update endpoint, 422 missing-fields contract) already exists and is reused unmodified. Contracts generation (Phase 1, `/contracts/`) is skipped because no new or changed external interface is introduced.

## Complexity Tracking

*No constitution violations — this section is intentionally empty.*
