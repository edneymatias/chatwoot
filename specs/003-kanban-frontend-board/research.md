# Phase 0 Research: Frontend Board — Kanban UI, Vuex Store, Settings

All items from the Technical Context are resolved below; no `NEEDS CLARIFICATION` markers remain.

## 1. Cross-column drag-and-drop pattern

- **Decision**: Use `vuedraggable` bound via `:model-value` (one-way) per column, with a shared `group` prop (e.g. `group="kanban-cards"`) across all `KanbanColumn` instances so cards can be dragged between columns. On `@change`, read the `added`/`removed`/`moved` event payload to determine the card id, source stage, target stage, and target index, then dispatch a single Vuex action (e.g. `opportunities/moveCard`) that both updates local state optimistically and calls the API to persist the new stage/position.
- **Rationale**: The codebase's existing `vuedraggable` usages (`CategoryList.vue`, `Macros/List.vue`) are all single-list reorder with `v-model`/`:list` two-way binding — sufficient for reordering within one list but not for moving items across independent lists with per-column pagination state. `:model-value` (one-way) is the standard `vuedraggable`/`Sortable.js` pattern for cross-list drag because it lets the parent (Vuex-backed) state be the single source of truth instead of two-way-syncing multiple local component copies, avoiding state-authority conflicts between columns.
- **Alternatives considered**: (a) Keep `:list` two-way binding per column with manual reconciliation on drop — rejected, requires diffing two local mutable arrays against the store on every drop and is fragile; (b) adopt a different drag library — rejected, `vuedraggable` is an existing dependency and the constraint explicitly avoids adding a new one.

## 2. Vuex module normalization shape

- **Decision**: Model `store/modules/opportunities/` and `store/modules/pipelineStages/` on the existing `store/modules/helpCenterCategories/` convention: `state.opportunities = { byId: {}, allIds: [], idsByStage: {}, uiFlags: { byId: {} } }` plus top-level `uiFlags` (`isFetchingByStage`, `isCreating`) and `pagination` (`pageByStage`, `hasMoreByStage`) for the per-column infinite scroll required by FR-004. `pipelineStages` mirrors the simpler `byId`/`allIds` shape (no per-stage pagination needed).
- **Rationale**: This is the only existing normalized-state Vuex module in the dashboard and is structurally close to this feature's needs (entities grouped/ordered by a parent key — `byLocale` there, `byStage` here). Reusing it keeps getters/mutations idiomatic and avoids full-array rescans on single-card mutations, per the stated performance constraint.
- **Alternatives considered**: Flat un-normalized array of opportunity objects re-filtered per column on every render — rejected, causes unnecessary rescans as data grows and diverges from the project's established Vuex convention (Constitution III).

## 3. Contact selection in the manual-creation modal

- **Decision**: Reuse the existing `contacts/search` Vuex action (`store/modules/contacts/actions.js`) and model the "select a contact" field in `OpportunityCreateModal.vue` on `components-next/NewConversation/components/ContactSelector.vue` (or the debounced search helper `createContactSearcher()` in `NewConversation/helpers/composeConversationHelper.js`).
- **Rationale**: Contact search/typeahead already exists and is battle-tested; no new API endpoint or store logic is needed for this piece of FR-002 (manual creation).
- **Alternatives considered**: A new bespoke contact-search component — rejected as unnecessary duplication.

## 4. Automation Rules action-picker extension for `create_opportunity`

- **Decision**: Add `{ key: 'create_opportunity', label: 'CREATE_OPPORTUNITY', inputType: 'search_select' }` to `AUTOMATION_ACTION_TYPES` in `routes/dashboard/settings/automation/constants.js`. Add a `type === 'create_opportunity'` case in `getActionDropdownValues()` in `composables/useAutomationValues.js` that returns the account's pipeline stages (fetched via the new `pipelineStages` Vuex module) as `{ id, name }` dropdown options, matching the shape `SingleSelect` already expects for other `search_select` actions. No new branch in `AutomationActionInput.vue` is needed since `search_select` already exists and renders a `SingleSelect` bound to `action_params`.
- **Rationale**: This is the exact declarative pattern used for `assign_agent`/`assign_team` — a config-table entry plus a getter-function case, not a new component. Matches Constitution Principle II (smallest change) and I (only additive edits to existing shared files).
- **Alternatives considered**: A dedicated `CreateOpportunityActionInput.vue` component — rejected; unnecessary since the existing `search_select` inputType already covers "pick one item from a list" without a custom sub-form, and the spec's automation action (Phase 2, FR-003 in `specs/002-automation-integration/spec.md`) only requires a stage id plus an optional title parameter. If the optional title-template field is required in the same picker UI, a second `inputType` (e.g. `search_select_with_text`) may be introduced in `AutomationActionInput.vue` as a single additive `v-else-if` branch during implementation — deferred to task-level design since it doesn't change the module boundary.

## 5. Pipeline Stages settings screen structure

- **Decision**: Model `routes/dashboard/settings/pipelineStages/` on the Help Center Categories screen (`components-next/HelpCenter/Pages/CategoryPage/*`) for the list + drag-reorder + create/rename dialogs, and on `routes/dashboard/settings/macros/Index.vue` for the simpler list/search/delete-confirmation skeleton. Deletion of an occupied stage (FR-010) surfaces the existing delete-confirmation dialog pattern but replaces the destructive action with a blocked-state message when the API returns a conflict (stage has opportunities).
- **Rationale**: Both are established, working reference implementations for exactly this CRUD-with-reorder shape; no new UI pattern needs to be invented.
- **Alternatives considered**: None warranted — this is a standard settings CRUD screen.

