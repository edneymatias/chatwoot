---
description: "Task list for Routine-Request Guardrail False Positive & Persona Precedence Fix implementation"
---

# Tasks: Routine-Request Guardrail False Positive & Persona Precedence Fix

**Input**: Design documents from `specs/071-scout-guardrail-precedence-fix/`
**Prerequisites**: [`plan.md`](file:///home/matias/Projects/chatwoot/specs/071-scout-guardrail-precedence-fix/plan.md), [`spec.md`](file:///home/matias/Projects/chatwoot/specs/071-scout-guardrail-precedence-fix/spec.md), [`research.md`](file:///home/matias/Projects/chatwoot/specs/071-scout-guardrail-precedence-fix/research.md), [`data-model.md`](file:///home/matias/Projects/chatwoot/specs/071-scout-guardrail-precedence-fix/data-model.md), [`quickstart.md`](file:///home/matias/Projects/chatwoot/specs/071-scout-guardrail-precedence-fix/quickstart.md)

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)
- Include exact file paths in descriptions

## Path Conventions

- **Custom fork tree**: `custom/app/services/custom/scout/`, `custom/spec/services/custom/scout/`
- **Root tooling/specs**: `specs/071-scout-guardrail-precedence-fix/`, `bin/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify baseline development environment and prompt builder test suite.

- [X] T001 Verify existing test suite and Scout prompt builder baseline in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core safety baseline that MUST be verified before prompt modifications begin.

**⚠️ CRITICAL**: Confirm baseline safety net specs pass to guarantee FR-007 compliance (reactive safety net unaffected).

- [X] T002 Verify baseline regression suite for reactive Response Auditor in `custom/spec/services/custom/scout/action_classifier_service_spec.rb` to ensure no changes to `ActionClassifierService` behavior per FR-007

**Checkpoint**: Foundation ready - user story implementation and tests can begin.

---

## Phase 3: User Story 1 - Routine/low-complexity requests are qualified, not handed off (Priority: P1) 🎯 MVP

**Goal**: A lead stating a routine, low-complexity, preventive, or recurring request with no specific problem on the first triage answer is recognized as a valid new commercial opportunity and qualified through the normal funnel instead of triggering immediate human handoff.

**Independent Test**: Verify prompt text includes the exhaustive "apenas quando:" criteria and explicit carve-out stating "Uma nova solicitação de baixa complexidade, preventiva, recorrente ou sem um problema específico descrito continua sendo uma oportunidade comercial nova e válida — siga o funil de qualificação normalmente nesses casos", and smoke test with lead stating routine request ("apenas consulta de rotina") continues qualification without `handover_to_human`.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T003 [US1] [U1][U6][A1][A2] Update and add unit tests in `custom/spec/services/custom/scout/system_prompts_service_spec.rb` asserting the "Reconhecimento de intenção fora de prospecção" bullet specifies exhaustive criteria introduced by "apenas quando:" (no longer the old illustrative "ex.:"), includes the explicit carve-out verbatim: "Uma nova solicitação de baixa complexidade, preventiva, recorrente ou sem um problema específico descrito continua sendo uma oportunidade comercial nova e válida — siga o funil de qualificação normalmente nesses casos", and contains no clause conditioning the classification on which conversational turn or phrasing surfaced the request (FR-001, FR-002, FR-003); verify tests fail before implementation

### Implementation for User Story 1

- [X] T004 [US1] [U1][U2][U3][U4][U5][U6][U7][U8][U9][A1][A2] Rewrite the "Reconhecimento de intenção fora de prospecção" bullet in `guardrails_section` of `custom/app/services/custom/scout/system_prompts_service.rb` verbatim per data-model.md: `- Reconhecimento de intenção fora de prospecção: Se em qualquer momento ficar claro que o contato não busca uma nova oportunidade comercial — apenas quando: já é cliente com um produto ou serviço em andamento, quer alterar ou cancelar algo que já existe (não uma nova solicitação), tem uma reclamação, ou faz uma pergunta puramente informativa sem nenhum sinal de interesse em um novo produto ou serviço — não tente resolver a questão por conta própria, mesmo que pareça simples. Utilize `handover_to_human` imediatamente. Uma nova solicitação de baixa complexidade, preventiva, recorrente ou sem um problema específico descrito continua sendo uma oportunidade comercial nova e válida — siga o funil de qualificação normalmente nesses casos. Se houver uma ferramenta externa configurada para verificar o status do contato (cliente existente, produto ou serviço em andamento) e o telefone já estiver disponível, consulte-a para reforçar a decisão — mas um sinal claro na própria fala do cliente já é suficiente para transferir, sem exigir confirmação do ERP.`

- [X] T014 [US1] [A1] Confirm outer-loop behavior A1 is green: run `custom/spec/services/custom/scout/system_prompts_service_spec.rb` and verify the T003 assertions on the exhaustive "apenas quando:" framing and the explicit routine-request carve-out now pass
- [X] T015 [US1] [A2] Confirm outer-loop behavior A2 is green: verify the T003 assertion that no clause conditions the routine-request classification on which conversational turn or phrasing surfaced it passes

**Checkpoint**: MVP ready — the rewritten guardrail bullet with exhaustive non-prospecting criteria and explicit routine-request carve-out is live and verified by T003 and T004.

---

## Phase 4: User Story 2 - Genuine non-prospecting signals still hand off immediately (Priority: P1)

**Goal**: Ensure contacts presenting genuine non-prospecting signals (existing customer with product/service in progress, rescheduling/cancelling existing item, complaint, or purely informational question) continue triggering immediate human handoff with zero regression.

**Independent Test**: Verify unit tests assert all 4 objective non-prospecting criteria in prompt and confirm relative ordering (`Fallback para humano:` < `Reconhecimento de intenção fora de prospecção:` < `Idioma e Estilo:`) remains intact.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T005 [US2] [U2][U3][U4][U5][U9][A3][A4][A5] Update unit tests in `custom/spec/services/custom/scout/system_prompts_service_spec.rb` asserting the 4 objective non-prospecting criteria ("já é cliente com um produto ou serviço em andamento", "quer alterar ou cancelar algo que já existe (não uma nova solicitação)", "tem uma reclamação", "faz uma pergunta puramente informativa sem nenhum sinal de interesse em um novo produto ou serviço") and verifying bullet ordering (`Fallback para humano` < `Reconhecimento de intenção...` < `Idioma e Estilo`) is preserved (FR-001, FR-003); verify tests fail before implementation
- [X] T006 [P] [US2] Run reactive safety net regression specs in `custom/spec/services/custom/scout/action_classifier_service_spec.rb` to confirm zero changes and full pass per FR-007

- [X] T016 [US2] [A3] Confirm outer-loop behavior A3 is green: verify the T005 assertion for "já é cliente com um produto ou serviço em andamento" passes
- [X] T017 [US2] [A4] Confirm outer-loop behavior A4 is green: verify the T005 assertions for "quer alterar ou cancelar algo que já existe (não uma nova solicitação)" and "tem uma reclamação" pass
- [X] T018 [US2] [A5] Confirm outer-loop behavior A5 is green: verify the T005 assertion for "faz uma pergunta puramente informativa sem nenhum sinal de interesse em um novo produto ou serviço" passes

**Checkpoint**: User Stories 1 and 2 are fully functional and independently tested with both positive qualification and negative handoff cases verified.

---

## Phase 5: User Story 3 - Account persona instructions can actually refine commercial-intent classification (Priority: P2)

**Goal**: Account persona instructions can refine or expand what counts as valid commercial intent specifically for the non-prospecting-intent guardrail, while instructions that contradict non-negotiable guardrails (anti-hallucination, JSON format, anti-false-promise, action confirmation) continue to have no effect.

**Independent Test**: Verify prompt text names "Reconhecimento de intenção fora de prospecção" as the sole exception that custom instructions may refine/expand even if touching the same subject, names non-negotiable guardrails (Anti-alucinação, Anti-falsa-promessa, Confirmação de ação), and states no other guardrail may be altered.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T007 [US3] [U10][U11][U12][U13][U14][A6][A7] Add unit tests in `custom/spec/services/custom/scout/system_prompts_service_spec.rb` asserting `custom_instructions_section` precedence text names the non-negotiables ("Anti-alucinação, Anti-falsa-promessa e Confirmação de ação") while retaining the pre-existing JSON-response-format and context-only requirements in the same clause, names "Reconhecimento de intenção fora de prospecção" as the sole exception that persona instructions can refine/expand ("mesmo que pareçam, à primeira vista, tocar no mesmo assunto dessa diretriz"), and explicitly forbids altering any other guardrail ("Nenhuma outra diretriz da seção acima pode ser alterada por estas instruções") (FR-004, FR-005, FR-006); verify tests fail before implementation

### Implementation for User Story 3

- [X] T008 [US3] [U10][U11][U12][U13][U14][U15][U16][A6][A7] Rewrite the precedence sentence in `custom_instructions_section` of `custom/app/services/custom/scout/system_prompts_service.rb` verbatim per data-model.md: `As instruções a seguir foram configuradas pelo administrador da conta. Siga-as, exceto quando conflitarem com o formato de resposta JSON, com a exigência de responder exclusivamente a partir do contexto fornecido, ou com as diretrizes inegociáveis de segurança e resposta descritas acima — no mínimo, Anti-alucinação, Anti-falsa-promessa e Confirmação de ação. A diretriz "Reconhecimento de intenção fora de prospecção" é a única exceção: estas instruções podem refinar ou expandir o que conta como uma nova oportunidade comercial válida especificamente nesse critério, mesmo que pareçam, à primeira vista, tocar no mesmo assunto dessa diretriz. Nenhuma outra diretriz da seção acima pode ser alterada por estas instruções.`

- [X] T019 [US3] [A6] Confirm outer-loop behavior A6 is green: verify the T007 assertion naming "Reconhecimento de intenção fora de prospecção" as the sole persona-refinable exception, including on subject-matter overlap, passes
- [X] T020 [US3] [A7] Confirm outer-loop behavior A7 is green: verify the T007 assertions naming the non-negotiable guardrails and forbidding alteration of any other guardrail pass

**Checkpoint**: All three user stories are implemented and independently tested.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, compliance, and multi-scenario verification.

- [X] T009 [P] [U7] Verify domain-agnostic wording per SC-004 with regex check `grep -niE "odont|dental|clinic|avaliação (odont|dentária)|consulta (odont|médica)" custom/app/services/custom/scout/system_prompts_service.rb` confirming zero matches
- [X] T010 [P] Run RuboCop on `custom/app/services/custom/scout/system_prompts_service.rb` and `custom/spec/services/custom/scout/system_prompts_service_spec.rb` to confirm zero offenses and adherence to 150-character limit / heredoc exemption
- [X] T011 [P] Run complete RSpec suite for prompt service in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`
- [X] T012 Run behavioral replay smoke tests using `Custom::Scout::PlaygroundRunner` per `specs/071-scout-guardrail-precedence-fix/quickstart.md` §4 (SC-001, SC-002, SC-003)
- [X] T013 [P] Verify custom module hooks with `bin/sync-custom-module-hooks --check` (62/62 wiring points present) and review `bin/sync-custom-module-hooks --audit` (13 pre-existing gaps in spec-kit tooling/unrelated configs, 0 gaps in feature files)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - verifies safety net baseline before changes
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - delivers the complete guardrail bullet (MVP)
- **User Story 2 (Phase 4)**: Depends on User Story 1 (Phase 3) - verifies genuine non-prospecting criteria and safety net regression
- **User Story 3 (Phase 5)**: Depends on User Story 1 (Phase 3) - delivers persona precedence exception
- **Polish (Phase 6)**: Depends on all user story phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - no dependencies on other stories; delivers Fragment 1 in `guardrails_section`
- **User Story 2 (P1)**: Can start after User Story 1 - verifies non-prospecting clauses and safety net regression without altering Fragment 1
- **User Story 3 (P2)**: Can start after User Story 1 - independent prompt fragment (`custom_instructions_section`); delivers Fragment 2

