# Feature Specification: Contact Panel Opportunities Section

**Feature Branch**: `020-contact-panel-opportunities`

**Created**: 2026-08-05

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 5/05-contact-panel-opportunities-section/spec9.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See a contact's opportunities without leaving the conversation (Priority: P1)

An agent working a conversation wants to know whether the contact already has open or past sales opportunities, and what state they're in, without switching to the kanban board and losing their place in the conversation.

**Why this priority**: This is the core value of the feature — surfacing sales context directly where the agent is already working. Without this, nothing else in the feature has a reason to exist.

**Independent Test**: Open a conversation for a contact who has one or more opportunities. Confirm an "Opportunities" section appears in the contact panel, listing those opportunities most-recent-first, without navigating away from the conversation.

**Acceptance Scenarios**:

1. **Given** a contact with three opportunities (one open, one won, one lost), **When** the agent opens the conversation and expands the "Opportunities" section in the contact panel, **Then** all three opportunities are listed, most recently created first, each showing its title, status, creation date, current stage, and time in stage.
2. **Given** a contact with no opportunities, **When** the agent expands the "Opportunities" section, **Then** an empty-state message is shown instead of a list.
3. **Given** an account where the opportunities/kanban feature is not enabled, **When** the agent opens any conversation's contact panel, **Then** no "Opportunities" section or accordion entry appears at all.

---

### User Story 2 - Edit an opportunity from the conversation (Priority: P2)

An agent reviewing a contact's opportunities in the panel wants to update one — change its stage, edit its value, or fill in missing details — without opening the kanban board.

**Why this priority**: Viewing opportunities is useful on its own (P1), but the ability to act on them from the same place is what turns this into a real workflow shortcut rather than a read-only summary.

**Independent Test**: From the contact panel's opportunity list, click an opportunity card and confirm an edit dialog opens over the conversation (no navigation), allowing stage, value, and custom attribute changes to be saved.

**Acceptance Scenarios**:

1. **Given** an open opportunity shown in the contact panel, **When** the agent clicks its card, **Then** an edit dialog opens in place, pre-filled with the opportunity's current title, stage, value, and custom attributes.
2. **Given** the edit dialog is open for an open opportunity, **When** the agent selects a different stage that has additional required fields, **Then** those required fields appear in the dialog and must be filled in before the change can be saved.
3. **Given** the edit dialog is open for an open opportunity, **When** the agent moves the opportunity backward to an earlier stage, **Then** the save succeeds without being blocked by the destination stage's required-fields check.
4. **Given** the edit dialog is open for an open opportunity, **When** the agent edits the deal value or any custom attribute and saves, **Then** the opportunity is updated and the dialog reflects the saved values.

---

### User Story 3 - Reopen a closed opportunity from the conversation (Priority: P3)

An agent reviewing a won or lost opportunity in the contact panel realizes it should be reopened (e.g., a lost deal is back in play) and wants to do so without leaving the conversation.

**Why this priority**: This extends the same shortcut convenience to closed opportunities, but affects a smaller slice of cases (only closed opportunities) than the general edit flow in P2.

**Independent Test**: From the contact panel, open the edit dialog for a won or lost opportunity, click the reopen action, and confirm the opportunity becomes editable as an open opportunity without closing and reordering the dialog.

**Acceptance Scenarios**:

1. **Given** a closed (won or lost) opportunity's edit dialog is open, **When** the agent clicks the reopen action, **Then** the opportunity's status becomes open immediately, and the dialog switches from a read-only stage display to an editable stage selector without requiring the dialog to be closed and reopened.
2. **Given** a closed opportunity's edit dialog is open and showing the read-only stage display, **When** the agent has not yet clicked reopen, **Then** no stage selector or save-triggered stage change is available — only the reopen action is offered for changing state.

---

### Edge Cases

