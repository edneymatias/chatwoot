---

description: "Task list template for feature implementation"
---

# Tasks: Scout Contact Identity Detection

**Input**: Design documents from `/specs/061-scout-contact-identity/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: This feature explicitly requests TDD specs — the source design document
(`docs/kanban/ciclo 10/scout/19-contact-identity-and-conversation-labeling/spec81.md`, "Specs
automatizados (TDD)") calls for a new spec file for the classifier plus additions to two existing
spec files, and `plan.md`'s Testing decision carries this through. `contact_identity_service_spec.rb`
is written test-first (T002 before T003); the other spec updates are added alongside their
production task per this repo's usual convention.

**Note**: Task numbering below reflects a 2026-09-02 `/speckit-analyze` remediation pass — T010 is
new (finding COV1) and every task from the former T010 onward shifted by one relative to the first
draft.

**Organization**: Tasks are grouped by user story (from `spec.md`) to enable independent
verification of each story once the shared Foundational phase (which User Story 1 and User Story 2
both build on) is complete. User Story 3 has no dependency on the Foundational phase and can run in
parallel with it.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US3, per `spec.md`)
- Include exact file paths in descriptions

## Path Conventions

Backend-only change inside this fork's isolated `custom/` tree (per `plan.md` Project Structure):
`custom/app/services/custom/scout/` for implementation, `custom/spec/services/custom/scout/` for
specs. No frontend, migration, or `enterprise/` paths are touched — no core `app/` file is edited.

---

## Phase 1: Setup

**Purpose**: Establish a known-good baseline before touching shared prompt-assembly code.

- [X] T001 Run the current targeted Scout spec suite to confirm a green baseline before any change: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb custom/spec/services/custom/scout/playground_runner_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The placeholder-name classifier that both User Story 1 (ask for the name) and User
Story 2 (never address by the placeholder) gate their shared warning text on.

**⚠️ CRITICAL**: User Story 1 and User Story 2 cannot be implemented until this phase is complete.
User Story 3 does NOT depend on this phase (see Phase 5) and may run in parallel with it.

- [X] T002 [P] Write `custom/spec/services/custom/scout/contact_identity_service_spec.rb` (new file) — table of cases for `Custom::Scout::ContactIdentityService.placeholder_name?` per `data-model.md` Validation rule and `spec.md` Edge Cases: positive (`'empty-meadow-50'`, `'polished-forest-561'`, 1-digit and 3-digit number boundary cases), negative (`'Maria Silva'`, `'joao123'`, `'primeirazinha11234'`, a name with more than two hyphen-separated words, `nil`, `''`). Also add an explicit regression assertion that `contact.name` is unchanged after the call, e.g. `expect { described_class.placeholder_name?(contact) }.not_to change(contact, :name)` (FR-008, added 2026-09-02 per `/speckit-analyze` finding UND1 — the classifier is a pure predicate by construction, but this pins it with a test instead of relying on inspection alone). Expect this whole file to fail — the class does not exist yet (FR-001, FR-007, FR-008)
- [X] T003 Implement `Custom::Scout::ContactIdentityService` in `custom/app/services/custom/scout/contact_identity_service.rb` per `data-model.md` Carrier: single class method `.placeholder_name?(contact)` returning `false` for a blank name, else matching `\A[a-z]+-[a-z]+-\d{1,3}\z`; mirror the stateless class-method style of `Custom::Scout::EmbeddingConfig`. Makes T002 pass (FR-001, FR-007, FR-008)

**Checkpoint**: Classifier is implemented and covered by a green, deterministic spec — User Story 1
and User Story 2 implementation can now begin.

---

## Phase 3: User Story 1 - Ask a site visitor for their real name (Priority: P1) 🎯 MVP

**Goal**: A website-widget contact with a system-generated placeholder name gets asked their
preferred name as early as possible — ideally in Scout's first response — with priority over a
pending qualification question, only once, and the answer is persisted.

**Independent Test**: Start a website widget conversation as a new, unidentified visitor, go
through a normal qualification flow, and confirm the agent asks for a name in its first response,
does not repeat the question on a later turn, and records the answer once given.

### Implementation for User Story 1

- [X] T004 [US1] In `custom/app/services/custom/scout/system_prompts_service.rb`, extract the contact line out of `context_section` into a new private `contact_context_section` method (output for a non-placeholder contact stays byte-identical: `"Contexto do Contato:\n#{@contact.to_llm_text}"`), then append a conditional warning paragraph when `Custom::Scout::ContactIdentityService.placeholder_name?(@contact)` is true. Per `data-model.md`'s System prompt contact-context section Rule, the warning text must instruct the model to: (a) never address the customer using the placeholder value, (b) ask for the preferred name as early as possible — ideally in its very first response — then persist it via the existing `update_contact` tool, (c) prioritize this question over any pending qualification question for the turn's single question slot, (d) treat this question as exempt from `funnel_section`'s "only ask about configured fields" guidance, (e) carry one short clause subordinating (b)/(c) to the existing no-question-on-handoff rule by cross-reference only, not a restatement, and (f) never ask again once already asked in this conversation, even if the visitor didn't answer (FR-002, FR-003, FR-004, FR-005, FR-011, FR-012, FR-013; `research.md` FR-011 and FR-013 decisions; (f) added 2026-09-02 per `/speckit-analyze` finding COV1). This is a long instruction paragraph — wrap the Ruby source across adjacent string literals the same way the existing `guardrails_section` bullets already do, to stay within the repo's 150-char RuboCop line limit (finding CON1)
- [X] T005 [P] [US1] Update `custom/spec/services/custom/scout/system_prompts_service_spec.rb`: add examples confirming the warning paragraph is present in the built prompt for a placeholder-named contact (`'empty-meadow-50'`) and absent for a real-named contact (existing `contact` factory, e.g. `'Maria Silva'`); assert the warning text expresses immediacy ("primeira resposta" or equivalent), priority over qualification, the FR-013 configured-fields exemption, and the "never ask again, even if unanswered" clause (FR-005, added 2026-09-02 per finding COV1) (FR-002, FR-003, FR-005, FR-012, FR-013)
- [X] T006 [US1] In `custom/app/services/custom/scout/playground_runner.rb`, add an optional `contact:` keyword param to `.new`/`#initialize` (default `nil`), store it, and forward it to `Custom::Scout::SystemPromptsService.build(contact: @contact, ...)` in `#build_system_instructions`. No caller (including the HTTP playground controller) needs to change — the param is additive (`research.md` PlaygroundRunner decision)
- [X] T007 [P] [US1] Update `custom/spec/services/custom/scout/playground_runner_spec.rb`: add an example asserting a `contact:` passed to `.new` is forwarded into `SystemPromptsService.build`, and an example confirming existing behavior (no `contact:` given) is unchanged
- [X] T008 [US1] Behavioral replay per `quickstart.md` §4a: using `Custom::Scout::PlaygroundRunner.new(scout:, contact: <placeholder contact>, message:, message_history:)`, reconstruct the message sequence from the real conversation referenced in `spec81.md` (`display_id 51`) turn by turn. Confirm the **first** reply asks for the customer's preferred name, and a subsequent turn's `tool_calls` includes `update_contact` once a name-like answer is given (SC-001)
- [X] T009 [US1] Behavioral check per `quickstart.md` §4b: using the same placeholder contact, send a first message containing a clear qualification cue (e.g. pricing question). Confirm the reply asks for the visitor's name rather than jumping into the qualification question (FR-012)
- [X] T010 [US1] Behavioral check per `quickstart.md` §4d (new, 2026-09-02 per finding COV1): using a fresh placeholder contact, send a first message that does not answer the identity question, then a second message. Confirm the **second** reply does not repeat the identity question — this is the scenario that actually exercises T004 clause (f), since the happy path (name answered) naturally stops re-triggering the warning once `contact.name` changes (FR-005)

