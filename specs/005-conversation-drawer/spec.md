# Feature Specification: Conversation Drawer on Card Click

**Feature Branch**: `005-conversation-drawer`

**Created**: 2026-07-31

**Status**: Draft

**Input**: User description: "Phase 5: Conversation Drawer on Card Click — replace the existing Opportunity detail side panel (which only shows metadata and links away to the full conversation view) with a drawer that opens on top of the Kanban board when a card is clicked, showing the full native conversation thread and contact sidebar in place, so agents can reply, resolve, and assign without leaving the board."

## Clarifications

### Session 2026-07-31

- Q: What should the drawer display while the conversation is being fetched, before it's ready to show the thread and sidebar? → A: Show the same loading/skeleton indicator the standalone conversation view already shows while loading a conversation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agent opens the full conversation from a Kanban card (Priority: P1)

An agent viewing the Kanban board clicks an Opportunity card that has a linked conversation. A drawer slides in from the right, on top of the board, showing the real conversation thread and the native contact sidebar — the same experience as the regular conversation view. The agent can reply, resolve, assign, or perform any other normal conversation action without ever leaving the Kanban board.

**Why this priority**: This is the core value of the feature — today agents must abandon the board entirely to act on a conversation. Delivering the in-context drawer is what makes the board a viable place to work from, not just a reporting screen.

**Independent Test**: Click a card with a linked conversation and confirm the drawer opens showing the message thread and contact sidebar, and that replying, resolving, and assigning all work exactly as they do in the standalone conversation view.

**Acceptance Scenarios**:

1. **Given** the Kanban board is open, **When** an agent clicks a card that has a linked conversation, **Then** a drawer slides in from the right showing that conversation's message thread and contact sidebar, without navigating away from the board.
2. **Given** the drawer is open, **When** the agent replies to, resolves, or assigns the conversation, **Then** the action succeeds exactly as it would in the standalone conversation view.
3. **Given** the drawer is open for a given conversation, **When** the agent reloads the page at the drawer's URL, **Then** the drawer reopens directly showing the same conversation.

---

### User Story 2 - Agent recognizes cards with no linked conversation (Priority: P2)

An agent scanning the board can immediately tell which cards have no conversation to open. Clicking such a card does nothing.

**Why this priority**: Without a visual cue, agents would repeatedly click dead cards expecting the drawer to open, creating confusion and eroding trust in the board.

**Independent Test**: View a board containing at least one opportunity without a linked conversation and confirm that card is visually muted, shows no pointer-hand affordance, and clicking it produces no action.

**Acceptance Scenarios**:

1. **Given** an opportunity card has no linked conversation, **When** the agent views the board, **Then** that card renders with reduced opacity and no clickable-hover affordance.
2. **Given** an opportunity card has no linked conversation, **When** the agent clicks it, **Then** nothing happens — no drawer opens, no navigation occurs.

---

### User Story 3 - Agent closes the drawer and returns cleanly to the board (Priority: P2)

After finishing work in the drawer, the agent closes it (via a close button or browser back navigation) and lands back on the board exactly as they left it, with no leftover state affecting the rest of the app.

**Why this priority**: A drawer that leaks state (e.g., a "stuck" active chat elsewhere in the app) or disrupts the board's own data would undermine trust in the whole feature, even if opening the drawer works correctly.

**Independent Test**: Open the drawer, close it via the close button, and separately via browser back navigation, and confirm in both cases the board reappears unchanged and no other part of the app still reflects the closed conversation as "active."

**Acceptance Scenarios**:

1. **Given** the drawer is open, **When** the agent clicks the close button, **Then** the board reappears with no change to its cards or stage layout, and no other part of the app treats that conversation as currently active.
2. **Given** the drawer is open, **When** the agent uses browser back navigation, **Then** the same clean return to the board occurs.

---

### User Story 4 - Agent sees a clear error when a linked conversation can't be opened (Priority: P3)

If the conversation behind a card can't actually be loaded (e.g., it was deleted, or the agent lost access), the drawer still opens but shows a clear error message and a way to close it, instead of a blank or broken panel.

