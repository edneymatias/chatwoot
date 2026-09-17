# Implementation Plan: Scout Overview — Recent Conversations List

**Branch**: `073-scout-overview-conversations` | **Date**: 2026-09-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/073-scout-overview-conversations/spec.md`

## Summary

Build the "Recent Conversations" section embedded at the bottom of the Scout Overview page: a paginated, filterable table displaying handled conversations for the selected Scout and period.
- **Columns**: Contact identity (name, identifier/channel handle), start timestamp, conversation duration (elapsed time between first and last message; "—" if only one message), message count (lead + Scout sum), and status badge.
- **Funnel Outcome Statuses**: Each conversation resolves to exactly one of 5 mutually exclusive statuses: `Qualified`, `Disqualified`, `Abandoned`, `In Progress`, and `Transferred without opportunity` (styled with neutral slate/gray, never categorized as a failure or disqualification).
- **Interactions**: 6 status filter pills with dynamic conversation counts (`All`, `Qualified`, `Disqualified`, `Abandoned`, `In Progress`, `Transferred without opportunity`), page-based pagination (25 items/page), synchronization with top-level Scout and Period selectors, and row click opening the native conversation transcript in a new tab (`/app/accounts/:account_id/conversations/:id`).
- **Backend**: Backed by a new collection action `GET /api/v1/accounts/:account_id/scout_overview_reports/conversations` with builder service `Reports::ScoutOverviewConversationsBuilder` querying PostgreSQL directly via `LEFT JOIN LATERAL` + `CASE` outcome classification, delivering sub-20ms query performance without any new database columns or background aggregation jobs.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7), JavaScript (Vue 3 + Vite)

**Primary Dependencies**:
- Rails, Pundit (`ScoutPolicy#show?` for authorization across all authenticated roles), `pattr_initialize`
- Vue 3 + Composition API (`<script setup>`), Tailwind CSS
- Design System: `BaseTable`, `BaseTableRow`, `BaseTableCell` (`dashboard/components-next/table/`), `PaginationFooter` (`dashboard/components-next/pagination/PaginationFooter.vue`), `Spinner` (`dashboard/components-next/spinner/Spinner.vue`), `EmptyStateLayout` (`dashboard/components-next/EmptyStateLayout.vue`)
- Time formatting: `formatDuration` from `shared/helpers/timeHelper.js`

**Storage**: PostgreSQL — zero new database tables or columns. Attribute conversations via `ichatr_scout_inboxes` join on `conversations`. Attribution to `ichatr_opportunities` via `ichatr_opportunity_conversations` lateral join. Message metrics via indexed grouped query on `messages`.

**Testing**:
- RSpec: request specs in `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` covering authorization, query filters, outcome status classifications, duration formatting, and pagination.
- Vitest: component tests in `app/javascript/dashboard/components-next/scout/overview/RecentConversationsSection.spec.js` and `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js`.

**Target Platform**: Containerized Rails + Vite dev stack (rootless Podman)

**Project Type**: Web application (Rails API backend + Vue 3 frontend)

**Performance Goals**: < 1.0s end-to-end load time on datasets of up to 10,000 conversations (SC-002). PostgreSQL query execution in < 25ms.

**Constraints**: On-demand computation only; no pre-aggregated tables or background worker jobs. No new database migrations. No new npm dependencies. Strict isolation between Scouts and accounts.