- What happens when a contact's opportunity list changes (e.g., a new opportunity is created) while the agent already has the conversation open? The list should reflect the current contact whenever the section is shown or the contact changes; a currently-open edit dialog for an existing opportunity is not required to live-refresh from unrelated background changes.
- How does the system handle a contact with a very large number of opportunities? The list is not paginated in this feature; a single contact's opportunity count is expected to remain small enough to display in full.
- What happens if the agent switches to a different conversation (different contact) while the opportunities section is expanded? The section must refresh to show the new contact's opportunities, not the previous contact's.
- What happens if saving an opportunity edit fails validation (e.g., a forward stage move is missing a required field)? The dialog surfaces the validation error and keeps the entered data so the agent can correct it, consistent with existing opportunity-editing behavior elsewhere in the product.
- What happens when a closed opportunity has no stage-required-fields issues to worry about, since it's not being moved forward? Reopening only flips status to open; no stage-requirement validation applies to the reopen action itself.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow filtering an account's opportunities by contact, returning that contact's opportunities ordered most-recently-created first.
- **FR-002**: System MUST display an "Opportunities" section in the conversation's contact panel, positioned and behaving as a collapsible section consistent with the panel's other sections.
- **FR-003**: The "Opportunities" section MUST be visible only for accounts where the opportunities/kanban feature is enabled; accounts without it see no trace of the section.
- **FR-004**: The "Opportunities" section MUST list every opportunity belonging to the currently open conversation's contact, regardless of status (open, won, or lost), most-recently-created first.
- **FR-005**: The "Opportunities" section MUST refresh its contents whenever the displayed contact changes (e.g., the agent switches conversations).
- **FR-006**: When a contact has no opportunities, the section MUST show an empty-state message instead of an empty list.
- **FR-007**: Each opportunity entry in the list MUST show, at minimum: title, status, creation date, current stage, time spent in the current stage, and the same key value/attribute highlights shown for opportunities on the kanban board.
- **FR-008**: Clicking an opportunity entry MUST open an editing dialog for that opportunity without navigating away from the conversation.
- **FR-009**: The editing dialog MUST allow changing an open opportunity's title, stage, deal value, and custom attributes, and saving those changes.
- **FR-010**: When changing an open opportunity's stage in the editing dialog, the dialog MUST determine required fields based on the newly selected destination stage (not the opportunity's currently saved stage), and MUST require the destination stage's required fields to be filled in before the change is accepted, consistent with the existing forward-stage-move validation elsewhere in the product.
- **FR-011**: Moving an opportunity backward to an earlier stage via the editing dialog MUST NOT be blocked by the destination stage's required-fields check.
- **FR-012**: The deal value field in the editing dialog MUST always be available for editing, and MUST only be marked as required when the selected destination stage requires a deal value.
- **FR-013**: For a closed (won or lost) opportunity, the editing dialog MUST show the current stage as read-only (no stage selector) and offer a reopen action instead.
- **FR-014**: Triggering the reopen action MUST immediately change the opportunity's status to open, independent of the dialog's main save action, and MUST update the dialog in place — without requiring it to be closed and reopened — so the agent can continue editing (including now selecting a stage) in the same sitting.
- **FR-015**: Saving changes from the editing dialog MUST persist title, stage, deal value, custom attributes, and assignee together in a single update.
- **FR-016**: This feature MUST NOT introduce any new way to create an opportunity from the contact panel.
- **FR-017**: This feature MUST NOT change who is allowed to change stage, reopen, or edit an opportunity's assignee — access remains as it is for opportunities today.
- **FR-018**: This feature MUST NOT add pagination or infinite scroll to the contact panel's opportunity list.
- **FR-019**: This feature MUST NOT alter the behavior of the contact panel's existing "previous conversations" section.

### Key Entities *(include if feature involves data)*

- **Opportunity**: A sales opportunity tied to a contact, with a title, status (open/won/lost), current pipeline stage, deal value, creation date, custom attributes, and assignee. This feature reads and updates existing opportunities; it does not introduce new opportunity data.
- **Contact**: The person a conversation belongs to; the anchor by which opportunities are filtered and displayed in the contact panel.
- **Pipeline Stage**: The stage an opportunity currently sits in, or is being moved to; determines which custom attributes are required.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An agent can see all of a contact's opportunities, with status and stage, within the same conversation view, in under 5 seconds of expanding the section.
- **SC-002**: An agent can open, edit, and save changes to an opportunity (including stage, value, and custom attributes) without ever leaving the conversation view.
- **SC-003**: An agent can reopen a closed opportunity and immediately continue editing it in the same dialog interaction, with zero additional navigation steps.
- **SC-004**: Accounts without the opportunities feature enabled see zero visual or functional change to their contact panel.
- **SC-005**: Opportunity edits made from the contact panel produce the same saved result as equivalent edits made from the kanban board, with no divergence in outcome.

## Assumptions

- The existing opportunities/kanban feature flag is the sole gate for this section's visibility; no separate permission or rollout mechanism is introduced.
- A single contact is expected to have a small number of opportunities (no pagination is needed for this feature to remain usable).
- Existing validation rules for forward stage moves (required fields) and existing access rules for editing/reopening opportunities are reused as-is; this feature does not redefine them.
- The opportunity editing dialog is a shared surface used both from the kanban board and from the contact panel; behavioral improvements made for this feature apply in both places rather than creating a separate, panel-only variant.
- Notifications on stage change or reopen are out of scope, consistent with current opportunity behavior.
