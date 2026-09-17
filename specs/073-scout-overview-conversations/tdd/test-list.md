---
feature: 073-scout-overview-conversations
loop: outside-in
profile: .specify/memory/tdd-profile.md
spec_criteria: 7
planned_at: 4c3b445494
updated_at: 4c3b445494
suite_baseline: red # ruby full suite red baseline due to upstream order-dependent agent_builder_spec test pollution; js suite is green (446 files, 4362 tests passed); targeted scout ruby specs green (24 examples, 0 failures)
---

# Test List: Scout Overview — Recent Conversations List

## Outer loop: acceptance behaviors

One per acceptance criterion in `spec.md`. Each stays red until the feature works
end to end through its real entry point.

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| A1 | On Scout Overview page with handled conversations in active period, Recent Conversations table renders rows with contact identity, start time, duration, message count, and status badge | AC-1, FR-001, FR-004 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::renders table with 5 columns` |
| A2 | Clicking a status filter pill filters table rows to that outcome and displays the count of matching conversations in the active period | AC-2, FR-002, FR-003 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::filters rows by status pill and displays counts` |
| A3 | In paginated view with more than 25 conversations, clicking next page in pagination footer requests and displays page 2 records without full page reload | AC-3, FR-010 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::navigates to page 2 via pagination footer` |
| A4 | Changing active period selector or scout selector on Overview page reloads Recent Conversations table and status pill counts for updated selection | AC-4, FR-009 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::synchronizes recent conversations when period or scout changes` |
| A5 | Handled conversation transferred to human agent with no opportunity displays status badge "Transferred without opportunity" with neutral slate styling and is never classified as Disqualified | AC-5, FR-005, FR-006, SC-003 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::displays transferred without opportunity with neutral styling` |
| A6 | Clicking anywhere on a conversation row invokes window.open with URL `/app/accounts/:account_id/conversations/:id`, target `_blank`, and `noopener,noreferrer` | AC-6, FR-012, SC-004 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::opens conversation in new tab on row click` |
| A7 | Clicking a conversation with missing ID or when popup is blocked shows an informative warning/error notification instead of crashing | AC-7, FR-014 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::handles missing conversation ID or blocked popup gracefully` |

## Inner loop: unit behaviors

Grouped by the component from `plan.md` that owns them. Each line names one
observable result.

### `custom/app/controllers/api/v1/accounts/scout_overview_reports_controller.rb`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U1 | Rejects unauthenticated request to `GET .../scout_overview_reports/conversations` with 401 Unauthorized | FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations unauthenticated` |
| U2 | Rejects request from user who is not a member of the account with 401 Unauthorized | FR-015 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations non-member` |
| U3 | Permits authenticated agent or administrator to access conversations report with 200 OK | FR-015, AC-1 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations authorized member` |
| U4 | Rejects request missing `scout_id` parameter with 422 Unprocessable Content and error message "scout_id is required" | contracts/api.md | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations missing scout_id` |
| U5 | Rejects request with `scout_id` belonging to a different account with 404 Not Found | contracts/api.md, SC-005 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations cross-account scout_id` |
| U6 | Rejects request with missing or invalid `range` parameter with 422 Unprocessable Content and error message "range is invalid or missing" | contracts/api.md | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations invalid range` |
| U7 | Rejects request with invalid `status` parameter (not in allowed list) with 422 Unprocessable Content and error message "status is invalid" | contracts/api.md | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations invalid status` |
| U8 | Accepts request with valid `status` parameter (`all`, `qualified`, `disqualified`, `abandoned`, `in_progress`, `transferred_without_opportunity`) with 200 OK | contracts/api.md, AC-2 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations valid status` |
| U9 | Caps `per_page` query parameter at maximum 100 records per page | contracts/api.md, FR-010 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations per_page cap` |
| U10 | Defaults `page` query parameter to 1 when `page` is less than 1 or omitted | contracts/api.md, FR-010 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::GET /conversations page default` |

### `custom/app/services/reports/scout_overview_conversations_builder.rb`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U11 | Restricts handled conversations to inboxes assigned to the Scout within the account | FR-005, SC-005 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder restricts to scout inboxes` |
| U12 | Classifies conversation as `qualified` when linked opportunity stage equals `scout.qualified_stage_id` | FR-005, AC-1 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder classifies qualified status` |
| U13 | Classifies conversation as `disqualified` when linked opportunity stage equals `scout.unqualified_stage_id` | FR-005, AC-1 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder classifies disqualified status` |
| U14 | Classifies conversation as `abandoned` when linked opportunity stage equals `scout.rescue_stage_id` | FR-005, AC-1 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder classifies abandoned status` |
| U15 | Classifies conversation as `in_progress` when linked opportunity is in an intermediate stage or conversation has status `pending` | FR-005, AC-1 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder classifies in_progress status` |
| U16 | Classifies conversation as `transferred_without_opportunity` when conversation status is not pending and no linked opportunity exists | FR-005, FR-006, AC-5, SC-003 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder classifies transferred_without_opportunity` |
| U17 | Returns `duration_seconds: null` when conversation has 1 or fewer messages | FR-007, EC-2 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder duration single message null` |
| U18 | Calculates `duration_seconds` as positive difference between first and last message when conversation has 2 or more messages | FR-007 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder duration multiple messages` |
| U19 | Calculates `messages_count` as the sum of incoming and outgoing messages in the conversation | FR-008 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder messages count` |
| U20 | Orders returned conversations chronologically by start timestamp descending (most recent first) | FR-011 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder chronological ordering` |
| U21 | Calculates `status_counts` across all 5 statuses and `all` total reflecting total handled conversations in period | FR-003, AC-2 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder status counts aggregation` |
| U22 | When `status` filter is applied, filters `conversations` array to matching status while `status_counts` retains full period totals | FR-002, FR-003, AC-2 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder status filter with preserved counts` |
| U23 | Paginates results returning correct `current_page`, `per_page`, `total_count`, and `total_pages` in `pagination` envelope | FR-010, AC-3 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder pagination metadata` |
| U24 | Excludes conversations created outside resolved date range or belonging to another Scout | FR-009, SC-005 | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder period and scout scoping` |
| U25 | Resolves latest opportunity stage when conversation has multiple associated opportunity records via lateral join | plan.md, data-model.md | example | DONE | `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb::builder multiple opportunities lateral resolution` |

### `app/javascript/dashboard/api/scoutOverviewReports.js`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U26 | Calls `GET /api/v1/accounts/:account_id/scout_overview_reports/conversations` with serialized query parameters (`scout_id`, `range`, `timezone_offset`, `status`, `page`, `per_page`) | contracts/api.md, FR-009 | example | DONE | `app/javascript/dashboard/api/specs/scoutOverviewReports.spec.js::getConversations sends GET with params` |

### `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U27 | Renders green/success styling and translated label for `qualified` status | FR-005 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js::renders qualified badge` |
| U28 | Renders amber/alert styling and translated label for `disqualified` status | FR-005 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js::renders disqualified badge` |
| U29 | Renders rose/warning styling and translated label for `abandoned` status | FR-005 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js::renders abandoned badge` |
| U30 | Renders blue/info styling and translated label for `in_progress` status | FR-005 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js::renders in_progress badge` |
| U31 | Renders neutral slate styling (`bg-n-slate-3 text-n-slate-11`) for `transferred_without_opportunity` status and never applies failure/error classes | FR-006, AC-5, SC-003 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/ConversationStatusBadge.spec.js::renders transferred_without_opportunity neutral badge` |

### `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U32 | Renders table headers for Contact, Start Time, Duration, Messages, and Status columns | FR-004, AC-1 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::renders 5 table headers` |
| U33 | Renders 6 status filter pills with counts for All, Qualified, Disqualified, Abandoned, In Progress, Transferred without opportunity | FR-002, FR-003, AC-2 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::renders 6 filter pills with counts` |
| U34 | Clicking a status filter pill updates active status, resets page to 1, and re-fetches conversations | FR-002, AC-2 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::click status pill re-fetches` |
| U35 | Formats duration using `formatDuration` when `duration_seconds` is present and greater than 0 | FR-007 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::formats duration when positive` |
| U36 | Displays dash placeholder (" — ") when `duration_seconds` is null or `messages_count` is 1 | FR-007, EC-2 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::displays dash placeholder for single message` |
| U37 | Truncates long contact names and phone numbers with Tailwind truncation classes to prevent row overflow | EC-5, FR-004 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::truncates long contact names` |
| U38 | Renders `EmptyStateLayout` when conversation list is empty for the active filter/period | FR-013, EC-1 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::renders empty state layout` |
| U39 | Renders `PaginationFooter` and re-fetches on page change event | FR-010, AC-3 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::renders pagination and fetches page` |
| U40 | Renders loading spinner while fetching conversations | plan.md | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::renders spinner during loading` |
| U41 | Invokes `window.open` with URL `/app/accounts/:account_id/conversations/:id`, `_blank`, and `'noopener,noreferrer'` on row click | FR-012, AC-6, SC-004 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::row click opens window` |
| U42 | Does not call `window.open` and triggers warning notification when conversation ID is missing or invalid | FR-014, AC-7 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::missing conversation id warning` |
| U43 | Displays warning notification when `window.open` returns null (popup blocked) | FR-014, AC-7 | example | DONE | `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js::blocked popup warning` |

### `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue`

| id | behavior | traces | kind | state | test |
| --- | --- | --- | --- | --- | --- |
| U44 | Embeds `RecentConversationsSection` at the bottom of the overview page passing `scoutId`, `range`, and `timezoneOffset` props | FR-001, AC-1 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::embeds RecentConversationsSection` |
| U45 | Re-fetches recent conversations when `selectedRange` changes | FR-009, AC-4 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::re-fetches conversations on period change` |
| U46 | Re-fetches recent conversations when `selectedScoutId` changes | FR-009, EC-4, AC-4 | example | DONE | `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js::re-fetches conversations on scout change` |

## Invariants and edge cases still to place

Behaviors that belong to the feature but do not yet have a home component. Each
must become a numbered line above before the feature is done, or be dropped with
a reason.

- Invariant: Mutually exclusive outcome status classification — every conversation resolves to exactly one status: `qualified`, `disqualified`, `abandoned`, `in_progress`, or `transferred_without_opportunity`; statuses never overlap. Placed on builder behaviors U12–U16.
- Invariant: Conservation of totals — the sum of status counts for `qualified` + `disqualified` + `abandoned` + `in_progress` + `transferred_without_opportunity` equals `status_counts.all`. Placed on builder behavior U21.
- Invariant: Multi-tenant and Scout isolation — zero conversations leak from other accounts or unassociated Scouts. Placed on controller U5 and builder U11, U24.

## Out of scope

Things a reader may expect on this list and the one-line reason they are absent.

- Column re-sorting: default ordering is fixed to start timestamp descending; custom re-sorting is out of scope per spec.md.
- Real-time WebSocket streaming: conversation data is queried on demand via pagination and status filter clicks; live WebSocket sync is out of scope per spec.md.
- Custom chat viewer / embedded transcript modal: row click opens native conversation URL (`/app/accounts/:account_id/conversations/:id`) in a new browser tab; no embedded modal viewer is built per spec.md.
- Pre-aggregated database tables or background worker jobs: on-demand PostgreSQL query via `Reports::ScoutOverviewConversationsBuilder` executes sub-20ms; background caching is unnecessary complexity per plan.md.

## Verification commands

Copied verbatim from `.specify/memory/tdd-profile.md` at planning time, so this
file is readable on its own:

- Single test (Ruby): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file} -e "{name}"`
- Single file (Ruby): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec {file}`
- Full suite (Ruby): `docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec`
- Single test (JS): `docker compose exec -T vite env TZ=UTC pnpm vitest run {file} -t "{name}"`
- Single file (JS): `docker compose exec -T vite env TZ=UTC pnpm vitest run {file}`
- Full suite (JS): `docker compose exec -T vite pnpm test`
- Coverage (JS): `docker compose exec -T vite pnpm test:coverage`
- Mutation: Deliberate-mutant spot check (see `.specify/memory/tdd-profile.md`; no automated mutation tool wired in repository)
