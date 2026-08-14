# Implementation Plan: Custom Date Attribute Filtering & Kanban Drag-to-Pan Navigation

**Branch**: `035-date-filter-kanban-pan` | **Date**: 2026-08-14 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/035-date-filter-kanban-pan/spec.md`

## Summary

This feature resolves a backend SQL evaluation limitation where custom date attributes in Opportunity queries were treated as exact string equality (`IN (...)`), enabling full relational date comparisons (`>`, `<`, `=`, `!=`, `days_before`, `is_present`, `is_not_present`) with safe PostgreSQL date casting. On the frontend, custom date attributes receive appropriate date operators, and the Kanban board receives smooth horizontal click-and-drag panning on desktop and touch swipe on mobile with the native horizontal scrollbar visually hidden.

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.1), JavaScript / Vue 3 (Composition API)

**Primary Dependencies**: Vuex, VueDraggable / SortableJS, TailwindCSS, ActiveRecord / PostgreSQL

**Storage**: PostgreSQL (JSONB `custom_attributes` column on `opportunities` table)

**Testing**: RSpec (`spec/controllers/api/v1/accounts/opportunities_controller_spec.rb`), Vitest (`app/javascript/dashboard/components-next/...`)

**Target Platform**: Web (Desktop Chrome/Firefox/Safari/Edge, Mobile/Tablet touch viewports)

**Project Type**: Web application (Rails + Vue 3 SPA)

**Performance Goals**: Instant drag response (<16ms 60fps), date filter queries executed within standard DB query latency (<50ms)

**Constraints**: Upstream compatibility (no breaking core tables or core Chatwoot models), Tailwind-only styling (no custom/scoped CSS), zero conflict with card drag-and-drop

**Scale/Scope**: All accounts with Kanban pipelines and custom attributes

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Upstream Compatibility First**: Decoupled changes within `custom/` and isolated component extensions without breaking shared core models.
- [x] **Smallest Production-Ready Change**: Minimal, direct edits to `opportunities_controller.rb`, `operators.js`, `filterHelper.js`, and `KanbanBoard.vue`.
- [x] **Adhere to Established Conventions**: Follows RuboCop (150-char line limit), ESLint Vue 3 Composition API `<script setup>`, Tailwind utilities only (no scoped CSS), synchronous en/pt-BR translations.
- [x] **Safe, Reversible Change Management**: Non-destructive, backward-compatible query parsing and UI event listeners.
- [x] **Dual-Tree Awareness**: Verified against OSS and Enterprise overlays.

## Project Structure

### Documentation (this feature)

```text
specs/035-date-filter-kanban-pan/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── opportunities-filter-contract.md
└── tasks.md             # Phase 2 output (generated via /speckit-tasks)
```

### Source Code (repository root)

```text
custom/app/controllers/api/v1/accounts/
└── opportunities_controller.rb                   # Custom attribute date comparison query handling

app/javascript/dashboard/
├── components-next/
│   ├── filter/
│   │   ├── operators.js                          # Date operators definition (customDateOperators)
│   │   └── helper/filterHelper.js                # Custom attribute filter operator wiring
│   └── Opportunities/
│       └── KanbanBoard.vue                       # Horizontal drag-to-pan & hidden scrollbar
└── i18n/locale/
    ├── en/opportunities.json                     # English translations if any new keys
    └── pt_BR/opportunities.json                  # Portuguese translations if any new keys

spec/
├── custom/controllers/api/v1/accounts/           # RSpec backend filter tests
│   └── opportunities_controller_spec.rb
└── javascript/
    └── dashboard/components-next/Opportunities/
        └── specs/KanbanBoard.spec.js             # Vitest frontend tests
```

**Structure Decision**: Standard Chatwoot architecture with backend customizations in `custom/app/` and frontend components in `app/javascript/dashboard/components-next/`.

## Complexity Tracking

*No constitutional violations.*
