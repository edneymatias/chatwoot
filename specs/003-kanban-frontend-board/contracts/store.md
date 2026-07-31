# Contract: Vuex Store Modules

These are the public actions/getters other code (components in this phase, and Phase 4's navigation/realtime wiring) is expected to call. Internal mutations are implementation detail and not part of this contract.

## `store/modules/pipelineStages`

**Actions**:
- `pipelineStages/fetch()` — GET all stages, populate `byId`/`allIds`.
- `pipelineStages/create({ name })` — POST, insert into `byId`/`allIds` on success.
- `pipelineStages/update({ id, name })` — PATCH name-only rename.
- `pipelineStages/reorder({ id, position })` — PATCH position (requires the backend `:position` param change in `contracts/api.md`); reorders `allIds` locally to match.
- `pipelineStages/delete({ id })` — DELETE; on `422` (occupied stage), action rejects with the server's error message for the caller (settings screen) to display per FR-010, rather than removing the stage from state.

**Getters**:
- `pipelineStages/stagesSortedByPosition` → `PipelineStage[]`, sorted by `position`.
- `pipelineStages/stageById(id)` → `PipelineStage | undefined`.

## `store/modules/opportunities`

**Actions**:
- `opportunities/fetchForStage({ stageId, page = 1 })` — GET `?pipeline_stage_id=stageId&page=page`; appends results to `idsByStage[stageId]` (or replaces if `page === 1`), updates `pagination.byStage[stageId]`. Called on column mount and by infinite scroll (FR-004).
- `opportunities/create({ title, contactId, pipelineStageId, originConversationId })` — POST; on success, unshifts the new id into `idsByStage[pipelineStageId]` so it's immediately visible (FR-008).
- `opportunities/moveCard({ id, fromStageId, toStageId, toIndex })` — optimistically mutates `idsByStage` for both stages and the card's `pipelineStageId`, then PATCHes `{ pipeline_stage_id: toStageId }`; on failure, reverts using the pre-move snapshot and surfaces an error for the UI to display (FR-005, SC-002).
- `opportunities/setStatus({ id, status })` — PATCHes `{ status }` only (never touches `pipelineStageId`); updates `byId[id].status` on success (FR-007a).

**Getters**:
- `opportunities/cardsForStage(stageId)` → `Opportunity[]`, ordered per `idsByStage[stageId]` (FR-002 — no cross-stage scan).
- `opportunities/cardById(id)` → `Opportunity | undefined`.
- `opportunities/hasMoreForStage(stageId)` → `Boolean`.
- `opportunities/isFetchingForStage(stageId)` → `Boolean`.

## Consumer contract note

Per spec.md Assumptions, neither module is registered in `store/modules/index.js` by this phase — components/tests within this phase's own directories import and mount these modules directly (e.g. via a local Vuex store instance in specs, or a manual `store.registerModule` in a standalone dev harness) rather than relying on global registration, which Phase 4 will add.
