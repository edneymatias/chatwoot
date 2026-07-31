# Tasks: Conversation Drawer on Card Click

**Input**: Design documents from `/specs/005-conversation-drawer/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not requested for this feature (no NEEDS CLARIFICATION or explicit test ask in spec.md);
verification is via `pnpm eslint`/`pnpm test` quality gates and the manual `quickstart.md`
scenarios instead of new automated test tasks.

**Organization**: Tasks are grouped by user story (spec.md priorities P1/P2/P2/P3) so each story is
implementable and testable as an increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: User story this task belongs to (US1, US2, US3, US4)
- File paths are given relative to the repository root

## Phase 1: Setup

No new project setup is required — this feature reuses the existing dashboard SPA, its Vuex
`conversations`/`opportunities` modules, and existing components/dependencies. No tasks in this
phase.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Removes the old detail panel and gives the board a mount point for the new drawer.
Must complete before any user story below. Leaves the app in a working state (an empty nested
route outlet renders nothing until US1 adds the route and drawer component).

- [X] T001 Delete `app/javascript/dashboard/components-next/Opportunities/OpportunityDetailView.vue` (FR-010)
- [X] T002 Edit `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`: remove the local `selectedOpportunityId`/`OpportunityDetailView` panel logic and render `<router-view>` in its place, so a future nested `opportunities_conversation` route can render there (depends on T001)

**Checkpoint**: Board renders with no detail panel and no console/build errors; `opportunities_index` still works exactly as before.

---

## Phase 3: User Story 1 - Agent opens the full conversation from a Kanban card (Priority: P1) 🎯 MVP

**Goal**: Clicking a linked card opens a drawer showing the real conversation thread and contact
sidebar, on top of the board, with reply/resolve/assign all working exactly as in the standalone
conversation view (FR-001, FR-002 partial, FR-004, FR-005, FR-006).

**Independent Test**: Click a card with a linked conversation; confirm the drawer opens showing
the message thread and contact sidebar, and that replying, resolving, and assigning all work.
(`quickstart.md` Scenario 1)

### Implementation for User Story 1

- [X] T003 [P] [US1] Create `app/javascript/dashboard/composables/useConversationDrawer.js`: given a `conversationId`, dispatch `getConversation` if not already in `chatList`, watch for the conversation to land in `chatList`, then dispatch `setActiveChat` and `markMessagesRead`; expose a `loading`/`ready` state per data-model.md (error state added in US4); reactively watch `route.params.conversationId` (not just the initial value) so that navigating directly from one linked card's conversation to another while the drawer is already open restarts this sequence from `loading` for the new id (spec.md Edge Case: rapid re-click)
- [X] T004 [US1] Create `app/javascript/dashboard/components-next/Opportunities/OpportunityConversationDrawer.vue`: use `useConversationDrawer.js` and render `ConversationBox` + `ConversationSidebar` (from `dashboard/components/widgets/conversation/`) once state is `ready`, matching how `ConversationView.vue` composes them, with no modifications to either shared component (FR-004) (depends on T003)
- [X] T005 [US1] Add an `opportunities_conversation` route manifest entry to `bin/sync-custom-module-hooks` (anchored inside the already-inserted `opportunities_index` block, path `opportunities/conversations/:conversationId`, component `OpportunityConversationDrawer.vue`), then run the script to apply it to `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` (depends on T004)
- [X] T006 [US1] Edit `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`: when `origin_conversation_id` is present, clicking the card navigates to the `opportunities_conversation` route for that conversation id (depends on T005)

**Checkpoint**: User Story 1 is fully functional and independently testable — `quickstart.md`
Scenario 1 passes end to end.

---

## Phase 4: User Story 2 - Agent recognizes cards with no linked conversation (Priority: P2)

**Goal**: Cards without a linked conversation are visually muted, show no click affordance, and do
nothing when clicked (FR-002 remainder, FR-003).

**Independent Test**: View a board with an opportunity that has no linked conversation; confirm
that card is muted with no hover affordance and clicking it does nothing. (`quickstart.md`
Scenario 2)

### Implementation for User Story 2

- [X] T007 [US2] Edit `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`: apply reduced opacity (`opacity-60`) and remove hover/click affordance when `origin_conversation_id` is absent, ensuring the click handler from T006 no-ops for these cards; while in this file, fix the pre-existing `defineEmits(['click', 'status-changed'])` vs. `$emit('statusChanged', ...)` naming mismatch (depends on T006, same file)

**Checkpoint**: User Stories 1 and 2 both independently testable; unlinked cards are visually and
functionally inert.

---

## Phase 5: User Story 3 - Agent closes the drawer and returns cleanly to the board (Priority: P2)

**Goal**: Closing the drawer (button or back navigation) returns to the board unchanged and clears
any active-conversation state so it doesn't leak elsewhere in the app (FR-007, FR-009).

**Independent Test**: Open the drawer, close it via the close button, and separately via browser
back navigation; confirm in both cases the board is unchanged and no other part of the app treats
the conversation as active. (`quickstart.md` Scenario 3)

### Implementation for User Story 3

- [X] T008 [P] [US3] Extend `app/javascript/dashboard/composables/useConversationDrawer.js`: dispatch `clearSelectedState` on unmount / route leave, matching `ConversationView.vue`'s `beforeRouteLeave` behavior
- [X] T009 [P] [US3] Edit `app/javascript/dashboard/components-next/Opportunities/OpportunityConversationDrawer.vue`: add a close action that navigates back to the `opportunities_index` route via `router.push`/`router.back()` only — it MUST NOT dispatch any board/opportunities data-fetch action (FR-009)

**Checkpoint**: All of US1-US3 independently testable; closing the drawer (either path) leaves no
residual active-chat state and doesn't touch board data.

---

## Phase 6: User Story 4 - Agent sees a clear error when a linked conversation can't be opened (Priority: P3)

**Goal**: If the conversation can't be loaded (not found, no permission), the drawer shows an
inline error and a close action instead of a blank panel (FR-008).

**Independent Test**: Directly navigate to the drawer's URL for a conversation id that can't be
loaded; confirm an inline error message with a close action appears. (`quickstart.md` Scenario 4)

### Implementation for User Story 4

- [X] T010 [US4] Extend `app/javascript/dashboard/composables/useConversationDrawer.js`: after the fetch settles, if the conversation still isn't present in `chatList`, expose an `error` state instead of `loading`/`ready`
- [X] T011 [US4] Edit `app/javascript/dashboard/components-next/Opportunities/OpportunityConversationDrawer.vue`: render an inline error message and the close action (from T009) when state is `error`, instead of `ConversationBox`/`ConversationSidebar` (depends on T009, T010)

**Checkpoint**: All four user stories independently testable and functioning together.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T012 [P] Run `docker compose exec vite pnpm eslint` and fix any violations across all touched/added files
- [X] T013 [P] Run `docker compose exec vite pnpm test` and fix any failures across all touched/added files
- [X] T014 Run `grep -r "OpportunityDetailView" app/javascript --include="*.vue" --include="*.js"` and confirm no results remain
- [X] T015 Execute all four `quickstart.md` scenarios manually against the running dev stack (`docker compose up -d`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: None — no tasks
- **Foundational (Phase 2)**: No dependencies — start immediately; BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (T001-T002)
- **User Story 2 (Phase 4)**: Depends on User Story 1 (T006, same file `KanbanCard.vue`)
- **User Story 3 (Phase 5)**: Depends on User Story 1 (T003, T004 — extends the same composable/component)
- **User Story 4 (Phase 6)**: Depends on User Story 1 and User Story 3 (T009 — reuses the close action; extends the same composable/component)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### Within Each User Story

- Composable changes before component changes that consume them (T003 → T004; T010 → T011)
- Component changes before the card-click wiring that depends on the route existing (T004 → T005 → T006)

### Parallel Opportunities

- T003 (`useConversationDrawer.js`) has no prior dependency once Foundational is done, so it can
  start in parallel with nothing else in Phase 3 (it's the first task in that phase)
- T008 and T009 (Phase 5) touch different files (composable vs. drawer component) and neither
  depends on the other — run in parallel
- T012 and T013 (Phase 7) are independent quality gates — run in parallel

---

## Parallel Example: User Story 3

```bash
# Launch both User Story 3 tasks together (different files, no dependency between them):
Task: "Extend useConversationDrawer.js to dispatch clearSelectedState on unmount/route leave"
Task: "Add close action to OpportunityConversationDrawer.vue navigating to opportunities_index"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational
2. Complete Phase 3: User Story 1
3. **STOP and VALIDATE**: Run `quickstart.md` Scenario 1 independently
4. This alone delivers the core value: agents can reply/resolve/assign from the board without
   leaving it

### Incremental Delivery

1. Foundational → board has a clean mount point, no detail panel
2. + User Story 1 → drawer opens and works for linked cards (MVP)
3. + User Story 2 → unlinked cards are visually/functionally inert
4. + User Story 3 → closing the drawer is clean and leak-free
5. + User Story 4 → broken conversation links show a clear error instead of a blank panel
6. + Polish → lint/test gates green, dead references removed, full quickstart re-run

### Notes

- [P] tasks touch different files and have no unmet dependency
- Each user story's checkpoint should pass its `quickstart.md` scenario before moving to the next
- Commit after each task or logical group
- Avoid: vague tasks, unnecessary same-file conflicts, cross-story dependencies that break story independence
