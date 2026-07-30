---
description: "Task list for Kanban Backend Core — Opportunities & Pipeline Stages"
---

# Tasks: Kanban Backend Core — Opportunities & Pipeline Stages

**Input**: Design documents from `/specs/001-kanban-backend-core/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/opportunities-api.md, quickstart.md

**Tests**: Included — the source design doc's Completion Criteria explicitly requires
`rspec` coverage (policy specs, request specs, model spec) as the verification mechanism for
this UI-less phase.

**Organization**: Tasks are grouped by user story (US1/US2/US3, per spec.md priorities) so each
can be implemented and independently tested.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- All commands run inside the `rails` container: `docker compose exec rails <command>`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Wire the isolated `custom/` module and its feature flag into the app (FR-001, FR-012)

- [X] T001 [P] Add `config.eager_load_paths << Rails.root.join('custom/lib')` and
  `config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]` to `config/application.rb`,
  placed immediately after the existing equivalent `enterprise/` lines
- [X] T002 [P] Add a new `- name: opportunities` entry to `config/features.yml` with
  `display_name: Opportunities (Kanban)`, `enabled: true`, `column: feature_flags_ext_1`
  (per the file's own header comment — `feature_flags` is full)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Data model, routing, and cross-cutting guards every user story depends on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Create migration `db/migrate/<timestamp>_create_matias_pipeline_stages.rb`
  (`create_table :matias_pipeline_stages` with `account_id:bigint` (indexed, FK to `accounts`),
  `name:string`, `position:integer`, timestamps)
- [X] T004 Create migration `db/migrate/<timestamp>_create_matias_opportunities.rb`
  (timestamp after T003's; `create_table :matias_opportunities` with `account_id:bigint`
  (indexed, FK), `contact_id:bigint` (indexed, FK to `contacts`, no uniqueness),
  `pipeline_stage_id:bigint` (indexed, FK to `matias_pipeline_stages`),
  `origin_conversation_id:bigint` (indexed, FK to `conversations`, nullable),
  `assignee_id:bigint` (indexed, FK to `users`, nullable), `title:string`, `status:integer`
  default 0, timestamps) — depends on T003
- [X] T005 Run `docker compose exec rails bundle exec rails db:migrate` and verify both
  `matias_pipeline_stages` and `matias_opportunities` tables exist per quickstart.md step 1 —
  depends on T003, T004
- [X] T006 [P] Create `PipelineStage` model in `custom/app/models/pipeline_stage.rb`
  (`belongs_to :account`, `has_many :opportunities, dependent: :restrict_with_error`,
  presence validation on `account_id`/`name`, default scope/`order(:position)`) — depends on T005
- [X] T007 [P] Create `Opportunity` model in `custom/app/models/opportunity.rb`
  (`belongs_to :account`, `:contact`, `:pipeline_stage`; `belongs_to :origin_conversation,
  class_name: 'Conversation', optional: true`; `belongs_to :assignee, class_name: 'User',
  optional: true`; `enum status: { open: 0, won: 1, lost: 2 }, default: :open`; presence
  validation on `title`/`contact_id`/`pipeline_stage_id`/`account_id`; custom validation
  rejecting a `pipeline_stage` whose `account_id` differs from the Opportunity's own) —
  depends on T005
- [X] T008 [P] Create `custom/app/models/custom/concerns/contact.rb` defining
  `module Custom::Concerns::Contact; extend ActiveSupport::Concern; included do
  has_many :opportunities, dependent: :destroy end; end` (auto-discovered by
  `Contact.include_mod_with('Concerns::Contact')`, already present at the bottom of
  `app/models/contact.rb` — zero edits to that file) — depends on T007
- [X] T009 Add `resources :pipeline_stages, only: [:index, :create, :update, :destroy]` and
  `resources :opportunities, only: [:index, :show, :create, :update, :destroy]` to the existing
  nested `accounts` resources block in `config/routes.rb` (alongside `resources :macros`) —
  depends on T006, T007
- [X] T010 [P] Create `custom/app/controllers/concerns/kanban_feature_guard.rb` — a controller
  concern with a `before_action` that renders a `403` JSON error unless
  `Current.account.feature_enabled?('opportunities')`, for reuse by both controllers (this exact
  status code is the contract asserted by T014/T020's feature-inactive test cases) —
  depends on T002
- [X] T011 [P] Verify `custom/` autoloading resolves both constants per quickstart.md step 2:
  `docker compose exec rails bundle exec rails runner "puts Opportunity"` and `"puts
  PipelineStage"` must not raise `NameError` — depends on T001, T006, T007

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - Administrator configures the account's pipeline (Priority: P1) 🎯 MVP

