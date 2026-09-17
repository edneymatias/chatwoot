---
feature: 072-scout-overview-metrics-funnel
loop: outside-in
profile: .specify/memory/tdd-profile.md
spec_criteria: 9
planned_at: 4c3b445
updated_at: 4c3b445
suite_baseline: red
---

# Test List: Scout Overview — Summary Metrics & Funnel Distribution

## Outer loop: acceptance behaviors

One per acceptance criterion in `spec.md`. Each stays red until the feature works
end to end through its real entry point (`ScoutOverviewReportsController` request specs and `ScoutOverview.vue` page specs).

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| A1 | A Scout with handled opportunities in the selected period covering qualified, disqualified, abandoned, and in-progress outcomes renders five summary metric cards with period calculations | US1-AC1, FR-001, FR-004, FR-005 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::acceptance A1: summary metrics for Scout with handled opportunities` |
| A2 | Changing the period selector (7d, 30d, this month, last month) updates summary metric cards for the new date window without a full page reload | US1-AC2, FR-003, FR-007 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::period range filtering and switching` |
| A3 | In an account with multiple Scouts, switching the Scout selector updates cards scoped strictly to the selected Scout without data contamination | US1-AC3, FR-002, FR-007, FR-011 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::multi-scout scoping` |
| A4 | A Scout with unconfigured outcome stages (qualified, unqualified, or rescue stage nil) renders neutral placeholder ("—") for those rates without errors or division by zero | US1-AC4, FR-006 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when outcome stages are unconfigured` |
| A5 | A Scout with zero handled opportunities in the selected period displays zero counts, null rates, and renders an empty-state layout replacing charts | US1-AC5, FR-014 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when no opportunities exist in period` |
| A6 | Scout-handled opportunities distributed across pipeline stages (including human-managed stages) display correct current counts for all account pipeline stages | US2-AC1, FR-008 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::pipeline stage distribution` |
| A7 | Changing the period selector leaves the pipeline-stage distribution chart unchanged as a current snapshot | US2-AC2, FR-008 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::pipeline stage distribution (period invariance)` |
| A8 | A Scout with interest attribute definition configured displays per-stage breakdown of opportunities by interest value | US3-AC1, FR-009 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::interest by stage configured` |
| A9 | A Scout without interest attribute definition configured displays an explanatory notice and a CTA button navigating to the Scout Funnel route | US3-AC2, FR-010 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::interest by stage unconfigured` |

## Inner loop: unit behaviors

Grouped by the component from `plan.md` that owns them. Each line names one
observable result.

### `custom/app/services/reports/scout_overview_builder.rb`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U1 | Attributes opportunities to Scout by joining origin_conversation through inbox to matching scout inboxes | US1-AC3, FR-011 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::summary metrics` |
| U2 | Filters summary metrics by period range based on opportunity created_at | US1-AC2, FR-003 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::period range filtering and switching` |
| U3 | Counts In Progress opportunities in total_handled alongside outcome stages | US1-AC1, FR-005, FR-011 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::summary metrics` |
| U4 | Computes qualification_rate as percentage of total_handled rounded to 2 decimal places when qualified_stage_id is present | US1-AC1, FR-005 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::summary metrics` |
| U5 | Computes disqualification_rate as percentage of total_handled rounded to 2 decimal places when unqualified_stage_id is present | US1-AC1, FR-005 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::summary metrics` |
| U6 | Computes abandonment_rate as percentage of total_handled rounded to 2 decimal places when rescue_stage_id is present | US1-AC1, FR-005, FR-012 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::summary metrics` |
| U7 | Returns nil for qualification_rate when qualified_stage_id is nil | US1-AC4, FR-006 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when outcome stages are unconfigured` |
| U8 | Returns nil for disqualification_rate when unqualified_stage_id is nil | US1-AC4, FR-006 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when outcome stages are unconfigured` |
| U9 | Returns nil for abandonment_rate when rescue_stage_id is nil | US1-AC4, FR-006 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when outcome stages are unconfigured` |
| U10 | Returns nil for all outcome rates when total_handled is 0 to avoid division by zero | US1-AC5, FR-006 | example | DONE | `custom/spec/services/reports/scout_overview_builder_spec.rb::when total_handled is 0 (U10, U13)` |
| U11 | Returns 0.0 for rate when total_handled > 0 and zero opportunities reached that outcome stage | US1-AC1, FR-005 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when zero opportunities reached outcome stage but total_handled > 0` |
| U12 | Computes avg_messages_per_conversation excluding activity messages (message_type == 2) across origin conversations in period | US1-AC1, FR-004 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::summary metrics` |
| U13 | Returns nil for avg_messages_per_conversation when no conversations exist in the period | US1-AC5, FR-004 | example | DONE | `custom/spec/services/reports/scout_overview_builder_spec.rb::when total_handled is 0 (U10, U13)` |
| U14 | Returns pipeline_stage_distribution for all account stages ordered by position ASC | US2-AC1, FR-008 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::pipeline stage distribution` |
| U15 | Includes stages with count 0 in pipeline_stage_distribution | US2-AC1, FR-008 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::pipeline stage distribution` |
| U16 | Computes pipeline_stage_distribution across lifetime scope ignoring period range | US2-AC2, FR-008 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::pipeline stage distribution` |
| U17 | Returns configured: false for interest_by_stage when scout interest_attribute_definition_id is nil | US3-AC2, FR-010 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::interest by stage unconfigured` |
| U18 | Returns configured: true with attribute_name and per-stage value breakdown when interest_attribute_definition_id is present | US3-AC1, FR-009 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::interest by stage configured` |
| U19 | Maps opportunities with missing or nil interest attribute under 'null' key in stage breakdown | US3-AC1, FR-009 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::interest by stage configured` |
| U20 | Computes interest_by_stage across lifetime scope ignoring period range | US3-AC1, FR-009 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::interest by stage configured` |
| U45 | Inactive Scout with enabled: false retains historical opportunity data and returns valid report payload | US1-AC3, FR-011 | example | DONE | `custom/spec/services/reports/scout_overview_builder_spec.rb::when scout is disabled` |
| U46 | When outcome stages point to the same stage, each rate counts opportunities in that stage independently | US1-AC1, FR-005 | example | DONE | `custom/spec/services/reports/scout_overview_builder_spec.rb::when outcome stages point to the same stage` |

### `custom/app/controllers/api/v1/accounts/scout_overview_reports_controller.rb`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U21 | Responds with 401 Unauthorized when request is unauthenticated | US1-AC1, FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when unauthenticated` |
| U22 | Responds with 401 Unauthorized when user is not a member of the account | US1-AC1, FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when user is not a member of the account` |
| U23 | Permits agent role member via ScoutPolicy#show? and responds with 200 OK | US1-AC1, FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::summary metrics` |
| U24 | Permits administrator role member and responds with 200 OK | US1-AC1, FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when user is an administrator` |
| U25 | Responds with 422 Unprocessable Content when scout_id param is missing | US1-AC1, FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when scout_id is missing` |
| U26 | Responds with 404 Not Found when scout_id does not exist in the account | US1-AC3, FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when scout_id does not exist in account` |
| U27 | Responds with 422 Unprocessable Content when range param is missing | US1-AC1, FR-003 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when range is missing` |
| U28 | Responds with 422 Unprocessable Content when range param is not in allowed set (7, 30, this_month, last_month) | US1-AC2, FR-003 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::when range is invalid` |
| U29 | Accepts optional timezone_offset and computes timezone-aware calendar month ranges | US1-AC2, FR-003 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::timezone offset` |
| U30 | Formats response JSON matching contract with summary, pipeline_stage_distribution, and interest_by_stage | US1-AC1, US2-AC1, US3-AC1, FR-004, FR-008, FR-009 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::response contract structure` |

### `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U31 | Renders card label and formatted numeric value when value is provided | US1-AC1, FR-004 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.spec.js::numeric value` |
| U32 | Renders neutral placeholder '—' when value is null | US1-AC4, FR-006 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.spec.js::null placeholder` |
| U33 | Renders percentage symbol or custom unit suffix when specified | US1-AC1, FR-004 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.spec.js::unit suffix` |

### `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U34 | Renders select dropdown with scout options when account has more than 1 scout | US1-AC3, FR-002 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.spec.js::multi scout render` |
| U35 | Renders nothing (hidden) when account has exactly 1 scout | US1-AC1, FR-002 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.spec.js::single scout hidden` |
| U36 | Emits change event with selected scout id when user selects a different scout | US1-AC3, FR-002, FR-007 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.spec.js::selection emit` |

### `app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U37 | Renders horizontal bar chart with stages ordered by stage_position ASC | US2-AC1, FR-008 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.spec.js::stage ordering` |
| U38 | Renders stage names and counts including stages with count 0 | US2-AC1, FR-008 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.spec.js::zero count stages` |

