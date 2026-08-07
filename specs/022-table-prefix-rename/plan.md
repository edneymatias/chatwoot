# Implementation Plan: Table Prefix Rename & Migration Namespace Policy

**Branch**: `022-table-prefix-rename` | **Date**: 2026-08-07 | **Spec**: [spec.md](file:///home/matias/dev/chatwoot/specs/022-table-prefix-rename/spec.md)

**Input**: Feature specification from `/specs/022-table-prefix-rename/spec.md`

## Summary

This phase renames the legacy `matias_` prefix to `ichatr_` across 7 custom Kanban module tables and their 13 associated migration files. It enforces a structural migration namespace policy by statically offsetting all custom migration timestamps by +100 years into the future, guaranteeing no timeline collisions with upstream Chatwoot migrations. A new `bin/ichatr-migration` generator wrapper will automate this timestamp shift for future custom migrations.

## Technical Context

**Language/Version**: Ruby 3.x, Node.js (for frontend testing)

**Primary Dependencies**: Ruby on Rails, ActiveRecord, RSpec

**Storage**: PostgreSQL

**Testing**: RSpec (`bundle exec rspec`), Jest/Vitest (`pnpm test`)

**Target Platform**: Linux Server / Docker (Rails monolith)

**Project Type**: Web application / Rails module refactoring

**Performance Goals**: N/A (Schema renaming, zero performance impact)

**Constraints**:
- Ensure all 13 migration files are modified in-place (filename + content) without adding a new `rename_table` migration.
- `bin/ichatr-migration` must intercept Rails generation output to mathematically offset the timestamp prefix safely.

**Scale/Scope**: 7 custom database tables, 13 custom migration files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Upstream Compatibility First**: **PASS**. The primary driver of this feature. Renaming custom tables to `ichatr_` and offsetting migration timestamps by +100 years explicitly prevents namespace and version collisions with future upstream `develop` merges.
- **Smallest Production-Ready Change**: **PASS**. Direct in-place editing of migration files and a local DB drop/re-create is the cleanest, smallest intervention for a development schema containing disposable data.
- **Adhere to Established Conventions**: **PASS**. `bin/ichatr-migration` will wrap the existing Rails generator rather than inventing a parallel framework.
- **Dual-Tree Awareness**: **PASS**. The `ichatr_` prefix applies only to custom module tables, completely isolated from OSS `app/` and `enterprise/` tables.

## Project Structure

### Documentation (this feature)

```text
specs/022-table-prefix-rename/
├── plan.md              # This file
├── research.md          # Implementation decisions & wrapper logic
├── data-model.md        # Renamed entities list & migration shift details
├── quickstart.md        # Guide for executing DB rebuild & verification
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code (repository root)

```text
# Relevant locations for this refactoring feature
bin/
└── ichatr-migration                  # [NEW] Generator wrapper script

db/migrate/
└── 2126*_*.rb                        # [MODIFIED] 13 existing custom migrations

app/models/
├── opportunity.rb                    # [MODIFIED] self.table_name
├── pipeline_stage.rb                 # [MODIFIED] self.table_name
├── opportunity_stage_change.rb       # [MODIFIED] self.table_name
├── pipeline_stage_required_field.rb  # [MODIFIED] self.table_name
├── pipeline_closing_required_field.rb# [MODIFIED] self.table_name
├── pipeline_card_field_config.rb     # [MODIFIED] self.table_name
└── pipeline_currency_setting.rb      # [MODIFIED] self.table_name

custom/app/policies/
└── opportunity_policy.rb             # [MODIFIED] raw SQL reference
```

**Structure Decision**: A flat modification of the existing Rails structure. The new wrapper script goes in `bin/` as per convention, existing migrations in `db/migrate/` are modified, and model table name overrides are updated.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*(No violations. The proposed approach fully aligns with the constitution.)*
