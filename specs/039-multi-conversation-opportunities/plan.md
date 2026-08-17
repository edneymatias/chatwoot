# Implementation Plan: Multi-Conversation Opportunity Lifecycle

**Branch**: `039-multi-conversation-opportunities` | **Date**: 2026-08-17 | **Spec**: [Multi-Conversation Opportunity Lifecycle](spec.md)

**Input**: Feature specification from [`specs/039-multi-conversation-opportunities/spec.md`](spec.md)

## Summary

Decouples the opportunity lifecycle from individual conversations by allowing an opportunity to have multiple associated conversations over time (1:N history), with at most one active (open) conversation at any given time. When an active conversation is resolved, the opportunity automatically detaches its active conversation slot and restores the "Start Conversation" action button on the Kanban card. When starting a conversation on a card, the system smartly checks for existing open conversations for the contact, allowing the agent to link an open conversation or start a new one. All associated conversations (past and present) remain accessible in the opportunity details history.

## Technical Context

**Language/Version**: Ruby 3.3+ (Rails 7.1), JavaScript (Vue 3, Pinia/Vuex)
**Primary Dependencies**: Rails, Vue 3 Composition API, Tailwind CSS, ActionCable
**Storage**: PostgreSQL (new `ichatr_opportunity_conversations` join table, `active_conversation_id` column on `ichatr_opportunities`)
**Testing**: RSpec (`bundle exec rspec`), Vitest (`pnpm test`)
**Target Platform**: Linux container (Podman / Docker Compose)
**Project Type**: Full-stack web application (Chatwoot fork)
**Performance Goals**: Sub-50ms opportunity updates, zero page reload on conversation resolve/reopen, instant real-time ActionCable broadcasts
**Constraints**: Follow Chatwoot fork Constitution (isolation in `custom/`, `ichatr_` prefix, no custom CSS, bilingual i18n)
**Scale/Scope**: Multi-tenant accounts with thousands of opportunities and conversations

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **I. Upstream Compatibility First**: All new models, listeners, and services live in `custom/app/` (`custom/app/models/opportunity_conversation.rb`, `custom/app/listeners/custom/`). Database tables use `ichatr_` prefix (`ichatr_opportunity_conversations`). Existing core classes hooked only via `prepend_mod_with` or standard Chatwoot dispatcher events.
- [x] **II. Smallest Production-Ready Change**: Reuses existing `ActionCableListener` and `StartOpportunityConversationButton` components, adding targeted modal and backend associations.
- [x] **III. Adhere to Established Conventions**: Tailwind CSS only, Composition API `<script setup>`, bilingual translations (`en.json`, `pt_BR.json`, `en.yml`, `pt_BR.yml`), 150-char RuboCop compliance.
- [x] **IV. Safe, Reversible Change Management**: Additive database migrations (`add_column`, `create_table`). Safe rollbacks.
- [x] **V. Dual-Tree Awareness (OSS + Enterprise)**: Verified compatibility; changes operate in custom layer without altering Enterprise overlays.

## Project Structure

### Documentation (this feature)

```text
specs/039-multi-conversation-opportunities/
├── plan.md              # Implementation plan
├── research.md          # Technical decisions and alternatives
├── data-model.md        # Database schema and model relationships
├── quickstart.md        # End-to-end validation scenarios
├── contracts/
│   └── opportunities_api.yaml # API and event contracts
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code Layout

```text
custom/
├── app/
│   ├── controllers/
│   │   └── api/v1/accounts/
│   │       └── opportunities_controller.rb   # update permitted params & link action
│   ├── listeners/
│   │   └── custom/
│   │       └── action_cable_listener.rb      # handle conversation_resolved / opened
│   └── models/
│       ├── opportunity.rb                    # associations & lifecycle helpers
│       └── opportunity_conversation.rb       # join model for 1:N history
└── spec/
    ├── controllers/
    │   └── api/v1/accounts/opportunities_controller_spec.rb
    └── models/
        ├── opportunity_spec.rb
        └── opportunity_conversation_spec.rb

db/
└── migrate/
    └── 20260817000001_create_ichatr_opportunity_conversations.rb

app/javascript/dashboard/
├── components-next/
│   └── Opportunities/
│       ├── KanbanCard.vue                    # active conversation handling
│       ├── ContactOpportunityCard.vue        # display active status & history
│       ├── OpportunityConversationLinkModal.vue # smart link vs start modal
│       └── OpportunityBackfillModal.vue      # conversation history list
├── routes/dashboard/
│   ├── conversation/
│   │   └── ContactOpportunities.vue          # active conversation matching
│   └── opportunities/
│       └── components/
│           ├── StartOpportunityConversationButton.vue # smart open conversation trigger
│           └── OpportunityListView.vue       # list view active conversation
└── i18n/locale/
    ├── en/opportunities.json                 # English UI copy
    └── pt_BR/opportunities.json              # Portuguese UI copy
```

**Structure Decision**: Decoupled backend architecture in `custom/` with additive migrations in `db/migrate/` and frontend components under `app/javascript/dashboard/` utilizing existing design patterns.

## Complexity Tracking

> **No violations. Pure additive decoupled architecture.**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *None* | N/A | N/A |
