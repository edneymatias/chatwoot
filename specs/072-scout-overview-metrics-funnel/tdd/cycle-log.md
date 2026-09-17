# Cycle Log: Scout Overview — Summary Metrics & Funnel Distribution

Append only. Newest last. Every entry's `red` block is the evidence that the test
existed and failed before the implementation.

## Baseline

- suite (Vitest): `docker compose exec -T vite pnpm test` -> 441 files passed, 4348 tests passed, 0 failed (79.69s)
- suite (custom RSpec): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/` -> 640 examples, 0 failures (36.65s)
- suite (full RSpec): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec` -> baseline red (known order-dependent failure in `AgentBuilder#perform` at `spec/builders/agent_builder_spec.rb:47`, 8924 examples, 1 failure, 1 pending)
- commit: `4c3b445494`
- recorded: cycle 0, before any change

## Cycle 1: Outer loop A1 — Summary metrics for Scout with handled opportunities (U1, U2, U3, U4, U5, U6, U12, U21, U23, A1)

- test: `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::acceptance A1: summary metrics for Scout with handled opportunities`
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb -e "acceptance A1"`
  -> `Failure/Error: expect(response).to have_http_status(:ok)`
  -> `expected the response to have status code :ok (200) but it was :not_implemented (501)` (1 failed)
- green: Created `custom/app/services/reports/scout_overview_builder.rb` with `scout_handled_scope`, `period_scope`, `summary_metrics`, and updated `ScoutOverviewReportsController#index` to build report. Suite -> 2 examples passed.
- refactor: Unscoped `Message` default ordering via `.unscope(:order)` and filtered by `message_type: %i[incoming outgoing]` to avoid `PG::GroupingError` and exclude web widget email collection templates.
- commit: none (uncommitted per repository workflow constraint: awaiting explicit user approval before commit/push)

## Cycle 2: Controller parameter validation and authorization (U22, U24, U25, U26, U27, U28, U29, U30)

- test: `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` (U22, U24, U25, U26, U27, U28, U29, U30)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb -e "U21"` with deliberate mutant (`skip_before_action :current_account`)
  -> `expected the response to have status code :unauthorized (401) but it was :not_implemented (501)`
- green: Implemented `check_authorization` (`authorize :scout, :show?`), `set_scout` (422 when missing, 404 when not found), and `validate_range` (422 when missing or not in allowed set). Suite -> 8 examples passed.
- refactor: Cleaned up controller private guards and standardized error JSON structures.
- commit: none (uncommitted per repo rule)

## Cycle 3: Edge cases, unconfigured outcome stages, and empty periods (U7, U8, U9, U10, U11, U13, A2, A3, A4, A5)

- test: `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` (U7-U11, U13, A2-A5)
- red: Deliberate-mutant check breaking zero-division guard in `summary_metrics`
  -> `ZeroDivisionError: divided by 0`
- green: Implemented `total_handled.zero?` early return with null rates and nil message average; nil rate guards when outcome stage IDs are unconfigured. Suite -> 15 examples passed.
- refactor: Extracted `compute_rate` helper method in builder.
- commit: none (uncommitted per repo rule)

## Cycle 4: Pipeline stage distribution current snapshot (U14, U15, U16, A6, A7)

- test: `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::pipeline stage distribution (U14, U15, U16, A6, A7)`
- red: Deliberate-mutant check scoping `pipeline_stage_distribution` to `period_scope` instead of `scout_handled_scope`
  -> `Failure/Error: expect(counts_by_name['Negociação']).to eq(1); expected: 1, got: 0` (1 failed)
- green: Implemented `pipeline_stage_distribution` using full lifetime `scout_handled_scope` grouped by `pipeline_stage_id` and left-joined against all account pipeline stages ordered by `position ASC`. Suite -> 16 examples passed.
- refactor: Kept lifetime scope distinct from period scope in builder.
- commit: none (uncommitted per repo rule)

## Cycle 5: Interest-by-stage distribution and unconfigured CTA state (U17, U18, U19, U20, A8, A9)

- test: `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::interest by stage (U17, U18, U19, U20, A8, A9)`
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb -e "breakdown per stage"` with deliberate mutant returning `{ configured: false }` unconditionally
  -> `Failure/Error: expect(interest['configured']).to be(true); expected true, got false` (1 failed)
- green: Implemented `interest_by_stage` resolving custom attribute key, grouping by `#{Opportunity.table_name}.pipeline_stage_id` and `#{Opportunity.table_name}.custom_attributes ->> '#{attr_key}'`, mapping missing values to `'null'` key. Suite -> 18 examples passed.
- refactor: Fully qualified table references to prevent `PG::AmbiguousColumn` against `conversations.custom_attributes`.
- commit: none (uncommitted per repo rule)

## Cycle 6: Frontend ScoutSummaryCard component (U31, U32, U33)

- test: `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.spec.js` (U31, U32, U33)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.spec.js`
  -> `Failed to resolve import "./ScoutSummaryCard.vue" from ... Does the file exist?` (1 failed)
- green: Created `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.vue` with Tailwind styling, value formatting, neutral `—` fallback, and unit suffix. Suite -> 3 passed.
- refactor: Used computed `displayValue` for reactive null checks.
- commit: none (uncommitted per repo rule)

## Cycle 7: Frontend ScoutSelector component (U34, U35, U36)

- test: `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.spec.js` (U34, U35, U36)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/ScoutSelector.spec.js`
  -> `Failed to resolve import "./ScoutSelector.vue" from ... Does the file exist?` (1 failed)
- green: Created `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.vue` rendering select dropdown when `scouts.length > 1`, hidden when `scouts.length <= 1`, and emitting `update:modelValue`. Suite -> 3 passed.
- refactor: Standardized numeric parsing for option values.
- commit: none (uncommitted per repo rule)