**Checkpoint**: User Story 1 is fully functional and independently testable — this is the MVP.

---

## Phase 4: User Story 2 - Never address the customer by their placeholder name (Priority: P1)

**Goal**: While a contact's name is still an unclaimed placeholder, Scout never uses that value to
address the customer directly.

**Independent Test**: Start a website widget conversation as an unidentified visitor and review
every agent message for direct address using the placeholder value; none should appear.

**Note**: No new production code — the "never address by placeholder" instruction is the same
warning paragraph built in T004 (User Story 1). This phase adds independent, targeted test
coverage for that specific clause so a future edit to the warning text can't silently drop it
without a dedicated failure.

### Implementation for User Story 2

- [X] T011 [US2] In `custom/spec/services/custom/scout/system_prompts_service_spec.rb`, add a dedicated `it` asserting the placeholder-contact warning specifically contains the "never use this name to address the customer" instruction — independent of and in addition to T005's presence/immediacy/priority assertions (FR-002)
- [X] T012 [US2] Manual check per `quickstart.md` §5 steps 1–4: open the website widget in a private window, go through a conversation without volunteering a name, and confirm Scout never addresses the visitor by a generated placeholder like "Olá, Empty Meadow!" at any point before the real name is given (SC-002)

**Checkpoint**: Both P1 stories (ask for the name, never address by placeholder) are independently
verified, built on the same shared warning text with no duplicated logic.

