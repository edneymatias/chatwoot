# Quickstart: Validating Opportunity Continuity Detection

Manual/end-to-end validation guide for the four user stories in `spec.md`. Assumes the stack is
already up (`docker compose up -d`) per the project's `CLAUDE.md`, and that a Scout is configured
on an inbox with at least one pipeline stage.

See `data-model.md` for the full decision matrix and `contracts/` for the exact tool/prompt surface
being validated.

## Prerequisites

- A seeded account with a Scout configured and an active pipeline (`docker compose exec rails
  bundle exec rails db:seed`, or the richer `Seeders::AccountSeeder` path from `CLAUDE.md`).
- One test contact with **no** existing deals (for User Story 3), and a way to create a second test
  contact with a pre-existing **open** deal from a **closed** conversation (for User Story 1) — this
  can be done via `bin/rails runner` against `Opportunity.create!` directly, or via the Kanban UI's
  manual creation flow, then resolving that origin conversation.

## User Story 1 — Continuing a known deal in a brand-new conversation

1. Create Contact A with one open `Opportunity` (status `open`) whose `origin_conversation` is
   already resolved/closed.
2. Start a **new** conversation as Contact A (no `OpportunityConversation` link to that deal yet).
3. As Contact A, message the Scout expressing renewed interest in the same business.
4. **Expected**: the assistant's `manage_opportunity` call declares the existing deal's
   `opportunity_id` (visible in the system prompt's `[Oportunidades Abertas do Contato]` block); the
   existing `Opportunity` is updated, no new one is created. Confirm via the Kanban board / DB:
   `Opportunity.where(contact_id: contact_a.id, status: :open).count == 1`.
5. Repeat with a contact whose deal is already linked to the *current* conversation via an existing
   `OpportunityConversation` row (not the origin) — same expected outcome (Acceptance Scenario 2).

## User Story 2 — Ambiguous continuity is never auto-resolved

1. Give Contact B two open deals.
2. Start a new conversation as Contact B and express general commercial interest without naming a
   specific one of the two deals.
3. **Expected**: no new `Opportunity` is created, neither existing one is modified, and a private
   note is added to the conversation explaining the ambiguity (content should reference the
   `ContinuityDecision#reason`, per `contracts/continuity_resolver_service.md`). The conversation
   otherwise continues normally (Scout still replies to the lead).
4. Separately, force the assistant to declare an `opportunity_id` that does not belong to Contact B
   (e.g. via the Playground/tool-testing surface from Phase 06 if available) — confirm the same
   ambiguous outcome (rejected, flagged, no automatic action) rather than silently trusting it.

## User Story 3 — New contact, genuinely new deal (regression guardrail)

1. Use a brand-new contact with zero deals.
2. Message the Scout expressing commercial interest.
3. **Expected**: a new `Opportunity` is created automatically, no ambiguity note, no extra steps —
   unchanged from pre-feature behavior. Confirm the `[Oportunidades Abertas do Contato]` context
   block is absent from the prompt for this contact (0 candidates → section omitted).

## User Story 4 — Rule-triggered creation shares the same logic

1. Configure an automation rule with a `create_opportunity` action, triggered on some conversation
   event (e.g. a label being added), for Contact C.
2. **Case A**: Contact C has zero open deals. Trigger the rule.
   - **Expected**: a new `Opportunity` is created, matching today's behavior.
3. **Case B**: Contact C already has one open deal. Trigger the rule again (new conversation/event).
   - **Expected**: no new `Opportunity` is created, the existing one is untouched, and a private
     note is added to the triggering conversation — the rule never silently reuses or duplicates.
     This is the resolved `/speckit-clarify` behavior: the automation path has no way to declare a
     match, so it always treats "one or more open deals already exist" as ambiguous.

## Regression check

- Run the existing specs for both call sites to confirm no prior behavior broke:
  `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
  custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb
  custom/spec/services/custom/automation_rules/action_service_spec.rb
  custom/spec/services/custom/opportunities/continuity_resolver_service_spec.rb`

**Test coverage note**: `create_opportunity` (the method this feature modifies, in
`custom/app/services/custom/automation_rules/action_service.rb`) currently has **zero direct spec
coverage** — `custom/spec/services/custom/automation_rules/action_service_spec.rb` today only
exercises `.process_campaign_attribution`. The core class this module is mixed into,
`AutomationRules::ActionService` (`app/services/automation_rules/action_service.rb`), takes
**positional** `initialize(rule, account, conversation)` args (upstream code, not the `custom/`
keyword-arg convention). New specs for the reuse/ambiguous scenarios in User Story 4 need to
instantiate that core class positionally and invoke the private method via
`.send(:create_opportunity, params)` — this is new coverage being added, not an extension of an
existing `describe '#create_opportunity'` block, so size the task for it accordingly.
