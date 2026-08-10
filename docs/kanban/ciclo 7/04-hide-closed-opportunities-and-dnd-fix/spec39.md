# Phase 39: Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug

**Depends on**: Phase 35 (unified search/sort/filtering for Kanban and List views), whose
`status` filter attribute this phase relies on unchanged; `KanbanStatusBar.vue` and
`KanbanBoard.vue` from the original Kanban board implementation.

## Context

Two related but distinct problems, addressed together because both were raised in the same
request and both touch the Kanban board:

1. **Display default**: today, both the Kanban board and the List view show opportunities of
   every status (open, won, lost) with no default scoping — the backend applies no default
   `status` filter, and the frontend sends none. Once an opportunity is concluded (won or lost),
   it should disappear from both views by default, remaining discoverable only by proactively
   using the existing filter system (no visual indicator needed that a default is applied). This
   mirrors the Conversations inbox's existing behavior: `ConversationFinder` already defaults to
   `status: 'open'` when no status param is present, hiding resolved/snoozed conversations from
   the default inbox view.
2. **Drag-and-drop usability bug**: `KanbanStatusBar.vue`'s won/lost drop zones are rendered as an
   absolutely-positioned overlay (`position: absolute`, `z-50`) floating on top of the pipeline
   stage columns, rather than occupying dedicated, non-overlapping layout space. Because its
   `Draggable` lists share the same SortableJS `group="kanban-cards"` as every `KanbanColumn.vue`
   lane, and SortableJS resolves drop targets by bounding-rect overlap (ignoring CSS
   stacking/z-index), a card dropped visually on the win/loss zone can register on **both** lists
   in a single drag gesture — firing `statusChanged` (correct) and `cardAdded`/`cardRemoved`
   (incorrect) independently, with no mutual exclusion between the two code paths in
   `KanbanBoard.vue`. The result: dropping a card to mark it won/lost sometimes also silently
   changes its `pipeline_stage_id` to whatever stage lane happens to be positioned underneath the
   drop zone, corrupting the stage the opportunity is recorded as having been won/lost at.

## Backend — default status scope

- **FR-001**: `Api::V1::Accounts::OpportunitiesController#index` defaults to `status: 'open'` when
  no status condition is present in the request — neither `params[:status]` nor a `status`
  condition inside the `payload` filter-conditions array — mirroring `ConversationFinder`'s
  `DEFAULT_STATUS` pattern (`app/finders/conversation_finder.rb:78-89,162-166`).
- **FR-002**: `status: 'all'` (top-level param) bypasses the default entirely, returning
  opportunities of every status — same convention as `ConversationFinder`'s `status=all` bypass.
- **FR-003**: Any explicit status filter — top-level `params[:status]`, or a `payload` condition
  targeting `status` (e.g. via the existing multiSelect filter UI selecting `won`/`lost`/any
  combination) — overrides the default; the existing `apply_filters` logic already applies these,
  it only needs to also suppress the new default when either is present.
- **FR-004**: `opportunities/fetchForContact` (`app/javascript/dashboard/store/modules/
  opportunities/actions.js:68-70`, backing `ContactOpportunities.vue`'s contact-profile panel) is
  updated to explicitly send `status: 'all'`. A contact's opportunity history panel must continue
  showing open, won, and lost deals for full context — deliberately excluded from the new default,
  the same way the Conversations panel on a contact's profile shows their full conversation
  history regardless of status.

## Frontend — Kanban & List views

- **FR-005**: No changes needed to `KanbanColumn.vue`'s `fetchForStage` call or
  `OpportunityListView.vue`'s `fetchAll` call — both already omit a status param on their default
  queries, so they inherit the new backend default (open-only) automatically.
- **FR-006**: No changes needed to the filter UI (`OpportunitiesFilter.vue`,
  `opportunityProvider.js`) — `status` is already a working multiSelect filter attribute with
  options `['open', 'won', 'lost']`; selecting `won`/`lost` there already produces a `payload`
  condition that overrides the backend default per FR-003. No visual indicator is added to signal
  that a default status scope is active — finding closed opportunities is a fully proactive action
  via the existing filter panel.

## Drag-and-drop fix

- **FR-007**: While a card drag is active (`isCardDragging`, already tracked in
  `KanbanBoard.vue`), reserve dedicated layout space for `KanbanStatusBar.vue`'s won/lost drop
  zones instead of floating them as an absolutely-positioned overlay on top of the columns — e.g.
  shrink/pad the columns' scroll container so its bounding rect no longer extends underneath the
  status bar while it's visible. This removes the bounding-rect overlap between the status bar's
  `Draggable` lists and the column `Draggable` lists (both currently `group="kanban-cards"`),
  which is the root cause of a single drop registering on both lists simultaneously.
- **FR-008**: Once the layout no longer overlaps, dropping a card on the won/lost zone changes
  only `status` via the existing `opportunities/setStatus` action — `pipeline_stage_id` is left
  untouched, so the stage at which a deal was won/lost stays accurate. No change needed to
  `setStatus`/`moveCard` action logic themselves; this is purely a layout fix that prevents the
  ambiguous double-drop from being registered in the first place.

## Testing / specs affected

- `spec/requests/api/v1/accounts/opportunities_controller_spec.rb:24-54` — the existing
  status-less `GET index` test needs a companion case asserting won/lost opportunities are
  excluded by default and included when `status=all` (or an explicit status filter) is passed.
- No existing frontend spec asserts on cross-status fetches without a status param, so none should
  break as a direct result of FR-001/FR-002, aside from `fetchForContact` needing its `status:
  'all'` param reflected in any spec that asserts on its request payload.
- The `KanbanStatusBar`/`KanbanColumn` drag interaction has no existing spec coverage; not adding
  one is acceptable per project convention (specs only written when explicitly requested), but
  worth flagging as a candidate during the implementation-plan phase.

## Out of scope

- Any change to the `Opportunity` model's `status` enum, or to the funnel/attribute report
  builders (`Reports::OpportunityFunnelBuilder`, `Reports::OpportunityAttributeSummaryBuilder`) —
  both already query `account.opportunities` directly with their own explicit status scopes and
  never call `OpportunitiesController#index`, so they're unaffected by this phase.
- Persisting the user's applied filters (status or otherwise) across page reloads/navigation —
  filters are not persisted anywhere in the Opportunities module today, and this phase does not
  introduce that.
- Auto-assigning a dedicated "closed" pipeline stage when an opportunity is marked won/lost — the
  stage is left exactly as it was before the drag (FR-008).
