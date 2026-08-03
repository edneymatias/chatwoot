---

description: "Task list template for feature implementation"
---

# Tasks: Closing Required Fields (Win/Loss)

**Input**: Design documents from `/specs/010-closing-required-fields/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/closing-required-fields-api.md, quickstart.md

**Tests**: Not included by default (project convention: avoid writing specs unless explicitly asked). Sibling feature `PipelineStageRequiredField` has model/request specs for parity — if the user wants matching coverage for this feature, ask before adding test tasks.

**Organization**: Tasks are grouped by user story (spec.md priorities P1/P2/P3) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Path Conventions

Existing Chatwoot monorepo layout (Rails API + Vue SPA). Fork-specific backend code under `custom/`; frontend under `app/javascript/dashboard/`. See `plan.md`'s Project Structure section for the full file tree.

---

## Phase 1: Setup

**Purpose**: Add the new table this feature needs.

- [x] T001 Create migration `db/migrate/<timestamp>_create_matias_pipeline_closing_required_fields.rb`: `create_table :matias_pipeline_closing_required_fields` with `t.references :account, null: false, foreign_key: true`, `t.references :custom_attribute_definition, null: false, foreign_key: true`, `t.integer :outcome, null: false`, `t.timestamps`; add a unique index on `[:account_id, :custom_attribute_definition_id, :outcome]` named `idx_matias_pipeline_closing_req_fields_on_acc_attr_outcome`. Mirrors `db/migrate/20260801082517_create_matias_pipeline_stage_required_fields.rb`.
- [x] T002 Run the migration: `docker compose exec rails bundle exec rails db:migrate`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core model that both US1 (enforcement) and US2 (admin config) depend on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Create `custom/app/models/pipeline_closing_required_field.rb`: `self.table_name = 'matias_pipeline_closing_required_fields'`; `belongs_to :account`; `belongs_to :custom_attribute_definition`; `enum outcome: { won: 0, lost: 1 }` (a comment above this line should note the integer mapping is independent of `Opportunity#status`'s own `enum status: { open: 0, won: 1, lost: 2 }` — same words, unrelated columns, to avoid confusion when the two models are read side by side); `validates :account, presence: true`; `validates :custom_attribute_definition, presence: true`; `validates :custom_attribute_definition_id, uniqueness: { scope: %i[account_id outcome], message: 'is already required for this outcome' }`; `validate :definition_must_be_opportunity_attribute` (identical body to the sibling `PipelineStageRequiredField#definition_must_be_opportunity_attribute`). Mirrors `custom/app/models/pipeline_stage_required_field.rb`.
- [x] T004 Add `has_many :pipeline_closing_required_fields, dependent: :destroy` to the `included do` block in `custom/app/models/custom/concerns/account.rb` (the existing extension point already providing `has_many :pipeline_stages` / `has_many :opportunities` on `Account`).
- [x] T005 [P] Create `custom/app/policies/pipeline_closing_required_field_policy.rb`: `index?`, `show?`, `create?`, `update?`, `destroy?` all `@account_user.administrator?`. Mirrors `custom/app/policies/pipeline_stage_required_field_policy.rb` exactly.

**Checkpoint**: Model, association, and policy exist — US1 and US2 can now proceed.

---

## Phase 3: User Story 1 - Blocking a close until required fields are filled (Priority: P1) 🎯 MVP

**Goal**: Changing an opportunity's status to `won`/`lost` is blocked (with a 422 + `missing_required_fields`) when a configured closing requirement for that outcome isn't met, and the Kanban UI shows a modal to fill in exactly the missing attributes and retry.

**Independent Test**: Seed one `PipelineClosingRequiredField` for `outcome: lost` via `rails runner` (per `quickstart.md` step 1), attempt to mark an opportunity lost via the API without that attribute, confirm `422` + `missing_required_fields.custom_attribute_keys`, then retry with the attribute included and confirm `200`.

### Implementation for User Story 1

