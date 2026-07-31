# Feature Specification: Frontend Board — Kanban UI, Vuex Store, Settings

**Feature Branch**: `003-kanban-frontend-board`

**Created**: 2026-07-30

**Status**: Draft

**Input**: User description: "docs/kanban/03-frontend-board/spec3.md — Phase 3: Frontend Board — Kanban UI, Vuex Store, Settings"

**Phase**: 3 of 4 (Frontend Board). Depends on Phase 1 (Opportunity/PipelineStage API endpoints) and Phase 2 (`create_opportunity` automation action, for the Automation Rules dropdown). Feeds Phase 4 (realtime wiring and navigation/route registration plug into the store and components built here).

## Clarifications

### Session 2026-07-30

- Q: When an administrator tries to delete a pipeline stage that still has opportunities in it, what should happen? → A: Deletion is blocked entirely if the stage has any opportunities (must be emptied first via manual moves).
- Q: Should agents be able to manually mark an opportunity as "won" or "lost" from the board UI in this phase? → A: Yes — add a simple "Mark as Won / Mark as Lost / Reopen" action on the card or detail view.
- Q: When a column has more opportunities than are currently loaded, how should the agent trigger loading the next page? → A: Infinite scroll — next page loads automatically as the agent scrolls near the bottom of the column.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agent views and moves opportunities across pipeline stages (Priority: P1)

An agent working the sales/support pipeline opens the Kanban board and sees one column per pipeline stage, with opportunity cards in each column. They drag a card from one column to another to reflect a status change (e.g. moving a deal from "Contacted" to "Negotiating").

**Why this priority**: This is the core value of the board — without visualized columns and working drag-and-drop, there is no Kanban experience at all, just a data model with no usable UI.

**Independent Test**: Load the board with pipeline stages and existing opportunities seeded; confirm columns render in the correct order and drag a card between two columns; confirm the card moves immediately in the UI and the underlying opportunity's stage is updated via the API.

**Acceptance Scenarios**:

1. **Given** pipeline stages exist ordered by position, **When** the board loads, **Then** one column renders per stage, in that position order, each showing its own opportunities.
2. **Given** a card in one column, **When** the agent drags it into a different column, **Then** the card appears in the destination column immediately and the API request to update the opportunity's stage succeeds.
3. **Given** a card is dragged to a new column, **When** the API update request fails, **Then** the card reverts to its original column and the agent is shown that the move did not persist.
4. **Given** a column has more opportunities than fit on one page, **When** the agent scrolls near the bottom of that column, **Then** the next page loads automatically for that column without affecting other columns.

---

### User Story 2 - Agent creates a new opportunity manually (Priority: P2)

An agent wants to track a new opportunity that didn't originate from an automation rule. They open a creation flow, pick a contact, a pipeline stage, and a title, and the new opportunity appears on the board right away.

**Why this priority**: Manual creation is the fallback path whenever automation doesn't cover a case; without it, agents have no way to get new opportunities into the pipeline outside of automation rules.

**Independent Test**: Open the manual-creation flow, search for and select an existing contact, pick a stage and enter a title, submit, and confirm the new card appears in the chosen column without a page reload.

**Acceptance Scenarios**:

1. **Given** the manual-creation flow is open, **When** the agent searches for a contact by name, **Then** matching existing contacts appear for selection.
2. **Given** a contact, pipeline stage, and title have been chosen, **When** the agent submits, **Then** a new opportunity is created and immediately visible as a card in the selected column.
3. **Given** the flow was launched from within an existing conversation, **When** the opportunity is created, **Then** it is linked to that conversation as its origin.
4. **Given** the flow was launched independently of any conversation, **When** the opportunity is created, **Then** it has no origin conversation and this is not treated as an error.

---

### User Story 3 - Agent inspects an opportunity's details, sets its status, and reaches its linked conversation (Priority: P3)

An agent wants to know more about a card at a glance — its current status and, if it came from a conversation, a way to jump back to that conversation. From the same place, the agent can mark the opportunity as won or lost once its outcome is known, or reopen it if that turns out to be premature.

**Why this priority**: Cards alone don't convey enough context for an agent to act; this closes the loop back to the conversation that likely drives the opportunity's next action, and gives agents the only way to actually produce the `won`/`lost` states the board is meant to visualize.

**Independent Test**: Click a card that has an origin conversation and confirm the detail view shows a working link/route to that conversation; mark the opportunity as won and confirm the card immediately shows the won badge; click a card without an origin conversation and confirm no broken link is shown.

**Acceptance Scenarios**:

1. **Given** a card with status `won` or `lost`, **When** it renders in any column, **Then** it shows a visually distinct badge for that status regardless of which column it's currently in.
2. **Given** a card with an origin conversation, **When** the agent clicks the card, **Then** a detail view opens showing a link to that conversation.
3. **Given** a card with no origin conversation, **When** the agent clicks the card, **Then** the detail view opens without showing a conversation link.
4. **Given** an open opportunity, **When** the agent chooses "Mark as Won" or "Mark as Lost" from the card or its detail view, **Then** the opportunity's status updates immediately and the corresponding badge appears, without changing its pipeline stage.
5. **Given** an opportunity marked `won` or `lost`, **When** the agent chooses "Reopen," **Then** its status returns to `open` and the won/lost badge is removed.

---

### User Story 4 - Administrator manages pipeline stages (Priority: P4)

An administrator wants to define and adjust the columns of the board itself — adding a new stage, renaming one, removing one that's no longer used, and reordering them to match the team's actual process.

**Why this priority**: The board's columns are only useful if administrators can adapt them to the team's process; this is lower priority than the board's core viewing/moving/creating behavior because a reasonable default set of stages can ship first.

**Independent Test**: As an administrator, open the pipeline stages settings screen, create a new stage, rename an existing one, reorder two stages via drag, delete a stage, then refresh the page and confirm all changes persisted.

**Acceptance Scenarios**:

1. **Given** the settings screen is open, **When** the administrator creates a new stage, **Then** it appears in the stage list and, after refresh, on the Kanban board in its saved position.
2. **Given** an existing stage, **When** the administrator renames or deletes it, **Then** the change persists after a page refresh.
3. **Given** two or more stages, **When** the administrator drags one to a new position, **Then** the new order persists after a page refresh.
4. **Given** a non-administrator user, **When** they attempt to access this settings screen, **Then** access is denied.

---

### User Story 5 - Administrator configures the "Create Opportunity" automation action (Priority: P5)

An administrator building an Automation Rule wants to pick the new "Create Opportunity" action and choose which pipeline stage it should create opportunities in, using the same rule-building screen already used for other actions.

**Why this priority**: This exposes Phase 2's backend action to end users; it's the lowest priority here because the rule-building screen and its other actions already exist and work — this user story only adds one more entry and its parameter form.

**Independent Test**: Open the Automation Rules action picker, select "Create Opportunity," confirm a pipeline-stage selector appears populated with real stages, save the rule, and confirm the selection persists on reopening.

**Acceptance Scenarios**:

1. **Given** the action picker is open, **When** the administrator views the list of available actions, **Then** "Create Opportunity" appears alongside existing actions.
2. **Given** "Create Opportunity" is selected, **When** its parameter form renders, **Then** it shows a pipeline-stage selector populated from the real list of pipeline stages.
3. **Given** a pipeline stage has been selected for the action, **When** the rule is saved and reopened, **Then** the previously selected stage is still shown.

---

### Edge Cases

