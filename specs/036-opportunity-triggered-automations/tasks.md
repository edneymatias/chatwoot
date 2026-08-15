# Tasks: Opportunity-Triggered Automations

**Input**: Design documents from `/specs/036-opportunity-triggered-automations/`

**Prerequisites**: [plan.md](file:///home/matias/dev/chatwoot/specs/036-opportunity-triggered-automations/plan.md), [spec.md](file:///home/matias/dev/chatwoot/specs/036-opportunity-triggered-automations/spec.md), [research.md](file:///home/matias/dev/chatwoot/specs/036-opportunity-triggered-automations/research.md), [data-model.md](file:///home/matias/dev/chatwoot/specs/036-opportunity-triggered-automations/data-model.md), [contracts/](file:///home/matias/dev/chatwoot/specs/036-opportunity-triggered-automations/contracts/opportunity-automation-rule-schema.md)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Core Seams & Model Extension)

**Purpose**: Establish core integration hooks with minimal upstream diff footprint.

- [X] T001 Add `AutomationRuleListener.prepend_mod_with('AutomationRuleListener')` seam in `app/listeners/automation_rule_listener.rb`
- [X] T002 [P] Extend `custom/app/models/custom/automation_rule.rb` with opportunity `actions_attributes` and `conditions_attributes`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core dispatching and execution infrastructure required for all opportunity automation stories.

**⚠️ CRITICAL**: Must be completed before user story implementation begins.

- [X] T003 Add lifecycle event dispatching (`opportunity_*`) and validation bypass (`return if Current.executed_by.is_a?(AutomationRule)`) in `custom/app/models/opportunity.rb`
- [X] T004 [P] Create base opportunity condition filter service in `custom/app/services/custom/automation_rules/opportunity_conditions_filter_service.rb`
- [X] T005 [P] Create base opportunity action executor with loop prevention (`Current.executed_by = @rule`) in `custom/app/services/custom/automation_rules/opportunity_action_service.rb`
- [X] T006 Create `custom/app/listeners/custom/automation_rule_listener.rb` to intercept `opportunity_*` events and route to opportunity filter and action services

**Checkpoint**: Core foundation ready — event dispatching and listener routing established.

---

## Phase 3: User Story 1 - Opportunity Creation & Stage Transition Automations (Priority: P1) 🎯 MVP

**Goal**: Enable automation rules on `opportunity_created`, `opportunity_updated`, and `opportunity_stage_changed` to filter by opportunity properties and execute opportunity updates (stage, assignee, status, value, custom attributes).

**Independent Test**: Configure a rule with trigger `opportunity_stage_changed` to update assignee and deal value. Move a card across stages in Kanban and verify assignee and value update automatically without infinite loops.

### Implementation for User Story 1

- [X] T007 [US1] Implement opportunity attribute filters (`pipeline_id`, `pipeline_stage_id`, `from_pipeline_stage_id`, `status`, `value`, `assignee_id`, `loss_reason`, `opportunity_custom_attributes`) in `custom/app/services/custom/automation_rules/opportunity_conditions_filter_service.rb`
- [X] T008 [US1] Implement opportunity actions (`update_opportunity_stage`, `update_opportunity_assignee`, `update_opportunity_status`, `update_opportunity_value`, `update_opportunity_custom_attribute`) in `custom/app/services/custom/automation_rules/opportunity_action_service.rb`
- [X] T009 [P] [US1] Add RSpec unit tests for opportunity actions & loop prevention in `custom/spec/services/custom/automation_rules/opportunity_action_service_spec.rb`
- [X] T010 [P] [US1] Add RSpec unit tests for opportunity condition filtering in `custom/spec/services/custom/automation_rules/opportunity_conditions_filter_service_spec.rb`

**Checkpoint**: User Story 1 (MVP) is fully functional and independently testable.

---

## Phase 4: User Story 2 - Cross-Entity Actions & Graceful Conversation Fallback (Priority: P2)

**Goal**: Execute actions on Contact and linked Conversation when an opportunity automation triggers, gracefully skipping conversation actions (no-op) when no origin conversation is linked.

**Independent Test**: Configure a rule on `opportunity_won` that updates a contact custom attribute AND posts a private note to the conversation. Trigger for a deal with a conversation (verify both update) and for a deal without a conversation (verify contact updates and no errors occur).

### Implementation for User Story 2

- [X] T011 [US2] Implement Contact attributes and Conversation attributes condition filters in `custom/app/services/custom/automation_rules/opportunity_conditions_filter_service.rb`
- [X] T012 [US2] Implement Contact actions (`update_contact_attribute`, `update_contact_custom_attribute`) in `custom/app/services/custom/automation_rules/opportunity_action_service.rb`
- [X] T013 [US2] Implement Conversation actions (`send_message`, `add_private_note`, `add_label`, `remove_label`, `assign_agent`, `assign_team`, `resolve_conversation`, `change_priority`, `send_webhook_event`, `send_email_to_team`, `update_conversation_custom_attribute`) with System/Bot author identity and safe no-op fallback when `origin_conversation_id` is nil in `custom/app/services/custom/automation_rules/opportunity_action_service.rb`
- [X] T014 [P] [US2] Add RSpec unit tests for cross-entity actions and standalone opportunity fallback in `custom/spec/services/custom/automation_rules/opportunity_action_service_spec.rb`

**Checkpoint**: User Stories 1 and 2 work independently and cross-entity actions execute reliably.

---

## Phase 5: User Story 3 - Opportunity Status Lifecycle Automations (Won, Lost, Reopened) (Priority: P3)

**Goal**: Trigger distinct automation workflows when opportunities transition to `won`, `lost`, or are reopened from a closed state.

**Independent Test**: Mark an opportunity as won/lost/reopened and verify corresponding automation rules fire and execute.

### Implementation for User Story 3

- [X] T015 [US3] Wire status transition event dispatches and listener handlers for `opportunity_won`, `opportunity_lost`, and `opportunity_reopened` in `custom/app/models/opportunity.rb` and `custom/app/listeners/custom/automation_rule_listener.rb`
- [X] T016 [P] [US3] Add RSpec unit tests for won, lost, and reopened automation event triggering in `custom/spec/listeners/custom/automation_rule_listener_spec.rb`

**Checkpoint**: Full lifecycle status triggers are operational.

---

## Phase 6: User Story 4 - Unified Automation Configuration in Settings UI (Priority: P4)

**Goal**: Provide a seamless and localized UI in Settings > Automations for configuring opportunity triggers, conditions, and actions.

**Independent Test**: Navigate to Settings > Automations in the browser, create a rule with an Opportunity trigger, configure conditions & actions, save, reload, and verify the rule is rendered accurately in both English and Portuguese (`pt-BR`).

### Implementation for User Story 4

- [X] T017 [P] [US4] Register 6 opportunity events, condition schemas, and action schemas in `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`
- [X] T018 [P] [US4] Extend `useAutomation.js` (`manifestCustomAttributes`) and `automationHelper.js` to dynamically load `opportunity_attribute` definitions and provide opportunity dropdown options
- [X] T019 [US4] Wire opportunity action inputs and options into `app/javascript/dashboard/components/widgets/AutomationActionInput.vue` and `app/javascript/dashboard/routes/dashboard/settings/automation/AutomationRuleForm.vue`
- [X] T020 [P] [US4] Add synchronous English and Portuguese translations for opportunity triggers, conditions, and actions in `app/javascript/dashboard/i18n/locale/en/automation.json` and `app/javascript/dashboard/i18n/locale/pt_BR/automation.json`

**Checkpoint**: Full end-to-end configuration is available in the dashboard UI.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Hook verification, linting compliance, and regression test suite validation.

- [X] T021 Update and audit sync hooks in `bin/sync-custom-module-hooks` and verify with `bin/sync-custom-module-hooks --check`
- [X] T022 [P] Run backend linting and complexity cleanup via `docker compose exec rails bundle exec rubocop -a`
- [X] T023 [P] Run frontend linting via `docker compose exec vite pnpm eslint`
- [X] T024 Run custom automation test suite via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories.
- **User Stories (Phases 3–6)**:
  - US1 (P1): Depends on Foundational (Phase 2).
  - US2 (P2): Depends on Foundational (Phase 2) and builds on US1 action service.
  - US3 (P3): Depends on Foundational (Phase 2).
  - US4 (P4): Depends on Foundational (Phase 2) and constants from US1–US3.
- **Polish (Phase 7)**: Depends on all user stories being complete.

### Parallel Opportunities

- **Setup & Foundational**: `T002`, `T004`, `T005` can be developed in parallel.
- **User Story 1**: Specs `T009` and `T010` can be written in parallel.
- **User Story 2**: Spec `T014` can run in parallel with implementation.
- **User Story 4**: Frontend constants `T017`, composables `T018`, and i18n `T020` can be built in parallel.
- **Polish**: Backend linting `T022` and frontend linting `T023` can run in parallel.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational).
2. Complete Phase 3 (User Story 1).
3. Validate User Story 1 using unit tests in `custom/spec/` and quick manual verification.

### Incremental Delivery

1. Foundation ready (Phases 1 & 2).
2. Deliver US1: Opportunity creation & stage transitions (MVP).
3. Deliver US2: Cross-entity actions & conversation fallback.
4. Deliver US3: Status lifecycle triggers (won, lost, reopened).
5. Deliver US4: Unified settings UI & bilingual i18n.
6. Deliver Polish: Hook sync audit, rubocop, eslint, and full test suite.
