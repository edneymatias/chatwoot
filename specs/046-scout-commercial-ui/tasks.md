---
description: "Task list for Scout Commercial Configuration UI implementation"
---

# Tasks: Scout Commercial Configuration UI

**Input**: Design documents from `/specs/046-scout-commercial-ui/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/rest-api.md, quickstart.md

**Tests**: Per project constitution and AGENTS.md guidelines, specs are avoided unless explicitly requested. Implementation tasks focus on production-ready code with complete validation and lint verification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- All tasks include exact file paths

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Feature registration, base routing constants, and shared API clients

- [X] T001 [P] Register scout feature flag in config/features.yml
- [X] T002 [P] Add FEATURE_FLAGS.SCOUT constant to app/javascript/dashboard/featureFlags.js
- [X] T003 [P] Create initial i18n translation files in app/javascript/dashboard/i18n/locale/en/scout.json and app/javascript/dashboard/i18n/locale/pt_BR/scout.json
- [X] T004 [P] Create Scout API client module in app/javascript/dashboard/api/scout.js

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core schema migrations, models, policies, background processing, and navigation wiring required before user stories

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Create migration for scout knowledge sources in db/migrate/21260819000007_create_ichatr_scout_knowledge_sources.rb
- [X] T006 [P] Create migration for scout required fields in db/migrate/21260819000008_create_ichatr_scout_required_fields.rb
- [X] T007 [P] Implement ScoutKnowledgeSource model with PDF 10MB validation, ActiveStorage attachment, and enums in custom/app/models/scout_knowledge_source.rb
- [X] T008 [P] Implement ScoutRequiredField model with Contact/Opportunity attribute validation in custom/app/models/scout_required_field.rb
- [X] T009 Update Scout model associations for knowledge sources and required fields in custom/app/models/scout.rb
- [X] T010 [P] Implement ScoutPolicy for role-based authorization in custom/app/policies/scout_policy.rb
- [X] T011 [P] Implement ScoutKnowledgeSourcePolicy in custom/app/policies/scout_knowledge_source_policy.rb
- [X] T012 [P] Implement ScoutToolPolicy in custom/app/policies/scout_tool_policy.rb
- [X] T013 [P] Implement Scout::KnowledgeSources::ProcessJob for URL fetch and PDF text extraction in custom/app/jobs/custom/scout/knowledge_sources/process_job.rb
- [X] T014 Update AgentRunner to read ready ScoutKnowledgeSource records instead of jsonb in custom/app/services/custom/scout/agent_runner.rb
- [X] T015 Add REST API routes for scouts, scout_inboxes, product_catalog_items, knowledge_sources, scout_tools, provider_settings, and playground_messages in config/routes.rb
- [X] T016 [P] Create base Scout Vue router configuration in app/javascript/dashboard/routes/dashboard/scout/scout.routes.js and register in app/javascript/dashboard/routes/dashboard/dashboard.routes.js
- [X] T017 [P] Add Scout entry to primary navigation sidebar in app/javascript/dashboard/components-next/sidebar/Sidebar.vue

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Admin configures a Scout end to end (Priority: P1) 🎯 MVP

**Goal**: Account admins and agents can list, create, and edit Scouts, attach/detach inboxes, manage the product catalog, add commercial knowledge sources (URLs, PDF uploads, FAQs), map funnel stages and qualification fields, and manage external REST/webhook tools from the primary-menu Scout section.

**Independent Test**: Log in as admin, create a new Scout, attach it to an inbox, add a product entry, add a knowledge source (URL and PDF), configure funnel stage mappings and select custom attribute qualification fields, create an external tool, and confirm all configuration is saved and visible on reload without touching Settings or Rails console.

### Implementation for User Story 1

- [X] T018 [P] [US1] Implement ScoutsController with CRUD (including the plain numeric `responses_quota` field, FR-012) and required fields synchronization in custom/app/controllers/api/v1/accounts/scouts_controller.rb
- [X] T019 [P] [US1] Implement ScoutInboxesController with duplicate inbox check in custom/app/controllers/api/v1/accounts/scouts/scout_inboxes_controller.rb
- [X] T020 [P] [US1] Implement ProductCatalogItemsController for JSONB catalog items in custom/app/controllers/api/v1/accounts/scouts/product_catalog_items_controller.rb
- [X] T021 [P] [US1] Implement KnowledgeSourcesController supporting URL, PDF upload, and FAQ CRUD in custom/app/controllers/api/v1/accounts/scouts/knowledge_sources_controller.rb
- [X] T022 [P] [US1] Implement ScoutToolsController for external REST/webhook tools CRUD in custom/app/controllers/api/v1/accounts/scout_tools_controller.rb
- [X] T023 [P] [US1] Create Scout list page view, visibly marking Scouts with no attached inbox as not yet live/connected, in app/javascript/dashboard/routes/dashboard/scout/pages/ScoutList.vue
- [X] T024 [US1] Create Scout detail view and navigation tabs container, visibly marking the Scout as not yet live/connected when it has no attached inbox, in app/javascript/dashboard/routes/dashboard/scout/pages/ScoutDetail.vue
- [X] T025 [P] [US1] Create Scout general settings tab component (including the `responses_quota` plain numeric field, FR-012) in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue
- [X] T026 [P] [US1] Create Scout inboxes management tab component in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutInboxesTab.vue
- [X] T027 [P] [US1] Create Scout product catalog tab and modal components in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutProductsTab.vue and ScoutProductModal.vue
- [X] T028 [P] [US1] Create Scout knowledge base tab and upload/crawl/FAQ modal in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutKnowledgeTab.vue and ScoutKnowledgeSourceModal.vue
- [X] T029 [P] [US1] Create Scout funnel and qualification fields tab component in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutFunnelTab.vue
- [X] T030 [P] [US1] Create Scout external tools list page and modal in app/javascript/dashboard/routes/dashboard/scout/pages/ScoutToolsList.vue and app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue

**Checkpoint**: At this point, User Story 1 is fully functional and delivers the core MVP commercial configuration experience.

---

## Phase 4: User Story 2 - Agent access mirrors admin for business config, but not for LLM credentials (Priority: P2)

**Goal**: Non-admin agents can access all commercial configuration screens in the primary menu (Scouts, products, knowledge base, funnel, tools, playground), but cannot view or edit LLM provider and API key settings, which are restricted to administrators in a dedicated Settings screen.

**Independent Test**: Log in as a non-admin agent and verify that all Scout primary-menu pages are accessible and editable, while navigating to `/settings/scout` (or provider settings API) is rejected with access denied. Log in as an admin and verify that `/settings/scout` is accessible and updates provider, model, and API key overrides.

### Implementation for User Story 2

- [X] T031 [P] [US2] Implement ProviderSettingsController restricting provider and API key management to administrators in custom/app/controllers/api/v1/accounts/scouts/provider_settings_controller.rb
- [X] T032 [US2] Update ScoutsController to exclude api_key_override from responses and sanitize provider params for non-admins in custom/app/controllers/api/v1/accounts/scouts_controller.rb
- [X] T033 [P] [US2] Create admin-only settings route and page for Scout LLM provider configuration in app/javascript/dashboard/routes/dashboard/settings/scout/scout.routes.js and app/javascript/dashboard/routes/dashboard/settings/scout/Index.vue
- [X] T034 [US2] Enforce role-based route permissions across primary-menu Scout routes and settings routes in app/javascript/dashboard/routes/dashboard/scout/scout.routes.js and app/javascript/dashboard/routes/dashboard/settings/settings.routes.js

**Checkpoint**: At this point, User Stories 1 and 2 work together with strict role-based access control.

---

## Phase 5: User Story 3 - Test a Scout's tool-calling behavior in a playground (Priority: P3)

**Goal**: Provide an interactive Playground screen where admins and agents can send test messages to a Scout, observe real-time assistant responses, and inspect executed tool calls (native tools simulated without DB persistence, external tools calling live endpoints).

**Independent Test**: Open the Playground for a configured Scout, send a message that triggers a native tool (e.g. create private note) and verify the simulated tool call appears in the chat without modifying database records. Send a message triggering an external REST/webhook tool and verify the real live endpoint response or failure status is displayed in the chat view.

### Implementation for User Story 3

- [X] T035 [P] [US3] Update native tools with playground mode skipping persistence in custom/app/services/custom/scout/tools/create_private_note.rb, update_contact.rb, manage_opportunity.rb, move_opportunity_stage.rb, handover_to_human.rb
- [X] T036 [US3] Implement Scout::PlaygroundRunner service orchestrating non-persistent test chat sessions in custom/app/services/custom/scout/playground_runner.rb
- [X] T037 [US3] Implement PlaygroundMessagesController handling test message dispatch in custom/app/controllers/api/v1/accounts/scouts/playground_messages_controller.rb
- [X] T038 [P] [US3] Create Scout Playground page and interactive chat component in app/javascript/dashboard/routes/dashboard/scout/pages/ScoutPlayground.vue and app/javascript/dashboard/components-next/Scout/pageComponents/ScoutPlaygroundChat.vue

**Checkpoint**: All three user stories are now complete and functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Translations completion, edge case safeguards, linting verification, and end-to-end scenario validation

- [X] T039 [P] Complete synchronous English and Portuguese translations in app/javascript/dashboard/i18n/locale/en/scout.json and app/javascript/dashboard/i18n/locale/pt_BR/scout.json
- [X] T040 [P] Add backend translation strings for Scout error messages in config/locales/en.yml and config/locales/pt_BR.yml
- [X] T041 [P] Run frontend and backend linting checks (pnpm eslint and bundle exec rubocop)
- [X] T042 [P] Run quickstart validation test scenarios from specs/046-scout-commercial-ui/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion (T005-T017)
- **User Story 2 (Phase 4)**: Depends on US1 completion (T018-T030) and Foundational policies
- **User Story 3 (Phase 5)**: Depends on US1 completion (T018-T030) and Foundational services
- **Polish (Phase 6)**: Depends on all user stories (Phases 3-5) being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Extends US1 controller/routing structures with admin-only provider isolation
- **User Story 3 (P3)**: Extends US1 Scout runtime with Playground service and interactive test UI

### Within Each User Story

- Schema/migrations and models before controllers
- Policies and controllers before frontend pages
- Reusable UI tab components before top-level route views
- Service runner updates before playground controllers

### Parallel Opportunities

- All Setup tasks marked [P] (T001-T004) can run in parallel
- Migrations and models in Foundational phase marked [P] (T005-T008, T010-T013) can run in parallel
- Controllers in User Story 1 marked [P] (T018-T022) can run in parallel
- UI tab components in User Story 1 marked [P] (T025-T030) can run in parallel
- Native tool playground updates in User Story 3 marked [P] (T035) can run in parallel with frontend playground components (T038)
- Translation tasks in Polish marked [P] (T039, T040) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch backend controllers in parallel:
Task: "Implement ScoutsController with CRUD in custom/app/controllers/api/v1/accounts/scouts_controller.rb"
Task: "Implement ScoutInboxesController in custom/app/controllers/api/v1/accounts/scouts/scout_inboxes_controller.rb"
Task: "Implement ProductCatalogItemsController in custom/app/controllers/api/v1/accounts/scouts/product_catalog_items_controller.rb"
Task: "Implement KnowledgeSourcesController in custom/app/controllers/api/v1/accounts/scouts/knowledge_sources_controller.rb"
Task: "Implement ScoutToolsController in custom/app/controllers/api/v1/accounts/scout_tools_controller.rb"

# Launch frontend tab components in parallel:
Task: "Create Scout general settings tab in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue"
Task: "Create Scout inboxes management tab in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutInboxesTab.vue"
Task: "Create Scout product catalog tab in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutProductsTab.vue"
Task: "Create Scout knowledge base tab in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutKnowledgeTab.vue"
Task: "Create Scout funnel and qualification fields tab in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutFunnelTab.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T017) — **CRITICAL**: Foundation ready
3. Complete Phase 3: User Story 1 (T018-T030)
4. **STOP and VALIDATE**: Test User Story 1 independently using step 1 of `quickstart.md`
5. Deploy/demo commercial configuration MVP

### Incremental Delivery

1. Complete Setup + Foundational → Core data structures and navigation ready
2. Add User Story 1 → Scout CRUD, products, knowledge base, funnel, tools (MVP!)
3. Add User Story 2 → Admin-only LLM credentials isolation and role verification
4. Add User Story 3 → Playground testing with simulated native tools and real external tools
5. Complete Polish → Full English/Portuguese i18n, lint checks, and quickstart verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Strict checklist format ` - [ ] [TaskID] [P?] [Story?] Description with file path` followed across all tasks
- Stop at any checkpoint to validate story independently
- Every customization adheres to this fork's constitution (all Ruby in `custom/`, no core `app/` or `enterprise/` modifications)

## Phase 7: Convergence

- [ ] T043 [US1] Guard against deleting/unassigning a PipelineStage referenced by a Scout's default/qualified/unqualified stage: add an in-use check in custom/app/models/pipeline_stage.rb (or custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb) and surface the conflict in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutFunnelTab.vue per spec.md Edge Cases (missing)
- [ ] T044 [US1] Fix Api::V1::Accounts::Scouts::ScoutInboxesController#create to return 422 with a clear error instead of silently reassigning an inbox already attached to another Scout, and add a confirmation step in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutInboxesTab.vue to let the user explicitly move the inbox per FR-002 / contracts/rest-api.md (contradicts)
