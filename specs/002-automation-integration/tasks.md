---

description: "Task list for Automation Integration — Create Opportunity Action"
---

# Tasks: Automation Integration — Create Opportunity Action

**Input**: Design documents from `/specs/002-automation-integration/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/create-opportunity-action.md, quickstart.md

**Tests**: Included — the source spec's User Story 2 (idempotency) is only verifiable via a
concurrency-style test, and `CLAUDE.md` general guidance permits specs when they cover real
requirements; both target spec files already exist and are extended in place, not created new.

**Organization**: Tasks are grouped by user story (US1: create Opportunity via automation, US2:
idempotent duplicate prevention) to allow independent implementation and testing of each.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- Include exact file paths in descriptions

## Path Conventions

Rails monolith, repository root. New extension code lives under `custom/app/...`; the single core
edit is in `app/services/automation_rules/action_service.rb`. All Ruby commands run via
`docker compose exec rails ...`; JS/i18n check via `docker compose exec vite ...`, per `CLAUDE.md`.

---

## Phase 1: Setup

**Purpose**: Nothing project-wide needs initializing — `custom/app/models/` already exists from
Phase 1 (kanban backend core), and the new `custom/app/services/custom/automation_rules/`
directory is created implicitly by writing its first file in T007. No standalone setup task is
needed this phase.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The database-level idempotency constraint (FR-005, SC-002) is required before either
user story's action logic can be considered complete, since both US1's "exactly one Opportunity"
acceptance scenario and US2's duplicate-prevention scenario depend on it existing.

**⚠️ CRITICAL**: T002 MUST be migrated before running any quickstart or spec validation for either
user story.

- [X] T002 Generate and write migration
      `db/migrate/<timestamp>_add_unique_index_on_matias_opportunities_origin_conversation.rb`
      adding `add_index :matias_opportunities, :origin_conversation_id, unique: true, where: "origin_conversation_id IS NOT NULL"`
      inside a `change` method (reversible); run
      `docker compose exec rails bundle exec rails db:migrate` and confirm `db/schema.rb` reflects
      the new unique partial index

**Checkpoint**: Foundation ready — both user stories can now be implemented.

---

## Phase 3: User Story 1 - Administrator automates opportunity creation from existing triggers (Priority: P1) 🎯 MVP

**Goal**: Make `create_opportunity` a selectable, dispatchable Automation Rule action that creates
exactly one correctly-scoped `Opportunity` when a rule's trigger fires.

**Independent Test**: Create an Automation Rule with any trigger event and a `create_opportunity`
action pointing at a valid `pipeline_stage_id`; fire the trigger for a conversation; confirm
exactly one `Opportunity` is created, linked to that conversation's contact and origin
conversation, in the configured stage, with status `open`.

### Tests for User Story 1

- [X] T003 [P] [US1] Add `describe '#create_opportunity'` context to
      `spec/models/automation_rule_spec.rb` asserting `actions_attributes` includes
      `"create_opportunity"` (contract: registration)
- [X] T004 [P] [US1] Add `describe '#create_opportunity'` context to
      `spec/services/automation_rules/action_service_spec.rb` covering: creates exactly one
      `Opportunity` scoped to account/contact/stage with status `open` (no `title_template`
      supplied, no `title_template` case); title defaults to `"#{contact.name} - #{Date.current}"`;
      title reflects a supplied `title_template`; a nonexistent/cross-account `pipeline_stage_id`
      raises and propagates out of the method uncaught (contract: dispatch, input, output)

### Implementation for User Story 1

- [X] T005 [US1] Add `AutomationRules::ActionService.prepend_mod_with('AutomationRules::ActionService')`
      as the single added line at the bottom of
      `app/services/automation_rules/action_service.rb` (the one permitted core-file edit)
- [X] T006 [US1] Create `module Custom::AutomationRule` in
      `custom/app/models/custom/automation_rule.rb` overriding `actions_attributes` to return
      `super + %w[create_opportunity]`
- [X] T007 [US1] Create `module Custom::AutomationRules::ActionService` in
      `custom/app/services/custom/automation_rules/action_service.rb` implementing
      `create_opportunity(params)` (private): resolves `pipeline_stage_id` from `params`, resolves
      `title_template` or falls back to `"#{@conversation.contact.name} - #{Date.current}"`,
      creates one `Opportunity` with `account: @conversation.account`,
      `contact: @conversation.contact`, `pipeline_stage_id: params[:pipeline_stage_id]`,
      `origin_conversation: @conversation`, `status: :open`, the resolved title — no rescue block
      inside the method itself (errors propagate to the existing `#perform` rescue wrapper)
- [X] T008 [US1] Add `"CREATE_OPPORTUNITY": "Create Opportunity"` under the `ACTIONS` key in
      `app/javascript/dashboard/i18n/locale/en/automation.json` (FR-008, contract: I18n)
- [X] T009 [US1] Run `docker compose exec rails bundle exec rspec spec/models/automation_rule_spec.rb spec/services/automation_rules/action_service_spec.rb`
      and confirm all US1 examples pass

**Checkpoint**: User Story 1 is fully functional and independently testable — a single
non-duplicate `create_opportunity` execution works end-to-end.

---

## Phase 4: User Story 2 - Automation does not create duplicate opportunities on repeated firing (Priority: P1)

