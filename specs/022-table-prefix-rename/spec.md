# Feature Specification: Table Prefix Rename & Migration Namespace Policy

**Feature Branch**: `ichatr-main`

**Created**: 2026-08-07

**Status**: Draft

**Input**: User description: "Phase 31: Table Prefix Rename & Migration Namespace Policy from docs/kanban/ciclo 6/11-table-prefix-rename/spec31.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Database Schema Prefix Migration (Priority: P1)

As a system developer and database administrator, I want all custom product tables and migration files renamed from the legacy `matias_` prefix to the `ichatr_` prefix, so that the custom module schema is cleanly namespaced under the official `ichatr` branding without leaving legacy prefix traces in production/development databases or ORM definitions.

**Why this priority**: Core branding and database schema cleanliness. Having legacy personal prefixes in database tables is non-professional and inconsistent with the module's target name ("ichatr").

**Independent Test**: Rebuild database from scratch (`bundle exec rails db:drop db:create db:migrate`), verify all 7 custom tables are created with `ichatr_` prefix, verify model schemas load cleanly, and perform full test suite execution.

**Acceptance Scenarios**:

1. **Given** a clean database setup, **When** running migrations, **Then** all 7 custom tables (`ichatr_opportunities`, `ichatr_pipeline_stages`, `ichatr_opportunity_stage_changes`, `ichatr_pipeline_stage_required_fields`, `ichatr_pipeline_closing_required_fields`, `ichatr_pipeline_card_field_configs`, `ichatr_pipeline_currency_settings`) are created with the `ichatr_` prefix.
2. **Given** the updated codebase, **When** searching repository code outside of documentation for `matias`, **Then** zero occurrences of the legacy prefix remain in models, policies, queries, or migration definitions.
3. **Given** the renamed tables and models, **When** running model annotation commands (`bundle exec annotaterb models`), **Then** model schema header comments are automatically updated to reflect `ichatr_` table names and fields.

---

### User Story 2 - Migration Timestamp Namespace Policy & Generator Tooling (Priority: P2)

As a contributor writing custom migrations for the fork, I want all custom migrations to use a deterministic +100-year timestamp offset policy and an automated migration generator command, so that custom migration version timestamps never collide with or reorder against upstream Chatwoot migrations.

**Why this priority**: Avoids migration ordering ambiguities and version collisions when pulling future upstream releases.

**Independent Test**: Run the new migration generator wrapper script `bin/ichatr-migration <NAME>`, verify that the generated migration filename timestamp has the +100-year offset applied automatically, and verify existing 13 custom migrations maintain relative ordering with +100-year timestamp offsets.

**Acceptance Scenarios**:

1. **Given** the 13 existing custom migration files, **When** reviewing their timestamps, **Then** all timestamps are shifted by +100 years while preserving their original relative execution sequence.
2. **Given** a developer running `bin/ichatr-migration add_custom_field_to_ichatr_opportunities`, **When** the command completes, **Then** a new Rails migration file is generated under `db/migrate/` whose timestamp prefix is set to `(current_year + 100)` while keeping the standard month, day, hour, minute, second structure.

---

### User Story 3 - Operational Quality Verification & Test Suite Parity (Priority: P3)

As an application maintainer, I want all automated unit tests, integration tests, and frontend tests to run cleanly post-migration, so that functionality is verified to be 100% regression-free across OSS and custom features.

**Why this priority**: Ensures that table renames and raw SQL query updates do not break existing features, business logic, or automated CI checks.

**Independent Test**: Execute backend (`bundle exec rspec`) and frontend (`pnpm test`) test suites against the rebuilt database and verify zero failures.

**Acceptance Scenarios**:

1. **Given** the updated models, policies, and database schema, **When** running `bundle exec rspec`, **Then** all Ruby specifications pass cleanly.
2. **Given** the updated system, **When** running `pnpm test`, **Then** all frontend tests pass cleanly.

---

### Edge Cases