### `app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U39 | Renders explanatory notice and CTA button navigating to scout_funnel when configured is false | US3-AC2, FR-010 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.spec.js::unconfigured cta state` |
| U40 | Renders breakdown distribution per stage when configured is true | US3-AC1, FR-009 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.spec.js::configured breakdown state` |

### `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U41 | Renders five summary cards, pipeline chart, and interest card on successful data fetch | US1-AC1, FR-004, FR-008, FR-009 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::renders full overview` |
| U42 | Renders EmptyStateLayout when total_handled is 0 | US1-AC5, FR-014 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::renders empty state` |
| U43 | Re-fetches overview report when period selector value changes without full page reload | US1-AC2, FR-007 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::period selector refetch` |
| U44 | Re-fetches overview report when scout selector value changes without full page reload | US1-AC3, FR-007 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::scout selector refetch` |

## Invariants and edge cases still to place

All invariants placed or resolved:

- Inactive Scout history: Placed as U45 (`custom/spec/services/reports/scout_overview_builder_spec.rb::when scout is disabled`) and verified green.
- Overlapping outcome stages: Placed as U46 (`custom/spec/services/reports/scout_overview_builder_spec.rb::when outcome stages point to the same stage`) and verified green.
- Attribution stability: Dropped per FR-011 and `plan.md`. Opportunity attribution is strictly defined via `scout_handled_scope` joining `origin_conversation: :inbox` to `scout.inboxes`. Because `Opportunity` stores `origin_conversation_id` rather than a direct `scout_id` foreign key, retroactive attribution across unlinked inboxes without adding new schema migration columns is architecturally out of scope per `plan.md`.
## Out of scope

