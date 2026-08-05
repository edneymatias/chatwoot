# Quickstart: Validating the Opportunity Attribute Report

## Prerequisites

- Stack running: `docker compose up -d`
- An account with the `opportunities` feature flag enabled and at least one list-type
  `opportunity_attribute` custom attribute defined (e.g. "Interesse" with values `Implantes`,
  `Ortodontia`, `Alinhadores`)
- A handful of opportunities tagged with different values of that attribute, in a mix of `open`,
  `won`, and `lost` statuses, some with `closed_at` inside the last 7 days and some outside

If starting from a bare seed, use the account seeder to get realistic opportunity data:

```bash
docker compose exec rails bundle exec rails runner \
  "Internal::SeedAccountJob.perform_now(Account.find(<id>))"
```

## Backend validation

1. Confirm the definition endpoint already returns the list-type opportunity attribute (no new
   backend work here — existing endpoint, contract unchanged):
   ```bash
   docker compose exec rails bundle exec rails runner \
     "puts Account.find(<id>).custom_attribute_definitions.opportunity_attribute.where(attribute_display_type: :list).pluck(:id, :attribute_display_name)"
   ```
2. Hit the new report endpoint directly (replace `<account_id>`/`<definition_id>` and use a valid
   session cookie or API access token):
   ```bash
   curl -s "http://localhost:3000/api/v1/accounts/<account_id>/opportunity_attribute_reports?custom_attribute_definition_id=<definition_id>" \
     -H "api_access_token: <token>" | jq
   ```
   Expected: one row per `attribute_values` entry (in definition order) plus a trailing
   `value: null` row, matching the shape in
   [contracts/opportunity_attribute_report.md](./contracts/opportunity_attribute_report.md).
3. Repeat with `since`/`until` unix timestamps covering only part of your test data's closed
   opportunities, and confirm `won_count`/`lost_count`/`avg_time_to_close` change while
   `opportunities_count`/`total_value` stay the same (open-pipeline aggregates are not
   period-filtered — FR-003).
4. Confirm the 422 path: pass a `custom_attribute_definition_id` for a text-type or
   conversation-scoped attribute and confirm a 422 with a clear error body, not an empty/200
   response.

## Frontend validation

1. Log in as an administrator, navigate to **Reports → Oportunidades**.
2. Confirm on first load (per the spec's Clarifications): the first list-type opportunity
   attribute (alphabetical order) is auto-selected, the date range defaults to the last 7 days,
   and the table loads immediately with no manual interaction required.
3. Confirm every defined value has a row, in definition order, with the "no value" row last and
   zeroed rows shown (not omitted) for values with no matching opportunities.
4. Change the attribute selector to a different list-type attribute — confirm the table reloads
   with a loading indicator and the row set changes to the new attribute's values, without
   navigating away from the page.
5. Change the date range — confirm won/lost counts and average time to close update, while row
   set and open-opportunity counts/values stay the same.
6. On an account with zero list-type opportunity attributes, confirm the attribute selector is
   empty and an inline empty state guides the user to create one, instead of a broken/empty table.
7. Confirm monetary totals render using the account's standard currency formatting (same as
   `KanbanCard.vue`/the Opportunity Funnel Report), not a raw number.
8. On the same test account, time the report page's load (selection → table rendered) against the
   Opportunity Funnel Report page's load and confirm they are comparable — no perceptible extra
   delay for a similarly-sized account (SC-002).
9. Confirm no control on the page allows editing an opportunity's attribute value (view/table only,
   no inline edit affordance) — the report is read-only (FR-013).

## Automated coverage (only if explicitly requested — see CLAUDE.md)

- `custom/spec/services/reports/opportunity_attribute_summary_builder_spec.rb` — one example per
  FR-003 through FR-007 (open aggregates, won/lost period filter, avg time to close, ordering,
  zeroed rows, "no value" bucketing including renamed/removed values)
- `custom/spec/requests/api/v1/accounts/opportunity_attribute_reports_controller_spec.rb` — success
  shape, 422 on invalid/non-list/non-opportunity attribute, 403 on non-administrator / disabled
  feature flag
