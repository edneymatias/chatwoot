# Feature Specification: Unified Card Click & History Links

**Feature Branch**: `043-card-click-history-links`

**Created**: 2026-09-02

**Status**: Draft

**Input**: User description: "Phase 83: Unified Kanban Card Click & Conversation Links in History — clicking a Kanban card (or list-view row) should always open something useful (the active conversation if one exists, otherwise the opportunity's history/audit panel), and conversation-related entries in that history panel should become clickable links that jump straight to the referenced conversation, regardless of its current status or whether it's still linked to the opportunity."

## Clarifications

### Session 2026-09-02

- Q: What should happen if a user clicks a history link for a conversation that no longer exists or fails to load? → A: Link is disabled upfront — when a conversation-related history entry's referenced conversation can't be resolved, it renders as plain, non-clickable text instead of a link, so there's nothing to click that could fail.
- Q: Should opening a conversation via a card click or a history link bypass Chatwoot's existing conversation access/permission policies? → A: No — access MUST respect Chatwoot's existing conversation access/permission policies; a user without permission to view a given conversation must not be able to reach it through this feature. This extends the same "disabled upfront" treatment: an entry the current user isn't authorized to view is also rendered as plain, non-clickable text.
- Q: Should the history panel show a conversation's status before the user clicks into it? → A: Yes — each conversation-related history entry MUST display the conversation's current status (e.g., open, pending, resolved) next to the link, so the user knows the state in advance.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Card click always opens something (Priority: P1)

Today, clicking a Kanban card (or the equivalent row in list view) only does something when the
opportunity has an active conversation attached — it opens that conversation. When there's no
active conversation, clicking the card does nothing at all, and the card is visually marked as
inert (grayed out, dashed border, non-pointer cursor). This makes opportunities without an active
conversation feel broken or unclickable, even though they still have useful information (their
history/audit trail) worth viewing.

With this change, clicking any card or row always opens something: the active conversation if one
exists, or the opportunity's history/audit panel directly if it doesn't. Every card looks and
behaves the same — fully clickable — regardless of whether it currently has a conversation
attached.

**Why this priority**: This is the core interaction fix. It removes a dead-end in the primary way
users interact with opportunities and makes every card equally useful to click, which is the most
visible and highest-value part of this feature.

**Independent Test**: Can be fully tested by clicking a card/row with an active conversation
(verify it opens that conversation) and a card/row without one (verify it opens the history panel
instead of doing nothing) — delivers value on its own even before Part 2 (history links) exists.

**Acceptance Scenarios**:

1. **Given** an opportunity card with an active conversation, **When** the user clicks the card,
   **Then** the drawer opens showing that conversation, exactly as it does today.
2. **Given** an opportunity card with no active conversation, **When** the user clicks the card,
   **Then** the drawer opens showing the opportunity's history/activity panel, instead of nothing
   happening.
3. **Given** an opportunity card with no active conversation, **When** the user clicks the
   "start/link conversation" ("+") control on the card, **Then** only the start/link action fires
   — the card's own navigation does not also trigger.
4. **Given** an opportunity row in list view (not the Kanban board), **When** the user clicks the
   row with or without an active conversation, **Then** the same behavior applies as for a Kanban
   card (scenarios 1–2).
5. **Given** an opportunity card with no active conversation, **When** the user looks at the card,
   **Then** it appears visually identical to a card with an active conversation — no grayed-out,
   dashed, or non-clickable styling.

---

### User Story 2 - Conversation history entries link to their conversation (Priority: P2)

The opportunity's history/audit panel already logs every conversation-related event (a
conversation was opened, transferred in, transferred out, or detached from the opportunity), but
today those entries are plain, unclickable text. A user reviewing the history has no way to jump
to the conversation being referenced — they'd have to go find it some other way, if it's even
still easy to find (e.g., if it was later transferred away or detached).

With this change, each of those four history entry types renders as a clickable link. Clicking one
takes the user straight to that specific conversation, inside the same drawer, switching it to the
conversation view.

**Why this priority**: This closes the loop opened by Part 1 — once every card reliably opens the
history panel, that panel becomes a much more valuable place to also let users jump into any
conversation it references, not just the currently active one.

**Independent Test**: Can be fully tested by opening an opportunity's history panel and clicking a
conversation-related entry, verifying it switches to showing that specific conversation — delivers
value on its own as a navigation shortcut, independent of Part 1's card-click change.

**Acceptance Scenarios**:

1. **Given** the history panel is open and shows a "conversation opened" entry, **When** the user
   clicks it, **Then** the drawer switches to showing that conversation.
2. **Given** a history entry referencing a conversation that has since been resolved/closed,
   **When** the user clicks it, **Then** that conversation still opens successfully.
3. **Given** a "conversation detached" entry, referencing a conversation no longer linked to this
   opportunity, **When** the user clicks it, **Then** that conversation still opens, and the
   opportunity context shown alongside it remains the opportunity whose history the user was
   viewing (not reset or lost).
4. **Given** a history entry for a non-conversation event (opportunity created, stage changed,
   won/lost/reopened), **When** the user views it, **Then** it remains plain text, unaffected by
   this change.
5. **Given** a conversation-related history entry whose referenced conversation can no longer be
   resolved (e.g., it no longer exists), **When** the user views the entry, **Then** it renders as
   plain, non-clickable text instead of a link.
6. **Given** a conversation-related history entry whose referenced conversation the current user
   does not have permission to view, **When** the user views the entry, **Then** it renders as
   plain, non-clickable text instead of a link — the same treatment as an unresolvable conversation.
