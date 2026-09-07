# Tasks: Scout Follow-Up Nudges and Rescue Handoff

**Input**: Design documents from `/specs/062-scout-follow-up-rescue-handoff/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/scouts-api.md`, `quickstart.md`

## Format: `[ID] [P?] [Story] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g., [US1], [US2], [US3], [US4])
- Every task includes exact file paths

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure verification

- [X] T001 Verify container environment and database status for custom Scout module via `docker compose ps` and `docker compose exec rails bundle exec rails db:migrate:status`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core database schema, model associations, parameter contracts, and background job scheduling that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 [P] Create migration `db/migrate/21260907000000_add_rescue_stage_and_follow_up_delays_to_ichatr_scouts.rb` with up/down methods adding `rescue_stage_id` (bigint FK with on_delete: :nullify) and `follow_up_delays_hours` (jsonb default `[2, 12, 24]`)
- [X] T003 Run database migration in development and test environments using `docker compose exec rails bundle exec rails db:migrate`
- [X] T004 [P] Add `rescue_stage` association and `follow_up_delays_hours` validation (array of exactly 3 strictly ascending, unique, positive integers — length fixed so attempt count can't drift from FR-004's "2 nudges then handoff") in `custom/app/models/scout.rb`
- [X] T005 [P] Permit `:rescue_stage_id` and `follow_up_delays_hours: []` in `custom/app/controllers/api/v1/accounts/scouts_controller.rb`
- [X] T006 [P] Add unit specs for `rescue_stage` association and `follow_up_delays_hours` validation in `custom/spec/models/scout_spec.rb`, including rejection of arrays with fewer or more than 3 values
- [X] T007 [P] Add controller specs for `rescue_stage_id` and `follow_up_delays_hours` request parameters in `custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb`
- [X] T008 Add cron job entry for `custom_scout_follow_up_job` (`*/30 * * * *`, class: `Custom::Scout::FollowUpJob`, queue: `scheduled_jobs`) in `config/schedule.yml`
- [X] T009 Verify schedule config spec passes for new cron job in `spec/configs/schedule_spec.rb`

**Checkpoint**: Foundation ready - core schema, Scout attributes, permitted params, validations, and cron schedule in place. User story implementation can now begin.

---

## Phase 3: User Story 1 - Contact receives a re-engagement check-in after going silent (Priority: P1) 🎯 MVP

**Goal**: Automatically send up to two re-engagement check-in messages to a contact who has gone silent in a pending Scout conversation, respecting configured silence thresholds.

**Independent Test**: Leave a Scout conversation without a reply past the first configured silence threshold (default: 2 hours) and confirm the contact receives exactly one check-in message with `content_attributes['scout_follow_up'] == true`; confirm a second message arrives past the second threshold (default: 12 hours) if still unanswered; confirm no further check-in if the contact replies, if the Scout has no `rescue_stage_id` configured (FR-007), or if the conversation has no open linked opportunity (FR-010).

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T010 [P] [US1] Add unit and job specs in `custom/spec/jobs/custom/scout/follow_up_job_spec.rb` for nudge 1 and 2 delivery, silence threshold calculation, attempt count derivation from message history (`content_attributes['scout_follow_up']`), contact reply reset, pre-send pending race check, skipping the entire Scout when `rescue_stage_id` is blank (FR-007), and skipping a conversation with no open linked opportunity (FR-010)
- [X] T011 [P] [US1] Add service spec in `custom/spec/services/custom/scout/agent_runner_spec.rb` for `process_audited_reply` race window re-checking `conversation_pending?` after response auditor execution

### Implementation for User Story 1

- [X] T012 [P] [US1] Add i18n copy keys for `conversations.scout.follow_up_nudge` in `config/locales/en.yml` and `config/locales/pt_BR.yml`
- [X] T013 [P] [US1] Add post-audit `return unless conversation_pending?` race condition guard in `custom/app/services/custom/scout/agent_runner.rb`
- [X] T014 [US1] Implement `Custom::Scout::FollowUpJob` class in `custom/app/jobs/custom/scout/follow_up_job.rb`: skip the whole Scout when `rescue_stage_id` is blank (FR-007), scan its pending conversations, skip any conversation with no open linked opportunity (FR-010), derive trailing attempt count from messages, check silence thresholds against `last_activity_at`, perform uncached `conversation.pending?` pre-check, and send nudge messages with `content_attributes: { scout_follow_up: true }`. These two skip guards run before the threshold check so they apply equally to nudges and to the rescue handoff added in Phase 4 — they are not handoff-specific.

**Checkpoint**: User Story 1 is functional - silent conversations receive automated nudges at configured intervals, stop when a contact replies or takes over, and never fire for Scouts without a rescue stage configured or for conversations with no open deal.

---

