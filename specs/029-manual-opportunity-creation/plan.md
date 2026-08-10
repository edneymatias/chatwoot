# Implementation Plan: Manual Opportunity Creation and Conversation Start

**Branch**: `029-manual-opportunity-creation` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/029-manual-opportunity-creation/spec.md`

## Summary

Provide an entry point to create an opportunity independently of a Kanban board column, and allow starting a conversation from an unlinked opportunity by wrapping the existing `ComposeConversation.vue` component.

## Technical Context

**Language/Version**: Ruby 3.x, Node.js

**Primary Dependencies**: Rails 7.x, Vue 3 (Composition API), Tailwind CSS

**Storage**: PostgreSQL

**Testing**: RSpec, Vitest/Jest

**Target Platform**: Web Browser

**Project Type**: Web Application (Chatwoot fork)

**Performance Goals**: Standard Chatwoot performance (instant Vue reactivity for opportunity updates).

**Constraints**: Strict adherence to existing Chatwoot UI patterns (no inline CSS).

**Scale/Scope**: Impacts Opportunities list and Kanban views.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] I. Upstream Compatibility First: The approach re-uses existing components (`OpportunityCreateModal`, `ComposeConversation`) and creates isolated wrapper components. Edits to core files (like `OpportunitiesController`) are purely additive (`opportunity_update_params`) and standard.
- [x] II. Smallest Production-Ready Change: Wrapper component is much smaller than building a custom conversation starter.
- [x] III. Adhere to Established Conventions: Follows Vue Composition API and Tailwind exclusively.
- [x] V. Dual-Tree Awareness: Modifications to `OpportunitiesController` are standard. No enterprise overriding is needed.

## Project Structure

### Documentation (this feature)

```text
specs/029-manual-opportunity-creation/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
app/
├── controllers/api/v1/accounts/opportunities_controller.rb
├── models/opportunity.rb
├── javascript/dashboard/
│   ├── components/
│   │   └── widgets/conversation/StartOpportunityConversationButton.vue
│   ├── routes/dashboard/opportunities/
│   │   ├── OpportunitiesViewBar.vue
│   │   ├── KanbanCard.vue
│   │   └── OpportunityListRow.vue
│   └── store/modules/opportunities.js

spec/
├── models/opportunity_spec.rb
├── controllers/api/v1/accounts/opportunities_controller_spec.rb
```

**Structure Decision**: Additive frontend components under `app/javascript/dashboard` and additive changes to existing core models and controllers.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | N/A |
