# Quickstart: Validating Scout Observability & Handoff Notice

Validates the two user stories in `spec.md` end-to-end. Run the automated specs first (fast,
deterministic); the manual walkthroughs below confirm the customer-visible and Langfuse-visible
behavior the specs assert against.

## Prerequisites

- Stack running: `docker compose up -d` (see `CLAUDE.md` for the full command set).
- A Scout-enabled inbox with an active `ScoutAccountConfig` (valid `api_key`) and at least one
  `Custom::Scout::Tools::CallCustomApi`-backed tool configured against an endpoint you can make
  fail on demand (e.g. point it at an unreachable host to force a network error).
- For the observability half only: `OTEL_PROVIDER`/`LANGFUSE_*` set in `InstallationConfig` and a
  reachable Langfuse project to view traces in. Skip this for the "integration not configured"
  check below.

## Automated checks

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout/agent_runner_spec.rb \
  custom/spec/services/custom/scout/handoff_service_spec.rb \
  custom/spec/services/custom/scout/tools/base_tool_spec.rb
```

Expected: all examples green, including the new ones asserting (a) a public outgoing message is
created before `bot_handoff!` in both paths, (b) the pre-existing private note is still created
unchanged, and (c) `instrument_tool_call`/`instrument_agent_session` are invoked (or safely skipped
when `ChatwootApp.otel_enabled?` is false).

## Manual walkthrough — User Story 1 (customer sees a transfer message)

1. **Fail-safe path**: Start a conversation in the Scout inbox, then force the fail-safe branch —
   easiest is temporarily exhausting the Scout's quota (`scout.quota_available?` returns false) or
   sending a message while the configured LLM key is invalid.
   - Expected: the conversation thread shows a public message ("Transferring to another agent for
     further assistance." / pt-BR equivalent) before the conversation reopens for the human queue.
   - Expected: the internal private note with the failure reason is still present, unchanged.
2. **Explicit handoff path**: Send a message that should trigger Scout's `handover_to_human` tool
   (per the account's system prompt / qualification rules).
   - Expected: same public transfer message appears, before the conversation reopens.
   - Expected: the existing private transfer note (with `reason`, if the model supplied one) is
     still present, unchanged.
3. Confirm the two messages use identical wording (per the spec Clarification: one fixed message,
   no variant per path/reason).

## Manual walkthrough — User Story 2 (trace visibility)

With `OTEL_PROVIDER`/`LANGFUSE_*` configured:

1. Send a message that causes Scout to call at least one tool successfully (e.g. `update_contact`).
   - In Langfuse, open the resulting trace: confirm it shows the main LLM prompt/response and a
     nested span for the tool call with its name, arguments, and result.
2. Send a message that causes Scout to call the misconfigured `CallCustomApi` tool (network
   failure).
   - Confirm the trace's tool-call span records the failure (error detail visible), without you
     needing to reproduce the conversation to know what went wrong.
3. Repeat step 1 with `OTEL_PROVIDER`/`LANGFUSE_*` unset (or `ChatwootApp.otel_enabled?` stubbed
   false in a console).
   - Confirm the conversation behaves identically to current production behavior — same response,
     same latency, no errors — and nothing appears in Langfuse (as expected, since it's a no-op
     when disabled).

## Cross-check against the spec

- SC-001: repeat the fail-safe and explicit-handoff walkthroughs a few times — every run must show
  the transfer message before the human queue pickup, no exceptions.
- SC-003: every tool call in a multi-tool conversation turn appears as its own span, not merged.
- SC-004: compare response timing for the same scripted conversation with the integration on vs.
  off — no observable difference.
