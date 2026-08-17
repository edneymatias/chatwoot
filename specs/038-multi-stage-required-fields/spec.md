# Feature Specification: Multi-Stage Required Fields

**Feature Branch**: `038-multi-stage-required-fields`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "quero que seja possivel exigir campos personalizados em qualquer estágio do funil efetivamente removendo o bloqueio que existe hoje que exige que um campo esteja associado a apenas uma etapa do funil."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Require the same custom field in multiple stages (Priority: P1)

A sales manager configuring the pipeline wants to require a custom attribute (e.g. "Budget confirmed") in more than one stage of the same funnel — for example both "Qualification" and "Proposal" — because the field is relevant checkpoint information at each of those points, not just one.

**Why this priority**: This is the core blocker being removed. Without it, the feature has no effect: managers today get an error the moment they try to mark a second stage as requiring an already-required attribute.

**Independent Test**: Can be fully tested by marking a custom attribute as required on Stage A, then marking the same attribute as required on Stage B in the same pipeline, and confirming both configurations are saved and both stages independently enforce the requirement.

**Acceptance Scenarios**:

1. **Given** a custom attribute is already required on Stage A, **When** a manager marks the same attribute as required on Stage B, **Then** the configuration is saved successfully (no "already required" error) and both stages now list the attribute as required.
2. **Given** a custom attribute is required on both Stage A and Stage B, **When** a manager removes the requirement from Stage A, **Then** Stage B's requirement remains intact and is still enforced.
3. **Given** a custom attribute is already required on Stage A, **When** a manager attempts to require the same attribute on Stage A again, **Then** the system still rejects the duplicate (the constraint against re-requiring the exact same attribute on the exact same stage is unchanged).

---

### User Story 2 - Field filled once is not re-requested on a later required stage (Priority: P2)

An opportunity moves forward through the pipeline. It already satisfied a required custom attribute at an earlier stage where that attribute was required and the value was filled in. Later, the opportunity moves into a different stage that also requires that same attribute.

**Why this priority**: This preserves existing behavior (documented in the original backlog note) that must not regress once a field can be required in multiple stages: once filled, a field should not block forward movement again solely because a later stage also requires it, as long as the value is still present on the opportunity.

**Independent Test**: Can be fully tested by moving an opportunity forward through a stage that requires an attribute (filling it in to pass), then continuing forward into a later stage that also requires that same attribute, and confirming the second forward move is not blocked by that attribute.

**Acceptance Scenarios**:

1. **Given** an opportunity moved forward through Stage A (which requires "Budget confirmed" and the value was filled in), **When** the opportunity is subsequently moved forward into Stage B (which also requires "Budget confirmed"), **Then** the move is not blocked by that attribute, because the value is already present on the opportunity.
2. **Given** an opportunity has never had "Budget confirmed" filled in, **When** it is moved forward into a stage that requires it, **Then** the move is blocked and the missing field is reported, regardless of how many other stages also require that attribute.

---

### User Story 3 - Manage per-stage required fields without cross-stage restrictions (Priority: P3)

A manager reviewing or editing a stage's required-fields configuration (e.g. via stage settings) wants the list of custom attributes available to select from to no longer exclude attributes just because another stage already requires them.

**Why this priority**: Supporting/UX polish — ensures the configuration screen reflects the new rule so managers aren't misled by a UI that still hides "already required elsewhere" attributes as unavailable.

**Independent Test**: Can be fully tested by opening the required-fields configuration for a stage after an attribute is already required on a different stage, and confirming that attribute appears as selectable (not hidden/disabled).

**Acceptance Scenarios**:

1. **Given** an attribute is required on Stage A, **When** a manager opens the required-fields configuration for Stage B, **Then** that attribute is shown as available to select as required, not hidden or disabled.

---

### Edge Cases

- What happens when an opportunity moves backward through a stage that requires an attribute, and then forward through that same stage again? (Existing forward-move-only validation trigger is unchanged: the check only runs on forward position moves, and only blocks when the attribute value is genuinely missing at validation time — no new re-trigger behavior is introduced by this change.)
- What happens when the same attribute is required on two stages and a manager removes the requirement from one of them while an opportunity's current stage still depends on the remaining requirement? The remaining stage's requirement continues to apply normally; removing a requirement from one stage has no effect on the other stage's independent requirement record.
- What happens if a manager tries to require the exact same attribute on the exact same stage twice (not two different stages)? This remains blocked — the restriction being removed is "different stages, same attribute," not "same stage, same attribute" duplicates.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow a custom attribute to be marked as required in more than one pipeline stage within the same account.
- **FR-002**: System MUST continue to prevent the exact same custom attribute from being required more than once on the exact same stage (no duplicate requirement records for one stage/attribute pair).
- **FR-003**: System MUST evaluate each stage's required-field list independently when validating a forward stage move — an opportunity moving into a stage is blocked only by attributes required on the destination stage that are actually missing from the opportunity at that time.
- **FR-004**: System MUST NOT re-block forward movement on an attribute that a later required stage also requires if that attribute already has a value on the opportunity (preserves "filled once, don't ask again" behavior).
- **FR-005**: System MUST allow removing a required-field configuration from one stage without affecting the required-field configuration of the same attribute on any other stage.
- **FR-006**: The required-fields configuration UI for a given stage MUST present custom attributes as selectable for that stage regardless of whether they are already required on other stages.
- **FR-007**: System MUST continue restricting required-field configuration to custom attributes scoped to opportunities (existing "must be an opportunity attribute" rule is unchanged).

### Key Entities

- **Pipeline Stage Required Field**: Links a pipeline stage to a custom attribute definition that must be filled in before an opportunity can move forward into (or past) that stage. Previously limited to one stage per attribute per account; now scopes uniqueness to the stage+attribute pair instead of the attribute alone.
- **Opportunity**: The record whose custom attribute values are checked against each stage's required-field list when it moves forward through the pipeline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Managers can configure the same custom attribute as required on at least two different stages in the same pipeline without encountering an error.
- **SC-002**: Opportunities that already have a required attribute filled in are never blocked from moving forward solely because a later stage also requires that same attribute — 0% false-block rate for already-filled attributes across multi-stage requirements.
- **SC-003**: Removing a required-field configuration from one stage does not alter enforcement behavior on any other stage requiring the same attribute, verified across all affected stages.

## Assumptions

- The existing "filled once, don't ask again" behavior is being preserved as-is, not redesigned — this spec only removes the cross-stage uniqueness restriction.
- This feature is independent of the pipeline closing (won/lost) required fields mechanism; no changes to that table or its validation trigger are in scope.
- No changes are needed to how missing required fields are reported to the user (error format/messaging stays the same), only to which combinations of stage + attribute are permitted to be configured as required.
- Backward stage moves are out of scope for new validation — the forward-only validation trigger for required fields is unchanged by this feature.
