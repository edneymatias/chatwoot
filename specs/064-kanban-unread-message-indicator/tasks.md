# Tasks: Kanban Unread Message Indicator (Post-Handoff Only)

**Input**: Design documents from `/specs/064-kanban-unread-message-indicator/`

**Prerequisites**: [plan.md](./plan.md) (required), [spec.md](./spec.md) (required for user stories), [research.md](./research.md), [data-model.md](./data-model.md), [quickstart.md](./quickstart.md)

**Tests**: Unit and component tests are included per plan.md and quickstart.md specifications.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

- **Backend (custom domain & concerns)**: `custom/app/models/`, `custom/spec/`
- **Backend (models & specs)**: `spec/models/`
- **Frontend (Vue & specs)**: `app/javascript/dashboard/components-next/Opportunities/`
- **Translations (i18n)**: `app/javascript/dashboard/i18n/locale/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify development test environment and container health

- [X] T001 Verify existing test environment and container health by running `docker compose exec vite pnpm test -- KanbanCard` and `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/concerns/conversation_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core method renaming and generalization that MUST be complete before User Stories 2-4 (which add new callers of the renamed broadcast method)

**⚠️ CRITICAL**: Blocks US2-US4. US1 (T003-T007) does not call the renamed broadcast method and has no hard dependency on this phase, but completing it first avoids two parallel method names existing simultaneously.

- [X] T002 Rename and generalize broadcast methods across models: Rename `Opportunity#broadcast_scout_badge_refresh` to `broadcast_kanban_badges_refresh` in `custom/app/models/opportunity.rb` and rename `refresh_linked_opportunities_scout_badge` to `refresh_linked_opportunities_kanban_badges` in `custom/app/models/custom/concerns/conversation.rb`, updating existing spec references in `custom/spec/models/custom/concerns/conversation_spec.rb`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - See which handed-off opportunities have new customer replies (Priority: P1) 🎯 MVP

**Goal**: Surface an unread message indicator dot on Kanban cards only for opportunities owned by a human (`!scout_engaged?`) when `active_conversation` has unread incoming customer messages.

**Independent Test**: Open the Kanban board with a mix of cards (Scout-engaged, handed-off with unread, non-Scout with unread, and read) and confirm the unread dot appears ONLY on human-owned cards with unread incoming messages.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T003 [P] [US1] Add unit tests for `Opportunity#has_unread_messages?` and `Opportunity#as_json` verifying `!scout_engaged? && active_conversation&.unread_incoming_messages&.any?` (returns true when scout is not engaged and active_conversation has an unread incoming message; returns false when `scout_engaged?` is true regardless of unread messages; returns false when messages are only private notes; returns false when active_conversation is nil) in `spec/models/opportunity_spec.rb`
- [X] T004 [P] [US1] Add component tests for unread indicator rendering when `opportunity.has_unread_messages` is true and omitting when false/undefined in `app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js`; also assert the existing "Scout" badge test cases still pass unmodified and that no count/number is rendered alongside the dot

### Implementation for User Story 1

- [X] T005 [P] [US1] Add `OPPORTUNITIES.BOARD.UNREAD_TOOLTIP` key to English and Portuguese translations in `app/javascript/dashboard/i18n/locale/en/opportunities.json` and `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`
- [X] T006 [P] [US1] Implement derived boolean `has_unread_messages?` honoring the constraint `!scout_engaged? && active_conversation&.unread_incoming_messages&.any?` (default `false` when no `active_conversation`) and include `'has_unread_messages' => has_unread_messages?` in `as_json` in `custom/app/models/opportunity.rb`
- [X] T007 [US1] Add pulsing unread indicator dot element (`animate-pulse [animation-duration:3s]`) with tooltip in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`

**Checkpoint**: User Story 1 should be fully functional and testable independently (MVP ready)

---

## Phase 4: User Story 2 - Indicator clears in real time once the conversation is read (Priority: P2)

**Goal**: Clear the unread indicator dot in real time without a page reload when an agent reads the linked conversation (updating `agent_last_seen_at`).

**Independent Test**: Mark a flagged conversation as read; confirm indicator dot disappears from the Kanban card within 5 seconds without reloading the board.

### Tests for User Story 2 ⚠️

- [X] T008 [P] [US2] Add unit specs asserting `Conversation#agent_last_seen_at` updates trigger `ActionCableBroadcastJob` with updated `has_unread_messages: false` payload for linked opportunities in `custom/spec/models/custom/concerns/conversation_spec.rb`

### Implementation for User Story 2

- [X] T009 [US2] Widen `after_commit` hook condition on `:update` to `saved_change_to_status? || saved_change_to_agent_last_seen_at?` calling `refresh_linked_opportunities_kanban_badges` in `custom/app/models/custom/concerns/conversation.rb`

**Checkpoint**: User Story 2 functional - indicator clears in real time when read

---

## Phase 5: User Story 3 - Indicator appears the moment a handed-off conversation gets a new message (Priority: P2)

**Goal**: Surface the unread indicator dot on the Kanban card in real time without reload when a customer sends a new incoming message to an already-handed-off conversation.

**Independent Test**: Send a new incoming message to a handed-off conversation with the board visible; confirm the unread dot appears on its Kanban card within 5 seconds without reloading.

### Tests for User Story 3 ⚠️

- [X] T010 [P] [US3] Add unit specs for `Custom::Concerns::Message` verifying incoming non-private messages trigger broadcasts for linked opportunities, while outgoing and private messages do not, in `custom/spec/models/custom/concerns/message_spec.rb`

### Implementation for User Story 3