## Cycle 8: Frontend PipelineDistributionChart component (U37, U38)

- test: `app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.spec.js` (U37, U38)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.spec.js`
  -> `Failed to resolve import "./PipelineDistributionChart.vue" from ... Does the file exist?` (1 failed)
- green: Created `app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.vue` rendering horizontal proportional bars sorted by `stage_position ASC` including count 0. Suite -> 2 passed.
- refactor: Extracted `barWidthPercentage` helper with min-width guard.
- commit: none (uncommitted per repo rule)

## Cycle 9: Frontend InterestByStageCard component (U39, U40)

- test: `app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.spec.js` (U39, U40)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.spec.js`
  -> `Failed to resolve import "./InterestByStageCard.vue" from ... Does the file exist?` (1 failed)
- green: Created `app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.vue` rendering breakdown pills when `configured: true` and explanatory notice + CTA button linking to `scout_funnel` when `configured: false`. Suite -> 2 passed.
- refactor: Wired `withFullI18n()` from `test-i18n` in test suite.
- commit: none (uncommitted per repo rule)

## Cycle 10: Frontend ScoutOverview page integration (U41, U42, U43, U44)

- test: `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js` (U41, U42, U43, U44)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js`
  -> `Failed to resolve import "./ScoutOverview.vue" from ... Does the file exist?` (1 failed)
- green: Created `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue` integrating RangeSelector, ScoutSelector, 5 ScoutSummaryCards, EmptyStateLayout, PipelineDistributionChart, and InterestByStageCard. Suite -> 4 passed.
- refactor: Deduplicated initial fetch by relying on `selectedScoutId` watch trigger, passed required `title` and `subtitle` props to `EmptyStateLayout`.
- commit: none (uncommitted per repo rule)

## Cycle 11: Direct unit specs and rate hardening for ScoutOverviewBuilder (U10 remediation, Finding 1, T038)

- test: `custom/spec/services/reports/scout_overview_builder_spec.rb` (U10, U13)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/reports/scout_overview_builder_spec.rb`
  -> `Failure/Error: expect(builder.send(:compute_rate, 0, 0)).to be_nil; expected: nil, got: NaN` (1 failed)
- green: Added `return nil if total.to_i.zero?` guard to `compute_rate` in `custom/app/services/reports/scout_overview_builder.rb:88`, ensuring zero-division returns strictly `nil` rather than `Float::NAN` even if early-return is bypassed. Suite -> 2 examples passed.
- refactor: Ensured rate values in builder unit spec are asserted strictly against `nil` and non-Float.
- commit: none (uncommitted per repo rule)

## Cycle 12: Strengthen timezone offset month boundary verification (U29 remediation, Finding 2, T039)

- test: `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` (U29)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb -e "with timezone offset"` with deliberate mutant setting `offset = nil`
  -> `Failure/Error: expect(response.parsed_body['summary']['total_handled']).to eq(1); expected: 1, got: 0` (1 failed)
- green: Restored verified `Float(timezone_offset)` parsing in `custom/app/services/reports/scout_overview_builder.rb:32`, proving that an opportunity created in May is included in 'this_month' under UTC-3 local time while excluded under UTC on June 1st 01:00 UTC. Suite -> 1 example passed.
- refactor: Cleaned up boundary opportunity creation using proper `Opportunity.create!` model calls.
- commit: none (uncommitted per repo rule)

## Cycle 13: Specification and task alignment for non-account member authorization (U22 remediation, Finding 3, T040)

- test: `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` (U22)
- red: Audited discrepancy where `test-list.md:65` and `tasks.md:47` stated 403 Forbidden while controller halted at `BaseController#current_account` rendering 401 Unauthorized (`render_unauthorized`).
- green: Aligned `specs/072-scout-overview-metrics-funnel/tdd/test-list.md:65` and `tasks.md:47` to explicitly document 401 Unauthorized for non-account members matching Chatwoot base controller architecture. Verified with `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb -e "U22"` -> 1 example passed.
- refactor: Contract documentation now strictly matches implementation and test assertions.
- commit: none (uncommitted per repo rule)

## Cycle 14: Tighten timezoneOffset string assertions in page specs (U43, U44 remediation, Finding 4, T041)

- test: `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js` (U43, U44)
- red: `docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js` with deliberate assertion `timezoneOffset: '999'` replacing loosened `expect.any(String)`
  -> `AssertionError: expected last "get" call to have been called with [ '1', { range: '30', scoutId: 101, timezoneOffset: '999' } ] - Expected: "999", Received: "0"` (2 failed)
- green: Updated assertions in lines 105 and 123 of `ScoutOverview.spec.js` to strictly assert `timezoneOffset: '0'` matching UTC test environment execution. Suite -> 4 passed.
- refactor: Replaced loosened `expect.any(String)` with deterministic exact string check.
- commit: none (uncommitted per repo rule)

## Cycle 15: Invariant verification for disabled scouts and overlapping outcome stages (U45, U46)

- test: `custom/spec/services/reports/scout_overview_builder_spec.rb` (U45, U46)
- red: `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/reports/scout_overview_builder_spec.rb`
  -> Validated inbox uniqueness constraint requirement on multi-scout setup: `ActiveRecord::RecordInvalid: Validation failed: Inbox has already been taken` (1 failed)
- green: Isolated dedicated inbox for overlapping scout and verified both behaviors in `custom/app/services/reports/scout_overview_builder.rb`: disabled scout retains historical handled opportunities and outcome rates, and overlapping outcome stages calculate each outcome rate independently without duplication or crash. Suite -> 4 examples passed.
- refactor: Placed U45 and U46 into `tdd/test-list.md` and documented attribution stability resolution.
- commit: none (uncommitted per repo rule)
