# Feature Specification: Stage Transition Rules

**Feature Branch**: `007-stage-transition-rules`

**Created**: 2026-08-01

**Status**: Draft

**Input**: User description: "Phase 7: Stage Transition Rules for the Kanban/Opportunities feature — lane-level required fields (custom attributes and deal value) enforced on forward stage moves, with a stage-aware creation form and a manual 'complete fields' backfill action. Derived from `docs/kanban/ciclo 2/03-stage-transition-rules/spec7.md`."

## Clarifications

### Session 2026-08-01

- Q: For a required field whose value is a "falsy" or zero-like value (an unchecked checkbox, a deal value of exactly 0, an empty-but-touched list selection), does that count as satisfying the requirement, or as still missing? → A: Any value that has been explicitly set counts as present, even if it's the type's "empty"-looking value (`false`, `0`) — presence means the key was set, not that it's truthy.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sales rep is guided to complete required info before advancing a deal (Priority: P1)

A sales rep drags an opportunity card forward from one pipeline stage into a later one that the
team has configured to require certain information (e.g. budget, decision maker, deal value)
before a deal can be considered "qualified" for that stage. If that information is missing, the
rep is stopped and shown exactly what's missing, fills it in on the spot, and the card completes
its move with the new information saved.

**Why this priority**: This is the core value of the feature — it is what makes pipeline stages
meaningful checkpoints instead of just labels, and prevents deals from silently skipping
qualification steps. Without this, none of the rest of the feature has a purpose.

**Independent Test**: Can be fully tested by configuring one stage with a required field, dragging
a card that lacks it into that stage, confirming the rep is prompted and blocked until the field
is filled, and confirming the card moves once submitted.

**Acceptance Scenarios**:

1. **Given** a destination stage requires "Budget" and the dragged deal has no budget set,
   **When** the rep drags the card into that stage, **Then** the move is paused and the rep is
   prompted to fill "Budget" before the card lands in the new stage.
2. **Given** a destination stage requires "Budget" and the dragged deal already has a budget
   value, **When** the rep drags the card into that stage, **Then** the card moves immediately
   with no prompt.
3. **Given** the destination stage is two positions ahead and an intermediate stage has its own
   required field the deal never filled, **When** the rep is prompted, **Then** that intermediate
   field is shown pre-filled if available and clearly optional, and does not block the move.
4. **Given** the rep is prompted for missing fields, **When** they cancel instead of submitting,
   **Then** the card visually returns to its original stage and nothing is saved.

---

### User Story 2 - Sales manager defines what information is required at each stage (Priority: P1)

A sales manager configuring the team's pipeline decides which pieces of deal information must be
known before a deal can be considered to have reached a given stage (e.g. "Proposal Sent" requires
a deal value; "Qualified" requires a budget and a decision-maker contact). They set this up once
per stage and can move a requirement from one stage to another as the process evolves.

**Why this priority**: Without a way to configure requirements, User Story 1 has nothing to
enforce. This is the setup work that makes the enforcement meaningful and adjustable to each
team's process.

**Independent Test**: Can be fully tested by opening a stage's configuration, assigning a field
and the deal value as required, saving, and confirming the requirement now shows up when
attempting to move a card into that stage.

**Acceptance Scenarios**:

1. **Given** a manager is editing a stage's settings, **When** they mark a deal field and the
   deal value as required for that stage, **Then** those requirements take effect immediately for
   subsequent moves into that stage.
2. **Given** a field is already required by one stage, **When** the manager assigns that same
   field as required to a different stage, **Then** it is removed from the original stage's
   requirements and only enforced at the new stage.

---

### User Story 3 - Rep is never blocked when moving a deal backward (Priority: P2)

A sales rep moves a card backward (e.g. to re-qualify a stalled deal), regardless of what
information is or isn't filled in. This never triggers a prompt or a block — moving backward is
always unrestricted.

**Why this priority**: This is a safety/usability guarantee that must hold for the feature to be
trusted; without it, reps could get stuck unable to correct a mistaken forward move or reflect a
deal regressing.

**Independent Test**: Can be fully tested by dragging a card with missing required fields into an
earlier stage and confirming no prompt appears and the move completes.

**Acceptance Scenarios**:

1. **Given** a deal is missing fields required by its current stage, **When** the rep drags it
   backward to an earlier stage, **Then** the move completes immediately with no validation and
   no prompt.

