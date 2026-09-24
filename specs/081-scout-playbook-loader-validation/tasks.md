---
description: "Task list for Scout Playbook Loader and Boot Validation"
---

# Tasks: Scout Playbook Loader and Boot Validation

**Input**: Design documents from `/specs/081-scout-playbook-loader-validation/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Test-Driven Development is MANDATORY per Constitution Principle VI. Every behavior change is driven by a test that fails first before implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)
- Include exact file paths in descriptions

## Path Conventions

- **Application code**: `custom/app/services/custom/scout_v2/`
- **Initializers**: `config/initializers/`
- **Playbook storage**: `custom/playbooks/`
- **Tests**: `custom/spec/services/custom/scout_v2/`, plus `spec/config/` for the boot initializer spec (mirrors `spec/config/searchkick_spec.rb`'s convention for testing initializers, since `config/initializers/` is a fixed shared location)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic directory structure

- [X] T001 Create playbook storage directory with `.keep` file in `custom/playbooks/.keep`
- [X] T002 [P] Create directory structure for service modules in `custom/app/services/custom/scout_v2/` and specs in `custom/spec/services/custom/scout_v2/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Define root `Custom::ScoutV2` namespace module in `custom/app/services/custom/scout_v2.rb` to establish clean Zeitwerk autoloading

**Checkpoint**: Foundation ready - user story implementation can now begin in priority order

---

## Phase 3: User Story 1 - Load a playbook file into a typed, queryable catalog (Priority: P1) 🎯 MVP

**Goal**: Load versioned playbook markdown files (YAML frontmatter + verbatim markdown body) into typed `Custom::ScoutV2::Playbook` value objects and queryable `Custom::ScoutV2::Playbook::Catalog` collections ordered by priority.

**Independent Test**: Place valid playbook files with full and minimal frontmatter into a temporary directory; verify all fields are readable, collection defaults (`[]` and `{}`) are returned when omitted, body is preserved byte-for-byte, and catalog supports `find_by_name` and `ordered_by_priority` without database or LLM dependencies.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T004 [P] [US1] Create unit spec for Playbook and Catalog in `custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb` covering `find_by_name`, `ordered_by_priority` (descending order, nil priorities sort last), `Enumerable` traversal, and empty catalog handling
- [X] T005 [P] [US1] Create unit spec for Playbook Loader in `custom/spec/services/custom/scout_v2/playbook/loader_spec.rb` covering complete frontmatter parsing, minimal frontmatter with default collections, exact verbatim body preservation, and permissive non-raising behavior on missing fields

### Implementation for User Story 1

- [X] T006 [P] [US1] Implement `Custom::ScoutV2::Playbook` immutable value object in `custom/app/services/custom/scout_v2/playbook.rb` with fields `name` (String), `title` (String), `priority` (Integer), `trigger` (String), `when_state` (normalized array of `[predicate_name, arg]` pairs, default `[]`), `requires` (Array of Strings, default `[]`), `needs` (Array of Strings, default `[]`), `tools` (Array of Strings, default `[]`), `exits` (Hash of String to Hash, default `{}`), `body` (verbatim String, default `''`), and `file_path` (String)
- [X] T007 [P] [US1] Implement `Custom::ScoutV2::Playbook::Catalog` in `custom/app/services/custom/scout_v2/playbook/catalog.rb` with `find_by_name` (exact-string match, nil if absent), `ordered_by_priority` (sorted by `priority` descending, nil priorities last), and `Enumerable` inclusion
- [X] T008 [US1] Implement `Custom::ScoutV2::Playbook::Loader` in `custom/app/services/custom/scout_v2/playbook/loader.rb` with `.load_all(dir)` reading `*.md` files directly under `dir`, splitting frontmatter via regex `/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m`, parsing with `YAML.safe_load`, normalizing collection defaults, and constructing `Playbook` instances

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently (`loader_spec.rb` and `catalog_spec.rb` passing).

---

## Phase 4: User Story 2 - Boot fails loudly on any broken reference between playbooks (Priority: P2)

**Goal**: Halt Rails boot during initialization with `Validator::ValidationError` collecting all broken references (blank `name`/`title`/`trigger`, unregistered predicate in `when_state`, unknown capability in `requires`, undeclared `exit_<name>` token, unresolved `open_playbook(<name>)` token, invalid `priority`, duplicate `priority`, duplicate `name`) in one pass — the 8 validation rules enumerated in `data-model.md`'s Playbook "Validation rules" section.