**Scale/Scope**: 1 API action on existing controller, 1 builder service, 1 API client function, 2 Vue components (`RecentConversationsSection.vue`, `ConversationStatusBadge.vue`), integration into `ScoutOverview.vue`, i18n keys for English (`en/scout.json`) and Portuguese (`pt_BR/scout.json`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| **I. Upstream Compatibility First** | ✅ PASS | All backend logic resides in `custom/` (`Reports::ScoutOverviewConversationsBuilder` and `ScoutOverviewReportsController`). Route addition is 2 lines in `config/routes.rb`. Zero edits to upstream core models or tables. |
| **II. Smallest Production-Ready Change** | ✅ PASS | Implements direct on-demand SQL query using existing indexed tables. Reuses `BaseTable`, `PaginationFooter`, `formatDuration`, and existing auth policy. No unnecessary abstractions or speculative caching layers. |
| **III. Adhere to Established Conventions** | ✅ PASS | RuboCop clean (150-char max), ESLint Airbnb+Vue 3, Tailwind utility classes only, `<script setup>`, PascalCase components, synchronized `en/scout.json` and `pt_BR/scout.json`. |
| **IV. Safe, Reversible Change Management** | ✅ PASS | Zero database migrations, zero schema alterations, purely additive query and UI presentation. |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | ✅ PASS | Scout is a fork-specific domain; checked and confirmed no `enterprise/app/` overrides exist or conflict. |
| **VI. Test-Driven Development (NON-NEGOTIABLE)** | ✅ PASS | Full TDD coverage: RSpec request specs for the new conversations endpoint and Vitest component specs for table rendering, badge styling, status filtering, and row click navigation. |

## Project Structure

### Documentation (this feature)

```text
specs/073-scout-overview-conversations/
├── plan.md              # Implementation plan (/speckit.plan output)
├── research.md          # Architecture decisions & research findings (Phase 0 output)
├── data-model.md        # Entities, status taxonomy & query logic (Phase 1 output)
├── quickstart.md        # Runnable verification guide & seed script (Phase 1 output)
├── contracts/
│   └── api.md           # API specification for conversations endpoint (Phase 1 output)
└── tasks.md             # Implementation tasks (/speckit.tasks output - Phase 2)
```

### Source Code (repository root)

**Backend** (`custom/`):
```text
custom/app/controllers/api/v1/accounts/
└── scout_overview_reports_controller.rb   # Add :conversations action

custom/app/services/reports/
└── scout_overview_conversations_builder.rb # New builder service

config/
└── routes.rb                              # Register collection route :conversations
```

**Frontend** (`app/javascript/dashboard/`):
```text
components-next/scout/overview/
├── RecentConversationsSection.vue         # Main table container & filter pills
├── ConversationStatusBadge.vue            # 5-state status badge with neutral styling
└── RecentConversationsSection.spec.js     # Vitest component tests

routes/dashboard/scout/pages/
├── ScoutOverview.vue                      # Embed RecentConversationsSection at bottom
└── ScoutOverview.spec.js                  # Updated integration spec

api/
└── scoutOverviewReports.js                # Add getConversations(accountId, params)
```

**i18n**:
```text
app/javascript/dashboard/i18n/locale/en/scout.json     # SCOUT.OVERVIEW.RECENT_CONVERSATIONS.*
app/javascript/dashboard/i18n/locale/pt_BR/scout.json  # Synchronous Brazilian Portuguese keys
```

**Tests**:
```text
custom/spec/requests/api/v1/accounts/
└── scout_overview_reports_controller_spec.rb # Request specs covering :conversations

app/javascript/dashboard/components-next/scout/overview/
└── RecentConversationsSection.spec.js        # Vitest component spec
```

**Structure Decision**: Fully decoupled fork architecture: service in `custom/app/services/reports/`, controller extension in `custom/app/controllers/api/v1/accounts/`, frontend components in `components-next/scout/overview/`, embedded declaratively into `ScoutOverview.vue`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *None* | N/A | N/A (Standard Rails service + controller pattern; zero constitution violations). |

> **Architecture Note**: On-demand SQL classification with `LEFT JOIN LATERAL` was chosen over cached summary tables or background workers per Principle II (Smallest Change) and SC-002: in PostgreSQL, indexed grouping on up to 10,000 conversations executes in under 20ms, rendering cache invalidation logic, Redis keys, or background worker jobs unnecessary complexity.