## Phase 4: User Story 2 - Unresponsive contact is handed off to a human with the deal flagged for follow-up (Priority: P1)

**Goal**: Release conversations that remain silent past the final silence threshold to human attendance via `Custom::Scout::HandoffService` and move the linked open opportunity to the configured rescue stage.

**Independent Test**: Leave a conversation silent through both re-engagement messages and past the final configured silence threshold (default: 24 hours); confirm the conversation is handed off with a continuity-of-care message and private note, and the open opportunity's pipeline stage updates to `scout.rescue_stage_id` without altering opportunity status. (The `rescue_stage_id`-blank and no-open-deal skip guards are already in place from User Story 1/T014 — this story only adds the handoff-specific behavior below.)

### Tests for User Story 2

- [X] T015 [P] [US2] Add job specs in `custom/spec/jobs/custom/scout/follow_up_job_spec.rb` verifying rescue handoff at final threshold, opportunity stage move to `rescue_stage_id`, and opportunity status retention (remains open, never set to won/lost by this job)

### Implementation for User Story 2

- [X] T016 [P] [US2] Add i18n copy keys for `conversations.scout.follow_up_handoff` in `config/locales/en.yml` and `config/locales/pt_BR.yml` conveying continuity of care without blaming contact silence
- [X] T017 [US2] Implement rescue handoff logic in `custom/app/jobs/custom/scout/follow_up_job.rb` to move linked open `Opportunity#pipeline_stage_id` to `scout.rescue_stage_id` and invoke `Custom::Scout::HandoffService` with the dedicated rescue handoff message and private note, once the final threshold is reached (relies on the T014 guards for `rescue_stage_id` presence and open-deal linkage — no need to re-check them here)

**Checkpoint**: User Story 2 is functional - unresponsive contacts are handed off to humans, private notes explain context, and open deals transition to the rescue stage.

---

## Phase 5: User Story 3 - Automated outreach respects the inbox's business hours (Priority: P2)

**Goal**: Protect contact experience by suppressing automated nudges and rescue handoffs outside inbox business hours, re-evaluating when business hours resume.

**Independent Test**: Configure inbox business hours to exclude current time, let a pending conversation reach a silence threshold, run the job, and verify no message or handoff is sent; confirm outreach proceeds normally once business hours resume.

### Tests for User Story 3

- [X] T018 [P] [US3] Add job specs in `custom/spec/jobs/custom/scout/follow_up_job_spec.rb` testing that `conversation.inbox.out_of_office?` suppresses nudge and handoff actions and allows outreach once business hours resume

### Implementation for User Story 3

- [X] T019 [US3] Add business hours check `conversation.inbox.out_of_office?` (from `OutOfOffisable`) in `custom/app/jobs/custom/scout/follow_up_job.rb` to skip processing during off-hours without dropping the pending attempt

**Checkpoint**: User Story 3 is functional - no outreach occurs outside operating hours, preserving brand tone.

---

## Phase 6: User Story 4 - Staff can spot Scout-owned conversations awaiting a reply directly on the deal board (Priority: P3)

**Goal**: Display a visible "Scout" badge on opportunity cards on the Kanban deal board when the active conversation is pending with an enabled Scout, and clear it once handed off.

**Independent Test**: View the deal board for an opportunity whose active conversation is pending on an enabled Scout inbox and confirm a "Scout" badge appears on its card; hand off the conversation (manually or automatically) and confirm the badge disappears.

### Tests for User Story 4

- [X] T020 [P] [US4] Add model specs in `spec/models/opportunity_spec.rb` verifying `scout_engaged?` returns true when active conversation is pending with an enabled Scout, false otherwise, and verify `Opportunity#as_json` includes `'scout_engaged'`
- [X] T021 [P] [US4] Add component unit tests in `app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js` for rendering and omitting the "Scout" badge based on `opportunity.scout_engaged`

### Implementation for User Story 4

- [X] T022 [P] [US4] Implement `scout_engaged?` helper and serialize `'scout_engaged' => scout_engaged?` in `Opportunity#as_json` in `custom/app/models/opportunity.rb`
- [X] T023 [P] [US4] Add frontend i18n key `OPPORTUNITIES.BOARD.SCOUT_BADGE` in `app/javascript/dashboard/i18n/locale/en/opportunities.json` and `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`
- [X] T024 [US4] Update `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` to render the "Scout" badge conditionally via `v-if="opportunity.scout_engaged"`

**Checkpoint**: User Story 4 is functional - deal board cards display the Scout badge for pending conversations and clear it immediately upon handoff.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Verification, linting, hook auditing, and test suite validation across all modified files

