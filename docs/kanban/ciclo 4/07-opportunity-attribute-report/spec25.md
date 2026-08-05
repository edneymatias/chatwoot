# Phase 25: Opportunity Attribute Report

**Depends on**: Phase 1 (backend core — `Opportunity.custom_attributes`),
Phase 21 (Opportunity Funnel Report — establishes the created-in-period vs.
closed-in-period vs. not-period-filtered cohort semantics this phase
reuses, and ships `closed_at`), existing `custom_attribute_definitions`
endpoint (`Api::V1::Accounts::CustomAttributeDefinitionsController`)

## Context

A new standalone page in the Reports module — menu entry **"Oportunidades"**
— not a chart on the funnel report page (Phase 21) and not an extension of
the existing conversation-scoped drilldown infra
(`V2::Reports::DrilldownBuilder`, which only groups by time buckets and has
no concept of a custom-attribute dimension). The user picks one **list-type**
`opportunity_attribute` custom attribute (e.g. "Interesse": implantes,
próteses, ortodontia, alinhadores, outros) and a date range; the page lists
one row per possible value of that attribute, with aggregate opportunity
metrics per value. Modeled directly on the existing Label Reports pattern
(`SummaryReports.vue` + `V2::Reports::LabelSummaryBuilder`) — one row per
category, aggregated metrics per row — applied to opportunities instead of
conversations/labels.

List-type custom attributes store a **single string value** per record
(`CustomAttribute.vue`'s `onUpdateListValue` sets `editedValue = value.name`,
a plain string), despite the multi-select-looking picker UI — so grouping
is a simple exact-match on `custom_attributes->>'#{attribute_key}'`, no
multi-value-per-record handling needed.

## Backend

**FR-001**: New `Api::V1::Accounts::OpportunityAttributeReportsController#index`,
accepting `since`, `until` (unix timestamp, same convention as
`OpportunityFunnelReportsController`) and `custom_attribute_definition_id`
(required).

**FR-002**: Validates `custom_attribute_definition_id` belongs to the
current account, has `attribute_model: opportunity_attribute`, and
`attribute_display_type: list` — returns a 422 otherwise (an operator
guessing/tampering with the param should get a clear error, not a
misleading empty report).

**FR-003**: New `Reports::OpportunityAttributeSummaryBuilder` computes, for
each value in `definition.attribute_values` **plus a synthetic "no value"
bucket** (opportunities where the attribute key is absent/blank):
- `opportunities_count` and `total_value`: sum over currently-`open`
  opportunities with that attribute value — **not period-filtered**, same
  convention as Phase 21's `pipeline_value_by_stage` (reflects current
  pipeline distribution, independent of the selected date range).
- `won_count`: opportunities with that attribute value, `status: won`,
  `closed_at` within the selected period.
- `lost_count`: same, `status: lost`, `closed_at` within the selected
  period.
- `avg_time_to_close`: average of `closed_at - created_at`, for `won`
  opportunities with that attribute value closed within the period —
  same definition as Phase 21's `sales_cycle_time` (won only; lost
  opportunities don't count toward a "time to close" average).

**FR-004**: Response shape: `{ definition: { id, attribute_key,
attribute_display_name }, rows: [{ value, opportunities_count, total_value,
won_count, lost_count, avg_time_to_close }] }`, one row per
`attribute_values` entry (in the order defined on the definition) plus the
"no value" row last, with `value: null`.

**FR-005**: No new endpoint for the attribute selector — the frontend reuses
the existing `GET custom_attribute_definitions?attribute_model=
opportunity_attribute` endpoint, filtering to `attribute_display_type ===
'list'` client-side.

**FR-006**: Empty states are non-error, matching existing report
conventions: an account with zero opportunities for a given value returns
a row with all metrics zeroed, not an omitted row or an error.

## Frontend

**FR-007**: New Reports page/route, menu entry **"Oportunidades"**,
following the existing Reports module page structure.

**FR-008**: Page layout: `ReportHeader`, an attribute selector (dropdown
populated from FR-005's filtered definitions list), the existing
report date-range filter component (same one used on the funnel report
page, Phase 21), and a table (`Table.vue`/tanstack, same pattern as
`SummaryReports.vue`) with columns: Valor · Oportunidades · Valor Total ·
Conversões · Perdas · Tempo médio de fechamento. Rows ordered per FR-004
(definition order, "Sem valor" last).

**FR-009**: "Valor Total" is formatted with `formatCurrencyAmount`
(`dashboard/constants/pipelineCurrency.js`, compact mode) — the same
currency formatting already used on `KanbanCard.vue`, no new formatting
logic.

**FR-010**: If the account has no `list`-type `opportunity_attribute`
definitions, the attribute selector is empty and the page shows an inline
empty state directing the user to create one under Custom Attributes
settings, instead of an empty/broken table.

**FR-011**: Changing the selected attribute or date range re-fetches and
re-renders the table with a loading spinner; the page itself doesn't
navigate away.

## Out of scope

- Any `attribute_model` other than `opportunity_attribute` (conversation/
  contact/company list attributes) — not part of this phase; could reuse
  `OpportunityAttributeSummaryBuilder`'s shape later if a similar need
  comes up, but not built generically now (YAGNI).
- Editing an opportunity's attribute value from this report screen
  (read-only reporting page).
- Charts/visualization beyond the table (e.g. a bar/pie breakdown) — table
  only, matching what was asked for.
- Handling of attribute values removed/renamed on the definition after
  opportunities were tagged with them — those opportunities would fall
  under "Sem valor" naturally once the value no longer matches
  `attribute_values`, no special migration/backfill logic needed.
- CSV export (existing Label Reports has a download button; not confirmed
  as required here — revisit if requested).
