# Quickstart: Contact Panel Opportunity Quick Create

Manual validation guide for this feature once implemented. Assumes the dev stack is already
running (`docker compose up -d`) and the Opportunities/Kanban feature flag is enabled for the test
account (see `plan.md` for touched files; see `contracts/component-interfaces.md` and
`data-model.md` for the underlying prop/mutation contracts these steps exercise).

## Prerequisites

- A seeded account with at least one contact that has an open conversation and **no** linked
  opportunity yet (`docker compose exec rails bundle exec rails db:seed`, or use
  `Seeders::AccountSeeder` per `CLAUDE.md` for richer data).
- A second contact (or the same contact via a second conversation) that already has an opportunity
  linked to a conversation, to validate the disabled-state and reorder/highlight scenarios.
- Logged into the dashboard at an open conversation for each contact above.

## Scenario 1 — Create from the open conversation (User Story 1, FR-001–FR-003, FR-008)

1. Open a conversation whose contact has no opportunity linked to *this* conversation.
2. Open the Contact Panel's Opportunities section.
3. **Expect**: an "Add opportunity" link-style action is visible and enabled.
4. Click it.
5. **Expect**: `OpportunityCreateModal` opens with the contact already fixed to the conversation's
   contact (no search needed).
6. Fill in title + stage (and any required fields for that stage) and submit.
7. **Expect**: the modal closes, and the new opportunity appears **at the top** of the Contact
   Panel's Opportunities list immediately — no manual refresh.

## Scenario 2 — Guardrail: one opportunity per conversation (User Story 2, FR-002, FR-004, FR-005)

1. Revisit the same conversation from Scenario 1 (now has a linked opportunity).
2. **Expect**: the "Add opportunity" action is now disabled.
3. Open a *different* conversation whose contact has no opportunity linked to it, click
   "Add opportunity".
4. **Expect**: the contact chip in the modal is read-only — no "Clear" button, no search input.
5. Open the opportunity creation flow from a non-conversation entry point (Kanban column "+", or
   the List view's "add opportunity" button).
6. **Expect**: contact search-and-select works exactly as before this feature (unaffected).

## Scenario 3 — Reorder and highlight (User Story 3, FR-006, FR-007)

1. Open a conversation whose contact has multiple opportunities, including one linked to *this*
   conversation but not created most recently.
2. **Expect**: the opportunity linked to the current conversation appears **first** in the Contact
   Panel list, with a visually distinct bottom border/accent versus the rest, which retain their
   prior relative order.

## Scenario 4 — Modal closes on conversation switch (FR-010, edge case)

1. Open a conversation, click "Add opportunity" to open the creation flow, start filling in the
   title (don't submit).
2. Switch to a different open conversation (e.g. click another conversation in the inbox list).
3. **Expect**: the creation flow closes automatically and the in-progress input is discarded — it
   does not remain open bound to the conversation you navigated away from.

## Automated checks

- `docker compose exec vite pnpm test` — component/store specs for the touched files
  (`ContactOpportunities.vue`, `ContactOpportunityCard.vue`, `OpportunityCreateModal.vue`,
  `store/modules/opportunities`).
- `docker compose exec vite pnpm eslint` — lint the touched Vue/JS files.
