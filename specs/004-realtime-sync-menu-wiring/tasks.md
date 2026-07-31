# Tasks: Realtime Sync & Menu/Route Wiring

**Input**: Design documents from `/specs/004-realtime-sync-menu-wiring/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included — spec.md's User Story acceptance scenarios and quickstart.md map directly to
rspec/vitest test tasks; this feature's Constitution Check requires safe/reversible change
management, so tests are written before the corresponding implementation per story.

**Organization**: Tasks are grouped by user story (US1 = P1 live sync, US2 = P2 discoverability,
US3 = P3 sync tooling) so each can be implemented and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1, US2, or US3
- Paths are repo-root-relative; this is a single Rails+Vue monorepo (no `frontend/`/`backend/` split)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the audited baseline from `research.md` §6 before making any new edits.

- [x] T001 Run `git diff --stat develop...HEAD -- app/javascript custom` and confirm the 7
  already-committed wiring points listed in `research.md` §6 are present, and that
  `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`,
  `app/javascript/dashboard/helper/actionCable.js`, and the Sidebar main-nav entry in
  `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` are still missing

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No shared blocking infrastructure is required — `Opportunity`, `PipelineStage`, the
`opportunities`/`pipelineStages` Vuex modules, `ActionCableBroadcastJob`, and `RoomChannel` all
already exist from Phases 1-3 (see `data-model.md`). This phase is intentionally empty; proceed
directly to User Story 1.

**Checkpoint**: Foundation already in place — user story implementation can begin immediately.

---

## Phase 3: User Story 1 - Kanban board updates live across sessions (Priority: P1) 🎯 MVP

**Goal**: Broadcast an `opportunity_updated` ActionCable event on every Opportunity create/update
over the existing `account_#{account_id}` stream, and have the frontend Kanban board consume it to
update in place.

**Independent Test**: Open the board in two sessions on the same account, drag a card to a new
stage in one session, and confirm the second session's board updates without a manual refresh
(quickstart.md steps 1-2 and 6.4).

### Tests for User Story 1

- [x] T002 [P] [US1] Write rspec spec in `spec/models/opportunity_spec.rb` asserting that creating
  and updating an `Opportunity` causes `ActionCableBroadcastJob` to receive `perform_later` with
  `["account_#{account.id}"]`, `'opportunity_updated'`, and a payload hash containing `id`,
  `pipeline_stage_id`, `status`, `contact_id`, `assignee_id`, `updated_at`, `account_id`
  (contracts/opportunity_updated_event.md; testing pattern per research.md §8) — confirm it FAILS
  before implementation
- [x] T003 [P] [US1] Write vitest spec in
  `app/javascript/dashboard/helper/specs/actionCable.spec.js` feeding an `opportunity_updated`
  payload into the ActionCable helper and asserting the `opportunities` Vuex module's
  `cardIdsByStage` and `cardsById` update in place (contracts/opportunity_updated_event.md
  Consumer contract) — confirm it FAILS before implementation

### Implementation for User Story 1

- [x] T004 [US1] Add `after_commit on: %i[create update]` callback to
  `custom/app/models/opportunity.rb` that builds the payload hash (`id`, `pipeline_stage_id`,
  `status`, `contact_id`, `assignee_id`, `updated_at`, `account_id`) and calls
  `ActionCableBroadcastJob.perform_later(["account_#{account_id}"], 'opportunity_updated', payload)`
  directly — no dispatcher/listener/Events::Types changes (research.md §2) — makes T002 pass
- [x] T005 [US1] Add `'opportunity_updated': this.onOpportunityUpdated,` entry to `this.events` in
  `app/javascript/dashboard/helper/actionCable.js`, immediately adjacent to the existing
  `'conversation.updated': this.onConversationUpdated,` line (research.md §5)
- [x] T006 [US1] Implement `onOpportunityUpdated` handler in
  `app/javascript/dashboard/helper/actionCable.js` dispatching the existing Phase 3
  `opportunities/updateOpportunity` Vuex action with the event payload, reusing the mutation that
  moves the card between `cardIdsByStage` arrays and upserts `cardsById[id]` — makes T003 pass

**Checkpoint**: User Story 1 is fully functional and independently testable — live updates work
even before US2's navigation entry exists (reachable via direct URL for testing).

---

## Phase 4: User Story 2 - Agents can discover and reach the Kanban board (Priority: P2)

**Goal**: Add a main-navigation entry and a `dashboard.routes.js` route so agents on
feature-flagged accounts can open the board; Pipeline Stages settings remains admin-only
(already wired in Phase 3).

**Independent Test**: Enable the Kanban feature for a test account, log in, confirm a navigation
entry appears and leads to the board; confirm the entry is absent for an account without the
feature enabled; confirm a non-admin agent does not see the Pipeline Stages settings entry
(quickstart.md step 6.1-6.3).

