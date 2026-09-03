# Quickstart: Validating Funnel Search Filters and Live Totals

## Prerequisites

- Stack running: `docker compose up -d`
- An account with the Kanban/Opportunities feature enabled, at least one pipeline with 2+ stages,
  and a handful of opportunities — some with campaign attribution data populated (e.g. via
  `Custom::ReferralAttributionService`, or set directly for a quick manual test):

```
docker compose exec rails bundle exec rails runner "
  o = Opportunity.first
  o.update!(campaign_name: 'Black Friday Leads', campaign_adset_name: 'Summer Promo', campaign_ad_name: 'Ad 1', campaign_platform: 'facebook')
"
```

- Migration applied: `docker compose exec rails bundle exec rails db:migrate`

## Scenario 1 — Search matches campaign fields (User Story 1, FR-001)

1. Open the Kanban board for that account.
2. Type `black friday` into the funnel's search box.
3. **Expected**: the opportunity updated above appears in results.
4. Repeat with `facebook` (platform) and `summer` (ad group) — same opportunity should appear each time.
5. Search by an unrelated opportunity's title — confirm it still appears (no regression to
   title/contact search).

Verify the index is actually used (SC — trigram index bitmap scan, not seq scan):
```
docker compose exec rails bundle exec rails runner "
  puts Opportunity.where('title ILIKE :q OR campaign_name ILIKE :q', q: '%black%').explain
"
```
Expected: plan includes a `Bitmap Index Scan` on `index_ichatr_opportunities_on_title_and_campaign_trgm`.

## Scenario 2 — Advanced filters on campaign/date fields (User Story 2, FR-003–FR-006)

1. Open the Kanban filter modal.
2. Confirm the attribute list includes: Campaign name, Ad group, Ad, Platform, Created at,
   Updated at — labeled correctly in both `en` and `pt_BR` (switch locale to confirm).
3. Apply "Ad group contains 'summer'" → confirm only matching opportunities show.
4. Apply "Platform equals Facebook" → confirm only Facebook-attributed opportunities show, and the
   dropdown offers exactly Facebook/Instagram.
5. Apply "Created at is greater than <a past date>" → confirm the expected subset shows.
6. Clear filters → confirm the board returns to the unfiltered set.

## Scenario 3 — Live totals (User Story 3, FR-007–FR-010, bug fix)

1. Load the board with no search/filter applied. Note the header total count/value and each
   column's badge.
2. Type a search term that narrows the result set. **Expected**: header total and every visible
   column's badge update immediately (no reload) to reflect only the matching subset.
3. Clear the search, apply an advanced filter instead. **Expected**: same live update behavior.
4. Clear the filter, switch the status view to "Won". **Expected**: totals recompute to reflect
   won-only opportunities (previously stuck showing/ignoring open-only numbers).
5. Switch to "Lost", then "All" — confirm totals recompute each time.
6. Return to the default view (no search/filter, status "Open"). **Expected**: totals match exactly
   what was noted in step 1 — no regression.

Directly verify the endpoint contract (see `contracts/pipeline_stage_aggregates.md`):
```
curl -s -H "Cookie: <session>" \
  "http://localhost:3000/api/v1/accounts/<account_id>/pipeline_stage_aggregates?stage_ids[]=<id>&status=won" \
  | jq
```
Expected: `count`/`value_sum` keys (not `open_count`/`open_value_sum`), reflecting only `won`
opportunities in that stage.

## Automated verification

- `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec spec/finders/opportunities_filter_spec.rb spec/requests/api/v1/accounts/pipeline_stage_aggregates_controller_spec.rb`
- `docker compose exec vite pnpm test` (covers `pipelineStages` store action/mutation changes)
- `docker compose exec rails bundle exec rubocop` (0 offenses, full repo)
- `docker compose exec vite pnpm eslint` (0 errors)

## Rollback check

With the migration rolled back (`bundle exec rails db:rollback`) and the code changes reverted,
confirm: search/filter/totals behave exactly as before this feature (open-only totals, no campaign
fields in search/filter) — i.e. the default-view regression check (spec.md FR-009/SC-004) has a
clean before/after baseline to compare against.
