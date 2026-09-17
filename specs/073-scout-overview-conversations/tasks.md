---
description: "Task list for Scout Overview Recent Conversations List implementation"
---

# Tasks: Scout Overview — Recent Conversations List

**Input**: Design documents from `/specs/073-scout-overview-conversations/`  
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/api.md`, `quickstart.md`, `tdd/test-list.md`  
**Tests**: TDD approach is mandatory per Constitution Principle VI. Test tasks MUST be written and observed failing (RED) before implementation code is written.  
**Organization**: Tasks are grouped by phase and user story to enforce test-driven development and enable independent verification of each capability.

## Format: `[ID] [P?] [Story] Description [BehaviorMarkers]`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g., `[US1]`, `[US2]`)
- **[BehaviorMarkers]**: Stable behavior IDs from `tdd/test-list.md` (e.g., `[U1]`, `[A1]`) indicating which behavior this task tests or implements
- Exact file paths are included in every task description

## Path Conventions

- **Backend (`custom/`)**: `custom/app/controllers/api/v1/accounts/`, `custom/app/services/reports/`, `config/routes.rb`
- **Frontend**: `app/javascript/dashboard/components-next/scout/overview/`, `app/javascript/dashboard/routes/dashboard/scout/pages/`, `app/javascript/dashboard/api/`
- **i18n**: `app/javascript/dashboard/i18n/locale/en/scout.json`, `app/javascript/dashboard/i18n/locale/pt_BR/scout.json`
- **Tests**: `custom/spec/requests/api/v1/accounts/`, `app/javascript/dashboard/components-next/scout/overview/`, `app/javascript/dashboard/routes/dashboard/scout/pages/`, `app/javascript/dashboard/api/specs/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Route configuration and synchronized bilingual localization keys.

- [X] T001 Register `:conversations` collection action under `resources :scout_overview_reports, only: [:index]` in `config/routes.rb`
- [X] T002 [P] Add English localization keys for recent conversations table headers, 6 status filter pills, outcome status badges, and empty state under `SCOUT.OVERVIEW.RECENT_CONVERSATIONS.*` in `app/javascript/dashboard/i18n/locale/en/scout.json`
- [X] T003 [P] Add Brazilian Portuguese (`pt-BR`) localization keys synchronously for recent conversations table headers, 6 status filter pills, outcome status badges, and empty state under `SCOUT.OVERVIEW.RECENT_CONVERSATIONS.*` in `app/javascript/dashboard/i18n/locale/pt_BR/scout.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: API client method, controller action validation scaffolding, and parameter bounds required by all user stories.

**⚠️ CRITICAL**: Test tasks MUST be observed failing (RED) before implementation tasks begin.

- [X] T021 [P] Write Vitest unit test in `app/javascript/dashboard/api/specs/scoutOverviewReports.spec.js` asserting `getConversations` sends GET request to `/api/v1/accounts/:account_id/scout_overview_reports/conversations` with serialized query parameters (`scout_id`, `range`, `timezone_offset`, `status`, `page`, `per_page`), observing it FAIL (RED) before implementation [U26]
- [X] T004 Implement `getConversations(accountId, { scoutId, range, timezoneOffset, status, page, perPage })` API client method in `app/javascript/dashboard/api/scoutOverviewReports.js`, turning T021 test GREEN (depends on T021) [U26]
- [X] T005 [P] Write RSpec request specs for `GET /api/v1/accounts/:account_id/scout_overview_reports/conversations` in `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` verifying authorization (`ScoutPolicy#show?`), 422 validation responses (`scout_id`, `range`, `status`), and pagination bounds (`page`, `per_page`), observing them FAIL (RED) before implementation [U1] [U2] [U3] [U4] [U5] [U6] [U7] [U8] [U9] [U10]
- [X] T006 Add `:conversations` action skeleton and query parameter validation in `custom/app/controllers/api/v1/accounts/scout_overview_reports_controller.rb` leveraging existing before-actions (`:check_authorization`, `:set_scout`, `:validate_range`) and adding action-specific validation for `status` (must be one of allowed values if present), `page` (integer >= 1), and `per_page` (default 25, max 100), turning T005 validation tests GREEN (depends on T005) [U1] [U2] [U3] [U4] [U5] [U6] [U7] [U8] [U9] [U10]

**Checkpoint**: Foundation ready — routing, API client, i18n, and parameter validation verified by passing tests. User story implementation can now begin.

---

## Phase 3: User Story 1 - View Scout Recent Conversations with Status Classification (Priority: P1) 🎯 MVP

