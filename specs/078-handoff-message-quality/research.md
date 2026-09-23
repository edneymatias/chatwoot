# Phase 0 Research: Response Auditor Handoff Message Quality

No unresolved `NEEDS CLARIFICATION` markers remain in the Technical Context — this is a small,
fully-scoped change to an already-isolated fork module with a prior investigation doc
(`docs/kanban/ciclo 10/scout/33-response-auditor-handoff-message-quality/spec-preview.md`) that
already identified root cause and draft content. The items below record the decisions actually
made, each with rationale and alternatives considered, per the required format.

## 1. Where to anchor the revised `out_of_scope_commercial_request` criterion

**Decision**: Edit the `system_instructions` prompt text in
`custom/app/services/custom/scout/action_classifier_service.rb` (the `out_of_scope_commercial_request`
bullet plus a clarifying addition to the "Anti-alucinação" paragraph), not the schema
(`action_classifier_schema.rb`) and not a new post-classification Ruby guard.

**Rationale**: The other three reasons already carry their evidence anchor as prompt text
(`human_offer_accepted`'s anchor lives in the same "Anti-alucinação" paragraph); the schema only
declares the enum values and has no room for behavioral criteria. A post-classification Ruby guard
(e.g. regex-detecting "single decline" after the fact) would require re-deriving from the raw
transcript work the classifier already does, duplicating logic and drifting from the model's own
judgment — the double-confirmation mechanism (`ResponseAuditor#handoff_confirmed?`) already exists
specifically to catch single-call misfires; strengthening the prompt is the same category of fix
already used for the `human_offer_accepted` false-positive (see `response_auditor.rb`'s comment on
`evaluate_action`, "confirmed 5/5 times").

**Alternatives considered**:
- *Ruby-side heuristic guard* (e.g. count declined questions, veto handoff if count == 1): rejected —
  requires re-parsing conversation history for "decline" signal outside the model, duplicating the
  classifier's own job with brittle heuristics, and doesn't correctly handle "customer never showed
  commercial intent" (FR-002's regression requirement) without essentially reimplementing the
  classifier.
- *New schema field* (e.g. `decline_count: integer`) forcing the model to self-report and gating in
  Ruby: rejected as speculative complexity beyond what FR-001/FR-002 require (Constitution Principle
  II) — the existing free-text-criterion + anti-hallucination-anchor pattern already works for the
  other three reasons without a structured counter.

## 2. Where to resolve the reason→{note, message} lookup

**Decision**: Add a private lookup method inside `Custom::Scout::HandoffService` (the class that
already owns both `create_transfer_note` and `send_public_handoff_message`), keyed by the raw
`reason` string it already receives, resolving each side (note vs. message) with its own locale
argument. No new service/class.

**Rationale**: `HandoffService` is already the single point every handoff path (tool, qualified-stage,
classifier) funnels through, and is already the class that resolves `conversation_locale` for the
existing generic fallback — adding the reason-specific lookup here reuses that resolution instead of
introducing a second locale-resolution code path in `ResponseAuditor`. Keeping it as a private method
(not a new service object) matches Constitution Principle II (smallest production-ready change) — a
16-string static lookup table via `I18n.t` doesn't justify a new class.

**Alternatives considered**:
- *New `Custom::Scout::HandoffReasonPresenter` service*: rejected — over-abstraction for a
  4-reason/2-field/2-locale static table; `I18n.t` with a computed key already is the presenter.
- *Resolve in `ResponseAuditor#execute_handoff` and pass both strings down to `HandoffService.perform`*:
  rejected — would duplicate the `account.locale`/`conversation_locale` resolution that already lives
  in `HandoffService`, and would leak i18n-key knowledge into `ResponseAuditor`, which today only
  knows about the raw `reason` string, not about locales.

## 3. i18n key shape and fallback mechanics

**Decision**: New namespace `conversations.scout.handoff_reasons.<reason>.note` and
`conversations.scout.handoff_reasons.<reason>.message`, one entry per `ActionClassifierSchema::REASONS`
value, in both `config/locales/en.yml` and `config/locales/pt_BR.yml`. Resolution uses
`I18n.t(key, locale: ..., default: nil)` (Rails' built-in `default:` option, not a hand-rolled
`I18n.exists?` check) so a missing/unrecognized reason yields `nil` and the existing fallback strings
(`conversations.scout.handoff` for the message, the existing literal `'motivo não informado pelo
modelo'`-style text for the note) apply unchanged — satisfying FR-009 without a bespoke rescue.

**Rationale**: Matches the project's existing i18n convention (same nesting style as
`conversations.scout.handoff`/`follow_up_handoff` already in both files) and Rails' idiomatic
missing-key handling, avoiding a custom `rescue I18n::MissingTranslationData`.

