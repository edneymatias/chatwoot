# Implementation Plan: Frontend Board — Kanban UI, Vuex Store, Settings

**Branch**: `003-kanban-frontend-board` | **Date**: 2026-07-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-kanban-frontend-board/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Deliver the frontend for the Kanban board introduced in Phase 1 (backend `PipelineStage`/`Opportunity` models) and wired into automation in Phase 2 (`create_opportunity` action). This phase adds: a normalized Vuex store module for opportunities and pipeline stages; a `KanbanBoard`/`KanbanColumn`/`KanbanCard` component set with drag-and-drop stage transitions and per-column infinite-scroll pagination; a manual opportunity creation modal; a card detail view with a Mark as Won/Lost/Reopen action; a "Pipeline Stages" settings screen for admins to create/rename/reorder/delete stages (delete blocked while occupied); and an extension of the existing Automation Rules action picker to expose `create_opportunity` with a pipeline-stage parameter. All new code lives in self-contained directories (components, store module, API clients, i18n file) so it stays easy to diff and re-apply against upstream Chatwoot, per the project's Upstream Compatibility First principle — the only touches to existing shared files are additive registration points (route table, action-type list, i18n index).

## Technical Context

**Language/Version**: JavaScript (Vue 3.4, `<script setup>` Composition API), consistent with the rest of `app/javascript/dashboard`.

**Primary Dependencies**: Vue 3, Vuex 4, Vue Router 4, `vuedraggable` (existing dependency, new usage pattern: `:model-value` one-way binding + shared `group` prop for cross-column drag), Tailwind (next-gen `n-*` design tokens), existing `ApiClient` base class for REST calls, existing i18n (`vue-i18n`) setup.

**Storage**: N/A client-side; persists via the existing Rails REST API for `PipelineStage`/`Opportunity` built in Phase 1. No schema/migration changes in this phase; two small additive controller-param changes are required as prerequisites (see `research.md` §9): `pipeline_stage_id`/`page` query support on `OpportunitiesController#index`, and permitting `:position` on `PipelineStagesController#update`.

**Testing**: `vitest` + `@vue/test-utils`, matching existing dashboard component/store specs (`docker compose exec vite pnpm test`).

**Target Platform**: Browser (Chatwoot dashboard SPA).

