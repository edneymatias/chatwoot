# Phase 0 Research: Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug

No `NEEDS CLARIFICATION` markers remain in the Technical Context — the following decisions were
resolved by reading the current codebase directly rather than by open research, since the feature
reuses an existing, proven pattern (`ConversationFinder`) and fixes a bug in existing code.

## Decision 1: Default status scoping mechanism

**Decision**: Add the default `status: 'open'` scoping inside
`Api::V1::Accounts::OpportunitiesController#apply_filters`
(`custom/app/controllers/api/v1/accounts/opportunities_controller.rb:65-69`), following the same
shape as `ConversationFinder#filter_by_status`
(`app/finders/conversation_finder.rb:162-166`, backed by `DEFAULT_STATUS = 'open'.freeze` at
line 4): skip the default when `params[:status] == 'all'`, apply `params[:status] ||
DEFAULT_STATUS` otherwise, and preserve suppression when the request already carries a `status`
condition inside `params[:payload]`.

**Rationale**: `ConversationFinder`'s pattern is the exact analogous default-visibility mechanism
already proven in production for Conversations; mirroring it keeps behavior and terminology
consistent across modules per the "Adhere to Established Conventions" principle, and requires no
new abstraction.

**Alternatives considered**:
- A model-level default scope on `Opportunity` (e.g. `default_scope`) — rejected because it would
  silently affect every query path (including background jobs, reports, `fetchForContact`),
  making it harder to reason about and requiring `unscoped` calls elsewhere; the controller-level
  scoping keeps the default local to the one endpoint that needs it.
- A new dedicated finder class (`OpportunityFinder`) mirroring `ConversationFinder` — rejected as
  disproportionate; `apply_filters` already centralizes all filtering logic for this controller in
  one place, and introducing a new class for one additional condition would violate "Smallest
  Production-Ready Change."

## Decision 2: `payload`-condition status detection

**Decision**: Detect an existing `status` condition inside `params[:payload]` by checking whether
any decoded filter entry's `attribute_key`/`attributeKey` equals `'status'`, using the same
`payload.each { |filter| ... }` traversal already present in `apply_filters`
(lines 77-120) — the check happens before applying the default, not as a new parsing pass.

**Rationale**: The multiSelect filter UI already produces `payload` conditions targeting
`status` (confirmed via `key == 'assignee_id' || key == 'status' || key == 'pipeline_stage_id'`
handling at line 107); reusing the same decoded structure avoids double-parsing `params[:payload]`
JSON and keeps the default-suppression check consistent with how the condition is later applied.

**Alternatives considered**: Re-parsing `params[:payload]` in a separate pre-check — rejected as
redundant JSON parsing for no behavioral benefit.

## Decision 3: Drag-and-drop layout fix approach

**Decision**: While `isCardDragging` is true (already tracked in `KanbanBoard.vue:21-29`), reserve
non-overlapping layout space for `KanbanStatusBar.vue`'s drop zones — e.g. reduce the height of the
scrollable columns container (`KanbanBoard.vue:220`, `class="flex flex-grow overflow-x-auto p-4
gap-4"`) via a bottom padding/margin sized to the status bar's height — instead of the current
`position: absolute; z-50` overlay (`KanbanStatusBar.vue:53-54`) that visually floats on top of the
columns. This removes the bounding-rect overlap between the status bar's `Draggable` lists and the
column `Draggable` lists, which both currently share SortableJS `group="kanban-cards"`
(`KanbanStatusBar.vue:58,86`; `KanbanColumn.vue:150`) — the root cause identified in the spec's
Context section.

**Rationale**: SortableJS resolves drop targets purely by bounding-rect overlap, ignoring CSS
stacking/z-index; as long as any list in the shared group visually overlaps another, a single
drop can register on both. Reserving dedicated space is the minimal fix that addresses the root
cause without touching the `Draggable` group configuration, `onStatusChanged`/`moveCard` action
logic (`KanbanBoard.vue:77-99`, `109-136`), or introducing mutual-exclusion logic between the two
event paths — all of which the spec (FR-008) explicitly calls out as unnecessary once the overlap
is gone.

**Alternatives considered**:
- Giving the status bar's `Draggable` lists a separate SortableJS `group` and manually forwarding
  won/lost drops via custom logic — rejected as more invasive (loses SortableJS's native
  drag-target resolution across zones) for no benefit over simply not overlapping.
- Adding mutual-exclusion logic in `KanbanBoard.vue` (e.g., a flag to ignore
  `cardAdded`/`cardRemoved` when a `statusChanged` fires in the same gesture, or vice versa) —
  rejected because it treats the symptom (both handlers firing) rather than the cause (the
  bounding-rect overlap), and the spec explicitly frames this as a "purely a layout fix" (FR-008).

## Decision 4: `fetchForContact` status override

**Decision**: Pass `status: 'all'` explicitly in the `fetchForContact` action's API call
(`app/javascript/dashboard/store/modules/opportunities/actions.js:68-70`,
`opportunitiesAPI.get({ contact_id: contactId })` → add `status: 'all'` to the params object).

**Rationale**: This is the one caller of the opportunities index endpoint that must NOT inherit
the new open-only default (per spec FR-004/User Story 3); explicitly opting out via the same
`status: 'all'` bypass convention used elsewhere keeps the override visible at the call site
rather than requiring a special-cased backend exception for this one consumer.

**Alternatives considered**: A backend exception keyed on `contact_id` presence — rejected because
it would silently couple the default-scoping logic to one specific frontend caller's needs,
making the controller harder to reason about; an explicit frontend `status: 'all'` param is the
same convention already used for "show me everything" and requires no controller-side special
case.
