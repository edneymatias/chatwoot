---

description: "Task list for RuboCop Complexity Cleanup implementation"
---

# Tasks: RuboCop Complexity Cleanup

**Input**: Design documents from `/specs/025-rubocop-complexity-cleanup/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- Paths shown below are relative to the repository root as the codebase is a monolithic Ruby on Rails application.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic verification

- [x] T001 Verify standard tools are functioning by running `bundle exec rubocop -v` and `bundle exec rspec -v` at repository root

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Update global RuboCop configuration as a baseline before refactoring targeted files.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Update `.rubocop.yml` to define `Metrics/CyclomaticComplexity` and `Metrics/PerceivedComplexity` with `Max: 11` as permanent settings (with explanatory comment) and remove global exclusions for these cops from `.rubocop_todo.yml`.

**Checkpoint**: Foundation ready - files can now be refactored and tested against the new baseline.

---

## Phase 3: User Story 1 - CI Pipeline Runs Cleanly (Priority: P1) 🎯 MVP

**Goal**: Refactor specific fork-owned files to pass standard complexity thresholds and remove their exclusions from `.rubocop_todo.yml`.

**Independent Test**: Can be fully tested by running `bundle exec rubocop` against the 6 specific files and verifying no complexity/size offenses are reported, alongside passing RSpec tests.

### Implementation for User Story 1

- [x] T003 [P] [US1] Refactor `custom/app/models/opportunity.rb` to extract `contact_json`/`assignee_json` and missing keys helpers to reduce `AbcSize` and `CyclomaticComplexity`.
- [x] T004 [P] [US1] Refactor `custom/app/services/reports/opportunity_funnel_builder.rb` to extract the day-bucketed count/value aggregation into a private helper.
- [x] T005 [P] [US1] Refactor `lib/seeders/account_seeder.rb` to extract the pipeline stage/attribute setup into a private helper from `seed_opportunities`.
- [x] T006 [P] [US1] Refactor `spec/bin/sync_custom_module_hooks_spec.rb` to split fixture-writing logic into per-commit helpers.
- [x] T007 [P] [US1] Refactor `custom/app/services/custom/automation_rules/action_service.rb` to extract `resolve_assignee_id` logic.
- [x] T008 [US1] Remove method length and complexity `Exclude` entries for the refactored files in `.rubocop_todo.yml` and ensure legacy rake-task exclusions are preserved.

**Checkpoint**: At this point, User Story 1 should be fully functional. Code should lint cleanly against the adjusted thresholds.

---

## Phase 4: User Story 2 - Clear Guidelines for Complexity (Priority: P2)

**Goal**: Add explicit documentation on handling RuboCop complexity offenses to avoid future accumulation of technical debt.

**Independent Test**: Can be verified by reading `AGENTS.md` and confirming instructions to refactor (using private helpers) rather than bypassing complexity cops.

### Implementation for User Story 2

- [x] T009 [US2] Update `AGENTS.md` to include a short guideline near the RuboCop command reference stating that complexity offenses must be resolved by refactoring (extracting private helpers) and that new `.rubocop_todo.yml` exceptions are unacceptable.

**Checkpoint**: User Stories 1 and 2 should both be complete.

---

## Phase 5: Extra RuboCop & Translation Cleanups

**Purpose**: Clean up remaining translation hardcodes, test file linting, and inline exclusions in the `custom/` module.

- [x] T011 [US2] Update `AGENTS.md` to document that Crowdin is not used and `pt-BR` translations must be added manually.
- [x] T012 [P] [US1] Refactor `custom/spec/models/pipeline_stage_required_field_spec.rb` and `custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb` to pass RuboCop rules and remove their entries from `.rubocop_todo.yml`.
- [x] T013 [P] [US1] Refactor `custom/app/models/pipeline_closing_required_field.rb` to extract hardcoded strings to `I18n.t`, provide `en`/`pt_BR` translations, and remove `# rubocop:disable Rails/I18nLocaleTexts`.
- [x] T014 [P] [US1] Refactor `custom/app/models/pipeline_stage.rb` to replace `update_all` with a proper iterator, removing `# rubocop:disable Rails/SkipsModelValidations`.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validations.

- [x] T010 Run validation steps documented in `specs/025-rubocop-complexity-cleanup/quickstart.md` (lint files and run specs).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
- **Polish (Final Phase)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - No technical dependencies on US1, can be done in parallel.

### Parallel Opportunities

- Foundational task configures `.rubocop.yml`. After it is complete, refactoring tasks T003, T004, T005, T006, and T007 can all run in parallel because they modify entirely separate files.
- Task T009 (US2) modifying documentation can be run in parallel with US1 tasks.
- Task T008 (US1) editing `.rubocop_todo.yml` should run after T003-T007 to avoid linting failures before refactors are complete.

---

## Parallel Example: User Story 1

```bash
# Launch refactoring of independent files in parallel:
Task: "Refactor custom/app/models/opportunity.rb ..."
Task: "Refactor custom/app/services/reports/opportunity_funnel_builder.rb ..."
Task: "Refactor lib/seeders/account_seeder.rb ..."
Task: "Refactor spec/bin/sync_custom_module_hooks_spec.rb ..."
Task: "Refactor custom/app/services/custom/automation_rules/action_service.rb ..."
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL)
3. Complete Phase 3: User Story 1 (Code Refactoring and Lint Checks)
4. **STOP and VALIDATE**: Ensure RuboCop passes and RSpec passes for all targeted files.

### Incremental Delivery

1. Complete Setup + Foundational → Baseline ready
2. Add User Story 1 → Refactor Code and Test independently → Clean CI!
3. Add User Story 2 → Update Guidelines
4. Run quickstart validations.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Verify tests pass after every individual file refactor
- Commit after each task or logical group
- Do not use `Exclude` masks for the newly refactored methods.
