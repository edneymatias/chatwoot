# Tasks: Scout Audience Targeting

**Input**: Design documents from `/specs/065-scout-audience-targeting/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are included per plan.md specifications (RSpec for custom backend models, services, and controllers; Vitest for frontend Vue components).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify development container environment and database readiness

- [X] T001 Verify development container environment and database readiness in `config/database.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core schema migration required before any user story can be implemented or tested

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Create database migration to add `audience` column with constraint "`jsonb`, `NOT NULL`, `default: []`" on `ichatr_scouts` table in `db/migrate/20260910145200_add_audience_to_ichatr_scouts.rb`
- [X] T003 Execute database migration via `docker compose exec rails bundle exec rails db:migrate` and record schema changes in `db/schema.rb`

**Checkpoint**: Foundation ready — database has `audience` column on `ichatr_scouts`, unblocking User Story implementation.

---

## Phase 3: User Story 1 - Define a target audience for a Scout (Priority: P1) 🎯 MVP

**Goal**: Admin can configure, inspect, persist, and clear a target audience (flat list of conditions over Contact attributes with AND/OR logic) on a Scout. Matching is evaluated via `Scout#engages?`.

**Independent Test**: Configure targeting conditions on a Scout (e.g. phone number equals X) and confirm conditions persist via API/UI and evaluate correctly in `Scout#engages?` (matches when matching, fails when not matching, engages everyone when empty).

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T004 [P] [US1] Create unit tests for `Custom::Scout::AudienceMatcherService` covering all operators, AND/OR sequence, missing contact attributes, narrow local rescue for invalid comparisons (FR-007: "caught with a narrow, local rescue and also treated as 'no match' for that one condition"), raising on unexpected system errors, and empty conditions list in `custom/spec/services/custom/scout/audience_matcher_service_spec.rb`
- [X] T005 [P] [US1] Extend unit tests for `Scout#engages?` in `custom/spec/models/scout_spec.rb` (file already exists — add new `describe`/`context` blocks) covering empty audience (returns true unconditionally), matching contact, non-matching contact, and the FR-011 forward-only invariant (given a conversation already `pending` with a Scout for a matching contact, updating that Scout's `audience` to exclude the contact and saving MUST NOT change the existing conversation's status — no code path re-evaluates already-pending conversations on an audience edit)
- [X] T006 [P] [US1] Extend controller request specs in `custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb` (file already exists — add new `describe`/`context` blocks) for `audience` param handling in `Api::V1::Accounts::ScoutsController` covering permit of `audience: [:attribute_key, :filter_operator, :query_operator, { values: [] }]`, serialization in show/index, and resetting with empty array
- [X] T007 [P] [US1] Create frontend component unit tests for `ScoutAudienceTab.vue` verifying empty state, adding condition, removing condition, clearing all conditions, and saving payload in `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutAudienceTab.spec.js`

### Implementation for User Story 1

- [X] T008 [US1] Implement `Custom::Scout::AudienceMatcherService` evaluating flat condition list against Contact attributes (`name`, `email`, `phone_number`, `identifier`, `blocked`, `country_code`, `city`, `company_name`, `labels`, and custom attributes) supporting operators (`equal_to`, `not_equal_to`, `is_present`, `is_not_present`, `contains`, `does_not_contain`, `starts_with`, `greater_than`, `less_than`) with constraint "An unrecognized `attribute_key` or `filter_operator` simply fails to match (falls through to 'no match' for that condition) rather than raising" and constraint "caught with a narrow, local rescue and also treated as 'no match' for that one condition (FR-007) — evaluation of the remaining conditions in the audience continues normally", allowing genuine unexpected errors to raise, in `custom/app/services/custom/scout/audience_matcher_service.rb`
- [X] T009 [US1] Implement `Scout#engages?(contact, conversation = nil)` method delegating to `Custom::Scout::AudienceMatcherService` with constraint "Returns `true` unconditionally when `audience` is blank (FR-003)" in `custom/app/models/scout.rb`
- [X] T010 [US1] Update `Api::V1::Accounts::ScoutsController` to permit strong parameters `audience: [:attribute_key, :filter_operator, :query_operator, { values: [] }]` allowing wholesale replacement and clearing with empty array `[]` (spec FR-003, US1 Scenario 4) in `custom/app/controllers/api/v1/accounts/scouts_controller.rb`
- [X] T011 [P] [US1] Add target audience localization keys for tab title, subtitle, empty state, buttons, and badges synchronously in `app/javascript/dashboard/i18n/locale/en/scout.json` and `app/javascript/dashboard/i18n/locale/pt_BR/scout.json`
- [X] T012 [P] [US1] Implement `ScoutAudienceTab.vue` container using `ConditionRow.vue` and `useContactFilterContext()` with empty state, condition list management, and save/clear actions via `ScoutAPI.update` in `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutAudienceTab.vue`
- [X] T013 [US1] Register `scout_audience` route under Scout detail routes in `app/javascript/dashboard/routes/dashboard/scout/scout.routes.js`
- [X] T014 [US1] Register audience tab in `ScoutDetail.vue` by updating `tabIndexMap`, `currentTab`, `tabs` computed list, `handleTabChanged` route map, and template rendering in `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutDetail.vue`