- [x] T006 [US1] In `custom/app/models/opportunity.rb`, add `validate :validate_closing_requirements, on: :update, if: :status_changed?` alongside the existing `validate :validate_forward_stage_move_requirements, ...` line, and implement the private method: guard `return unless status.to_s.in?(%w[won lost])`; look up `PipelineClosingRequiredField.where(account_id: account_id, outcome: status)`; for each row's `custom_attribute_definition`, check `(custom_attributes || {}).key?(definition.attribute_key)` (same presence semantics as `validate_forward_stage_move_requirements`); on any missing key, set `self.missing_required_fields = { custom_attribute_keys: missing_keys }` and `errors.add(:base, 'Missing required fields to close this opportunity')`. Per `data-model.md`, this runs fully independently of the existing stage-move validation.
- [x] T007 [US1] Create `app/javascript/dashboard/components-next/Opportunities/ClosingRequirementsModal.vue`, mirroring `StageTransitionRequirementsModal.vue`: props `opportunity` (Object, required), `outcome` (String, required — `'won'` or `'lost'`), `initialMissingFields` (Object, default `{ custom_attribute_keys: [] }`); use `OpportunityRequiredFieldsForm.vue` for `v-model:custom-attributes` bound to a local copy of `props.opportunity.custom_attributes`, passing `missing-custom-attribute-keys`; no deal-value / stage-position logic (this modal has no "optional from previous stages" section, unlike the stage-move modal, since closing requirements aren't stage-scoped); `onSubmit` dispatches `opportunities/setStatus` with `{ id: opportunity.id, status: outcome, custom_attributes: customAttributes.value }`, catches a `422` with `missing_required_fields` to re-populate `missingCustomAttributeKeys` instead of closing, and emits `submit`/`close` on success.
- [x] T008 [US1] Extend `setStatus` action in `app/javascript/dashboard/store/modules/opportunities/actions.js` (currently `setStatus: async ({ commit, state }, { id, status }) => {...}`) to accept an optional `custom_attributes` param, pass it through to `opportunitiesAPI.update(id, { status, custom_attributes })`, and on success merge the returned `custom_attributes` into the committed state (mirroring how `moveCard` already merges `custom_attributes`/`value` on its optimistic commit); keep the existing revert-on-error behavior (`commit('SET_STATUS', { id, status: previousStatus })` then `throwErrorMessage(error)`), but re-throw the raw error (not just the message) so callers can inspect `error.response.data.missing_required_fields`, matching how `executeMoveCard` currently catches errors from `moveCard`.
- [x] T009 [US1] In `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`, wrap the existing `onStatusChanged` handler (`onStatusChanged = ({ id, status }) => { store.dispatch('opportunities/setStatus', { id, status }); }`) in a try/catch identical in shape to `executeMoveCard`: on a `422` with `error.response.data.missing_required_fields`, set a new `closingRequirementsModalData` ref (`{ opportunity: store.state.opportunities.byId[id], outcome: status, initialMissingFields: missing }`) and open a new `isClosingRequirementsModalOpen` ref; add `<ClosingRequirementsModal v-if="isClosingRequirementsModalOpen" ... @close="closeClosingRequirementsModal" />` next to the existing `<StageTransitionRequirementsModal>` block, importing the new component.

**Checkpoint**: User Story 1 is fully functional and independently testable via the API (per `quickstart.md` steps 2-3) even before US2's admin UI exists (requirements can be seeded via `rails runner` in the meantime).

---

## Phase 4: User Story 2 - Configuring required fields per outcome (Priority: P2)

**Goal**: An account admin can manage two independent lists (required-for-won, required-for-lost) of opportunity custom attributes via the API and a settings screen.

**Independent Test**: As an admin, `POST` a closing requirement for `outcome: won`, a different one for `outcome: lost`, `GET` the list and confirm both appear; attempt a duplicate `(attribute, outcome)` pair and confirm it's rejected with a 422.

### Implementation for User Story 2

- [x] T010 [US2] Add routes in `config/routes.rb` **inside the existing accounts-scoped resources block** — the same nested block that already declares `resources :pipeline_stages` and `resources :opportunities` (do not declare this as a new top-level or separately-scoped resource; it must sit at the same indentation/nesting level as those siblings so it inherits the `/api/v1/accounts/:account_id/` scoping): `resources :pipeline_closing_required_fields, only: [:index, :create, :destroy]`.
- [x] T011 [US2] Create `custom/app/controllers/api/v1/accounts/pipeline_closing_required_fields_controller.rb`: `include Concerns::KanbanFeatureGuard`; `before_action :check_authorization`; `index` renders `Current.account.pipeline_closing_required_fields`; `create` builds `Current.account.pipeline_closing_required_fields.build(closing_required_field_params)`, saves, and renders the record or a 422 with `errors.full_messages.join(', ')` (no destroy-then-create upsert like the sibling controller, since duplicates are already prevented per-outcome by the model's uniqueness validation and the same attribute is allowed across both outcomes); `destroy` finds `Current.account.pipeline_closing_required_fields.find(params[:id])` (by the row's own `id`, not by `custom_attribute_definition_id` — see `contracts/closing-required-fields-api.md`) and destroys it, rendering `head :ok` or a 422; `closing_required_field_params` permits `:custom_attribute_definition_id, :outcome`.
- [x] T012 [P] [US2] Create `app/javascript/dashboard/api/pipelineClosingRequiredFields.js`: `class PipelineClosingRequiredFieldsAPI extends ApiClient { constructor() { super('pipeline_closing_required_fields', { accountScoped: true }); } }`, exporting a singleton instance (uses the base `ApiClient`'s `get`/`create`/`delete` for `index`/`create`/`destroy` — no custom methods needed since routes aren't nested under another resource).
- [x] T013 [US2] Create a new Vuex module `app/javascript/dashboard/store/modules/pipelineClosingRequiredFields/` (`actions.js`, `mutations.js`, `getters.js`, `index.js`, mirroring the shape of `store/modules/pipelineStages/`): `fetch` action populates state from the API; `create({ customAttributeDefinitionId, outcome })` and `destroy(id)` actions call the new API client and update local state; getters expose `requiredForWon`/`requiredForLost` (or a single list filtered by outcome in the component). Register the module in the root store index alongside the existing `pipelineStages` module.
- [x] T014 [US2] Create `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/ClosingRequiredFields.vue`: reuse the checkbox-list attribute-picker markup pattern from `EditPipelineStage.vue` (`opportunityAttributes` computed from `store.getters['attributes/getAttributesByModel']('opportunity_attribute')`), rendered twice — once for "required for won" and once for "required for lost" — each backed by its own `selectedAttributeIds`-style ref seeded from `pipelineClosingRequiredFields` store state; saving diffs the checkbox selection against existing entries and dispatches `create`/`destroy` for additions/removals per list, independently per outcome.
- [x] T015 [US2] Add a route entry for the new settings screen in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/pipelineStages.routes.js` (e.g. `path: frontendURL('accounts/:accountId/settings/pipeline-stages/closing-required-fields')`, `name: 'pipeline_closing_required_fields_index'`, `meta: { permissions: ['administrator'] }`, `component: ClosingRequiredFields`), and add a link to it from the existing stages `Index.vue` (no tab-bar shell — a simple navigation link, per `research.md`'s decision to defer the tabbed shell).
- [x] T016 [P] [US2] Add new i18n strings to `app/javascript/dashboard/i18n/locale/en/opportunity.json` (or wherever `OPPORTUNITIES.REQUIREMENTS_MODAL` keys currently live) for the new settings screen labels ("Required for won", "Required for lost", save/empty-state copy) and any new `ClosingRequirementsModal` strings not already covered by reused `OPPORTUNITIES.REQUIREMENTS_MODAL` keys.

**Checkpoint**: Admins can fully configure closing requirements through the UI; combined with US1, the feature is end-to-end functional.

---

## Phase 5: User Story 3 - Reopening a closed opportunity is unaffected (Priority: P3)

**Goal**: Confirm reopening (status → `open`) never triggers the closing-requirement check, regardless of missing attributes.

**Independent Test**: Mark an opportunity `won` while missing an attribute required for `won` isn't possible to set up normally (US1 blocks it) — so seed the missing state directly (e.g. `update_column`), then change status back to `open` via the API and confirm `200` with no `missing_required_fields` in the response, per `quickstart.md` step 4.

### Implementation for User Story 3

- [x] T017 [US3] No new production code — this story is satisfied by the guard clause already implemented in T006 (`return unless status.to_s.in?(%w[won lost])`). Verify manually via `quickstart.md` step 4 (`PATCH` with `{"opportunity": {"status": "open"}}` against an opportunity missing a required-for-won/lost attribute) and confirm the reopen succeeds with no validation triggered.

**Checkpoint**: All three user stories verified independently.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T018 [P] Run `docker compose exec rails bundle exec rubocop -a custom/app/models/pipeline_closing_required_field.rb custom/app/controllers/api/v1/accounts/pipeline_closing_required_fields_controller.rb custom/app/policies/pipeline_closing_required_field_policy.rb custom/app/models/opportunity.rb custom/app/models/custom/concerns/account.rb`.
- [x] T019 [P] Run `docker compose exec vite pnpm eslint:fix` on the new/modified Vue and JS files.
- [x] T020 Run the full `quickstart.md` validation end-to-end (backend `rails runner`/`curl` steps 1-4, and the manual UI checklist in step 5) and confirm every "Expected" outcome matches. During step 5, also time the admin flow of adding/removing a required attribute on the new settings screen and confirm it completes in under 1 minute, per SC-003.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Setup (T001-T002) — BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2). Independently testable via API without US2's UI.
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2). Does not depend on US1's frontend work, but its settings screen is only meaningful once US1's enforcement exists.
- **User Story 3 (Phase 5)**: Depends on T006 (part of US1) — it verifies a guard clause already written there; no new implementation.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Within Each User Story

- T006 (model validation) before T007-T009 (frontend, which assumes the 422 contract exists).
- T003-T005 (model/association/policy) before T010-T011 (routes/controller reference the model and policy).
- T010-T012 before T013 (store module calls the API client, which calls the routes/controller).
- T013 before T014 (settings screen consumes the store module).

### Parallel Opportunities

- T005 can run in parallel with T003/T004 (different files).
- T012 and T016 are marked `[P]` — independent files from the rest of their phase's tasks.
- T018 and T019 (Polish) can run in parallel — different toolchains.
- US1 (Phase 3) and US2 (Phase 4) can be worked on in parallel once Phase 2 completes, since US1's enforcement doesn't require US2's admin UI to exist (config can be seeded directly for testing).

---

## Parallel Example: Foundational Phase

```bash
# T003 and T005 touch different files and have no interdependency:
Task: "Create PipelineClosingRequiredField model in custom/app/models/pipeline_closing_required_field.rb"
Task: "Create PipelineClosingRequiredFieldPolicy in custom/app/policies/pipeline_closing_required_field_policy.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002).
2. Complete Phase 2: Foundational (T003-T005).
3. Complete Phase 3: User Story 1 (T006-T009).
4. **STOP and VALIDATE**: Seed a `PipelineClosingRequiredField` via `rails runner` and verify enforcement + UI modal per `quickstart.md` steps 1-3.
5. Deploy/demo if ready — admins can already be configured via `rails console` until US2 ships.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. User Story 1 → enforcement works end-to-end (backend + Kanban modal) → demo with seeded config.
3. User Story 2 → admins can self-serve configuration via settings UI → demo.
4. User Story 3 → verify no regression on reopen (no new code, verification only).
5. Polish → lint, format, full quickstart pass.

---

## Notes

- Tests were intentionally omitted per project convention (avoid writing specs unless explicitly asked); the sibling feature's specs (`custom/spec/models/pipeline_stage_required_field_spec.rb`, `custom/spec/requests/api/v1/accounts/pipeline_stage_required_fields_controller_spec.rb`) are the parity reference if the user requests matching coverage later.
- The combined-request edge case (both `pipeline_stage_id` and `status` changing in one request, where only one validation's `missing_required_fields` payload survives) is a known, UI-unreachable limitation documented in `research.md` — no task addresses it, by design.
- No Enterprise-tree changes required (confirmed via `research.md` — no Opportunities code exists under `enterprise/`).