- [X] T025 [P] Run backend RSpec test suite covering all custom and modified modules via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/jobs/custom/scout/follow_up_job_spec.rb custom/spec/services/custom/scout/agent_runner_spec.rb custom/spec/models/scout_spec.rb custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb spec/models/opportunity_spec.rb spec/configs/schedule_spec.rb`
- [X] T026 [P] Run frontend Vitest test suite via `docker compose exec vite pnpm test -- KanbanCard`
- [X] T027 [P] Run RuboCop linting on backend files via `docker compose exec rails bundle exec rubocop custom/app/models/scout.rb custom/app/controllers/api/v1/accounts/scouts_controller.rb custom/app/jobs/custom/scout/follow_up_job.rb custom/app/services/custom/scout/agent_runner.rb custom/app/models/opportunity.rb db/migrate/21260907000000_add_rescue_stage_and_follow_up_delays_to_ichatr_scouts.rb`
- [X] T028 [P] Run ESLint on frontend files via `docker compose exec vite pnpm eslint app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js`
- [X] T029 Run sync-custom-module-hooks audit via `docker compose exec rails ruby bin/sync-custom-module-hooks --check`
- [X] T030 Validate manual verification scenarios against `specs/062-scout-follow-up-rescue-handoff/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion (Phase 2)
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) and integrates with `FollowUpJob` from User Story 1
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) and integrates with `FollowUpJob` from User Story 1
- **User Story 4 (Phase 6)**: Depends on Foundational (Phase 2) - independent from US1-US3 job logic (touches `Opportunity` and `KanbanCard.vue`)
- **Polish (Phase 7)**: Depends on all user stories (Phases 3-6) being complete

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Foundational. Delivers core nudge capabilities, the `FollowUpJob` foundation, and the `rescue_stage_id`/open-deal skip guards (FR-007, FR-010) that also protect the handoff added in US2.
- **User Story 2 (P1)**: Extends `FollowUpJob` from US1 with rescue stage change and handoff logic; reuses US1's skip guards rather than re-implementing them.
- **User Story 3 (P2)**: Adds business-hours filtering to `FollowUpJob` from US1.
- **User Story 4 (P3)**: Completely decoupled from `FollowUpJob` logic; can be developed in parallel with US1-US3 once Foundational (Phase 2) is complete.

### Within Each User Story

- Tests written and verified failing before implementation
- Models and migrations before services and jobs
- Services/jobs before API exposure or UI components
- Story validated independently before advancing to the next priority

### Parallel Opportunities

- **Phase 2**: T004 (Scout model), T005 (ScoutsController), T006 (Scout spec), T007 (Controller spec) can all be authored in parallel once migration T002/T003 runs.
- **Phase 3**: T010 (job specs), T011 (agent runner spec), T012 (i18n locales), T013 (agent runner guard) can be developed in parallel before T014.
- **Phase 4**: T015 (job rescue specs) and T016 (handoff i18n locales) can be authored in parallel before T017.
- **Phase 5**: T018 (business hours specs) can be written in parallel with T019 implementation.
- **Phase 6**: T020 (backend spec), T021 (frontend spec), T022 (backend model), and T023 (frontend i18n) can all proceed in parallel before T024.
- **Phase 7**: T025, T026, T027, T028 can be run in parallel across testing and linting targets.

---

## Parallel Example: User Story 1

```bash
# Author test specs and locale entries in parallel:
Task T010: "Add unit and job specs in custom/spec/jobs/custom/scout/follow_up_job_spec.rb"
Task T011: "Add service spec in custom/spec/services/custom/scout/agent_runner_spec.rb"
Task T012: "Add i18n copy keys in config/locales/en.yml and config/locales/pt_BR.yml"
Task T013: "Add post-audit guard in custom/app/services/custom/scout/agent_runner.rb"
```

## Parallel Example: User Story 4

