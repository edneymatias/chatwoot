# Tasks: Unified Card Click & History Links

**Input**: Design documents from `specs/043-card-click-history-links/`  
**Prerequisites**: `plan.md`, `spec.md`, `data-model.md`, `contracts/`, `research.md`, `quickstart.md`  

## Format: `- [ ] [ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no blocking dependencies)
- **[Story]**: User story identifier (`[US1]`, `[US2]`)
- Every task includes explicit file paths

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify environment, documentation, and existing test baseline.

- [x] T001 Verify baseline frontend and backend test suites run cleanly via `docker compose exec vite pnpm test` and `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/opportunities/activities_controller_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Update routing and drawer composable so that navigating to the opportunity conversation route without a `conversationId` is a first-class supported state.

**⚠️ CRITICAL**: Must complete before User Story 1 and User Story 2 navigation changes can function properly.

- [x] T002 Make `conversationId` parameter optional (`conversations/:conversationId?`) on `opportunities_conversation` route in `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- [x] T003 Guard `route.params.conversationId` watcher against undefined/empty values so it does not invoke `processConversation(undefined)` in `app/javascript/dashboard/composables/useConversationDrawer.js`

**Checkpoint**: Foundation ready — navigation with only `query: { opportunityId }` will not crash or trigger invalid conversation lookups.

---

## Phase 3: User Story 1 - Card click always opens something (Priority: P1) 🎯 MVP

**Goal**: Clicking any Kanban card or list-view row always opens the drawer: showing the active conversation if present, or opening directly to the opportunity's activity/history tab if there is no active conversation. All cards appear visually interactive (no grayscale or dashed styling). The "+" start/link conversation button continues to work in isolation.

**Independent Test**: Load the Kanban board and list view. Click a card/row with an active conversation → verify drawer opens to the conversation. Click a card/row without an active conversation → verify drawer opens to the opportunity's activity tab (previously a no-op) with no grayscale/dashed border. Click the "+" button on a card without an active conversation → verify only the start/link dialog opens without triggering the card navigation.

### Implementation for User Story 1

- [x] T004 [US1] Update `OpportunityConversationDrawer.vue` default `activeTab` initialization and watchers in `app/javascript/dashboard/components-next/Opportunities/OpportunityConversationDrawer.vue` to default to `'activity'` when `route.params.conversationId` is absent and `'conversation'` when `conversationId` is present
- [x] T005 [P] [US1] Update `handleCardClick` in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` to always navigate to `opportunities_conversation` with `query: { opportunityId: props.opportunity.id }` (omitting `params.conversationId` when `active_conversation_id` is absent), and update `cardClass` to remove non-clickable/grayscale/dashed styles so all cards render with standard interactive hover styling
- [x] T006 [P] [US1] Update `handleRowClick` in `app/javascript/dashboard/routes/dashboard/opportunities/Index.vue` to navigate to `opportunities_conversation` with `query: { opportunityId: opportunity.id }` (omitting `conversationId` when `active_conversation_id` is absent)
- [x] T007 [P] [US1] Update `OpportunityListView.vue` row styling in `app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunityListView.vue` to remove grayscale/dashed border on rows without active conversation so all rows display standard interactive hover styling
- [x] T008 [P] [US1] Add Vitest unit test coverage for `OpportunityConversationDrawer.vue` in `app/javascript/dashboard/components-next/Opportunities/specs/OpportunityConversationDrawer.spec.js` verifying `activeTab` defaults to `'activity'` when `route.params.conversationId` is absent, defaults to `'conversation'` when present, and switches to `'conversation'` when the param transitions from absent to present (depends on T004)
- [x] T009 [P] [US1] Add Vitest unit test coverage for the list view in `app/javascript/dashboard/routes/dashboard/opportunities/components/specs/OpportunityListView.spec.js` verifying `handleRowClick` dispatches a rowClick event for rows with and without an active conversation, and that all rows render with interactive pointer styling (depends on T006, T007)
- [x] T010 [US1] Add Vitest unit test coverage for `KanbanCard.vue` in `app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js` verifying click handler dispatches route push for opportunities with and without active conversations, and does not fire when clicking the start conversation button (depends on T005)

**Checkpoint**: User Story 1 complete & independently testable — clicking cards/rows always opens the drawer to conversation or activity log, with uniform interactive styling, and all three touched components have dedicated test coverage.

---

## Phase 4: User Story 2 - Conversation history entries link to their conversation (Priority: P2)

**Goal**: Every conversation-related history entry (`conversation_opened`, `conversation_transferred_in`, `conversation_transferred_out`, `conversation_detached`) displays the conversation's current status and renders as a clickable link to jump straight to that conversation inside the drawer, provided the current user has permission and the conversation exists; otherwise, it renders as plain text with no status badge.

**Independent Test**: Open an opportunity's activity log. Verify conversation events show their current status badge (`open`, `pending`, `resolved`, `snoozed`) and are clickable links when accessible. Click a link for an open, resolved, or detached conversation → verify drawer switches to that conversation while preserving `query.opportunityId`. Verify unauthorized or missing conversations render as plain unclickable text with no badge. Verify non-conversation events remain plain text.

### Implementation for User Story 2

- [x] T011 [US2] Update `Api::V1::Accounts::Opportunities::ActivitiesController#index` in `custom/app/controllers/api/v1/accounts/opportunities/activities_controller.rb` to batch-load referenced conversations across all conversation-related activities (`conversation_opened`, `conversation_transferred_in`, `conversation_transferred_out`, `conversation_detached`), evaluate `ConversationPolicy.new(pundit_user, conv).show?`, and enrich matching activities with `conversation_status` and `conversation_viewable` fields
- [x] T012 [P] [US2] Update request specs in `custom/spec/requests/api/v1/accounts/opportunities/activities_controller_spec.rb` to verify `conversation_status` and `conversation_viewable` enrichment for all 4 conversation event types, including authorized, unauthorized (inaccessible inbox/team), and nonexistent conversation cases, and verifying non-conversation activities are not modified
- [x] T013 [P] [US2] Add conversation status translation strings (if needed for uppercase badges / a11y) synchronously in `app/javascript/dashboard/i18n/locale/en/opportunities.json` and `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`
- [x] T014 [US2] Update `OpportunityActivityLog.vue` in `app/javascript/dashboard/components-next/Opportunities/OpportunityActivityLog.vue` to render conversation events as clickable links with a status badge when `activity.conversation_viewable === true`, falling back to plain text when false, and implementing link click to navigate to `opportunities_conversation` with `params: { conversationId: displayId }` and preserved `query: { opportunityId: props.opportunityId }`
- [x] T015 [US2] Add Vitest unit test coverage for `OpportunityActivityLog.vue` in `app/javascript/dashboard/components-next/Opportunities/specs/OpportunityActivityLog.spec.js` verifying link rendering when `conversation_viewable` is true, plain text when false or missing, and route push on link click

