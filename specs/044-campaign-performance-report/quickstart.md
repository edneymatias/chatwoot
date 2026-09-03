# Quickstart: Ad Campaign Performance Report

Validation guide for confirming the feature works end-to-end once implemented. Assumes the
container dev stack is already running (`docker compose up -d`) per `CLAUDE.md`.

## Prerequisites

- An account with the Kanban/Opportunities module enabled.
- Ad campaign attribution enabled and connected for that account (`CampaignAttributionSetting`),
  with at least one opportunity whose `campaign_resolution_status` is `resolved`. The fastest way
  to get this locally is the account seeder:
  ```
  docker compose exec rails bundle exec rails runner \
    "Internal::SeedAccountJob.perform_now(Account.find(<id>))"
  ```
  (confirm the seeder produces resolved campaign-attributed opportunities; if not, resolve at
  least one manually via the Rails console for a realistic test.)
- At least one `PipelineStage` on that account's pipeline.

## Scenario 1 — Report entry hidden when not eligible (SC-004)

1. On an account with `CampaignAttributionSetting.enabled: false` (or zero resolved
   attributions), open the dashboard.
2. **Expected**: The Reports sidebar section does **not** show a "Campanhas de Anúncios" entry.

## Scenario 2 — Milestone stage designation (User Story 3, FR-001)

1. Go to pipeline stage management, edit any stage, enable "Usar como marco no Relatório de
   Campanhas de Anúncios".
2. Save. Edit a *different* stage and enable the same toggle.
3. **Expected**: The first stage's toggle is now off (re-open its edit form to confirm) — only one
   stage account-wide can hold the designation at a time.

## Scenario 3 — Report loads with full KPI set (User Story 1, FR-002 through FR-007)

1. On an eligible account (attribution enabled, resolved data present, one stage designated as
   milestone), open Reports → "Campanhas de Anúncios".
2. **Expected**: Page loads with the standard date-range filter at the top (not inline with any
   table), and 7 KPI cards: Leads, `<milestone stage name>`, Ganhos, Perdidos, Campanhas,
   Conjuntos, Criativos.
3. Cross-check `summary.leads` against `Opportunity.where.not(campaign_source_id: [nil,
   '']).where.not(campaign_resolution_status: %w[organic_post not_applicable])` count for the same
   account/date range in the Rails console.

## Scenario 4 — No milestone configured (Edge case, FR-005/FR-011)

1. Un-designate the milestone stage entirely (no stage has `campaign_report_milestone: true`).
2. Reload the report.
3. **Expected**: 6 KPI cards (no milestone card), and the breakdown table has no milestone column
   or rate column — no error, no broken layout.

## Scenario 5 — Breakdown tabs and "Não identificado" (User Story 2, FR-008 through FR-010)

1. On the loaded report, switch between "Campanhas" / "Conjuntos" / "Criativos" tabs.
2. **Expected**: Each tab re-groups the same data at the right hierarchy level, with no visible
   network request on tab switch (check browser dev tools — should be zero new XHR/fetch calls).
3. If any opportunity in range has `campaign_resolution_status: 'pending'` or a missing
   `campaign_name`, confirm it appears as a "Não identificado" row, contributing to that row's
   leads/won/lost/milestone counts but not to `summary.distinct_campaigns`.

## Scenario 6 — Date range changes refresh everything (FR-011)

1. Change the date-range filter to a narrower window.
2. **Expected**: Every KPI card and every breakdown table row updates; one new network request is
   issued (unlike the tab switch in Scenario 5).

## Automated coverage

- `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/reports/campaign_performance_builder_spec.rb custom/spec/models/pipeline_stage_spec.rb custom/spec/requests/api/v1/accounts/campaign_performance_reports_controller_spec.rb custom/spec/controllers/api/v1/accounts/campaign_attribution_settings_controller_spec.rb spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb`
- `docker compose exec vite pnpm test` (frontend — new report page, table component, and the two
  new Vuex modules)
- Full pre-release gate per `CLAUDE.md` before shipping: RuboCop, ESLint, full RSpec, full `pnpm
  test`, `bin/sync-custom-module-hooks --check`/`--audit`.
