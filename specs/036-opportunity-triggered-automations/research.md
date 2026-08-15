# Phase 0 Research: Opportunity-Triggered Automations

## Technical Investigation & Architectural Decisions

### 1. Event Dispatching & Listener Architecture

**Context**: When opportunity lifecycle transitions happen (create, update, stage change, win, loss, reopen), the system must dispatch event notifications to the async dispatcher so `AutomationRule` rules can be evaluated and executed in background jobs.

**Decision**:
- In `custom/app/models/opportunity.rb` (a fork-isolated model), extend callbacks (`after_commit on: :create`, `after_commit on: :update`) to dispatch lifecycle events through `Rails.configuration.dispatcher.dispatch`:
  - `opportunity_created`
  - `opportunity_updated`
  - `opportunity_stage_changed` (when `saved_change_to_pipeline_stage_id?`)
  - `opportunity_won` (when `status == 'won'` and `saved_change_to_status?`)
  - `opportunity_lost` (when `status == 'lost'` and `saved_change_to_status?`)
  - `opportunity_reopened` (when `status == 'open'` and `status_before_last_save.in?(%w[won lost])`)
- Pass execution metadata in `event.data`:
  ```ruby
  {
    opportunity: self,
    changed_attributes: saved_changes,
    from_pipeline_stage_id: pipeline_stage_id_before_last_save,
    performed_by: Current.executed_by || Current.user
  }
  ```
- In core `app/listeners/automation_rule_listener.rb`, add a single-line seam at the end: `AutomationRuleListener.prepend_mod_with('AutomationRuleListener')` (mirroring the standard pattern used in `ActionService`).
- In `custom/app/listeners/custom/automation_rule_listener.rb`, define `module Custom::AutomationRuleListener` to receive and route all `opportunity_*` events to `Custom::AutomationRules::OpportunityConditionsFilterService` and `Custom::AutomationRules::OpportunityActionService`.

**Rationale**: Conforms directly to Chatwoot's event dispatcher pattern (`AsyncDispatcher -> EventDispatcherJob -> AutomationRuleListener`). Decoupled and non-blocking for user requests, with zero disruption to standard conversation events.

---

### 2. Condition Filtering across Opportunity, Contact, and Conversation

**Context**: Opportunity rules need to filter on Opportunity properties (pipeline, stage, previous stage, status, value with comparison operators, assignee, loss reason, custom fields), Contact properties (standard and custom), and linked Conversation properties (inbox, status, priority, labels, custom fields).

**Decision**:
- Implement `Custom::AutomationRules::OpportunityConditionsFilterService` under `custom/app/services/custom/automation_rules/opportunity_conditions_filter_service.rb`.
- Structure filter evaluations against loaded models in pure Ruby / ActiveModel:
  - **Opportunity Filters**:
    - `pipeline_id`, `pipeline_stage_id`, `from_pipeline_stage_id`: direct ID equality/inclusion matching.
    - `status`, `assignee_id`, `loss_reason`: equality / presence matching.
    - `value`: numeric comparison (`equal_to`, `not_equal_to`, `greater_than`, `less_than`).
    - Opportunity `custom_attributes`: type-aware matching against `opportunity.custom_attributes[key]`.
  - **Contact Filters**:
    - Standard contact attributes (`name`, `email`, `phone_number`, `company_name`, `country_code`, `city`) and contact `custom_attributes`.
  - **Conversation Filters**:
    - When `opportunity.origin_conversation` is present: match `inbox_id`, `status`, `priority`, `labels` (via conversation taggings), and `custom_attributes`.
    - When `origin_conversation` is nil: conversation conditions evaluate safely to false without throwing errors.

**Rationale**: Core `ConditionsFilterService` builds raw SQL joins tied to the `conversations` table (`Conversation.where(id: @conversation.id).joins(...)`), which would fail or crash on opportunities without a conversation. A dedicated filter service in `custom/` keeps evaluation isolated, fast, and completely safe.

---

### 3. Action Execution & Graceful Fallback

**Context**: Actions in opportunity rules can target Opportunity, Contact, or Conversation entities. When an opportunity is not linked to a conversation (`origin_conversation_id == nil`), conversation actions must be skipped gracefully (no-op) while opportunity and contact actions execute successfully.

