# Quickstart: Scout Contact Identity Detection

Validation guide for confirming the feature works end-to-end once implemented. Assumes the
container-based dev stack from `CLAUDE.md` (`docker compose up -d`).

## Prerequisites

- Stack running: `docker compose up -d`
- An account with a configured `Scout` (LLM config present — see `Account`/`Scout` setup docs for
  this fork if none exists yet)
- Access to `docker compose exec rails bundle exec rails console`

## 1. Automated specs (primary validation)

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/contact_identity_service_spec.rb \
  custom/spec/services/custom/scout/system_prompts_service_spec.rb \
  custom/spec/services/custom/scout/playground_runner_spec.rb
```

Expected: all examples pass, including (per `data-model.md`):
- `ContactIdentityService.placeholder_name?` table of positive/negative cases (see spec.md Edge
  Cases and `research.md` shape rule), plus an explicit assertion that `contact.name` is unchanged
  after the call (FR-008, added 2026-09-02 per `/speckit-analyze` finding UND1).
- `SystemPromptsService#context_section` includes the warning when `contact.name` is a placeholder,
  and omits it for a real name.
- The warning text asks for the name as early as possible (first response), states priority over a
  pending qualification question (FR-003, FR-012), states it is exempt from the "only ask about
  configured fields" funnel guidance (FR-013), carries a short cross-reference subordinating it
  to the handoff rule (FR-011, added post-audit — see `research.md`), and states it must never be
  asked again once already asked, even if unanswered (FR-005, added 2026-09-02 per finding COV1).
- `SystemPromptsService#guardrails_section` includes the new "Identidade do contato" bullet
  unconditionally, carrying the same immediacy + priority + once-only + FR-013 exemption + handoff
  cross-reference language (FR-005, FR-006, FR-012, FR-013).
- The existing "Fallback para humano" / handoff-closing-reminder examples in
  `system_prompts_service_spec.rb` still pass unchanged — evidence FR-011's generic coverage wasn't
  disturbed.
- **New**: a deterministic example asserting a prompt built for a placeholder-named contact with
  funnel fields configured contains the identity warning, the handoff-reminder text, and the
  funnel-guidance text all simultaneously and unmodified (added post-audit, see `research.md` and
  `data-model.md`) — a fast regression guard that doesn't depend on an LLM call.

## 2. Manual classifier check (Rails console)

```ruby
docker compose exec rails bundle exec rails console

Custom::Scout::ContactIdentityService.placeholder_name?(Contact.new(name: 'empty-meadow-50'))
# => true
Custom::Scout::ContactIdentityService.placeholder_name?(Contact.new(name: 'polished-forest-561'))
# => true
Custom::Scout::ContactIdentityService.placeholder_name?(Contact.new(name: 'Maria Silva'))
# => false
Custom::Scout::ContactIdentityService.placeholder_name?(Contact.new(name: 'primeirazinha11234'))
# => false
Custom::Scout::ContactIdentityService.placeholder_name?(Contact.new(name: nil))
# => false
```

## 3. Prompt assembly check (Rails console)

```ruby
account  = Account.first
scout    = account.scouts.first
placeholder_contact = account.contacts.create!(name: 'empty-meadow-50', identifier: SecureRandom.uuid)

prompt = Custom::Scout::SystemPromptsService.build(scout: scout, contact: placeholder_contact)
prompt.include?('AVISO') # => true — conditional warning present
prompt.include?('Identidade do contato') # => true — guardrail bullet always present
```

Inspect the warning text manually to confirm it asks for immediacy (first response), priority over
qualification (FR-003, FR-006, FR-012), exemption from the configured-fields-only funnel guidance
(FR-013), and the short handoff cross-reference clause (FR-011 subordination, added post-audit) —
these are wording requirements, not booleans, so eyeball the actual paragraph rather than a single
`include?` check.

## 4. Behavioral replay (smoke tests via `PlaygroundRunner`, per spec.md SC-001 and the clarified FRs)

