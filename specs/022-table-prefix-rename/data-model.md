# Data Model: Table Prefix Rename

This phase purely renames the database tables for the 7 custom Kanban module entities from `matias_*` to `ichatr_*`. No new columns or relationships are being added.

## Entities

| Model | Old Table Name | New Table Name |
|-------|----------------|----------------|
| `Opportunity` | `matias_opportunities` | `ichatr_opportunities` |
| `PipelineStage` | `matias_pipeline_stages` | `ichatr_pipeline_stages` |
| `OpportunityStageChange` | `matias_opportunity_stage_changes` | `ichatr_opportunity_stage_changes` |
| `PipelineStageRequiredField` | `matias_pipeline_stage_required_fields` | `ichatr_pipeline_stage_required_fields` |
| `PipelineClosingRequiredField` | `matias_pipeline_closing_required_fields` | `ichatr_pipeline_closing_required_fields` |
| `PipelineCardFieldConfig` | `matias_pipeline_card_field_configs` | `ichatr_pipeline_card_field_configs` |
| `PipelineCurrencySetting` | `matias_pipeline_currency_settings` | `ichatr_pipeline_currency_settings` |

## Migration Changes

All existing 13 migrations that originally created these tables or added columns/indexes to them will be edited in-place:
- **Timestamps**: The `YYYY` part of the 14-digit prefix will be incremented by 100 (e.g., `2026` -> `2126`).
- **Filenames**: `matias` replaced with `ichatr`.
- **Class Names**: `Matias` replaced with `Ichatr`.
- **Content**: All symbols, strings, index names, and foreign key references mapping to `matias_` will be replaced with `ichatr_`.
