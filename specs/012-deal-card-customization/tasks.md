---

description: "Task list for Deal Card Customization"

---

# Tasks: Deal Card Customization

**Input**: Design documents from `/specs/012-deal-card-customization/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/pipeline-card-field-configs-api.md, contracts/pipeline-currency-setting-api.md,
quickstart.md

**Tests**: Not requested in the feature spec — no test tasks are included, per repo convention
(avoid writing specs unless explicitly asked). `pnpm eslint` and `bundle exec rubocop` remain
mandatory quality gates (see Polish phase).

**Organization**: Both user stories in spec.md (US1: admin configures fields, US2: cards show
badges) require the same backend data model and API, so that shared backend + frontend-state work
sits in Phase 2 (Foundational) rather than being duplicated. Each user story phase then adds only
its own UI slice on top. The account-wide currency setting (Amendment 2026-08-03) is also shared
infrastructure — its model/API/store land in Phase 2 alongside the card-field-config work, since
both User Story 1 (currency selector in the settings tab) and User Story 2 (currency-formatted
badges) depend on it.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)

## Path Conventions

Web app (Rails + Vue monolith), per plan.md's Project Structure — fork-specific backend code under
`custom/app/...`, minimal core wiring in `app/models/custom_attribute_definition.rb` and
`config/routes.rb`, frontend under `app/javascript/dashboard/...`.

---

## Phase 1: Setup

**Purpose**: No new tooling/dependencies are needed — this feature reuses the existing Rails/Vue
stack, `ColorPicker.vue`, `Label.vue`, and `ApiClient` conventions already in the repo. Nothing to
initialize.

*(No tasks — proceed directly to Foundational.)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The data model, API, authorization, and frontend Vuex module that both user stories
depend on — for both the card-field-config list and the account-wide currency setting. Nothing in
Phase 3/4 can be meaningfully tested without this phase complete.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T001 Create migration `db/migrate/<timestamp>_create_matias_pipeline_card_field_configs.rb` for table `matias_pipeline_card_field_configs` (`account_id` FK, `custom_attribute_definition_id` nullable FK, `field_type` integer, `color` string, `position` integer, timestamps), per data-model.md
- [ ] T002 Run the migration and confirm schema.rb updates (`docker compose exec rails bundle exec rails db:migrate`)
- [ ] T003 [P] Create `PipelineCardFieldConfig` model in `custom/app/models/pipeline_card_field_config.rb`: `belongs_to :account`, `belongs_to :custom_attribute_definition, optional: true`, `enum field_type: { custom_attribute: 0, deal_value: 1 }`, `color` presence validation, `custom_attribute_definition_id` uniqueness scoped to `account_id` (only when `custom_attribute`), validation that the referenced definition is `opportunity_attribute`, validation for at most one `deal_value` row per account, validation for at most 3 rows per account, `before_validation :set_position, on: :create` mirroring `PipelineStage#set_position` — see research.md and data-model.md
- [ ] T004 [P] Add `has_many :pipeline_card_field_configs, dependent: :destroy` to `Account` in `custom/app/models/custom/concerns/account.rb`
- [ ] T005 [P] Create new concern `custom/app/models/custom/concerns/custom_attribute_definition.rb` (`Custom::Concerns::CustomAttributeDefinition`) with `has_many :pipeline_card_field_configs, dependent: :destroy`
- [ ] T006 Wire the new concern by appending `CustomAttributeDefinition.include_mod_with('Concerns::CustomAttributeDefinition')` to the bottom of `app/models/custom_attribute_definition.rb`
- [ ] T007 [P] Create `PipelineCardFieldConfigPolicy` in `custom/app/policies/pipeline_card_field_config_policy.rb`, mirroring `PipelineClosingRequiredFieldPolicy` (all actions gated on `@account_user.administrator?`)
- [ ] T008 Create `Api::V1::Accounts::PipelineCardFieldConfigsController` in `custom/app/controllers/api/v1/accounts/pipeline_card_field_configs_controller.rb` with `index`, `create`, `update`, `destroy` actions per contracts/pipeline-card-field-configs-api.md (422 with error message on validation failure, `head :ok` on destroy)
- [ ] T009 Add route in `config/routes.rb`: `resources :pipeline_card_field_configs, only: [:index, :create, :update, :destroy]` alongside the existing `pipeline_closing_required_fields` route
- [ ] T010 [P] Create frontend API client `app/javascript/dashboard/api/pipelineCardFieldConfigs.js` extending `ApiClient` with `accountScoped: true`, resource `pipeline_card_field_configs`
- [ ] T011 [P] Create Vuex module files in `app/javascript/dashboard/store/modules/pipelineCardFieldConfigs/`: `actions.js` (`fetch`, `create`, `update`, `destroy`), `mutations.js`, `getters.js`, `index.js` (namespaced, `records`/`uiFlags` state) — mirror `pipelineClosingRequiredFields`, adding the `update` action it lacks
- [ ] T012 Register the new `pipelineCardFieldConfigs` Vuex module in the dashboard store's module index (wherever `pipelineClosingRequiredFields` is currently registered)
- [ ] T013 [P] Create migration `db/migrate/<timestamp>_create_matias_pipeline_currency_settings.rb` for table `matias_pipeline_currency_settings` (`account_id` bigint not null unique FK, `currency` string not null default `'usd'`, timestamps), per data-model.md
- [ ] T014 Run the migration and confirm schema.rb updates (`docker compose exec rails bundle exec rails db:migrate`)
- [ ] T015 [P] Create `PipelineCurrencySetting` model in `custom/app/models/pipeline_currency_setting.rb`: `belongs_to :account`, `currency` presence + inclusion validation in `%w[usd brl]`, `account_id` uniqueness
- [ ] T016 Add `has_one :pipeline_currency_setting, dependent: :destroy` to `Account` in `custom/app/models/custom/concerns/account.rb` (same file as T004 — sequence after it, not in parallel)
- [ ] T017 [P] Create `PipelineCurrencySettingPolicy` in `custom/app/policies/pipeline_currency_setting_policy.rb`, mirroring `PipelineCardFieldConfigPolicy` (all actions gated on `@account_user.administrator?`)
- [ ] T018 Create `Api::V1::Accounts::PipelineCurrencySettingsController` in `custom/app/controllers/api/v1/accounts/pipeline_currency_settings_controller.rb` with singular-resource `show`/`update` actions per contracts/pipeline-currency-setting-api.md (`show` lazily returns default `'usd'` without persisting; `update` finds-or-creates the row; 422 with error message on validation failure)
- [ ] T019 Add route in `config/routes.rb`: `resource :pipeline_currency_setting, only: [:show, :update]`, mirroring the existing `resource :branded_email_layout, only: [:show, :update]` singleton pattern
- [ ] T020 [P] Create `app/javascript/dashboard/constants/pipelineCurrency.js`: `SUPPORTED_PIPELINE_CURRENCIES = ['usd', 'brl']`, `DEFAULT_PIPELINE_CURRENCY = 'usd'`, `getCurrencyConfig`, `formatCurrencyAmount` — structurally mirrors `constants/billing.js`, kept as a separate module per research.md
- [ ] T021 [P] Create frontend API client `app/javascript/dashboard/api/pipelineCurrencySetting.js` extending `ApiClient`, singleton style (overrides `get()`/`update()` without an id param, mirroring `api/samlSettings.js`)
- [ ] T022 [P] Create Vuex module files in `app/javascript/dashboard/store/modules/pipelineCurrencySetting/`: `actions.js` (`fetch`, `update`), `mutations.js`, `getters.js`, `index.js` (namespaced, single-record `state.currency`/`uiFlags`)
- [ ] T023 Register the new `pipelineCurrencySetting` Vuex module in the dashboard store's module index (same location as T012)