Per `research.md`, `PlaygroundRunner` gains an optional `contact:` param so this replay can
actually exercise the contact-context warning:

```ruby
runner = Custom::Scout::PlaygroundRunner.new(
  scout: scout,
  contact: placeholder_contact,
  message: '<first customer message from the replayed conversation>',
  message_history: [] # build up turn-by-turn from the real conversation transcript
)
runner.perform[:reply]
```

### 4a. Core replay (SC-001)

Reconstruct the message sequence from the real conversation referenced in the source design
(`docs/kanban/ciclo 10/scout/19-contact-identity-and-conversation-labeling/spec81.md`, conversation
`display_id 51`) turn by turn, feeding each prior turn into `message_history`. Confirm the **first**
reply asks for the customer's preferred name (FR-003 — immediacy, not "at some point" as originally
drafted), and that a subsequent turn's `tool_calls` includes an `update_contact` call once a
name-like answer is given.

### 4b. Priority over qualification (FR-012)

Using the same `placeholder_contact`, send a first message that itself contains a clear
qualification cue (e.g. "Quero saber o preço do plano Enterprise para minha empresa"). Confirm the
reply asks for the visitor's name rather than jumping straight into the pricing/qualification
question — the identity question must win the single question-per-turn slot.

### 4c. Handoff suppression (FR-011 — expected already-passing, not new behavior)

Using a placeholder-named contact, drive the conversation (via `message_history`) to the point where
the next tool call would be `handover_to_human` (or an opportunity stage transition that triggers
handoff). Confirm the final reply contains **no question at all** — neither a qualification question
nor the identity question. Per `research.md`, this should already pass unmodified today, since the
existing "no questions in a handoff-ending turn" guardrail is unconditional; this step is a
regression check, not a test of new code. Note this scenario only exercises the model-obedience
path (tool-called or stage-transition handoff); the separate `ResponseAuditor`-triggered handoff
path is safe independent of the prompt (it always sends the fixed handoff sentence by code, never
the model's own text — see `research.md`), so it needs no behavioral test here.

### 4d. No repeat when unanswered (FR-005 — added 2026-09-02 per `/speckit-analyze` finding COV1)

Using a fresh placeholder-named contact, send a first message that does **not** answer the identity
question (e.g. ignore it and ask an unrelated question back, or reply with something that isn't a
name). Feed that as the next turn's `message_history` and send a second message. Confirm the
**second** reply does not repeat the identity question — since `contact.name` is still unchanged
(the visitor never gave a usable answer), this is the one case where the warning keeps re-injecting
every turn, so it's the scenario that actually exercises the new "never ask again once already
asked, even if unanswered" clause (as opposed to the happy path, where `contact.name` changes after
a successful answer and the warning naturally stops appearing on its own).

**Caveat** (already noted in the source spec): this is a smoke test, not a determinism guarantee —
the underlying model is stochastic. Final validation is the manual operator test in the real widget
described below.

## 5. Manual end-to-end check (real widget, final validation)

1. Open the website widget in an incognito/private window (ensures a fresh, unidentified contact).
2. Start a conversation and go through a normal qualification flow without volunteering a name.
3. Confirm Scout asks how you'd like to be called in its very first response (not deferred), and
   never addresses you by a generated placeholder like "Olá, Empty Meadow!" beforehand.
4. Reply with a name; confirm the contact record is updated (check via the agent-side contact panel
   or `Contact.find_by(...).name` in console) and that Scout greets you by name afterward.
5. Repeat with a WhatsApp-connected inbox where the channel profile name already looks like a real
   name — confirm Scout does **not** ask (no regression, per spec.md SC-004).
6. Repeat once more driving straight toward a qualified handoff (e.g. clearly stating a purchase
   intent immediately) with a placeholder-named contact — confirm Scout never asks for the name in
   the same turn it hands off (FR-011).

## Expected outcome

All of the above pass with no changes required to `app/models/contact.rb`,
`ContactInboxWithContactBuilder`, or any file outside `custom/app/services/custom/scout/` and its
specs (per Constitution Principle I check in `plan.md`).
