# Feature Specification: Opportunity-Triggered Automations

**Feature Branch**: `036-opportunity-triggered-automations`

**Created**: 2026-08-14

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 8/02-opportunity-triggered-automations/spec12.md"

## Clarifications

### Session 2026-08-14

- Q: When an automation rule moves an opportunity to a stage with required closing fields (e.g., loss reason or mandatory custom fields), how should the system handle missing required fields? → A: Bypass stage required-field validations during automated transitions so background workflows proceed uninterrupted (required field validations protect manual user input in the UI).
- Q: When an opportunity automation rule executes a conversation action (such as sending a message or adding a private note), what sender identity should be assigned to the message? → A: System / Automation Bot (matches standard Chatwoot automation behavior, clear audit trail).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Opportunity Creation & Stage Transition Automations (Priority: P1)

As an account administrator or sales manager, I want to automatically execute actions (such as assigning sales reps, updating custom attributes, or setting default stages) when opportunities are created or move across pipeline stages, so that our team reduces manual CRM tasks and maintains consistent sales processes.

**Why this priority**: Core value of opportunity automations. Automating stage progression and immediate assignment is the most frequent and critical CRM automation use case.

**Independent Test**: Configure a rule with trigger "Opportunity Stage Changed" (e.g. from "Qualification" to "Proposal") with an action to update the opportunity assignee and custom field. Move a card in Kanban or edit its stage, then verify the assignee and custom fields update automatically.

**Acceptance Scenarios**:

1. **Given** an active automation rule configured with trigger `opportunity_created` and an action to assign a specific agent, **When** a new opportunity is created manually or via integration, **Then** the opportunity is assigned to the specified agent immediately.
2. **Given** an automation rule configured with trigger `opportunity_stage_changed` matching source stage `Lead` and target stage `Negotiation`, **When** an opportunity moves from `Lead` to `Negotiation`, **Then** the configured rule actions execute.
3. **Given** an automation rule configured with trigger `opportunity_stage_changed` matching source stage `Lead` and target stage `Negotiation`, **When** an opportunity moves from `Contacted` to `Negotiation` (different source stage), **Then** the rule does not execute.

---

### User Story 2 - Cross-Entity Actions & Graceful Conversation Fallback (Priority: P2)

As a sales agent or manager, I want opportunity events to execute updates on associated contacts and linked conversations (such as adding internal notes, applying labels, or sending messages), while ensuring that opportunities without a linked conversation still execute contact and opportunity actions without errors.

**Why this priority**: Opportunities are often tied to active customer conversations and contacts. Automating cross-entity communication delivers high operational efficiency, and safe fallback prevents silent failures or broken workflows for standalone opportunities.

**Independent Test**: Create an automation rule on `opportunity_won` that updates a contact custom attribute AND posts a private note to the conversation. Trigger the rule for an opportunity with a linked conversation (verify note posted and contact updated), and for an opportunity without a linked conversation (verify contact updated successfully and no errors thrown).

**Acceptance Scenarios**:

1. **Given** an opportunity linked to a conversation and contact, **When** an automation rule fires with actions targeting the opportunity, contact, and conversation, **Then** all three entities are updated accordingly (e.g. stage updated, contact tag set, private note posted to conversation).
2. **Given** an opportunity without any linked conversation (`origin_conversation_id` is empty), **When** an automation rule triggers containing conversation-specific actions (e.g. `send_message`, `add_private_note`, `change_priority`), **Then** the conversation-specific actions are safely skipped (no-op) and the opportunity/contact actions complete successfully.
3. **Given** an automation rule with contact attribute updates, **When** the opportunity triggers the rule, **Then** the linked contact's standard attributes and custom attributes are updated as defined in the rule.

---

### User Story 3 - Opportunity Status Lifecycle Automations (Won, Lost, Reopened) (Priority: P3)

As a sales operations administrator, I want to trigger distinct workflows when an opportunity is marked as won, lost, or reopened, so that post-sales onboarding, lost-deal notifications, or win-back campaigns are triggered automatically.

**Why this priority**: Closes the CRM lifecycle loop by automating win/loss/reopen handling, webhooks, and team alerts.

