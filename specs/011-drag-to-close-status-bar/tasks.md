# Tasks: Drag-to-Close Status Bar

**Input**: Design documents from `/specs/011-drag-to-close-status-bar/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not requested in the feature spec — per project convention, no new test files are added. Verification is done via the `quickstart.md` manual scenarios and existing lint/test commands.

**Organization**: Tasks are grouped by user story (spec.md) to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Maps task to US1/US2/US3 from spec.md
- File paths are absolute-relative to repo root

## Path Conventions

Single project (existing Chatwoot dashboard SPA): `app/javascript/dashboard/components-next/Opportunities/`, `app/javascript/dashboard/i18n/locale/`

---

## Phase 1: Setup

**Purpose**: Confirm the existing toolchain already covers this feature's needs — no new dependencies or scaffolding required.

- [X] T001 Confirm `vuedraggable` is already a resolved dependency (check `package.json`/`pnpm-lock.yaml`) and review its `move`/`start`/`end` event API before implementation

---

## Phase 2: Foundational

**Purpose**: N/A — this feature has no shared infrastructure to stand up beyond what already exists (the `"kanban-cards"` `vuedraggable` group, the `opportunities/setStatus` Vuex action, and `KanbanBoard.vue`'s existing `onStatusChanged`/`ClosingRequirementsModal` wiring). All of it is reused as-is; no blocking prerequisite tasks are needed before user story work can start.

**Checkpoint**: Proceed directly to Phase 3.

---

## Phase 3: User Story 1 - Closing an opportunity by dragging onto Won or Lost (Priority: P1) 🎯 MVP

**Goal**: Let a user drag an open opportunity card onto a "Won" or "Lost" drop zone that appears during drag, changing its status while it stays in its current lane.

**Independent Test**: Drag an open opportunity card onto the "Won" zone and verify its status updates to "won" while it remains in its current pipeline lane; repeat for "Lost"; verify dropping elsewhere leaves status unchanged.

### Implementation for User Story 1

- [X] T002 [P] [US1] Create `KanbanStatusBar.vue` in `app/javascript/dashboard/components-next/Opportunities/KanbanStatusBar.vue`: renders two drop zones ("Won"/"Lost") sharing the `"kanban-cards"` `vuedraggable` group, uses the `move` guard to reject the array-splice mutation, applies a highlight class while a dragged card is over a zone, and emits `status-changed` with `{ id, status }` on a valid drop (reusing `OPPORTUNITIES.BOARD.STATUS.WON`/`LOST` i18n labels)
- [X] T003 [US1] In `app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue`, forward the `vuedraggable` list's `start`/`end` lifecycle as `drag-start`/`drag-end` emits so the board knows when a card drag is in progress
- [X] T004 [US1] In `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`, add a local `isCardDragging` ref toggled by `KanbanColumn`'s `drag-start`/`drag-end`, render `KanbanStatusBar` only while `isCardDragging` is true, and wire its `status-changed` emit to the existing `onStatusChanged` handler (unchanged — already calls `opportunities/setStatus` and opens `ClosingRequirementsModal` on the 422 `missing_required_fields` response)
- [X] T005 [US1] In `app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue` (or the `vuedraggable` binding for each card), disable dragging for cards whose `opportunity.status` is not `"open"` (e.g. `vuedraggable`'s per-item `:disabled`/`move` predicate) so already-won/lost cards cannot be picked up and dropped on `KanbanStatusBar` (FR-011)
- [X] T006 [US1] Verify manually (Quickstart Scenarios 1–3) that dropping a card on `KanbanStatusBar` never mutates `idsByStage`/the originating `KanbanColumn` list — only a `status-changed` emit occurs; static lint cannot assert this runtime behavior

**Checkpoint**: User Story 1 is fully functional — run Quickstart Scenarios 1–3 and 6 (`specs/011-drag-to-close-status-bar/quickstart.md`) to validate independently.

---

## Phase 4: User Story 2 - Reopening a closed opportunity is unaffected (Priority: P2)

**Goal**: Confirm the existing "reopen" button on won/lost cards keeps working unchanged after the drag-to-close status bar is introduced.

**Independent Test**: On a card that is currently won or lost, click "reopen" and verify status becomes "open" without any drag interaction or status bar involvement.

### Implementation for User Story 2

- [X] T007 [US2] Review `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`'s reopen button (`v-if="opportunity.status !== 'open'"`, emits `statusChanged` with `status: 'open'`) to confirm it is untouched by the US1 changes, then run Quickstart Scenario 4's reopen check (`specs/011-drag-to-close-status-bar/quickstart.md`) to confirm no regression

**Checkpoint**: User Stories 1 and 2 both work independently — reopening remains a direct, non-drag action.

---

## Phase 5: User Story 3 - Won/lost buttons are no longer available on the card (Priority: P2)

**Goal**: Remove the direct "Mark as Won"/"Mark as Lost" buttons from the opportunity card now that the drag-to-close status bar is the supported path.

**Independent Test**: Inspect an open opportunity card's hover actions and verify no "Won"/"Lost" buttons are present, only the remaining actions (reopen when applicable, complete-fields when applicable).

### Implementation for User Story 3

- [X] T008 [US3] In `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, remove the "Mark as Won" and "Mark as Lost" buttons (and their now-unused `MARK_WON`/`MARK_LOST` click handlers) from the Quick Actions Overlay, keeping the "Reopen" and "Complete Fields" buttons intact

