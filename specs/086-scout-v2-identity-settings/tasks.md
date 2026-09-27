---
description: "Task list for Scout V2 Identity and Style Settings implementation"
---

# Tasks: Scout V2 Identity and Style Settings

**Input**: Design documents from `/specs/086-scout-v2-identity-settings/` (`plan.md`, `spec.md`, `data-model.md`, `research.md`, `contracts/`, `quickstart.md`)

**Prerequisites**: `plan.md`, `spec.md`, `data-model.md`, `research.md`, `contracts/identity_section.md`, `contracts/scouts_api.md`, `contracts/general_settings_ui.md`, `quickstart.md`

**Tests**: Test-Driven Development (Constitution VI, VII, VIII) is non-negotiable for this repository. All behavior changes MUST be preceded by a failing test at a real entry point before implementation code is written. Translation keys are behavior (FR-013, FR-021): they are added only after the test asserting the translated text has been observed failing.

**Organization**: Tasks are grouped by user story. Stories run in dependency order — US1 (P1), then US3 (P3, the API the screen saves through), then US2 (P2) — as recorded in `plan.md` ("Built before US2 so the screen has a working endpoint").

## Format: `- [ ] [ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., `[US1]`, `[US2]`, `[US3]`)
- Every task includes exact file paths

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Core database schema migration adding `role` and `scope` to `ichatr_scouts` table that MUST be complete before ANY user story can be implemented. There is no separate setup phase: backend and UI translation keys are delivered inside the story that tests them (Constitution VI/VIII).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete and the schema is cleanly regenerated.

- [x] T001 Create additive database migration for nullable text columns role and scope (default nil) on ichatr_scouts in db/migrate/21260927000000_add_role_and_scope_to_ichatr_scouts.rb
- [x] T002 Run database migrations in development and test environments and regenerate schema in db/schema.rb per AGENTS.md guidelines (verifying no n8n triggers/functions leak)

**Checkpoint**: Foundation ready - user story implementation can now begin.

---

## Phase 2: User Story 1 - The new version introduces itself with the account's own Role and Scope (Priority: P1) 🎯 MVP

**Goal**: Allow Scout V2 instructions to reflect account-specific Role and Scope in the `[Identity]` section with independent fallbacks to Default Identity when empty, while strictly isolating Persona and preserving legacy V1 prompt invariance.

**Independent Test**: Can be fully tested by setting `role` and `scope` directly on a `Scout` record; verifying `Custom::ScoutV2::Instructions::IdentityBuilder.call` output reflects the 4 combinations per `contracts/identity_section.md`; verifying `Custom::ScoutV2::Instructions::Builder.call` contains no Persona content across all sections and keeps `[Safety]`; verifying `Custom::Scout::SystemPromptsService.build` output is byte-identical under `freeze_time` before and after setting the 5 fields; verifying in `turn_runner_spec.rb` that saved role/scope reach composed instructions.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation (Constitution VI & VIII)**

- [x] T003 [P] [US1] Add unit tests for Role and Scope normalization (ends stripped, internal line breaks preserved, whitespace-only ⇒ nil) and length validation (500 after normalization accepted, 501 rejected with a :too_long error, `count: 500`) in custom/spec/models/scout_spec.rb
- [x] T004 [P] [US1] Create unit tests for IdentityBuilder asserting the exact section text for the four Role/Scope combinations, multi-line Scope/Role lists, and Persona absence in custom/spec/services/custom/scout_v2/instructions/identity_builder_spec.rb
- [x] T005 [P] [US1] Add assertions that, with Role/Scope both empty and both filled, no Persona content appears in any of the four instruction sections and `[Safety]` keeps its anti-hallucination and commercial-scope rules (FR-004, FR-006) in custom/spec/services/custom/scout_v2/instructions/builder_spec.rb
- [x] T006 [P] [US1] Add frozen-time regression test asserting V1 prompt byte-for-byte invariance before and after setting the five fields, with Persona still inside `<account_custom_instructions>`, in custom/spec/services/custom/scout/system_prompts_service_spec.rb
- [x] T007 [P] [US1] Add integration test verifying saved role and scope reach composed instructions passed to RubyLLM chat in custom/spec/services/custom/scout_v2/turn_runner_spec.rb

