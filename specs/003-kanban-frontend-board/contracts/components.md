# Contract: Component Props/Events & Automation Action Picker Extension

## `KanbanBoard.vue`

- Props: none required (reads `pipelineStages/stagesSortedByPosition` and dispatches `opportunities/fetchForStage` per column itself), OR optionally accepts `originConversationId: Number | null` to pass through to the create modal when embedded in a conversation context (kept as a prop so Phase 4 can wire it without touching this component's internals).
- Emits: `card-click(opportunityId)` — bubbled up from `KanbanCard`, for Phase 4 to wire into a route push if desired; this phase's own `OpportunityDetailView` also listens to this internally when the board owns the detail view state.

## `KanbanColumn.vue`

- Props: `stage: PipelineStage` (required).
- Behavior: mounts → dispatches `opportunities/fetchForStage({ stageId: stage.id })`; on near-bottom scroll → dispatches `opportunities/fetchForStage({ stageId: stage.id, page: nextPage })` if `hasMoreForStage(stage.id)`.
- Renders a `Draggable` bound with `:model-value="cardsForStage(stage.id)"` and `group="kanban-cards"` (research.md §1). vuedraggable fires `@change` **per column, independently** — the source column receives `{ removed }`, the destination column receives `{ added }` (each with `element`/`newIndex`/`oldIndex`, no cross-column pairing). `KanbanColumn` therefore only emits its own half up to `KanbanBoard`: `card-removed({ id, fromStageId })` on `removed`, `card-added({ id, toStageId, toIndex })` on `added`. `KanbanBoard` correlates the two (same drag = same `id`, arriving in the same tick) into one `opportunities/moveCard({ id, fromStageId, toStageId, toIndex })` dispatch — a drop back into the same column produces only a `moved` event (no `added`/`removed`) and is a no-op per the spec's Edge Cases. When `cardsForStage(stage.id)` is empty, `Draggable` renders zero cards with no special-case markup — the column's empty state is just the default empty-array render, no dedicated "empty" branch needed.

## `KanbanCard.vue`

- Props: `opportunity: Opportunity` (required).
- Displays: title, contact, assignee, status badge (`open`/`won`/`lost` — FR-006).
- Emits: `click` (opens detail view, FR-007), and exposes Mark as Won/Lost/Reopen as a quick action per FR-007a (emits `status-changed({ id, status })`, parent dispatches `opportunities/setStatus`).

## `OpportunityCreateModal.vue`

- Props: `originConversationId: Number | null` (default `null` — FR-009).
- Emits: `created(opportunity)` on success, `close`.
- Internally uses contact search (research.md §3) and `pipelineStages/stagesSortedByPosition` for the stage select; dispatches `opportunities/create`.
- Empty state: if the contact search returns zero matches, the contact field shows a "no results" message in place of the option list (no dispatch, no error) — spec.md Edge Cases.

## `OpportunityDetailView.vue`

- Props: `opportunityId: Number` (required).
- Shows: full card info, origin conversation link if `originConversationId` is present (FR-007), and the Mark as Won/Lost/Reopen action (FR-007a) — same `status-changed` emit contract as `KanbanCard`.

## Automation Rules action-picker extension (no new component)

- `routes/dashboard/settings/automation/constants.js` → `AUTOMATION_ACTION_TYPES` gains:
  ```js
  { key: 'create_opportunity', label: 'CREATE_OPPORTUNITY', inputType: 'search_select' }
  ```
- `composables/useAutomationValues.js` → `getActionDropdownValues(type)` gains a `create_opportunity` case returning `pipelineStages/stagesSortedByPosition` mapped to `{ id, name }` option objects (same shape already consumed by `SingleSelect` for `assign_agent`/`assign_team`).
- No edit to `AutomationActionInput.vue` is required for the stage-only picker (FR-013's minimum). If an optional title-template text field is added in the same form during task-level implementation, one additive `v-else-if` branch/new `inputType` may be introduced there — tracked as an implementation-time decision, not a contract change, since it doesn't alter `AUTOMATION_ACTION_TYPES`' external shape for any existing action.
