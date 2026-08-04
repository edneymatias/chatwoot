# Research: Deal Card Customization

## Extension architecture: `custom/` tree + `include_mod_with`

**Decision**: New backend code (model, controller, policy) lives under `custom/app/...`, mirroring
`PipelineClosingRequiredField`/`PipelineStageRequiredField` exactly. The new table is
`matias_pipeline_card_field_configs` (fork-specific prefix). `Account` and
`CustomAttributeDefinition` gain their new `has_many` associations via the existing
`Custom::Concerns::*` module + `include_mod_with('Concerns::*')` pattern already used for `Account`
(`custom/app/models/custom/concerns/account.rb`), not by editing the core model bodies directly.

**Rationale**: This is the established, already-proven extension point in this fork
(Constitution Principle I) — every prior Phase (6, 7, 19, 9) used this exact shape. Deviating
would create a one-off inconsistency and a future merge-conflict surface.

**Alternatives considered**: Editing `app/models/account.rb` / `app/models/custom_attribute_definition.rb`
directly — rejected, forbidden by Constitution Principle I except for the one-line
`include_mod_with` wiring at the bottom of the file (which itself already exists for `Account`
and needs to be *added*, following the same one-line pattern, for `CustomAttributeDefinition`
since no `Custom::Concerns::CustomAttributeDefinition` module exists yet).

## `CustomAttributeDefinition` cleanup gap

**Decision**: A new `Custom::Concerns::CustomAttributeDefinition` module is introduced (first of
its kind — no prior phase needed it) with `has_many :pipeline_card_field_configs, dependent: :destroy`,
wired via `CustomAttributeDefinition.include_mod_with('Concerns::CustomAttributeDefinition')`
appended at the bottom of `app/models/custom_attribute_definition.rb` (one line, matching the
existing `Account.include_mod_with(...)` convention).

**Rationale**: Verified that `CustomAttributeDefinition` currently has *no* `has_many` back to
`PipelineStageRequiredField`/`PipelineClosingRequiredField` either — deleting a definition
referenced by those tables today would raise `ActiveRecord::InvalidForeignKey` (their migrations
use a plain `foreign_key: true` with no `dependent: :destroy` at the Rails level and no
`on_delete: :cascade` at the DB level). This is a pre-existing gap in those two phases, not
something this phase should silently inherit. FR-003/FR-012 of this feature's spec explicitly
require deleting a definition to cascade-clean this feature's config, so the new concern only
needs to cover `pipeline_card_field_configs` — fixing the pre-existing gap for the other two
tables is out of scope for this feature.

**Alternatives considered**: DB-level `ON DELETE CASCADE` via `foreign_key: { on_delete: :cascade }`
in the migration — would satisfy FR-012 without any model-level `has_many`, but diverges from
this fork's established pattern (`dependent: :destroy` at the Rails level, matching every sibling
table) and wouldn't run any potential future Rails callbacks on the destroyed records. Rejected
for consistency.

## Position / ordering

**Decision**: Reuse `PipelineStage#set_position`'s append-only pattern verbatim:
`account.pipeline_card_field_configs.maximum(:position) + 1` in a `before_validation :set_position, on: :create`
callback. No renumbering on destroy (gaps are harmless — cards only need relative order via
`default_scope { order(:position) }` or an explicit `.order(:position)` in the controller/serializer).

**Rationale**: Byte-for-byte matches existing `PipelineStage` precedent already in this codebase;
no new pattern needed.

**Alternatives considered**: A `position` recompute/renumber on destroy — rejected as unnecessary
complexity per Constitution Principle II (smallest change); relative order survives gaps fine at
a 3-row cap.

## Frontend state module shape

**Decision**: New Vuex module `pipelineCardFieldConfigs` (`actions.js`, `mutations.js`,
`getters.js`, `index.js`) mirrors `pipelineClosingRequiredFields` exactly, plus an `update` action
(closing-required-fields has no `update` since it never needed one; this feature does, for color
changes) using the same `ApiClient`-based API class pattern
(`app/javascript/dashboard/api/pipelineClosingRequiredFields.js`).

**Rationale**: `ApiClient` already provides `update(id, data)` for free — no new HTTP plumbing
needed, just one more thin action wrapping it (same shape as `create`/`destroy`).

## Color input & rendering

**Decision**: Reuse `ColorPicker.vue` (`app/javascript/dashboard/components-next/colorpicker/ColorPicker.vue`,
free-hex `v-model`) for the settings-page color input, and the `Label.vue`
(`components-next/label/`) inline `:style="{ background: labelColor }"` +
`getContrastingTextColor` (`@chatwoot/utils`, already used in `components/ui/Label.vue`) pattern
for the badge itself on `KanbanCard.vue`.