**Independent Test**: Construct test fixtures for each violation class; verify `Playbook::Validator.call!` raises `ValidationError` naming all offending files and references without starting in a degraded state, and passes cleanly with zero warnings or LLM calls on a valid catalog. `spec/config/scout_v2_playbooks_spec.rb` additionally exercises this through the actual boot initializer (the real entry point FR-012 gates on), not just `Validator` in isolation.

### Collaborators for User Story 2

- [X] T009 [P] [US2] Implement Declared Capability Catalog in `custom/app/services/custom/scout_v2/capabilities/catalog.rb` with `KNOWN_NAMES = %w[scheduling customer_registry].freeze` and `.known?(name)` case-sensitive string membership check
- [X] T010 [P] [US2] Implement initial Predicates Registry lookup interface in `custom/app/services/custom/scout_v2/predicates/registry.rb` with `.registered?(name)` returning boolean for known predicate names (`opportunity_open`, `pending_required_fields`) and `.resolve(name)` raising `ArgumentError` for unregistered names

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T011 [P] [US2] Create unit and contract spec for Playbook Validator in `custom/spec/services/custom/scout_v2/playbook/validator_spec.rb` covering all 8 violation rules from `data-model.md` (blank `name`/`title`/`trigger`; missing or non-integer `priority`; duplicate `priority`; duplicate `name`; unregistered predicate in `when_state`; unknown capability in `requires`; undeclared `exit_<name>` token; unresolved `open_playbook(<name>)` token), aggregate reporting of multiple violations in a single raised error, and clean boot on valid playbooks
- [X] T012 [P] [US2] Create boot initializer spec in `spec/config/scout_v2_playbooks_spec.rb`, following `spec/config/searchkick_spec.rb`'s `load Rails.root.join('config/initializers/scout_v2_playbooks.rb')` + `with_modified_env` convention: verify a `SCOUT_V2_PLAYBOOKS_DIR` fixture with no broken references boots without raising, and a fixture directory containing a broken reference (e.g. duplicate `priority`) causes `Playbook::Validator::ValidationError` to propagate from the initializer load

### Implementation for User Story 2

- [X] T013 [US2] Implement `Custom::ScoutV2::Playbook::Validator` and nested `Validator::ValidationError < StandardError` in `custom/app/services/custom/scout_v2/playbook/validator.rb` implementing `.call!(catalog)` with all 8 validation rules from `data-model.md` (blank `name`/`title`/`trigger`; missing or non-integer `priority`; duplicate `priority`; duplicate `name`; unregistered `when_state` predicate; unknown `requires` capability; undeclared `exit_<name>` token; unresolved `open_playbook(<name>)` token), regex token scanning (`exit_<name>`, `open_playbook(<name>)`), and one-pass violation aggregation across all files
- [X] T014 [US2] Implement boot-time validation Rails initializer in `config/initializers/scout_v2_playbooks.rb` invoking `Validator.call!(Loader.load_all)` inside `Rails.application.config.after_initialize` with `ENV['SCOUT_V2_PLAYBOOKS_DIR']` override support

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently (`validator_spec.rb` and `spec/config/scout_v2_playbooks_spec.rb` passing, boot validation active).

---

## Phase 5: User Story 3 - A condition check is a small, independently testable, named unit (Priority: P3)

**Goal**: Provide small, testable condition checks (predicates) evaluating facts against `RoutingContext` with logical AND evaluation across `when_state` condition lists.

**Independent Test**: Exercise `OpportunityOpen` and `PendingRequiredFields` predicates directly with satisfying and non-satisfying `RoutingContext` instances; verify `Predicates::Evaluator` evaluates multiple conditions with logical AND (vacuously true for empty list, propagating `ArgumentError` for unregistered predicate names) without requiring a model or live conversation.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T015 [P] [US3] Create unit spec for `OpportunityOpen` predicate in `custom/spec/services/custom/scout_v2/predicates/opportunity_open_spec.rb` verifying true for open status and false for non-open status or nil opportunity
- [X] T016 [P] [US3] Create unit spec for `PendingRequiredFields` predicate in `custom/spec/services/custom/scout_v2/predicates/pending_required_fields_spec.rb` verifying true for present pending fields and false for empty array
- [X] T017 [P] [US3] Create unit spec for `Predicates::Evaluator` in `custom/spec/services/custom/scout_v2/predicates/evaluator_spec.rb` verifying logical AND over multi-condition lists, vacuous truth for empty `when_state`, error propagation for unregistered predicate names, and that a `when_state` entry's `arg` value is forwarded through to the resolved predicate's `#call` (confirming the `[predicate_name, arg]` plumbing FR-014 requires, even though the two shipped predicates ignore it — see spec.md Assumptions)

