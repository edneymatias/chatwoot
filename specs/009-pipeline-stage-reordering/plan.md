# Implementation Plan: Pipeline Stage Reordering

**Branch**: `009-pipeline-stage-reordering` | **Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-pipeline-stage-reordering/spec.md`

## Summary

The Pipeline Stages settings screen already lets admins drag a stage to a new position (via `vuedraggable`) and already dispatches a `pipelineStages/update` call with `{ id, position }` for the moved stage. The backend `PipelineStagesController#update` only persists that one record's `position`, so sibling stages keep their old values — positions collide, order is not actually preserved, and the Kanban board (which reads the same `stagesSortedByPosition` getter) can end up showing a stale/broken column order. The fix is entirely a persistence-and-sync problem, not a new UI: make `PipelineStage#update` (when `position` changes) renumber every affected sibling atomically within the account, and have the reorder response return the full, freshly-ordered stage list so the frontend store — and therefore every screen that reads it (settings list, Kanban board) — stays in sync. The drag-and-drop settings screen also gets a try/catch around the reorder dispatch so a failed save reverts the visual order and surfaces an error, per User Story 3.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7), JavaScript (Vue 3, Composition API)

**Primary Dependencies**: Rails/ActiveRecord, Pundit (authorization), Vuex, `vuedraggable` (already in use), Vitest/RSpec for tests

**Storage**: PostgreSQL — `matias_pipeline_stages` table (fork-specific, prefixed per Constitution Principle I), column `position:integer, null: false`

**Testing**: `bundle exec rspec` (model + request specs), `pnpm test` (Vitest, only if the existing settings screen already has coverage worth extending — per repo convention, do not add specs speculatively)

**Target Platform**: Existing Chatwoot web dashboard (Rails API + Vue SPA), no new platform

**Project Type**: Web application (existing Rails + Vue monorepo)

**Performance Goals**: Reorder save completes well within normal interactive request latency (no batch/background processing needed — pipeline stage lists are small, typically single-digit to low tens of records per account)

**Constraints**: Must not introduce a new gem/dependency for something this small (Constitution Principle II); must keep the change inside `custom/` (model/controller) and existing `app/javascript` files already owned by this feature (Constitution Principle I); no new permission model (reuses existing `PipelineStagePolicy#update?`)

**Scale/Scope**: Single account's pipeline stages only (typically < 20 stages); no cross-account or bulk-import reordering in scope

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. All backend changes stay inside `custom/app/models/pipeline_stage.rb` and `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`, both already fork-specific/isolated files under the `custom/` tree with a fork-prefixed table (`matias_pipeline_stages`). Frontend changes stay inside the existing feature's own files (`store/modules/pipelineStages/*`, `routes/dashboard/settings/pipelineStages/Index.vue`) — no core/upstream file is touched. No renaming/restructuring of upstream files.
- **II. Smallest Production-Ready Change**: PASS. Reuses the existing `PATCH .../pipeline_stages/:id` endpoint and existing `update` Vuex action/mutation shape rather than introducing a new bulk-reorder endpoint or a position-management gem (e.g. `acts_as_list`). No speculative features (bulk drag of multiple stages, cross-account reorder, etc.) are added.
- **III. Adhere to Established Conventions**: PASS. Ruby changes follow existing RuboCop conventions; Vue changes stay in Composition API/`<script setup>`; no new bare strings (existing `useAlert`/i18n error messaging reused for the failure-revert path).
- **IV. Safe, Reversible Change Management**: PASS. All position updates happen inside a single DB transaction with row locking to avoid partial/corrupted reorders; no destructive migrations needed (the `position` column already exists).
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. Confirmed via `grep -rl "PipelineStage" enterprise/` — no matches. Pipeline stages are not touched by the enterprise overlay, so no Enterprise-side change or extension point is needed.

No violations to justify in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/009-pipeline-stage-reordering/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
└── app/
    ├── models/
    │   └── pipeline_stage.rb                 # add position-renumbering logic on update
    └── controllers/api/v1/accounts/
        └── pipeline_stages_controller.rb      # #update: return full reordered list on position change

app/javascript/dashboard/
├── api/
│   └── pipelineStages.js                      # no change (existing update() call reused)
├── store/modules/pipelineStages/
│   ├── actions.js                             # update: handle list-shaped response, resync full collection
│   └── mutations.js                           # add SET_STAGES (or reuse CLEAR+ADD_MANY) for full resync
├── routes/dashboard/settings/pipelineStages/
│   └── Index.vue                              # onChange: try/catch, revert local order + alert on failure
└── components-next/Opportunities/
    └── KanbanBoard.vue                        # no change — already reads stagesSortedByPosition getter

spec/
├── models/pipeline_stage_spec.rb                                 # new (if added — see note above)
└── requests/api/v1/accounts/pipeline_stages_controller_spec.rb    # new (if added — see note above)
```

**Structure Decision**: Existing web application layout (Rails API in `custom/app/`, Vue SPA in `app/javascript/dashboard/`) is reused as-is. This is a persistence/sync bug-fix-shaped feature layered onto already-existing files; no new top-level structure, service objects, or endpoints are introduced.

## Complexity Tracking

*No Constitution Check violations — table intentionally omitted.*
