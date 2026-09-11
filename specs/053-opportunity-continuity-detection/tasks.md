# Tasks: Opportunity Continuity Detection

**Branch**: `053-opportunity-continuity-detection` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Directory structure initialization for the new opportunities services namespace

- [X] T001 Create directory structure for new namespace in `custom/app/services/custom/opportunities/` and `custom/spec/services/custom/opportunities/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core continuity resolver service and value object that all user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Implement `ContinuityDecision` value object and `Custom::Opportunities::ContinuityResolverService` 3-branch funnel (`:create_new`, `:reuse`, `:ambiguous`) in `custom/app/services/custom/opportunities/continuity_resolver_service.rb`
- [X] T003 [P] Implement unit specs for `Custom::Opportunities::ContinuityResolverService` (account/contact scoping, `status: :open` filter ignoring won/lost, 0 candidates, declared match, undeclared/unmatched candidates, traceable reason, and that two sequential calls after an intervening state change return correct non-stale results — no memoization/caching) in `custom/spec/services/custom/opportunities/continuity_resolver_service_spec.rb`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Continuing a known deal in a brand-new conversation (Priority: P1) 🎯 MVP

**Goal**: When a contact has an existing open deal, the assistant identifies it from structured prompt context, passes `opportunity_id` in `manage_opportunity`, and updates the existing deal in place rather than creating a duplicate.

**Independent Test**: Create a contact with one open `Opportunity` whose origin conversation is resolved. Start a new conversation as that contact and express renewed commercial interest; verify that `manage_opportunity` updates the existing deal in place and only one open deal exists for the contact.

### Tests for User Story 1

- [X] T004 [P] [US1] Add unit specs for structured open opportunities context block (`[Oportunidades Abertas do Contato]`) and commercial guardrail prompt in `custom/spec/services/custom/scout/system_prompts_service_spec.rb` — including an assertion that `context_section` still renders `contact.to_llm_text` narrative memory alongside the new block (FR-006: in addition to, not instead of)
- [X] T005 [P] [US1] Add unit specs for `manage_opportunity` tool `:reuse` execution flow (declared match updating existing opportunity) in `custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb`

### Implementation for User Story 1

- [X] T006 [P] [US1] Implement structured open opportunities context section (`open_opportunities_section`) in `custom/app/services/custom/scout/system_prompts_service.rb`
- [X] T007 [P] [US1] Add commercial intent guardrail reinforcement bullet to `guardrails_section` in `custom/app/services/custom/scout/system_prompts_service.rb`
- [X] T008 [P] [US1] Add `opportunity_id` parameter to `Custom::Scout::Tools::ManageOpportunity` in `custom/app/services/custom/scout/tools/manage_opportunity.rb`
- [X] T009 [US1] Integrate `ContinuityResolverService` into `Custom::Scout::Tools::ManageOpportunity#execute` to handle `:reuse` updates (replacing `origin_conversation_id`-only lookup) in `custom/app/services/custom/scout/tools/manage_opportunity.rb`

**Checkpoint**: At this point, User Story 1 is functional — Scout detects existing open deals and updates them without duplication.

---

## Phase 4: User Story 2 - Ambiguous continuity is never auto-resolved (Priority: P1)

**Goal**: When a contact has multiple open deals and no declared match, or when the declared `opportunity_id` fails validation (e.g. belongs to another contact or does not exist), the system never guesses or duplicates; it records a reviewable private note and continues the conversation normally.

**Independent Test**: Give a contact two open deals and trigger commercial interest without a declared match. Confirm no deal is created or modified, and a private note explaining the ambiguity is recorded on the conversation. Separately, verify declaring an invalid `opportunity_id` is rejected and flagged identically.

### Tests for User Story 2

- [X] T010 [P] [US2] Add unit specs for ambiguous continuity scenarios (multiple open deals without declared match, invalid `opportunity_id`, wrong-contact deal) and private note creation in `custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb`

### Implementation for User Story 2

- [X] T011 [US2] Implement `:ambiguous` handling in `Custom::Scout::Tools::ManageOpportunity#execute` (create private note via `Messages::MessageBuilder` using `decision.reason`, skip deal creation/mutation, return non-mutating result) in `custom/app/services/custom/scout/tools/manage_opportunity.rb`

**Checkpoint**: At this point, both User Story 1 and User Story 2 are functional — deterministic reuse occurs when validated, and all ambiguous cases are safely flagged without guessing.

---

## Phase 5: User Story 3 - New contact, genuinely new deal (Priority: P2)

**Goal**: When a contact has zero open deals, deal creation continues automatically with zero added friction, and the prompt omits the open opportunities context block.

**Independent Test**: With a contact having zero open deals, express commercial interest to Scout; confirm a new `Opportunity` is created automatically without an ambiguity note, and the prompt context block is omitted.

### Tests for User Story 3

- [X] T012 [P] [US3] Add unit specs for 0-deals automatic creation and prompt block omission in `custom/spec/services/custom/scout/system_prompts_service_spec.rb` and `custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb`

### Implementation for User Story 3

- [X] T013 [P] [US3] Ensure `open_opportunities_section` in `custom/app/services/custom/scout/system_prompts_service.rb` cleanly returns nil when `@contact` is nil or has 0 open deals
- [X] T014 [US3] Ensure `:create_new` branch in `Custom::Scout::Tools::ManageOpportunity#execute` retains referral attribution and stage fallback behavior in `custom/app/services/custom/scout/tools/manage_opportunity.rb`

**Checkpoint**: At this point, User Stories 1, 2, and 3 are functional — existing baseline creation for new leads is preserved without regression.

---

## Phase 6: User Story 4 - Rule-triggered deal creation never silently duplicates either (Priority: P2)

