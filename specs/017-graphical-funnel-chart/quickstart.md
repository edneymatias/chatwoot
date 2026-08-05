# Quickstart: Validating the Graphical Funnel Chart

## Prerequisites

- Dev stack running: `docker compose up -d` (see project `CLAUDE.md`).
- An account with pipeline stages that have distinct `accent_color` values (plus at least one
  stage with no `accent_color` set, to exercise the fallback-color path) and some opportunity
  data (seed via `docker compose exec rails bundle exec rails db:seed`, or the richer
  `Seeders::AccountSeeder` path documented in `CLAUDE.md`, if the account needs realistic funnel
  numbers).

## Backend validation (`counts` field)

No spec task is generated for this endpoint by default (per constitution's "avoid writing specs
unless explicitly asked"); validate directly instead:

1. `docker compose exec rails bundle exec rails runner "puts Reports::OpportunityFunnelBuilder.new(account: Account.first, range: 30.days.ago..Time.current).build[:conversion_funnel]"`
   — spot-check the hash shape against `contracts/conversion-funnel-data-contract.md` directly:
   confirm `counts` is present, same length/order as `labels`, and each value equals the count of
   period-created opportunities that reached that stage or later.
2. If a request/builder spec is later added for this endpoint (optional, not part of this
   feature's default task list), run it with `docker compose exec rails bundle exec rspec
   <path-to-spec>`.

## Component-level validation (frontend, independent of the backend)

1. If a `FunnelChart.spec.js` Vitest spec exists (optional — no task creates one by default, see
   plan.md Project Structure), run it with `docker compose exec vite pnpm test -- FunnelChart`
   (covers: renders one band per point, empty/single-point cases, percentage clamping, hover
   tooltip show/hide). Otherwise, skip straight to the manual check below.
2. Optionally mount `FunnelChart.vue` in Storybook/a scratch route with a hardcoded `points` array
   matching the reference image (`labels: ['1','2','3','4','5']`, `percentage: [100, 9, 3, 1, 0]`,
   `count: [2895099, 264277, 74828, 28213, 7917]`, distinct `color` per point) to visually confirm
   the curved taper, inline labels, badge-styled percentage, and hover tooltip.

## Page-level validation (end-to-end)

1. `docker compose up -d`, then open the dashboard and navigate to
   **Reports → Opportunity Funnel Report**.
2. Confirm the "Conversion Funnel" section renders the new tapering funnel shape (not bars),
   colored per pipeline stage, matching each stage's kanban lane color.
3. Confirm each visible band shows stage name, count, and a badge-styled percentage; for any band
   too narrow for inline text, hover it and confirm the tooltip shows the same three values.
4. Toggle the report's date-range filter and confirm the funnel updates (band widths/labels
   reflect the new period) without errors.
5. Confirm no other chart on the page changed (Win Rate, Pipeline Value by Stage, etc. still
   render as before).

## Expected outcome

Matches spec.md Success Criteria SC-001–SC-004: steepest drop-off is visually obvious, every
nonzero stage renders a hoverable band regardless of size, figures match what the prior bar chart
showed, and exact detail for any band is available within one hover.