**Goal**: As an operator or commercial manager viewing the Scout Overview page, view a paginated list of recent conversations handled by the selected Scout, showing contact identity, start timestamp, duration, total message count, and funnel outcome status badge, filterable by 6 status pills with dynamic counts, with duration showing `" — "` for single-message exchanges.

**Independent Test**: Seed conversations covering all five outcome states (`qualified`, `disqualified`, `abandoned`, `in_progress`, and `transferred_without_opportunity`) plus single-message conversation; verify table displays 5 columns, accurate status pill counts, duration formatting ("—" for single message), 25-record pagination, and synchronization with top-level Scout and Period selectors.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T007 [P] [US1] Add RSpec request specs in `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` verifying inbox scoping, 5 outcome classifications (`qualified`, `disqualified`, `abandoned`, `in_progress`, and `transferred_without_opportunity`), single-message null duration, multi-message duration, message counts, chronological ordering, status counts aggregation, status filtering, pagination envelope, range/scout scoping, and lateral opportunity resolution, observing them FAIL (RED) before builder implementation [U11] [U12] [U13] [U14] [U15] [U16] [U17] [U18] [U19] [U20] [U21] [U22] [U23] [U24] [U25]
- [X] T022 [P] [US1] Write Vitest unit tests in `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js` asserting status badge colors and labels for `qualified`, `disqualified`, `abandoned`, `in_progress`, and `transferred_without_opportunity` with neutral slate styling, observing them FAIL (RED) before badge component implementation [U27] [U28] [U29] [U30] [U31]
- [X] T008 [P] [US1] Write Vitest component spec in `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js` testing 5 table columns (Contact, Start Time, Duration, Messages, Status), 6 filter pills with counts, status pill click and re-fetch, duration formatting with `" — "` dash placeholder for single-message, text truncation for long contacts, empty state on zero matches, loading spinner, and pagination controls, observing them FAIL (RED) before component implementation [U32] [U33] [U34] [U35] [U36] [U37] [U38] [U39] [U40]
- [X] T015 [P] [US1] Update Vitest integration specs in `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js` asserting `RecentConversationsSection` is embedded with `scoutId`, `range`, and `timezoneOffset` props and synchronizes on period or scout selector changes, observing them FAIL (RED) before overview embedding [U44] [U45] [U46]

### Implementation for User Story 1

- [X] T009 [P] [US1] Implement `Reports::ScoutOverviewConversationsBuilder` in `custom/app/services/reports/scout_overview_conversations_builder.rb` querying `account.conversations.where(inbox_id: scout.inboxes.select(:id)).where(created_at: resolved_range)`, resolving `latest_opp` via `LEFT JOIN LATERAL`, classifying outcome status via SQL `CASE` expression (`qualified` when `pipeline_stage_id = scout.qualified_stage_id`, `disqualified` when `pipeline_stage_id = scout.unqualified_stage_id`, `abandoned` when `pipeline_stage_id = scout.rescue_stage_id`, `in_progress` when other stage or no opp with `conversations.status = 2` (`:pending`), `transferred_without_opportunity` when no opp and `conversations.status != 2`), aggregating `status_counts` across all 5 statuses and `all` total, applying `status` filter, sorting chronologically descending, paginating per page, and resolving per-page message metrics via grouped query on `messages`, turning T007 tests GREEN (depends on T007) [U11] [U12] [U13] [U14] [U15] [U16] [U17] [U18] [U19] [U20] [U21] [U22] [U23] [U24] [U25]
- [X] T010 [US1] Wire `Reports::ScoutOverviewConversationsBuilder` into `Api::V1::Accounts::ScoutOverviewReportsController#conversations` in `custom/app/controllers/api/v1/accounts/scout_overview_reports_controller.rb` returning JSON envelope with `conversations`, `status_counts`, and `pagination`, turning T007 tests GREEN (depends on T006, T007, T009) [U11] [U12] [U13] [U14] [U15] [U16] [U17] [U18] [U19] [U20] [U21] [U22] [U23] [U24] [U25]
- [X] T011 [P] [US1] Create `ConversationStatusBadge.vue` in `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.vue` rendering 5 outcome statuses with Tailwind styling, ensuring `transferred_without_opportunity` uses neutral slate styling (`bg-n-slate-3 text-n-slate-11 dark:bg-n-slate-4 dark:text-n-slate-11`) and is not styled as a failure or disqualification, turning T022 tests GREEN (depends on T022) [U27] [U28] [U29] [U30] [U31]
- [X] T012 [US1] Implement `RecentConversationsSection.vue` in `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.vue` using `BaseTable`, `BaseTableRow`, `BaseTableCell`, `PaginationFooter`, `EmptyStateLayout`, `Spinner`, and `ConversationStatusBadge`, managing active status pill filter, page pagination state, duration formatting via `formatDuration` (or `" — "` when duration is null or messages <= 1), text truncation, and data fetching via `scoutOverviewReportsAPI.getConversations`, turning T008 tests GREEN (depends on T004, T008, T011) [U32] [U33] [U34] [U35] [U36] [U37] [U38] [U39] [U40]
- [X] T013 [US1] Embed `RecentConversationsSection.vue` at the bottom of `ScoutOverview.vue` in `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue` below pipeline distribution and interest cards, bound to `selectedScoutId`, `selectedRange`, and `timezoneOffset`, turning T015 tests GREEN (depends on T012, T015) [U44] [U45] [U46]

