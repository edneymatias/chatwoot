# Quickstart: Validating Scout Opportunity Value Estimation

Prerequisites: stack running (`docker compose up -d`), a seeded account with a Scout, an
`opportunity_attribute` custom attribute of `attribute_display_type: list`
(e.g. "Interesse" with options `Implante`, `Clareamento`, `Outro`), and an inbox connected to a
Meta channel (WhatsApp/Instagram referral) if validating User Story 2's ad-content path — see
`spec.md` User Story 2 for why paid-ad referral content is required for that path specifically.

Run all commands via `docker compose exec rails ...` / `docker compose exec vite ...` per
`CLAUDE.md`.

## 1. Configure the interest attribute and value table (User Story 1)

Via the dashboard: open the Scout's settings → Funnel tab (extended by this feature) → click the
list-type opportunity attribute chip as "Interest", enter a value for one or more of its options (leave at least
one, e.g. "Outro", unmapped on purpose), save.

Or directly against the model in a Rails console, for a fast backend-only check:

```ruby
scout = Scout.find(<id>)
scout.update!(
  interest_attribute_definition: CustomAttributeDefinition.find_by(attribute_key: 'interesse'),
  value_by_interest: { 'Implante' => 2500, 'Clareamento' => 400 }
)
```

**Expected**: `scout.reload.interest_attribute_definition` and `scout.value_by_interest` persist
as set. A Scout with neither configured (fresh seed data) shows unchanged behavior everywhere
else — verify by running the existing `manage_opportunity` spec suite unmodified against such a
Scout and confirming no failures (FR-003).

## 2. Ad-content classification at creation time (User Story 2)

Simulate a referral-originated conversation whose first incoming message carries a `referral`
`content_attributes` payload with `headline`/`body` text that clearly names one configured
interest option (e.g. headline: "Agende seu Implante Dentário"). Trigger `manage_opportunity`
with `action: 'create'` for that conversation (via the Scout's normal qualification flow, or
directly in a spec/console call to
`Custom::Scout::Tools::ManageOpportunity#execute`).

**Expected**:
- The created `Opportunity#custom_attributes['interesse']` equals `'Implante'`.
- The created `Opportunity#value` equals `2500` — populated before any reply from the lead.
- Repeating with ambiguous/generic ad content (or no referral at all) yields an Opportunity with
  no `interesse` attribute and no `value` set automatically — the qualification conversation
  continues asking as it does today (spec Edge Cases, FR-005).
- Repeating with ad content matching "Outro" (unmapped) yields the attribute set but `value`
  still `nil` — not `0` (FR-007).

## 3. Value stays in sync with the lead's own answer (User Story 3)

Update an existing open Opportunity's `custom_attributes` via `manage_opportunity`
(`action: 'update'`) with the interest key set to a different mapped option than any earlier
auto-classification.

**Expected**: `Opportunity#value` reflects the newly-set option's mapped amount, overriding any
earlier ad-based guess (spec User Story 3, Acceptance Scenario 2). Setting an unmapped option
(e.g. "Outro") leaves the existing `value` untouched rather than clearing it.

## 4. Forecast reflects real values (why this feature exists)

```ruby
Reports::SalesForecastCalculator.new(account: account, durations_by_stage: {...}).call
```

**Expected**: Open Scout-originated opportunities with a mapped interest now contribute their real
mapped value to `weighted_value`, instead of the `0.0` fallback documented at
`custom/app/services/reports/sales_forecast_calculator.rb:113` (SC-001).

## 5. Automated verification

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/referral_interest_classifier_service_spec.rb \
  custom/spec/services/custom/scout/value_estimation_service_spec.rb \
  custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb \
  custom/spec/models/scout_spec.rb
docker compose exec rails bundle exec rubocop custom/app/services/custom/scout custom/app/models/scout.rb custom/app/controllers/api/v1/accounts/scouts_controller.rb
docker compose exec vite pnpm eslint
```

All specs pass, RuboCop is clean (see `spec.md`'s Testing section for the exact scenarios each
spec file must cover), and ESLint is clean for the touched `ScoutFunnelTab.vue`.
