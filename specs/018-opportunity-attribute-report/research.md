# Phase 0 Research: Opportunity Attribute Report

## 1. Grouping opportunities by a jsonb custom attribute value

**Decision**: Use Postgres jsonb `->>` text extraction directly in `.group(Arel.sql("custom_attributes->>'#{attribute_key}'"))` / `.where("custom_attributes->>'#{attribute_key}' = ?", value)` style queries, with the attribute key interpolated from the already-validated `CustomAttributeDefinition#attribute_key` (never raw user input) to avoid SQL injection.

**Rationale**: This idiom is already established elsewhere in the codebase (`Account` model and `DeleteAccountsJob` both query `custom_attributes->>'marked_for_deletion_at'`), so it's a house convention, not a new pattern. `attribute_key` only ever comes from an ActiveRecord-loaded `CustomAttributeDefinition` scoped to the current account (FR-002), so it's never attacker-controlled — no parameterization risk.

**Alternatives considered**: Loading all opportunities into Ruby and grouping in-memory — rejected, doesn't scale and duplicates work Postgres already does efficiently; a jsonb GIN/expression index — not needed at this data volume (opportunity counts are per-account, in the hundreds per FR/SC-002), can be added later without changing the query shape if it ever becomes necessary.

## 2. "No value" bucket detection

**Decision**: An opportunity falls into the "no value" bucket when `custom_attributes->>'#{attribute_key}'` is `NULL` (key absent) **or** its value is not present in the definition's current `attribute_values` list (renamed/removed value, per spec Edge Cases). Computed by first grouping all opportunities by their raw stored value, then bucketing any group whose key isn't one of the definition's current values into "no value" alongside the truly-missing-key group.

**Rationale**: Matches the spec's explicit assumption that renamed/removed values are treated the same as missing values, with no backfill/migration. A single SQL `GROUP BY` already returns per-raw-value aggregates; reconciling that against `attribute_values` in Ruby (a small, bounded list) is cheap and avoids a more complex SQL `CASE WHEN value IN (...)` expression for a negligible perf gain.

**Alternatives considered**: A SQL `CASE WHEN custom_attributes->>'key' = ANY(values) THEN value ELSE NULL END` grouping expression — rejected as unnecessary complexity; the two-step Ruby reconciliation is simpler and just as correct at this scale.

## 3. Reusing the funnel report's period-cohort conventions

**Decision**: Mirror `Reports::OpportunityFunnelBuilder` exactly: `opportunities_count`/`total_value` come from `account.opportunities.open` grouped by attribute value, never filtered by `since`/`until` (same convention as `pipeline_value_by_stage`); `won_count`/`lost_count`/`avg_time_to_close` come from `account.opportunities.where(closed_at: range)` further filtered by `status: :won`/`:lost`, matching `win_rate`/`sales_cycle_time`.

**Rationale**: FR-003/FR-004/FR-005 explicitly restate these conventions from Phase 21; reusing the identical `period_created_opportunities`/`period_closed_opportunities`-style private helpers (rewritten as `period_closed_opportunities` scoped additionally by attribute value) keeps the two builders' semantics provably consistent without sharing a base class (YAGNI — no third builder exists yet to justify extracting one).

**Alternatives considered**: Extracting a shared `Reports::OpportunityCohortHelpers` module now — rejected per Constitution Principle II (smallest production-ready change); revisit only if a third opportunity-report builder needs the same helpers.

## 4. Attribute selector data source

**Decision**: Reuse the existing `GET custom_attribute_definitions?attribute_model=opportunity_attribute` endpoint (`Api::V1::Accounts::CustomAttributeDefinitionsController`, core/unmodified), filtering client-side to `attribute_display_type === 'list'`. No new backend endpoint for listing selectable attributes.

**Rationale**: Explicitly matches the source phase doc's FR-005 and avoids duplicating an already-correct, account-scoped, authorized endpoint. `CustomAttributeDefinitionsController` already supports the `attribute_model` filter param server-side; the `list`-only filter is a one-line `.filter()` in the Vuex getter/component, consistent with how thin client-side filters are already used elsewhere in the dashboard.

**Alternatives considered**: A new `attribute_display_type` query param on the core controller — rejected, would require editing a core OSS controller file (Constitution Principle I forbids this without an extension point, and none is needed here since client-side filtering is trivial and the full list is already small).

## 5. Frontend table & selector components

**Decision**: Table: new `OpportunityAttributeReportTable.vue`, structurally mirroring `AssigneePerformanceTable.vue` (tanstack `useVueTable` + `Table.vue` + `Pagination.vue`), but simpler — no per-row cross-join against an external collection (agents), since rows come directly from the API response in server-decided order (FR-006). Attribute picker: `components-next/select/Select.vue`, the existing generic single-choice `{ value, label }` dropdown already used for comparable pickers elsewhere in `components-next`.

**Rationale**: `AssigneePerformanceTable.vue` is the closest existing precedent for a small, non-paginated-in-practice (page size 10, rarely more than a handful of attribute values) tanstack table inside a report page — reusing its shape keeps the new component trivial. `Select.vue`'s `options: { value, label }[]` prop shape maps directly onto `{ value: definition.id, label: definition.attribute_display_name }`.

**Alternatives considered**: `SelectMenu.vue` / `ComboBox.vue` — both support richer interactions (search, multi-select) not needed for a small, single-choice list of attributes; `Select.vue` is the minimal fit.
