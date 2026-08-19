---

description: "Task list for Scout Core & Data Model implementation"
---

# Tasks: Scout Core & Data Model

**Input**: Design documents from `/specs/042-scout-core-data-model/`
- Specification: [spec.md](./spec.md)
- Implementation Plan: [plan.md](./plan.md)
- Data Model: [data-model.md](./data-model.md)
- Research: [research.md](./research.md)
- Quickstart Guide: [quickstart.md](./quickstart.md)

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `quickstart.md`

**Tests**: Unit tests in RSpec (`custom/spec/models/`) are included for data model validations, associations, encryption fail-safe behavior, and quota logic.

**Organization**: Tasks are grouped by phase and user story to enable independent implementation and testing of each increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)
- Every task includes exact file paths in its description

## Path Conventions

- **Models**: `custom/app/models/`
- **Concerns**: `custom/app/models/custom/concerns/`
- **Specs**: `custom/spec/models/`
- **Migrations**: `db/migrate/`

---

## Phase 1: Setup (Database Migrations & Infrastructure)

**Purpose**: Database schema initialization for Scout tables and opportunity extension

- [X] T001 [P] Create migration for `ichatr_scouts` table with provider enum, model_name, api_key_override, quota, and enabled columns in `db/migrate/21260819000001_create_ichatr_scouts.rb`
- [X] T002 [P] Create migration for `ichatr_scout_inboxes` pivot table with unique index on `inbox_id` in `db/migrate/21260819000002_create_ichatr_scout_inboxes.rb`
- [X] T003 [P] Create migration for `ichatr_scout_tools` table with name, description, endpoint_url, http_method, auth_headers, parameter_schema in `db/migrate/21260819000003_create_ichatr_scout_tools.rb`
- [X] T004 [P] Create migration to add nullable `lost_reason` column to `ichatr_opportunities` in `db/migrate/21260819000004_add_lost_reason_to_ichatr_opportunities.rb`
- [X] T005 Run database migrations via `docker compose exec rails bundle exec rails db:migrate`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core model infrastructure and associations that MUST be complete before user stories

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 [P] Update Account custom concern with `has_many :scouts, dependent: :destroy` and `has_many :scout_tools, dependent: :destroy` in `custom/app/models/custom/concerns/account.rb`
- [X] T007 [P] Verify `Opportunity#lost_reason` is usable as a plain attribute once the `lost_reason` column exists (T004) — no model code expected beyond confirming Rails auto-generates the accessor; add explicit code only if a real need surfaces in `custom/app/models/opportunity.rb`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Provision a Scout AI agent for an account (Priority: P1) 🎯 MVP

**Goal**: An operator can create a Scout record for an account (with provider enum, model name, API key override, persona, pipeline stage hint), associate it with inboxes via `ScoutInbox` (enforcing single-Scout-per-inbox), create account-scoped `ScoutTool` records, and execute an LLM tool-calling round-trip via `RubyLLM.context`.

**Independent Test**: Create a `Scout` and `ScoutInbox` in Rails console, verify provider enum constraints and inbox uniqueness, and call `scout.llm_chat.ask(...)` to complete a live tool-calling request against a configured LLM provider (Quickstart §1–4).

### Implementation for User Story 1

