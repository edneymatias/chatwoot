# Quickstart: Validating the Frontend Board

This phase ships components, a Vuex module, and API clients that are **not yet wired into navigation/routes** (deferred to Phase 4 per spec.md Assumptions). Validation here is therefore at the unit/component level plus a manual harness, not a full click-through of the live dashboard.

## Prerequisites

- Stack running: `docker compose up -d` (needs `rails`, `vite`, `postgres`, `redis`).
- An account with the `opportunities` feature flag enabled and at least one pipeline stage (`PipelineStage.seed_defaults_for!` runs automatically on first `GET /pipeline_stages`).
- The two backend param additions from `contracts/api.md` (`position` on `PipelineStagesController#update`, `pipeline_stage_id`/`page` filters on `OpportunitiesController#index`) implemented and passing their existing request specs (`spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb`, `.../opportunities_controller_spec.rb`).

## 1. Backend contract check

```bash
docker compose exec rails bundle exec rspec spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb spec/requests/api/v1/accounts/opportunities_controller_spec.rb
```
Expected: all pass, including new/updated examples for `position` update and `pipeline_stage_id`/`page` filtered index.

## 2. Vuex store module

```bash
docker compose exec vite pnpm test store/modules/opportunities
docker compose exec vite pnpm test store/modules/pipelineStages
```
Expected: actions correctly call the API client and commit normalized state per `contracts/store.md`; `moveCard` reverts state on a mocked API failure (validates FR-005/SC-002); `fetchForStage` appends rather than replaces on `page > 1` (validates FR-004).

## 3. Components

```bash
docker compose exec vite pnpm test components-next/Opportunities
```
Expected: `KanbanColumn` renders one card per entry in `cardsForStage`, in `idsByStage` order; dragging across two mounted columns (sharing a Vuex store instance with `group="kanban-cards"`) emits `card-moved` with correct `fromStageId`/`toStageId`; `KanbanCard` shows the `won`/`lost` badge only for those statuses; `OpportunityCreateModal` disables submit until contact + stage + title are set; `OpportunityDetailView` hides the conversation link when `originConversationId` is null.

## 4. Manual harness (since routes aren't registered yet)

Since this phase doesn't wire routes, mount the board standalone for manual verification, e.g. a temporary Storybook-style entry or a scratch route added locally (not committed) that:
1. Registers `pipelineStages` and `opportunities` modules on a local store instance.
2. Renders `<KanbanBoard />`.
3. Confirms: columns render in position order (US1 scenario 1); dragging a card between columns updates it immediately and persists (US1 scenario 2); killing network to the PATCH endpoint and retrying a drag reverts the card (US1 scenario 3); scrolling a long column loads more cards without disturbing other columns (US1 scenario 4); the manual-create modal creates a visible card (US2); clicking a card opens the detail view and Mark as Won/Lost/Reopen updates the badge without moving the card (US3).

## 5. Automation Rules action picker

```bash
docker compose exec vite pnpm test routes/dashboard/settings/automation
```
Expected: `AUTOMATION_ACTION_TYPES` includes `create_opportunity`; selecting it renders a stage-populated `SingleSelect` (mock `pipelineStages/stagesSortedByPosition`); saving and reopening the rule preserves the selected `pipeline_stage_id` (US5 scenarios 1–3).

## 6. Dark mode / i18n spot check

- Toggle dark mode in the manual harness from step 4; confirm columns/cards/badges remain legible (FR-015, SC-006).
- Grep for hardcoded strings introduced by this phase: `grep -rn "['\"][A-Z][a-z]" app/javascript/dashboard/components-next/Opportunities app/javascript/dashboard/routes/dashboard/settings/pipelineStages` should show no bare user-facing English strings outside of `i18n/locale/en/opportunities.json` (FR-014).

## Done when

- All automated checks in steps 1–3 and 5 pass.
- Manual harness in step 4 demonstrates every acceptance scenario in User Stories 1–3 (P1–P3) end-to-end against a real (dev) backend.
- Step 6 passes visually.
