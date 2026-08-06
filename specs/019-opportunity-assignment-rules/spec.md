# Feature Specification: Opportunity Assignment Rules

**Feature Branch**: `019-opportunity-assignment-rules`

**Created**: 2026-08-05

**Status**: Draft

**Input**: User description: "Phase 24: Opportunity Assignment Rules — close the gap where `Opportunity.assignee_id` exists in the data model but nothing lets anyone set it: add a configurable assignee (specific agent, or 'same as the conversation') to the automation action that creates opportunities, and add a manual assign/reassign field to the opportunity create and edit views. Also fixes a bug where the opportunity-creation automation action never actually created opportunities because its stage selection was silently broken."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Auto-assign opportunities created by automation (Priority: P1)

An administrator sets up an automation rule that creates an opportunity when a conversation meets certain conditions. They want that opportunity to land on a specific agent's plate automatically — either a fixed agent/administrator, or whoever is already handling the conversation — instead of every new opportunity showing up unowned.

**Why this priority**: This is the primary way opportunities will get an owner going forward, and it also carries the fix for a bug where this automation action never actually created opportunities at all. Without it, the automation action remains silently broken and opportunities have no owner.

**Independent Test**: Configure an automation rule with the "create opportunity" action, set an assignee (a specific agent, or "same as the conversation"), trigger the rule, and confirm the resulting opportunity exists and is owned by the expected person.

**Acceptance Scenarios**:

1. **Given** an automation rule with a "create opportunity" action configured with a specific agent as assignee, **When** the rule is triggered, **Then** the created opportunity is assigned to that agent.
2. **Given** an automation rule with a "create opportunity" action configured with "same as the conversation" as assignee, and the triggering conversation currently has an assignee, **When** the rule is triggered, **Then** the created opportunity is assigned to that same conversation assignee.
3. **Given** the same "same as the conversation" configuration, but the triggering conversation currently has no assignee, **When** the rule is triggered, **Then** the created opportunity is created successfully with no assignee (no substitute owner is chosen).
4. **Given** an automation rule with a "create opportunity" action and a valid pipeline stage configured, **When** the rule is triggered, **Then** the opportunity is created in that stage (this previously failed every time due to a configuration bug, and must now succeed).

---

### User Story 2 - Manually reassign an opportunity's owner (Priority: P2)

An agent or administrator looks at an existing opportunity (e.g., from its kanban card) and wants to hand it off to someone else, or claim it, without needing an automation rule.

**Why this priority**: Automation won't cover every case — deals get reassigned as work is redistributed. This is the second most common way ownership will change day to day.

**Independent Test**: Open an existing opportunity for editing, change its assignee to a different agent (or clear it), save, and confirm the opportunity's owner reflects the change.

**Acceptance Scenarios**:

1. **Given** an opportunity with no assignee, **When** a user opens it for editing and selects an agent as the assignee, **Then** the opportunity is saved with that agent as its owner.
2. **Given** an opportunity already assigned to an agent, **When** a user opens it for editing and selects a different agent, **Then** the opportunity's owner is updated to the new agent.
3. **Given** an opportunity already assigned to an agent, **When** a user opens it for editing and clears the assignee, **Then** the opportunity becomes unassigned.
4. **Given** an opportunity being edited, **When** any agent or administrator on the account performs the reassignment, **Then** the action succeeds regardless of who is performing it (no ownership restriction).

---

### User Story 3 - Set an owner while creating an opportunity (Priority: P3)

A user manually creating a new opportunity wants to pick its owner at creation time rather than leaving it unassigned and reassigning it later.

**Why this priority**: Lower priority because it applies to the manual creation flow, which today has no dedicated entry point in the product surface yet; the field itself should exist and work whenever that entry point is built.

**Independent Test**: Open the opportunity creation form, pick an assignee, submit, and confirm the newly created opportunity has that assignee.

**Acceptance Scenarios**:

1. **Given** the opportunity creation form, **When** a user selects an assignee before submitting, **Then** the created opportunity is owned by that assignee.
2. **Given** the opportunity creation form, **When** a user submits without selecting an assignee, **Then** the created opportunity has no owner.

---

### Edge Cases

