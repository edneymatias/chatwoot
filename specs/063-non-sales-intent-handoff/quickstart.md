# Quickstart: Non-Sales Intent Recognition and Immediate Handoff

Validation guide for confirming the feature works end-to-end once implemented. Assumes the
container-based dev stack from `CLAUDE.md` (`docker compose up -d`).

## Prerequisites

- Stack running: `docker compose up -d`
- An account with a configured `Scout` (LLM config present)
- Access to `docker compose exec rails bundle exec rails console`

## 1. Automated spec (primary validation)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb
```

Expected: all examples pass, including a new example asserting `guardrails_section` contains the
"Reconhecimento de intenção fora de prospecção" bullet (per FR-001–FR-005 in `spec.md` and
Decision 1 in `research.md`), placed after the existing "Fallback para humano" bullet, and that all
pre-existing guardrail examples (including "Fallback para humano" and the handoff-closing
reminder) still pass unchanged — evidence the new bullet didn't disturb existing behavior.

## 2. Prompt assembly check (Rails console)

```ruby
account = Account.first
scout   = account.scouts.first

prompt = Custom::Scout::SystemPromptsService.build(scout: scout)
prompt.include?('Reconhecimento de intenção fora de prospecção') # => true — unconditional, present for every account
```

## 3. Behavioral replay (smoke tests via `PlaygroundRunner`, per spec.md SC-001)

```ruby
runner = Custom::Scout::PlaygroundRunner.new(
  scout: scout,
  message: '<contact message under test>',
  message_history: [] # build up turn-by-turn if the scenario needs prior context
)
runner.perform[:reply]
```

### 3a. Existing customer / ongoing treatment (User Story 1)

Send a message stating the contact is already a customer or has a treatment in progress (e.g. "Já
sou paciente, estou em tratamento e preciso remarcar minha consulta"). Confirm the reply's
`tool_calls` include `handover_to_human` and the final text is a natural closing message (no
attempt to resolve the reschedule itself, no question — per the existing handoff-closing rule).

### 3b. Reschedule / cancel / complaint (User Story 2)

Repeat 3a's assertion pattern with three separate messages: a reschedule request, a cancellation
request, and a complaint. Confirm each drives an immediate `handover_to_human` call rather than
Scout attempting to process the request itself.

### 3c. Triage-question decline (User Story 3)

Feed a `message_history` where the last assistant turn asks the triage question (e.g. "você quer
tirar uma dúvida rápida ou está buscando informações sobre um tratamento específico?"), then send a
contact message indicating "só uma dúvida rápida" unrelated to scheduling an evaluation. Confirm
the reply calls `handover_to_human` instead of attempting to answer the question.

### 3d. Optional reinforcement never blocks handoff (User Story 4)

Repeat 3a with two account configurations:
- **With** a `ScoutTool` configured for customer-status lookup and the contact's phone number
  present — confirm handoff still occurs even if the tool call returns no match or errors.
- **Without** any such tool configured — confirm handoff occurs identically, based on the
  contact's words alone.

### 3e. Non-trigger regression check (Edge Cases)

Send a message from a contact expressing new purchase interest despite mentioning a past,
completed treatment (e.g. "já fiz tratamento com vocês antes e quero fazer outro agora"). Confirm
Scout continues ordinary qualification (no immediate handoff) — this guardrail must not fire on a
legitimate returning-prospect case.

**Caveat**: these are smoke tests, not a determinism guarantee — the underlying model is
stochastic. Final validation is the manual operator test below.

## 4. Reactive safety net regression check

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/action_classifier_service_spec.rb
```

Expected: unchanged, all passing — confirms the Fase 12 reactive `ActionClassifierService`
(`out_of_scope_commercial_request`) safety net was not modified by this feature (per FR-006 and
Decision 4 in `research.md`).

## 5. Manual end-to-end check (real widget or connected channel, final validation)

1. Start a conversation as an existing customer and state you already have a treatment in
   progress. Confirm Scout transfers to a human immediately rather than continuing to qualify you.
2. Repeat, asking to reschedule an appointment. Confirm the same immediate handoff.
3. Repeat, letting Scout ask its own triage question, then answer that it's "just a quick question"
   unrelated to a new evaluation. Confirm the same immediate handoff.
4. If an account has an external customer-status `ScoutTool` configured, repeat step 1 and confirm
   the handoff still happens the same way regardless of what that tool returns.

## Expected outcome

All of the above pass with no changes required to any file outside
`custom/app/services/custom/scout/system_prompts_service.rb` and its spec (per Constitution
Principle I check in `plan.md`), and with `ActionClassifierService` behavior fully unchanged.
