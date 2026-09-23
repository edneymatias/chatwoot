# Contract: `Custom::Scout::ResponseAuditor#audit`

This is an internal Ruby service-object contract (no HTTP/external API is
exposed by this feature) between `Custom::Scout::AgentRunner` (the sole
caller, `agent_runner.rb:88-98`) and `Custom::Scout::ResponseAuditor`. It
documents the observable input/output contract after this feature, calling
out exactly what changes and what is guaranteed unchanged.

## Method signature (unchanged)

```ruby
ResponseAuditor.new(scout:, conversation:, handoff_already_flagged: false)
  .audit(chat:, response_text:, message_history:, recorded_tool_calls:, available_tool_names: [])
```

No parameter is added, removed, or renamed. `handoff_already_flagged:`
already exists and is already threaded through by the caller
(`agent_runner.rb:90`); this feature changes only what `audit` does with it.

## Return contract

`audit` returns one of three shapes (unchanged set — no new action type is
introduced):

| `action`   | Other keys      | Meaning |
|------------|------------------|---------|
| `:proceed` | `reply: String`  | Deliver `reply` as-is; caller may still trigger handoff using `reply` as the message if a tool flagged one (`agent_runner.rb:102`). |
| `:handoff` | —                | A handoff already fully happened inside `audit` (classifier-confirmed handoff, or a handoff newly decided mid-repair); caller sends nothing further (`agent_runner.rb:107-108`). |
| `:escalate`| `reason: String` | Reply was inconsistent and repair could not fix it; caller performs a fail-safe handoff with `reason` (`agent_runner.rb:109-111`). |

## New guarantee (FR-001, FR-002, FR-003)

**When `handoff_already_flagged: true`** (a tool already deterministically
decided handoff this turn):

- `audit` MUST return `{ action: :proceed, reply: response_text }` where
  `response_text` is *exactly* the input `response_text` — byte-for-byte,
  never rewritten.
- `audit` MUST NOT call `Custom::Scout::ClaimConsistencyService#check`.
- `audit` MUST NOT call `chat.ask` (the repair call).
- This guarantee holds regardless of what `response_text` says — even a
  reply containing an unrelated false claim is not verified in this state
  (accepted trade-off, spec Edge Cases).
- This guarantee is conditioned on `conversation_pending?` exactly as every
  other early return in `audit` already is — a conversation that stopped
  being pending before `audit` runs still short-circuits via the existing
  first guard (`response_auditor.rb:23`), unaffected by this feature.

## Unchanged guarantee (FR-004, FR-005)

**When `handoff_already_flagged: false`** (the default, and the case for
every turn where no handoff tool ran): `audit`'s behavior — the full
`evaluate_action` → `check_claim_consistency` →
`perform_repair_and_reverify` → `reverify_consistency` chain, including the
case where `reverify_consistency` returns `{ action: :handoff }` because the
repair call itself triggered a new handoff — is byte-for-byte identical to
today. This is covered by the full existing `response_auditor_spec.rb`
suite continuing to pass unmodified.

## New side effect (FR-006) — logging only, not part of the return value

Whenever `perform_repair_and_reverify` actually executes a repair call (i.e.
only reachable when `handoff_already_flagged: false` and
`check_claim_consistency` judged the original reply inconsistent), the
repair call's parsed `reasoning` and `response` are written to
`Rails.logger.info` before `audit` returns. This is a log-sink side effect
only — it is not observable via `audit`'s return value and does not change
any return shape above.
