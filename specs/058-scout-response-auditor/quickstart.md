# Quickstart: Validating Scout Response Auditor

Validates all three user stories in `spec.md` end-to-end. Run the automated specs first; the
manual walkthrough reproduces the two real failure patterns that motivated this feature (a false
"already done" claim, and an unfulfilled handoff/other promise) and confirms both are now caught.

## Prerequisites

- Stack running: `docker compose up -d`.
- Run the new migration: `docker compose exec rails bundle exec rails db:migrate`.
- A Scout-enabled inbox with a working `ScoutAccountConfig` (either supported provider — `gemini`
  or `openai`). Run at least one full walkthrough (below) against a **Gemini**-configured account
  specifically: research.md §4 flags an unresolved, pre-existing question (inherited from Phase
  057, not introduced here) about whether Gemini's API tolerates `with_schema` + `with_tool`
  together on every turn — the repair step in User Story 1/2 reuses that same combination, so a
  clean run here is also evidence the underlying combination still works.
- Enable the flag on the Scout under test (no settings-UI toggle exists yet — same as
  `feature_memory` today):
  ```
  docker compose exec rails bundle exec rails runner \
    "Scout.find(<id>).update!(feature_response_auditor: true)"
  ```
- Recommended: the Langfuse/OTel integration from feature 056 configured — makes it easy to inspect
  the extra classifier/consistency-check LLM spans for any turn under test.

## Automated checks

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/tools/call_recorder_spec.rb \
  custom/spec/services/custom/scout/action_classifier_service_spec.rb \
  custom/spec/services/custom/scout/claim_consistency_service_spec.rb \
  custom/spec/services/custom/scout/response_auditor_spec.rb \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/services/custom/scout/playground_runner_spec.rb
```

Expected: all examples green, including new ones asserting (a) `CallRecorder` produces the same
recorded-call shape `PlaygroundRunner` already relied on, now with an `error` key on a failed call;
(b) both classifiers return a normalized decision via `with_schema` and degrade to a "no decision"
outcome on any internal failure without raising; (c) `ResponseAuditor` runs the classifiers in the
documented order, repairs at most once via the same live `chat` object, and escalates to the
existing fail-safe handoff if still inconsistent after reverification; (d) with the flag off,
`AgentRunner` never instantiates `ResponseAuditor` and no new LLM calls happen; (e)
`responses_consumed` increments exactly once per turn regardless of how many auditor calls ran;
(f) `PlaygroundRunner`'s existing behavior/spec is unchanged after the `CallRecorder` extraction.

## Manual walkthrough — User Story 1 (no false "already done" claims reach the customer)

1. With the flag enabled, start a conversation and ask Scout to do something that would normally
   call `manage_opportunity`/`move_opportunity_stage`, but engineer a turn where the tool call
   doesn't happen (e.g. ask about an update in a way that doesn't clearly trigger the tool, similar
   to the original production bug).
2. Confirm the customer never receives a reply claiming the update already happened — either a
   corrected reply arrives (Scout honestly states it hasn't done it, or actually calls the tool
   this time), or the conversation is handed off to a human with an internal transfer note.
3. Repeat with a variant where the tool *is* called but forced to fail (e.g. temporarily point the
   opportunity ID at one that doesn't exist) — confirm the same protection applies (a failed tool
   call must not let a "completed" claim through unchecked, per the clarified spec decision).
4. Disable the flag and repeat step 1 — confirm the false claim is delivered exactly as it was
   before this feature (baseline regression check for FR-008).

## Manual walkthrough — User Story 2 (promised actions always actually happen)

1. With the flag enabled, get Scout into a state where its drafted reply is likely to promise a
   human handoff (e.g. a request Scout can't fully resolve) but avoid triggering the
   `handover_to_human` tool — confirm the conversation ends up genuinely handed off to a human
   (visible transfer note + status change), not left `pending` indefinitely.
2. Separately, try to get Scout to promise some *other* future action (e.g. "I'll check that and
   get back to you") without a matching tool call — confirm this is also corrected or escalated,
   not just the handoff-specific case.
3. Separately, send an explicit request for a human ("I want to talk to a person") and confirm a
   real handoff happens even if Scout's own drafted reply doesn't mention handing off.
4. Disable the flag and repeat step 1 — confirm behavior matches today (no proactive handoff beyond
   what Scout's own reply/tool use already triggers).

## Manual walkthrough — User Story 3 (safe to enable per account)

1. With the flag off (default) on a second Scout, run several ordinary conversations and confirm no
   behavior, latency, or `responses_consumed` difference from before this feature existed.
2. With the flag on, run an ordinary conversation with no false claims/missed handoffs and confirm
   the customer experience is unaffected (no visible sign the extra checking ran).

## Cross-check against the spec

- SC-001/SC-002: across the manual walkthrough conversations, 100% of the engineered false-claim
  and broken-promise turns should end up corrected or escalated — none should reach the customer
  unmodified.
- SC-003: the explicit-human-request walkthrough step results in a real handoff in the same turn.
- SC-004: the flag-off walkthrough step shows no measurable difference from pre-feature behavior.
- SC-005: no walkthrough step should ever fail to deliver *a* reply to the customer — if an auditor
  call is deliberately broken (e.g. temporarily misconfigure the account's model mid-turn), the
  original reply must still be delivered, logged as an auditor failure rather than blocking
  delivery.
- SC-006: check `responses_consumed` after each walkthrough turn — it must increase by exactly 1,
  regardless of how many classifier/repair calls happened in that turn.
