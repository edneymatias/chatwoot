# Phase 1 Data Model: Scout Response Auditor

One new persisted field (a boolean flag on the existing `Scout` model); everything else this
feature introduces is either a plain in-memory Ruby value (recorded tool calls) or a plain
`RubyLLM::Schema` subclass (not a Chatwoot-persisted record) — matching Constitution Principle IV
(migrations must be additive and must not alter existing core tables).

## `Scout#feature_response_auditor` (persisted)

| Field | Type | Null | Default | Meaning |
|---|---|---|---|---|
| `feature_response_auditor` | boolean | `false` | `false` | Per-account opt-in gate (spec FR-007/FR-008). When `false` (default), `AgentRunner` never calls `ResponseAuditor` — behavior is byte-for-byte identical to today. |

Added via one additive migration on `ichatr_scouts`, mirroring the existing `feature_memory`
column exactly (`db/migrate/21260819000005_add_pipeline_fields_to_ichatr_scouts.rb:7`):
`t.boolean :feature_response_auditor, null: false, default: false`. No index needed (only ever
read by primary-key-scoped `Scout` instances already loaded in memory, never queried directly).
Reversible via a `down` that removes the column, same shape as the existing migration's `down`.

No frontend change: like `feature_memory`, this column has no dedicated settings-UI toggle in
`ScoutSettings.vue` — it's operated the same way `feature_memory` already is (API/console/seed),
per research.md §5.

## Turn's tool activity — `recorded_tool_calls` (in-memory only)

Not a database table. A plain `Array` of `Hash`, scoped to one turn (`@recorded_tool_calls`, reset
per `AgentRunner#perform` / `PlaygroundRunner#perform` call), produced by
`Custom::Scout::Tools::CallRecorder` wrapping each tool's `#execute`:

| Field | Type | Present when | Meaning |
|---|---|---|---|
| `tool_name` | string | always | The tool's `#name` (e.g. `manage_opportunity`, `handover_to_human`) — matches the identifier the model used to invoke it. |
| `arguments` | hash | always | The normalized keyword arguments the tool was called with. |
| `simulated` | boolean | always | Whether the call's effects were simulated rather than real. `CallRecorder` takes this as an explicit parameter from the includer — `PlaygroundRunner` passes `tool_name != 'call_custom_api'` (its existing rule, unchanged), `AgentRunner` always passes `false` (every call it wraps is a real production execution). |
| `result` | any | tool call succeeded | The tool's return value. |
| `error` | string | tool call raised | `exception.message`. Presence of this key (regardless of `result`) means the action did **not** actually complete — this is the ground truth `ClaimConsistencyService` uses to treat a "completed action" claim as false even when a matching tool call exists but failed (clarified spec decision). |

This is the same shape `PlaygroundRunner#execute_and_record` already produces today
(`custom/app/services/custom/scout/playground_runner.rb:81-93`, including its always-present
`simulated` key — confirmed by cross-validation against the actual source, corrected from an
earlier draft of this document that omitted it) — `CallRecorder` extracts it unchanged so
`PlaygroundRunner`'s existing consumers see no difference, while `AgentRunner` gains it for the
first time (previously it had no visibility into which tools actually ran in a turn).

## `Custom::Scout::ActionClassifierSchema` (LLM output contract, not persisted)

| Field | Type | Required | Meaning |
|---|---|---|---|
| `action` | string, enum | yes | `continue` \| `handoff` |
| `action_reason` | string, enum | yes | One of a Scout-owned, commercial-domain reason set (see below) — not Captain's 12 support-domain reasons. |

Initial reason set (proposed at plan time; may be refined during implementation without spec/plan
impact, per the spec's Assumptions on reason-list scope):

- `explicit_human_request` — customer unambiguously asks for a person.
- `human_offer_accepted` — customer accepts a previously offered human handoff.
- `repeated_frustration_or_loop` — conversation is stuck/looping without progress.
- `out_of_scope_commercial_request` — request falls outside the commercial scope already locked by
  the Phase 08 guardrail, but the guardrail's prompt-only instruction didn't stop the model from
  continuing to engage with it.

## `Custom::Scout::ClaimConsistencySchema` (LLM output contract, not persisted)

| Field | Type | Required | Meaning |
|---|---|---|---|
| `decision` | string, enum | yes | `safe` \| `false_promise` \| `false_completed_action` |
| `reason` | string | yes | Short free-text justification, logged for operator troubleshooting (spec Assumptions: logs only, no dedicated reporting UI in this feature). |

`decision` values, grounded against `recorded_tool_calls` (§ above) plus conversation history and
the drafted reply text:

- `safe` — reply is consistent with what actually happened this turn (including replies that make
  no completion/future-work claim at all).
- `false_promise` — reply promises **any** future action (handoff or otherwise) with no matching
  tool call recorded this turn (clarified spec scope — broad, not handoff-only).
- `false_completed_action` — reply claims an action (opportunity/stage/data update, handoff, etc.)
  already happened, but no matching tool call exists in `recorded_tool_calls`, or one exists but
  carries an `error` key (clarified spec decision — a failed call does not count as completed).

## Validation rules

- Both schemas are `strict` (matching `Custom::Scout::ResponseSchema`'s existing default,
  established in Phase 057) — a classifier response missing a required field fails schema
  validation on providers that enforce it; `ActionClassifierService`/`ClaimConsistencyService`
  treat this identically to any other unparseable/errored LLM call (research.md §6): logged,
  treated as "no decision," original reply proceeds to dispatch unmodified.
- `feature_response_auditor` has no application-level validation beyond the DB-level `null: false`
  — a plain boolean, same as `feature_memory`.

## State transitions

No new conversation/message state machine. `ResponseAuditor` only ever drives the conversation
through transitions that already exist:

- `pending` → (via `HandoffService#perform` or `AgentRunner#perform_fail_safe_handoff`) →
  `bot_handoff!` — both already-existing call sites, reused unchanged (spec FR-004/FR-006/FR-010).
- `pending` → (reply dispatched via `dispatch_outgoing_reply`, unchanged) — no new transition.

`ResponseAuditor` itself is stateless across turns — each turn's audit (classify → maybe
consistency-check → maybe one repair-and-reverify) starts and ends within a single
`AgentRunner#process_response` call, per spec FR-013 (auditing only ever runs against a
conversation still awaiting a Scout reply, never against one a human has already taken over).