**Checkpoint**: Backend API and frontend Vuex modules (both card-field-configs and the currency
setting) are in place and can be exercised directly (e.g. via `curl`/Postman or Vuex devtools) —
user story implementation can now begin.

---

## Phase 3: User Story 1 - Admin configures which fields appear on cards (Priority: P1) 🎯 MVP

**Goal**: An account admin can open the pipeline settings, select up to 3 fields (custom
attributes and/or Deal Value), assign each a color, set the account's currency, and save.

**Independent Test**: Open the "Card Fields" settings tab, select/deselect fields with colors, set
a currency, save, reload the page, and confirm the selections and currency persist exactly as
saved.

### Implementation for User Story 1

- [x] T024 [US1] Create `CardFieldConfig.vue` in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/CardFieldConfig.vue`, styled after `ClosingRequiredFields.vue`: on mount, dispatch `attributes/get`, `pipelineCardFieldConfigs/fetch`, and `pipelineCurrencySetting/fetch`, and build a checkbox list from `attributes/getAttributesByModel('opportunity_attribute')` plus a fixed "Deal Value" pseudo-option
- [x] T025 [US1] In `CardFieldConfig.vue`, show an inline `ColorPicker.vue` next to each checked field, disable unchecked checkboxes once 3 are selected with a "3/3 selected" hint, and implement `submit()` that diffs current selections/colors against the loaded configs (new selections → `create`, unchecked existing entries → `destroy`, color changes on entries that remain selected → `update`), matching the diff pattern in `ClosingRequiredFields.vue`'s `submit()`
- [x] T026 [US1] In `CardFieldConfig.vue`, add a separate currency selector (a `<select>`/dropdown over `SUPPORTED_PIPELINE_CURRENCIES` from `constants/pipelineCurrency.js`, pre-filled from the `pipelineCurrencySetting` store), visually and functionally independent from the 3 field checkboxes/color pickers, and have `submit()` dispatch `pipelineCurrencySetting/update` when the selected currency changed
- [x] T027 [US1] Add a `Card Fields` entry as the **first** tab in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/Index.vue`'s `tabs` list (before "Pipeline Stages" and "Closing Requirements"), and render `<CardFieldConfig />` for that tab's `selectedTabIndex`
- [x] T028 [US1] Add new i18n strings for the Card Fields tab (tab label, "Deal Value" option label, "3/3 selected" hint, currency selector label/options, save button/success/error messages) to `app/javascript/dashboard/i18n/locale/en/opportunities.json`, following the existing `OPPORTUNITIES.REQUIREMENTS_MODAL`/`PIPELINE_STAGES_MGMT` key structure

