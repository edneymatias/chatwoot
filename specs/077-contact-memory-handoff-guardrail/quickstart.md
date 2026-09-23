# Quickstart / Validation Guide: Contact Memory Handoff Pretext Guardrail

Validates the feature end-to-end against its acceptance criteria. Details of the behavioral
contracts are in [`contracts/`](./contracts/); the data shape is in [`data-model.md`](./data-model.md).

## Prerequisites

- Stack up: `docker compose up -d`.
- Run all Ruby commands inside the `rails` container with the test env prefix (per `AGENTS.md`):
  `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec <cmd>`.

## 1. Unit: memory-interpretation warning (User Stories 1 & 3)

Target spec: `custom/spec/services/custom/scout/system_prompts_service_spec.rb`.

Run:

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test \
  bundle exec rspec custom/spec/services/custom/scout/system_prompts_service_spec.rb
```

Expected:
- When the contact has ≥1 note, the built prompt contains the memory-interpretation `AVISO:`
  paragraph asserting all three points in [`contracts/memory-warning-prompt.md`](./contracts/memory-warning-prompt.md)
  (past-summary, personalization-allowed, never-standalone-handoff, naming `handover_to_human`).
- When the contact has no notes, the prompt does NOT contain that paragraph.
- Existing identity/phone warning examples still pass unchanged.

## 2. Unit: dated note content (User Story 4)

Target spec: `custom/spec/services/custom/scout/contact_notes_service_spec.rb`.

Run:

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test \
  bundle exec rspec custom/spec/services/custom/scout/contact_notes_service_spec.rb
```

Expected:
- Each persisted `Note#content` starts with `[DD/MM/YYYY] ` (see
  [`contracts/memory-note-format.md`](./contracts/memory-note-format.md)); the returned array matches
  the persisted (dated) content.
- The error-path example (LLM raises) still persists nothing and returns `[]`.

## 3. Behavioral replay (Acceptance Scenarios, real entry point)

Use `Custom::Scout::PlaygroundRunner` (the convention from guardrail phases 23 and 29).

- **US1 — stale note does not trigger handoff**: contact carries a note describing a past, resolved
  "I want a human" request; replay a new conversation where the contact engages normally and answers
  a follow-up vaguely. Expect Scout to continue the qualification flow (or ask a clarifying question)
  and NOT call `handover_to_human`. (SC-001, SC-005)
- **US2 — genuine present-turn request still hands off**: replay a conversation where the contact
  explicitly asks for a human now — once with no notes on file, once with an unrelated/contradictory
  note. Expect an immediate `handover_to_human` in both. (SC-002)
- **US3 — personalization preserved**: contact with a note about a past interest starts a new
  conversation; Scout's greeting may reference that history to anticipate the likely current
  interest, without that reference causing or requiring a handoff. (SC-003)

## 4. Dashboard visibility spot-check (User Story 4, scenario 3)

In the dashboard contact Notes view, a note generated after this change shows its embedded
`[DD/MM/YYYY]` date inside the note text, alongside the view's own separate "written X ago"
timestamp — the overlap is expected (accepted per Clarifications).

## Pass criteria

- Steps 1–2 green.
- Step 3 replays match the expected handoff / no-handoff / personalization outcomes above.
- No edits to any upstream/shared file (esp. `app/services/llm_formatter/contact_llm_formatter.rb`);
  no new tool/model/schema/migration (FR-008).
