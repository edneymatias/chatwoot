# Feature Specification: Closing Required Fields (Win/Loss)

**Feature Branch**: `010-closing-required-fields`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "Phase 19: Closing Required Fields (Win/Loss) — closing an opportunity as won or lost may require specific custom attributes to be filled first (e.g. a loss reason, or contact phone/email on a win). These requirements are global per account (one set of attributes required to mark won, one set required to mark lost), independent of pipeline stage. Distinct from the existing per-stage forward-move requirement mechanism (Phase 7)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Blocking a close until required fields are filled (Priority: P1)

A sales rep drags an opportunity card to a "won" or "lost" outcome (or otherwise changes its status). If the account has configured required attributes for that outcome and the opportunity is missing any of them, the rep is stopped and shown a form to fill in exactly the missing attributes before the status change is finalized.

**Why this priority**: This is the core value of the feature — without it, closing requirements are configured but never enforced, so the feature does nothing.

**Independent Test**: Configure one required attribute for "lost", attempt to mark an opportunity without that attribute as lost, and verify the change is blocked and a form requesting the attribute appears.

**Acceptance Scenarios**:

1. **Given** an account has one custom attribute configured as required for "lost" and an opportunity lacks a value for it, **When** a user changes that opportunity's status to lost, **Then** the status change is rejected and the user is shown a form requesting the missing attribute.
2. **Given** the user fills in the missing attribute via the form and resubmits, **When** the retry request is sent, **Then** the opportunity's status is updated to lost and the custom attribute value is saved.
3. **Given** an account has no required attributes configured for "won", **When** a user changes an opportunity's status to won, **Then** the status change succeeds immediately with no form shown.

---

### User Story 2 - Configuring required fields per outcome (Priority: P2)

An account admin opens the pipeline setup screen and, in a dedicated "Closing" tab, selects which custom attributes are required for marking an opportunity as won, and separately which are required for marking one as lost.

**Why this priority**: Enforcement (User Story 1) has no effect until an admin can configure which attributes are required, but the underlying data model can be seeded/tested before the settings UI exists.

**Independent Test**: As an admin, open the Closing tab, add an attribute to the "required for won" list and a different attribute to the "required for lost" list, save, and verify both lists persist on reload.

**Acceptance Scenarios**:

1. **Given** an admin is on the Closing tab, **When** they add a custom attribute to the "required for won" list, **Then** it is saved and appears in the list on reload.
2. **Given** an admin is on the Closing tab, **When** they add the same custom attribute to both the "required for won" and "required for lost" lists, **Then** both are saved independently (no conflict).
3. **Given** an admin attempts to add the same attribute twice to the same outcome's list, **When** they submit, **Then** the duplicate is rejected or silently ignored (no duplicate entry is created).

---

### User Story 3 - Reopening a closed opportunity is unaffected (Priority: P3)

A user reopens a previously won or lost opportunity back to an open/in-progress status. Since closing requirements only guard the transition *into* won or lost, reopening does not trigger any required-field check.

**Why this priority**: Lower priority because it's a guard against an incorrect implementation rather than new user-facing value, but important to verify since the validation trigger (status change) could easily be misapplied to all status changes rather than only closing ones.

**Independent Test**: Reopen a won opportunity that is missing attributes normally required for "won" and confirm the reopen succeeds without any required-field prompt.

**Acceptance Scenarios**:

1. **Given** an opportunity is currently won and missing an attribute that is required for "won", **When** a user changes its status back to open, **Then** the change succeeds with no required-field check performed.

---

### Edge Cases

- What happens when a required attribute is later removed from the account's custom attribute definitions entirely? The closing requirement referencing it should no longer be enforceable and should not block closes (the definition no longer exists).
- What happens when an admin removes an attribute from the "required for lost" list after opportunities have already been closed as lost without it? Already-closed opportunities are unaffected retroactively — the requirement only applies at the moment of the status-changing action.
- How does the system handle a status change request that changes both `pipeline_stage_id` and `status` in the same request? Both the existing forward-stage-move requirement check and the new closing requirement check apply independently; either can block the request.
- What happens if the same custom attribute is required for both "won" and "lost"? This is allowed — the two lists are independent per outcome.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow account admins to configure a list of custom attributes required specifically for marking opportunities as "won", independent of pipeline stage.
- **FR-002**: System MUST allow account admins to configure a separate list of custom attributes required specifically for marking opportunities as "lost", independent of pipeline stage.
- **FR-003**: System MUST prevent duplicate entries for the same custom attribute within the same outcome's required list, while allowing the same attribute to appear in both the "won" and "lost" lists.
- **FR-004**: System MUST only allow custom attributes of the opportunity-attribute type to be configured as closing requirements.
- **FR-005**: System MUST validate, at the moment an opportunity's status is changed to "won" or "lost", that all custom attributes configured as required for that outcome have values present on the opportunity.
- **FR-006**: System MUST reject the status change and report exactly which required attributes are missing when the validation in FR-005 fails.
- **FR-007**: System MUST NOT run the closing-requirement validation when an opportunity's status changes to anything other than "won" or "lost" (e.g. reopening to an open/in-progress status).
- **FR-008**: System MUST present the user with a way to supply the missing required attribute values and retry the status change without losing the in-progress close action.
- **FR-009**: System MUST apply closing requirements uniformly across all pipeline stages within an account — they are not scoped to a specific stage.
- **FR-010**: System MUST keep closing-requirement validation independent of the existing per-stage forward-move requirement validation — a status change to won/lost may be subject to both checks without one overriding the other.

### Key Entities

- **Closing Required Field**: Represents that a specific custom attribute is required before an opportunity can be marked with a given outcome (won or lost) for a given account. Attributes: account, custom attribute definition, outcome (won/lost).
- **Opportunity**: The existing entity being closed; gains a validation dependency on Closing Required Field entries matching its account and target outcome whenever its status is changing to won or lost.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users attempting to close an opportunity as won or lost while missing a required attribute are blocked 100% of the time until the attribute is supplied.
- **SC-002**: Users can supply missing required attributes and complete the close action in a single follow-up submission, without re-entering unrelated opportunity data.
- **SC-003**: Admins can configure or update the required-attribute lists for won and lost outcomes in under 1 minute per change.
- **SC-004**: Reopening a closed opportunity is never blocked by closing requirements, regardless of which attributes are missing.

## Assumptions

- Closing requirements are attribute-based only (an attribute must have a value present); value-based conditions (e.g. requiring a minimum deal value) are out of scope unless a concrete need is identified later.
- Closing requirements are global per account, not configurable per pipeline or per stage.
- The existing missing-required-fields error contract and retry pattern established for per-stage forward-move requirements will be reused for closing requirements, so no new interaction pattern is introduced for end users.
- Only custom attributes already defined as opportunity attributes can be selected as closing requirements; defining new attribute types is out of scope.