**Checkpoint**: User Story 2 complete & independently testable — conversation events in activity log are clickable links with status badges when viewable and plain text otherwise.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Automated test validation, lint verification, and manual scenario execution.

- [x] T016 [P] Run backend RSpec tests via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/opportunities/activities_controller_spec.rb`
- [x] T017 [P] Run backend RuboCop checks via `docker compose exec rails bundle exec rubocop`
- [x] T018 [P] Run frontend test suite via `docker compose exec vite pnpm test`
- [x] T019 [P] Run frontend ESLint checks via `docker compose exec vite pnpm eslint`
- [x] T020 Execute manual verification scenarios per `specs/043-card-click-history-links/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - baseline checks can start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 - BLOCKS all user story navigation.
- **User Story 1 (Phase 3 - P1)**: Depends on Foundational (Phase 2).
- **User Story 2 (Phase 4 - P2)**: Backend (T011) can start in parallel with US1; frontend (T014) depends on Foundational (Phase 2) and US1 drawer tab handling.
- **Polish (Phase 5)**: Depends on completion of User Stories 1 and 2.

### Within Each User Story

- Foundational route param change before card click triggers it.
- Backend controller enrichment and request specs before frontend consumes the new fields.
- Components updated before adding component-level Vitest specs.

### Parallel Opportunities

- **Phase 2**: T002 (`dashboard.routes.js`) and T003 (`useConversationDrawer.js`) can be executed in parallel.
- **Phase 3 (US1)**: T005 (`KanbanCard.vue`), T006 (`Index.vue`), and T007 (`OpportunityListView.vue`) can be implemented in parallel once T004 is completed. Once their respective implementation tasks land, T008, T009, and T010 (the three Vitest spec tasks) can also run in parallel with each other, since each touches a different spec file.
- **Phase 4 (US2)**: Backend enrichment T011/T012 and i18n keys T013 can be worked on in parallel with Phase 3 frontend work.
- **Phase 5 (Polish)**: T016, T017, T018, and T019 can be run in parallel.

---

## Parallel Example: User Story 1

```bash
# Update card and list view click handlers and styling in parallel:
Task: "Update handleCardClick and cardClass in app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue"
Task: "Update handleRowClick in app/javascript/dashboard/routes/dashboard/opportunities/Index.vue"
Task: "Update OpportunityListView.vue row styling in app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunityListView.vue"
```

```bash
# Once their implementation tasks are done, add test coverage in parallel:
Task: "Add OpportunityConversationDrawer.vue Vitest spec covering activeTab default/switch logic"
Task: "Add list-view Vitest spec covering handleRowClick and row styling"
Task: "Add KanbanCard.vue Vitest spec covering handleCardClick and the start-conversation button"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational route & composable changes).
2. Complete Phase 3 (User Story 1: card and row click handling, styling updates, and their test coverage).
3. **STOP and VALIDATE**: Verify clicking cards without active conversation opens the history tab, while cards with active conversation open conversation view.
4. Deploy / demonstrate MVP.

### Incremental Delivery

1. Phase 1 + 2: Foundational routing support for optional conversation ID.
2. Phase 3 (US1 MVP): Every card click opens something useful, removing UI dead-ends.
3. Phase 4 (US2): Enrich activities API with policy-checked conversation status and render interactive links in activity log.
4. Phase 5 (Polish): Run full automated suites and quickstart scenarios.

---

## Phase 6: Convergence

- [ ] T021 Fix ESLint violations in the feature's own new spec files — `docker compose exec vite pnpm eslint` globs the whole app and its pre-existing project-wide noise masks these — per Constitution III (contradicts): run `pnpm eslint:fix` for the 15 auto-fixable `prettier/prettier` errors across `app/javascript/dashboard/components-next/Opportunities/specs/OpportunityActivityLog.spec.js` (2 errors), `app/javascript/dashboard/components-next/Opportunities/specs/OpportunityConversationDrawer.spec.js` (12 errors), and `app/javascript/dashboard/routes/dashboard/opportunities/components/specs/OpportunityListView.spec.js` (1 error); then manually rename the kebab-case `'select-conversation'` stub emit declaration and its `$emit('select-conversation', ...)` call to camelCase `'selectConversation'` in `OpportunityConversationDrawer.spec.js` (1 `vue/custom-event-name-casing` error) so `npx eslint` run against these files reports 0 errors