## 6. API client convention

- **Decision**: `api/opportunities.js` and `api/pipelineStages.js` each define a class extending the shared `ApiClient` base (`api/ApiClient.js`), e.g. `class OpportunitiesAPI extends ApiClient { constructor() { super('opportunities', { accountScoped: true }); } }`, exported as a singleton, following the pattern used by `api/agentBots.js`/`api/attributes.js`. Custom endpoints beyond CRUD (e.g. move/status-change, reorder) are added as extra instance methods on the same class.
- **Rationale**: Matches every other simple resource client in the dashboard; no new HTTP-wrapping abstraction needed.
- **Alternatives considered**: None warranted.

## 7. Design tokens and i18n registration

- **Decision**: Use existing `n-*` Tailwind utility classes (`bg-n-surface-1`, `text-n-slate-12`, `border-n-weak`, etc.), confirmed defined in `theme/colors.js`/`tailwind.config.js`. Add a new `i18n/locale/en/opportunities.json` file (one-file-per-feature convention, like `macros.json`) registered in `i18n/locale/en/index.js`; add the automation action label under the existing `AUTOMATION.ACTIONS` key in `i18n/locale/en/automation.json`.
- **Rationale**: Matches Constitution III (established conventions) and keeps new strings isolated to a single diffable file plus one-line registrations in shared index files.
- **Alternatives considered**: None warranted.

## 9. Backend endpoint gap: per-stage pagination and stage reorder

- **Finding**: Inspecting the actual Phase 1/2 implementation (`custom/app/controllers/api/v1/accounts/opportunities_controller.rb`, `pipeline_stages_controller.rb`) shows: (a) `OpportunitiesController#index` returns the full policy-scoped collection with no `pipeline_stage_id` filter or page params — insufficient for FR-002 (fetch cards for one stage without scanning all stages) and FR-004 (per-column infinite scroll); (b) `PipelineStagesController#update` only permits `:name` — no way to persist a new `position` via the API, needed for FR-010's drag-to-reorder. Both gaps are parameter/query additions only — the underlying columns (`pipeline_stage_id`, `status`, `position`) already exist in the Phase 1 schema, and `PipelineStage` already enforces occupied-stage delete-blocking via `has_many :opportunities, dependent: :restrict_with_error` (confirmed satisfies FR-010's block-with-message requirement as-is).
- **Decision**: Treat these as small, additive parameter/query changes to the already-existing Phase 1 controllers (permit `:position` in `pipeline_stage_params`; add `pipeline_stage_id`/`page` query support to `OpportunitiesController#index`), to be included as backend prerequisite tasks in this phase's `tasks.md` rather than deferred, since without them the frontend cannot satisfy FR-002/FR-004/FR-010 at all. This does not conflict with the Technical Context's "no new backend storage" statement — no schema/migration changes are needed, only controller param/query surface.
- **Rationale**: Blocking this phase entirely on a hypothetical "Phase 1.5" would violate the smallest-production-ready-change principle by fragmenting a two-line controller change into its own phase; these are the minimum backend touches required for this phase's own functional requirements to be implementable at all.
- **Alternatives considered**: Client-side filtering/pagination over the full unfiltered `index` response — rejected, explicitly contradicts FR-001/FR-002 ("without scanning across all stages' cards") and would not scale.

## 8. Enterprise dual-tree check

- **Decision**: No Enterprise-specific overrides exist for Automation Rules UI or Settings navigation (`grep` across `enterprise/app/javascript` for automation/settings found no matches). This phase requires no Enterprise extension points.
- **Rationale**: Confirms Constitution Principle V gate is satisfied with no follow-up work.

## 10. VueDraggable reactivity and rendering crashes

- **Finding**: During Phase 3 implementation, binding `vuedraggable` directly to a Vuex getter (`stagesSortedByPosition`) resulted in Vue reactivity bugs where mutating the DOM via Sortable.js clashed with Vue's virtual DOM patch cycle for immutable Vuex state, leading to "Unhandled error during execution of component update" and freezing the app route. Furthermore, using an invalid icon string (`line-horizontal-3`) for a `fluent-icon` component within the draggable list completely crashed the render cycle when Vue attempted to rebuild it after a drag event.
- **Decision**: 1) Map the sorted stages from Vuex to a local reactive `ref` synced via `watch`, rather than binding `v-model` directly to the getter. 2) Always use established Unocss utility icons (e.g., `class="i-lucide-grip-vertical"`) for drag handles instead of `fluent-icon` unless existence is strictly verified.
- **Rationale**: Prevents unhandled Vue patch errors and guarantees stable drag-and-drop rendering mechanics.

## 11. Settings Layout wrapping

- **Finding**: Chatwoot's settings screens require a global layout wrapper to correctly constrain width and center content. Omitting `SettingsWrapper` around the route causes the panel to stretch to the screen edge and hug the left margin. Failing to use `SettingsLayout` inside the component breaks structural spacing.
- **Decision**: Always inject new settings routes inside a `SettingsWrapper` children block (in `settings.routes.js`), and always use `<SettingsLayout>` with `#header` and `#body` slots at the component's root.
- **Rationale**: Preserves UI consistency across all settings pages and avoids fragile `max-w` margin hacking.