---

### User Story 4 - Deal creator sees relevant fields without being forced to fill them (Priority: P2)

A person creating a new opportunity picks a starting stage. If that stage has required fields
configured, the creation form shows those fields right away so the person filling it out
naturally sees what's expected — but they can still save the deal without filling them in.

**Why this priority**: Keeps the lightweight creation flow lightweight (not a full edit form)
while still surfacing expectations, and avoids penalizing deals created directly into a later
stage (e.g. imported or referred deals) that don't have prior stage history to justify a hard
block.

**Independent Test**: Can be fully tested by starting to create an opportunity, selecting a stage
with required fields, confirming those fields render on the form, and confirming the opportunity
can still be saved without filling them.

**Acceptance Scenarios**:

1. **Given** a person is creating a new opportunity, **When** they select a stage that has
   required fields configured, **Then** those fields appear inline on the creation form.
2. **Given** those fields are left empty, **When** the person submits the creation form, **Then**
   the opportunity is created successfully.

---

### User Story 5 - Rep can backfill missing information without moving the deal (Priority: P3)

A deal is sitting in a stage whose requirements it doesn't currently satisfy — because it moved
backward into the stage, or because a manager changed the stage's requirements after the deal
already arrived there. The rep sees a clear, always-available action on the card to complete the
missing information without having to drag it anywhere.

**Why this priority**: This is the safety net for the two situations (backward moves,
reconfiguration) that the forward-move gate deliberately does not cover; lower priority since it
depends on the core enforcement (US1/US2) already existing.