**Goal**: Automation rule action `create_opportunity` uses the shared `ContinuityResolverService` (with `declared_opportunity_id: nil`). It auto-creates when 0 open deals exist, and creates a private note flag whenever 1 or more open deals already exist (never auto-reusing or silently duplicating).

**Independent Test**: Trigger an automation rule with `create_opportunity` for a contact with 0 open deals (creates deal). Trigger the rule for a contact with 1 open deal (creates private note on conversation, leaves deals untouched).

### Tests for User Story 4

- [X] T015 [P] [US4] Add direct unit specs for `create_opportunity` in `custom/spec/services/custom/automation_rules/action_service_spec.rb` covering 0 open deals (create) and ≥1 open deals (ambiguity note, no creation/modification)

### Implementation for User Story 4

- [X] T016 [US4] Refactor `create_opportunity` in `custom/app/services/custom/automation_rules/action_service.rb` to invoke `ContinuityResolverService` and handle `:create_new` vs `:ambiguous` (adding private note to `@conversation`)

**Checkpoint**: All user stories (conversational Scout and automation rules) use the shared continuity resolver with identical decision rules.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Linting, translations, full test validation, and end-to-end verification

- [X] T017 [P] Verify synchronous i18n translations across `config/locales/en.yml` and `config/locales/pt_BR.yml` for any new user-facing private note templates or tool messages
- [X] T018 Run RuboCop checks and refactor any complexity offenses across all created and modified files in `custom/app/services/custom/`
- [X] T019 Execute full backend test suite for modified modules via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/opportunities/continuity_resolver_service_spec.rb custom/spec/services/custom/scout/system_prompts_service_spec.rb custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb custom/spec/services/custom/automation_rules/action_service_spec.rb`
- [X] T020 Run manual quickstart verification scenarios per `specs/053-opportunity-continuity-detection/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase (Phase 2) completion
  - User Story 1 (P1): Depends on Phase 2
  - User Story 2 (P1): Depends on User Story 1 tool wiring (`ManageOpportunity`)
  - User Story 3 (P2): Depends on User Story 1 & 2 tool wiring
  - User Story 4 (P2): Depends on Phase 2 (independent of Scout tool changes)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Foundational resolver service is ready. Implements prompt context and Scout tool declared-id reuse.
- **User Story 2 (P1)**: Builds on User Story 1's `ManageOpportunity` execution flow to handle `:ambiguous` branch with private notes.
- **User Story 3 (P2)**: Guardrail check on User Story 1 & 2 to ensure 0-deal case creates cleanly without prompts or notes.
- **User Story 4 (P2)**: Independent of Scout tools — connects `AutomationRules::ActionService` directly to the Phase 2 resolver service.

### Within Each User Story

- Tests written alongside/before implementation tasks
- Context & parameter additions before tool resolution execution
- Core execution before integration and verification

### Parallel Opportunities

- **Phase 2**: T002 implementation and T003 specs can be developed in tandem
- **Phase 3 (US1)**: T004 (prompt specs), T005 (tool specs), T006 (prompt context), T007 (guardrails), and T008 (tool param) can all run in parallel
- **Phase 4 (US2)**: T010 (specs) and T011 (implementation)
- **Phase 5 (US3)**: T012 (specs) and T013 (clean omission)
- **Phase 6 (US4)**: T015 (specs) and T016 (action service) can run in parallel with User Story 1-3 tasks once Phase 2 is complete

---

## Parallel Example: User Story 1

```bash
# Launch test and prompt tasks for User Story 1 together:
Task: "T004 [P] [US1] Add unit specs for structured open opportunities context block in custom/spec/services/custom/scout/system_prompts_service_spec.rb"
Task: "T005 [P] [US1] Add unit specs for manage_opportunity tool :reuse execution flow in custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb"
Task: "T006 [P] [US1] Implement structured open opportunities context section in custom/app/services/custom/scout/system_prompts_service.rb"
Task: "T007 [P] [US1] Add commercial intent guardrail reinforcement bullet in custom/app/services/custom/scout/system_prompts_service.rb"
Task: "T008 [P] [US1] Add opportunity_id parameter to Custom::Scout::Tools::ManageOpportunity in custom/app/services/custom/scout/tools/manage_opportunity.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational `ContinuityResolverService` (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Scout tool reuse with declared `opportunity_id`)
4. **STOP and VALIDATE**: Test User Story 1 independently in isolation

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (T001–T003)
2. Add User Story 1 → Test single deal continuity across conversations (MVP!) (T004–T009)
3. Add User Story 2 → Test ambiguous resolution & private note generation (T010–T011)
4. Add User Story 3 → Verify 0-deal regression guardrail (T012–T014)
5. Add User Story 4 → Connect automation rules action service to resolver (T015–T016)
6. Polish & Verify → Run RuboCop, full RSpec test suite, and quickstart scenarios (T017–T020)

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[US1]`, `[US2]`, `[US3]`, `[US4]` labels map tasks to user stories for traceability
- All tasks include checkboxes `- [ ]`, task IDs (`T001`–`T020`), and exact file paths

---

## Phase 8: Convergence

**Purpose**: Close test-coverage gaps found by `/speckit-converge` on 2026-08-28 — the underlying implementation is correct for both items below; only the spec assertions are missing.

- [X] T021 Add assertion in `custom/spec/services/custom/opportunities/continuity_resolver_service_spec.rb` verifying two sequential `#call` invocations, with an intervening state change (e.g. a new open `Opportunity` created for the contact between calls), return correct non-stale results per T003 (partial)
- [X] T022 Add assertion in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`'s `open_opportunities_section` "when contact has open opportunities" context verifying `contact.to_llm_text` narrative memory still renders in the same prompt alongside `[Oportunidades Abertas do Contato]` per FR-006 (partial)
