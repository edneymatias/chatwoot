# Implementation Plan: Opportunity Activity Log

**Branch**: `040-opportunity-activity-log` | **Date**: 2026-08-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/040-opportunity-activity-log/spec.md`

## Summary

Implement a dedicated, read-only activity audit log for Opportunities in the Kanban module. Event capture is completely decoupled from core and enterprise code by leveraging the existing Wisper event dispatcher (`Custom::OpportunityActivityListener` prepended to `AsyncDispatcher` via `Custom::AsyncDispatcher`) for deal lifecycle events (`created`, `stage_changed`, `won`, `lost`, `reopened`) and an `after_create` callback on `OpportunityConversation` for conversation linkage. Data is persisted in `ichatr_opportunity_activities` with high-performance indexes and a one-time SQL migration backfill. A read-only REST endpoint serves the timeline, which is rendered in the Kanban conversation drawer via `OpportunityActivityLog.vue` using Vue 3 Composition API, Tailwind CSS, and synchronous `en` / `pt-BR` localizations.

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.1), JavaScript / Vue 3  
**Primary Dependencies**: ActiveRecord, Wisper (Chatwoot dispatcher), Vuex, Tailwind CSS, Vue Router, Lucide / Phosphor Icons  
**Storage**: PostgreSQL (`ichatr_opportunity_activities` table with `jsonb` metadata)  
**Testing**: RSpec (`custom/spec/`), Vitest / Jest (`app/javascript/`)  
**Target Platform**: Linux containerized web environment (Docker/Podman)  
**Project Type**: Full-stack web application feature (custom decoupled module)  
**Performance Goals**: Timeline query response < 200ms, instantaneous UI drawer tab swapping  
**Constraints**: Zero edits to core (`app/`) or `enterprise/` logic files; 100% Tailwind utility styling (no scoped/custom CSS); RuboCop (150-char line limit); dual `en` and `pt_BR` i18n  
**Scale/Scope**: Account-scoped timeline supporting typical deal histories (tens to hundreds of events per opportunity) without pagination in v1  

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|---|---|---|
| **I. Upstream Compatibility First** | All new models, listeners, controllers, and services reside in `custom/` with table prefix `ichatr_`. Wire-ins use existing `prepend_mod_with` on `AsyncDispatcher` and manifest entries in `bin/sync-custom-module-hooks`. Zero core or enterprise hard forks. | **PASS** |
| **II. Smallest Production-Ready Change** | Scope restricted to read-only activity logging for core lifecycle and conversation link events; no speculative integrations (calls/tasks deferred). | **PASS** |
| **III. Adhere to Established Conventions** | Follows RuboCop rules, ESLint, Tailwind utility classes exclusively, Vue 3 `<script setup>`, and synchronous `en`/`pt-BR` translations. | **PASS** |
| **IV. Safe, Reversible Change Management** | Migration provides standard `up` and `down` definitions and idempotent backfill. | **PASS** |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | Evaluated for Enterprise: uses `prepend_mod_with` and public events, remaining 100% compatible across OSS and Enterprise editions. | **PASS** |

## Project Structure

### Documentation (this feature)

```text
specs/040-opportunity-activity-log/
├── plan.md              # Implementation Plan
├── research.md          # Phase 0 decisions & architecture
├── data-model.md        # Phase 1 schema, associations, metadata
├── quickstart.md        # Phase 1 validation scenarios
├── contracts/           # Phase 1 API and component contracts
│   ├── api-activities.md
│   └── component-contracts.md
├── checklists/
│   └── requirements.md  # Spec quality checklist
├── spec.md              # Feature specification
└── tasks.md             # Phase 2 task decomposition (/speckit-tasks output)
```

### Source Code Layout

```text
# Backend (Custom Module & Migrations)
db/migrate/
└── 21260817140000_create_ichatr_opportunity_activities.rb  # Migration + SQL backfill

custom/
├── app/
│   ├── models/
│   │   ├── opportunity_activity.rb                         # Model with polymorphic actor
│   │   ├── opportunity.rb                                  # Association: has_many :activities
│   │   └── opportunity_conversation.rb                     # Callback: after_create :record_activity
│   ├── listeners/
│   │   └── custom/
│   │       └── opportunity_activity_listener.rb            # Wisper event listener
│   ├── dispatchers/
│   │   └── custom/
│   │       └── async_dispatcher.rb                         # prepend_mod_with for AsyncDispatcher
│   └── controllers/
│       └── api/
│           └── v1/
│               └── accounts/
│                   └── opportunities/
│                       └── activities_controller.rb        # Read-only GET index endpoint
├── spec/
│   ├── models/
│   │   └── opportunity_activity_spec.rb
│   ├── listeners/
│   │   └── custom/
│   │       └── opportunity_activity_listener_spec.rb
│   └── requests/
│       └── api/
│           └── v1/
│               └── accounts/
│                   └── opportunities/
│                       └── activities_controller_spec.rb

# Frontend
app/javascript/dashboard/
├── api/
│   └── opportunities.js                                    # Added getActivities(opportunityId)
├── store/modules/opportunities/
│   ├── actions.js                                          # Added fetchActivities action
│   └── getters.js                                          # Added opportunityByConversationId getter
├── components-next/Opportunities/
│   ├── OpportunityActivityLog.vue                          # Vertical timeline component
│   └── OpportunityConversationDrawer.vue                   # ButtonGroup toggle & view swap
└── i18n/locale/
    ├── en/
    │   └── opportunities.json                              # English translations
    └── pt_BR/
        └── opportunities.json                              # Brazilian Portuguese translations

# Tooling / Sync Manifest
bin/
└── sync-custom-module-hooks                                # Route manifest wiring for activities
```

**Structure Decision**: Fully decoupled custom module architecture placing all new backend logic under `custom/`, migration in `db/migrate/`, frontend components in `app/javascript/dashboard/components-next/Opportunities/`, and wiring tracked in `bin/sync-custom-module-hooks`.

## Complexity Tracking

*No constitutional violations identified. Design adheres strictly to the decoupled extension model.*
