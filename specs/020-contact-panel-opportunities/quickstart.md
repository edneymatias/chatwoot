# Quickstart: Contact Panel Opportunities Section

Validation scenarios for this feature, tied to the spec's User Stories and Acceptance Scenarios. See [data-model.md](./data-model.md) for entity details and [contracts/contact-opportunities-filter.md](./contracts/contact-opportunities-filter.md) for the request/response shapes referenced below.

## Prerequisites

- Stack running: `docker compose up -d`
- An account with the opportunities/kanban feature flag enabled (`FEATURE_FLAGS.OPPORTUNITIES` / `Concerns::KanbanFeatureGuard`), and at least one pipeline with stages.
- A contact with three opportunities in different statuses (one `open`, one `won`, one `lost`), each in different pipeline stages, seeded via `Seeders::AccountSeeder` or created manually through the existing kanban board create flow.

## Scenario 1 — View a contact's opportunities (User Story 1, P1)

1. Open a conversation belonging to the seeded contact.
2. Expand the "Opportunities" section in the contact panel.
3. **Expect**: all three opportunities listed, most-recently-created first, each showing title, status, creation date, current stage, and time in stage.
4. Open a conversation for a different contact with zero opportunities.
5. **Expect**: the section shows an empty-state message instead of a list.
6. Repeat step 1–3 against an account without the opportunities feature flag enabled.
7. **Expect**: no "Opportunities" entry appears in the sidebar at all.

Backend check: `GET /api/v1/accounts/:account_id/opportunities?contact_id=:contact_id` returns only that contact's opportunities, most-recent-first — see the filter contract.

## Scenario 2 — Edit an opportunity from the conversation (User Story 2, P2)

1. From the panel's opportunity list, click the `open` opportunity's card.
2. **Expect**: an edit dialog opens in place (no navigation), pre-filled with title, stage, value, and custom attributes.
3. Select a different stage that has additional required custom attributes.
4. **Expect**: those fields appear in the dialog and block saving until filled in.
5. Fill them in, save.
6. **Expect**: 200 response, dialog reflects saved values, list entry updates to the new stage.
7. Reopen the dialog and move the opportunity backward to an earlier stage that would otherwise have unmet requirements.
8. **Expect**: save succeeds without being blocked by that stage's required-fields check (FR-011).

## Scenario 3 — Reopen a closed opportunity (User Story 3, P3)

1. From the panel, open the edit dialog for the `won` (or `lost`) opportunity.
2. **Expect**: dialog shows the current stage as read-only text plus a reopen action; no stage selector is present yet.
3. Click the reopen action.
4. **Expect**: the opportunity's status becomes `open` immediately (single `PUT` with `{ "status": "open" }`), and — without closing/reopening the dialog — the read-only stage display is replaced by an editable stage selector.
5. Select a stage and save as in Scenario 2.
6. **Expect**: save succeeds per the same forward/backward rules as Scenario 2.

## Scenario 4 — Cross-surface consistency (SC-005)

1. Edit an opportunity's stage/value/custom attributes from the kanban board directly.
2. Open the same opportunity's contact panel entry.
3. **Expect**: the panel reflects the board's changes (shared Vuex `byId` cache), and vice versa after an edit made from the panel.

## Out of scope (do not test as regressions)

- No new "create opportunity" entry point from the contact panel (FR-016).
- No permission/assignee-rule changes (FR-017).
- No pagination/infinite scroll on the panel's opportunity list, however many opportunities the contact has (FR-018).
- The "previous conversations" section's own behavior must be unchanged (FR-019).
