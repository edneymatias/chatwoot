# Quickstart: Validating Scout Audience Targeting

Prerequisites: the container dev stack is running (`docker compose up -d`), you have an account
with at least one enabled Scout attached to an inbox (see existing Scout setup phases), and you
can send messages into that inbox as two different contacts (e.g. two WhatsApp/API-channel test
numbers).

## 1. Baseline — no audience configured (regression check)

1. Open the Scout's detail page in the dashboard and confirm the new "Público-Alvo" / "Target
   Audience" tab shows the empty state ("Sem público-alvo configurado — o Scout atende todos os
   contatos desta inbox.").
2. Send a message into the inbox from **any** test contact.
3. **Expected**: the conversation is picked up by the Scout as before this feature — confirms
   FR-003 / SC-003 (no regression when unconfigured).

## 2. Configure a target audience (US1)

1. On the Target Audience tab, add a condition, e.g. `phone_number` `equal_to` `<contact A's
   number>`, and save.
2. Reload the tab and confirm the condition persisted (see `contracts/scouts-api.md` for the
   expected `audience` shape in the Scout's API response).
3. **Expected**: matches FR-001/FR-002/FR-008 — condition-building UI reuses the existing
   Contacts/Kanban filter component (`ConditionRow.vue`).

## 3. Matching contact still gets the Scout (US1 + US2)

1. As Contact A (the one matching the saved condition), send a new message into the inbox.
2. **Expected**: conversation is created `pending` and picked up by the Scout, same as always —
   confirms FR-004.

## 4. Non-matching contact is routed to the human queue on a new conversation (US2)

1. As Contact B (does **not** match the saved condition), send a new message into the inbox for
   the first time.
2. **Expected**: the conversation appears directly in the normal (human) conversation queue with
   status `open`, not `pending` — the Scout never engages it. Confirms FR-005 / SC-002.

## 5. Non-matching contact reopening a resolved conversation is also routed to the human queue (US3)

1. Take an existing resolved conversation belonging to Contact B.
2. As Contact B, send a new message on that resolved conversation.
3. **Expected**: the conversation reopens with status `open` (human queue), not handed back to the
   Scout. Confirms FR-006 / SC-002.

## 6. Clear the audience (User Story 1, Acceptance Scenario 4)

1. Remove all conditions from the Target Audience tab and save.
2. Repeat step 4 with Contact B.
3. **Expected**: Contact B is now engaged by the Scout again — audience is empty, so the Scout
   reverts to engaging everyone. Confirms FR-003.

## 7. Forward-only application on audience edits (Clarification, FR-011)

1. With Contact A still matching an active audience condition and mid-conversation (`pending`,
   Scout engaged), edit the audience so Contact A **no longer** matches, and save.
2. **Expected**: the already-`pending` conversation with Contact A is left untouched — still
   `pending`, still with the Scout — because the change only applies to conversations created or
   reopened after the edit, not retroactively. Confirms FR-011.
3. Have Contact A resolve that conversation, then send a new message to reopen it (or start a
   brand-new conversation).
4. **Expected**: this time the new/reopened conversation goes to the human queue (`open`), since
   the audience no longer matches Contact A as of this point onward.

## 8. Per-condition fail-safe on bad values (Edge Case, FR-007)

Covered by automated tests rather than manual verification (see
`custom/spec/services/custom/scout/audience_matcher_service_spec.rb`):
- A `greater_than`/`less_than` condition compared against a non-numeric value must evaluate that
  one condition as "no match" and let the rest of the audience evaluate normally — not raise.
- A genuinely unexpected error (e.g. simulating a bug via a stubbed method raising `NoMethodError`)
  must NOT be silently swallowed into "engage anyway" — it should propagate, confirming the
  matcher does not use a blanket top-level rescue (see research.md).

## Running the automated checks

```bash
# Backend
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/audience_matcher_service_spec.rb \
  custom/spec/models/custom/conversation_spec.rb \
  custom/spec/models/custom/message_spec.rb \
  custom/spec/models/scout_spec.rb \
  custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb

# Frontend
docker compose exec vite pnpm test -- ScoutAudienceTab
```