Things a reader may expect on this list and the one-line reason they are absent.

- Pre-computed database cache tables or background aggregation jobs: explicitly rejected per FR-013 and Principle II in favor of on-demand indexed PostgreSQL queries.
- Role restriction restricting overview to administrators: explicitly rejected per FR-015 in favor of `ScoutPolicy#show?` allowing agents and admins.
- Editing or managing Scout outcome stages or interest definition from Overview: managed exclusively in Scout Funnel settings screen (`scout_funnel` route).
- Custom arbitrary date picker: period options are bounded to 7d, 30d, this_month, and last_month per FR-003 and existing `RangeSelector` design.

## Verification commands

Copied verbatim from `.specify/memory/tdd-profile.md` at planning time, so this
file is readable on its own:

- Single test (Ruby): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file} -e "{name}"`
- Single test (JS): `docker compose exec -T vite env TZ=UTC pnpm vitest run {file} -t "{name}"`
- Single file (Ruby): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file}`
- Single file (JS): `docker compose exec -T vite env TZ=UTC pnpm vitest run {file}`
- Full suite (Ruby): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec`
- Full suite (JS): `docker compose exec -T vite pnpm test`
- Coverage (JS): `docker compose exec -T vite pnpm test:coverage`
- Mutation (changed files): Deliberate-mutant spot check (see `.specify/memory/tdd-profile.md`)