### Implementation for User Story 1

- [x] T008 [P] [US1] Implement normalization (normalizes :role, :scope, with: ->(v) { v.strip.presence }) and validation (validates :role, :scope, length: { maximum: 500 }) in custom/app/models/scout.rb
- [x] T009 [P] [US1] Implement statement replacement and fallback logic for intro, purpose (role), and scope in Custom::ScoutV2::Instructions::IdentityBuilder in custom/app/services/custom/scout_v2/instructions/identity_builder.rb

**Checkpoint**: At this point, User Story 1 is fully functional and testable independently (MVP scope).

---

## Phase 3: User Story 3 - Invalid Identity or style values are rejected at the settings API without saving anything (Priority: P3)

**Goal**: Permit the 5 fields in `scout_params`; reject invalid enum values (`tone`, `response_length`, including integer 1, numeric string "1", `""` and `null`) at the controller request boundary on both create and update with translated 422 messages before anything touches the record; reject out-of-bounds `role`/`scope` (>500 chars after strip) at model validation; leave all attributes and required definitions untouched on rejection. Built before US2 because the screen saves through this endpoint.

**Independent Test**: Execute request specs against `Api::V1::Accounts::ScoutsController` (`PATCH` and `POST`): verify valid writes persist and return the 5 fields; verify rejections for `tone` (`"bogus"`, `1`, `"1"`, `""`, `null`), `response_length` (`"long"`, `1`, `"1"`, `""`, `null`), and `role`/`scope` (> 500 chars); verify name and required custom attribute definitions are unchanged after rejection; verify a rejected `POST` creates no scout; verify whitespace-only role/scope stores null; verify the exact en and pt_BR message for each of the four rejected attributes.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation (Constitution VI & VIII)**

- [x] T010 [US3] Add request specs in custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb covering: valid create/update/show of the five fields; the PATCH rejection matrix per the Independent Test, each sent with a `name` change and `required_custom_attribute_definition_ids` (both unchanged afterwards); a `POST` with `tone: 1` returning 422 and creating no scout; Role/Scope 501 rejected and 500 + padding accepted and stored trimmed; whitespace-only ⇒ `null`; and the exact message from `contracts/scouts_api.md` for each of `tone`, `response_length`, `role`, `scope`, under an en requester and under a pt_BR requester

### Implementation for User Story 3

- [x] T011 [US3] Implement request-boundary enum validation before_action (create and update) and permit role, scope, tone, response_length, greeting in custom/app/controllers/api/v1/accounts/scouts_controller.rb
- [x] T012 [P] [US3] Add `activerecord.attributes.scout.{role,scope,tone,response_length}` and `activerecord.errors.models.scout.attributes.{tone,response_length}.inclusion` / `{role,scope}.too_long` in English in config/locales/en.yml
- [x] T013 [P] [US3] Add the same keys in Brazilian Portuguese in config/locales/pt_BR.yml

**Checkpoint**: User Stories 1 and 3 work independently; the settings API accepts, returns and guards the five fields.

---

## Phase 4: User Story 2 - Administrators configure Identity and style from the scout settings screen (Priority: P2)

**Goal**: Provide an always-visible "New version of the Scout" section in `ScoutGeneralSettings.vue` with inputs for Role, Scope, Tone, Response length, and Greeting, including character counters (500 limit), translated option lists, help texts, and payload integration with `ScoutAPI.update`.