- What happens when an automation rule was configured before this feature shipped (using the old, broken configuration format)? Opening it in the editor shows the assignee and stage fields unconfigured; nothing is auto-migrated, and the admin must reconfigure the action from scratch.
- What happens when "same as the conversation" is selected but the conversation has no assignee at the moment the automation runs? The opportunity is still created, simply with no owner — there is no fallback assignee.
- What happens when an automation rule includes both an "assign conversation to an agent" action and a "create opportunity with same as the conversation" action in the same rule? Because actions run in the order they're configured and the conversation's state is re-read before each one, placing the assignment action first ensures the opportunity picks up that same agent.
- Is there any restriction on which agents/administrators can be chosen as assignee, or who can perform an assignment? No — any agent or administrator can be assigned, and any agent or administrator can perform the assignment or reassignment.
- Does assigning or reassigning an opportunity notify the new owner? No — no notification is sent as part of this feature.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The "create opportunity" automation action MUST support configuring an assignee, chosen either as a specific agent/administrator or as "same as the conversation" (the conversation the automation rule is running against).
- **FR-002**: When the automation action's assignee is set to "same as the conversation," the created opportunity MUST be assigned to that conversation's current assignee at the time the action runs; if the conversation has no assignee, the opportunity MUST still be created, left unassigned, with no substitute owner chosen.
- **FR-003**: The "create opportunity" automation action MUST correctly apply its configured pipeline stage to the created opportunity. (Previously this silently failed every time due to a configuration mismatch, so no opportunity was ever created by this action — this must now work.)
- **FR-004**: Any agent or administrator MUST be able to set or change an opportunity's assignee to any agent or administrator on the account; no permission restriction is applied to who can assign or be assigned.
- **FR-005**: No notification MUST be sent to an agent when an opportunity is assigned or reassigned to them, whether via automation or manually.
- **FR-006**: Users MUST be able to change an existing opportunity's assignee (including clearing it back to unassigned) from the opportunity edit view.
- **FR-007**: Users MUST be able to set an opportunity's assignee at creation time from the opportunity creation view; leaving it unset MUST result in the opportunity being created with no owner.
- **FR-008**: The manual assign/reassign fields (create and edit views) MUST NOT offer a "same as the conversation" option — that choice only makes sense in the automation context; manual assignment is always a direct selection of a person or "no owner."
- **FR-009**: Automation rules that were configured before this feature shipped, using the previous (non-functional) configuration format, MUST NOT be auto-migrated; reopening them for editing MUST show the assignee and stage fields as unconfigured, requiring the admin to reconfigure from scratch.

### Key Entities *(include if feature involves data)*

- **Opportunity**: A sales deal tracked on the kanban pipeline. Gains a settable/changeable **owner** (an agent or administrator, or none) and a correctly-applied **pipeline stage** at creation.
- **Automation Rule Action ("create opportunity")**: A configurable step within an automation rule that creates an opportunity when the rule fires. Its configuration now includes an assignee choice (specific person or "same as the conversation") in addition to its existing pipeline stage choice.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of opportunities created by a correctly configured "create opportunity" automation action are actually created (versus 0% before this feature, due to the prior silent failure).
- **SC-002**: 100% of opportunities created via a "same as the conversation" automation configuration are owned by the triggering conversation's assignee whenever that conversation has one.
- **SC-003**: A user can change an existing opportunity's owner in a single edit-and-save action, with the change visible immediately afterward.
- **SC-004**: A user can set an opportunity's owner at the moment of creating it, with no separate follow-up step required.

## Assumptions

- The assignee options (specific agent/administrator) are drawn from the same verified agent/administrator list already used elsewhere in the account's automation and assignment tooling — no new roster or grouping is introduced.
- Assignment behavior mirrors Chatwoot's existing conversation-assignment model: open to any agent or administrator, with no ownership-based permission gating.
- Notifications on opportunity assignment/reassignment, and any concept of pipeline- or stage-level ownership groups restricting who can be assigned, are explicitly out of scope for this feature and are tracked separately for a future cycle.
- The opportunity creation view's assignee field is being added in preparation for use; no new UI entry point to reach that creation view is introduced as part of this feature.
- Configuring the automation action's opportunity title template remains a pre-existing, unrelated gap and is not addressed here.