**Goal**: Admin-managed, ordered Pipeline Stages per account, with zero-config lazy default
seeding (FR-002, FR-005, FR-007, FR-009)

**Independent Test**: On an account with zero stages, call the stages `index` endpoint twice —
first call creates the two default stages, second call returns the same two without duplicating;
an admin can create/rename/reorder/delete stages, an agent cannot.

### Tests for User Story 1

- [X] T012 [P] [US1] Model spec in `spec/models/pipeline_stage_spec.rb` — presence validations,
  `position` ordering, destroy is rejected while an `Opportunity` still references the stage
- [X] T013 [P] [US1] Policy spec in `spec/policies/pipeline_stage_policy_spec.rb` — administrator
  allowed on all actions, agent denied on all actions
- [X] T014 [P] [US1] Request spec in
  `spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb` — `index` lazy-seeds exactly
  the two default stages and is idempotent on a second call; `create` never accepts a
  client-supplied `position`; `update`; `destroy` (including the reject-if-referenced case);
  admin-only enforcement on every action

### Implementation for User Story 1

- [X] T015 [US1] Create `PipelineStagePolicy` in
  `custom/app/policies/pipeline_stage_policy.rb`, mirroring
  `app/policies/custom_attribute_definition_policy.rb` (all actions →
  `@account_user.administrator?`)
- [X] T016 [US1] Implement lazy default-stage seeding on `PipelineStage` in
  `custom/app/models/pipeline_stage.rb` (e.g. `self.seed_defaults_for!(account)`), made
  concurrency-safe by wrapping the check-and-create in `account.with_lock` (same row-lock
  pattern already used in `app/models/campaign.rb`) so two simultaneous first-time requests
  cannot both pass the `account.pipeline_stages.exists?` check and double-seed: acquire the
  lock, re-check `exists?` inside it, and only then create "Leads Recebidos" then "Em Contato"
  with auto-assigned positions
- [X] T017 [US1] Implement position auto-assignment on `PipelineStage` create in
  `custom/app/models/pipeline_stage.rb` (`before_validation` sets `position` to
  `account.pipeline_stages.maximum(:position).to_i + 1` when blank)
- [X] T018 [US1] Create `PipelineStagesController` in
  `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`
  (`include KanbanFeatureGuard`; `index` calls the T016 seeding method then lists stages
  ordered by position; `create`/`update`/`destroy` with `check_authorization` via Pundit)

**Checkpoint**: User Story 1 fully functional and testable independently

---

## Phase 4: User Story 2 - Team tracks Opportunities tied to a Contact (Priority: P1)

**Goal**: Manual Opportunity CRUD tied to a Contact, movable across Pipeline Stages, with
`origin_conversation_id` immutable after creation (FR-003, FR-004, FR-008, FR-011)

**Independent Test**: Create an Opportunity via the API with only `contact_id` +
`pipeline_stage_id`; it persists, shows up in the Contact's Opportunities, can be moved to a
different stage/status/assignee, and any attempt to change `origin_conversation_id` afterward is
rejected.

### Tests for User Story 2