**Independent Test**: Mount `ScoutGeneralSettings.vue` in Vitest with `withFullI18n`; verify every observable behavior listed in `contracts/general_settings_ui.md` (always-visible section, prefill and `0 / 500` counters for null values, exact Tone/Response length options, 500-char limit, save payload, concrete hint texts, en and pt_BR rendering).

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation (Constitution VI & VIII)**

- [x] T014 [US2] Create component tests in app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutGeneralSettings.spec.js covering contract behaviors 1–7: visibility without any flag; prefill (and empty fields with `0 / 500` counters for `null` values); exactly 5 Tone and 3 Response length options in contract order; `maxlength="500"` and `500 / 500`; save payload with the five keys and edited values, and `greeting: null` when Greeting is empty; en hints asserted as literal phrases (not read back from the catalog) — each field's hint mentions the new version and the Greeting hint advises leaving it blank when the inbox already greets; and pt_BR rendering by switching `locale.value` on the i18n instance returned by `withFullI18n()` and assert…

### Implementation for User Story 2

- [x] T015 [P] [US2] Add English UI locale strings under SCOUT.GENERAL for V2 section title, description, labels, placeholders, hints, and option lists in app/javascript/dashboard/i18n/locale/en/scout.json
- [x] T016 [P] [US2] Add Brazilian Portuguese UI locale strings under SCOUT.GENERAL for V2 section title, description, labels, placeholders, hints, and option lists in app/javascript/dashboard/i18n/locale/pt_BR/scout.json
- [x] T017 [US2] Implement V2 settings section with TextArea (role, scope, maxlength 500, counter), Select (tone, response_length), Input (greeting), and handleSave payload (greeting sent as `null` when empty) in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue

**Checkpoint**: All user stories are now independently functional and verified against contracts.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Code style compliance and verification that affect multiple user stories across the repository.

- [x] T018 [P] Run RuboCop on modified Ruby files: custom/app/models/scout.rb, custom/app/controllers/api/v1/accounts/scouts_controller.rb, custom/app/services/custom/scout_v2/instructions/identity_builder.rb, db/migrate/21260927000000_add_role_and_scope_to_ichatr_scouts.rb, custom/spec/models/scout_spec.rb, custom/spec/services/custom/scout_v2/instructions/identity_builder_spec.rb, custom/spec/services/custom/scout_v2/instructions/builder_spec.rb, custom/spec/services/custom/scout/system_prompts_service_spec.rb, custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb, custom/spec/services/custom/scout_v2/turn_runner_spec.rb
- [x] T019 [P] Run ESLint on modified Vue components and spec files in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutGeneralSettings.vue and app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutGeneralSettings.spec.js
- [x] T020 Fast-forward `develop` (`git fetch upstream develop --tags && git merge --ff-only upstream/develop`), then run `--check` and `--audit` in bin/sync-custom-module-hooks
- [x] T021 Execute targeted backend and frontend test validation suite per quickstart.md in specs/086-scout-v2-identity-settings/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 1)**: No dependencies - BLOCKS all user stories because the database columns `role` and `scope` on `ichatr_scouts` must exist for model and controller operations.
- **User Story 1 (Phase 2)**: Depends on Phase 1.
- **User Story 3 (Phase 3)**: Depends on Phase 1 and Phase 2 (Role/Scope normalization and length validation live on the model).
- **User Story 2 (Phase 4)**: Depends on Phase 3 — until T011 permits the five fields, `scout_params` silently drops them and a save from the screen persists nothing (US2 acceptance scenario 4, FR-018, FR-019). The component spec mocks `ScoutAPI`, so T014 can be written earlier, but the story is only complete after Phase 3.
- **Polish (Phase 5)**: Depends on all user story implementations being completed.

### User Story Dependencies

- **User Story 1 (P1)**: Independent of US2 and US3. Establishes the `role` and `scope` model attributes and the `IdentityBuilder` prompt generation engine.
- **User Story 3 (P3)**: Guards the settings API controller boundary (`scouts_controller.rb`) for writes from the screen or external integrations. Relies on model validations from US1.
- **User Story 2 (P2)**: Saves through the API contract delivered by US3.