**Independent Test**: Configure a rule on `opportunity_lost` filtered by loss reason "Budget" to add a label "lost-budget" to the contact and send an email notification to the team. Mark an opportunity as lost with reason "Budget", and verify the actions trigger.

**Acceptance Scenarios**:

1. **Given** an automation rule with trigger `opportunity_won`, **When** an opportunity is marked as won, **Then** the configured actions (such as sending a webhook event or updating contact tier) execute immediately.
2. **Given** an automation rule with trigger `opportunity_lost` filtered by `loss_reason` or deal value, **When** an opportunity status changes to `lost` matching the filter criteria, **Then** the rule executes.
3. **Given** an automation rule with trigger `opportunity_reopened`, **When** a previously won or lost opportunity is reopened (status changed back to `open`), **Then** the reopen automation actions execute.

---

### User Story 4 - Unified Automation Configuration in Settings UI (Priority: P4)

As an administrator, I want to configure opportunity automation rules directly in the existing Automation Settings screen, using a unified interface that supports opportunity triggers, filters (pipeline, stage, value, assignee, loss reason, custom attributes), and actions.

**Why this priority**: Consistent administrative user experience ensures that users do not need a separate tool or complex custom setup to manage opportunity rules.

**Independent Test**: Navigate to Settings > Automations, create a new rule, select an Opportunity trigger, configure conditions for Opportunity/Contact/Conversation, select Opportunity actions, save the rule, and edit it afterwards.

**Acceptance Scenarios**:

1. **Given** an admin in Settings > Automations, **When** creating or editing a rule, **Then** they can choose Opportunity trigger events alongside existing conversation and contact triggers.
2. **Given** an Opportunity trigger is selected in the UI, **When** configuring conditions, **Then** the filter dropdowns dynamically display opportunity-specific attributes (pipeline, current stage, previous stage, status, value, assignee, loss reason, custom fields), contact attributes, and conversation attributes.
3. **Given** an Opportunity trigger is selected, **When** configuring actions, **Then** available actions include opportunity updates, contact updates, and conversation updates.
4. **Given** existing non-opportunity automation rules in the system, **When** viewing or executing them, **Then** their behavior and UI remain completely unaffected.

---

### Edge Cases

- **Infinite Automation Loops**: What happens when an action in an opportunity automation rule updates an opportunity attribute (e.g. changes stage) which matches another automation rule? The execution context must identify rule-executed changes and prevent recursive or circular trigger firing.
- **Missing or Deleted Entities**: What happens if an automation references a pipeline stage, assignee, or custom attribute that has since been deleted or disabled? The rule execution must log a warning and gracefully continue without crashing the background worker.
- **Concurrent Opportunity Updates**: How does the system handle rapid back-to-back stage transitions or concurrent updates? Each transition triggers the appropriate event idempotently, evaluating conditions against the opportunity state at trigger time.
- **Value Comparison Operators**: How does the system handle decimal or zero opportunity values when matching numerical operators (`greater_than`, `less_than`, `equal_to`)? Standard numeric comparison is applied, treating missing values as zero or non-matching depending on the operator.
- **Stage Origin Validation**: For `opportunity_stage_changed`, what happens if `from_pipeline_stage_id` condition is set but the opportunity was newly created directly in that stage? Creation events do not have a previous stage; stage-changed rules only match when an actual transition occurred.
- **Stage Required Fields Validation**: What happens when an automation action (`update_opportunity_stage`) attempts to move an opportunity into a stage requiring mandatory fields (e.g. loss reason or mandatory custom attributes) that are not present? Automated background transitions bypass UI-focused stage required-field validations to ensure system workflows execute uninterrupted without stalling.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support the following opportunity trigger events in the automation engine:
  - `opportunity_created`
  - `opportunity_updated`
  - `opportunity_stage_changed`
  - `opportunity_won`
  - `opportunity_lost`
  - `opportunity_reopened`
- **FR-002**: System MUST allow filtering opportunity automation rules by Opportunity attributes:
  - `pipeline_id`
  - `pipeline_stage_id` (current or destination stage)
  - `from_pipeline_stage_id` (previous or source stage)
  - `status` (`open`, `won`, `lost`)
  - `value` (with operators `equal_to`, `not_equal_to`, `greater_than`, `less_than`)
  - `assignee_id`
  - `loss_reason`
  - Opportunity `custom_attributes`