**Why this priority**: This is a lower-frequency edge case, but without it agents would be stuck looking at a broken or empty drawer with no explanation and no way out.

**Independent Test**: Trigger the drawer for a conversation id that cannot be loaded (not found or no permission) and confirm an inline error message with a close action appears instead of a blank panel.

**Acceptance Scenarios**:

1. **Given** a card's linked conversation id can no longer be loaded, **When** the agent clicks the card, **Then** the drawer opens showing an inline error message and a close action, instead of the message thread and contact sidebar.

---

### Edge Cases

- What happens when an agent directly opens the drawer's URL for a conversation they don't have permission to view? → Same inline error state as User Story 4.
- What happens when the agent clicks a card while a previous drawer is still closing/opening? → The drawer reflects only the most recently clicked card's conversation; no stale conversation is shown.
- What happens to the Kanban board's own data (cards, stages) while the drawer is open or after it closes? → It is unaffected; opening or closing the drawer never reloads or mutates board data.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Opening the conversation drawer MUST be addressable by its own URL nested under the Kanban board's URL, so the drawer can be deep-linked, reloaded, and closed via back navigation.
- **FR-002**: Clicking a card with a linked conversation MUST open the drawer for that conversation. Clicking a card without a linked conversation MUST have no effect (no drawer, no navigation).
- **FR-003**: Cards without a linked conversation MUST be visually distinguished (reduced opacity) and MUST NOT present a clickable-hover affordance.
- **FR-004**: The drawer MUST show only the message thread and the native contact/conversation sidebar — no conversation list — reusing the same underlying conversation experience components used elsewhere in the product, without modifying those shared components.
- **FR-005**: Opening the drawer MUST make the selected conversation the active conversation for the standard reply/resolve/assign actions to work, exactly as they do in the standalone conversation view.
- **FR-006**: On opening, the drawer MUST load the conversation's data if not already available, mark its messages as read, and only then render the message thread and sidebar. While that load is in progress, the drawer MUST show the same loading/skeleton indicator the standalone conversation view already shows while loading a conversation, rather than a blank panel.
- **FR-007**: Closing the drawer (button or back navigation) MUST clear any "active conversation" state so it does not leak into other parts of the app after the drawer closes.
- **FR-008**: If the conversation fails to load (not found, no permission, etc.), the drawer MUST show an inline error message and a close action instead of the message thread and sidebar. This error MUST NOT be shown as a toast, since the drawer is already open and visible before the outcome of the load is known.
- **FR-009**: Closing the drawer MUST return the agent to the board without reloading or otherwise altering the board's own data (cards, stages).
- **FR-010**: The prior Opportunity detail side panel (metadata view with a link that navigated away to the conversation) MUST be removed. Opportunity status actions (mark won/lost/reopen) remain available only through the existing card hover actions on the board itself.

### Key Entities *(include if feature involves data)*

- **Opportunity**: Existing board entity; its `origin_conversation_id` attribute determines whether a card is clickable and which conversation the drawer opens.
- **Conversation**: Existing entity, unmodified by this feature; the drawer surfaces its existing message thread and contact/sidebar experience within the Kanban context.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Agents can go from viewing the board to actively replying in a linked conversation without ever leaving the board, in a single click.
- **SC-002**: 100% of cards without a linked conversation are visually distinguishable from clickable cards and produce no action when clicked.
- **SC-003**: After closing the drawer, the board is indistinguishable from its state before the drawer was opened, and no other part of the app is affected by the conversation having been viewed.
- **SC-004**: Agents encountering a conversation that can't be loaded always see a clear explanation and a way back to the board, never a blank or broken screen.

## Assumptions

- The existing message-thread and contact-sidebar components already used by the standalone conversation view can be reused as-is, without modification, to compose the drawer.
- The existing conversation-fetch and active-conversation state management already used by the standalone conversation view are reusable as-is; no backend or API changes are required.
- Allowing agents to link a conversation to an opportunity after the fact (for cards currently shown as non-clickable) is out of scope for this phase.
- Surfacing opportunity information inside the native contact sidebar is a separate, future idea and out of scope for this phase.
