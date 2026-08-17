---

description: "Task list for Multi-Conversation Opportunity Lifecycle implementation"
---

# Tasks: Multi-Conversation Opportunity Lifecycle

**Input**: Design documents from `specs/039-multi-conversation-opportunities/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/opportunities_api.yaml](contracts/opportunities_api.yaml), [quickstart.md](quickstart.md)

**Organization**: Tasks are grouped by phase and user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`, `[US4]`)
- Exact file paths are specified in every task description

---

## Phase 1: Setup & Data Model Foundation

**Purpose**: Database schema, models, and associations that all user stories depend on.

- [X] T001 Create database migration in `db/migrate/20260817000001_create_ichatr_opportunity_conversations.rb` with `ichatr_opportunity_conversations` join table, `active_conversation_id` reference with partial unique index on `ichatr_opportunities`, and safe data backfill for existing opportunities.
- [X] T002 [P] Create `OpportunityConversation` model in `custom/app/models/opportunity_conversation.rb` with associations (`belongs_to :opportunity`, `belongs_to :conversation`, `belongs_to :account`) and validations.
- [X] T003 [P] Create `Custom::Concerns::Conversation` concern in `custom/app/models/custom/concerns/conversation.rb` adding `has_many :opportunity_conversations`, `has_many :opportunities`, and `has_one :active_opportunity`.
- [X] T004 Update `Opportunity` model in `custom/app/models/opportunity.rb` with `belongs_to :active_conversation`, `has_many :opportunity_conversations`, helper methods (`attach_conversation!`, `detach_active_conversation!`), and serialize `active_conversation_id`, `active_conversation_display_id`, and `associated_conversations` in `as_json`.

---

## Phase 2: Foundational (Backend Event Listeners & Controllers)

**Purpose**: Event dispatching, controllers, and automation rule adapters.

- [X] T005 Implement event hooks in `custom/app/listeners/custom/action_cable_listener.rb` for `conversation_resolved`, `conversation_opened`, and `conversation_deleted` to auto-detach/re-attach active conversation and broadcast `opportunity_updated`.
- [X] T006 [P] Update `OpportunitiesController` in `custom/app/controllers/api/v1/accounts/opportunities_controller.rb` to permit `active_conversation_id`, resolve conversation display IDs, eager load `:active_conversation`, and add conversation link endpoint.
- [X] T007 [P] Update automation rule services in `custom/app/services/custom/automation_rules/opportunity_action_service.rb` and `custom/app/services/custom/automation_rules/opportunity_conditions_filter_service.rb` to resolve `@conversation = opportunity.active_conversation || opportunity.origin_conversation`.

**Checkpoint**: Foundation ready — database, models, listeners, and controllers support multi-conversation lifecycle.

---

## Phase 3: User Story 1 - Automatic Conversation Detachment on Closure (Priority: P1) 🎯 MVP

**Goal**: When an active conversation concludes and is resolved, the opportunity detaches the active conversation slot and restores the "Start Conversation" action button in realtime on the Kanban card without page reload.

**Independent Test**: Link an opportunity to an active conversation. Resolve the conversation in Chatwoot. Verify in realtime that the opportunity card reflects an unlinked conversation state and displays the "Start Conversation" button.