### Within Each User Story

- Tests MUST be written and fail before implementation (Constitution Principle VI)
- US1: `T003` fails before `T004` implements Fragment 1; `T014`–`T015` confirm outer-loop behaviors A1/A2 are green afterward
- US2: `T005` locks in non-prospecting criteria and ordering; `T006` runs regression suite; `T016`–`T018` confirm outer-loop behaviors A3/A4/A5 are green afterward
- US3: `T007` fails before `T008` implements Fragment 2; `T019`–`T020` confirm outer-loop behaviors A6/A7 are green afterward

### Parallel Opportunities

- In Phase 4, `T006` (`action_classifier_service_spec.rb`) can run in parallel with `T005` (`system_prompts_service_spec.rb`)
- In Phase 6, `T009` (grep check), `T010` (RuboCop), `T011` (RSpec suite), and `T013` (sync hooks audit) can all execute in parallel

---

## Parallel Example: User Story 1

```bash
# Write failing test first in system_prompts_service_spec.rb:
Task: "Update and add unit tests in custom/spec/services/custom/scout/system_prompts_service_spec.rb asserting the Reconhecimento de intenção fora de prospecção bullet specifies exhaustive criteria"

# Implement Fragment 1 in system_prompts_service.rb:
Task: "Rewrite the Reconhecimento de intenção fora de prospecção bullet in guardrails_section of custom/app/services/custom/scout/system_prompts_service.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`)
2. Complete Phase 2: Foundational baseline check (`T002`)
3. Complete Phase 3: User Story 1 (`T003`, `T004`, `T014`, `T015`) — delivers the rewritten guardrail bullet
4. **STOP and VALIDATE**: Test User Story 1 independently in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`
5. MVP is deliverable — routine requests are now qualified through the funnel

### Incremental Delivery

1. Setup + Foundational (`T001`, `T002`) → Baselines confirmed
2. User Story 1 (`T003`, `T004`, `T014`, `T015`) → Rewritten guardrail bullet ships (MVP!)
3. User Story 2 (`T005`, `T006`, `T016`–`T018`) → Genuine non-prospecting signals and safety net confirmed
4. User Story 3 (`T007`, `T008`, `T019`, `T020`) → Persona precedence refinement ships
5. Polish & Verification (`T009`–`T013`) → Domain check, RuboCop, full RSpec, smoke replay, sync hooks audit

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks
- `[Story]` label maps task to specific user story for traceability (`[US1]`, `[US2]`, `[US3]`)
- RuboCop 150-char line limit is exempted inside heredocs (`AllowHeredoc: true`), matching existing long lines in `system_prompts_service.rb`
- Non-negotiable guardrails (Anti-alucinação, Anti-falsa-promessa, Confirmação de ação, JSON format, context only) remain strictly protected
- Verify tests fail before implementing each user story (Constitution Principle VI)
- Bracketed ids like `[U1]`/`[A1]` mark which `specs/071-scout-guardrail-precedence-fix/tdd/test-list.md` behavior a task covers; `/speckit.tdd.run` ticks a task's checkbox only when it can read a behavior id from it
- `T014`–`T020` are outer-loop completion gates (Phase 5 of `/speckit.tdd.plan`): each story's acceptance behaviors must be green, not just its unit tests, before the story counts as done

---

## Phase 7: TDD remediation

**Source**: `specs/071-scout-guardrail-precedence-fix/tdd/verification.md` (`/speckit.tdd.verify`,
verdict `PASS_WITH_GAPS`). Not a blocker — no `FAIL`-triggering condition was found (no test-quality
`HIGH` smell, no untested criterion, no weakened test, no surviving mutant in a `DONE` behavior) — but
Finding 3 is a real completion-claim-with-no-evidence gap and should close before this feature is
considered fully verified end to end.

- [X] T021 [Finding 3, HIGH] Actually run `quickstart.md` §4's `PlaygroundRunner` replay (§4a–§4e, covering SC-001, SC-002, SC-003) and record the transcript/`result[:tool_calls]` output for each scenario in `specs/071-scout-guardrail-precedence-fix/tdd/behavioral-replay-evidence.md`
- [ ] T022 [Finding 1, MED] Once the user approves committing this feature's changes (per `AGENTS.md`'s
  workflow constraint), commit test and source changes in the same per-cycle order the cycle log
  claims (tests before/with their implementing edit), so a future audit can classify these behaviors
  `PROVEN` instead of `LIKELY`. Verify with `git log --stat` showing test-file commits at or before
  their corresponding source-file commit for each of the 5 cycles.
- [X] T023 [Finding 2, MED] Refresh the stale `test` column line-number pointers in `specs/071-scout-guardrail-precedence-fix/tdd/test-list.md` for `U8` (148 → 153), `U15` (154-158 → 178-184), and `U16` (180-185 → 221)
- [X] T024 [Finding 4, LOW] Reword `tasks.md` `T013`'s completion text to match what `bin/sync-custom-module-hooks --audit` actually confirms (`--check`: 62/62 wiring points present; `--audit`: pre-existing gaps in spec-kit tooling/`Gemfile`/`vite.config.ts` are unrelated to this feature's files) rather than "confirm zero gaps"