- [X] T019 [P] [US2] Model spec in `spec/models/opportunity_spec.rb` — presence validations,
  rejects a `pipeline_stage` from a different account, a Contact can have multiple simultaneous
  Opportunities, `status` is freely editable between `open`/`won`/`lost` in any direction
- [X] T020 [P] [US2] Request spec in
  `spec/requests/api/v1/accounts/opportunities_controller_spec.rb` — `create` with
  `contact_id`+`pipeline_stage_id`, appears under `contact.opportunities`; `update` of
  `pipeline_stage_id`/`title`/`assignee_id`/`status`; `update` attempting to change
  `origin_conversation_id` is rejected and the original value is retained; cross-account
  `pipeline_stage_id` is rejected

### Implementation for User Story 2

- [X] T021 [US2] Create baseline `OpportunityPolicy` in
  `custom/app/policies/opportunity_policy.rb` (`@account_user.administrator?` grants all
  actions; otherwise `record.assignee_id == user.id` grants `show?`/`update?`/`destroy?`) — full
  conversation-access rule added in US3 (T024)
- [X] T022 [US2] Create `OpportunitiesController` in
  `custom/app/controllers/api/v1/accounts/opportunities_controller.rb` (`include
  KanbanFeatureGuard`; `index`/`show`/`create`/`update`/`destroy` with `check_authorization`;
  `create` requires `contact_id` + `pipeline_stage_id`, accepts optional
  `origin_conversation_id` only here; `update`'s permitted params never include
  `origin_conversation_id`, so any attempt to pass it is silently ignored and the persisted
  value never changes)

**Checkpoint**: User Stories 1 AND 2 both work independently

---

## Phase 5: User Story 3 - Access to Opportunities is limited to the people who should see them (Priority: P2)

**Goal**: Full `OpportunityPolicy` access matrix — administrator (full), assignee-agent
(scoped), conversation-access-agent (scoped via reused inbox/team rules), unrelated agent
(denied) (FR-006)

**Independent Test**: As an agent who is neither assignee nor has conversation access, view/edit
attempts are denied; as the assignee or with conversation access, allowed; as administrator,
always allowed.

### Tests for User Story 3

- [ ] T023 [P] [US3] Policy spec in `spec/policies/opportunity_policy_spec.rb` covering all four
  roles: administrator (allowed), assignee-agent (allowed), agent with origin-conversation
  inbox/team access but not assignee (allowed), unrelated agent (denied)

### Implementation for User Story 3

- [X] T024 [US3] Extend `OpportunityPolicy` in `custom/app/policies/opportunity_policy.rb` to
  grant access when the record's `origin_conversation` is present by delegating to
  `Pundit.policy!(user, opportunity.origin_conversation).show?` — this reuses
  `ConversationPolicy#show?` (which already covers administrator, agent bot, inbox access, and
  team access) as a public entry point, requiring zero edits to
  `app/policies/conversation_policy.rb` and no duplication of its private
  `inbox_access?`/`team_access?` logic
- [X] T025 [US3] Add a Pundit `OpportunityPolicy::Scope` in
  `custom/app/policies/opportunity_policy.rb` implementing the `index` scoping rule (all
  Opportunities for administrators; assignee-or-conversation-access-only for agents), and wire
  `OpportunitiesController#index` in
  `custom/app/controllers/api/v1/accounts/opportunities_controller.rb` to use
  `policy_scope(Opportunity)` instead of the unscoped account association

**Checkpoint**: All user stories independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification across the whole phase

- [X] T026 [P] Run `docker compose exec rails bundle exec rubocop -a custom/` and fix any
  offenses in the new `custom/` files
- [X] T027 Run the full `quickstart.md` validation end-to-end inside the `rails` container (all
  8 steps: migrations, autoloading, model/association sanity, lazy seeding, feature
  activation/deactivation, policy specs, API contract specs, cross-account guard)
