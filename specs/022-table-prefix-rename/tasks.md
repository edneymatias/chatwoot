---
description: "Task list for Table Prefix Rename & Migration Namespace Policy feature implementation"
---

# Tasks: Table Prefix Rename & Migration Namespace Policy

**Input**: Design documents from `/specs/022-table-prefix-rename/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create generator wrapper script in `bin/ichatr-migration`
- [x] T002 [P] Ensure generator script is executable with `chmod +x bin/ichatr-migration`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

*(No foundational blocking tasks required for this refactoring phase)*

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Database Schema Prefix Migration (Priority: P1) 🎯 MVP

**Goal**: Rename custom product tables from `matias_` prefix to `ichatr_` prefix in ORM models, policies, and migration file contents.

**Independent Test**: Code search verifies no `matias` occurrences remain in the 7 modified models or `opportunity_policy.rb`.

### Implementation for User Story 1

- [x] T003 [P] [US1] Update `self.table_name` override in `app/models/opportunity.rb`
- [x] T004 [P] [US1] Update `self.table_name` override in `app/models/pipeline_stage.rb`
- [x] T005 [P] [US1] Update `self.table_name` override in `app/models/opportunity_stage_change.rb`
- [x] T006 [P] [US1] Update `self.table_name` override in `app/models/pipeline_stage_required_field.rb`
- [x] T007 [P] [US1] Update `self.table_name` override in `app/models/pipeline_closing_required_field.rb`
- [x] T008 [P] [US1] Update `self.table_name` override in `app/models/pipeline_card_field_config.rb`
- [x] T009 [P] [US1] Update `self.table_name` override in `app/models/pipeline_currency_setting.rb`
- [x] T010 [P] [US1] Update raw SQL string in `custom/app/policies/opportunity_policy.rb`
- [x] T011 [P] [US1] Replace `matias`/`Matias` strings with `ichatr`/`Ichatr` across the 13 custom migration file contents in `db/migrate/`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently (minus file renaming, which is handled in US2).

---

## Phase 4: User Story 2 - Migration Timestamp Namespace Policy & Generator Tooling (Priority: P2)

**Goal**: Ensure all 13 custom migrations and future migrations use a deterministic +100-year timestamp offset policy to prevent upstream collisions.

**Independent Test**: Generating a new migration via `bin/ichatr-migration test_migration` produces a file in `db/migrate/` whose timestamp year is 100 years from now.

### Implementation for User Story 2

- [x] T012 [P] [US2] Implement ruby script logic inside `bin/ichatr-migration` to wrap `rails generate migration`, parse output, add 100 to timestamp year, and rename the newly created file.
- [x] T013 [P] [US2] Rename the 13 custom migration files in `db/migrate/` to add +100 years to their prefix and change `matias` to `ichatr` in their filenames.

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently.

---

## Phase 5: User Story 3 - Operational Quality Verification & Test Suite Parity (Priority: P3)

**Goal**: Verify 100% regression-free state through full database rebuild and test execution.

**Independent Test**: Backend and frontend automated tests pass cleanly against the rebuilt database.

### Implementation for User Story 3

- [x] T014 [US3] Drop, create, and migrate the local database using `rails db:drop db:create db:migrate`
- [x] T015 [US3] Regenerate model schema comments using `bundle exec annotaterb models`
- [x] T016 [US3] Run repo-wide code search to verify zero remaining occurrences of `matias` (outside `docs/`)
- [x] T017 [US3] Execute backend Ruby test suite using `bundle exec rspec`
- [x] T018 [US3] Execute frontend Vue test suite using `pnpm test`

**Checkpoint**: All user stories should now be independently functional.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T019 Run validation procedures described in `quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - May integrate with US1 but should be independently testable
- **User Story 3 (P3)**: Depends on US1 and US2 since the database rebuild and test execution require the schema definitions and model updates to be finalized.

### Within Each User Story

- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All model `self.table_name` override updates marked [P] can run in parallel
- Modifying migration file contents (T011) and implementing the generator wrapper (T012) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch model updates in parallel:
Task: "Update self.table_name override in app/models/opportunity.rb"
Task: "Update self.table_name override in app/models/pipeline_stage.rb"
Task: "Update self.table_name override in app/models/opportunity_stage_change.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 3: User Story 1
3. **STOP and VALIDATE**: Test User Story 1 independently

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Verify code replacements
3. Add User Story 2 → Verify file renames and script functionality
4. Add User Story 3 → Verify end-to-end functionality via DB rebuild and tests

### Parallel Team Strategy

With multiple developers:
1. Developer A: Implements Model and Policy updates (US1)
2. Developer B: Implements Migration content and filename updates (US1/US2)
3. Developer C: Implements the generator wrapper script (US2)
4. Team synchronizes to run DB rebuild and test suites (US3)