**Independent Test**: Can be fully tested by putting a card into a stage with unmet requirements
(via backward move or by changing that stage's requirements after the fact) and confirming a
"complete fields" action is visible, opens the missing fields, and updates the deal in place
without changing its stage.

**Acceptance Scenarios**:

1. **Given** a card sits in a stage whose required fields it doesn't currently satisfy, **When**
   the rep views the card, **Then** a "complete fields" action is visible.
2. **Given** the rep uses that action and fills the missing fields, **When** they submit,
   **Then** the deal is updated and remains in its current stage.
3. **Given** a card's stage requirements are already satisfied, **When** the rep views the card,
   **Then** no "complete fields" action is shown.

---

### Edge Cases

- What happens when a deal is dragged forward two or more stages at once? Only the destination
  stage's own required fields block the move; fields belonging to stages in between are shown as
  optional context, not enforced.
- What happens if a required field is deleted or a stage is removed while deals are mid-pipeline?
  Requirements tied to a removed stage or field no longer apply; this is not a supported
  reconfiguration scenario requiring special handling beyond normal data cleanup.
- What happens if someone bypasses the on-screen prompt and submits a forward move directly (e.g.
  via a direct API call) with missing required fields? The move is rejected with a clear,
  structured description of what's missing, mirroring what the on-screen prompt would have shown.
- What happens if a deal is created directly into a later stage without ever passing through
  earlier stages? No historical fields from skipped stages are demanded — only the created
  stage's own fields are surfaced, and even those don't block creation.
- What happens when the same field is required by a stage, then unassigned from it without being
  reassigned elsewhere? It simply stops being enforced anywhere until assigned to a stage again.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every opportunity MUST be able to store a numeric deal value and a set of custom
  field values, independent of whether it originated from a conversation.
- **FR-002**: The system MUST allow designating at most one pipeline stage per account as the
  stage that requires the deal value to be filled in; assigning this to a new stage automatically
  removes it from whichever stage previously had it.
- **FR-003**: The system MUST allow designating any custom deal field as required by at most one
  pipeline stage at a time; assigning a field to a new stage automatically removes the requirement
  from its previous stage.
- **FR-004**: The system MUST support defining custom fields that belong to opportunities (as
  distinct from fields that belong to conversations or contacts), so that lead-qualification data
  can exist even for opportunities without an originating conversation.
- **FR-005**: When an opportunity is moved to a stage with a strictly later position than its
  previous stage (a forward move), the system MUST verify that every field required by the
  destination stage — including the deal value, if required — has been explicitly set before
  allowing the move to complete. A field counts as set once it has any explicit value, including
  a "falsy" or zero-like one (an unchecked checkbox, a deal value of `0`); only a field that was
  never touched counts as missing.
- **FR-006**: When an opportunity is moved to a stage with the same or earlier position than its
  previous stage (a backward or lateral move), the system MUST NOT perform any required-field
  validation and MUST allow the move unconditionally.
- **FR-007**: When a forward move is blocked due to missing required fields, the system MUST
  communicate which specific fields are missing (including whether the deal value specifically is
  missing) in a way that can be used to guide the user to fix them.
- **FR-008**: Users MUST be able to attempt to fix missing required fields and retry the move
  without losing their place, both when caught before the move is dispatched and when caught by
  the system rejecting the underlying request directly.
- **FR-009**: When prompted to fill fields for a forward move, users MUST also be able to see and
  optionally edit fields belonging to every stage positioned earlier than the destination stage
  (i.e. all stages before it by position, excluding the destination itself — not only stages
  between the deal's current and destination stage), pre-filled with any existing values, without
  those fields blocking the move.
- **FR-010**: Creating a new opportunity MUST NOT be blocked by any stage's required-field
  configuration, regardless of which stage is selected as the starting stage.
- **FR-011**: The opportunity creation experience MUST surface the required fields of whichever
  stage is currently selected as the starting stage, so the creator can see and optionally fill
  them even though they aren't enforced at creation time.
- **FR-012**: Users configuring a pipeline stage MUST be able to view and change which custom
  deal fields, and whether the deal value, are required for that specific stage.
- **FR-013**: Every opportunity card MUST expose a manually-triggerable action to fill in fields
  required by the card's current stage, available independent of any drag action, and this action
  MUST be visible only when the card's current stage has at least one unmet requirement.
- **FR-014**: Using the manual "complete fields" action MUST update the opportunity's field values
  without changing its current stage.
- **FR-015**: Attempting to save a forward stage move directly (bypassing any on-screen guidance)
  with missing required fields MUST be rejected with a response that clearly identifies which
  required fields are missing.

### Key Entities

- **Opportunity (deal)**: A sales opportunity tracked on the pipeline board; gains a numeric deal
  value and a set of custom field values as attributes. May or may not have an originating
  conversation.
- **Pipeline Stage (lane)**: A position/column on the pipeline board; can be configured to require
  the deal value and/or one or more specific custom deal fields be filled before a deal can move
  forward into it.
- **Custom Deal Field**: A user-defined field that belongs to opportunities specifically (as
  opposed to conversations or contacts), used to capture lead-qualification data such as budget or
  decision maker.
- **Stage Field Requirement**: The association between a pipeline stage and a custom deal field
  (or the deal value) marking it as required to advance into that stage; unique per field across
  the account, so a field is required by at most one stage at any time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Sales reps attempting to advance a deal into a stage with missing required
  information are shown exactly what's missing before any move is committed, with zero cases of a
  deal silently landing in a stage without its required data being filled.
- **SC-002**: Moving a deal backward never triggers a validation prompt, in 100% of backward-move
  attempts regardless of the deal's field completeness.
- **SC-003**: Sales managers can reconfigure which fields are required at which stage, and see the
  change reflected the next time any deal is moved, without needing engineering assistance.
- **SC-004**: A deal that ends up in a stage with unmet requirements (via backward move or
  reconfiguration) can always be brought into compliance through a single, discoverable action on
  the card, without needing to move the deal at all.
- **SC-005**: Creating a new opportunity directly into any stage — including one with required
  fields — succeeds without being blocked, in 100% of creation attempts.
- **SC-006**: Direct attempts to bypass on-screen guidance and force a forward move with missing
  required data are rejected 100% of the time, with a response that identifies the missing fields.

## Assumptions

- The custom-field infrastructure already used elsewhere in the product (for conversations and
  contacts) is extended with a new category for opportunity-level fields, rather than building a
  parallel custom-field system from scratch.
- "Position" of a pipeline stage refers to its existing order within the pipeline, which already
  determines forward vs. backward for the purposes of this feature.
- Automation or bulk pre-filling of opportunity custom fields on creation is out of scope for this
  feature and would be considered separately if pursued.
- A custom deal field or the deal value being required by "at most one lane at a time" is the
  desired model going forward; there is no need to support a field being required by multiple
  stages simultaneously or remaining required indefinitely once passed.
- Retroactively re-validating every existing deal against changed stage requirements in bulk is
  out of scope; the manual per-card "complete fields" action is the intended remediation path.
