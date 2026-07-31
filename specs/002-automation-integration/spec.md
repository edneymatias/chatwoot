# Feature Specification: Automation Integration — Create Opportunity Action

**Feature Branch**: `002-automation-integration`

**Created**: 2026-07-30

**Status**: Draft

**Input**: User description: "docs/kanban/02-automation-integration/spec2.md — Phase 2: Automation Integration — create_opportunity Automation Action"

**Phase**: 2 of 4 (Automation Integration). Depends on Phase 1 (Backend Core — Opportunity, Pipeline Stage). Feeds Phase 3 (frontend Automation Rules UI dropdown).

## Clarifications

### Session 2026-07-30

- Q: When the same Automation Rule fires near-simultaneously for the same conversation, should duplicate Opportunity creation be prevented with a database-level guarantee, or is a simple application-level check acceptable? → A: Database-level uniqueness constraint on origin conversation, guaranteeing zero duplicates even under concurrent firing.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Administrator automates opportunity creation from existing triggers (Priority: P1)

An account administrator already uses Chatwoot's Automation Rules to react to events like "conversation created" or "label added." They want one of those existing rules to also automatically create an Opportunity in a chosen pipeline stage, without needing a separate, bespoke configuration screen just for this purpose.

**Why this priority**: This is the entire scope of this phase — without it, Opportunities can only ever be created manually, defeating the purpose of automation integration.

**Independent Test**: Create an Automation Rule with any existing trigger event and a "create_opportunity" action pointing at a chosen pipeline stage. Fire the triggering event for a conversation and confirm exactly one Opportunity is created, linked to that conversation's contact and to the origin conversation, in the configured stage.

**Acceptance Scenarios**:

1. **Given** an Automation Rule configured with a `create_opportunity` action and a valid `pipeline_stage_id`, **When** the rule's trigger event fires for a conversation, **Then** exactly one Opportunity is created for that conversation's contact, in the specified stage, with status `open`.
2. **Given** an Automation Rule's `create_opportunity` action includes no `title_template`, **When** the action runs, **Then** the created Opportunity's title defaults to the conversation's contact name plus the creation date.
3. **Given** an Automation Rule's `create_opportunity` action includes a `title_template`, **When** the action runs, **Then** the created Opportunity's title reflects that template.

---

### User Story 2 - Automation does not create duplicate opportunities on repeated firing (Priority: P1)

The same Automation Rule can legitimately fire more than once for the same conversation (e.g. a second label is added, triggering the rule again). The administrator expects this not to spawn multiple Opportunities for a single conversation.

**Why this priority**: Without idempotency, routine automation usage would flood the pipeline with duplicate Opportunities, making the feature unreliable and unusable in practice.

**Independent Test**: Run the same `create_opportunity` action twice for the same conversation and confirm only one Opportunity exists afterward, with no error raised on the second run.

**Acceptance Scenarios**:

1. **Given** an Opportunity already exists with a given conversation as its origin, **When** a `create_opportunity` action runs again for that same conversation, **Then** no new Opportunity is created and no error is raised.

---

### Edge Cases

- The action runs for a conversation whose contact is missing or invalid — the resulting error must propagate through the existing automation action error-handling/logging path rather than being silently swallowed inside the action itself.
- The action's `pipeline_stage_id` refers to a stage that doesn't exist or belongs to a different account — creation must fail rather than silently creating an Opportunity in the wrong or no stage.
- The action is configured on a rule whose trigger event is unrelated to conversations in a way that would leave no conversation context — out of scope; this phase assumes the action always runs in the context of a conversation, matching how `add_label`/`remove_label` already operate.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST make `create_opportunity` available as a selectable Automation Rule action alongside existing actions (e.g. `add_label`, `assign_agent`), without altering the behavior or list of any pre-existing action.
- **FR-002**: The system MUST extend the existing Automation action-dispatch mechanism to support running `create_opportunity`, using the same extension pattern already used for other automation/model behavior in this project, without changing how any existing action is dispatched or executed.
- **FR-003**: The `create_opportunity` action MUST accept a required parameter identifying which pipeline stage the new Opportunity should start in, and an optional parameter for the Opportunity's title; if the title is not supplied, the system MUST default it to the conversation's contact name combined with the creation date, in the format `"<contact name> - <creation date>"`.
- **FR-004**: The `create_opportunity` action MUST create exactly one Opportunity scoped to the same account as the conversation, linked to the conversation's contact, set to the configured pipeline stage, linked to the triggering conversation as its origin, and set to `open` status.
- **FR-005**: The `create_opportunity` action MUST be idempotent per conversation: if an Opportunity already exists whose origin is the same conversation, the system MUST skip creating a new one without raising an error, regardless of how many times the action subsequently runs for that conversation. This guarantee MUST hold even when the action runs concurrently for the same conversation (e.g. two triggering events firing in quick succession), enforced via a database-level uniqueness constraint on the origin conversation reference rather than an application-level check alone.
- **FR-006**: Any failure while creating the Opportunity (e.g. invalid data) MUST surface through the same error handling and logging already applied to other automation actions, without the `create_opportunity` action introducing its own separate error handling.
- **FR-007**: The `create_opportunity` action MUST be usable with any existing Automation Rule trigger event and any existing condition type; this phase MUST NOT introduce any new trigger event or condition type.
- **FR-008**: The system MUST provide a human-readable label for the `create_opportunity` action (e.g. "Create Opportunity") alongside the labels already provided for existing actions, so that any interface listing available actions can display it in place of a raw internal key.

### Key Entities

- **Automation Rule Action (create_opportunity)**: A new entry in the set of actions an Automation Rule can perform. Takes a target pipeline stage and an optional title template as configuration; produces at most one Opportunity per originating conversation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An administrator can configure an existing Automation Rule to create Opportunities with zero additional UI or setup screens beyond the existing Automation Rules configuration flow.
- **SC-002**: 100% of repeated action executions for the same conversation — including concurrent/near-simultaneous executions — result in exactly one Opportunity for that conversation, never more.
- **SC-003**: 100% of successful executions produce an Opportunity correctly scoped to the triggering conversation's account, contact, and configured pipeline stage.
- **SC-004**: Errors during Opportunity creation (e.g. invalid data) are captured and logged through the existing automation error-handling path in 100% of observed failures, with zero unhandled exceptions escaping the action.

## Assumptions

- This phase ships no end-user interface changes; the action becomes usable via API/backend configuration now, and will appear in the Automation Rules UI dropdown once Phase 3 renders it.
- A single implicit pipeline per account (established in Phase 1) remains in effect; this phase introduces no multi-pipeline routing.
- The action always runs in the context of a conversation, consistent with how comparable existing actions (e.g. `add_label`) already operate.
- "Skip silently" for duplicate prevention means no Opportunity is created and no error/log entry is produced for that specific duplicate-detection case, distinct from genuine failures which must still propagate and be logged.
