# Quickstart: Validating Response Auditor Handoff Message Quality

Prerequisites: stack running (`docker compose up -d`), per `AGENTS.md`. All commands below run
inside the `rails` container.

## 1. Classification-accuracy fix (User Story 1 / FR-001, FR-002)

Targeted spec run (see `data-model.md` Entity: Handoff Reason and `contracts/handoff-reason-mapping.md`
for the exact criterion contract):

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/action_classifier_service_spec.rb
```

Expected: a new example replaying a message history equivalent to the production case
(conversation 71393/display 45007 — customer asks for help twice, states a concrete need, answers
qualification questions, then declines exactly one further question) asserts the classifier does
**not** return `action: 'handoff'` / `action_reason: 'out_of_scope_commercial_request'` for that
history. A second new example (existing customer, ongoing unrelated issue / complaint / purely
informational question, no commercial intent) still asserts `out_of_scope_commercial_request` fires —
proving no regression (SC-002).

Behavioral replay (optional, matches the scout-doc's own verification method): use
`Custom::Scout::PlaygroundRunner` against conversation display_id 45007's transcript and confirm the
reply follows the "Respeito ao ritmo do lead" guardrail (acknowledges pace, leaves door open) instead
of transferring.

## 2. Internal note readability (User Story 2 / FR-004, FR-005, FR-008, FR-009)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/handoff_service_spec.rb
```

Expected: for each of the 4 reasons, a new example asserts the created private `Message#content`
(queried via `@conversation.messages.where(private: true).last` or equivalent, per existing spec
conventions in this file) contains the reason's localized `note` label — not the raw enum code —
resolved in `account.locale`, for both `pt-BR` and `en` accounts. A fallback example asserts a
`nil`/blank `reason` still produces today's generic "motivo não informado" text unchanged.

## 3. Customer-facing message (User Story 3 / FR-006, FR-007, FR-009)

Same spec file/run as step 2. Expected: for each of the 4 reasons, a new example asserts the created
public `Message#content` (`private: false`) equals that reason's localized `message`, resolved in
`conversation_locale` (`@conversation.language`, independent of `account.locale` — cover the
divergent-locale edge case explicitly: pt-BR account, English-language conversation). A fallback
example asserts an unrecognized reason still sends today's generic `conversations.scout.handoff` text
unchanged.

## 4. Locale file parity (FR-010)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/handoff_service_spec.rb -e "parity"
```

Expected: a new example (or a small dedicated spec, per project convention for other synced
namespaces) asserts `en.yml` and `pt_BR.yml` expose the identical key set under
`conversations.scout.handoff_reasons`, and no value under that namespace is blank.

## 5. No additional LLM call (FR-011)

Covered implicitly by steps 2–3: the handoff-service specs already stub/avoid `llm_chat` entirely
(reason resolution is pure `I18n.t`), so a passing run with no new LLM-related stub/expectation is
itself the evidence.

## 6. Other two handoff paths unaffected (FR-012)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/jobs/custom/scout/follow_up_job_spec.rb
```

Expected: both suites pass unchanged (no new examples required here — these two paths are explicitly
out of scope per FR-012; a passing existing suite is the regression check).

## Full targeted run for this feature

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/action_classifier_service_spec.rb \
  custom/spec/services/custom/scout/handoff_service_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/jobs/custom/scout/follow_up_job_spec.rb \
  custom/spec/services/custom/scout/response_auditor_spec.rb
```

Do not run the full `bundle exec rspec` suite as part of this feature's iterative loop (Constitution
Principle IX) — reserve that for the pre-release checklist in `AGENTS.md`.
