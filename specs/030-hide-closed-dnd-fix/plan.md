# Implementation Plan: Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug

**Branch**: `030-hide-closed-dnd-fix` | **Date**: 2026-08-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/030-hide-closed-dnd-fix/spec.md`

## Summary

Scope the Kanban board and List view's default opportunity query to `status: open` (mirroring
`ConversationFinder::DEFAULT_STATUS`), while leaving the existing status filter and the contact
profile panel's full-history query unaffected. Separately, fix a drag-and-drop bug where
`KanbanStatusBar.vue`'s won/lost drop zones — rendered as an absolutely-positioned overlay sharing
a SortableJS `group` with the pipeline stage columns — can register a single drop on both the
status bar and a column simultaneously, corrupting `pipeline_stage_id` on a status change. The fix
reserves dedicated, non-overlapping layout space for the drop zones while a drag is active instead
of floating them on top of the columns.

## Technical Context

**Language/Version**: Ruby (Rails, per repo `Gemfile`) for the backend; Vue 3 (Composition API,
`<script setup>`) for the frontend.

**Primary Dependencies**: Rails API controller layer (`ActiveRecord` scoping); Vuex (store
modules); `vuedraggable` (SortableJS wrapper) for Kanban drag-and-drop.

**Storage**: PostgreSQL — existing `opportunities` table and `status` column; no schema change.

**Testing**: RSpec (`spec/requests/api/v1/accounts/opportunities_controller_spec.rb`) for the
backend default-status behavior. No new frontend spec — per project convention, specs are only
added when explicitly requested, and there's no existing frontend spec coverage for the
`KanbanStatusBar`/`KanbanColumn` drag interaction to extend.

**Target Platform**: Web — Chatwoot's Rails API + Vue single-page dashboard.

**Project Type**: Web application (existing Rails + Vue monolith).

**Performance Goals**: N/A — no new performance targets; the change adds a `WHERE status = ...`
condition to an already-scoped, already-indexed query path and must not regress existing
pagination behavior.

**Constraints**: Must follow this fork's `custom/` tree convention for backend changes (the
`OpportunitiesController` already lives under `custom/app/controllers/...`, not `app/controllers/`)
and its established `app/javascript/dashboard/components-next/Opportunities/` +
`app/javascript/dashboard/routes/dashboard/opportunities/` convention for frontend changes (the
Kanban/List UI is not under `custom/` on the frontend side — it was built directly into the
dashboard tree in earlier phases, so this feature continues that existing placement rather than
introducing a new one).

**Scale/Scope**: Unaffected — same query/pagination pattern as today, only the default filter
condition changes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. Backend change is confined to
  `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`, a fork-specific file
  already isolated from upstream. Frontend changes are confined to files that don't exist upstream
  (the Opportunities/Kanban feature is entirely fork-specific). No core/shared upstream file is
  touched.
- **II. Smallest Production-Ready Change**: PASS. The plan adds one default-scoping condition
  (mirroring an existing, proven pattern from `ConversationFinder`) and one layout adjustment to
  an existing component; no speculative abstractions, flags, or new endpoints are introduced.
- **III. Adhere to Established Conventions**: PASS. Ruby changes follow existing controller
  conventions in the same file; Vue changes stay within Composition API / `<script setup>` /
  Tailwind-only styling already used by `KanbanBoard.vue` and `KanbanStatusBar.vue`.
- **IV. Safe, Reversible Change Management**: PASS. All changes are local, reversible file edits;
  no destructive or hard-to-reverse operations are involved.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (N/A). `enterprise/` has no
  Opportunities-related files (confirmed by search) — the entire Opportunities/Kanban feature is
  fork-specific (`custom/` backend, dashboard-tree frontend) and out of Enterprise's scope, so no
  Enterprise override or extension point decision is needed.

No violations to record in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/030-hide-closed-dnd-fix/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
└── app/controllers/api/v1/accounts/
    └── opportunities_controller.rb        # add default status: 'open' scoping in apply_filters

spec/requests/api/v1/accounts/
└── opportunities_controller_spec.rb       # add default-status / status=all coverage

app/javascript/dashboard/
├── store/modules/opportunities/
│   └── actions.js                         # fetchForContact: send status: 'all'
└── components-next/Opportunities/
    ├── KanbanBoard.vue                    # reserve layout space for status bar during drag
    └── KanbanStatusBar.vue                # stop floating as position:absolute overlay

# No changes needed (already inherit new backend default, per spec FR-005/FR-006):
# app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue
# app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunityListView.vue
# app/javascript/dashboard/components-next/filter/OpportunitiesFilter.vue
```

**Structure Decision**: Existing Rails + Vue monolith structure, unchanged. Backend edit stays
inside the fork's `custom/` overlay tree (Principle I); frontend edits stay inside the
already-established `app/javascript/dashboard/components-next/Opportunities/` and
`store/modules/opportunities/` locations used by every prior Kanban-related phase — no new
top-level directories or structural changes are introduced.

## Complexity Tracking

*No Constitution Check violations — section intentionally left empty.*
