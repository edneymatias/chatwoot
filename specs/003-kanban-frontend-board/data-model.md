# Phase 1 Data Model: Frontend Board — Kanban UI, Vuex Store, Settings

This describes the **client-side** (Vuex) representation of entities already defined server-side in Phase 1 (`PipelineStage`, `Opportunity` models). No new server-side schema is introduced by this phase.

## Pipeline Stage (client-side)

Normalized in `store/modules/pipelineStages/`.

| Field | Type | Notes |
|---|---|---|
| `id` | Number | Server-assigned id, primary key in `byId` |
| `name` | String | Display label / column header |
| `position` | Number | Determines column display order (ascending) |
| `accountId` | Number | Scoping field, not displayed |

**State shape**:
```
state.pipelineStages = {
  byId: { [id]: PipelineStage },
  allIds: [id, ...],       // kept sorted by position via SET_STAGE_POSITIONS-style mutation
  uiFlags: { isFetching, isCreating, isUpdating, isDeleting },
}
```

**Derived (getter)**: `stagesSortedByPosition` — maps `allIds` through `byId`, sorted by `position`.

**Validation rules** (client-side, mirrors FR-010):
- `name` required, non-empty.
- Delete is blocked client-side by disabling the delete action (and shown as a clear message) when the stage's `idsByStage[stageId]` in the opportunities module is non-empty; the authoritative block still happens via the Phase 1 API (409/422 response), which the UI surfaces if the client-side check is stale.

## Opportunity (client-side)

Normalized in `store/modules/opportunities/`.

| Field | Type | Notes |
|---|---|---|
| `id` | Number | Server-assigned id, primary key in `byId` |
| `title` | String | Card title |
| `contact` | Object `{ id, name, ... }` | Denormalized snapshot of the associated contact for card display |
| `assignee` | Object `{ id, name, ... }` \| `null` | Denormalized snapshot of the assigned agent, if any |
| `status` | Enum `open` \| `won` \| `lost` | Drives badge display (FR-006, FR-007a) |
| `pipelineStageId` | Number | Foreign key into `pipelineStages.byId`; determines which column the card renders in |
| `originConversationId` | Number \| `null` | Optional; drives the detail view's conversation link (FR-007) |
| `accountId` | Number | Scoping field, not displayed |

**State shape**:
```
state.opportunities = {
  byId: { [id]: Opportunity },
  idsByStage: { [stageId]: [id, ...] },   // ordered card ids per column
  allIds: [id, ...],                       // union, used for by-id lookups/updates only
  pagination: {
    byStage: { [stageId]: { page: Number, hasMore: Boolean } },
  },
  uiFlags: {
    isFetchingByStage: { [stageId]: Boolean },
    isCreating: Boolean,
    isMoving: { [cardId]: Boolean },       // per-card in-flight flag for optimistic move + revert
  },
}
```

**Derived (getters)**:
- `cardsForStage(stageId)` — maps `idsByStage[stageId]` through `byId`; O(cards in that stage), never scans other stages (FR-002).
- `cardById(id)`.
- `hasMoreForStage(stageId)` / `isFetchingForStage(stageId)`.

**State transitions**:
- `status`: `open → won`, `open → lost`, `won → open`, `lost → open` (Reopen). No direct `won ↔ lost` transition specified; going from `won`/`lost` back to the other requires an intermediate `open` (Reopen then re-mark), matching FR-007a's literal wording ("mark an open opportunity as won or lost, and reopen a won/lost opportunity back to open").
- `pipelineStageId`: changes only via drag-and-drop move (FR-005) or manual creation's initial stage selection (FR-008); status changes MUST NOT alter `pipelineStageId` (FR-007a).

**Mutation-level invariants** (drive the mutation design, not just documentation):
- Moving a card between stages updates `idsByStage` for both the source and destination stage arrays and the card's `pipelineStageId` in `byId`, atomically within one mutation, so no intermediate state has the card in two columns or zero columns.
- A failed move (API rejection) triggers a mutation that reverses the above using the pre-move snapshot captured by the action before the optimistic update (FR-005's revert requirement).

## Board pagination state

Represented as `state.opportunities.pagination.byStage` above (folded into the Opportunity module rather than a separate top-level entity, since it's always accessed per-stage alongside the cards it paginates). Tracks, per FR-004 / Key Entities "Board pagination state": current loaded page and whether more remains, independently per stage, so scrolling one column never affects another column's loaded data or pagination cursor.

## Relationships

```
PipelineStage 1 ──── * Opportunity   (pipelineStageId)
Opportunity   * ──── 1 Contact       (denormalized snapshot only; contact is not owned by this module)
Opportunity   * ──── 0..1 Conversation (originConversationId; denormalized link only)
```

No client-side entity owns Contact or Conversation records — both are referenced by id/snapshot and read from their own existing store modules (`contacts`, `conversation`) where a live link is needed (e.g. navigating to the origin conversation).
