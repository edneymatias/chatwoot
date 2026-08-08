# Research: RuboCop Complexity Cleanup

## Overview
This feature requires no external technologies or complex architectural decisions. The "research" phase here primarily confirms the syntax and approach for extracting private helper methods in Ruby classes without breaking existing behavior.

## Decisions

### 1. Refactoring Strategy for `as_json` (FR-004)
- **Decision**: Extract `contact_json` and `assignee_json` private methods.
- **Rationale**: Reduces AbcSize in `Opportunity#as_json`.

### 2. Refactoring Strategy for Validations (FR-005)
- **Decision**: Extract `missing_required_keys(pipeline_stage)` into a private method that iterates through `required_custom_attribute_definitions`.
- **Rationale**: Reduces Cyclomatic and Perceived complexity by isolating the missing key logic.

### 3. Refactoring Strategy for Aggregations (FR-006)
- **Decision**: Extract `aggregate_opportunities_by_day(opportunities, range)` into a private method.
- **Rationale**: Isolates the data grouping logic.

### 4. Refactoring Strategy for Seeders (FR-007)
- **Decision**: Extract `setup_pipeline_stage_and_attributes` from `seed_opportunities`.
- **Rationale**: Shortens the method length of `seed_opportunities`.

### 5. Refactoring Strategy for Specs (FR-008)
- **Decision**: Extract `write_commit_one_fixtures` and `write_commit_two_fixtures` in `spec/bin/sync_custom_module_hooks_spec.rb`.
- **Rationale**: Shortens the `setup_files` method length while adhering to per-example setup preferences.

### 6. Refactoring Strategy for Action Service (FR-009)
- **Decision**: Extract `resolve_assignee_id(assignee_id_param, conversation)`.
- **Rationale**: Isolates the branching logic for "same_as_conversation" vs explicit ID.