**Checkpoint**: User Story 1 is fully functional and testable independently. Admins can configure, save, and clear Scout audiences, and `Scout#engages?` evaluates contacts against the audience.

---

## Phase 4: User Story 2 - Route non-matching new conversations to the human queue (Priority: P2)

**Goal**: When a new conversation is created in an inbox with an enabled Scout, evaluate if the contact matches the target audience. If non-matching, route the conversation directly to the human queue (`:open`) instead of `:pending`. If matching, retain `:pending` for Scout engagement.

**Independent Test**: As Contact B (non-matching), create a new conversation and verify its status is `:open` (human queue). As Contact A (matching), create a new conversation and verify its status is `:pending` (Scout queue).

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T015 [P] [US2] Create model specs for `Custom::Conversation#determine_conversation_status` covering enabled Scout with matching contact (`:pending`), enabled Scout with non-matching contact (`:open`), disabled Scout or inbox without Scout (calls `super` unaltered), and blocked contact (`:resolved`) in `custom/spec/models/custom/conversation_spec.rb`

### Implementation for User Story 2

- [X] T016 [US2] Implement `Custom::Conversation` module overriding `determine_conversation_status` (prepended onto `Conversation`) with constraint "calls `super` unconditionally before applying its own logic", checking `return unless pending?`, and setting `self.status = :open if inbox&.scout&.enabled? && !inbox.scout.engages?(contact, self)` in `custom/app/models/custom/conversation.rb`

**Checkpoint**: User Stories 1 and 2 work independently. Non-matching new conversations are routed straight to human queue without abandoning contacts in pending state.

---

## Phase 5: User Story 3 - Route reopened non-matching conversations to the human queue (Priority: P3)

**Goal**: When a resolved conversation is reopened by a contact who does NOT match the Scout's target audience, route it to the human queue (`open!`) instead of handing it to the Scout, while preserving `Current.executed_by = sender if conversation.inbox.api? && reopened_by_contact?` for Opportunity/Kanban attribution. If matching, allow reopening to the Scout (`pending!`).

**Independent Test**: Resolve a conversation for non-matching Contact B, send an incoming message, verify conversation reopens with status `:open` and `Current.executed_by` is set for API channel. With matching Contact A, verify conversation reopens with status `:pending`.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T017 [P] [US3] Extend model specs in `custom/spec/models/custom/message_spec.rb` (file already exists — add new `describe`/`context` blocks) for `Custom::Message#reopen_resolved_conversation` covering enabled Scout with matching contact (reopens to `:pending`), enabled Scout with non-matching contact (reopens to `:open`), preserving `Current.executed_by` on API channel when reopened by contact, and inbox without Scout (calls `super`)

### Implementation for User Story 3

- [X] T018 [US3] Extend `Custom::Message` to override `reopen_resolved_conversation`: call `super` if `conversation.inbox&.scout` is blank or disabled; if non-matching (`!scout.engages?(conversation.contact, conversation)`), enforce constraint "MUST still set `Current.executed_by = sender if conversation.inbox.api? && reopened_by_contact?`" before calling `conversation.open!`; otherwise call `super` in `custom/app/models/custom/message.rb`

**Checkpoint**: All three User Stories are functional and independently testable. Both new and reopened non-matching conversations reliably route to the human queue.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, full test suite pass, lint compliance, and end-to-end quickstart validation

- [X] T019 [P] Run RuboCop lint checks across modified and new Ruby files and resolve any offenses in `custom/app/` and `custom/spec/`
- [X] T020 [P] Run ESLint checks across modified and new Vue/JS files and resolve any offenses in `app/javascript/dashboard/`
- [X] T021 Run backend and frontend test suites via RSpec (`custom/spec/`) and Vitest for modified modules
- [X] T022 Execute manual validation scenarios according to `specs/065-scout-audience-targeting/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories (database column required)
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1 (P1): Can start immediately after Phase 2 (MVP)
  - User Story 2 (P2): Depends on US1 completion (`Scout#engages?` matcher method)
  - User Story 3 (P3): Depends on US1 completion (`Scout#engages?` matcher method)
  - US2 and US3 can proceed in parallel once US1 core matcher is in place
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Phase 2 (migration). Delivers `audience` column, matcher service, model method, API endpoint, and UI tab.
- **User Story 2 (P2)**: Depends on US1 (`Scout#engages?`). Implements new conversation status determination in `Custom::Conversation`.
- **User Story 3 (P3)**: Depends on US1 (`Scout#engages?`). Implements conversation reopening routing in `Custom::Message`.
- **Independent Testability**: Each story has its own automated specs and independent manual verification criteria.

