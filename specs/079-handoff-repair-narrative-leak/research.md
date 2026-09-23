# Phase 0 Research: Response Auditor Repair Loop Narrative Leak

No `NEEDS CLARIFICATION` markers remain in `spec.md` (confirmed by
`checklists/requirements.md`, all items checked). This document records the
technical decisions the plan is built on, each already resolved by the spec's
Assumptions section and the source diagnostic
(`docs/kanban/ciclo 10/scout/35-response-auditor-repair-loop-narrative-leak/spec-preview.md`).

## Decision 1: Where to skip the claim-consistency check

**Decision**: In `Custom::Scout::ResponseAuditor#audit`, skip both
`check_claim_consistency` and `perform_repair_and_reverify` for the entire
turn when `@handoff_already_flagged` is `true` — mirroring the existing early
return already used in `evaluate_action` (`response_auditor.rb:59`,
`return nil if @handoff_already_flagged`) that skips the action classifier for
the same condition.

**Rationale**: `@handoff_already_flagged` is set once per turn by the caller
(`AgentRunner#process_audited_reply`, `agent_runner.rb:86,90`) from
`tool.present?` — a tool (`handover_to_human`) has already run and
deterministically decided the turn ends in handoff before `audit` is ever
called. `evaluate_action` already treats this as "nothing left to decide" for
the *action* classifier; `check_claim_consistency` currently does not receive
the same treatment, which is the entire defect (spec User Story 1, FR-001/
FR-002). Reusing the exact same guard variable and the same file's established
pattern (per Constitution Principle II, smallest change; Principle III,
established conventions) needs no new state and no new per-request parameter.

**Alternatives considered** (recorded in spec Assumptions, rejected):
- *Keep the check running but block only the repair model call*, falling back
  to the fixed generic message (`I18n.t('conversations.scout.handoff')`) on an
  inconsistent verdict. Rejected: strictly more code (still calls
  `ClaimConsistencyService`, still needs the block-repair branch), throws away
  a coherent, correct model-authored message in favor of a generic fallback
  for no benefit — the tool's `SUCCESS` result is already proof the claimed
  action happened, so there is nothing left to verify. The source diagnostic
  itself recommends against this option as more complex and inconsistent with
  the file's existing pattern.

## Decision 2: Exact skip boundary inside `audit`

**Decision**: The skip is expressed as a guard at the top of `audit` (after
the existing `evaluate_action` call chain returns nil because it's flagged),
not by threading a new parameter through `check_claim_consistency` or
`perform_repair_and_reverify`. Concretely: add a single early-return line
before the `consistency_result = check_claim_consistency(...)` call, gated on
`@handoff_already_flagged`.

**Rationale**: `audit`'s existing control flow already has the exact shape
needed:
```ruby
action_outcome = evaluate_action(message_history)   # returns nil, flagged already
return action_outcome if action_outcome
return { action: :proceed, reply: response_text } unless conversation_pending?

consistency_result = check_claim_consistency(...)   # must not run when flagged
```
Adding `return { action: :proceed, reply: response_text } if @handoff_already_flagged`
directly after the `conversation_pending?` guard and before
`check_claim_consistency` satisfies FR-001/FR-002/FR-003 in one line, touches
no other method, and changes nothing about `evaluate_action`,
`perform_repair_and_reverify`, or `reverify_consistency` — so FR-004 (no
change to the check-and-repair path when not flagged) and FR-005 (repair
discovering a new, previously-unflagged handoff mid-repair is untouched, since
that path is only reachable once `check_claim_consistency` already ran and
returned inconsistent) hold by construction, not by extra conditionals.

**Alternatives considered**:
- Guard inside `check_claim_consistency` itself (return a synthetic "safe"
  result when flagged). Rejected: `check_claim_consistency` is a thin,
  single-purpose wrapper around `ClaimConsistencyService#check`
  (`response_auditor.rb:138-145`); teaching it to fabricate a result for an
  unrelated concern (handoff-already-decided) breaks its single
  responsibility and would silently affect any other future caller of that
  private method.
- Guard inside `perform_repair_and_reverify` only. Rejected: does not satisfy
  FR-001 (the consistency check itself must not run) — it would still make
  the wasted `ClaimConsistencyService` LLM call and only skip acting on its
  verdict.

## Decision 3: Repair outcome logging (User Story 2)

**Decision**: Extend `execute_repair` to log the repaired call's full parsed
content (reasoning + response) via `Rails.logger.info`, using the same
message-prefix convention as the existing main-turn reasoning log line
(`agent_runner.rb:133`, `"[Scout AgentRunner] reasoning: #{...}"`) — here
`"[Scout][ResponseAuditor] repair reasoning: #{reasoning}"` immediately after
parsing, followed by the existing repaired response continuing through
`parse_repaired_content` unchanged. `parse_repaired_content` currently
extracts only `response` and discards `reasoning`
(`response_auditor.rb:157-166`); the reasoning must be read before that
discard.

**Rationale**: FR-006/SC-004 require the repair loop's full outcome
(reasoning + response), not just a "repair ran" boolean, to be diagnosable
from logs alone — matching the log detail already given to the main turn.
`Rails.logger.info` (not `.warn`, which is reserved for
`handle_audit_error`'s failure path, `response_auditor.rb:115-121`) is the
correct level: this is normal-path observability, not an error condition.

**Alternatives considered**:
- A new persisted log/audit DB table. Rejected: spec's Key Entities describes
  "Repair Outcome Log Entry" as an application log record, not a new
  persisted model; no requirement calls for querying repair history outside
  logs, and adding a table for this is speculative scope beyond FR-006
  (Constitution Principle II).

## Summary

Both decisions localize entirely inside
`custom/app/services/custom/scout/response_auditor.rb` (fork-owned file,
already the sole owner of this behavior — no upstream/enterprise
counterpart exists per the earlier `custom/` grep). No new extension point,
no new database table, no new configuration is needed; Constitution Principle
I (upstream compatibility) is satisfied trivially since this file has no
upstream equivalent to diverge from.