- **FR-003**: System MUST allow filtering opportunity automation rules by Contact attributes (standard attributes and custom attributes).
- **FR-004**: System MUST allow filtering opportunity automation rules by Conversation attributes (inbox, labels, priority, status, channel, custom attributes) when a linked conversation is present.
- **FR-005**: System MUST support the following Opportunity-specific actions:
  - `update_opportunity_stage`: Move opportunity to a target stage (bypassing UI-enforced required closing fields to allow uninterrupted automated workflow transitions)
  - `update_opportunity_assignee`: Assign or unassign agent responsible for the opportunity
  - `update_opportunity_status`: Set status to `open`, `won`, or `lost`
  - `update_opportunity_value`: Update the monetary value of the opportunity
  - `update_opportunity_custom_attribute`: Update specific opportunity custom field values
- **FR-006**: System MUST support Contact-specific actions in opportunity-triggered rules:
  - `update_contact_custom_attribute`
  - `update_contact_attribute` (e.g. company, phone, email, name)
- **FR-007**: System MUST support Conversation actions in opportunity-triggered rules when a linked conversation exists (with message/note actions authored by System / Automation Bot identity):
  - `send_message`
  - `add_private_note`
  - `add_label` / `remove_label`
  - `assign_agent` / `assign_team` / `remove_assigned_agent` / `remove_assigned_team`
  - `resolve_conversation` / `open_conversation` / `snooze_conversation` / `pending_conversation`
  - `change_priority`
  - `send_webhook_event`
  - `send_email_to_team`
  - `update_conversation_custom_attribute`
- **FR-008**: System MUST safely skip conversation actions without failing the rule or interrupting other actions when an opportunity has no associated conversation (`origin_conversation_id` is nil).
- **FR-009**: System MUST prevent infinite execution loops by tracking the execution source context and suppressing cascading triggers originating from automation rule actions.
- **FR-010**: System MUST expose all opportunity triggers, conditions, and actions within the existing Automation Settings UI in a unified and localized manner (English and Portuguese `pt-BR`).
- **FR-011**: System MUST process opportunity automations asynchronously in background jobs to preserve snappy user interactions and UI responsiveness.
- **FR-012**: System MUST permit automated stage transitions executed by automation rules even if stage-configured closing required fields (such as loss reason or mandatory custom attributes) are blank, ensuring background workflows execute reliably.

### Key Entities *(include if feature involves data)*

- **Opportunity**: Represents the sales deal in a pipeline with attributes including stage, status, monetary value, assignee, contact, optional linked origin conversation, loss reason, and custom attributes.
- **Automation Rule (`AutomationRule`)**: Configuration entity defining the account, event name/trigger, condition filters, and action list to execute when criteria match.
- **Automation Execution Context**: Runtime context providing access to the triggered opportunity, its associated contact, and its optional linked conversation, alongside execution origin metadata for loop detection.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of configured opportunity trigger events (`created`, `updated`, `stage_changed`, `won`, `lost`, `reopened`) fire reliably when corresponding lifecycle events occur.
- **SC-002**: 100% of opportunity automations execute without error even when targeting standalone opportunities that lack linked conversations (safe fallback verification).
- **SC-003**: Background automation rule processing completes and applies all matching actions within 3 seconds of the trigger event under standard system load.
- **SC-004**: Zero infinite recursion / worker queue loop incidents caused by cascading opportunity automation actions.
- **SC-005**: Administrators can configure, filter, and save an opportunity automation rule with custom conditions in under 2 minutes using the Settings UI.

## Assumptions

- **Existing Automation Engine**: The feature extends Chatwoot's existing `AutomationRule` architecture, event listeners, and Vue frontend components rather than creating a duplicate or disconnected subsystem.
- **Dual Language Support**: All new UI strings, trigger names, condition labels, and action labels will have synchronous translations in both English (`en`) and Portuguese (`pt-BR`).
- **Contact & Opportunity Association**: Every opportunity is assumed to be associated with an account and a contact; conversation association is optional.
- **Permissions**: Creating and managing automation rules requires administrator permissions within the account, matching standard Chatwoot automation permissions.