### Within Each User Story

- Tests MUST be written FIRST and observed failing before implementation (Constitution VI & VIII).
- Translation keys (backend and UI) are added only after the test asserting their text is observed failing.
- Models and validations before controller endpoints.
- Story complete and verified before moving to next phase.

### Parallel Opportunities

- **Phase 2 (Tests)**: T003, T004, T005, T006, and T007 can all be written concurrently across their independent spec files.
- **Phase 2 (Implementation)**: T008 (`scout.rb`) and T009 (`identity_builder.rb`) touch different files.
- **Phase 3 (Implementation)**: T012 (`config/locales/en.yml`) and T013 (`config/locales/pt_BR.yml`) can run in parallel with each other and with T011.
- **Phase 4 (Translations)**: T015 (`locale/en/scout.json`) and T016 (`locale/pt_BR/scout.json`) can be prepared concurrently.
- **Phase 5 (Polish)**: T018 (RuboCop) and T019 (ESLint) can execute in parallel.

---

## Parallel Example: User Story 1

```bash
# Launch all test writing for User Story 1 in parallel:
Task: "T003 [P] [US1] Add unit tests for Role and Scope normalization in custom/spec/models/scout_spec.rb"
Task: "T004 [P] [US1] Create unit tests for IdentityBuilder in custom/spec/services/custom/scout_v2/instructions/identity_builder_spec.rb"
Task: "T005 [P] [US1] Add assertions for Persona absence and Safety presence in custom/spec/services/custom/scout_v2/instructions/builder_spec.rb"
Task: "T006 [P] [US1] Add frozen-time regression test in custom/spec/services/custom/scout/system_prompts_service_spec.rb"
Task: "T007 [P] [US1] Add integration test in custom/spec/services/custom/scout_v2/turn_runner_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Foundational migration (`ichatr_scouts` table columns).
2. Complete Phase 2: User Story 1 (IdentityBuilder + Scout model normalization and validations + specs).
3. **STOP and VALIDATE**: Run targeted RSpec suite for US1 per `quickstart.md` §2. Identity generation is now fully functional on the server.

### Incremental Delivery

1. Foundational → Database schema ready.
2. User Story 1 → Model normalization and V2 IdentityBuilder logic verified (MVP!).
3. User Story 3 → Strong params, API boundary validation and translated 422 rejections active.
4. User Story 2 → General settings Vue UI component, counters, and translations active, saving through the US3 endpoint.
5. Phase 5: Polish → RuboCop, ESLint, sync-hooks, and targeted end-to-end regression validation green.

---

## Notes

- `[P]` tasks = different files, no dependencies.
- `[Story]` label (`[US1]`, `[US2]`, `[US3]`) maps task directly to user stories in `spec.md`.
- No story labels on Foundational or Polish phases.
- Every task description includes exact, concrete file paths.
- Tests must fail for the right reason before implementation code is added.

---

## Phase 6: Convergence

- [x] T022 [US3] Add JSON-typed request specs (`as: :json`) in custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb that send `tone`/`response_length` as the integer `1` and as `null`, both wrapped (`{ scout: { … } }`) and unwrapped (auto-wrapped by `wrap_parameters`), each with a `name` change, asserting 422, the translated out-of-list message, and the scout unchanged; the current matrix posts form-encoded params, so `1` reaches the controller as the string `"1"` and the integer case is never exercised per US3/AC3, SC-006 (partial)
- [x] T023 [US2] Extend the prefill case in app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutGeneralSettings.spec.js to assert the Tone and Response length `<select>` values equal the scout's non-default `professional`/`thorough` and the Greeting `<input>` shows the stored greeting; today only Role/Scope textareas are asserted, so a component that ignores `scout.tone`/`scout.response_length` still passes, per US2/AC6, FR-018 (partial)