**Checkpoint**: An admin can fully configure card fields and the account currency end-to-end via
the settings UI; changes persist across reloads. (Badges won't appear on the board yet — that's
User Story 2.)

---

## Phase 4: User Story 2 - Team members see configured fields on cards (Priority: P1)

**Goal**: Every kanban card shows a colored, value-only, type-formatted badge for each configured
field that has a present value on that deal, with monetary badges using the account's configured
currency, and no visual change when nothing is configured.

**Independent Test**: With fields and a currency already configured (via direct DB/API setup or
User Story 1), open the kanban board and confirm badges render correctly for deals with and
without values, monetary badges reflect the configured currency, and cards on an unconfigured
account are unchanged.

### Implementation for User Story 2

- [x] T029 [US2] In `KanbanBoard.vue`'s mount logic, dispatch `pipelineCardFieldConfigs/fetch` and `pipelineCurrencySetting/fetch` once per board visit, alongside the existing `pipelineStages/fetch` dispatch
- [x] T030 [US2] In `KanbanCard.vue`, add a computed list of configured fields from the `pipelineCardFieldConfigs` store getters (ordered by `position`), each resolving the opportunity's raw value: `custom_attributes[definition.attribute_key]` for `custom_attribute` configs, `opportunity.value` for `deal_value` configs
- [x] T031 [US2] In `KanbanCard.vue`, format each resolved value by the definition's `attribute_display_type` (date values via `date-fns format` as in `CustomAttribute.vue`; `list`/`text`/`number` render as their plain value, no new formatter, per research.md); for `deal_value` configs and `attribute_display_type: 'currency'` custom attributes, format via `formatCurrencyAmount` from `constants/pipelineCurrency.js` using the currency from the `pipelineCurrencySetting` store getter; skip rendering a badge for any blank value, and omit the whole row when every configured value is blank for that card
- [x] T032 [US2] In `KanbanCard.vue`, render each non-blank badge using the `Label.vue` inline-style pattern (`background-color` from the config's `color`, text color via `getContrastingTextColor` from `@chatwoot/utils`), value only, placed as a new row alongside the existing fixed fields (which remain unchanged)

**Checkpoint**: All user stories now work end-to-end — admins configure fields and currency, and
every card on the board reflects them correctly, with zero change for unconfigured accounts.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final quality gates across both stories

- [x] T033 [P] Run `docker compose exec rails bundle exec rubocop -a` and fix any offenses in touched Ruby files
- [x] T034 [P] Run `docker compose exec vite pnpm eslint --fix` and fix any offenses in touched JS/Vue files
- [x] T035 Walk through `quickstart.md` end-to-end in a running dev stack (configure fields, set a currency, verify badges including currency formatting, verify removal cascade including deleting a referenced custom attribute definition, verify no-config baseline) and fix any discrepancies found

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: No dependencies — start immediately. BLOCKS both user stories.
- **User Story 1 (Phase 3)**: Depends on Phase 2 only.
- **User Story 2 (Phase 4)**: Depends on Phase 2 only — does NOT depend on Phase 3 (badges can be
  verified with configs/currency created directly via the API, independent of the settings UI
  existing).
- **Polish (Phase 5)**: Depends on Phases 3 and 4 both being complete.

### Within Phase 2 (Foundational)

- T001 → T002 (migrate after creating the migration)
- T002 → T003 (model needs the table to exist to be exercised, though the file itself can be
  written in parallel with T002 running)
- T003, T004, T005 can be written in parallel ([P]) — different files
- T005 → T006 (wiring line references the concern module)
- T003 → T007 (policy references the model class name)
- T003, T007 → T008 (controller uses both model and policy)
- T008 → T009 (route wires to the controller)
- T010, T011 can be written in parallel ([P]) — different files
- T011 → T012
- T013 → T014 (migrate after creating the migration)
- T014 → T015 (model needs the table to exist to be exercised, though the file itself can be
  written in parallel with T014 running)
- T015, T017 can be written in parallel ([P]) — different files
- T004 → T016 (same `account.rb` concern file; sequence the two edits, don't run them concurrently)
- T015, T017 → T018 (controller uses both model and policy)
- T018 → T019 (route wires to the controller)
- T020, T021, T022 can be written in parallel ([P]) — different files
- T022 → T023

### Parallel Opportunities

- T003, T004, T005 (backend model/concerns, different files)
- T007 (policy) can be written in parallel with T004/T005 once T003 exists
- T010, T011 (frontend API client + Vuex module, different files) in parallel with backend T003-T009
- T015, T017, T020, T021, T022 (currency model/policy/frontend, different files) in parallel with
  each other and with the card-field-config track T003-T012, once T014 has landed
- T033, T034 (Polish lint passes) in parallel

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Backend model + concerns, in parallel once T001/T002 land:
Task: "Create PipelineCardFieldConfig model in custom/app/models/pipeline_card_field_config.rb"
Task: "Add has_many :pipeline_card_field_configs to custom/app/models/custom/concerns/account.rb"
Task: "Create custom/app/models/custom/concerns/custom_attribute_definition.rb"

# Frontend, in parallel with all backend work:
Task: "Create app/javascript/dashboard/api/pipelineCardFieldConfigs.js"
Task: "Create app/javascript/dashboard/store/modules/pipelineCardFieldConfigs/{actions,mutations,getters,index}.js"

# Currency setting track, in parallel once T014 lands:
Task: "Create PipelineCurrencySetting model in custom/app/models/pipeline_currency_setting.rb"
Task: "Create PipelineCurrencySettingPolicy in custom/app/policies/pipeline_currency_setting_policy.rb"
Task: "Create app/javascript/dashboard/constants/pipelineCurrency.js"
Task: "Create app/javascript/dashboard/api/pipelineCurrencySetting.js"
Task: "Create app/javascript/dashboard/store/modules/pipelineCurrencySetting/{actions,mutations,getters,index}.js"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (backend + Vuex modules, including the currency setting)
2. Complete Phase 3: User Story 1 (settings UI)
3. **STOP and VALIDATE**: Admin can configure fields/currency and see them persist — verify via
   API/Vuex devtools that the data is correct, even before cards render anything
4. This alone is not a complete user-visible feature (no badges yet), but proves the backend and
   settings UI are correct in isolation

### Incremental Delivery

1. Foundational → backend/API/store ready (fields + currency), testable via API calls directly
2. Add User Story 1 → admin can configure fields and currency end-to-end via UI
3. Add User Story 2 → cards render badges, currency-formatted where applicable → full feature
   complete
4. Run Polish phase → lint + quickstart validation

### Suggested Full-Feature Scope

Because both user stories are P1 in the spec, ship them together for a coherent MVP: Foundational
+ US1 + US2 + Polish is the minimum for a demoable, complete feature.

---

## Notes

- [P] tasks = different files, no dependencies
- No test tasks included — not requested in the spec; lint gates (T033, T034) and manual
  quickstart validation (T035) are the quality bar for this change
- Commit after each task or logical group
- Verify no regression to unconfigured accounts (spec FR-010 / SC-003) as part of T035
- The currency setting (T013-T023, T026, T031) is deliberately built as account-wide
  infrastructure, not a card-only construct, even though its UI currently lives in the "Card
  Fields" tab — see spec.md Amendment and Assumptions
