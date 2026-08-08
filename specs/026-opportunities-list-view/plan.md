# Implementation Plan: Kanban List View

**Branch**: `026-opportunities-list-view` | **Date**: 2026-08-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/026-opportunities-list-view/spec.md`

## Summary

Implement a dense, read-only list view alternative to the Kanban board for opportunities. The implementation is purely frontend-focused, leveraging an existing backend API endpoint to fetch a flat list of opportunities across all stages, with the view preference (Kanban vs List) stored locally in the browser.

## Technical Context

**Language/Version**: Vue 3, JavaScript, Ruby 3.x

**Primary Dependencies**: Vuex, Tailwind CSS, Rails

**Storage**: PostgreSQL (Backend unchanged), `localStorage` (Frontend preference)

**Testing**: Jest/Vitest for frontend unit tests

**Target Platform**: Web Browser

**Project Type**: Web Application (Frontend Module)

**Performance Goals**: Smooth infinite scroll up to hundreds of items, instantaneous mode switching.

**Constraints**: The list view is strictly read-only for v1. No drag-and-drop or stage mutations.

**Scale/Scope**: Localized entirely to the frontend opportunities module (`app/javascript/dashboard/routes/dashboard/opportunities/`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. This is an additive UI layer (new components) and additive Vuex state that does not alter or conflict with existing Kanban board behavior or any backend logic.
- **II. Smallest Production-Ready Change**: PASS. Leveraging the existing un-filtered backend endpoint rather than building a new custom endpoint specifically for the list view.
- **III. Adhere to Established Conventions**: PASS. The new components will follow the established Composition API, Tailwind, and Vuex patterns.
- **V. Dual-Tree Awareness**: PASS. This is a frontend presentation change within the OSS tree and does not alter public API contracts or enterprise-specific backend behavior.

## Project Structure

### Documentation (this feature)

```text
specs/026-opportunities-list-view/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/javascript/dashboard/
├── routes/dashboard/opportunities/
│   ├── components/
│   │   ├── OpportunitiesViewBar.vue
│   │   ├── OpportunityListView.vue
│   │   └── OpportunityListRow.vue
│   └── Index.vue
└── store/modules/opportunities/
    ├── actions.js
    ├── getters.js
    ├── mutations.js
    └── state.js
```

**Structure Decision**: The feature files will be placed directly within the existing `app/javascript/dashboard/routes/dashboard/opportunities` directory where the current Kanban components reside. Vuex changes will be scoped to the existing `opportunities` store module.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*(No violations detected)*
