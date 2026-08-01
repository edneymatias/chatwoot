# Feature Specification: Card Info Enrichment & Lane Ordering

**Feature Branch**: `006-card-info-and-ordering`

**Created**: 2026-07-31

**Status**: Draft

**Input**: User description: "Phase 6: Card Info Enrichment & Lane Ordering — Opportunity cards on the Kanban board should reliably show who the linked contact and assignee are, with a contact avatar and the opportunity's creation date, and cards within a lane should consistently sort newest-first by creation time, on every board load and refresh, not just as an artifact of local card creation."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agent identifies a card's contact at a glance (Priority: P1)

An agent scanning the board can see, for every card with a linked contact, that contact's avatar and name, without opening the card.

**Why this priority**: Contact identity is the primary thing an agent needs to triage a card. Today this information silently fails to render at all, so agents can't tell who a card belongs to without opening it — undermining the board as a scannable work surface.

**Independent Test**: Load the board and confirm every card with a linked contact shows that contact's avatar (or initials fallback) next to their name.

**Acceptance Scenarios**:

1. **Given** an opportunity card has a linked contact, **When** the agent views the board, **Then** the card shows the contact's avatar (or initials fallback if no avatar image) next to the contact's name.
2. **Given** an opportunity card has an assigned agent, **When** the agent views the board, **Then** the card shows that assignee's name.
3. **Given** an opportunity card has no assigned agent, **When** the agent views the board, **Then** the card shows no assignee information.

---

### User Story 2 - Agent trusts the board's newest-first ordering across reloads (Priority: P1)

An agent who refreshes the board, or loads it fresh in a new session, sees cards within each lane still ordered newest-first by creation time — the same order they'd expect from having watched cards get created locally.

**Why this priority**: Ordering that only holds up until the next refresh is misleading and erodes trust in the board; agents scanning for the newest opportunities need a stable, predictable order every time they load the page, not just right after creating a card in their own session.

**Independent Test**: Create several opportunities in a lane, reload the board from scratch, and confirm they still appear newest-first by creation time.

**Acceptance Scenarios**:

1. **Given** multiple opportunities exist in the same stage, **When** the agent loads or reloads the board, **Then** those opportunities appear ordered newest-created-first within that lane.
2. **Given** a card is moved to a different stage, **When** the board is reloaded afterward, **Then** the card's position in its new lane still reflects its original creation time relative to the other cards there, not the time of the move.

---

### User Story 3 - Agent sees how recently an opportunity was created (Priority: P3)

An agent looking at a card can see how long ago it was created, without opening it.

**Why this priority**: This is a helpful scanning aid on top of correct ordering and contact identity, but it's not required for the board to be trustworthy or usable — it's a lower-impact convenience.

**Independent Test**: Load the board and confirm every card shows a human-readable creation date/time.

**Acceptance Scenarios**:

1. **Given** an opportunity card is displayed, **When** the agent views the board, **Then** the card shows a human-readable indication of when the opportunity was created.

---

### Edge Cases

- What happens when an opportunity has no linked contact? → No contact avatar/name is shown for that card (unchanged from today's card layout otherwise).
- What happens when a contact has no avatar image? → The avatar falls back to showing the contact's initials, consistent with avatars elsewhere in the product.
- What happens when two opportunities in the same lane share the exact same creation timestamp? → Their relative order between each other is not guaranteed, but both still sort correctly relative to all other opportunities by creation time.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The board MUST provide, for every opportunity with a linked contact, that contact's name, email, and avatar image (or basis for an initials fallback).
- **FR-002**: The board MUST provide, for every opportunity with an assigned agent, that assignee's name and avatar image (or basis for an initials fallback); opportunities with no assigned agent MUST provide no assignee information.
- **FR-003**: Opportunities MUST be returned/ordered newest-created-first within each stage, both on initial board load and on every subsequent reload — not only as a side effect of locally creating a card in the current session.
- **FR-004**: Moving a card to a different stage MUST NOT change its relative creation-time ordering among the cards in the destination lane once the board is reloaded.
- **FR-005**: Every card with a linked contact MUST visibly display that contact's avatar next to the contact's name.
- **FR-006**: Every card MUST visibly display the opportunity's creation date, in a human-readable/relative format consistent with similar timestamps shown elsewhere in the product.
- **FR-007**: No additional "open conversation" link or element is added to the card; the existing whole-card click behavior remains the sole way to open the linked conversation.

### Key Entities *(include if feature involves data)*

- **Opportunity**: Existing board entity; gains reliably-available contact and assignee identity information and a defined, stable creation-time ordering within its stage.
- **Contact**: Existing entity; its name, email, and avatar are surfaced on the card it's linked to.
- **Assignee (Agent)**: Existing entity; its name and avatar are surfaced on the card it's linked to, when present.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For 100% of cards with a linked contact, agents can identify the contact by name and avatar without opening the card.
- **SC-002**: Card order within a lane matches newest-created-first by creation time on every board load, including a fresh page refresh, 100% of the time.
- **SC-003**: Moving a card to another stage never changes its relative position by creation time once the board is reloaded.
- **SC-004**: For every card, agents can tell how recently the opportunity was created without opening it.

## Assumptions

- Contact and assignee avatar images follow the same URL/fallback pattern already used for avatars elsewhere in the product; no new avatar-hosting mechanism is introduced.
- No dedicated backend serializer class is introduced for this data — the existing lightweight approach used for other opportunity fields is extended, since the added payload is small.
- Assignee avatars are not required on the card in this phase; only the assignee's name display is guaranteed (unchanged from today), in addition to the new contact avatar.
- Linking a conversation directly from the card (beyond the existing whole-card click) remains out of scope, as established in the prior phase.