**Project Type**: Web application — this phase is frontend-only within the existing single Rails+Vue monorepo (no separate `frontend/`/`backend/` split; Chatwoot's `app/javascript/dashboard` is the SPA source tree).

**Performance Goals**: Column render and infinite scroll have no specific req/s target since this is a client-rendered UI over existing paginated REST endpoints, sized for typical account data volumes (tens to low hundreds of opportunities per stage). Drag-drop is decoupled from network latency by design: `opportunities/moveCard` (FR-005) updates the card's stage in Vuex state synchronously on drop, before the PATCH resolves, so the UI reflects the move immediately regardless of API response time; a failed PATCH reverts the optimistic update (SC-002).

**Constraints**: Must not introduce full-array rescans/rebuilds on single-card mutations (normalized `byId`/`allIds`-style state per the project's established Vuex convention); must reuse the existing `vuedraggable` dependency rather than adding a new drag library; must follow existing design-token/Tailwind-only styling rules (no custom or scoped CSS); must not alter behavior of any existing Automation Rules action.

**Scale/Scope**: One Vuex module (opportunities + pipeline stages), ~3 board components (Board/Column/Card) + manual-create modal + detail view, one settings screen (list/create/rename/reorder/delete), one API client pair, one action-picker extension, one new i18n file.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)** — PASS. All new Vue components, the Vuex module, and API clients live in new, self-contained files/directories (e.g. `store/modules/opportunities/`, `store/modules/pipelineStages/`, a dedicated `opportunities`/`kanban` component tree, a new `opportunities.js`/`pipelineStages.js` API client pair, a new `i18n/locale/en/opportunities.json`). The only edits to existing shared files are additive registration points that upstream Chatwoot expects extensions to touch: the Vuex store index (module registration), the dashboard route table (new settings route), `AUTOMATION_ACTION_TYPES` in `settings/automation/constants.js` (one new entry), `AutomationActionInput.vue` (at most one new `v-else-if` branch if a new `inputType` is required), and the i18n locale index (one new import). No core file is rewritten wholesale.
- **II. Smallest Production-Ready Change** — PASS. Reuses existing conventions end-to-end (normalized Vuex shape modeled on `helpCenterCategories`, drag reorder pattern modeled on `CategoryList.vue`, action-picker `inputType` pattern, `ApiClient` base class, one-file-per-feature i18n) instead of introducing new abstractions or a new drag/state library.
- **III. Adhere to Established Conventions** — PASS. Tailwind-only styling with `n-*` tokens, Composition API with `<script setup>`, PascalCase components, i18n via `en.json` (no bare strings), strong param-equivalent prop validation via Vue `props`.
- **IV. Safe, Reversible Change Management** — PASS. Feature ships behind its own routes/components; no destructive migrations (none in this phase); existing Automation Rules and Settings screens remain functionally unchanged for accounts not using Opportunities.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS (no action needed). Automation Rules UI and Settings navigation are OSS-only surfaces in this codebase; no Enterprise-specific dashboard overrides were found for these screens. Will re-confirm in Phase 0 research if any enterprise dashboard override of Automation Rules/Settings exists.

No violations requiring Complexity Tracking.

**Post-Phase 1 re-check**: Design artifacts (`data-model.md`, `contracts/`) introduced two small additive backend controller-param changes (`research.md` §9) — no new tables/migrations, no rewritten controllers, consistent with Principle I (only additive touches to existing Phase 1 files) and Principle II (smallest change needed to make FR-002/FR-004/FR-010 implementable). All five gates remain PASS.

## Project Structure

### Documentation (this feature)

```text
specs/003-kanban-frontend-board/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/javascript/dashboard/
├── api/
│   ├── opportunities.js                     # NEW — ApiClient subclass, CRUD + move/status endpoints
│   └── pipelineStages.js                    # NEW — ApiClient subclass, CRUD + reorder endpoint
├── store/modules/
│   ├── opportunities/                       # NEW — normalized byId/allIds-by-stage Vuex module
│   │   ├── index.js
│   │   ├── getters.js
│   │   ├── mutations.js
│   │   └── actions.js
│   └── pipelineStages/                      # NEW — normalized byId/allIds Vuex module
│       ├── index.js
│       ├── getters.js
│       ├── mutations.js
│       └── actions.js
│                                             # NOTE: registering these modules in store/modules/index.js
│                                             # is a Phase 4 responsibility per spec.md Assumptions — not touched here.
├── components-next/Opportunities/           # NEW — board + card components
│   ├── KanbanBoard.vue
│   ├── KanbanColumn.vue
│   ├── KanbanCard.vue
│   ├── OpportunityCreateModal.vue
│   └── OpportunityDetailView.vue            # includes Mark as Won/Lost/Reopen action
├── routes/dashboard/settings/pipelineStages/  # NEW — admin settings screen
│   ├── Index.vue
│   ├── PipelineStageList.vue                # drag-to-reorder, modeled on CategoryList.vue
│   └── PipelineStageForm.vue
├── routes/dashboard/settings/automation/
│   ├── constants.js                         # EDIT — add `create_opportunity` to AUTOMATION_ACTION_TYPES
├── components/widgets/
│   └── AutomationActionInput.vue            # EDIT — add branch only if a new inputType is required
├── composables/
│   └── useAutomationValues.js               # EDIT — add `create_opportunity` case for stage dropdown options
└── i18n/locale/en/
    ├── opportunities.json                   # NEW — board/settings/detail-view strings
    ├── automation.json                      # EDIT — add ACTIONS.CREATE_OPPORTUNITY label
    └── index.js                             # EDIT — register opportunities.json import

# NOTE: dashboard.routes.js / settings.routes.js registration for the board and Pipeline
# Stages settings screen is explicitly out of scope for this phase (spec.md Assumptions) —
# components/screens are fully built but wired into navigation/routes in Phase 4.

tests/ (dashboard specs, colocated per existing convention)
├── store/modules/opportunities/**/*.spec.js
├── store/modules/pipelineStages/**/*.spec.js
└── components-next/Opportunities/**/*.spec.js
```

**Structure Decision**: Single monorepo, frontend-only change within the existing `app/javascript/dashboard` SPA tree (Chatwoot has no separate `frontend/`/`backend/` split — Option 2 from the template doesn't apply literally, but conceptually this phase is the "frontend" half of the multi-phase Kanban feature, with Phase 1's Rails models as its "backend"). New feature code is isolated into dedicated files/directories (`api/opportunities.js`, `store/modules/opportunities/`, `store/modules/pipelineStages/`, `components-next/Opportunities/`, `routes/dashboard/settings/pipelineStages/`, `i18n/locale/en/opportunities.json`) per Constitution Principle I. This phase's only edits to shared files are the automation action picker's `constants.js`/`useAutomationValues.js` (in scope per US5/FR-012/FR-013) and the i18n locale index; global Vuex store registration and route table wiring (`store/modules/index.js`, `dashboard.routes.js`, `settings.routes.js`) are explicitly deferred to Phase 4 per this spec's Assumptions — this phase delivers fully built but not-yet-registered components, store modules, and screens.

## Complexity Tracking

*No violations — table omitted.*