- [X] T008 [P] [US1] Create `ScoutInbox` pivot model with `belongs_to :scout`, `belongs_to :inbox`, and `validates :inbox_id, uniqueness: true` in `custom/app/models/scout_inbox.rb`
- [X] T009 [P] [US1] Create `ScoutTool` model with account association, validations (`name`, `description`, `endpoint_url`, `http_method`), and default `parameter_schema` in `custom/app/models/scout_tool.rb`
- [X] T010 [US1] Create `Scout` model with `provider` enum (`gemini: 0`, `openai: 1`, `anthropic: 2`), associations (`belongs_to :account`, `has_many :scout_inboxes, dependent: :destroy`, `has_many :inboxes, through: :scout_inboxes`, `belongs_to :default_pipeline_stage, optional: true`), and validations in `custom/app/models/scout.rb`
- [X] T011 [US1] Implement multi-provider `Scout#llm_chat` client resolution using `RubyLLM.context` with per-provider key mapping (`gemini_api_key`, `openai_api_key`, `anthropic_api_key`) in `custom/app/models/scout.rb`
- [X] T012 [US1] Create unit specs for `ScoutInbox` uniqueness and foreign key validations in `custom/spec/models/scout_inbox_spec.rb` (depends on T010 — needs a real `Scout` record to associate against)
- [X] T013 [P] [US1] Create unit specs for `ScoutTool` validations, account scoping, and lifecycle independence from Scout in `custom/spec/models/scout_tool_spec.rb`
- [X] T014 [P] [US1] Create unit specs for `Scout` provider enum, model associations, cascade deletion of `ScoutInbox`, and `llm_chat` instantiation in `custom/spec/models/scout_spec.rb`
- [X] T014a [US1] Manually execute `quickstart.md` §1–4 in the Rails console against a real configured LLM provider to confirm the SC-001 provisioning + tool-calling round-trip works end to end

**Checkpoint**: User Story 1 MVP fully functional and verified via unit specs and manual console round-trip.

---

## Phase 4: User Story 2 - Keep Scout credentials safe at rest (Priority: P2)

**Goal**: Ensure `Scout#api_key_override` and `ScoutTool#auth_headers` are encrypted at rest unconditionally, failing closed (raising an error on save) when `ActiveRecord::Encryption` is not configured.

**Independent Test**: Verify database columns contain ciphertext (base64 blob) when saved with encryption configured, and verify attempting to save without encryption raises `ActiveRecord::Encryption::Errors::Configuration` (Quickstart §5–6).

### Implementation for User Story 2

- [X] T015 [P] [US2] Add unconditional `encrypts :api_key_override` (no `Chatwoot.encryption_configured?` guard) in `custom/app/models/scout.rb`
- [X] T016 [P] [US2] Add unconditional `encrypts :auth_headers` (no `Chatwoot.encryption_configured?` guard) in `custom/app/models/scout_tool.rb`
- [X] T017 [P] [US2] Add unit specs verifying encrypted storage of `api_key_override` and fail-closed behavior on unconfigured encryption in `custom/spec/models/scout_spec.rb`
- [X] T018 [P] [US2] Add unit specs verifying encrypted storage of `auth_headers` and fail-closed behavior on unconfigured encryption in `custom/spec/models/scout_tool_spec.rb`

**Checkpoint**: User Stories 1 AND 2 functional with verified credential encryption and fail-closed safety.

---

## Phase 5: User Story 3 - Respect response quota groundwork before billing exists (Priority: P3)

**Goal**: Implement `Scout#quota_available?` logic (`true` when `responses_quota` is `-1` or `responses_consumed < responses_quota`; `false` when consumed reaches/exceeds finite quota or quota is `0`) and numericality validations.

**Independent Test**: Call `Scout#quota_available?` across unlimited (`-1`), under quota, at quota, over quota, and zero-quota instances (Quickstart §7).

### Implementation for User Story 3

- [X] T019 [US3] Add validations for `responses_quota >= -1` and `responses_consumed >= 0` along with the `quota_available?` method in `custom/app/models/scout.rb`
- [X] T020 [US3] Add unit specs for `quota_available?` covering unlimited (`-1`), under quota, at quota, over quota, and zero quota (`0`) in `custom/spec/models/scout_spec.rb`

**Checkpoint**: All user stories (US1, US2, US3) implemented and independently verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates, linting, test suite execution, and rollback validation

