# Contract: Handoff Reason → {Note, Message} Mapping

This feature has no new HTTP endpoint, job queue message, or public Ruby API. The closest thing to an
external interface is the data contract between:

1. `Custom::Scout::ActionClassifierSchema::REASONS` (the fixed producer of `action_reason` values), and
2. `config/locales/en.yml` / `config/locales/pt_BR.yml` (the consumer-facing i18n key sets translators
   and future reason additions must keep in sync).

## i18n key contract

For every value `r` in `Custom::Scout::ActionClassifierSchema::REASONS`, both locale files MUST define:

```yaml
en:
  conversations:
    scout:
      handoff_reasons:
        <r>:
          note: "<short, human-readable internal-note label, English>"
          message: "<warm, reason-specific customer-facing closing message, English>"

pt_BR:
  conversations:
    scout:
      handoff_reasons:
        <r>:
          note: "<short, human-readable internal-note label, Portuguese>"
          message: "<warm, reason-specific customer-facing closing message, Portuguese>"
```

**Invariants**:
- Key set under `conversations.scout.handoff_reasons` is identical between `en.yml` and `pt_BR.yml`
  (FR-010). A key present in one file and missing in the other is a contract violation, verified by a
  spec that diffs both files' key sets for this namespace (mirrors existing project convention for
  other synced namespaces).
- Every `<r>.note` and `<r>.message` value is non-blank real content — no placeholder/TODO strings
  (FR-010, "with real content").
- Adding, removing, or renaming a value in `ActionClassifierSchema::REASONS` is out of scope for this
  feature (spec Assumptions); this contract governs only the four reasons that exist today. A future
  reason addition must extend both locale files under this same namespace to remain consistent with
  this contract, but implementing that extension is not part of this feature.

## Call contract: `Custom::Scout::HandoffService#perform`

**Unchanged public signature**: `perform(assignee_id: nil, team_id: nil, reason: nil, message: nil)`.
No caller (`ResponseAuditor#execute_handoff`, the `handover_to_human` tool path, or the qualified-stage
handoff path) changes its call site for this feature — the reason-mapping lookup is entirely internal
to `HandoffService`, keyed off the same `reason` string already passed in today.

**Behavioral contract** (new, internal):

| Input | `note_label` resolved? | `customer_message` resolved? | Resulting internal note | Resulting public message |
|---|---|---|---|---|
| `reason` is one of the 4 known codes | Yes (`account.locale`) | Yes (`conversation_locale`) | Localized prefix + reason-specific `note` label | Reason-specific `message` (used when `message:` not explicitly passed — see row 4) |
| `reason` is `nil` or blank (`""`) | No | No | Existing generic fallback text (`'motivo não informado pelo modelo'`-equivalent), unchanged | Existing generic `conversations.scout.handoff`, unchanged |
| `reason` is a non-blank string that does **not** match any of the 4 known codes (e.g. the qualified-stage path's default string, or the tool path's model-authored free text) | No | No | Existing behavior unchanged: **raw `reason` text interpolated as-is** (`reason.presence`) — NOT the generic fallback text; this is the pre-existing, still-correct behavior for human-authored reasons | Existing generic `conversations.scout.handoff` **only if reached** — see row 4, `message:` is always explicitly passed by both callers that produce this kind of reason today, so this branch is never actually exercised for the customer-facing side in practice |
| `message:` explicitly passed (both non-classifier callers, `agent_runner.rb`'s `trigger_handoff` and `follow_up_job.rb`, always pass one today) | N/A — note logic (row 1–3) is independent of `message:` | N/A — unaffected by this feature | Depends on `reason` per rows 1–3 | Explicit `message:` always wins (existing `content = message.presence \|\| ...` precedence, unchanged) |

**Precision on FR-009's "fall back to today's existing generic text"**: this requirement is scoped by
FR-012 to the classifier-driven path only. Within that path, `action_reason` is either `nil` (row 2,
the API/schema layer failed to produce a value) or one of the 4 schema-enforced codes (row 1) — the
"non-blank but unmatched" case (row 3) is a defensive branch that in practice is only ever reached by
the two *non-classifier* callers, whose reason strings are never nil and never coincide with one of the
4 codes. Implementing the label lookup as `label_for(reason) || reason.presence ||
I18n.t(<blank-fallback-key>)` (label wins, then the pre-existing raw-text branch, then the pre-existing
blank-fallback branch) satisfies FR-009 for the classifier path while leaving the tool/qualified-stage
paths' existing raw-text note behavior byte-for-byte unchanged, per FR-012 — no caller-identity check
is needed to keep the two behaviors apart, because the fallback chain's existing precedence already
separates them by whether `reason` matches a known code.

This preserves FR-012: the two non-classifier handoff paths keep passing their own `message:`
(already-authored text) and are unaffected by the new reason-specific customer message logic, which
only ever applies when no explicit `message:` is given — the same precedence rule that already exists
today (`message.presence || I18n.t('conversations.scout.handoff', ...)`), now with a reason-specific
value substituted as the non-explicit branch's default.
