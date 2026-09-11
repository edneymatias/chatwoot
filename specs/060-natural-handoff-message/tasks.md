---

description: "Task list template for feature implementation"
---

# Tasks: Natural Handoff Message

**Input**: Design documents from `/specs/060-natural-handoff-message/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: This feature does not add a separate TDD "write failing tests first" phase — per this
project's convention (avoid writing specs unless explicitly asked), no speculative new spec files
are introduced. However, four **existing** spec files assert on behavior this feature intentionally
changes (e.g. `handover_to_human_spec.rb` currently expects `HandoffService` to be called
synchronously) and one covers behavior that must remain provably unchanged — those files are
required to be updated as part of the corresponding implementation task, not deferred. This matches
`spec80.md`'s own "Testes" section, which enumerates exactly these updates as in-scope.

**Organization**: Tasks are grouped by user story (from `spec.md`) to enable independent
verification of each story once the shared Foundational phase (which two of the five stories build
directly on) is complete.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US5, per `spec.md`)
- Include exact file paths in descriptions

## Path Conventions

Backend-only change inside this fork's isolated `custom/` tree (per `plan.md` Project Structure):
`custom/app/services/custom/scout/` for implementation, `custom/spec/services/custom/scout/` for
specs. No frontend, migration, or `enterprise/` paths are touched.

---

## Phase 1: Setup

**Purpose**: Establish a known-good baseline before changing shared handoff plumbing.

- [x] T001 Run the current targeted Scout spec suite to confirm a green baseline before any change: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/tools/handover_to_human_spec.rb custom/spec/services/custom/scout/handoff_service_spec.rb custom/spec/services/custom/scout/agent_runner_spec.rb custom/spec/services/custom/scout/system_prompts_service_spec.rb custom/spec/services/custom/scout/response_auditor_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared plumbing that User Story 1, 2, and 3 all depend on — generalizing handoff
detection so it works uniformly for any tool exposing `handoff_needed`, and giving
`HandoffService` a way to accept a caller-supplied message instead of always using the fixed
sentence.

**⚠️ CRITICAL**: No user story below is independently verifiable until this phase is complete.

- [x] T002 In `custom/app/services/custom/scout/handoff_service.rb`, add an optional `message:` keyword param to `#perform`, thread it into the (now `message:`-accepting) `send_public_handoff_message` as `content: message.presence || I18n.t('conversations.scout.handoff', locale: conversation_locale)` (FR-003; `data-model.md` Handoff message entity)
- [x] T003 In `custom/app/services/custom/scout/agent_runner.rb`, generalize handoff detection per `research.md` Decision 2 and `plan.md` Summary: change `build_tools` to return only the tools array (drop the `[tools, handover]` tuple); make `process_response` always call `parse_structured_response` first, regardless of any tool's state, and fall back to `perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.')` when parsing yields nothing; add `handoff_requested_tool(tools)` (`tools.find { |tool| tool.respond_to?(:handoff_needed) && tool.handoff_needed }`); add `trigger_handoff(tool, reply_text)` that calls `HandoffService#perform(message: reply_text, assignee_id: handoff_param(tool, :handoff_assignee_id), team_id: handoff_param(tool, :handoff_team_id), reason: handoff_param(tool, :handoff_reason) || 'Oportunidade movida para o estágio qualificado')`; add `handoff_param(tool, method_name)`; remove `qualification_handoff_needed?` and `trigger_qualification_handoff` (FR-001, FR-002, FR-007; `data-model.md` Conversation turn entity)

**Checkpoint**: Any tool that sets `handoff_needed` is now detected uniformly, and
`HandoffService` can render either a caller-supplied message or the fixed fallback. No user-facing
behavior has changed yet — `HandoverToHuman` still short-circuits before this code runs until
Phase 3 lands.

---

## Phase 3: User Story 1 - Contextual closing message on assistant-initiated handoff (Priority: P1) 🎯 MVP

**Goal**: When the assistant itself decides a human is needed (via `handover_to_human`), the
customer sees the assistant's own closing text instead of the fixed sentence.