---

## Phase 5: User Story 3 - Use judgment on channels without a reliable system signal (Priority: P2)

**Goal**: On channels other than the website widget, Scout uses judgment to decide whether the
available contact name looks like a system identifier/handle rather than a person's name, and if
so asks for the preferred name under the same non-intrusive rules as User Story 1.

**Independent Test**: Start conversations on a non-website channel with (a) a contact whose profile
name is clearly a real person's name and (b) a contact whose profile name looks like a generic
handle; confirm the agent asks for a preferred name only in case (b), and only once.

**Note**: This story does not depend on `Custom::Scout::ContactIdentityService` (Phase 2) — it is a
static, channel-agnostic guardrails bullet with no per-contact code branching. It can be
implemented in parallel with Phase 2/3/4. Unlike User Story 1 (see COV1 in T004/T010), the
"ask again" bound (FR-005) was already explicit in this bullet's design from the start, so no
equivalent remediation was needed here.

### Implementation for User Story 3

- [X] T013 [US3] In `custom/app/services/custom/scout/system_prompts_service.rb`, add a new bullet to `guardrails_section`, inserted after the existing "Esclarecimento" bullet, per `data-model.md`'s Guardrails identity bullet Rule: for any channel other than the website widget (no closed list), if the available name looks like a system identifier/handle rather than a person's name, ask once, as early as possible (ideally the first response), with priority over a pending qualification question, exempt from the configured-fields-only guidance, without asking again if already asked, without asking at all if the name already looks like a real person's name, and subject to the same short handoff cross-reference clause as T004's warning (FR-005, FR-006, FR-011, FR-012, FR-013). Same as T004: wrap the Ruby source across adjacent string literals to stay within the 150-char RuboCop line limit (finding CON1)
- [X] T014 [P] [US3] Update `custom/spec/services/custom/scout/system_prompts_service_spec.rb`: add an example confirming `guardrails_section`'s output always includes the new "Identidade do contato" bullet, with the immediacy/priority/once-only/exemption/handoff-cross-reference phrasing (FR-005, FR-006, FR-012, FR-013)
- [X] T015 [US3] Manual check per `quickstart.md` §5 step 5: repeat the widget test with a WhatsApp-connected inbox where the channel profile name already looks like a real name; confirm Scout does **not** ask the identity question (SC-004, no regression)

**Checkpoint**: All three user stories are independently functional and verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Regression coverage spanning multiple sections/stories, full-suite validation, and
lint compliance across all touched files.