**Goal**: Guarantee that repeated (including concurrent/near-simultaneous) `create_opportunity`
executions for the same conversation never produce more than one `Opportunity`, and never raise.

**Independent Test**: Run the same `create_opportunity` action twice (and, for the concurrency
guarantee, twice near-simultaneously) for the same conversation; confirm only one `Opportunity`
exists afterward with no error raised on the second/losing run.

### Tests for User Story 2

- [X] T010 [US2] Extend `spec/services/automation_rules/action_service_spec.rb`'s
      `create_opportunity` context with: running the action twice sequentially for the same
      conversation results in exactly one `Opportunity` and no raised error (FR-005 first
      acceptance scenario); a test simulating a lost race against the unique index (e.g. inserting
      a competing `Opportunity` with the same `origin_conversation_id` directly, bypassing the
      pre-check, before invoking the action) still results in exactly one `Opportunity` and no
      raised error (SC-002 concurrency guarantee)

### Implementation for User Story 2

- [X] T011 [US2] In `create_opportunity` (`custom/app/services/custom/automation_rules/action_service.rb`),
      guard creation with a pre-check (`Opportunity.exists?(origin_conversation_id: @conversation.id)`
      → return early if true) plus a `rescue ActiveRecord::RecordNotUnique` around the `create!`
      call itself, treating a caught `RecordNotUnique` as an already-idempotent no-op (per
      research.md Decision 3 and data-model.md) — this is the only rescue permitted inside the
      method, scoped exclusively to the uniqueness race, distinct from the uncaught-propagation
      behavior for all other errors (T007)
- [X] T012 [US2] Run `docker compose exec rails bundle exec rspec spec/services/automation_rules/action_service_spec.rb`
      and confirm the new idempotency examples (T010) pass, including the simulated-race case

**Checkpoint**: Both P1 user stories are complete and independently verified — the feature is
production-ready as scoped.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final end-to-end validation against the documented quickstart, beyond the unit-level
specs already run per-story.

- [X] T013 Run the full `quickstart.md` validation sequence end-to-end inside the `rails`/`vite`
      containers (migration reversibility check, `actions_attributes` registration check, prepend
      wiring `git diff` check, rails-console idempotency walkthrough, i18n label check, full spec
      suite for both extended files) and confirm every step matches its documented expected outcome

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — trivial, can start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS both user stories (the unique index is a
  precondition for both US1's "exactly one Opportunity" assertion and all of US2)
- **User Story 1 (Phase 3)**: Depends on Foundational completion only
- **User Story 2 (Phase 4)**: Depends on Foundational completion AND on US1's `create_opportunity`
  method existing (T007) — it extends the same method with the race-guard rather than being a
  separate code path, so in practice implement sequentially (US1 then US2), not in parallel
- **Polish (Phase 5)**: Depends on both user stories being complete

### Within Each User Story

- Tests before implementation (T003/T004 before T005–T008; T010 before T011)
- Model/registration change (T006) and service/dispatch change (T005, T007) before running specs
  (T009)

### Parallel Opportunities

- T003 and T004 (different spec files, no shared dependency) can run in parallel
- T005, T006, T008 touch three independent files and can be done in parallel once T002 (migration)
  is applied; T007 depends on T005 existing conceptually (the prepend seam) but not on its file
  content, so T005–T008 can all be drafted in parallel and only need to land together before T009

---

## Parallel Example: User Story 1

```bash
# Tests (different files):
Task: "Add actions_attributes assertion to spec/models/automation_rule_spec.rb"
Task: "Add create_opportunity dispatch/output specs to spec/services/automation_rules/action_service_spec.rb"

# Implementation (different files):
Task: "Add prepend_mod_with line to app/services/automation_rules/action_service.rb"
Task: "Create custom/app/models/custom/automation_rule.rb"
Task: "Add CREATE_OPPORTUNITY i18n key to app/javascript/dashboard/i18n/locale/en/automation.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (unique index — CRITICAL, also needed by US2)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Run T009's spec suite; confirm single-execution behavior end-to-end
5. This alone is a viable, demoable MVP: single-firing automation-driven Opportunity creation
   works, even before the idempotency hardening in US2 is added

### Incremental Delivery

1. Setup + Foundational → unique index in place
2. Add User Story 1 → validate independently (T009) → MVP
3. Add User Story 2 → validate independently (T012) → duplicate-firing is now safe
4. Polish (T013) → full quickstart confirms both stories together

## Notes

- [P] tasks = different files, no dependencies
- Both user stories are P1 — there is no lower-priority story to defer; ship both before calling
  this phase complete, but US1 alone is a coherent, stoppable checkpoint if needed
- Commit after each task or logical group, inside the `vite` container per `CLAUDE.md`'s pre-commit
  hook note
- Avoid: adding a rescue inside `create_opportunity` for anything other than the
  `ActiveRecord::RecordNotUnique` race (T011) — all other errors must propagate uncaught per FR-006
- FR-007 (usable with any existing trigger/condition; no new trigger/condition type) has no
  dedicated task by design — it's satisfied by omission (no trigger/condition code is added or
  changed anywhere in this task list) and implicitly exercised by T004/T009 dispatching
  `create_opportunity` the same way every other action is dispatched, regardless of which event
  triggered it