**Decision**:
- Implement `Custom::AutomationRules::OpportunityActionService` under `custom/app/services/custom/automation_rules/opportunity_action_service.rb`.
- Supported actions:
  - **Opportunity Actions**:
    - `update_opportunity_stage(stage_id)`: moves stage, updates record.
    - `update_opportunity_assignee(user_id)`: assigns user or clears assignment.
    - `update_opportunity_status(status)`: sets open/won/lost.
    - `update_opportunity_value(value)`: updates monetary value.
    - `update_opportunity_custom_attribute(params)`: updates custom attributes hash.
  - **Contact Actions**:
    - `update_contact_attribute(params)`: updates standard fields on `opportunity.contact`.
    - `update_contact_custom_attribute(params)`: updates custom attributes on `opportunity.contact`.
  - **Conversation Actions** (with safe fallback):
    - When `opportunity.origin_conversation` exists: delegate to existing conversation action handlers (`send_message`, `add_private_note`, `add_label`, `remove_label`, `assign_agent`, `assign_team`, `resolve_conversation`, `open_conversation`, `snooze_conversation`, `pending_conversation`, `change_priority`, `send_webhook_event`, `send_email_to_team`, `update_conversation_custom_attribute`).
    - Messages and private notes use System / Automation Bot identity.
    - When `opportunity.origin_conversation` is nil: safely log and skip conversation actions (no-op).

**Rationale**: Core `ActionService` performs `@conversation.reload` in `perform`, which raises `NoMethodError` when `@conversation` is nil. A dedicated opportunity action service in `custom/` isolates opportunity workflows and provides 100% crash protection for standalone opportunities.

---

### 4. Loop Prevention & Stage Validation Bypass

**Context**:
1. Automation actions that update opportunities could trigger additional automation events, risking infinite recursion.
2. Automated stage transitions should not be blocked if the destination stage has UI required fields configured (e.g. closing fields).

**Decision**:
- **Loop Prevention**:
  - `OpportunityActionService` wraps execution in `Current.executed_by = @rule`.
  - In `Opportunity` callbacks and `AutomationRuleListener`: check `Current.executed_by.is_a?(AutomationRule)` or `event.data[:performed_by].is_a?(AutomationRule)`. If present, skip triggering cascading automations.
- **Stage Validation Bypass**:
  - In `Opportunity` model (`validate_forward_stage_move_requirements` and `validate_closing_requirements`), add:
    ```ruby
    return if Current.executed_by.is_a?(AutomationRule)
    ```
  - This allows background automation rules to transition stages without being blocked by UI-only operator input requirements.

---

### 5. Frontend & UI Configuration

**Context**: Users configure rules in Settings > Automations (`/app/accounts/{accountId}/settings/automation`).

**Decision**:
- Extend `constants.js` with:
  - `AUTOMATION_RULE_EVENTS`: append 6 opportunity triggers (`opportunity_created`, `opportunity_updated`, `opportunity_stage_changed`, `opportunity_won`, `opportunity_lost`, `opportunity_reopened`).
  - `AUTOMATIONS`: map conditions and actions for each opportunity trigger.
  - `AUTOMATION_ACTION_TYPES`: register opportunity and contact action types with appropriate input types (`search_select`, `plain_text`, `custom_attribute`, etc.).
- Update `useAutomationValues.js` and `useAutomation.js` (`manifestCustomAttributes`) to dynamically load `opportunity_attribute` definitions.
- Reuse existing UI widgets (`SingleSelect.vue`, `ConditionRow.vue`, `AutomationActionInput.vue`, `NextInput.vue`) directly — no unnecessary bespoke Vue components.
- Add synchronous translations in `en.json` and `pt_BR.json` for all new event names, condition labels, and action labels.

**Rationale**: 100% unified experience in existing Chatwoot Automation Settings without separate screens or redundant components.

---

### 6. Upstream Compatibility & Seam Audit (`bin/sync-custom-module-hooks`)

| File / Component | Modification Type | Conflict Risk on Upstream Sync | Protection Mechanism |
|:---|:---|:---|:---|
| `app/listeners/automation_rule_listener.rb` | 1-line seam (`prepend_mod_with`) | Negligible (EOF) | Tracked in `MANIFEST` of `bin/sync-custom-module-hooks` |
| `custom/app/listeners/custom/automation_rule_listener.rb` | New file in `custom/` | Zero | Total filesystem isolation |
| `custom/app/models/opportunity.rb` | Add callbacks & bypass in `custom/` model | Zero | Fork-owned file |
| `custom/app/models/custom/automation_rule.rb` | Extends `actions_attributes` & `conditions_attributes` | Zero | Native Chatwoot `prepend_mod_with` pattern |
| `custom/app/services/custom/automation_rules/*` | New services in `custom/` | Zero | Total filesystem isolation |
| `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` | Add event constants & mappings | Low | Listed under `out_of_scope` in sync auditor |
| `app/javascript/dashboard/composables/useAutomation.js` | Add `opportunity_attribute` loader | Low | Tracked in `MANIFEST` of `bin/sync-custom-module-hooks` |
| `app/javascript/dashboard/i18n/locale/*` | Add locale keys | Low | Additive JSON keys |

**Conclusion**: The implementation guarantees maximum upstream compatibility with strictly zero intrusive edits to Chatwoot core domain models (`Conversation`, `Contact`, `Message`, `Account`). All fork-specific logic is fully encapsulated in `custom/` and verified via `bin/sync-custom-module-hooks --check`.
