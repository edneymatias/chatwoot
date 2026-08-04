# Quickstart: Validate the Opportunity Funnel Report

Prerequisites: stack running (`docker compose up -d`), an account with the
`opportunities` feature flag enabled, and a logged-in administrator user
(see [contracts/opportunity_funnel_report.md](contracts/opportunity_funnel_report.md)
for why administrator access is required).

## 1. Seed opportunity data

```bash
docker compose exec rails bundle exec rails runner "
  Internal::SeedAccountJob.perform_now(Account.find(<id>))
"
```

Or, for a minimal manual check, create a few opportunities directly via the
existing kanban board UI/API across at least two pipeline stages, with a mix
of `open`, `won`, and `lost` statuses and at least one assignee set.

## 2. Verify the `closed_at` callback (backend)

```bash
docker compose exec rails bundle exec rails console
```

```ruby
account = Account.find(<id>)
opp = account.opportunities.open.first
opp.update!(status: :won)
opp.reload.closed_at   # => a Time, not nil

opp.update!(status: :open)
opp.reload.closed_at   # => nil
```

Expected: `closed_at` is set on the open→won save, cleared on the reopen
save. Matches spec FR-001/FR-002.

## 3. Hit the report endpoint directly

```bash
curl -s "http://localhost:3000/api/v1/accounts/<account_id>/opportunity_funnel_reports?since=<unix_ts>&until=<unix_ts>" \
  -H "api_access_token: <admin_user_token>" | jq
```

Expected: a single JSON object with all 7 keys from
`contracts/opportunity_funnel_report.md`, each already chart-ready (no
further computation needed client-side). Confirm:
- `pipeline_value_by_stage` and `avg_time_in_stage` values do **not** change
  when you vary `since`/`until`.
- The other 5 keys **do** change when you narrow/widen the range.
- Re-run with a `since`/`until` window containing zero opportunities →
  every key is still present, period-scoped ones are empty/zero,
  `pipeline_value_by_stage`/`avg_time_in_stage` are unaffected.

## 4. Verify the report page (frontend)

1. Log in as an administrator.
2. Navigate to **Reports → Funnel** (new sidebar entry under the existing
   Reports section — the English source string; a Portuguese label appears
   only once Crowdin syncs the pt-BR translation, not from this feature's
   own `en.json` change).
3. Confirm all 7 charts render:
   - Conversion funnel (horizontal bar chart, decreasing bars)
   - Win rate (donut chart + `ReportMetricCard` headline percentage)
   - Pipeline value by stage (bar chart)
   - Average time in stage (bar chart)
   - New opportunities over time (line chart)
   - Sales cycle time (`ReportMetricCard` only, no chart)
   - Performance by assignee (bar chart)
4. Change the date-range filter (reusing the existing `ReportFilters`
   component) and confirm only the 5 period-scoped charts update.
5. Switch to an account/period with zero opportunity data and confirm the
   page loads with empty states, no error toast, no broken chart render.

## 6. Sanity-check report load time (SC-002)

With the seeded/sample account from step 1 (hundreds of opportunities across
multiple stages), open the Funnel report and compare its load time, by eye,
against an existing report page in the same account (e.g. the Overview or
CSAT report) — it should feel comparable, not noticeably slower. This is a
manual sanity check, not a load test; the endpoint issues 7 independently
grouped/aggregated SQL queries with no N+1 (per `plan.md`'s Performance
Goals), so a large gap here would indicate a missing index or an accidental
N+1 rather than expected behavior.

## Done when

- Backend: `closed_at` callback behavior matches step 2, endpoint response
  matches `contracts/opportunity_funnel_report.md` including the empty-state
  shape.
- Frontend: all 7 charts render and update correctly per section 4's steps
  3–5, load time feels comparable to other report pages per section 6, and the
  page is reachable only by administrators (non-admin users don't see the
  sidebar entry / get 403 if navigating directly).
