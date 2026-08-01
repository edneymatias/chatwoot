# Implementation Plan: Card Info Enrichment & Lane Ordering

**Branch**: `006-card-info-and-ordering` | **Date**: 2026-07-31 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-card-info-and-ordering/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Enrich Kanban opportunity cards with contact avatar, assignee, and creation-date
information, and make lane ordering stable (newest-first) across reloads. The
technical approach is backend-only for data shape and ordering (extend
`Opportunity#as_json` to merge `contact`/`assignee` hashes with `avatar_url` and an
epoch-seconds `created_at`, and add `.order(created_at: :desc)` to the index query)
plus a frontend rendering change (`KanbanCard.vue` renders the contact avatar via the
existing `Avatar.vue` component and the creation date via the existing
`dynamicTime`/`shortTimestamp` helpers). No schema changes, no new serializer class,
no assignee avatar, and no new conversation-link element.

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails), Node 24.x / Vue 3.5.12 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails (ActiveRecord `as_json`), Vue 3, `date-fns` (via existing `shared/helpers/timeHelper.js`), existing `Avatarable` concern and `components-next/avatar/Avatar.vue`

**Storage**: PostgreSQL — existing `matias_opportunities` table; no schema changes

**Testing**: RSpec (`rspec-rails`) for backend, Vitest for frontend — no new specs mandated per project convention (verify manually per `quickstart.md`)

**Target Platform**: Web (Chatwoot dashboard, server-rendered API + Vue SPA)

**Project Type**: Web application (Rails API + Vue SPA), fork-specific feature under `custom/` and `components-next/Opportunities/`

**Performance Goals**: N/A — no measurable performance targets beyond existing index query behavior; ordering adds a single indexed `ORDER BY created_at`

**Constraints**: Must not add a new serializer class, DB column, or assignee avatar (per spec Assumptions); must reuse existing `Avatarable`/`Avatar.vue`/`timeHelper.js` utilities rather than new ad hoc logic

**Scale/Scope**: Single model (`Opportunity`), single controller action (`OpportunitiesController#index`), single Vue component (`KanbanCard.vue`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Upstream Compatibility First | PASS | All touched files (`custom/app/models/opportunity.rb`, `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`, `components-next/Opportunities/KanbanCard.vue`) are fork-specific; no OSS core file is modified. |
| II. Smallest Production-Ready Change | PASS | No new serializer class, no new DB column/position field, no assignee avatar — scope is intentionally minimal per spec Assumptions. |
| III. Adhere to Established Conventions | PASS | Reuses existing `Avatarable` concern, `Avatar.vue`, and `dynamicTime`/`shortTimestamp` helpers already used elsewhere (e.g. `ConversationCard.vue`) instead of inventing new patterns. |
| IV. Safe/Reversible Change Management | PASS | Backend change is an additive `as_json` merge and an `ORDER BY` clause; frontend change is additive template/markup — both easily revertable, no destructive migration. |
| V. Dual-Tree Awareness (OSS + Enterprise) | N/A | Opportunity/Kanban is entirely fork-specific code under `custom/`; it does not touch OSS `app/` core or `enterprise/`. |

No violations — Complexity Tracking left empty.

## Project Structure

### Documentation (this feature)

```text
specs/006-card-info-and-ordering/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── checklists/
    └── requirements.md  # Already present (spec quality checklist)
```

No `contracts/` directory: this feature has no new external API endpoint or schema —
it modifies the existing `Opportunity#as_json` response shape and adds an `ORDER BY`
to an existing endpoint (`GET /api/v1/accounts/:account_id/opportunities`).

### Source Code (repository root)

```text
custom/
├── app/
│   ├── models/
│   │   └── opportunity.rb                          # extend #as_json
│   └── controllers/
│       └── api/v1/accounts/
│           └── opportunities_controller.rb         # add .order(created_at: :desc)

app/javascript/
├── dashboard/components-next/Opportunities/
│   └── KanbanCard.vue                               # add contact avatar + creation date
├── dashboard/components-next/avatar/
│   └── Avatar.vue                                   # reused, unmodified
└── shared/helpers/
    └── timeHelper.js                                # reused, unmodified (dynamicTime/shortTimestamp)
```

**Structure Decision**: Fork-specific web application layout — Rails backend changes
live under `custom/app/` (mirroring the `matias_opportunities` fork convention), and
the Vue frontend change lives under the existing
`app/javascript/dashboard/components-next/Opportunities/` tree. No new
directories are introduced.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations — table intentionally left empty.