**Independent Test**: Start a conversation that leads the assistant to call `handover_to_human`;
confirm the customer's final message is the assistant's own turn text, not the old fixed sentence,
and that no other message repeats the fixed sentence alongside it.

### Implementation for User Story 1

- [x] T004 [US1] In `custom/app/services/custom/scout/tools/handover_to_human.rb`, change `execute` (outside the playground branch, which is unchanged) to no longer call `Custom::Scout::HandoffService` directly: rename `attr_reader :handoff_executed` to `attr_reader :handoff_needed, :handoff_assignee_id, :handoff_team_id, :handoff_reason`, set those four ivars from the method params, and return the instruction string `'A transferência será confirmada após sua resposta final. Escreva agora uma mensagem natural de encerramento, sem perguntas.'` (spec80.md scope item 2; FR-001)
- [x] T005 [P] [US1] Update `custom/spec/services/custom/scout/tools/handover_to_human_spec.rb`: replace the existing `handoff_executed`/`delegates to HandoffService` expectations with assertions that `execute` outside the playground sets `handoff_needed`, `handoff_assignee_id`, `handoff_team_id`, `handoff_reason` and returns the instruction string, without calling `HandoffService`. No playground-mode `it` exists in this file today (verified: `rg playground custom/spec/services/custom/scout/` has zero hits anywhere in the Scout spec tree) — add a **new** `it` covering `execute` with `playground?` true, asserting it still returns the existing `"[Simulado] Atendimento transferido para humano..."` text unchanged. This is the only concrete automated coverage for FR-008 in this feature (FR-008)
- [x] T006 [US1] In `custom/spec/services/custom/scout/agent_runner_spec.rb`, add a **new** integration-level scenario exercising the `handover_to_human` tool end to end (none exists today — confirmed via grep, this file currently has no `handover_to_human`/`HandoverToHuman`/`handoff_executed` reference at all; do not search for one to "adjust"). Assert the final public handoff message equals the model's parsed `response` text (via `HandoffService#perform(message: ..., ...)`), not the fixed `I18n` sentence, and that exactly one outgoing message is sent (FR-001, FR-002)

**Checkpoint**: Assistant-initiated handoffs now show the assistant's own closing text end to end;
playground behavior is unchanged. This alone is a demonstrable MVP.

---

## Phase 4: User Story 2 - Contextual closing message on automatic qualification handoff (Priority: P1)

**Goal**: When an opportunity automatically reaches the qualified pipeline stage mid-conversation,
the customer sees a natural closing message sourced from that turn, not the fixed sentence.

**Independent Test**: Drive a conversation so the opportunity reaches the qualified stage
mid-conversation; confirm the customer-facing handoff message is the assistant's own turn text.

### Implementation for User Story 2

No new production code — `ManageOpportunity`/`MoveOpportunityStage` already expose `handoff_needed`
(unchanged by this feature) and Phase 2's generalized detection in `agent_runner.rb` already covers
this trigger. Only verification is needed.

- [x] T007 [US2] Update `custom/spec/services/custom/scout/agent_runner_spec.rb`: add/adjust the mechanical-qualification scenario (`ManageOpportunity`/`MoveOpportunityStage` reporting `handoff_needed: true`) so it asserts the public handoff message is the model's parsed `response` text, and that the reason falls back to `'Oportunidade movida para o estágio qualificado'` when the tool exposes no `handoff_reason` (mirrors `trigger_handoff`'s default) (FR-001, FR-007)
- [x] T008 [US2] Manual behavioral check per `specs/060-natural-handoff-message/quickstart.md` scenario 2: drive a conversation to opportunity qualification and confirm the resulting public message is natural closing text, not the old fixed sentence

**Checkpoint**: Both P1 stories (assistant-initiated and automatic-qualification handoff) now show
contextual closing text, built on the same shared plumbing with no duplicated logic.

---

## Phase 5: User Story 3 - Safe fallback when no usable closing text exists (Priority: P2)