- [X] T016 In `custom/spec/services/custom/scout/system_prompts_service_spec.rb`, add the deterministic coexistence example from `research.md`/`data-model.md`: build a prompt for a placeholder-named contact on an account with configured funnel fields, and assert the identity warning text, the existing "Fallback para humano"/`handoff_closing_reminder_section` handoff text, and the existing `funnel_section` guidance text are all present simultaneously and unmodified in the same rendered prompt (alignment-audit finding — cheap regression guard against a future edit dropping or reordering one section while touching another)
- [X] T017 Behavioral check per `quickstart.md` §4c: using a placeholder-named contact, drive the conversation (via `message_history`) to the point where the next tool call would be `handover_to_human` (or a stage transition that triggers handoff). Confirm the final reply contains no question at all — neither qualification nor identity. Expected to already pass unmodified (FR-011 is covered by existing guardrails, not new code) — this is a regression check, not a test of new behavior
- [X] T018 Run the full targeted Scout spec suite: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/contact_identity_service_spec.rb custom/spec/services/custom/scout/system_prompts_service_spec.rb custom/spec/services/custom/scout/playground_runner_spec.rb` — confirm 0 failures
- [X] T019 Run `docker compose exec rails bundle exec rubocop custom/app/services/custom/scout/contact_identity_service.rb custom/app/services/custom/scout/system_prompts_service.rb custom/app/services/custom/scout/playground_runner.rb` — confirm 0 offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — run first to establish the baseline.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS User Story 1 and User Story 2 (both rely on
  `ContactIdentityService` gating the shared warning text). Does NOT block User Story 3.
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2).
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) and on T004 (the warning text it
  adds targeted coverage for). Not independent of User Story 1's implementation task, though it is
  independently *testable* once T004 exists.
- **User Story 3 (Phase 5)**: No dependency on Phase 2 at all — pure guardrails prompt-string
  change, can run fully in parallel with Phases 2–4.
- **Polish (Phase 6)**: T016 depends on T004 (needs the warning text to exist); T017 depends on
  T004/T006 (needs the warning text and the `PlaygroundRunner` `contact:` param); T018/T019 depend
  on all prior phases being complete.

### Within Each User Story

- Production code change before its own spec update (T002 is the exception: TDD, spec written
  first and expected to fail before T003's implementation).
- Spec update before manual/behavioral verification.

### Parallel Opportunities

- T013/T014 (User Story 3) can start immediately after Setup, in parallel with Phase 2 and
  everything after it — different guardrails bullet, no shared dependency on the classifier.
- T002 (Foundational spec) has no dependency and can be written immediately after Setup.
- T005 (US1 spec) and T007 (US1 PlaygroundRunner spec) touch the same production dependency
  (T004/T006 respectively) but different spec files, and can run in parallel once their respective
  production tasks land.

---

## Parallel Example: Foundational + User Story 3

```bash
# Once Phase 1 (Setup) is done, these two tracks have no file overlap and can run together:
Task: "T002 Write contact_identity_service_spec.rb in custom/spec/services/custom/scout/"
Task: "T013 Add guardrails identity bullet in custom/app/services/custom/scout/system_prompts_service.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (baseline).
2. Complete Phase 2: Foundational (`ContactIdentityService`, TDD).
3. Complete Phase 3: User Story 1 (ask for the name, early, with priority, only once; persist via
   `update_contact`).
4. **STOP and VALIDATE**: Run T005/T007 and `quickstart.md` §4a/§4b/§4d; confirm the site-widget
   identity question fires correctly, wins priority over qualification, and doesn't repeat.
5. This alone resolves the core evidence gap (two real conversations where the name was never
   asked) and is demoable on its own.

### Incremental Delivery

1. Setup + Foundational → classifier ready.
2. User Story 1 → site-widget identity question fixed (MVP).
3. User Story 2 → "never address by placeholder" pinned by its own regression spec (near-zero
   extra code, mostly verification, same as User Story 1's warning text).
4. User Story 3 → non-website-channel judgment guardrail, independently shippable at any point.
5. Polish → cross-section regression coverage (T016), full suite, rubocop.

### Notes

- Given how small this feature is (one new file, two edited files, no schema changes), a solo
  implementer will likely complete all phases in a single sitting; the phase breakdown exists
  primarily to make each user story's acceptance criteria independently checkable, per `spec.md`.
- The 2026-09-02 alignment audit's two findings (FR-013 exemption, FR-011 handoff cross-reference)
  and the 2026-09-02 `/speckit-analyze` remediation (FR-005 once-only clause on the site path,
  FR-008 regression pin, RuboCop line-wrap reminder) are folded directly into T004/T013's
  implementation tasks (and T002's spec), not treated as separate follow-up tasks — they are part
  of the warning/bullet text and classifier spec as specified in `data-model.md`, not additive
  changes layered on afterward.
- Commit after each checkpoint (Foundational, then each user story), per this repo's Conventional
  Commits convention — do not commit or push without explicit user validation first, per this
  repo's workflow constraint.