**Rationale**: Both are already-established, already-imported-elsewhere components/helpers in
this codebase for exactly this "free-hex, admin-chosen color" use case (Labels feature) — no new
color infrastructure needed, matching spec14.md's explicit direction.

## Value formatting by `attribute_display_type`

**Decision (updated 2026-08-03)**: `date` values are formatted with `date-fns` (matching
`CustomAttribute.vue`'s existing precedent); `list`/`text`/`number` values render as their plain
string value (no formatter exists or is needed for these). Monetary values — the fixed
`deal_value` field, and any custom attribute with `attribute_display_type: 'currency'` — are the
one exception: they ARE now formatted, using the new pipeline currency setting's
`formatCurrencyAmount` helper (see "Account-wide currency setting" below), because the currency
setting this phase introduces makes that both possible and required (spec FR-015).

**Rationale**: The original research pass (before the currency-setting requirement was added)
found no currency formatter existed anywhere to reuse, so currency values were left as plain
numbers per Constitution Principle II. That constraint is now satisfied differently: this phase
itself introduces the one small, reusable currency-formatting helper (mirroring `billing.js`'s
existing shape, see below), so formatting currency values is no longer "inventing a formatter
from scratch outside scope" — it's the explicit, requested purpose of the new setting. Non-
monetary types are unaffected and still use only pre-existing helpers.

**Alternatives considered**: Still leaving `deal_value`/currency-attribute badges as plain numbers
and only storing the currency setting for future use — rejected; it would make the currency
setting inert within this phase, contradicting the explicit requirement that the badge itself
consume it now (spec FR-015, User Story 2 acceptance scenario 6).

## Account-wide currency setting

**Decision**: A new singleton-per-account model `PipelineCurrencySetting`
(`matias_pipeline_currency_settings`, one row per account) stores the account's chosen currency
code. Backend exposes it as a singular Rails resource, `resource :pipeline_currency_setting, only: [:show, :update]`,
mirroring the existing `resource :branded_email_layout, only: [:show, :update]` /
`resource :saml_settings` singleton-resource pattern already used elsewhere in this codebase
(`show` lazily returns a default `'usd'` without persisting; `update` creates/updates the row).
Frontend gets a small dedicated `app/javascript/dashboard/constants/pipelineCurrency.js` module
(`SUPPORTED_PIPELINE_CURRENCIES = ['usd', 'brl']`, `DEFAULT_PIPELINE_CURRENCY = 'usd'`,
`getCurrencyConfig`, `formatCurrencyAmount`), structurally identical to the existing
`dashboard/constants/billing.js` (`BILLING_CURRENCY_CONFIG`/`formatCurrencyAmount`, itself an
`Intl.NumberFormat`-based helper), rather than importing `billing.js` directly.

**Rationale**: `billing.js`'s own header comment scopes it explicitly as "single source of truth
for billing currencies" — reusing it directly for pipeline/CRM currency would couple two
unrelated domains (Stripe billing vs. deal values) and risk either domain's currency list
diverging awkwardly from the other's needs. Duplicating the ~30-line `Intl.NumberFormat` pattern
into a pipeline-scoped module is a smaller, cleaner change than generalizing `billing.js`, per
Constitution Principle II. The two supported currencies (`usd`, `brl`) match this fork's existing
billing currency support and the user's own stated need — no larger ISO-4217 list is introduced
speculatively.

**Alternatives considered**:
- Reusing `billing.js`'s `formatCurrencyAmount`/`BILLING_CURRENCY_CONFIG` directly — rejected for
  the domain-coupling reason above.
- Refactoring `billing.js` into a generic, domain-agnostic currency module shared by both features
  — rejected as unnecessary scope expansion for this change; can be revisited later if a third
  consumer appears.
- Storing the currency as a column on `PipelineCardFieldConfig` or as an account-level flag on one
  of its rows — rejected: currency is a singleton per account, unrelated to the 0-3 row list of
  badge-field configs, and conflating the two would make the 3-row cap and per-field uniqueness
  validations awkward to reason about.
- A generic key-value settings table (e.g. `matias_account_settings`) for this and future
  singleton settings — rejected as speculative infrastructure for a single current need
  (Constitution Principle II).

## Admin-only authorization

**Decision**: `PipelineCardFieldConfigPolicy` mirrors `PipelineClosingRequiredFieldPolicy` exactly
— `index?`/`show?`/`create?`/`update?`/`destroy?` all gated on `@account_user.administrator?`.

**Rationale**: Confirmed via direct inspection of `custom/app/policies/pipeline_closing_required_field_policy.rb`
and `pipeline_stage_policy.rb` — both existing sibling settings are admin-only, so this new
account-wide settings surface follows the same default without needing a spec clarification.