- [X] T021 [P] Run RuboCop check on all new/modified files via `docker compose exec rails bundle exec rubocop custom/app/models/ custom/spec/models/ db/migrate/21260819*`
- [X] T022 Run complete RSpec test suite for Scout models via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/scout_spec.rb custom/spec/models/scout_inbox_spec.rb custom/spec/models/scout_tool_spec.rb`
- [X] T023 Run database migration rollback and re-apply validation per `quickstart.md` §8 via `docker compose exec rails bundle exec rails db:rollback STEP=4 && docker compose exec rails bundle exec rails db:migrate`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) migration completion - BLOCKS all user stories
- **User Stories (Phases 3–5)**: Depend on Foundational (Phase 2) completion
  - Sequential delivery order: US1 (P1 MVP) → US2 (P2) → US3 (P3)
- **Polish (Phase 6)**: Depends on all user story phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 - provides base `Scout`, `ScoutInbox`, `ScoutTool`, and `llm_chat` resolution
- **User Story 2 (P2)**: Builds on `Scout` and `ScoutTool` models from US1, adding unconditional encryption
- **User Story 3 (P3)**: Builds on `Scout` model from US1, adding quota validations and helper methods

### Within Each User Story

- Database tables and foundational associations exist before model code
- Model core definition before feature additions
- Specs written alongside implementation to verify acceptance criteria
- Story verified independently before moving to next priority

### Parallel Opportunities

- **Phase 1**: All 4 migration files (T001, T002, T003, T004) can be created in parallel
- **Phase 2**: Account concern update (T006) and Opportunity update (T007) can be executed in parallel
- **Phase 3**: `ScoutInbox` (T008) and `ScoutTool` (T009) can be created in parallel; `ScoutTool` specs (T013) and `Scout` specs (T014) can be drafted in parallel with model work, but `ScoutInbox` specs (T012) must wait for `Scout` (T010) to exist
- **Phase 4**: Unconditional encryption for `Scout` (T015) and `ScoutTool` (T016), and their specs (T017, T018), can be developed in parallel

---

## Parallel Example: User Story 1

```bash
# Launch model definitions for independent entities:
Task: "Create ScoutInbox pivot model with belongs_to :scout, belongs_to :inbox, and validates :inbox_id, uniqueness: true in custom/app/models/scout_inbox.rb"
Task: "Create ScoutTool model with account association, validations, and default parameter_schema in custom/app/models/scout_tool.rb"

# Launch specs for independent models:
Task: "Create unit specs for ScoutInbox uniqueness and foreign key validations in custom/spec/models/scout_inbox_spec.rb"
Task: "Create unit specs for ScoutTool validations, account scoping, and lifecycle independence from Scout in custom/spec/models/scout_tool_spec.rb"
```

---

## Parallel Example: User Story 2

```bash
# Apply unconditional encryption across distinct models:
Task: "Add unconditional encrypts :api_key_override (no Chatwoot.encryption_configured? guard) in custom/app/models/scout.rb"
Task: "Add unconditional encrypts :auth_headers (no Chatwoot.encryption_configured? guard) in custom/app/models/scout_tool.rb"

# Add encryption test coverage in parallel:
Task: "Add unit specs verifying encrypted storage of api_key_override in custom/spec/models/scout_spec.rb"
Task: "Add unit specs verifying encrypted storage of auth_headers in custom/spec/models/scout_tool_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete **Phase 1: Setup** (Migrations T001–T005)
2. Complete **Phase 2: Foundational** (Account concern & Opportunity T006–T007)
3. Complete **Phase 3: User Story 1** (Scout, ScoutInbox, ScoutTool, `llm_chat` T008–T014)
4. **STOP and VALIDATE**: Verify US1 via console round-trip (`quickstart.md` §1–4) and RSpec specs
5. MVP achieved: working multi-provider Scout agent provisioning and tool-calling client

### Incremental Delivery

1. Setup + Foundation ready → Core tables and relationships in place
2. Add User Story 1 (P1) → Test independently → MVP verified!
3. Add User Story 2 (P2) → Test independently → Unconditional credential encryption active
4. Add User Story 3 (P3) → Test independently → Quota groundwork complete
5. Run Phase 6 Polish → RuboCop clean, full spec suite passing, migration rollback verified

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[Story]` label (`[US1]`, `[US2]`, `[US3]`) maps tasks to specific user stories for traceability
- All tasks strictly follow the `- [ ] [TaskID] [P?] [Story?] Description with file path` format
- Unconditional `encrypts` intentionally deviates from `Chatwoot.encryption_configured?` per FR-005/006 and research.md §2