### Acceptance Verification for User Story 1

- [X] T023 [US1] Verify Acceptance Behavior [A1]: Recent Conversations table renders with all 5 columns (Contact, Start Time, Duration, Messages, Status) for handled conversations in active period [A1]
- [X] T024 [US1] Verify Acceptance Behavior [A2]: Status filter pills filter table rows to selected outcome and display accurate counts for active period [A2]
- [X] T025 [US1] Verify Acceptance Behavior [A3]: Pagination bar navigates to page 2 records without full page reload when more than 25 conversations exist [A3]
- [X] T026 [US1] Verify Acceptance Behavior [A4]: Period selector and scout selector changes reload Recent Conversations table and counts without full page reload [A4]
- [X] T027 [US1] Verify Acceptance Behavior [A5]: Conversation handed off without sales opportunity displays status badge "Transferred without opportunity" with neutral slate styling and is never categorized as Disqualified [A5]

**Checkpoint**: At this point, User Story 1 is fully functional and testable independently. MVP is complete!

---

## Phase 4: User Story 2 - Open Full Native Conversation History from Row (Priority: P2)

**Goal**: As an operator reviewing the Recent Conversations table, click anywhere on a conversation row to open the complete, native conversation view (`/app/accounts/:account_id/conversations/:id`) in a new browser tab with `noopener,noreferrer`, leaving the Overview page state intact, with graceful error handling if the conversation is inaccessible.

**Independent Test**: In the Recent Conversations table, click a conversation row and verify `window.open` is invoked with the conversation URL in a new tab with `noopener,noreferrer`, and verify that clicking an inaccessible conversation displays an informative error/warning notice without crashing the page.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T014 [P] [US2] Add Vitest unit tests in `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js` asserting row click invokes `window.open` with URL `/app/accounts/:account_id/conversations/:conversation_id`, target `_blank`, and window features `'noopener,noreferrer'`, and verifying graceful notification if conversation ID is missing/invalid or window opening is blocked, observing them FAIL (RED) before handler implementation [U41] [U42] [U43]

### Implementation for User Story 2

- [X] T016 [US2] Implement row click navigation handler in `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.vue` opening `/app/accounts/:account_id/conversations/:id` in a new tab via `window.open(url, '_blank', 'noopener,noreferrer')` and displaying an informative notification if conversation ID is missing or window opening is blocked, turning T014 tests GREEN (depends on T012, T014) [U41] [U42] [U43]

### Acceptance Verification for User Story 2

- [X] T028 [US2] Verify Acceptance Behavior [A6]: Row click opens full native conversation transcript in a new browser tab with noopener,noreferrer [A6]
- [X] T029 [US2] Verify Acceptance Behavior [A7]: Missing conversation ID or blocked window popup displays informative warning notification without crashing [A7]

**Checkpoint**: At this point, User Stories 1 AND 2 are fully functional and integrated.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Edge case handling, formatting validation, test suite execution, and quickstart scenario verification.

- [X] T017 [P] Validate contact identity text truncation with standard Tailwind truncation classes (`truncate`, `max-w-*`) on long names and phone numbers to prevent row overflow in `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.vue` [U37]
- [X] T018 Run backend RuboCop auto-correct and RSpec suite via `docker compose exec -T rails bundle exec rubocop -a` and `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb`
- [X] T019 Run frontend ESLint and Vitest suites via `docker compose exec -T vite pnpm eslint` and `docker compose exec -T vite pnpm test app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js`
- [X] T020 Execute manual verification using quickstart seed script in `specs/073-scout-overview-conversations/quickstart.md` confirming all 5 outcome states, single-message duration dash, filter pills, pagination, and row opening

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion (routes and i18n available) — BLOCKS User Story 1
- **User Story 1 (Phase 3)**: Depends on Foundational completion (API client and validation available)
- **User Story 2 (Phase 4)**: Depends on User Story 1 (requires rendered table rows in `RecentConversationsSection.vue`)
- **Polish (Phase 5)**: Depends on User Story 1 and User Story 2 completion

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) — No dependencies on other stories
- **User Story 2 (P2)**: Depends on User Story 1 component (`RecentConversationsSection.vue` table rows) to attach click behavior