- A column has zero opportunities — it renders as an empty column, not an error state or missing column.
- A drag-and-drop move is dropped back into its original column — no API call or visible change should occur that isn't a no-op.
- An administrator attempts to delete a pipeline stage that still contains opportunities — deletion MUST be blocked and the administrator MUST see a clear message that the stage must be emptied (opportunities moved to other stages) before it can be deleted.
- The manual-creation flow's contact search returns no matches — the agent sees a clear "no results" state rather than an empty, ambiguous list.
- Dark mode is toggled — columns, cards, and status badges all remain legible with no leftover light-mode-only styling.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST maintain the board's opportunity data in a normalized client-side structure (cards indexed by id, per-stage ordered lists of card ids, and per-stage pagination state) so that updating one card or moving one card between stages does not require iterating over or rebuilding the full set of cards.
- **FR-002**: The system MUST provide a way to fetch, for a given pipeline stage, the full list of opportunity cards currently assigned to it, ordered for display, without scanning across all stages' cards to produce that list.
- **FR-003**: The system MUST render one column per pipeline stage, ordered by each stage's configured position, with each column showing only the opportunity cards assigned to it.
- **FR-004**: The system MUST support paginated, per-column loading of opportunities via infinite scroll: as the agent scrolls near the bottom of a column, the next page for that column loads automatically, without affecting other columns' loaded data.
- **FR-005**: The system MUST support moving an opportunity card from one column to another via drag-and-drop; the move MUST be reflected in the UI immediately and confirmed by an update to the opportunity's stage on the server; if the server update fails, the card MUST revert to its original column.
- **FR-006**: Each opportunity card MUST display its title, associated contact, assignee, and a status indicator distinguishing `open`, `won`, and `lost` states, with `won`/`lost` shown with a distinct visual treatment regardless of the column the card currently occupies.
- **FR-007**: Clicking an opportunity card MUST open a detail view showing the opportunity's origin conversation, if one exists, with a way to navigate to that conversation; if no origin conversation exists, the detail view MUST NOT show a broken or empty conversation link.
- **FR-007a**: The card or its detail view MUST provide actions to mark an `open` opportunity as `won` or `lost`, and to reopen a `won`/`lost` opportunity back to `open`; changing status MUST update the card's badge immediately and MUST NOT change the opportunity's pipeline stage.
- **FR-008**: The system MUST provide a manual-creation flow allowing an agent to create an opportunity by selecting an existing contact (via search), a pipeline stage, and a title; the created opportunity MUST appear on the board immediately without requiring a page reload.
- **FR-009**: The manual-creation flow MUST allow an optional link to an origin conversation, settable only when the flow is launched from within an existing conversation's context; opportunities created without this context MUST have no origin conversation and this MUST NOT be treated as an error.
- **FR-010**: The system MUST provide an administrator-only settings screen for managing pipeline stages: creating, renaming, deleting, and reordering stages (via drag), displayed in position order, with all changes persisted such that they survive a page refresh. Deleting a stage that still contains opportunities MUST be blocked, with a clear message that the stage must be emptied first.
- **FR-011**: Access to the pipeline stages settings screen MUST be restricted to administrators and MUST be hidden or blocked entirely when opportunities functionality is not enabled for the account.
- **FR-012**: The existing Automation Rules action picker MUST include the "Create Opportunity" action (registered server-side in Phase 2) in its list of selectable actions, using the same list mechanism as existing actions, without altering the behavior of any pre-existing action entry.
- **FR-013**: When "Create Opportunity" is selected in the Automation Rules action picker, its parameter form MUST require a pipeline stage, presented as a selection populated from the real list of pipeline stages, following the same presentation pattern already used by comparable existing action parameters (e.g. the agent/team selectors used by other actions).
- **FR-014**: All user-facing text introduced by this phase MUST be sourced from the application's translation strings rather than hardcoded in components.
- **FR-015**: All visual styling introduced by this phase MUST remain legible and correctly themed in both light and dark display modes.

### Key Entities

- **Pipeline Stage (client-side)**: A named, ordered column on the board; has a position determining display order and a set of opportunities currently assigned to it.
- **Opportunity (client-side)**: A card on the board; has a title, an assigned contact, an assignee, a status (`open`/`won`/`lost`), a current pipeline stage, and an optional origin conversation.
- **Board pagination state**: Tracks, per pipeline stage, how much of that stage's opportunity list has been loaded and whether more remains.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An agent can view the full pipeline and locate any given opportunity's current stage within seconds of opening the board, with no more than one loading interruption per column when paging further opportunities.
- **SC-002**: 100% of drag-and-drop moves between columns either persist correctly on the server or are visibly reverted in the UI if the server update fails — no move ever leaves the UI and the underlying data in a mismatched state.
- **SC-003**: An agent can create a new opportunity and see it appear on the board in under 10 seconds from opening the creation flow, without needing to refresh the page.
- **SC-004**: An administrator can create, rename, delete, and reorder pipeline stages, with 100% of those changes surviving a page refresh.
- **SC-005**: An administrator configuring an Automation Rule can select "Create Opportunity" and its target pipeline stage using the same interaction pattern as configuring any other existing action, with zero additional training or documentation required beyond what's needed for existing actions.
- **SC-006**: 100% of user-facing text and visual elements introduced by this phase render correctly and legibly in both light and dark mode.

## Assumptions

- Wiring this board, its settings screen, and the manual-creation entry point into navigation menus, `dashboard.routes.js`, `settings.routes.js`, and the global Vuex store registration is out of scope for this phase and is handled by Phase 4; this phase delivers fully built but not-yet-registered components, store module, and screens.
- Realtime updates via ActionCable are out of scope for this phase; the store here only reacts to its own API calls, not to pushes from other users' concurrent actions. A user will not see another user's move reflected on their own board without a manual refresh until Phase 4 adds realtime wiring.
- The conversation-sidebar "Create Opportunity" action button that launches the manual-creation flow from within a conversation is a Phase 4 responsibility; this phase only builds the modal/flow and the store action it calls.
- The `opportunities` feature flag gating access (established in Phase 1) is available and correctly reflects whether the account has this functionality enabled.
- A single, implicit pipeline per account remains in effect (per Phase 1); this phase does not introduce multi-pipeline selection.
