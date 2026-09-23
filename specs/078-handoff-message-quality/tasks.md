# Tasks: Response Auditor Handoff Message Quality

**Input**: Design documents from `/specs/078-handoff-message-quality/`

**Prerequisites**: plan.md (completed), spec.md (completed), research.md (completed), data-model.md (completed), contracts/handoff-reason-mapping.md (completed), quickstart.md (completed)

**Tests**: All test tasks included per Constitution Principle VI (TDD non-negotiable for behavior changes). Tests run surgically per Principle IX (no global suite runs during iteration).

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

---

## Phase 1: Setup
*Project structure already exists; no initialization tasks needed.*

---

## Phase 2: Foundational (Code Review & Structure Analysis)

- [x] T001 Review existing code: `custom/app/services/custom/scout/action_classifier_service.rb` for system_instructions prompt structure and `ActionClassifierSchema::REASONS` enum
- [x] T002 Review existing code: `custom/app/services/custom/scout/handoff_service.rb` for `create_transfer_note` and `send_public_handoff_message` method signatures
- [x] T003 Review existing code: `custom/app/services/custom/scout/response_auditor.rb` for `execute_handoff` call site and reason threading
- [x] T004 Review existing code: `config/locales/en.yml` and `config/locales/pt_BR.yml` for existing `conversations.scout.*` namespace structure
- [x] T005 [P] Review existing test structure: `custom/spec/services/custom/scout/action_classifier_service_spec.rb` and `handoff_service_spec.rb` for existing test patterns and setup conventions
- [x] T006 Add shared plumbing in `custom/app/services/custom/scout/handoff_service.rb`, used by both US2 and US3: (1) set `@action_reason = reason` at the top of `perform`, right after the method signature — `create_transfer_note` and `send_public_handoff_message` currently only receive `reason`/`message` as local parameters, with no instance-level access to `reason` from `send_public_handoff_message`; (2) add a private `account_locale` method (`@conversation.account.locale.presence || I18n.default_locale.to_s`), symmetric to the existing `conversation_locale` method but independent of `@conversation.language` (required for FR-005 — the note label must NOT fall through to conversation language the way `conversation_locale` does)
---

## Phase 3: User Story 1 (P1) — Classifier stops misreading single decline as out-of-scope

**Story Goal**: A customer who declines exactly one qualification question after already demonstrating commercial intent is no longer misclassified as out-of-scope; the classifier keeps engaging normally instead of handing off.

**Independent Test Criteria**:
- Single-decline-after-intent scenario does not trigger `out_of_scope_commercial_request` reason (SC-001)
- Genuine out-of-scope cases (existing customer unrelated issue, complaint, no intent) still correctly identified and handed off (SC-002, no regression)

### Implementation Tasks
- [x] T007 [US1] Write failing test in `custom/spec/services/custom/scout/action_classifier_service_spec.rb`: classifier does NOT return `action: 'handoff'` / `action_reason: 'out_of_scope_commercial_request'` for message history where customer asks for help, states concrete need, answers qualification questions, then declines exactly one further question (mirrors production conversation 71393/display 45007)