### Within Each User Story

- Tests MUST be written FIRST and observed FAILING (RED) before implementation (Principle VI)
- Backend builder (`Reports::ScoutOverviewConversationsBuilder`) and badge component (`ConversationStatusBadge.vue`) can be implemented in parallel
- Section container (`RecentConversationsSection.vue`) integrates badge and API client
- Embedded into `ScoutOverview.vue` once section container is implemented
- Acceptance verification tasks run once unit behaviors are green to verify end-to-end criteria

### Parallel Opportunities

- **Phase 1**: T002 and T003 (en and pt-BR localization files) can run in parallel
- **Phase 2**: T021/T004 (JS API client) and T005/T006 (RSpec request specs for validation) can run in parallel
- **Phase 3 (Tests)**: T007 (RSpec request specs for outcomes), T022 (Badge spec), T008 (Section component spec), and T015 (Overview spec) can run in parallel
- **Phase 3 (Implementation)**: T009 (Ruby builder service) and T011 (Vue status badge) can run in parallel
- **Phase 4 (Tests)**: T014 (Section row click spec) can be written before T016 implementation
- **Phase 5**: T017 (UI truncation), T018 (backend checks), and T019 (frontend checks) can run independently

---

## Parallel Example: User Story 1

```bash
# Launch test tasks for User Story 1 together:
Task: "Add RSpec request specs in custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb" [U11-U25]
Task: "Write Vitest unit tests in app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js" [U27-U31]
Task: "Write Vitest component spec in app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js" [U32-U40]
Task: "Update Vitest integration specs in app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js" [U44-U46]

# Launch backend builder and frontend badge component in parallel:
Task: "Implement Reports::ScoutOverviewConversationsBuilder in custom/app/services/reports/scout_overview_conversations_builder.rb" [U11-U25]
Task: "Create ConversationStatusBadge.vue in app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.vue" [U27-U31]
```

---

## Parallel Example: User Story 2

```bash
# Launch test task for User Story 2:
Task: "Add Vitest unit tests in app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js" [U41-U43]

# Implement row click handler:
Task: "Implement row click navigation handler in app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.vue" [U41-U43]
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (Routes & i18n keys)
2. Complete Phase 2: Foundational (API client test & method, validation tests & controller skeleton)
3. Complete Phase 3: User Story 1 (RSpec/Vitest tests → Builder service → Status badge → Table section → Overview page embed → Acceptance verification)
4. **STOP and VALIDATE**: Verify User Story 1 independently with quickstart seed data (5 outcome states, filter pills, pagination, single-message dash)
5. MVP is fully functional!

### Incremental Delivery

1. Setup + Foundational → Routing, localization, API client ready
2. Add User Story 1 → Paginated, classified recent conversations table rendered (MVP!)
3. Add User Story 2 → Row click opening full conversation in new tab with graceful missing handling
4. Phase 5 Polish → Truncation check, full RuboCop/ESLint/RSpec/Vitest suites passing clean

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks
- `[Story]` label (`[US1]`, `[US2]`) maps task to specific user story for traceability
- `[U1]`..`[U46]` and `[A1]`..`[A7]` markers map tasks directly to `tdd/test-list.md` behaviors for `/speckit.tdd.run` automated ticking
- All tasks strictly follow format `- [ ] [TaskID] [P?] [Story?] Description with file path [BehaviorMarkers]`
- Every constraint from `data-model.md` and `contracts/api.md` is quoted verbatim in task descriptions
- Zero database migrations or new tables introduced (satisfying Constitution Principles I, II, and IV)
- Translations kept strictly synchronized between `en/scout.json` and `pt_BR/scout.json`

---

## Phase 6: TDD Remediation

**✅ RESOLVED — findings F1–F10 cleared during `/speckit.implement` TDD remediation pass.**
Findings are ordered HIGH first. No finding may be closed by editing this file; each
requires an observable code or test change verified by the command shown.

### HIGH findings (blocking)

- [X] TR001 **[F1–F4] Establish red phases for U28–U31 ConversationStatusBadge badge tests**
  The four tests in `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js:19-59`
  for `disqualified`, `abandoned`, `in_progress`, and `transferred_without_opportunity` were
  written after `ConversationStatusBadge.vue` was fully implemented (cycle 27 created all five
  status entries at once); cycles 28–31 record no failure output.
  Fix: delete the `STATUS_CONFIG` entries for the four statuses (keeping only `qualified`) before
  running each test, observe failure, restore. Record the failure output in `tdd/cycle-log.md`
  as a retroactive red entry for each, or re-split the badge component implementation so each
  status is added one cycle at a time going forward.
  Verify: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js`
  passes after each retroactive red is documented.