**Goal**: When the assistant's turn text can't be parsed or is blank, the customer still gets the
existing fixed generic message — no blank or broken handoff.

**Independent Test**: Force a turn ending in handoff whose response is unparseable or blank;
confirm the customer still receives the fixed sentence.

### Implementation for User Story 3

- [x] T009 [P] [US3] Update `custom/spec/services/custom/scout/handoff_service_spec.rb`: add an `it` confirming `message:` when present becomes the public message content, and an `it` confirming a blank/nil `message` falls back to `I18n.t('conversations.scout.handoff', ...)` (FR-003; spec80.md Testes section, `handoff_service_spec.rb` bullet)
- [x] T010 [US3] Review `custom/spec/services/custom/scout/agent_runner_spec.rb`'s existing unparseable/blank-response scenario (routes to `perform_fail_safe_handoff` with the fixed message) and confirm it still passes unchanged after Phase 2's reordering of `process_response` — add an explicit regression assertion if the current scenario doesn't already pin this (FR-003, FR-006)

**Checkpoint**: The "fail closed" guarantee is explicitly verified — no regression risk introduced
by sourcing messages from the model in Phases 3–4.

---

## Phase 6: User Story 4 - No question left unanswered at handoff (Priority: P2)

**Goal**: The assistant's closing text for any turn ending in handoff never poses a question to the
customer, since there's no chance for them to answer before the transfer completes.

**Independent Test**: Review a sample of real historical conversations that ended in handoff (via
replay) and confirm none of the resulting closing messages end in a question.

**Note**: This story is prompt content only (`system_prompts_service.rb`) and has no dependency on
Phases 2–5 — it can be implemented and verified in parallel with any of them.

### Implementation for User Story 4

- [x] T011 [P] [US4] Extend the "Fallback para humano" bullet inside `guardrails_section` in `custom/app/services/custom/scout/system_prompts_service.rb` per spec80.md scope item 1: instruct the model that whenever a turn will end in handoff (via `handover_to_human` or automatic stage qualification), its final response must be a natural closing message confirming what was registered and explaining a human will continue, and must never contain a question (FR-004)
- [x] T012 [P] [US4] Update `custom/spec/services/custom/scout/system_prompts_service_spec.rb`: add an `it` confirming the extended directive text is present in `guardrails_section`'s output (FR-004)
- [x] T013 [US4] Behavioral replay per `specs/060-natural-handoff-message/quickstart.md` scenario 4: use `Custom::Scout::PlaygroundRunner` to replay `conversation_id 43` / `display_id 41` (the original evidence conversation) and confirm the resulting closing message neither ends in a question nor repeats the old fixed sentence

**Checkpoint**: The prompt guardrail is in place and confirmed against the known historical evidence
conversation — the "asks a question and transfers anyway" regression is not reintroduced.

---

## Phase 7: User Story 5 - Unchanged behavior for the independent consistency-review handoff path (Priority: P3)

**Goal**: When the standalone `ActionClassifierService`/`ResponseAuditor` mechanism decides a
handoff independently of the current turn, the customer still sees the existing fixed sentence.

**Independent Test**: Trigger a handoff via the standalone consistency-review path and confirm the
customer-facing message is still the existing fixed sentence.

**Note**: This story requires no production code change — `Custom::Scout::ResponseAuditor#execute_handoff`
already calls `HandoffService.perform(reason: reason)` without a `message:` argument, and Phase 2
did not touch that call site. Only a regression assertion is needed.

### Implementation for User Story 5

- [x] T014 [P] [US5] In `custom/spec/services/custom/scout/agent_runner_spec.rb` (or `custom/spec/services/custom/scout/response_auditor_spec.rb`, whichever already exercises the `ActionClassifierService`-decided handoff), add/confirm an assertion that this path calls `HandoffService#perform` without a `message:` argument, so the public message remains the fixed `I18n` sentence (FR-005)

**Checkpoint**: All five user stories are independently verified; the two explicitly-unchanged
paths (this one and the system-failure fail-safe from Phase 5) are pinned by regression assertions.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Full-suite validation and lint compliance across all touched files.

