# Implementation Plan: RuboCop Complexity Cleanup

**Branch**: `025-rubocop-complexity-cleanup` | **Date**: 2026-08-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/025-rubocop-complexity-cleanup/spec.md`

## Summary

This plan outlines the refactoring of 6 specific fork-owned files to reduce their RuboCop complexity metrics (MethodLength, AbcSize, CyclomaticComplexity, PerceivedComplexity) by extracting private helper methods. It also permanently un-masks these offenses from `.rubocop_todo.yml` and updates the project constitution/documentation (`AGENTS.md`) with clearer rules on complexity handling.

## Technical Context

**Language/Version**: Ruby 3.2 (implied by Chatwoot stack)

**Primary Dependencies**: RuboCop, RSpec

**Storage**: N/A (Code quality only)

**Testing**: RSpec

**Target Platform**: Backend (Rails)

**Project Type**: web-service (Internal tool/quality)

**Performance Goals**: N/A (Code maintainability)

**Constraints**: Existing unit tests must continue to pass. Refactored methods must fall under standard `Metrics/MethodLength` (19) and `Metrics/AbcSize` (26). 

**Scale/Scope**: 6 Ruby files plus `.rubocop.yml`, `.rubocop_todo.yml`, and `AGENTS.md`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Upstream Compatibility First**: Pass. The refactors affect only fork-owned files and legacy exclusions remain untouched.
- **Smallest Production-Ready Change**: Pass. The changes are scoped exclusively to extracting private helpers for complex methods.
- **Adhere to Established Conventions**: Pass. This feature enforces established RuboCop conventions.
- **Dual-Tree Awareness**: Pass. Applies to specific `custom/` and `spec/` files.

## Project Structure

### Documentation (this feature)

```text
specs/025-rubocop-complexity-cleanup/
├── plan.md              
├── research.md          
├── data-model.md        
├── quickstart.md        
└── tasks.md             
```

### Source Code (repository root)

```text
.
├── .rubocop.yml
├── .rubocop_todo.yml
├── AGENTS.md
├── custom/app/models/opportunity.rb
├── custom/app/services/reports/opportunity_funnel_builder.rb
├── custom/app/services/custom/automation_rules/action_service.rb
├── lib/seeders/account_seeder.rb
└── spec/bin/sync_custom_module_hooks_spec.rb
```

**Structure Decision**: No structural changes. The changes happen directly in the identified files within the existing Chatwoot fork layout.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

(No violations)