**Alternatives considered**:
- *Ruby `Hash` constant instead of i18n keys* (e.g. `HANDOFF_REASON_COPY = { 'explicit_human_request' =>
  { pt: '...', en: '...' } }`): rejected — bypasses the project's established i18n pipeline (no
  Portuguese/English sync tooling, no locale fallback chain, inconsistent with FR-010's explicit
  "Portuguese and English translation files" framing and the constitution's translation-sync rule for
  fork-owned features).
- *`I18n.exists?` guard before calling `I18n.t`*: rejected — `I18n.t(..., default: nil)` is the
  single idiomatic call already used elsewhere in the codebase for optional-key lookups; a separate
  existence check is redundant.

## 4. Locale resolution per audience (note vs. message)

**Decision**: Reuse `HandoffService#conversation_locale` (already defined, currently only used for the
generic public fallback) for the customer-facing message; add a symmetric `account_locale` resolution
(`@conversation.account.locale.presence || I18n.default_locale.to_s`) for the internal note label.

**Rationale**: Directly satisfies FR-005 (note in account's configured language) and FR-007 (message in
conversation's language) as two independently-resolved fields, matching the scout-doc's explicit
design decision and the existing precedent that `conversation_locale` already diverges from
`account.locale` by design elsewhere in the same file.

**Alternatives considered**:
- *Single shared locale for both note and message*: rejected — directly contradicts FR-005/FR-007 and
  the documented edge case (Portuguese-speaking team account serving an English-writing customer).

## 5. Localizing `create_transfer_note`'s shared prefix — scoped to known reasons only

**Decision**: Add a *second*, dedicated i18n key for the note's prefix text
(`conversations.scout.handoff_note_prefix`), with the `pt-BR` value set to today's exact literal
(`"📋 Transferência para atendimento humano:"`) and an English value added for `en`. This localized
prefix is used **only** on the branch where `reason` matches one of the 4 known
`ActionClassifierSchema::REASONS` codes — i.e. paired with the resolved reason `note` label, both
resolved via the same `account_locale` call. When `reason` is blank or does not match a known code
(the two non-classifier paths' own reason strings, or a missing reason), `create_transfer_note`
keeps interpolating today's hardcoded Portuguese prefix literal exactly as before — untouched by
this feature.

**Rationale**: FR-008 (scoped by FR-012 to the classifier-driven path, and now explicit in FR-008's
own wording) requires the prefix and label to never mix languages *for the four known reasons*. The
prefix literal in `create_transfer_note` is shared code across all three handoff paths, so localizing
it unconditionally would flip the prefix's rendered language for the tool-triggered and
qualified-stage paths too on any non-`pt-BR`-locale account — a direct FR-012 violation, since those
two paths' notes must stay byte-for-byte unchanged regardless of account locale. Branching the
localized prefix strictly on "reason matches a known code" satisfies FR-008 for the classifier path
while making zero observable change to the other two paths for any account locale, not just the
fork's current all-`pt-BR` default.

**Alternatives considered**:
- *Leave the prefix hardcoded in Portuguese, only localize the label*: rejected — violates FR-008
  for the classifier-driven, known-reason case (a `pt-BR` prefix next to an `en` label).
- *Localize the prefix unconditionally for every handoff path* (original decision, superseded):
  rejected — violates FR-012, since it changes the tool-triggered and qualified-stage paths' note
  language for any account whose locale isn't `pt-BR`, which is only accidentally unobservable today
  because every existing account happens to use `pt-BR`.

## 6. No additional LLM call

**Decision**: Confirmed — reason resolution is a pure `I18n.t` hash lookup keyed by the classifier's
already-returned `action_reason` string; no new prompt, no new `@scout.llm_chat` invocation anywhere
in the note/message resolution path.

**Rationale**: Directly required by FR-011 and the scout-doc's explicit rejection of an LLM-authored
closing message (risk of a desynchronized/incoherent message, per `spec80.md`'s objection, which this
feature's fixed-message-map approach sidesteps entirely).