**Checkpoint**: All three user stories are complete and independently verifiable — run Quickstart Scenario 4's "buttons are gone" check.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency and validation pass across all stories.

- [X] T009 [P] Remove the now-unused `OPPORTUNITIES.BOARD.ACTIONS.MARK_WON`/`MARK_LOST` i18n keys from `app/javascript/dashboard/i18n/locale/en/opportunities.json` if no longer referenced anywhere else in the codebase (grep before removing)
- [X] T010 Run `docker compose exec vite pnpm eslint` and `docker compose exec vite pnpm test` across the changed files
- [X] T011 Run all 6 scenarios in `specs/011-drag-to-close-status-bar/quickstart.md` end-to-end, including Scenario 5 (closing-required-fields blocking) if a `010-closing-required-fields`-configured account is available, and Scenario 6 (already-closed cards are not draggable, FR-011)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: N/A — nothing blocks user story work
- **User Story 1 (Phase 3)**: Can start after Setup; delivers the MVP
- **User Story 2 (Phase 4)**: Independent of US1's code changes (no shared files), but its validation (T007) is more meaningful once US1 exists so the "no regression" claim covers the new drag path too
- **User Story 3 (Phase 5)**: Touches the same file as no other story (`KanbanCard.vue`'s Quick Actions Overlay is otherwise unmodified by US1/US2) but should ship **after** US1 is deployed, since removing the buttons before the drag replacement exists would leave no way to close an opportunity
- **Polish (Phase 6)**: Depends on Phases 3–5 being complete

### Parallel Opportunities

- T002 (`KanbanStatusBar.vue`) can be built in parallel with T003 (`KanbanColumn.vue` drag events) since they're different files; T004 depends on both. T005 (closed-card drag guard) also touches `KanbanColumn.vue` and can be done alongside T003.
- T008 (US3, `KanbanCard.vue`) can be developed in parallel with US1/US2 by a different contributor, but hold merging/shipping it until US1 (T002–T006) is deployed.
- T009 (i18n cleanup) can run in parallel with T010/T011.

---

## Parallel Example: User Story 1

```bash
# T002 and T003 touch different files and have no dependency on each other:
Task: "Create KanbanStatusBar.vue in app/javascript/dashboard/components-next/Opportunities/KanbanStatusBar.vue"
Task: "Forward drag start/end events in app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue"
# T004 then wires both together in KanbanBoard.vue
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Skip Phase 2 (no foundational work needed)
3. Complete Phase 3: User Story 1 (T002–T006)
4. **STOP and VALIDATE**: Run Quickstart Scenarios 1–3 and 6
5. Demo the drag-to-close interaction — buttons can remain temporarily since US1 doesn't require removing them

### Incremental Delivery

1. Setup → User Story 1 (T002–T006) → validate → this alone already delivers the new interaction (buttons still present as a safety net)
2. User Story 2 (T007) → confirm no regression on reopen
3. User Story 3 (T008) → remove the old buttons now that the drag path is proven
4. Polish (T009–T011) → cleanup and full quickstart pass

---

## Notes

- No tests were requested in the spec; verification relies on `quickstart.md` manual scenarios plus `pnpm eslint`/`pnpm test`.
- All work is frontend-only (`app/javascript/dashboard/components-next/Opportunities/*` and one i18n file) — no backend, migration, or API contract changes, matching `plan.md`.
- Commit after each task or logical group; stop at each phase checkpoint to validate independently.

---

## Phase 7: Convergence

**Purpose**: Address gaps found during convergence check.

- [X] T012 Apply the `.is-closed` class to won and lost cards in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` to ensure the `filter=".is-closed"` in KanbanColumn prevents dragging them per FR-011 (partial)
- [X] T013 Review and finalize the unrequested change in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` that modified the "Complete Fields" button to act as a general "Edit" button for all open opportunities per User Chat Request (unrequested)

---

## Phase 8: Convergence

**Purpose**: Address gaps found during convergence check.

- [X] T014 Address unrequested change in `app/javascript/dashboard/components-next/Opportunities/KanbanStatusBar.vue` that inverted the order of Won/Lost drop zones (Lost on left, Won on right) based on user chat feedback (unrequested)
- [X] T015 Address unrequested change in `app/javascript/dashboard/components-next/Opportunities/KanbanStatusBar.vue` that added base red/green background colors to drop zones prior to hover based on user chat feedback (unrequested)