7. **Given** the history panel is open, **When** the user views a conversation-related entry whose
   conversation is accessible to them, **Then** the entry shows that conversation's current status
   (e.g., open, pending, resolved) next to the link, before they click it.

---

### Edge Cases

- Clicking the card/row's "+"/start-conversation control never also triggers the card's own
  navigation (covered in User Story 1, Scenario 3).
- Following a history link for a conversation that is resolved, closed, or no longer linked to the
  opportunity still succeeds in opening it (User Story 2, Scenarios 2–3).
- Rapidly clicking a card and then a "+" control (or vice versa) does not leave the drawer in an
  inconsistent state — the last user action determines what's shown.
- A conversation-related history entry whose referenced conversation can't be resolved (e.g., it no
  longer exists) renders as plain, non-clickable text instead of a link (User Story 2, Scenario 5).
- A conversation-related history entry whose referenced conversation the current user lacks
  permission to view renders as plain, non-clickable text instead of a link, and shows no status
  badge (User Story 2, Scenario 6).
- Opening a conversation the current user isn't authorized to view — via a card/row click or a
  history link — is blocked/handled the same way unauthorized conversation access is handled
  elsewhere in the product; this feature does not introduce a new or different access rule.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Clicking a Kanban card or list-view row for an opportunity with an active
  conversation MUST open that conversation, as it does today (no regression).
- **FR-002**: Clicking a Kanban card or list-view row for an opportunity with no active
  conversation MUST open the opportunity's history/activity view, instead of taking no action.
- **FR-003**: Cards and rows for opportunities without an active conversation MUST be presented
  with the same clickable visual treatment as those with one — no distinct
  grayed-out/dashed/non-interactive styling.
- **FR-004**: The "start/link a conversation" control on a card MUST remain available and
  functional independent of the card's own click behavior, and clicking it MUST NOT also trigger
  the card's navigation.
- **FR-005**: Each conversation-related history entry (conversation opened, transferred in,
  transferred out, or detached) MUST be rendered as a clickable link.
- **FR-006**: Clicking a conversation-related history link MUST open that specific conversation,
  regardless of its current status (open, resolved/closed) or whether it is still linked to the
  opportunity.
- **FR-006a**: When a conversation-related history entry's referenced conversation cannot be
  resolved (e.g., it no longer exists) or the current user does not have permission to view it, the
  entry MUST render as plain, non-clickable text instead of a link.
- **FR-007**: The opportunity context associated with the history/conversation view being shown
  MUST remain correct and unchanged after the user follows a history link.
- **FR-008**: History entries for non-conversation events (opportunity created, stage changed,
  won, lost, reopened) MUST remain unaffected by this change.
- **FR-009**: The "+"/start-conversation control MUST remain the only entry point for starting or
  linking a new conversation from the board — this feature does not add another one.
- **FR-010**: Any conversation opened through this feature — whether via a card/row click or a
  history-panel link — MUST respect Chatwoot's existing conversation access/permission policies; a
  user without permission to view a given conversation MUST NOT gain access to it through this
  feature.
- **FR-011**: Each conversation-related history entry whose conversation is accessible to the
  current user MUST display that conversation's current status (e.g., open, pending, resolved)
  alongside the link, so the user can see the state before clicking.

### Key Entities *(include if feature involves data)*

- **Opportunity**: A sales/deal record shown as a card (Kanban) or row (list view); may or may not
  currently have an active conversation attached.
- **Conversation**: A support/chat conversation that can be linked to an opportunity, currently
  active or not, independently open/pending/resolved, and subject to Chatwoot's existing
  access/permission rules governing who may view it.
- **History/Activity Entry**: A timestamped record of something that happened to an opportunity
  (conversation opened/transferred/detached, stage changes, won/lost/reopened, etc.), shown in the
  opportunity's audit trail.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of clicks on an opportunity card or list-view row result in the drawer showing
  either the active conversation or the history panel — zero no-op clicks.
- **SC-002**: Users can reach any conversation referenced in an opportunity's history in a single
  click from the history panel, regardless of that conversation's current status.
- **SC-003**: Opportunities with and without an active conversation are visually indistinguishable
  in terms of clickability — no user-reported confusion about which cards are "clickable."
- **SC-004**: Following a history link never changes or loses the opportunity context shown in the
  drawer — 100% of history-link navigations preserve the correct opportunity.
- **SC-005**: Users can identify a referenced conversation's current status directly from the
  history panel, without opening it, for 100% of conversation-related entries whose conversation is
  accessible to them.
- **SC-006**: No user is ever able to view a conversation through this feature that they could not
  already view through existing conversation access rules — zero unauthorized-access incidents
  attributable to this feature.

## Assumptions

- The card-click and basic history-link navigation (User Story 1, and User Story 2 scenarios
  1–4) need no backend/data changes — the underlying data (active conversation id, and each
  history entry's referenced conversation id) already exists and is already being persisted.
  Whether displaying each entry's current status and pre-filtering entries by access permission
  (FR-010, FR-011) require new or extended data exposure is an open question for planning, not
  assumed either way here.
- The "+"/start-conversation control remains the sole entry point for starting or linking a new
  conversation from the board; this feature does not introduce another one.
- Introducing a separate "related conversations" list/section outside the existing history panel
  is out of scope — making the existing history entries clickable is sufficient for this phase.
- Existing automated test coverage for the affected views will be extended to cover the new
  no-active-conversation click path and the history-link click path, alongside the existing
  covered paths.
- No new access-control logic is introduced by this feature — it reuses Chatwoot's existing
  conversation access/permission checks rather than defining new ones.
- The status shown next to a history entry reflects the conversation's current status at the time
  the history panel is viewed, not its status at the time the historical event occurred.