- [X] T028 Verify migration reversibility per quickstart.md step 1:
  `docker compose exec rails bundle exec rails db:rollback STEP=2` followed by
  `docker compose exec rails bundle exec rails db:migrate` succeeds without error
- [X] T029 Verify the feature-activation toggle end-to-end per quickstart.md step 5
  (`account.disable_features!('opportunities')` blocks the endpoints without deleting data;
  `account.enable_features!('opportunities')` resumes using the same prior Pipeline Stages and
  Opportunities)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T001, T002 can start immediately, in parallel
- **Foundational (Phase 2)**: T003→T004→T005 must run in that order (migrations); T006, T007,
  T010 depend on T005/T002 as noted but not on each other, so they may run in parallel; T008
  depends on T007; T009 depends on T006+T007; T011 depends on T001+T006+T007. **BLOCKS all user
  stories.**
- **User Stories (Phase 3-5)**: All depend on Foundational (Phase 2) completion
- **Polish (Phase 6)**: Depends on all three user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational — no dependency on US2/US3
- **User Story 2 (P1)**: Can start after Foundational — independent of US1; its baseline
  `OpportunityPolicy` (T021) is later extended, not replaced, by US3
- **User Story 3 (P2)**: Can start after Foundational, but its implementation tasks (T024, T025)
  build directly on the `OpportunityPolicy` file created in US2 (T021) — sequence US2 before US3
  in single-developer execution; a second developer could stub the policy file to work on T023's
  test list in parallel

### Within Each User Story

- Tests before implementation (write and confirm they fail first)
- Models before policies/controllers (already satisfied — models live in Foundational)
- Policies before controllers that call `check_authorization`/`policy_scope`

### Parallel Opportunities

- T001, T002 (Setup) in parallel
- T006, T007, T010 (Foundational) in parallel once T005/T002 are done
- T012, T013, T014 (US1 tests) in parallel
- T019, T020 (US2 tests) in parallel
- T023 (US3 test) can be drafted in parallel with US1/US2 implementation, run against a stub
  policy, then finalized once T024/T025 land

---

## Parallel Example: Foundational Phase

```bash
# After T005 (migrations run):
Task: "Create PipelineStage model in custom/app/models/pipeline_stage.rb"
Task: "Create Opportunity model in custom/app/models/opportunity.rb"
Task: "Create KanbanFeatureGuard concern in custom/app/controllers/concerns/kanban_feature_guard.rb"
```

## Parallel Example: User Story 1 Tests

```bash
Task: "Model spec in spec/models/pipeline_stage_spec.rb"
Task: "Policy spec in spec/policies/pipeline_stage_policy_spec.rb"
Task: "Request spec in spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: run T012–T014 specs, confirm lazy-seed idempotency manually
5. This alone proves the pipeline configuration foundation works before adding Opportunities

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. Add User Story 1 → test independently (admin can configure a working pipeline)
3. Add User Story 2 → test independently (Opportunities can be created/moved/tracked)
4. Add User Story 3 → test independently (access is correctly restricted)
5. Polish phase → full quickstart.md pass, rubocop clean, migration reversibility confirmed

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No frontend/JS tasks exist in this phase — spec.md and plan.md both explicitly scope this
  phase to backend-only (Phase 3 of the 4-phase Kanban MVP handles the frontend)
- Commit after each task or logical group, per the repository's existing commit conventions
- The pre-commit hook requires committing from inside the `vite` container per `CLAUDE.md`

---

## Phase 7: Convergence

- [X] T030 Split `opportunity_params` in `OpportunitiesController` to reject `:origin_conversation_id` on updates per FR-008 / T022 (contradicts)
- [X] T031 Add missing request spec examples for `origin_conversation_id` update rejection and cross-account stage rejection per US2 / T020 (partial)
- [X] T032 Create `OpportunityPolicy` spec (`spec/policies/opportunity_policy_spec.rb`) covering all four access roles per US3 / T023 (missing)