### Within Each User Story

- Tests MUST be written and fail before implementation
- Services and models before endpoints and hooks
- Core logic before routing/UI integration
- Story checkpoint validated before considering complete

### Parallel Opportunities

- Within Phase 3 (US1 Tests): T004, T005, T006, and T007 can all be written in parallel
- Within Phase 3 (US1 Implementation): T011 (i18n) and T012 (Vue tab) can proceed in parallel with backend service work
- Within Phase 4 (US2) and Phase 5 (US3): T015/T016 (US2 Conversation) and T017/T018 (US3 Message) touch completely separate model files and can be executed in parallel once US1 is complete
- Within Phase 6 (Polish): T019 (RuboCop) and T020 (ESLint) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all test writing tasks for User Story 1 together:
Task: T004 "Create unit tests for Custom::Scout::AudienceMatcherService in custom/spec/services/custom/scout/audience_matcher_service_spec.rb"
Task: T005 "Create unit tests for Scout#engages? in custom/spec/models/scout_spec.rb"
Task: T006 "Create controller request specs for audience param handling in custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb"
Task: T007 "Create frontend component unit tests for ScoutAudienceTab.vue in app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutAudienceTab.spec.js"

# Launch parallel frontend implementation tasks:
Task: T011 "Add target audience localization keys in app/javascript/dashboard/i18n/locale/en/scout.json and pt_BR/scout.json"
Task: T012 "Implement ScoutAudienceTab.vue component in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutAudienceTab.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (Database migration)
3. Complete Phase 3: User Story 1 (Matcher service, model method, controller params, and UI tab)
4. **STOP and VALIDATE**: Verify audience configuration, persistence, and `Scout#engages?` evaluation
5. Deliver MVP capability (admins can configure audiences and confirm matching logic)

### Incremental Delivery

1. Foundation: Schema migration applied (`ichatr_scouts.audience`)
2. Increment 1 (MVP - US1): Audience configuration and matcher service ready
3. Increment 2 (US2): New conversations from non-matching contacts route to human queue (`:open`)
4. Increment 3 (US3): Reopened conversations from non-matching contacts route to human queue (`:open`), preserving attribution
5. Increment 4 (Polish): RuboCop, ESLint, test suite, and quickstart end-to-end validation

### Parallel Team Strategy

With multiple developers:
1. Team completes Phase 1 and Phase 2 together
2. Once Phase 2 is complete:
   - Developer A implements Backend (T008, T009, T010)
   - Developer B implements Frontend (T011, T012, T013, T014)
3. Once US1 merges:
   - Developer A implements US2 (`Custom::Conversation`)
   - Developer B implements US3 (`Custom::Message`)
4. Reconverge for Phase 6 Polish & Validation

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[Story]` label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group with user validation
- Adheres to Chatwoot Constitution Principle I (Upstream Compatibility First) by keeping all domain code under `custom/` and isolated Vue tab components

---

## Phase 7: Convergence

**Purpose**: Close test-coverage gaps found by `/speckit-converge` after `/speckit-implement` completed Phases 1-6. Both findings are `partial` (implementation is correct and already passing; only test coverage is incomplete) — see the Convergence Findings report for full evidence.

- [X] T023 Extend `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutAudienceTab.spec.js` with test cases for `addCondition()` (grows `filters`), `removeCondition(index)` (shrinks `filters`), and `saveAudience()` (asserts `ScoutAPI.update` is called with the correctly-shaped `audience` payload: `attribute_key`/`filter_operator`/`query_operator`/`values`) per tasks.md T007 / FR-008, FR-009 (partial)
- [X] T024 Add a "when Captain is also present on the inbox" context under `#reopen_resolved_conversation` in `custom/spec/models/custom/message_spec.rb`, mirroring the existing Captain-coexistence context already present for `#mark_pending_conversation_as_open_for_human_response` in the same file, asserting the documented Enterprise/Scout MRO composability tradeoff behaves as designed per plan.md Technical Context Constraints / Constitution V (partial)
