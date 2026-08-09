# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Implement unified search, sort, and filtering for opportunities across Kanban and List views. Extends `OpportunitiesController#index` with robust filtering logic and updates `OpportunitiesViewBar.vue` to own and apply local filter state without Vuex persistence.

## Technical Context

**Language/Version**: Ruby 3.x, Vue 3 / JavaScript

**Primary Dependencies**: Rails, Vue.js (Composition API)

**Storage**: PostgreSQL

**Testing**: RSpec, Jest/Vitest

**Target Platform**: Web Browser

**Project Type**: Web Application

**Performance Goals**: API response and UI render < 3 seconds

**Constraints**: Local Vue component state for filters (no URL/Vuex persistence). Search via SQL ILIKE, not a dedicated full-text engine.

**Scale/Scope**: Impacts Opportunities views (List and Kanban).

## Constitution Check

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Upstream Compatibility First**: PASSED. Changes are additive and use established controller patterns without disrupting upstream paradigms.
- **Smallest Production-Ready Change**: PASSED. Avoids heavy abstractions (e.g. separate search engines) in favor of standard Rails query methods.
- **Adhere to Established Conventions**: PASSED. Follows `ContactAPI` local filter state patterns; avoids persisting to Vuex unnecessarily.
- **Dual-Tree Awareness**: PASSED. No enterprise-specific logic conflicts detected for basic opportunity listing.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/
├── controllers/api/v1/accounts/
│   └── opportunities_controller.rb
└── javascript/dashboard/
    ├── api/
    │   └── opportunities.js
    ├── components/
    │   └── widgets/
    │       └── OpportunitiesViewBar.vue
    └── routes/dashboard/opportunities/
        ├── Index.vue
        ├── KanbanBoard.vue
        ├── KanbanColumn.vue
        └── OpportunityListView.vue
```

**Structure Decision**: The feature operates within the existing MVC structure for Chatwoot's opportunity tracking. It modifies the existing Rails controller and Vue components without introducing new major folders or modules.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