- [X] T008 [US1] Update `KanbanCard.vue` in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` to check `active_conversation_id` / `active_conversation_display_id` for card click routing, active chat styling, and displaying `StartOpportunityConversationButton` when no active conversation exists.
- [X] T009 [P] [US1] Update `OpportunityListView.vue` in `app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunityListView.vue` and `Index.vue` in `app/javascript/dashboard/routes/dashboard/opportunities/Index.vue` to use `active_conversation_id` for row clicks, styling, and action button.
- [X] T010 [P] [US1] Update `ContactOpportunities.vue` in `app/javascript/dashboard/routes/dashboard/conversation/ContactOpportunities.vue` to match current conversation against `active_conversation_display_id` and `associated_conversations`.

**Checkpoint**: User Story 1 (MVP) is fully functional and independently testable.

---

## Phase 4: User Story 2 - Smart Conversation Initiation & Linking (Priority: P1)

**Goal**: When clicking "Start Conversation" on a card without an active conversation, detect if the contact has open conversations. If 1+ open conversations exist, show a modal to link an existing conversation (with transfer warning if active elsewhere) or start new. If 0 open conversations exist, open the composer directly.

**Independent Test**: Click "Start Conversation" on an opportunity whose contact has an open conversation; verify modal displays choices and links successfully. Click on an opportunity whose contact has no open conversations; verify composer opens directly.

- [X] T011 [P] [US2] Create `OpportunityConversationLinkModal.vue` in `app/javascript/dashboard/components-next/Opportunities/OpportunityConversationLinkModal.vue` displaying selectable open conversation cards (inbox icon, display ID, snippet, transfer warning) and action to start a new conversation.
- [X] T012 [US2] Update `StartOpportunityConversationButton.vue` in `app/javascript/dashboard/routes/dashboard/opportunities/components/StartOpportunityConversationButton.vue` to fetch contact conversations on click, open `OpportunityConversationLinkModal` when open conversations exist, or open `ComposeConversation` when none exist, linking created/chosen chat as `active_conversation_id`.
- [X] T013 [P] [US2] Add `linkConversation` action in `app/javascript/dashboard/store/modules/opportunities/actions.js` to dispatch conversation attachment to backend and sync Vuex store.

**Checkpoint**: User Stories 1 and 2 work seamlessly together.

---

## Phase 5: User Story 3 - Multi-Conversation History in Opportunity Details (Priority: P2)

**Goal**: Display complete timeline of all associated conversations (past and active) in the opportunity details drawer/modal with status badges, dates, and 1-click navigation links.

**Independent Test**: Open the details drawer for an opportunity with multiple conversations. Verify all conversations appear in chronological order with correct status and direct click-through to messages.

- [X] T014 [US3] Update `OpportunityBackfillModal.vue` in `app/javascript/dashboard/components-next/Opportunities/OpportunityBackfillModal.vue` to render a "Conversation History" section showing `associated_conversations` (Open/Resolved status, dates, active tag, and click-to-open drawer navigation).
- [X] T015 [P] [US3] Update `ContactOpportunityCard.vue` in `app/javascript/dashboard/components-next/Opportunities/ContactOpportunityCard.vue` to indicate active vs historical conversation status in the contact sidebar.

**Checkpoint**: Conversation history is fully visible and accessible in opportunity details views.

---

## Phase 6: User Story 4 - Single Active Conversation Constraint & Rule Enforcement (Priority: P2)

**Goal**: Enforce at most one active conversation per opportunity across backend validations and stage transitions, preserving active conversations during Won/Lost stage moves until resolved.

**Independent Test**: Verify that transitioning an opportunity to Won or Lost does not detach or close the active conversation, and attempting to link a second conversation prompts or replaces the active slot.

- [X] T016 [US4] Add validation in `Opportunity` (`custom/app/models/opportunity.rb`) to enforce exclusivity of active conversation across open opportunities, with explicit transfer support.
- [X] T017 [US4] Ensure terminal stage (`won`/`lost`) transition logic in `custom/app/models/opportunity.rb` preserves `active_conversation_id` until the conversation itself is resolved.

---

## Phase 7: Polish & Bilingual Translations

**Purpose**: Translations, code formatting, and end-to-end validation.

- [X] T018 [P] Add English translations in `app/javascript/dashboard/i18n/locale/en/opportunities.json` for link modal, transfer warnings, and conversation history labels.
- [X] T019 [P] Add synchronous Portuguese (`pt-BR`) translations in `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json` for all new UI strings.
- [X] T020 Execute end-to-end validation scenarios from `specs/039-multi-conversation-opportunities/quickstart.md`, run backend lint (`bundle exec rubocop`), and frontend lint (`pnpm eslint`).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup & Foundation)**: No dependencies — start immediately.
- **Phase 2 (Foundational Listeners & Controllers)**: Depends on Phase 1 completion.
- **Phase 3 (User Story 1 - MVP)**: Depends on Phase 2.
- **Phase 4 (User Story 2)**: Depends on Phase 2 & Phase 3.
- **Phase 5 (User Story 3)**: Depends on Phase 1 & Phase 2.
- **Phase 6 (User Story 4)**: Depends on Phase 2.
- **Phase 7 (Polish & Translations)**: Depends on Phases 3, 4, 5, 6 completion.

### Parallel Opportunities

- **Phase 1**: T002, T003 can run in parallel with T001.
- **Phase 2**: T006, T007 can run in parallel with T005.
- **Phase 3**: T009, T010 can run in parallel with T008.
- **Phase 4**: T011, T013 can run in parallel with T012.
- **Phase 5**: T015 can run in parallel with T014.
- **Phase 7**: T018, T019 can run in parallel.

---

## Implementation Strategy

### MVP First (User Story 1 Only)
1. Complete Phase 1 (Data migration & models).
2. Complete Phase 2 (Event listeners & controllers).
3. Complete Phase 3 (Kanban card detachment & button display).
4. **Validate MVP**: Resolving a conversation frees up the card and restores "Start Conversation".

### Incremental Delivery
1. Add User Story 2 (Smart Linking Modal & initiate flow).
2. Add User Story 3 (Conversation History in drawer/modal).
3. Add User Story 4 (Exclusivity constraint & Won/Lost preservation).
4. Add Phase 7 (i18n English + Portuguese & lints).