### Tests for User Story 2

- [x] T007 [P] [US2] Write vitest spec for `Sidebar.vue` asserting the Kanban main-nav entry
  renders when `hasOpportunities`/`FEATURE_FLAGS.OPPORTUNITIES` is enabled for the account and is
  absent from the rendered menu when the flag is disabled (spec.md US2 Acceptance Scenario 2,
  SC-003) — confirm it FAILS before implementation
- [x] T008 [P] [US2] Write rspec request/routing spec asserting `opportunities_index` is reachable
  by `administrator`, `agent`, and `custom_role` sessions, and that `pipeline_stages_index` remains
  reachable only by `administrator` sessions (spec.md US2 Acceptance Scenarios 3-4, FR-007) —
  confirm it FAILS before implementation

### Implementation for User Story 2

- [x] T009 [US2] Add `opportunities_index` route to
  `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` (directly into the
  `accounts/:accountId` children array, importing `KanbanBoard.vue` from
  `dashboard/components-next/Opportunities/KanbanBoard.vue` and gating it with
  `FEATURE_FLAGS.OPPORTUNITIES`) — makes routing tests pass
- [x] T010 [US2] Add a main-navigation menu entry linking to `opportunities_index` in
  `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, gated on the existing
  `hasOpportunities`/`FEATURE_FLAGS.OPPORTUNITIES` computed pattern already used for the Settings
  › Pipeline Stages sub-entry (distinct from that existing admin-only settings entry — this is the
  board's own main-nav entry, visible to any agent per FR-005) — makes T007 pass

**Checkpoint**: User Stories 1 AND 2 both work independently — the board is discoverable and live
updates work end-to-end.

---

## Phase 5: User Story 3 - Maintainers can safely re-apply all shared-file wiring after every upstream update (Priority: P3)

**Goal**: Build `bin/sync-custom-module-hooks`, an idempotent, fail-fast, anchor-based CLI whose
manifest covers all ~9 wiring points from this and prior phases (2 new from US1/US2, plus the 7
already-committed reachability and automation-integration files per FR-014).

**Independent Test**: Run `--check` on the already-wired checkout and confirm all wiring points
report present; run `--apply` twice and confirm the second run makes no changes; deliberately break
one anchor and confirm `--check`/`--apply` fails loudly naming the file and anchor (quickstart.md
steps 3-5).

### Tests for User Story 3

- [x] T011 [P] [US3] Write rspec spec in `spec/bin/sync_custom_module_hooks_spec.rb` covering:
  `--check` on a clean checkout reports all manifest entries `present` and exits `0`; `--apply` on a
  checkout missing an entry inserts it and is idempotent on a second run (no diff); an entry whose
  `anchor` is not found produces a non-zero exit and an error naming the file and anchor, without
  applying that file's remaining entries, while still processing other files (contracts/sync-script-cli.md)
  — confirm it FAILS before implementation

### Implementation for User Story 3

- [x] T012 [US3] Create `bin/sync-custom-module-hooks` with the manifest array (`file:`, `anchor:`,
  `insert:`, optional `indent:`) containing entries for the 2 new US1/US2 wiring points
  (`actionCable.js` opportunity_updated entry, `dashboard.routes.js` opportunities_index route,
  Sidebar.vue main-nav entry) plus the 7 already-committed wiring points identified in
  research.md §6: `Sidebar.vue` (Settings › Pipeline Stages entry), `settings.routes.js`
  (Pipeline Stages route), `store/index.js` (opportunities/pipelineStages module registration),
  `featureFlags.js`, `composables/useAutomationValues.js`, `helper/automationHelper.js`,
  `routes/dashboard/settings/automation/constants.js`, `i18n/locale/en/index.js`,
  `i18n/locale/en/automation.json`, `i18n/locale/en/settings.json` (data-model.md "Wiring point")
- [x] T013 [US3] Implement `--check` mode in `bin/sync-custom-module-hooks`: for each manifest
  entry, report `present`/`missing`/`anchor_not_found`; never write; exit `0` only if all entries
  are `present` (contracts/sync-script-cli.md) — makes T011's `--check` assertions pass
- [x] T014 [US3] Implement `--apply` mode (default) in `bin/sync-custom-module-hooks`: skip entries
  already `present`; insert `insert` adjacent to `anchor` for `missing` entries and write the file;
  on `anchor_not_found`, record a failure for that file, skip that file's remaining entries, but
  continue processing other files; exit non-zero if any entry ended `anchor_not_found`
  (contracts/sync-script-cli.md) — makes T011's `--apply`/idempotency/fail-fast assertions pass
- [x] T015 [US3] Ensure `bin/sync-custom-module-hooks` stderr output on `anchor_not_found` includes
  the exact file path and anchor string (contracts/sync-script-cli.md Output contract) and stdout
  on a clean `--check` ends with `All N wiring points present.`

**Checkpoint**: All user stories are independently functional; the sync script's manifest is the
single reviewable source of truth for every wiring edit made across Phases 1-4.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all three stories.

- [x] T016 [P] Run `docker compose exec rails bundle exec rubocop -a custom/app/models/opportunity.rb bin/sync-custom-module-hooks spec/models/opportunity_spec.rb spec/bin/sync_custom_module_hooks_spec.rb`
- [x] T017 [P] Run `docker compose exec vite pnpm eslint:fix` on the modified JS/Vue files
  (`actionCable.js`, `Sidebar.vue`, `dashboard.routes.js`, `actionCable.spec.js`)
- [x] T018 Execute quickstart.md end-to-end: sections 1-5 (automated) and section 6 (manual
  two-session live-update verification, admin vs. non-admin Pipeline Stages visibility). Note:
  section 6.4's "within a few seconds" check is a qualitative smoke test of SC-001's 5s target,
  not a stopwatch-precise measurement — the 5s figure is inherited from the existing
  `ActionCableBroadcastJob`/`:critical` queue latency (see plan.md Performance Goals) and is not
  independently re-benchmarked by this feature.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — run first to confirm the audited baseline
- **Foundational (Phase 2)**: Empty — no blocking prerequisites for this feature
- **User Story 1 (Phase 3)**: Can start immediately after Setup — no dependency on US2/US3
- **User Story 2 (Phase 4)**: Can start immediately after Setup — independent of US1 (the board
  route can be added regardless of whether live sync is wired yet), though both are needed for the
  full end-to-end quickstart section 6
- **User Story 3 (Phase 5)**: Can start immediately after Setup for the script's mechanics (T011-T015),
  but its manifest content for the 2 new wiring points depends on US1 (T005) and US2 (T009, T010)
  having landed first, since the manifest's `anchor`/`insert` values must match the real code
- **Polish (Phase 6)**: Depends on all three user stories being complete

### Within Each User Story

- Tests (T002/T003, T007/T008, T011) MUST be written and FAIL before their corresponding
  implementation tasks
- US1: T004 (backend) and T005-T006 (frontend) are independent of each other, both depend on their
  respective tests
- US2: T009 (route) and T010 (nav entry) are independent of each other, both depend on their
  respective tests (T008, T007)
- US3: T012 (manifest) before T013/T014 (check/apply logic) before T015 (output polish)

### Parallel Opportunities

- T002 and T003 (US1 tests, different files) in parallel
- T004 (backend) and T005-T006 (frontend) in parallel once T002/T003 exist, since they touch
  different files
- T007 and T008 (US2 tests, different files) in parallel
- T009 and T010 (US2 implementation, different files) in parallel once T007/T008 exist
- T011 (US3 test) can be written in parallel with US1/US2 work, though T012's manifest content
  for the 2 new entries must wait on US1/US2 landing
- T016 and T017 (Polish, different toolchains) in parallel

---

## Parallel Example: User Story 1

```bash
# Launch both US1 tests together:
Task: "Write rspec spec in spec/models/opportunity_spec.rb for opportunity_updated broadcast"
Task: "Write vitest spec in app/javascript/dashboard/helper/specs/actionCable.spec.js for opportunity_updated handling"

