# Phase 1 Data Model: Response Auditor Repair Loop Narrative Leak

No new database tables, columns, or migrations. Both entities named in
`spec.md`'s Key Entities section are in-process/log constructs, not persisted
records.

## Tool-Decided Handoff Flag

- **Kind**: Existing per-request boolean, already present — this feature only
  widens its effect, it does not add a new field.
- **Representation**: `@handoff_already_flagged` instance variable on
  `Custom::Scout::ResponseAuditor`, set once in `#initialize` from the
  `handoff_already_flagged:` keyword argument
  (`response_auditor.rb:15-20`, default `false`).
- **Producer**: `Custom::Scout::AgentRunner#process_audited_reply`
  (`agent_runner.rb:86,89-90`), computed as `tool.present?` where `tool` is
  the `handover_to_human` tool instance if it ran and set `handoff_needed`
  this turn (`agent_runner.rb:115-117`).
- **Lifetime**: Scoped to a single `ResponseAuditor#audit` call (one model
  turn); never persisted, never read across turns or conversations.
- **Existing consumer**: `evaluate_action` (`response_auditor.rb:59`) —
  skips the action classifier when `true`.
- **New consumer (this feature)**: `audit` itself — skips
  `check_claim_consistency`/`perform_repair_and_reverify` when `true`,
  returning `{ action: :proceed, reply: response_text }` with the original,
  unmodified reply.
- **Validation rules**: None beyond existing — it is a plain boolean derived
  from tool-call success upstream of this class; `ResponseAuditor` does not
  re-derive or validate it.
- **State transitions**: None — set once at construction, immutable for the
  life of the `audit` call.

## Repair Outcome Log Entry

- **Kind**: A structured `Rails.logger.info` line, not a persisted model —
  matches the existing "Repair Outcome Log Entry" description in `spec.md`
  ("A new log record capturing what the repair loop's model call produced").
- **Producer**: `Custom::Scout::ResponseAuditor#execute_repair`
  (`response_auditor.rb:152-155`), emitted whenever the repair loop actually
  runs (i.e., whenever `perform_repair_and_reverify` is reached, which after
  this feature only happens for the non-flagged path per FR-004/FR-005).
- **Fields captured**:
  - `reasoning`: the repaired call's `reasoning` field, parsed from the same
    structured JSON payload `parse_repaired_content` already parses for
    `response` (`response_auditor.rb:157-166`). Absent/blank when the model
    did not include one (mirrors `agent_runner.rb:133`'s handling of a
    missing `hash['reasoning']`).
  - `response`: the repaired reply text — already computed by
    `parse_repaired_content`; the log entry reuses it rather than
    recomputing it.
- **Format convention**: `"[Scout][ResponseAuditor] repair reasoning: #{reasoning}"`
  at `Rails.logger.info`, matching the existing
  `"[Scout AgentRunner] reasoning: #{...}"` line's prefix-and-level
  convention (`agent_runner.rb:133`) and the `[Scout][ResponseAuditor]`
  prefix already used by this file's own warn-level error log
  (`response_auditor.rb:117-119`).
- **Relationship to existing error log**: Distinct from
  `handle_audit_error`'s `Rails.logger.warn` line — that logs
  *audit-pipeline failures* (exceptions); this logs a *successful* repair
  call's content, at `.info`, unconditionally whenever repair runs.
- **Lifetime**: Write-only, log-sink lifetime (whatever the deployment's log
  retention is); no application code reads it back.