### Implementation for User Story 3

- [X] T018 [P] [US3] Implement `Custom::ScoutV2::RoutingContext` struct in `custom/app/services/custom/scout_v2/routing_context.rb` with `:opportunity` and `:pending_fields` keyword attributes
- [X] T019 [P] [US3] Implement `Custom::ScoutV2::Predicates::Base` abstract class in `custom/app/services/custom/scout_v2/predicates/base.rb` defining `#call(ctx, arg = nil)` raising `NotImplementedError`
- [X] T020 [P] [US3] Implement `Custom::ScoutV2::Predicates::OpportunityOpen` in `custom/app/services/custom/scout_v2/predicates/opportunity_open.rb` subclassing `Base` and evaluating `ctx.opportunity&.status.to_s == 'open'`
- [X] T021 [P] [US3] Implement `Custom::ScoutV2::Predicates::PendingRequiredFields` in `custom/app/services/custom/scout_v2/predicates/pending_required_fields.rb` subclassing `Base` and evaluating `ctx.pending_fields.present?`
- [X] T022 [US3] Wire concrete predicate classes into `Custom::ScoutV2::Predicates::Registry` in `custom/app/services/custom/scout_v2/predicates/registry.rb` so `.resolve(name)` returns the corresponding predicate class — depends on US2's T010, which creates this same file's lookup skeleton
- [X] T023 [US3] Implement `Custom::ScoutV2::Predicates::Evaluator` in `custom/app/services/custom/scout_v2/predicates/evaluator.rb` with `.call(when_state, ctx)` executing logical AND over all conditions via `Registry.resolve(name).new.call(ctx, arg)`

**Checkpoint**: All user stories should now be independently functional and tested.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification, linting, and regression testing across all stories

- [X] T024 [P] Validate all end-to-end quickstart scenarios from `specs/081-scout-playbook-loader-validation/quickstart.md`
- [X] T025 [P] Run RuboCop static analysis on all feature files in `custom/app/services/custom/scout_v2/`, `custom/spec/services/custom/scout_v2/`, `spec/config/scout_v2_playbooks_spec.rb`, and `config/initializers/scout_v2_playbooks.rb` ensuring zero offenses
- [X] T026 Run targeted RSpec test suite covering all scout_v2 specs via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout_v2/ spec/config/scout_v2_playbooks_spec.rb`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories proceed in priority order (P1 → P2 → P3)
  - US1 provides `Playbook`, `Catalog`, and `Loader`
  - US2 builds `Validator` and boot wiring on top of US1 `Catalog`
  - US3 implements concrete predicates and evaluator for `when_state` conditions
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after US1 - Validates `Catalog` and `Playbook` objects loaded by US1
- **User Story 3 (P3)**: The condition-check struct/class definitions (T015–T021) can start after
  Foundational (Phase 2), independently of US2. Wiring the concrete predicate classes into
  `Predicates::Registry` (T022) has a hard file-level dependency on US2's T010 (which creates
  `predicates/registry.rb`'s lookup skeleton) — both tasks edit the same file, so T022 cannot start
  until T010 is done. `Predicates::Evaluator` (T023) only needs `Registry.resolve` to exist (T010),
  not the concrete predicates wired in.

### Within Each User Story

- Tests MUST be written and fail before implementation code is written (TDD)
- Data structures / value objects before services
- Collaborators before main service
- Core logic before integration and boot wiring

### Parallel Opportunities

- **Phase 1**: T001 and T002 can run in parallel
- **Phase 3 (US1)**:
  - T004 and T005 (specs) can be written in parallel
  - T006 (`Playbook`) and T007 (`Catalog`) can be implemented in parallel
- **Phase 4 (US2)**:
  - T009 (`Capabilities::Catalog`) and T010 (`Predicates::Registry`) can run in parallel
  - T011 (`Validator` spec) and T012 (initializer spec) can be written in parallel
- **Phase 5 (US3)**:
  - T015, T016, T017 (predicate and evaluator specs) can be written in parallel
  - T018 (`RoutingContext`) and T019 (`Predicates::Base`) can be implemented in parallel
  - T020 (`OpportunityOpen`) and T021 (`PendingRequiredFields`) can be implemented in parallel
- **Phase 6 (Polish)**:
  - T024 and T025 can run in parallel

---

## Phase 7: Convergence

- [X] T027 Rewrite the "forwards arg parameter to predicate #call" example in `custom/spec/services/custom/scout_v2/predicates/evaluator_spec.rb` (currently `allow(Custom::ScoutV2::Predicates::Registry).to receive(:registered?/:resolve)`, lines ~72-73) to verify `Evaluator.call`'s arg-forwarding without stubbing the internal `Predicates::Registry` collaborator per Constitution VII (contradicts)

---

## Phase 8: Code Review Fixes

- [X] T028 Record unusable frontmatter on a new `Playbook#load_errors` in `custom/app/services/custom/scout_v2/playbook/loader.rb` (non-list `when_state`, a `when_state` entry that is neither a String nor a single-key mapping, non-mapping `exits`, and `Psych::Exception` from `YAML.safe_load`) instead of dropping it or aborting the pass; report each entry as a violation in `validator.rb`
- [X] T029 Enforce the `\A[a-z][a-z0-9_]*\z` format on `name` and `exits` keys in `validator.rb`, and broaden `EXIT_TOKEN_PATTERN`/`OPEN_PLAYBOOK_PATTERN` so references spelled outside that format are captured and reported
- [X] T030 Fail boot on a missing playbooks directory (`Dir.children` raises `Errno::ENOENT`) and move the `SCOUT_V2_PLAYBOOKS_DIR` default into `Loader.load_all`, so `config/initializers/scout_v2_playbooks.rb` no longer duplicates it
- [X] T031 Rewrite `validator_spec.rb` with `let` instead of helper methods, assert `error.class.name` and `error.violations` (file path plus broken reference) across the validator, loader, and initializer specs, and add loader/validator/initializer examples for T028–T030
- [X] T032 Refactor `Playbook` to `Data.define`, simplify `Catalog#initialize` and add `alias [] find_by_name`, remove speculative fallbacks in `validator.rb` (`file_ref`, `validate_body_tokens`) and add String type checks for `title`/`trigger`, and remove redundant wiring/stdlib tests from `opportunity_open_spec.rb`, `pending_required_fields_spec.rb`, and `catalog_spec.rb` per AGENTS.md