- What happens if a raw SQL string query or scope (e.g. policy checks) still references `matias_opportunities`? The application would throw a database runtime exception (missing relation error). The repo-wide grep check prevents this by validating that no `matias` references remain in non-doc codebase files.
- What happens if standard `rails generate migration` is run directly instead of `bin/ichatr-migration`? Standard migration creation would generate a current-year timestamp, risking timestamp ordering overlaps with upstream. Guidelines and developer tooling ensure `bin/ichatr-migration` is the standard generator entry point for custom migrations.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST rename all 7 custom domain tables from `matias_*` to `ichatr_*`: `matias_opportunities`, `matias_pipeline_stages`, `matias_opportunity_stage_changes`, `matias_pipeline_stage_required_fields`, `matias_pipeline_closing_required_fields`, `matias_pipeline_card_field_configs`, `matias_pipeline_currency_settings`.
- **FR-002**: System MUST edit all 13 existing custom migration files under `db/migrate/` in place to update table, column, foreign key (`foreign_key: { to_table: ... }`), index definitions, class names (`CreateIchatr*`), and explicit index names to use `ichatr_*`.
- **FR-003**: System MUST update all 7 corresponding ActiveRecord models (`Opportunity`, `PipelineStage`, `OpportunityStageChange`, `PipelineStageRequiredField`, `PipelineClosingRequiredField`, `PipelineCardFieldConfig`, `PipelineCurrencySetting`) to reference `'ichatr_...'` as `self.table_name`.
- **FR-004**: System MUST update hand-crafted raw-SQL references in application policies (specifically `OpportunityPolicy`) to reference `ichatr_opportunities`.
- **FR-005**: System MUST re-stamp all 13 existing custom migration filenames and class definitions with a **+100 years** offset on their timestamp (e.g., `20260730...` → `21260730...`), preserving their exact relative chronological order.
- **FR-006**: System MUST introduce a command line wrapper `bin/ichatr-migration <NAME>` that wraps standard migration generation and automatically re-writes the generated migration filename timestamp to include the +100-year offset.
- **FR-007**: System MUST support dropping and re-migrating the local development database from scratch (`db:drop db:create db:migrate`) and regenerating `db/schema.rb` and model schema comments (`bundle exec annotaterb models`).
- **FR-008**: System MUST pass a repo-wide case-insensitive code search for `matias` outside of `docs/` with zero matches remaining.
- **FR-009**: System MUST pass all Ruby (`bundle exec rspec`) and JS/Vue (`pnpm test`) test suites cleanly post-migration.

### Key Entities

- **Custom Domain Tables**: Database tables specific to the custom module (`ichatr_opportunities`, `ichatr_pipeline_stages`, `ichatr_opportunity_stage_changes`, `ichatr_pipeline_stage_required_fields`, `ichatr_pipeline_closing_required_fields`, `ichatr_pipeline_card_field_configs`, `ichatr_pipeline_currency_settings`).
- **Migration Timestamp Offset Policy**: Structural rule applying +100 years to custom migration timestamps to guarantee non-collision with upstream migration timelines.
- **Migration Generator Wrapper**: Executable script `bin/ichatr-migration` ensuring new custom migrations adhere automatically to the +100-year timestamp offset policy.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of custom database tables (7 out of 7) use the `ichatr_` prefix with 0 legacy `matias_` table references remaining in non-doc codebase files.
- **SC-002**: 100% of custom migration files (13 out of 13) bear +100-year timestamp prefixes in chronological order under `db/migrate/`.
- **SC-003**: 100% of automated test suites (`bundle exec rspec` and `pnpm test`) pass cleanly after database re-creation.
- **SC-004**: Executing `bin/ichatr-migration` creates valid Rails migration files with future (+100 year) timestamps in 100% of invocations.

## Assumptions

- Development and local test environments do not contain persistent production data that requires non-destructive table rename migrations (`rename_table`); dropping and re-creating schema from scratch is acceptable and preferred for clean migration history.
- Upstream Chatwoot will never issue migrations dated +100 years in the future, guaranteeing collision safety.
- Documentation files in `docs/` may retain historical context references to `matias_` tables for spec history and auditing purposes.
