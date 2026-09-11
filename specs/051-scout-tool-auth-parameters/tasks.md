# Implementation Tasks: Scout Custom Tool Authentication & Visual Parameter Builder

**Feature Branch**: `051-scout-tool-auth-parameters` | **Date**: 2026-08-26 | **Spec**: [specs/051-scout-tool-auth-parameters/spec.md](file:///home/matias/Projects/chatwoot/specs/051-scout-tool-auth-parameters/spec.md) | **Plan**: [specs/051-scout-tool-auth-parameters/plan.md](file:///home/matias/Projects/chatwoot/specs/051-scout-tool-auth-parameters/plan.md)

---

## Phase 1: Setup (Database & Model Foundation)

**Purpose**: Database schema expansion and base model validation for authentication modes and parameter names.

- [x] T001 Create migration to add `auth_type` column to `ichatr_scout_tools` in db/migrate/21260826180000_add_auth_type_to_ichatr_scout_tools.rb
- [x] T002 [P] Update ScoutTool model with `auth_type` inclusion validation, defaults, and masked credentials helpers in custom/app/models/scout_tool.rb
- [x] T003 [P] Add backend safeguard validation on ScoutTool model for `parameter_schema` property names — reject names that don't match `/^[a-zA-Z_][a-zA-Z0-9_]*$/` or that duplicate another property in the same schema — in custom/app/models/scout_tool.rb

---

## Phase 2: Foundational (Backend Execution & Controller)

**Purpose**: Core backend request execution, controller endpoint handling, and localized error messages for all authentication modes.

**⚠️ CRITICAL**: Foundational tasks must complete before user story UI implementation begins.

- [x] T004 [P] Update HttpRequestExecutor service to format Bearer, Basic, API Key, and None authentication headers in custom/app/services/custom/scout/tools/http_request_executor.rb
- [x] T005 [P] Update ScoutToolsController to permit `auth_type`, preserve unchanged masked credentials on update, and forward auth to test endpoint in custom/app/controllers/api/v1/accounts/scout_tools_controller.rb
- [x] T006 [P] Add backend (Rails) localized validation error messages for `auth_type` inclusion, API Key header name/value presence, and parameter name format/uniqueness in config/locales/en.yml and config/locales/pt_BR.yml
- [x] T007 [P] Add unit and controller RSpec tests for `auth_type`, parameter name/duplicate validation, `HttpRequestExecutor` header formatting, and masked secret updates in custom/spec/models/scout_tool_spec.rb, custom/spec/services/custom/scout/tools/http_request_executor_spec.rb, and custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb

**Checkpoint**: Backend foundation ready — model, controller, and executor handle all auth types and parameter schemas, with localized validation messages.

---

## Phase 3: User Story 1 - Visual Parameter Builder for Custom Tools (Priority: P1) 🎯 MVP

**Goal**: Enable administrators and agents to build structured tool parameters (name, type, description, required, order) via an intuitive visual UI that compiles to JSON Schema without manual syntax editing.

**Independent Test**: Create a new tool, add multiple parameters with various data types (`string`, `number`, `integer`, `boolean`, `array`, `object`), reorder them, toggle required flags, verify strict identifier validation rejects spaces/hyphens, verify duplicate names are rejected, and verify compiled JSON Schema is saved correctly and reflects the chosen order.

### Implementation for User Story 1

- [x] T008 [P] [US1] Add bilingual localization keys for visual parameter builder in app/javascript/dashboard/i18n/locale/en/scout.json and app/javascript/dashboard/i18n/locale/pt_BR/scout.json
- [x] T009 [US1] Implement visual parameter builder state (array-backed, order-preserving), parameter cards list, type dropdown, description input, required checkbox, delete action, and reorder controls (move up/down or drag handle) in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue
- [x] T010 [US1] Implement strict parameter identifier regex validation (`/^[a-zA-Z_][a-zA-Z0-9_]*$/`), duplicate name detection, and JSON Schema compiler (preserving parameter order as the `properties` key order) on save; remove the legacy raw `schemaJson` textarea from the modal in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue

**Checkpoint**: At this point, User Story 1 is fully functional — users can visually create, reorder, and validate parameters without touching raw JSON.

---

## Phase 4: User Story 2 - Standardized HTTP Authentication Methods (Priority: P1)

**Goal**: Provide standard authentication modes (None, Bearer Token, Basic Auth, API Key) in the modal with dynamic credential inputs, client-side secret masking, and secure encrypted persistence.

**Independent Test**: Configure a tool with each authentication type, verify the corresponding credential fields appear (and no free-form headers field is present), verify existing secrets display as `••••••••` upon editing, and verify credentials remain encrypted at rest.

### Implementation for User Story 2

- [x] T011 [P] [US2] Add bilingual localization keys for authentication types and credential inputs in app/javascript/dashboard/i18n/locale/en/scout.json and app/javascript/dashboard/i18n/locale/pt_BR/scout.json
- [x] T012 [US2] Implement Authentication Type dropdown and dynamic credential input fields (Token for Bearer; Username/Password for Basic; Header Name/Value for API Key); remove the legacy free-form raw `headersJson` textarea from the modal in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue
- [x] T013 [US2] Implement secret masking (`••••••••`), credential payload serialization, and unchanged secret preservation logic in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue

**Checkpoint**: User Stories 1 AND 2 are complete — tools can be configured with structured authentication and visual parameters, with no raw-JSON fields remaining in the modal.

---

## Phase 5: User Story 3 - Testing Connection with Configured Authentication and Parameters (Priority: P2)

**Goal**: Pre-populate the test playground with intelligent sample values based on defined visual parameters, and execute live test requests using the configured authentication mode.

**Independent Test**: Define parameters and an authentication mode, open the test section, verify default sample JSON matches the parameter types, and execute a test request confirming remote endpoint receives proper authentication headers.

### Implementation for User Story 3

- [x] T014 [P] [US3] Implement dynamic test payload sample generation based on defined visual parameters and types in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue
- [x] T015 [US3] Update test connection submission payload in ScoutToolModal.vue to transmit `auth_type` and credential objects to ScoutAPI.testTool in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue

**Checkpoint**: User Story 3 complete — operators can test connections with dynamic sample payloads and live authentication.

---

## Phase 6: User Story 4 - Best-Effort Conversion of Development-Era Tools (Priority: P3)

**Goal**: Automatically parse and populate existing development-era tools into the visual parameter builder and authentication dropdown when opened for editing.

**Independent Test**: Load a tool created prior to this feature with legacy JSON Schema properties and Bearer/Basic headers, confirming fields map correctly into the visual builder.

### Implementation for User Story 4

- [x] T016 [US4] Implement schema and header decompilation helpers to populate visual parameters and detect standard Bearer/Basic/API Key headers when opening existing tools in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue

**Checkpoint**: All user stories are complete and operational.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates, code style compliance, and full end-to-end verification.

- [x] T017 [P] Run RuboCop on all modified backend files in custom/ and db/migrate/
- [x] T018 [P] Run ESLint on modified frontend files in app/javascript/dashboard/
- [x] T019 Run full backend RSpec test suite for Scout custom tools in custom/spec/
- [x] T020 Execute manual verification walkthrough following quickstart guide in specs/051-scout-tool-auth-parameters/quickstart.md


---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1 (migration and model). Blocks all user story implementations.
- **Phase 3 (User Story 1 - Parameters)**: Can start after Phase 2.
- **Phase 4 (User Story 2 - Auth Modes)**: Can start after Phase 2 (runs in parallel or sequentially with US1).
- **Phase 5 (User Story 3 - Test Connection)**: Depends on US1 (parameters) and US2 (auth).
- **Phase 6 (User Story 4 - Legacy Parsing)**: Depends on US1 and US2 components.
- **Phase 7 (Polish)**: Runs after all user stories are complete.

### Parallel Opportunities

- T002, T003 can be developed in parallel once T001 migration is created.
- T004, T005, T006, and T007 can be developed in parallel once Phase 1 is complete.
- Localization tasks T008 and T011 can be edited in parallel with backend work.
- User Story 1 (Parameters UI) and User Story 2 (Auth UI) target distinct sections of `ScoutToolModal.vue` and can be constructed incrementally.
- Quality gate tasks T017, T018, and T019 can run in parallel during the polish phase.

---

## Implementation Strategy

### MVP Scope (User Story 1 & User Story 2)
1. Execute Phase 1 (Migration & Model setup).
2. Execute Phase 2 (Foundational backend, localized errors & tests).
3. Execute Phase 3 (User Story 1 - Visual Parameter Builder).
4. Execute Phase 4 (User Story 2 - Authentication Modes).
5. **Validate MVP**: Create and save an authenticated tool with structured, reorderable parameters, with no raw-JSON fields left in the UI.

### Incremental Delivery
1. Foundation complete → Backend fully supports `auth_type`, formatted headers, and localized validation messages.
2. Deliver US1 + US2 → Core custom tool configuration modal transformed to visual builder + auth dropdown; legacy raw-JSON fields removed.
3. Deliver US3 → Interactive playground dynamically populated from parameters with live auth testing.
4. Deliver US4 → Legacy tool decompilation.
5. Polish & Verification → 100% test pass, 0 linter errors, quickstart validated.

---

## Phase 8: Convergence

**Purpose**: Close gaps found by `/speckit-converge` between the spec/plan/tasks intent and the current implementation.

- [x] T021 Add backend safeguard validation on `ScoutTool` requiring `auth_headers` to contain the necessary non-blank credential field(s) for the selected `auth_type` (token for `bearer`; username+password for `basic`; header_name+header_value for `api_key`), with a localized error message added to config/locales/en.yml and config/locales/pt_BR.yml, in custom/app/models/scout_tool.rb per FR-012 (missing)
- [x] T022 Fix `validateForm()` in ScoutToolModal.vue to use a correct, dedicated error message (not the parameter-name key) when the tool's own Name field is blank, in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue per FR-012 (contradicts)
