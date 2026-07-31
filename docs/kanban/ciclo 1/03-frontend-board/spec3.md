# Phase 3: Frontend Board — Kanban UI, Vuex Store, Settings

**Depends on**: Phase 1 (API endpoints for Opportunities/PipelineStages must exist), Phase 2 (for the Automation Rules dropdown to show `create_opportunity`)
**Feeds**: Phase 4 (realtime wiring plugs into the Vuex module and components built here)

## Context

Builds the visible Kanban board: columns = `PipelineStage`s, cards = `Opportunity`s, drag-and-drop between columns updates `pipeline_stage_id`. Also builds the admin settings screen for managing Pipeline Stages, and surfaces the new `create_opportunity` automation action in the existing Automation Rules UI.

No frontend extension point equivalent to `custom/` exists for Vue/Vite (no `app/javascript` overlay, no build alias) — this phase's frontend code lives in its own self-contained folder tree so it stays easy to diff/re-apply against upstream, but registering it into menus/routes/store requires editing a small, fixed set of core files. Those registration edits happen in Phase 4, not here — this phase produces components/store/screens that are fully built but not yet wired into navigation.

## Dev Environment

All `pnpm`/eslint/test commands run inside the `vite` container: `docker compose exec vite <command>`. The dev server itself is already running as the `vite` and `rails` containers (`docker compose up -d`); the dashboard is reachable at `http://localhost:3000` on the host — no `pnpm dev` needs to be started manually, and no host Node toolchain is used.

## Functional Requirements

**FR-001**: Vuex module at `app/javascript/dashboard/store/modules/opportunities.js` (or an isolated subpath such as `app/javascript/dashboard/opportunities/store/opportunities.js` registered later in Phase 4) with **normalized state**, not flat arrays:
```js
state: {
  cardsById: {},        // { [id]: opportunity }
  cardIdsByStage: {},   // { [stageId]: [id, id, ...] }
  pagination: {},        // { [stageId]: { page, hasMore } }
  uiFlags: { isFetching: false },
}
```
Mutations MUST update `cardsById` and `cardIdsByStage` independently (e.g., `SET_CARD` upserts into `cardsById`; `MOVE_CARD` removes an id from the source stage's array in `cardIdsByStage` and pushes it into the destination stage's array — no full-array rebuild/iteration over all cards). Actions: `fetchStage(stageId, page)` (paginated per-column fetch, Kaminari-style, merges into `pagination[stageId]`), `createOpportunity(payload)`, `updateOpportunity({ id, changes })`, `moveOpportunity({ id, fromStageId, toStageId })` (optimistic local mutation + API call, revert on failure).

**FR-002**: Getters MUST expose `cardsForStage(stageId)` (maps `cardIdsByStage[stageId]` through `cardsById`, returning full card objects for rendering) without any array-of-all-cards `.filter()` scan.

**FR-003**: `KanbanBoard.vue` (container) renders one `KanbanColumn.vue` per `PipelineStage` (fetched via a `pipeline_stages` API/store call, ordered by `position`). Each column renders `OpportunityCard.vue` per card.

**FR-004**: Drag-and-drop MUST use `vuedraggable`, following this repo's existing convention (`:model-value` one-way binding + shared `group` prop across columns — NOT `:list`, per existing Chatwoot drag-and-drop usage elsewhere in the codebase). On drop, dispatch `moveOpportunity`.

**FR-005**: `OpportunityCard.vue` displays: title, contact name/avatar, assignee, status badge (`open`/`won`/`lost` — distinct visual treatment, e.g. green/red badge for `won`/`lost` regardless of which stage the card is currently in, since status is independent of stage per the approved data model). Clicking the card opens a detail view/modal showing the `origin_conversation` (if present) with a link/route to that conversation.

**FR-006**: A manual-creation modal/flow lets an agent create an `Opportunity` by selecting a `Contact` (typeahead search reusing existing contact search API), `PipelineStage`, and `title`. `origin_conversation_id` is optional in this flow and only settable if launched from within an existing conversation's context (e.g., a "Create Opportunity" action button in the conversation sidebar — the button itself and its registration into the conversation UI is Phase 4 scope; this phase only builds the modal component and store action it calls).

**FR-007**: Settings screen for Pipeline Stages (`SettingsOpportunities/PipelineStages` or similar folder) — admin-only, gated by the `opportunities` feature flag from Phase 1 (FR-012). Lists stages ordered by `position`, supports create/rename/delete/reorder (drag-to-reorder using the same `vuedraggable` convention as FR-004, persisting `position` on drop).

**FR-008**: In the existing Automation Rules action-picker component, the new `create_opportunity` action (registered backend-side in Phase 2) MUST render with a parameter form requiring `pipeline_stage_id` (a select populated from the Pipeline Stages API) — implemented by extending the existing action-type-to-component mapping used by that picker (identify and reuse the exact pattern already used for `assign_agent`/`assign_team`'s dropdown params, do not invent a new pattern).

**FR-009**: All user-facing strings MUST go through i18n (`en.json`), no bare strings in templates, per repo convention.

**FR-010**: Styling MUST use Tailwind utility classes only, with Chatwoot's next-gen design tokens (`bg-n-surface-1`, `text-n-slate-12`, `border-n-weak`, etc.) for dark-mode compatibility — no static colors, no scoped CSS, no inline styles.

## Out of Scope (this phase)

- Wiring `KanbanBoard.vue` into the sidebar menu, `dashboard.routes.js`, `settings.routes.js`, or `store/index.js` (Phase 4).
- Realtime updates via ActionCable (Phase 4) — this phase's store only reacts to its own API calls, not websocket pushes.
- The anchor-marker + fail-fast sync script (Phase 4).

## Completion Criteria

This phase has visible UI — validate manually in the browser in addition to automated tests.

1. **Component tests**: `docker compose exec vite pnpm test` for new specs under `app/javascript/dashboard/**/__tests__/` covering: `opportunities.js` store mutations (assert `cardIdsByStage` and `cardsById` update correctly on `SET_CARD`/`MOVE_CARD` without touching unrelated stage arrays), `KanbanBoard.vue` renders one column per stage, `OpportunityCard.vue` renders `won`/`lost` badges correctly regardless of current stage.

2. **Lint clean**: `docker compose exec vite pnpm eslint` reports zero errors on all new files.

3. **Manual browser verification** (since this is UI-heavy, exercise the actual golden path before marking done — per repo convention of testing UI changes in-browser):
   - The `vite`/`rails` containers are already running the dev server; open `http://localhost:3000` on the host browser — no separate dev-server start step needed.
   - Since routing isn't wired yet (Phase 4), temporarily mount `KanbanBoard.vue` behind a throwaway dev-only route, or use Storybook/isolated component preview if available, to confirm: columns render in `position` order, cards render with correct badge for `status`, drag-and-drop between columns fires `moveOpportunity` and the API call succeeds (check network tab for the `PATCH` request and 200 response), the manual-creation modal creates an `Opportunity` visible immediately in the correct column, and the Pipeline Stages settings screen create/rename/delete/reorder all persist correctly (refresh page and confirm state survived).
   - Remove the throwaway dev route before merging/handing off to Phase 4 (Phase 4 supplies the real route).
   - Confirm dark mode: toggle dark mode and check no static-color classes leaked in (visually inspect column backgrounds, card backgrounds, badges).

4. **Automation Rules UI check** (FR-008): open Settings → Automation → create/edit a rule, confirm "Create Opportunity" appears in the action dropdown and its Pipeline Stage select is populated from real data (proves Phase 2's backend registration is correctly consumed).
