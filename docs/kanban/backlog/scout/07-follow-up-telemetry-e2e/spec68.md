# Phase 07 — Follow-up, Telemetry & E2E

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §5, §6
**Depends on**: Phase 02 (Opportunity/tool pipeline), Phase 05 (UI to surface telemetry, if
surfaced there).

## Goal

Close the loop on stalled leads and give operators visibility into usage, plus end-to-end test
coverage for the full Scout flow.

## Scope

- `Scout::FollowUpJob` — new job built from scratch (no pre-existing `FollowUpSchedulerJob` in this
  codebase, contrary to the original spec60.md draft). Runs on a schedule, finds opportunities
  stuck in the triage stage past `follow_up_delay_hours`, and re-engages via the Scout.
- Token/response telemetry: `tokens_consumed`, `messages_processed` counters for the Managed/System
  key mode (spec60.md §6) — persisted per account/Scout in Postgres.
- End-to-end test suite covering: referral-carrying inbound message → Opportunity creation with
  attribution → qualification turns → stage move → handoff, and the Fail-Safe path.

## Out of scope

- No billing/invoicing built on top of the telemetry counters — groundwork only, per spec60.md
  §4.3.

## Acceptance criteria

- A stalled triage-stage opportunity past `follow_up_delay_hours` receives a re-engagement message
  from the Scout, exactly once per stall period (no duplicate follow-ups).
- Telemetry counters accurately reflect tokens/messages for at least one full conversation in
  Managed key mode.
- E2E suite passes covering the golden path (CTWA lead → qualified → handoff) and the Fail-Safe
  path (quota exhausted mid-conversation).