- [x] T008 [US1] Revise `out_of_scope_commercial_request` criterion in `custom/app/services/custom/scout/action_classifier_service.rb` `system_instructions` prompt: add anti-hallucination anchor text and explicit single-decline carve-out, mirroring the anchor pattern already used for `human_offer_accepted` criterion (see research.md Decision #1)

- [x] T009 [US1] Verify T007 test now passes after T008 implementation

- [x] T010 [US1] Write regression test in `custom/spec/services/custom/scout/action_classifier_service_spec.rb`: classifier STILL correctly returns `action: 'handoff'` / `action_reason: 'out_of_scope_commercial_request'` for genuine out-of-scope scenarios (existing customer's unrelated ongoing issue, complaint filing, or purely informational question with no commercial intent)

- [x] T011 [US1] Verify T010 test passes (ensures FR-002 no regression)

---

## Phase 5: User Story 3 (P3) — Customer receives reason-specific closing message

**Story Goal**: When a classifier-driven handoff occurs, the customer sees a short, warm, reason-appropriate closing message instead of a single generic message.

**Independent Test Criteria**:
- Each of 4 defined classifier reasons produces reason-specific message instead of generic fallback (SC-004, FR-006)
- Reason-specific message resolved in conversation's language independent of account language (FR-007, edge case coverage: pt-BR account + English conversation)
- Unrecognized or missing reason falls back to existing generic text unchanged (FR-009)
- Two non-classifier handoff paths (tool-triggered, qualified-stage) remain unaffected with no change to their existing behavior (FR-012)

### Implementation Tasks
- [x] T020 [US3] Add i18n keys to `config/locales/en.yml` under `conversations.scout.handoff_reasons`: add `message` field for each of the 4 reasons with warm, reason-specific English customer-facing text (complementing the `note` field added in T012)

- [x] T021 [US3] Add i18n keys to `config/locales/pt_BR.yml` under `conversations.scout.handoff_reasons`: add `message` field for each of the 4 reasons with warm, reason-specific Portuguese text (complementing the `note` field added in T013)

- [x] T022 [US3] Add private method `reason_message(reason, locale)` in `custom/app/services/custom/scout/handoff_service.rb`: resolves i18n key `conversations.scout.handoff_reasons.#{reason}.message` with `I18n.t(..., locale: locale, default: nil)`; returns `nil` when `reason` is blank or unmatched (no separate fallback literal here — the `nil` propagates to the existing `message.presence || I18n.t('conversations.scout.handoff', ...)` precedence in `send_public_handoff_message`)

- [x] T023 [US3] Update `send_public_handoff_message` in `custom/app/services/custom/scout/handoff_service.rb`: when no explicit `message:` is passed (the classifier-driven path), resolve `reason_message(@action_reason, conversation_locale)` (using the ivar added in T006) and use it as the non-explicit-message default in place of the plain `I18n.t('conversations.scout.handoff', ...)` call — i.e. `content = message.presence || reason_message(@action_reason, conversation_locale) || I18n.t('conversations.scout.handoff', locale: conversation_locale)`; when `message:` is explicitly passed (both non-classifier paths), it wins unchanged (preserving FR-012)

- [x] T024 [US3] Write test in `custom/spec/services/custom/scout/handoff_service_spec.rb`: for each of the 4 defined reasons, assert that `send_public_handoff_message` (called without explicit `message:`) creates a public message whose content equals that reason's localized `message` (not the generic fallback) resolved in `conversation.language` (`conversation_locale`)

- [x] T025 [US3] Write edge-case test in `custom/spec/services/custom/scout/handoff_service_spec.rb`: verify message resolution with divergent locales (pt-BR account locale, English conversation language) — public message appears in English, internal note in Portuguese

- [x] T026 [US3] Write fallback test in `custom/spec/services/custom/scout/handoff_service_spec.rb`: when `reason` is unrecognized or missing, public message falls back to existing generic `conversations.scout.handoff` text unchanged

- [x] T027 [US3] Write regression test in `custom/spec/services/custom/scout/handoff_service_spec.rb`: when `message:` is explicitly passed (both non-classifier callers: tool path `agent_runner.rb`, qualified-stage path `follow_up_job.rb`), the explicit message always wins regardless of `reason` value, unchanged

- [x] T028 [P] [US3] Verify all T024–T027 tests pass (FR-006, FR-007, FR-009, FR-012)

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T029 Run targeted test suite per quickstart.md: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/action_classifier_service_spec.rb` — verify T007, T009, T010 examples pass

- [x] T030 Run targeted test suite per quickstart.md: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/handoff_service_spec.rb` — verify T016–T018, T024–T027 examples pass

- [x] T031 [P] Run regression test suite: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/agent_runner_spec.rb` — verify no breakage to tool-triggered handoff path

- [x] T032 [P] Run regression test suite: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/jobs/custom/scout/follow_up_job_spec.rb` — verify no breakage to qualified-stage handoff path

- [x] T033 [P] Run regression test suite: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/response_auditor_spec.rb` — verify call sites and double-confirmation logic unchanged

- [x] T034 Verify RuboCop compliance: `docker compose exec rails bundle exec rubocop custom/app/services/custom/scout/action_classifier_service.rb custom/app/services/custom/scout/handoff_service.rb` — ensure 150-character line limit and no complexity offenses

- [x] T035 Verify RuboCop compliance: `docker compose exec rails bundle exec rubocop config/locales/en.yml config/locales/pt_BR.yml` — ensure YAML formatting compliance

- [x] T036 Final integration: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/` — run all custom scout specs to verify no hidden dependencies or regressions
---

## Dependencies & Execution Strategy

### Dependency Graph

```
Phase 2 (Foundational) → Phase 3 (US1)
Phase 2 (Foundational) → Phase 4 (US2)
Phase 2 (Foundational) → Phase 5 (US3)
Phase 3 (US1) ✓ → Phase 4 (US2)  [independent after Phase 3 complete]
Phase 4 (US2) ✓ → Phase 5 (US3)  [independent after Phase 4 complete]
Phase 3 ✓ + Phase 4 ✓ + Phase 5 ✓ → Phase 6 (Polish)
```

Note: T006 (Phase 2) wires the `@action_reason` ivar and `account_locale` helper shared by both
Phase 4 (T015, note label) and Phase 5 (T023, customer message) — it lives in Foundational, not
inside either story, specifically so it is not duplicated or skipped if a story is deferred.

### Parallel Execution within Stories

**Within US1 (Phase 3)**:
- T010 (regression test writing) can start in parallel with T007 (single-decline test), before T008 (implementation)

**Within US2 (Phase 4)**:
- T012 + T013 (i18n keys for en + pt-BR) are parallelizable (independent locale files)
- T016 + T017 + T018 (test writing) can proceed in parallel after i18n keys and T014/T015 are ready

**Within US3 (Phase 5)**:
- T020 + T021 (i18n keys for en + pt-BR) are parallelizable
- T024–T027 (test writing) can proceed in parallel after i18n keys are ready

**Within Phase 6 (Polish)**:
- T029, T030: depend on Phases 3, 4, 5 complete; sequential (spec runs)
- T031–T033: parallelizable (independent regression test files)
- T034, T035: parallelizable (independent lint checks)
- T036: final integration; runs after all other phase 6 tasks

### MVP Scope (Recommended)

**Minimum Viable Product**: Implement US1 + US2 (Phase 3 + Phase 4)
- Fixes the root-cause classifier defect (FR-001, FR-002)
- Adds operational clarity for team reviewing handoffs (FR-004, FR-005, FR-008)
- Delivers measurable improvement in accuracy and auditability
- US3 (customer message) is a polish layer; deferred for Phase 2 release if time-constrained

**Full Scope**: All three user stories (Phase 3 + Phase 4 + Phase 5)
- Addresses classifier accuracy, team clarity, *and* customer-facing tone
- Delivers complete, production-ready feature across all surfaces
- No technical or scheduling blocker; same team/container environment

---

## Testing Strategy

All tests follow Constitution Principle VI (TDD), Principle VII (Observable Behavior), and Principle VIII (Pragmatic Functional Slices):

1. **Write tests first** (T007, T010, T016–T018, T024–T027): each assertion validates real, observable behavior (message content, locale resolution) through existing spec patterns (private message queries, locale stubs)

2. **Run targeted, scoped tests** (T029–T033): no global suite runs during iteration; only the affected service files per quickstart.md

3. **No mocking of internals**: tests exercise real `I18n.t` lookups and fallback chains against the actual locale YAML files; `Conversation` and `Account` fixtures provide real test data

4. **Regression checks** (T031–T033): existing suites for non-classifier paths run unchanged to prove FR-012 compliance (other two handoff paths unaffected)

---

## Format Validation Checklist

- ✓ All tasks follow checklist format: `- [ ] [TaskID] [P?] [Story?] Description`
- ✓ Sequential task IDs (T001–T036) in execution order
- ✓ Parallelizable tasks marked `[P]`
- ✓ Story-phase tasks marked `[Story]` (US1, US2, US3)
- ✓ All file paths explicit and exact
- ✓ Phase boundaries clear (Setup, Foundational, US1–US3, Polish)
- ✓ Independent test criteria per story
- ✓ Dependency graph documented
- ✓ Parallel execution examples provided