- [X] T011 [US3] Create `Custom::Concerns::Message` concern adding `after_commit` on `:create` with condition `incoming? && !private?` calling `refresh_linked_opportunities_kanban_badges` for all linked opportunities in `custom/app/models/custom/concerns/message.rb`

**Checkpoint**: User Story 3 functional - incoming messages trigger real-time dot appearance

---

## Phase 6: User Story 4 - Indicator turns off automatically if Scout re-engages (Priority: P3)

**Goal**: Automatically turn off the unread indicator in real time if Scout re-engages on the conversation (e.g. status reverts to pending on a Scout-enabled inbox), even if unread messages remain.

**Independent Test**: Revert a conversation's status to pending on a Scout-enabled inbox while unread messages exist; confirm the unread dot disappears and the Scout badge appears within 5 seconds without reload.

### Tests & Verification for User Story 4 ⚠️

- [X] T012 [P] [US4] Add unit specs verifying that reverting conversation status back to pending on a Scout-enabled inbox rebroadcasts linked opportunities with `has_unread_messages: false` and `scout_engaged: true` in `custom/spec/models/custom/concerns/conversation_spec.rb`

**Checkpoint**: All user stories functional and independently verified

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Ensure code quality, linting compliance, and full end-to-end scenario validation across backend and frontend

- [X] T013 [P] Run global linters across backend and frontend per repo rules (`docker compose exec rails bundle exec rubocop` and `docker compose exec vite pnpm eslint`)
- [X] T014 Execute full quickstart validation scenarios from `specs/064-kanban-unread-message-indicator/quickstart.md`, including manually confirming SC-003's 5-second real-time target (deliberately verified manually, not via an automated timing assertion, consistent with how the sibling "Scout" badge broadcast was validated)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Sequenced after Foundational (Phase 2) for convenience, but has no hard dependency on it (T003-T007 never call the renamed broadcast method)
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) and US1 model changes (Phase 3)
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) and US1 model changes (Phase 3)
- **User Story 4 (Phase 6)**: Depends on Foundational (Phase 2), US1 (Phase 3), and US2 (Phase 4)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - Delivers MVP capability (derived field, as_json, UI dot, i18n)
- **User Story 2 (P2)**: Integrates with US1's derived field; adds real-time clearing when `agent_last_seen_at` updates
- **User Story 3 (P2)**: Integrates with US1's derived field; adds real-time appearance when incoming `Message` is created
- **User Story 4 (P3)**: Validates that Scout re-engagement turns off indicator via status transition broadcast from US2

### Within Each User Story

- Tests MUST be written and fail before implementation
- Backend models / translations before UI components
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 3 (US1)**:
  - T003 (Opportunity unit specs) and T004 (KanbanCard component specs) can run in parallel [P]
  - T005 (Translations i18n) can run in parallel with T006 (Backend model implementation) [P]
- **Phase 4 (US2)** and **Phase 5 (US3)**:
  - T008 (Conversation concern specs) and T010 (Message concern specs) can run in parallel across separate files [P]
- **Phase 7 (Polish)**:
  - T013 (RuboCop & ESLint linters) can run in parallel before manual quickstart validation [P]

---

## Parallel Example: User Story 1

```bash
# Launch unit tests and component tests for User Story 1 in parallel:
Task: "Add unit tests for Opportunity#has_unread_messages? and Opportunity#as_json in spec/models/opportunity_spec.rb"
Task: "Add component tests for unread indicator rendering in app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js"

# Launch translations and backend model logic in parallel:
Task: "Add OPPORTUNITIES.BOARD.UNREAD_TOOLTIP key to English and Portuguese translations in app/javascript/dashboard/i18n/locale/en/opportunities.json and app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json"
Task: "Implement derived boolean has_unread_messages? in custom/app/models/opportunity.rb"
```

---

## Parallel Example: User Story 2 & User Story 3

```bash
# Backend triggers for read state and new message can be developed in parallel:
Task (US2): "Widen after_commit hook condition on :update in custom/app/models/custom/concerns/conversation.rb"
Task (US3): "Create Custom::Concerns::Message concern in custom/app/models/custom/concerns/message.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002) - rename broadcast methods
3. Complete Phase 3: User Story 1 (T003 - T007)
4. **STOP and VALIDATE**: Test User Story 1 independently (board shows dot for handed-off/non-scout cards with unread incoming messages; hides dot for scout-engaged cards)
5. Deploy/demo MVP

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (MVP) → Test independently
3. Add User Story 2 → Test real-time read clearing independently
4. Add User Story 3 → Test real-time new incoming message independently
5. Add User Story 4 → Test real-time Scout re-engagement independently
6. Complete Polish (linters & quickstart scenarios)

### Parallel Team Strategy

With multiple developers:
1. Team completes Setup (T001) + Foundational (T002) together
2. Once Foundational is done:
   - Developer A: User Story 1 (T003-T007)
   - Once US1 backend lands:
     - Developer B: User Story 2 (T008-T009)
     - Developer C: User Story 3 (T010-T011)
3. Stories integrate cleanly without file collisions

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks
- `[Story]` label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Do NOT create git commits or push to remote before explicit user approval per repo rules

---

## Phase 8: Convergence

- [X] T015 Add a test to `spec/models/opportunity_spec.rb`'s `#has_unread_messages?` block asserting it returns `false` when `active_conversation` has already been handed off (not pending) with an unread incoming message, while a second, non-active conversation linked to the same opportunity is still pending on a Scout-enabled inbox per FR-002 / spec.md Edge Cases (multi-conversation) / Clarifications Session 2026-09-10 Q1 (partial)
