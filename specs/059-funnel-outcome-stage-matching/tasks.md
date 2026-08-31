# Tasks: Funnel Outcome-Stage Matching for Scout

**Input**: Design documents from `/specs/059-funnel-outcome-stage-matching/`
**Prerequisites**: [plan.md](file:///home/matias/Projects/chatwoot/specs/059-funnel-outcome-stage-matching/plan.md), [spec.md](file:///home/matias/Projects/chatwoot/specs/059-funnel-outcome-stage-matching/spec.md), [research.md](file:///home/matias/Projects/chatwoot/specs/059-funnel-outcome-stage-matching/research.md), [data-model.md](file:///home/matias/Projects/chatwoot/specs/059-funnel-outcome-stage-matching/data-model.md), [quickstart.md](file:///home/matias/Projects/chatwoot/specs/059-funnel-outcome-stage-matching/quickstart.md)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- File paths are exact and relative to repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify repository environment and baseline test fixtures

- [x] T001 [P] Run `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb` to confirm the existing suite is green before making any changes (pre-feature baseline)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure baseline validation

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Confirm the pre-existing disqualification-is-review-queue bullet (including the "registre-o como nota interna" internal-note clause, FR-002) and the automatic-handoff-on-qualify bullet (FR-003) are present and unmodified in `build_funnel_guidelines_lines`'s current output in `custom/app/services/custom/scout/system_prompts_service.rb` — this feature depends on both but does not change them; add an assertion for the untested "nota interna" clause to `custom/spec/services/custom/scout/system_prompts_service_spec.rb` if not already covered

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel or sequentially

---

## Phase 3: User Story 1 - Outcome-Driven Stage Transitions (Priority: P1) 🎯 MVP

**Goal**: Scout compares turn outcomes against configured stage descriptions and moves the opportunity when a clear match occurs, applying the closest-match tie-break rule and forward-only progression guard.

**Independent Test**: Run conversation where lead declines/postpones vs confirms against configured stage descriptions; verify opportunity transitions to the matching stage without marking lost/won.

### Tests for User Story 1

- [x] T003 [P] [US1] Add unit test assertions for outcome-driven stage matching, tie-breaking, and forward-only progression in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

### Implementation for User Story 1

- [x] T004 [US1] Implement outcome-stage comparison guideline bullet with tie-breaking and forward-only rules in `custom/app/services/custom/scout/system_prompts_service.rb`

**Checkpoint**: User Story 1 prompt guidelines are generated and verified via unit tests

---

## Phase 4: User Story 2 - Correct Belief About Available Capabilities (Priority: P1)

**Goal**: Scout recognizes its opportunity management tools are sufficient to record any qualification data (including dates and scheduling info) without assuming external capabilities are missing or triggering redundant manual handoffs.

**Independent Test**: Verify Scout records dates/times and advances stages using internal tools rather than citing missing scheduling tools or handing off to humans prematurely.

### Tests for User Story 2

- [x] T005 [P] [US2] Add unit test assertions for tool sufficiency and qualification data capture in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

### Implementation for User Story 2

- [x] T006 [US2] Implement tool-sufficiency guideline bullet for qualification data and dates in `custom/app/services/custom/scout/system_prompts_service.rb`

**Checkpoint**: User Stories 1 and 2 deliver complete P1 autonomous qualification capabilities

---

## Phase 5: User Story 3 - Focused, Advancing Conversational Pace (Priority: P2)

**Goal**: Scout asks at most one question per turn and always closes with a question/next step unless the lead signaled a pause, maintaining conversational momentum without stacking questions or producing inert replies.

**Independent Test**: Review generated prompt guardrails to ensure responses are instructed to ask only one question per turn and maintain advancing conversation flow.

### Tests for User Story 3

- [x] T007 [P] [US3] Add unit test assertions for conversational pacing and single-question rule in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

### Implementation for User Story 3

- [x] T008 [US3] Implement "Ritmo e condução da conversa" guardrail bullet in `custom/app/services/custom/scout/system_prompts_service.rb`

**Checkpoint**: User Story 3 ensures natural, focused conversational pacing

---

## Phase 6: User Story 4 - Discreet, Natural Action Confirmations (Priority: P2)

**Goal**: Confirmations of recorded/updated actions use natural customer-facing language without leaking internal opportunity IDs, technical attribute keys, or system log phrasing.

**Independent Test**: Verify prompt guardrails instruct plain customer-facing confirmations without opportunity IDs, raw attribute names, or technical logs.

### Tests for User Story 4

- [x] T009 [P] [US4] Add unit test assertions for natural action confirmation and internal ID masking in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

### Implementation for User Story 4

- [x] T010 [US4] Update "Confirmação de ação" guardrail bullet in `custom/app/services/custom/scout/system_prompts_service.rb`

**Checkpoint**: User Story 4 prevents internal jargon and CRM identifiers in customer messages

---

## Phase 7: User Story 5 - Natural Clarification for List-Based Fields (Priority: P3)

**Goal**: Scout asks open, conversational questions when collecting list-based values rather than reciting configured options as a multiple-choice menu, while still mapping free-text answers internally.

**Independent Test**: Verify prompt guardrails instruct open-ended phrasing for list attributes rather than multiple-choice recitation.

### Tests for User Story 5

- [x] T011 [P] [US5] Add unit test assertions for open-question formulation on list attributes in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

### Implementation for User Story 5

- [x] T012 [US5] Update "Esclarecimento" guardrail bullet in `custom/app/services/custom/scout/system_prompts_service.rb`

**Checkpoint**: User Story 5 enables natural clarification without menu enumeration

---

## Phase 8: User Story 6 - Operator Guidance for Actionable Stage Descriptions (Priority: P3)

**Goal**: Display an unconditional helper hint below the stage description label in both Add and Edit pipeline stage modals in English and Portuguese, guiding operators on how AI uses stage descriptions.

**Independent Test**: Open Add and Edit stage modals in EN and pt-BR; verify helper hint text appears under the description label regardless of whether the field is empty.

### Implementation for User Story 6

- [x] T013 [P] [US6] Add `DESC_HINT` i18n translation keys in `app/javascript/dashboard/i18n/locale/en/opportunities.json` and `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json` (fork-owned locales only — this fork does not use Crowdin; do not touch `pt/opportunities.json` or other Crowdin-managed locales, per constitution Personalization Boundaries)
- [x] T014 [P] [US6] Add static stage description helper hint paragraph in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue`
- [x] T015 [P] [US6] Add static stage description helper hint paragraph in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`

**Checkpoint**: User Story 6 provides operator guidance in UI across all supported locales

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates, linting, and end-to-end smoke testing

- [x] T016 [P] Run RuboCop linting and line-length checks on backend service and spec in `custom/app/services/custom/scout/system_prompts_service.rb` and `custom/spec/services/custom/scout/system_prompts_service_spec.rb`
- [x] T017 [P] Run ESLint checks on modified Vue components in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue` and `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`
- [x] T018 Run complete backend RSpec suite for SystemPromptsService in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`
- [x] T019 Execute manual behavioral smoke test with `PlaygroundRunner` and UI verification per `specs/059-funnel-outcome-stage-matching/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - baseline check
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories 1-5 (backend prompt service) can be implemented sequentially (P1 → P2 → P3) or in parallel
  - User story 6 (frontend UI + i18n) is completely decoupled from backend prompt changes and can run in parallel with US1-US5
- **Polish (Final Phase)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 - Core outcome-matching guideline in `build_funnel_guidelines_lines`
- **User Story 2 (P1)**: Can start after Phase 2 - Tool-sufficiency guideline in `build_funnel_guidelines_lines`
- **User Story 3 (P2)**: Can start after Phase 2 - Conversational pacing in `guardrails_section`
- **User Story 4 (P2)**: Can start after Phase 2 - Action confirmation clause in `guardrails_section`
- **User Story 5 (P3)**: Can start after Phase 2 - Clarification clause in `guardrails_section`
- **User Story 6 (P3)**: Can start after Phase 2 - Independent frontend changes in Vue modals and locale JSONs

### Within Each User Story

- Test assertions added in `system_prompts_service_spec.rb` before or alongside prompt updates
- Verify line lengths comply with RuboCop 150-char limit via string backslash continuations
- Ensure unconditional rendering of UI hint in both Add and Edit modals

### Parallel Opportunities

- All test writing tasks ([P]) can run in parallel
- Frontend tasks (T013, T014, T015) can run in parallel with backend prompt tasks (T003-T012)
- Locale file updates (T013) can run in parallel across `en` and `pt_BR` (the only two fork-owned locales; no other locale is touched)
- Linting checks (T016, T017) can run in parallel

---

## Parallel Example: User Story 6 & User Story 1

```bash
# Developer A working on Backend Prompt & Tests (US1):
Task: "Add unit test assertions for outcome-driven stage matching in custom/spec/services/custom/scout/system_prompts_service_spec.rb"
Task: "Implement outcome-stage comparison guideline bullet in custom/app/services/custom/scout/system_prompts_service.rb"

# Developer B working on Frontend UI & i18n (US6):
Task: "Add DESC_HINT i18n translation keys in app/javascript/dashboard/i18n/locale/en/opportunities.json and pt_BR/opportunities.json"
Task: "Add static stage description helper hint paragraph in AddPipelineStage.vue and EditPipelineStage.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup & Phase 2: Foundational baseline
2. Complete Phase 3: User Story 1 (Outcome-driven stage matching prompt guideline + tests)
3. **VALIDATE**: Run RSpec for `SystemPromptsService` to verify MVP prompt generation
4. Deploy/demonstrate outcome-driven transitions

### Incremental Delivery

1. **Increment 1 (MVP)**: US1 (Outcome-stage matching)
2. **Increment 2**: US2 (Tool capability & scheduling belief)
3. **Increment 3**: US3 (Conversational pacing & single-question rule)
4. **Increment 4**: US4 (Discreet action confirmations)
5. **Increment 5**: US5 (Natural list clarifications)
6. **Increment 6**: US6 (Operator UI hint in Add/Edit stage forms)
7. **Increment 7**: Full Polish (Linting, RSpec suite, manual smoke test per quickstart)

---

## Notes

- All tasks follow strict checklist format: `- [ ] [TaskID] [P?] [Story?] Description with file path`
- No new database columns or models are introduced; changes are strictly prompt text in `SystemPromptsService`, static UI helper copy in pipeline stage modals, and corresponding test coverage
- RuboCop 150-character limit must be strictly respected via backslash string continuation

---

## Phase 10: Convergence

**Purpose**: Close gaps found by `/speckit-converge` between the implemented code and spec.md/plan.md/tasks.md

- [x] T020 [CRITICAL] Remove the erroneously-added `DESC_HINT` key from `app/javascript/dashboard/i18n/locale/pt/opportunities.json` (`pt` is a Crowdin-managed, non-fork-owned locale — this fork only maintains `en`/`pt_BR` translations for fork-owned features) per Constitution: Personalization Boundaries / FR-009 (contradicts)
- [x] T021 Add an RSpec assertion in `custom/spec/services/custom/scout/system_prompts_service_spec.rb` confirming the disqualification bullet's "registre-o como nota interna" clause is present in `build_funnel_guidelines_lines`'s output (`custom/app/services/custom/scout/system_prompts_service.rb:146`) per FR-002 (partial)
