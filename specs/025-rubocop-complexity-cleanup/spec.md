# Feature Specification: RuboCop Complexity Cleanup

**Feature Branch**: `[025-rubocop-complexity-cleanup]`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "$ARGUMENTS"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - CI Pipeline Runs Cleanly (Priority: P1)

As a developer, I want the backend linting process to pass successfully, so that I can confidently merge changes without being blocked by complexity metrics.

**Why this priority**: The `lint-backend` CI job is currently failing on the main branch due to an unmasked complexity offense, which blocks or complicates future deployments.

**Independent Test**: Can be fully tested by running `bundle exec rubocop` against the specific fork-owned files and verifying no offenses are reported under the baseline thresholds.

**Acceptance Scenarios**:

1. **Given** a fresh checkout of the branch, **When** I run `rubocop` on `custom/app/services/custom/automation_rules/action_service.rb`, **Then** no complexity or size offenses are reported.
2. **Given** the repository's RuboCop configuration, **When** I inspect `.rubocop_todo.yml`, **Then** no fork-owned files have exclusions for method length or complexity.

---

### User Story 2 - Clear Guidelines for Complexity (Priority: P2)

As a developer or AI agent, I want clear documentation on how to handle RuboCop complexity offenses, so that I don't accumulate technical debt by masking them in the future.

**Why this priority**: Prevents regression and ensures all future contributions maintain the expected code quality standards.

**Independent Test**: Can be fully tested by verifying the instructions in `AGENTS.md` and ensuring they accurately reflect the standard for resolving complexity offenses.

**Acceptance Scenarios**:

1. **Given** the `AGENTS.md` file, **When** I read the guidelines, **Then** I see explicit instructions to refactor code (using private helpers) instead of adding exceptions to `.rubocop_todo.yml`.

### Edge Cases

- What happens if a refactored private helper still exceeds complexity limits? (It should be further split).
- What happens if the `Max: 11` threshold in `.rubocop.yml` accidentally allows new offenses in other files? (It's a global threshold, but developers are guided by `AGENTS.md` to keep standard methods under 7/8).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST have `Metrics/CyclomaticComplexity` and `Metrics/PerceivedComplexity` configured with a maximum of 11 in `.rubocop.yml` as permanent settings with an explanatory comment, removing them from `.rubocop_todo.yml`.
- **FR-002**: System MUST NOT have `Exclude` entries in `.rubocop_todo.yml` for method length or complexity for the files: `custom/app/models/opportunity.rb`, `custom/app/services/reports/opportunity_funnel_builder.rb`, `lib/seeders/account_seeder.rb`, and `spec/bin/sync_custom_module_hooks_spec.rb`.
- **FR-003**: System MUST preserve all other `.rubocop_todo.yml` entries untouched, including exclusions for legacy upstream rake tasks.
- **FR-004**: System MUST implement extracted private helper methods for `contact` and `assignee` JSON construction in `custom/app/models/opportunity.rb`.
- **FR-005**: System MUST implement an extracted private helper method for computing missing required fields in `custom/app/models/opportunity.rb#validate_forward_stage_move_requirements`.
- **FR-006**: System MUST implement an extracted private helper method for day-bucketed count/value aggregation in `custom/app/services/reports/opportunity_funnel_builder.rb`.
- **FR-007**: System MUST implement an extracted private helper method for pipeline stage and custom attribute setup in `lib/seeders/account_seeder.rb#seed_opportunities`.
- **FR-008**: System MUST implement split per-commit helper methods for fixture-writing logic in `spec/bin/sync_custom_module_hooks_spec.rb#setup_files`.
- **FR-009**: System MUST implement an extracted private helper method for assignee resolution in `custom/app/services/custom/automation_rules/action_service.rb#create_opportunity`.
- **FR-010**: System MUST include a guideline in `AGENTS.md` requiring backend code to pass baseline complexity thresholds by extracting private helpers, and forbidding the use of `.rubocop_todo.yml` exceptions for complexity/length offenses.
- **FR-011**: System MUST document in `AGENTS.md` that this fork does not use Crowdin and that translations must be manually provided for both `en` and `pt-BR`.
- **FR-012**: System MUST resolve all `.rubocop_todo.yml` exceptions (including test-specific cops like `LetSetup`) for `custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb` and `custom/spec/models/pipeline_stage_required_field_spec.rb`.
- **FR-013**: System MUST resolve inline RuboCop exceptions (`rubocop:disable`) in `custom/app/models/pipeline_closing_required_field.rb` and `custom/app/models/pipeline_stage.rb` through proper code refactoring.
- **FR-014**: System MUST extract hardcoded validation strings in pipeline fields to `I18n.t` and provide both `en` and `pt_BR` localized strings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the 6 targeted Ruby files pass `bundle exec rubocop` cleanly against the baseline thresholds without exclusions.
- **SC-002**: 100% of the existing RSpec tests for the 6 targeted files continue to pass successfully.
- **SC-003**: 0 new exceptions or thresholds for fork-authored files exist in `.rubocop_todo.yml`.
- **SC-004**: 0 inline `# rubocop:disable` or `.rubocop_todo.yml` entries remain anywhere inside the `custom/` module.

## Assumptions

- The existing test suite provides adequate coverage for the refactored methods, meaning any behavioral changes introduced during refactoring will be caught by tests.
- Refactoring these methods by extracting helpers will be sufficient to bring them under the `Metrics/MethodLength` (19) and `Metrics/AbcSize` (26) baseline thresholds.
- The two legacy rake-task files correctly pass with the new `Max: 11` threshold in `.rubocop.yml`.
