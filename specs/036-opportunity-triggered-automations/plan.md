# Implementation Plan: Opportunity-Triggered Automations

**Branch**: `036-opportunity-triggered-automations` | **Date**: 2026-08-14 | **Spec**: [specs/036-opportunity-triggered-automations/spec.md](file:///home/matias/dev/chatwoot/specs/036-opportunity-triggered-automations/spec.md)

**Input**: Feature specification from `/specs/036-opportunity-triggered-automations/spec.md`

## Summary

Enables the Chatwoot `AutomationRule` engine to trigger on Opportunity lifecycle events (`opportunity_created`, `opportunity_updated`, `opportunity_stage_changed`, `opportunity_won`, `opportunity_lost`, `opportunity_reopened`). Provides condition filtering across Opportunity, Contact, and linked Conversation properties, supports multi-target actions (moving stages, assigning reps, updating standard & custom fields, and sending messages/notes/webhooks), ensures graceful fallback when opportunities lack origin conversations, and prevents recursive trigger loops via `Current.executed_by` tracking.

## Technical Context

**Language/Version**: Ruby 3.3.x (Rails 7.x), JavaScript / Vue 3 (Composition API / Vuex)

**Primary Dependencies**: Chatwoot core `AutomationRule` engine, `AsyncDispatcher`, `EventDispatcherJob`, Sidekiq background processing.

**Storage**: PostgreSQL (`automation_rules` JSONB storage for conditions/actions, `ichatr_opportunities`, `contacts`, `conversations`).

**Testing**: RSpec for backend services (`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/...`).

**Target Platform**: Linux containerized web service (Docker / rootless Podman).

**Project Type**: Full-stack web application feature (Rails backend + Vue 3 frontend settings).

**Performance Goals**: Async background processing completes within <3s from trigger event. Zero UI latency overhead during opportunity updates.

**Constraints**:
- Strict adherence to fork constitution: all new backend classes live under `custom/`.
- Prepend extensions (`prepend_mod_with`) for shared listeners and models.
- Graceful no-op for conversation actions when `origin_conversation_id` is nil.
- Bypass UI required stage closing fields for automated transitions.
- Synchronous English (`en.json`) and Portuguese (`pt_BR.json`) localization.

**Scale/Scope**: Scales with standard Chatwoot automation workloads (thousands of daily opportunity lifecycle events).

## Constitution Check

| Principle | Assessment | Status |
|:---|:---|:---|
| **I. Upstream Compatibility First** | All new backend services (`OpportunityConditionsFilterService`, `OpportunityActionService`) and listeners live in `custom/app/`. Extension points into `AutomationRuleListener` and `AutomationRule` use `prepend_mod_with`. No core files are hard-forked. | **PASS** |
| **II. Smallest Production-Ready Change** | Directly extends existing `AutomationRule` JSONB patterns and `AsyncDispatcher` event hooks without introducing redundant database tables, external workflow engines, or duplicate UIs. | **PASS** |
| **III. Adhere to Established Conventions** | Follows RuboCop rules (150-char max line length, private helper extraction), Vue 3 Composition API in dashboard settings, and synchronous `en`/`pt_BR` translations without Crowdin. | **PASS** |
| **IV. Safe, Reversible Change Management** | Changes are purely additive to the database JSONB payloads and isolated in `custom/` modules. | **PASS** |
| **V. Dual-Tree Awareness (OSS + Enterprise)** | Verified no conflicting `enterprise/` overrides exist for `Opportunity` or `AutomationRuleListener`. Contracts remain consistent. | **PASS** |

## Project Structure

### Documentation (this feature)

```text
specs/036-opportunity-triggered-automations/
├── plan.md              # This implementation plan
├── research.md          # Phase 0 architectural research & decisions
├── data-model.md        # Phase 1 data entities, condition/action schemas
├── quickstart.md        # Phase 1 validation scenarios and run guides
├── contracts/
│   └── opportunity-automation-rule-schema.md
└── checklists/
    └── requirements.md  # Quality validation checklist
```

### Source Code Layout

```text
# Backend (Isolated in custom/ overlay)
custom/
├── app/
│   ├── listeners/
│   │   └── custom/
│   │       └── automation_rule_listener.rb    # Handles opportunity_* events and dispatches to service
│   ├── models/
│   │   ├── opportunity.rb                     # Lifecycle event callbacks (dispatches opportunity_*)
│   │   └── custom/
│   │       └── automation_rule.rb             # Extends actions_attributes and conditions_attributes
│   └── services/
│       └── custom/
│           └── automation_rules/
│               ├── opportunity_conditions_filter_service.rb  # Evaluates filters for opportunities
│               └── opportunity_action_service.rb             # Executes actions across Opportunity, Contact, Conversation
└── spec/
    ├── listeners/
    │   └── custom/
    │       └── automation_rule_listener_spec.rb
    └── services/
        └── custom/
            └── automation_rules/
                ├── opportunity_conditions_filter_service_spec.rb
                └── opportunity_action_service_spec.rb

# Core Seams & Hooks
app/
└── listeners/
    └── automation_rule_listener.rb            # Adds prepend_mod_with('AutomationRuleListener')

# Frontend (Automation Settings in Dashboard)
app/javascript/dashboard/
├── routes/dashboard/settings/automation/
│   ├── constants.js                           # Adds opportunity events, actions, and condition schemas
│   └── AutomationRuleForm.vue                 # Wires dynamic opportunity selectors
├── composables/
│   └── useAutomationValues.js                 # Populates opportunity stages, users, and attributes
└── i18n/locale/
    ├── en/
    │   └── automation.json                    # English translations for new triggers & actions
    └── pt_BR/
        └── automation.json                    # Portuguese translations for new triggers & actions
```

## Complexity Tracking

*No constitutional violations identified. No exceptions requested.*
