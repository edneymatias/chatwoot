# Phase 1 Data Model: Response Auditor Handoff Message Quality

No database schema changes. This feature introduces one conceptual, in-memory/static entity backed
entirely by existing i18n infrastructure — no migration, no new AR model, no new table.

## Entity: Handoff Reason

A fixed classification the response auditor's `Custom::Scout::ActionClassifierService` assigns when
it decides `action == 'handoff'`. Already exists today as
`Custom::Scout::ActionClassifierSchema::REASONS`; this feature does not add, remove, or rename values
(see spec Assumptions).

| Field | Type | Source of truth | Notes |
|---|---|---|---|
| `code` | `String` enum | `Custom::Scout::ActionClassifierSchema::REASONS` | One of `explicit_human_request`, `human_offer_accepted`, `repeated_frustration_or_loop`, `out_of_scope_commercial_request`. Unchanged by this feature. |
| `note_label` | `String`, localized | `I18n.t("conversations.scout.handoff_reasons.#{code}.note", locale: account_locale)` | Resolved against the conversation's **account** locale (FR-005). `nil` when `code` is missing/unrecognized. |
| `customer_message` | `String`, localized | `I18n.t("conversations.scout.handoff_reasons.#{code}.message", locale: conversation_locale)` | Resolved against the **conversation's own** locale (FR-007). `nil` when `code` is missing/unrecognized. |

**Validation rules**:
- `code` is validated today at the schema layer (`ActionClassifierSchema`'s `enum:` constraint on the
  LLM structured-output call) — unchanged by this feature.
- `note_label`/`customer_message` have no independent validation; a `nil` result (missing key or
  unrecognized `code`) is not an error state — it is the documented fallback trigger (FR-009).
- Key-parity between `en.yml` and `pt_BR.yml` for the `handoff_reasons` namespace is a build-time/test-time
  invariant (FR-010), not a runtime validation — enforced by a spec asserting both YAML files expose
  the same key set under `conversations.scout.handoff_reasons`, mirroring the existing project-wide
  key-parity convention for other localized namespaces.

**State/relationships**: `Handoff Reason` has no persistence and no relationships to AR models. It is
a pure function of the classifier's already-returned `action_reason` string plus two locale strings
already resolvable from the `Conversation`/`Account` the handoff is running against
(`@conversation.language`, `@conversation.account.locale`) — both already read elsewhere in
`Custom::Scout::HandoffService`.

## Fallback entity: Generic Handoff Text / Raw Reason Text

Already exists (`conversations.scout.handoff` for the customer message; the inline literal
`'motivo não informado pelo modelo'` for a blank note reason) and is unchanged by this feature.
`Handoff Reason#note_label`/`#customer_message` resolve to `nil` whenever `reason` does not match one
of the four defined codes (missing key or unrecognized/blank string) — but `nil` does **not** always
mean "render the generic text" for the note side specifically:

- `customer_message` is `nil` → the public message always falls back to
  `conversations.scout.handoff` (true generic text), because that i18n call has no other fallback
  tier today.
- `note_label` is `nil` **and** `reason` is blank/`nil` → the note falls back to the existing generic
  literal (FR-009).
- `note_label` is `nil` **but** `reason` is a non-blank string that simply isn't one of the four codes
  (the only real-world case: the two non-classifier handoff paths' own reason strings, e.g.
  `agent_runner.rb`'s `'Oportunidade movida para o estágio qualificado'` default, or model-authored
  free text) → the note falls back to **today's existing raw-text behavior** (`reason.presence`),
  unchanged — not the generic literal. This is what keeps FR-012 satisfied without any caller-identity
  branching: the fallback chain's existing precedence (`note_label || reason.presence ||
  generic_literal`) already separates "known code" from "human-authored text" from "nothing given"
  using only the shape of `reason` itself.