---

## Parallel Execution Examples

### Parallel Example: User Story 1
```bash
# Launch test creation for User Story 1 in parallel:
Task: "Create unit spec for Playbook and Catalog in custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb"
Task: "Create unit spec for Playbook Loader in custom/spec/services/custom/scout_v2/playbook/loader_spec.rb"

# Launch data structures for User Story 1 in parallel:
Task: "Implement Custom::ScoutV2::Playbook immutable value object in custom/app/services/custom/scout_v2/playbook.rb"
Task: "Implement Custom::ScoutV2::Playbook::Catalog in custom/app/services/custom/scout_v2/playbook/catalog.rb"
```

### Parallel Example: User Story 3
```bash
# Launch predicate tests in parallel:
Task: "Create unit spec for OpportunityOpen predicate in custom/spec/services/custom/scout_v2/predicates/opportunity_open_spec.rb"
Task: "Create unit spec for PendingRequiredFields predicate in custom/spec/services/custom/scout_v2/predicates/pending_required_fields_spec.rb"
Task: "Create unit spec for Predicates::Evaluator in custom/spec/services/custom/scout_v2/predicates/evaluator_spec.rb"

# Launch predicate implementations in parallel:
Task: "Implement Custom::ScoutV2::Predicates::OpportunityOpen in custom/app/services/custom/scout_v2/predicates/opportunity_open.rb"
Task: "Implement Custom::ScoutV2::Predicates::PendingRequiredFields in custom/app/services/custom/scout_v2/predicates/pending_required_fields.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001, T002)
2. Complete Phase 2: Foundational (T003)
3. Complete Phase 3: User Story 1 (T004–T008)
4. **STOP and VALIDATE**: Run `custom/spec/services/custom/scout_v2/playbook/` specs and verify a valid playbook file loads into a queryable catalog
5. Deliver/demo MVP increment

### Incremental Delivery

1. **Increment 1 (MVP)**: Setup + Foundational + User Story 1 → Playbook loading and catalog queries work independently
2. **Increment 2**: User Story 2 → Boot-time validation and loud startup failure on broken references active
3. **Increment 3**: User Story 3 → Isolated predicate checks and logical AND condition evaluation verified
4. **Increment 4**: Polish → Static analysis and end-to-end quickstart validation complete

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks
- `[Story]` label (`[US1]`, `[US2]`, `[US3]`) maps task to specific user story for traceability
- All tests follow Constitution Principles VI, VII, and VIII: TDD with real objects, no mocks for internal collaborators
- Commit after each task or logical group with Conventional Commits format
- Avoid modifying existing upstream files: all code resides in `custom/` plus the dedicated initializer `config/initializers/scout_v2_playbooks.rb` and its spec `spec/config/scout_v2_playbooks_spec.rb`
