---
description: "Task list for Non-Sales Intent Recognition and Immediate Handoff implementation"
---

# Tasks: Non-Sales Intent Recognition and Immediate Handoff

**Input**: Design documents from `specs/063-non-sales-intent-handoff/`
**Prerequisites**: [`plan.md`](file:///home/matias/Projects/chatwoot/specs/063-non-sales-intent-handoff/plan.md), [`spec.md`](file:///home/matias/Projects/chatwoot/specs/063-non-sales-intent-handoff/spec.md), [`research.md`](file:///home/matias/Projects/chatwoot/specs/063-non-sales-intent-handoff/research.md), [`data-model.md`](file:///home/matias/Projects/chatwoot/specs/063-non-sales-intent-handoff/data-model.md), [`quickstart.md`](file:///home/matias/Projects/chatwoot/specs/063-non-sales-intent-handoff/quickstart.md)

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`, `[US4]`)
- Include exact file paths in descriptions

## Path Conventions

- **Custom fork tree**: `custom/app/services/custom/scout/`, `custom/spec/services/custom/scout/`
- **Root tooling/specs**: `specs/063-non-sales-intent-handoff/`, `bin/`

## Important: single atomic bullet, not incremental rewrites

Per `research.md` Decision 1 and `plan.md`'s Summary/Constitution Check (Principle II), the entire
guardrail bullet text is a single string already fully decided by
`docs/kanban/ciclo 10/scout/23-non-sales-intent-immediate-handoff/spec86.md` — it is implemented
**once**, in full, in **T004**. US2–US4 (Phases 4–6) add only verifying tests for clauses that are
already present after T004 lands; they do **not** re-edit the guardrail bullet. This avoids
rewriting the same line of code four times for a string whose final content was never in question.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify baseline development test environment and prompt builder test suite.

- [X] T001 Verify existing test suite and Scout prompt builder baseline in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core safety baseline that MUST be verified before prompt modifications begin.

**⚠️ CRITICAL**: Confirm baseline safety net specs pass to guarantee FR-006 compliance (no unintended changes to reactive safety net).

- [X] T002 Verify regression safety baseline for reactive Response Auditor in `custom/spec/services/custom/scout/action_classifier_service_spec.rb` to ensure no changes to `ActionClassifierService` behavior per FR-006

**Checkpoint**: Foundation ready - user story implementation and tests can begin.

---

## Phase 3: User Story 1 - Existing Customer with Support Need Handoff (Priority: P1) 🎯 MVP

**Goal**: When a contact states they are already a customer or mentions a treatment already in progress, Scout stops trying to resolve the matter itself and calls `handover_to_human` immediately. This phase delivers the **complete** guardrail bullet (all clauses for US1–US4 at once, per research.md Decision 1), not just the US1 clause.

**Independent Test**: Send a message indicating existing customer or ongoing treatment (e.g. "Já sou paciente, estou em tratamento e preciso de ajuda"); verify prompt includes the guardrail placed "Immediately after the existing `- Fallback para humano: ...` bullet" directing immediate `handover_to_human` without attempting self-resolution, and distinguishing from non-triggers where "A returning customer expressing new purchase interest — remains ordinary qualification, not covered by this guardrail".

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T003 [P] [US1] Add unit test asserting `guardrails_section` includes the "Reconhecimento de intenção fora de prospecção" bullet placed "Immediately after the existing `- Fallback para humano: ...` bullet" with "Static string (no interpolation, no per-account variation)" instructing immediate `handover_to_human` when contact "afirma já ser cliente, menciona tratamento em andamento" without attempting self-resolution in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

### Implementation for User Story 1

- [X] T004 [US1] Implement the **complete** "Reconhecimento de intenção fora de prospecção" guardrail bullet — verbatim text per `docs/kanban/ciclo 10/scout/23-non-sales-intent-immediate-handoff/spec86.md`, covering in one atomic edit: existing-customer/ongoing-treatment ("afirma já ser cliente, menciona tratamento em andamento"), reschedule/cancel/complaint ("quer reagendar/cancelar, tem uma reclamação"), triage-question decline ("responde a uma pergunta de triagem indicando ser 'só uma dúvida rápida' não relacionada a agendar avaliação"), the immediate-`handover_to_human`-without-self-resolution instruction, and the optional non-blocking external-status-tool reinforcement clause — in `custom/app/services/custom/scout/system_prompts_service.rb`, placed immediately after the existing `- Fallback para humano: ...` bullet

**Checkpoint**: MVP ready — the entire guardrail bullet (all trigger clauses and the reinforcement clause) is live and testable independently. No further edits to this bullet are made in Phases 4–6; they only add verifying tests.

---

## Phase 4: User Story 2 - Reschedule, Cancellation, or Complaint Requests Handoff (Priority: P1)

**Goal**: Confirm the guardrail (already fully implemented in T004) recognizes reschedule, cancellation, and complaint requests, directing immediate `handover_to_human` without attempting to process or resolve the request on its own.

**Independent Test**: Verify prompt output includes explicit triggers for "reschedule", "cancel", and "complaint", directing immediate `handover_to_human` without attempting to resolve or placate the request.

### Tests for User Story 2

- [X] T005 [P] [US2] Add unit test asserting `guardrails_section` includes explicit triggers for contacts who "quer reagendar/cancelar, tem uma reclamação" directing immediate `handover_to_human` without attempting self-resolution in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

**Checkpoint**: No implementation task in this phase — the clause was already delivered by T004 (single atomic bullet, see "Important" note above). This test locks in independent story-level coverage for the clause that already ships with the MVP.

---

## Phase 5: User Story 3 - Contact Declines Triage Question Handoff (Priority: P2)

**Goal**: Confirm the guardrail (already fully implemented in T004) recognizes a contact answering a Scout-initiated triage question by indicating their need is a quick question unrelated to scheduling an evaluation, directing immediate handoff instead of Scout attempting to answer the question.

**Independent Test**: Verify prompt output includes instructions that answering a triage question with "just a quick question" ("só uma dúvida rápida") unrelated to evaluation scheduling triggers immediate `handover_to_human`.

### Tests for User Story 3

- [X] T006 [P] [US3] Add unit test asserting `guardrails_section` includes the directive for contacts who "responde a uma pergunta de triagem indicando ser 'só uma dúvida rápida' não relacionada a agendar avaliação" directing immediate `handover_to_human` in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

**Checkpoint**: No implementation task in this phase — same rationale as Phase 4.

---

## Phase 6: User Story 4 - Optional Customer-Status Lookup Reinforcement (Priority: P3)

**Goal**: Confirm the guardrail (already fully implemented in T004) states that if an external customer/treatment status tool is configured and phone number is available, Scout may consult it to reinforce the handoff decision, subject to: "Reinforcing only — a positive result strengthens confidence in an already-suggested handoff; absence of the tool, an error, or a non-positive result MUST NOT block or delay the handoff".

**Independent Test**: Verify prompt text includes optional status lookup reinforcement guidance while explicitly stating that a clear signal in the contact's own words is sufficient and external ERP confirmation is never required.

### Tests for User Story 4

- [X] T007 [P] [US4] Add unit test asserting `guardrails_section` includes the guidance that an external tool for contact status may be consulted to reinforce the decision when phone is available, but "um sinal claro na própria fala do cliente já é suficiente para transferir, sem exigir confirmação do ERP" in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

**Checkpoint**: No implementation task in this phase — same rationale as Phase 4. All user stories (US1–US4) are now confirmed covered by the single bullet implemented in T004 and verified across T003, T005, T006, T007.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, compliance, and multi-scenario verification.

- [X] T008 [P] Verify RuboCop linting passes 100% clean with 150-character maximum line length on `custom/app/services/custom/scout/system_prompts_service.rb` and `custom/spec/services/custom/scout/system_prompts_service_spec.rb`; confirm the diff for this feature touches only those two files (no new tool, model, or migration — FR-007)
- [X] T009 [P] Run complete RSpec test suite for prompt service and reactive safety net in `custom/spec/services/custom/scout/system_prompts_service_spec.rb` and `custom/spec/services/custom/scout/action_classifier_service_spec.rb`
- [X] T010 Run behavioral smoke validation using `Custom::Scout::PlaygroundRunner` per `specs/063-non-sales-intent-handoff/quickstart.md`
- [X] T011 [P] Verify fork custom module wiring and audit using `bin/sync-custom-module-hooks` (repo-wide release gate per `CLAUDE.md`; expected no-op since this feature touches only a fork-original file with no upstream/enterprise equivalent — see `plan.md` Testing note)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - verifies safety net baseline before changes
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - delivers the complete guardrail bullet (single atomic edit)
- **User Stories 2-4 (Phases 4-6)**: Depend on User Story 1 (Phase 3) completion - add verifying tests only, no further code changes
- **Polish (Phase 7)**: Depends on all user story phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - delivers the entire guardrail bullet in one edit
- **User Story 2 (P1)**: Can start after User Story 1 - adds a verifying test only; the clause already ships with T004
- **User Story 3 (P2)**: Can start after User Story 1 (independent of US2) - adds a verifying test only
- **User Story 4 (P3)**: Can start after User Story 1 (independent of US2/US3) - adds a verifying test only

### Within Each User Story

- US1: test MUST be written and fail before T004's implementation lands
- US2-US4: tests are written against the already-complete guardrail bullet from T004 and should pass immediately; they exist for independent per-story regression coverage, not to gate new implementation

### Parallel Opportunities

- Within US1, test `T003` can be drafted prior to service implementation `T004`
- Once T004 lands, tests `T005`, `T006`, and `T007` (Phases 4-6) have no inter-dependencies and can all be added in parallel
- In Phase 7, RuboCop check `T008`, RSpec suite `T009`, and sync hooks audit `T011` can run in parallel

---

## Parallel Example: User Story 1

```bash
# Write test first in system_prompts_service_spec.rb:
Task: "Add unit test asserting guardrails_section includes the Reconhecimento de intenção fora de prospecção bullet in custom/spec/services/custom/scout/system_prompts_service_spec.rb"

# Implement the complete guardrail bullet in system_prompts_service.rb:
Task: "Implement the complete Reconhecimento de intenção fora de prospecção guardrail bullet (all clauses) in custom/app/services/custom/scout/system_prompts_service.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`)
2. Complete Phase 2: Foundational baseline check (`T002`)
3. Complete Phase 3: User Story 1 (`T003`, `T004`) — delivers the complete guardrail bullet
4. **STOP and VALIDATE**: Test User Story 1 independently in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`
5. MVP is deliverable — all four stories' clauses are already present in the bullet

### Incremental Delivery

1. Setup + Foundational (`T001`, `T002`) → Baseline confirmed
2. User Story 1 (`T003`, `T004`) → Complete guardrail bullet ships (MVP)
3. User Story 2 (`T005`) → Reschedule/cancellation/complaint clause verified independently
4. User Story 3 (`T006`) → Triage-question decline clause verified independently
5. User Story 4 (`T007`) → Optional status lookup reinforcement clause verified independently
6. Polish & Verification (`T008`–`T011`) → Clean RuboCop, full RSpec, smoke verification, sync hooks audit

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks
- `[Story]` label maps task to specific user story for traceability (`[US1]`, `[US2]`, `[US3]`, `[US4]`)
- RuboCop 150-char line limit must be respected using heredoc line-breaking as done across `system_prompts_service.rb`
- Non-triggers: A returning customer expressing new purchase interest remains ordinary qualification (verified via `quickstart.md` §3e, exercised by `T010`)
- The guardrail bullet is implemented once, in full, in `T004` — Phases 4-6 add tests only (see "Important" note above)
- Verify the US1 test (`T003`) fails before implementing `T004`