```bash
# Backend and frontend work can proceed concurrently:
Task T020: "Add model specs in spec/models/opportunity_spec.rb"
Task T021: "Add component unit tests in app/javascript/dashboard/components-next/Opportunities/specs/KanbanCard.spec.js"
Task T022: "Implement scout_engaged? in custom/app/models/opportunity.rb"
Task T023: "Add frontend i18n keys in app/javascript/dashboard/i18n/locale/{en,pt_BR}/opportunities.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (environment check)
2. Complete Phase 2: Foundational (migration, Scout model, controller params, schedule cron entry)
3. Complete Phase 3: User Story 1 (nudge 1 and 2 logic, silence detection, attempt counting, pending race guard, `rescue_stage_id`/open-deal skip guards)
4. **STOP and VALIDATE**: Verify User Story 1 via RSpec and `quickstart.md` Step 2 & 3.
5. Deploy/demo initial automated nudge behavior.

### Incremental Delivery

1. Phase 1 + Phase 2 → Database and base configuration ready
2. Phase 3 (US1) → Automated re-engagement nudges active (MVP!)
3. Phase 4 (US2) → Rescue handoff and opportunity stage transition to rescue stage active
4. Phase 5 (US3) → Out-of-office respect added to protect brand reputation
5. Phase 6 (US4) → Visual badge on Kanban board provides immediate staff clarity
6. Phase 7 (Polish) → Full test pass, linting, and synchronization audit

---

## Phase 8: Convergence

**Purpose**: Close a gap found by `/speckit-converge` between the implemented behavior and the spec's timing guarantees, verified empirically against the running code (not just static review).

- [X] T031 [CRITICAL] Fix `Custom::Scout::FollowUpJob#process_conversation` (`custom/app/jobs/custom/scout/follow_up_job.rb`) so silence-threshold comparisons are measured from the conversation's last non-follow-up activity instead of `conversation.last_activity_at`. Core `Message#set_conversation_activity` (`app/models/message.rb:456-459`) resets `last_activity_at` to "now" on every message, including the job's own nudges (confirmed via `rails runner` against a real job run: after nudge 1, silence resets from 3h to 0h) — so each subsequent threshold silently compounds off the previous nudge's send time instead of the original silence point, meaning the default `[2, 12, 24]` schedule actually takes ~38 total hours of silence to reach handoff instead of the specified 24h cap. Derive the reference timestamp from the created_at of the last message that is not itself a `scout_follow_up` nudge (mirroring the existing `follow_up_attempts` message traversal) and use it in place of `conversation.last_activity_at` for the per-conversation threshold check. Add a regression test to `custom/spec/jobs/custom/scout/follow_up_job_spec.rb` that sends nudge 1 via a real `Custom::Scout::FollowUpJob.perform_now` call, time-travels forward, and runs the job again *without* manually overriding `last_activity_at` afterward, asserting nudge 2 fires based on total original silence rather than time-since-nudge-1 — the current "second threshold" test masks this bug by forcing `last_activity_at` directly after manually creating messages, bypassing the real job-driven flow. per FR-002, FR-003, SC-002 (contradicts)
- [X] T032 [HIGH] Update `Opportunity#scout_engaged?` in `custom/app/models/opportunity.rb` so it evaluates `active_conversation || origin_conversation` rather than solely `active_conversation`, ensuring in-progress opportunities linked to pending Scout conversations receive the "Scout" badge on the Kanban deal board in real functional environments where `active_conversation_id` remains nil until human handoff. Add unit tests in `spec/models/opportunity_spec.rb` verifying `scout_engaged?` returns true for opportunities whose `origin_conversation` is pending with an enabled Scout even when `active_conversation_id` is nil. per US4/AC1 (partial)
- [X] T033 [HIGH] Reported directly by the user: T032's `active_conversation || origin_conversation` fallback still misses real multi-conversation deals where the currently-`pending` conversation is linked via `opportunity_conversations` but is neither the `active_conversation` (only promoted when a conversation is attached while `open?`, see `attach_conversation!` in `custom/app/models/custom/concerns/opportunity_conversation_management.rb`) nor the `origin_conversation` (may be long resolved). Replace `scout_engaged?` in `custom/app/models/opportunity.rb` with `conversations.pending.any? { |conv| conv.inbox&.scout&.enabled? }`, checking every conversation ever linked to the deal instead of just the two special pointers. Updated `spec/models/opportunity_spec.rb`: rebuilt the fixture to link via `origin_conversation:` (matching how real data is populated, including the historical backfill migration `db/migrate/21260817120000_create_ichatr_opportunity_conversations.rb`), and added a case covering a pending conversation attached via `attach_conversation!(other_conversation, set_active: false)` that is neither active nor origin. Verified empirically: 25/25 examples pass in `spec/models/opportunity_spec.rb` and 105/105 across the full feature suite. per US4/AC1, data-model.md `scout_engaged?` (contradicts)
- [X] T034 [MEDIUM] Reported directly by the user (with a screenshot from a real dark-theme board): the "Scout" badge in `KanbanCard.vue` rendered with no visible background/text color. Root cause: `bg-n-brand-3`/`text-n-brand-11` don't exist as Tailwind utilities — `n-brand` (`theme/colors.js`) is a single flat color (`#2781F6`), not a numbered 1-12 scale, unlike `n-blue`/`n-slate`/etc., which are real CSS-variable-backed, theme-aware scales. A follow-up attempt to add a small `i-lucide-bot` icon prefix inside the badge was also rejected by the user as illegible at 10px and redundant next to the "Scout" text label. Reverted to a text-only badge using the valid `bg-n-blue-3 text-n-blue-11` tokens (matching the original design reference in `docs/kanban/ciclo 10/scout/22-scout-follow-up-nudges-and-rescue-handoff/spec85.md`). Verified: ESLint 0 errors, Vitest 4/4 passing in `KanbanCard.spec.js`. per FR-013 (contradicts)
