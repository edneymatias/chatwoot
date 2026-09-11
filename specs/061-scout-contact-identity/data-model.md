# Data Model: Scout Contact Identity Detection

No database schema changes. This feature reads the existing `contacts.name` column and produces a
transient classification used only while building the system prompt for a given turn — there are
no new persisted tables, columns, or migrations. The entities below (from the spec's Key Entities
section) map onto existing runtime objects and one new stateless classifier.

## Entities

### Contact name classification

The transient result of checking whether a contact's current display name looks system-generated.

| Attribute | Type | Notes |
|---|---|---|
| `placeholder?` | Boolean | `true` only for website-widget contacts whose `name` matches the Haikunator shape; never computed/asserted for other channels (FR-001) |

**Validation rule** (FR-001, FR-007, FR-008):
- Matches `\A[a-z]+-[a-z]+-\d{1,3}\z` — two lowercase word-like segments joined by a hyphen,
  followed by a 1–3 digit number. This is a *shape* check, not a dictionary lookup, so it keeps
  working if Haikunator's word lists change.
- `blank?` names return `false` (never flagged as placeholder).
- Real names (`"Maria Silva"`, capitalized, space-separated) and other-channel handles without this
  exact hyphenated shape (`"primeirazinha11234"`) do not match.
- The classifier never mutates, validates, or normalizes `contact.name` (FR-008) — it is a pure
  read-only predicate. Pinned by an explicit spec assertion (not just true-by-construction), e.g.
  `expect { described_class.placeholder_name?(contact) }.not_to change(contact, :name)`, so a
  future refactor that accidentally adds a mutation fails a test instead of only failing by
  inspection (2026-09-02 `/speckit-analyze` finding UND1).

**Carrier**: New stateless service `Custom::Scout::ContactIdentityService`
(`custom/app/services/custom/scout/contact_identity_service.rb`), exposing a single class method
`.placeholder_name?(contact) -> Boolean`. No instance state, no persistence — mirrors the existing
style of `Custom::Scout::EmbeddingConfig`.

### System prompt contact-context section

The portion of the assembled system prompt that describes the current contact to the model.

| Attribute | Type | Notes |
|---|---|---|
| `base_text` | String | Existing `"Contexto do Contato:\n#{@contact.to_llm_text}"` line — unchanged output when the contact is not a placeholder |
| `warning_appended` | Boolean (conceptual) | `true` only when `ContactIdentityService.placeholder_name?(@contact)` is `true` for the current contact |

**Rule** (FR-002, FR-003, FR-005, FR-012, FR-013): When `warning_appended` is true, an additional
paragraph is joined onto `base_text` instructing the model to (a) never address the customer using
the placeholder value, (b) ask for the preferred name as early as possible — ideally in its very
first response — then persist it via the existing `update_contact` tool, (c) prioritize this
question over any other pending qualification question competing for the turn's single question
slot, (d) treat this question as exempt from the "don't invent questions outside configured fields"
guidance in `funnel_section` (FR-013 — added post-audit: `funnel_section` is assembled immediately
after this one, per `research.md`), (e) carry one short clause subordinating (b)/(c) to the existing
no-question-on-handoff rule by cross-reference only — not a restatement (added post-audit per the
documented 2026-08-30 "asked and transferred" incident, see `research.md` FR-011 decision), and (f)
**never ask again once already asked in this conversation, even if the visitor didn't answer**
(FR-005 — added 2026-09-02 per `/speckit-analyze` finding COV1: the warning re-injects on every
turn as long as `contact.name` still matches the placeholder shape, so without this explicit clause
an unanswered ask could repeat on a later turn; this mirrors the "without asking again if already
asked" clause the guardrails bullet below already had for the non-website case, closing the
asymmetry between the two insertion points).

**Carrier**: `Custom::Scout::SystemPromptsService#context_section`, refactored to extract the
contact line into its own private method (e.g. `contact_context_section`) so the conditional
warning can be appended cleanly — following the same section-builder pattern already used for
`open_opportunities_section`, `out_of_office_notice`, etc.

### Guardrails identity bullet

A new, channel-agnostic instruction appended to the existing guardrails list, independent of the
per-contact context section above.

| Attribute | Type | Notes |
|---|---|---|
| `text` | String (static) | One bullet instructing the model to use judgment: if the available name (on any channel other than the website widget — no closed list) looks like a system identifier/handle rather than a person's name, ask once, as early as possible (ideally the first response), with priority over a pending qualification question and exempt from the configured-fields-only guidance, without asking again if already asked or if the name already looks real, subject to the same handoff cross-reference as the context-section warning |

**Rule** (FR-005, FR-006, FR-012, FR-013): This bullet is always present in `guardrails_section` for every
account/turn — unconditional, no per-contact branching (unlike the context-section warning above,
which is per-contact and site-channel-specific). It is the mechanism covering User Story 3
(non-website channels), where no deterministic signal is available, and carries the same
immediacy + priority + configured-fields-exemption + handoff-cross-reference language as the
site-specific warning above (FR-012/FR-013 apply identically on both — see `research.md`).

**Carrier**: `Custom::Scout::SystemPromptsService#guardrails_section` — one additional bullet line
appended to the existing heredoc, inserted after the "Esclarecimento" bullet per the source design.

## No persisted entities

This feature does not add, remove, or alter any ActiveRecord model, migration, or database column.
`Contact#name` (core, upstream) is read-only from this feature's perspective. The only *persisted*
side effect (writing the real name once the customer answers) is performed entirely by the existing
`Custom::Scout::Tools::UpdateContact` tool, which this feature does not modify.

## Supporting change: deterministic coexistence spec (identity text + handoff reminder + funnel guidance)

Not a new entity — a new example in `custom/spec/services/custom/scout/system_prompts_service_spec.rb`
asserting that a prompt built for a placeholder-named contact (with `funnel_section` present, i.e. an
account with configured funnel fields) contains, simultaneously and unmodified: the identity warning
text, the existing "Fallback para humano"/`handoff_closing_reminder_section` handoff text, and the
existing `funnel_section` guidance. A plain string-presence assertion on the rendered prompt, added
post-audit as a cheap regression guard against a future edit accidentally dropping or reordering one
section while touching another (see `research.md`). Complements, does not replace, the
`quickstart.md` manual/`PlaygroundRunner` behavioral scenarios (LLM-dependent, non-deterministic).

## Supporting change: `PlaygroundRunner` gains an optional `contact:` param

Not a new entity — `Custom::Scout::PlaygroundRunner` gains an optional `contact:` keyword
(default `nil`), forwarded to `SystemPromptsService.build(contact: @contact, ...)`. This is required
for the spec's own "Verificação comportamental" replay test to be able to exercise the
contact-context warning at all (see `research.md`); it does not change any existing caller's
behavior since the param is optional and the HTTP playground controller keeps omitting it.
