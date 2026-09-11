# Quickstart: Validating Scout Structured Response Reliability

Validates both user stories in `spec.md` end-to-end. Run the automated specs first; the manual
walkthrough confirms the real-world failure rate that motivated this feature is actually fixed —
the exact thing 3/3 real conversations failed at before this change.

## Prerequisites

- Stack running: `docker compose up -d`.
- A Scout-enabled inbox with a working `ScoutAccountConfig` (either supported provider — `gemini`
  or `openai`).
- Recommended: the Langfuse/OTel integration from feature 056 configured (`OTEL_PROVIDER=langfuse`
  etc. in `InstallationConfig`) — makes it trivial to inspect the raw model output for any turn
  that still fails, the same way the original bug was diagnosed.

## Automated checks

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/response_schema_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb
```

Expected: all examples green, including new ones asserting (a) the chat is configured with
`Custom::Scout::ResponseSchema` via `with_schema`, (b) `parse_structured_response` correctly
extracts `response` when `content` arrives as an already-parsed `Hash`, (c) it still falls back
correctly when `content` arrives as a `String` (fenced JSON or plain text), (d) tool-calling still
works with the schema active, and (e) the existing fail-closed behavior (FR-003) is unchanged when
a usable response still can't be obtained.

## Manual walkthrough — User Story 1 (conversations complete instead of failing over)

1. Start several real qualification conversations with Scout (ideally reproducing the exact shape
   that failed before: at least one turn where the model also calls a tool, e.g.
   `manage_opportunity`, in the same turn as its final reply).
2. For each conversation, confirm the customer receives the model's actual reply and the
   conversation does **not** get the "Falha ao interpretar resposta estruturada do modelo." private
   note / fail-safe handoff.
3. Repeat across enough conversations to sanity-check the <5% failure-rate target from SC-001 (a
   handful of clean runs is enough to see the fix is working; this is not meant to be a large-scale
   statistical test).
4. If the account's Langfuse integration (feature 056) is configured, spot-check a trace for one of
   these conversations: the LLM generation span's output should show a proper JSON object (or the
   provider's schema-conformant shape), not the "reasoning: ...\n\nresponse: ..." plain-text shape
   from the original bug report.

## Manual walkthrough — User Story 2 (fail-closed still holds)

1. Temporarily misconfigure the account's model (e.g. point `ScoutAccountConfig#model_name` at a
   nonexistent model, or otherwise force a failure) so the provider cannot produce any usable
   response.
2. Confirm the customer still never sees raw/malformed text — the existing fail-safe handoff
   (public transfer message from feature 056 + private alert note) still fires exactly as before.
3. Restore the valid configuration afterward.

## Cross-check against the spec

- SC-001: across the conversations run in the manual walkthrough, count how many hit the
  parse-failure fail-safe path vs. how many completed normally — should be well under 5%, a sharp
  drop from the ~100% observed before this feature.
- SC-002: at least one multi-turn conversation involving a tool call completes with the customer
  receiving the model's real reply.
- SC-003: the forced-failure walkthrough (User Story 2) shows zero raw/malformed content reaching
  the customer.