- [X] TR002 **[F5] Assert specific alert message in U42 missing-ID warning test**
  `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js:278`:
  `expect(mockUseAlert).toHaveBeenCalled()` does not verify the alert message; a wrong i18n
  key passes silently.
  Fix: change to `expect(mockUseAlert).toHaveBeenCalledWith(expect.stringContaining('INVALID_ID'))` or
  use `withFullI18n()` and assert the translated Portuguese/English string.
  Verify: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js -t "missing conversation ID"`

- [X] TR003 **[F5] Assert specific alert message in U43 popup-blocked warning test**
  `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js:290`:
  same vacuous-assertion problem for the blocked-popup path.
  Fix: `expect(mockUseAlert).toHaveBeenCalledWith(expect.stringContaining('POPUP_BLOCKED'))`.
  Verify: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js -t "popup is blocked"`

- [X] TR004 **[F6] Replace vacuous `toBeDefined()` on timezoneOffset prop**
  `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js:137`:
  `expect(section.props('timezoneOffset')).toBeDefined()` always passes.
  Fix: assert a specific expected value, e.g.
  `expect(section.props('timezoneOffset')).toBe(String(-(new Date().getTimezoneOffset() / 60)))`.
  Verify: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js -t "embeds RecentConversationsSection"`

### MED findings (should fix before merge)

- [X] TR005 **[F7] Replace re-implemented ordering assertion in U20**
  `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb:794`:
  `expect(start_times).to eq(start_times.sort.reverse)` is self-referential.
  Fix: assert the specific conversation IDs in expected order, e.g.
  `expect(convs.map { |c| c['id'] }).to eq([c_new.id, c_old.id])`.
  Verify: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb -e "chronologically"`

- [X] TR006 **[F8] Replace loose inequality bounds in U21 status counts test**
  `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb:806-808`:
  `counts['qualified'].to be >= 1` is non-deterministic across fixture contexts.
  Fix: assert exact counts matching the before-block setup (1 qualified, 1 disqualified).
  Verify: same file `-e "status_counts"`.

- [X] TR007 **[F9] Split U8 valid-status assertion roulette into per-status examples**
  `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb:589-596`:
  a loop testing 6 statuses in one `it` block hides which status failed.
  Fix: use `%w[...].each { |st| it "accepts #{st} status" { ... } }` or individual `it` blocks.
  Verify: same file `-e "valid status"`.

- [X] TR008 **[F10] Complete filter-pill assertions for all 6 pills**
  `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js:103-110`:
  only 3 of 6 filter pills are asserted.
  Fix: add assertions for `Abandoned`, `In Progress`, and `Transferred without opportunity` pills
  with their expected counts from `mockConversationsResponse.data.status_counts`.
  Verify: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js -t "6 filter pills"`

---

## Phase 7: TDD Remediation (Round 2)

Non-blocking findings identified in verification pass (`PASS_WITH_GAPS`). Can be addressed before merge.

### MED findings (recommended before merge)

- [ ] TR009 **[Finding 1] Remove framework inheritance assertions in ApiClient spec**
  `app/javascript/dashboard/api/specs/scoutOverviewReports.spec.js:6-10`:
  `expect(scoutOverviewReportsAPI).toBeInstanceOf(ApiClient)` and `toHaveProperty('get')` test framework inheritance rather than feature behavior.
  Fix: remove inheritance test or replace with contract assertion on API endpoint structure.
  Verify: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/api/specs/scoutOverviewReports.spec.js`

### LOW findings (optional polish)

- [ ] TR010 **[Finding 2] Disambiguate duplicate `(U44)` tag in ScoutOverview spec**
  `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js:109`:
  Line 109 carries `(U44)` from feature 072, creating duplicate tag ambiguity with line 127 (`(U44, A1)`).
  Fix: remove or update the `(U44)` label on line 109 to match feature 072 behavior nomenclature.
  Verify: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js`