# Then launch backend and frontend implementation together:
Task: "Add after_commit broadcast callback to custom/app/models/opportunity.rb"
Task: "Add opportunity_updated event entry + handler to app/javascript/dashboard/helper/actionCable.js"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (confirm baseline)
2. Phase 2: Foundational is empty — skip
3. Complete Phase 3: User Story 1 (live broadcast + frontend handling)
4. **STOP and VALIDATE**: run quickstart.md steps 1-2; verify live sync via direct board URL even
   without a nav entry yet
5. This is the MVP — live sync is the core value proposition per spec.md's User Story 1 priority

### Incremental Delivery

1. Setup → Phase 3 (US1) → validate independently → live sync works (MVP)
2. Add Phase 4 (US2) → validate independently → board is discoverable via navigation, hidden when
   the feature flag is off, and Pipeline Stages stays admin-only (T007/T008)
3. Add Phase 5 (US3) → validate independently → sync script protects all wiring going forward
4. Phase 6 → final polish and full quickstart validation

### Parallel Team Strategy

With multiple developers, after Phase 1 Setup:
- Developer A: User Story 1 (backend broadcast + frontend handler)
- Developer B: User Story 2 (nav-visibility/permission tests, route + nav entry)
- Developer C: starts User Story 3's script mechanics (T011-T014 skeleton/tests), finalizing the
  manifest's 2 new entries once A and B land

## Phase 7: Convergence

- [X] T019 Update sync script manifest anchors and inserts for `actionCable.js` and `Sidebar.vue` to match the linter-formatted codebase per FR-009, FR-012, FR-013 (partial)