- [x] T015 Run the full targeted Scout spec suite: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/tools/handover_to_human_spec.rb custom/spec/services/custom/scout/handoff_service_spec.rb custom/spec/services/custom/scout/agent_runner_spec.rb custom/spec/services/custom/scout/system_prompts_service_spec.rb custom/spec/services/custom/scout/response_auditor_spec.rb` — confirm 0 failures
- [x] T016 Run `docker compose exec rails bundle exec rubocop custom/app/services/custom/scout/agent_runner.rb custom/app/services/custom/scout/handoff_service.rb custom/app/services/custom/scout/system_prompts_service.rb custom/app/services/custom/scout/tools/handover_to_human.rb` — confirm 0 offenses
- [x] T017 [P] Execute the remaining `specs/060-natural-handoff-message/quickstart.md` manual scenarios not already covered by T008/T013 — scenario 1 (assistant-initiated live check) and scenario 6 (playground unaffected) — and confirm expected outcomes

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — run first to establish the baseline.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS User Stories 1, 2, and 3 (all three rely on
  the generalized handoff detection and `HandoffService#perform(message:)`).
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2).
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2). Does NOT depend on User Story 1 —
  `ManageOpportunity`/`MoveOpportunityStage` already expose `handoff_needed` independently of the
  `HandoverToHuman` tool change.
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) only.
- **User Story 4 (Phase 6)**: No dependency on Phase 2 at all — pure prompt-string change, can run
  fully in parallel with Phases 2–5.
- **User Story 5 (Phase 7)**: No production dependency — regression assertion only; can run any
  time, though it's ordered last here since it's the lowest priority (P3).
- **Polish (Phase 8)**: Depends on all prior phases being complete.

### Within Each User Story

- Production code change (if any) before its own spec update.
- Spec update before manual/behavioral verification.

### Parallel Opportunities

- T011/T012 (User Story 4) can start immediately, in parallel with Phase 2 and everything after it —
  different file, no shared dependency.
- T005 (US1 spec) and T009 (US3 spec) touch different files and can run in parallel once their
  respective production tasks (T004, T002) land.
- T014 (US5) can run in parallel with any other phase — it only asserts existing, untouched
  behavior.

---

## Parallel Example: Foundational + User Story 4

```bash
# Once Phase 1 (Setup) is done, these two tracks have no file overlap and can run together:
Task: "T003 Generalize handoff detection in custom/app/services/custom/scout/agent_runner.rb"
Task: "T011 Extend guardrails_section in custom/app/services/custom/scout/system_prompts_service.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (baseline).
2. Complete Phase 2: Foundational (generalized handoff detection + `HandoffService` message param).
3. Complete Phase 3: User Story 1 (`handover_to_human` shows the model's own text).
4. **STOP and VALIDATE**: Run T005/T006 and quickstart.md scenario 1; confirm the assistant-initiated
   handoff path shows natural closing text with no fixed sentence.
5. This alone resolves the most common handoff path's tone complaint and is demoable on its own.

### Incremental Delivery

1. Setup + Foundational → shared plumbing ready.
2. User Story 1 → assistant-initiated handoffs fixed (MVP).
3. User Story 2 → automatic-qualification handoffs fixed (near-zero extra code, mostly verification).
4. User Story 3 → fallback safety net explicitly pinned by regression specs.
5. User Story 4 → prompt guardrail against trailing questions, verified via historical replay.
6. User Story 5 → confirms the one path this feature intentionally leaves untouched.
7. Polish → full suite + rubocop + remaining manual scenarios.

### Notes

- Given how small and tightly coupled this feature is (4 existing files, no new files, no schema
  changes), a solo implementer will likely complete Phases 2–7 in a single sitting; the phase
  breakdown above exists primarily to make each user story's acceptance criteria independently
  checkable, per `spec.md`.
- Commit after each checkpoint (Foundational, then each user story), per this repo's Conventional
  Commits convention — do not commit or push without explicit user validation first, per this
  repo's workflow constraint.
