# Phase 14: Deal Card Customization

**Depends on**: Phase 6 (card info and ordering), Phase 7 (stage transition
rules / required custom attributes)

## Context

`KanbanCard.vue` today shows a fixed set of info (contact, assignee, status
badge, creation date, unmet-requirements state). This phase adds one more
row to the card: up to 3 admin-configured values, shown as colored badges,
alongside the existing fixed fields (which are unchanged).

**Scope: account-wide today, named for pipeline-wide tomorrow.** There is no
`Pipeline` model in this codebase yet — `PipelineStage` belongs directly to
`account`, and multiple pipelines are themselves still just a placeholder
(Phase 17, `ciclo 4/05-multi-pipeline-and-cross-pipeline-automations`). This
phase's config is therefore keyed by `account_id`, exactly like Phase 19's
`PipelineClosingRequiredField`. When Phase 17 introduces a real `Pipeline`
model, this config's scope should be revisited (`account_id` swapped for
`pipeline_id`) — see the note added to Phase 17's placeholder.

**Field pool**: the same `opportunity_attribute`-model custom attributes
already used by Phase 7's required-fields and Phase 19's closing-fields
config, plus the fixed `value` (deal value) field introduced in Phase 7.
Any future `opportunity_attribute` custom attribute is automatically
eligible for this row — no new flag is added to `CustomAttributeDefinition`.

**Color**: free-form hex per configured field, chosen by the admin — the
same scheme already used by the Labels feature (`AddLabel.vue`'s
`woot-color-picker` storing an arbitrary hex, rendered via `Label.vue`'s
`labelStyle`/`getContrastingTextColor` pattern). This is an existing,
established exception to the "Tailwind only" styling rule for
user-chosen colors, and this phase reuses it as-is rather than introducing
a curated token palette.

**Display**: value only, no attribute name label, to keep the row compact.
A configured field's badge simply does not render for an opportunity that
has no value for it yet — no empty/placeholder badge.

## Functional Requirements

### Data model

**FR-001**: A new table `matias_pipeline_card_field_configs` is added
(`account_id`, `custom_attribute_definition_id` nullable, `field_type`
integer, `color` string, `position` integer, timestamps). `field_type` is
an enum (`custom_attribute: 0`, `deal_value: 1`); `custom_attribute_definition_id`
is null when `field_type` is `deal_value`.

**FR-002**: A new `PipelineCardFieldConfig` model belongs to `account` and,
optionally, `custom_attribute_definition`. It validates: `color` presence;
`custom_attribute_definition_id` uniqueness scoped to `account_id` (when
`custom_attribute`); the referenced definition's `attribute_model` is
`opportunity_attribute` (same validation shape as
`PipelineStageRequiredField`/`PipelineClosingRequiredField`); at most one
`deal_value`-type row per account; **at most 3 rows total per account**.
`position` is auto-assigned on create, append-style, following
`PipelineStage#set_position`'s pattern (`account.pipeline_card_field_configs.maximum(:position) + 1`).
Destroying an entry does not renumber the remaining ones — gaps in
`position` are harmless since cards only need relative ordering.

**FR-003**: `Account` gains `has_many :pipeline_card_field_configs, dependent: :destroy`.
`CustomAttributeDefinition` gains `dependent: :destroy` on its association
to this model (mirroring how required-fields are already cleaned up),
so deleting a definition removes any card-field config referencing it.

### Backend API

**FR-004**: A new `Api::V1::Accounts::PipelineCardFieldConfigsController`
(including `Concerns::KanbanFeatureGuard`, authorized via Pundit like its
siblings) supports:
- `index` — list the account's configs.
- `create` — add a field (`custom_attribute_definition_id` or `field_type: deal_value`),
  rejecting with `422` past the 3-row cap or a duplicate `deal_value`.
- `update` — change an existing entry's `color`.
- `destroy` — remove a field.

**FR-005**: `PipelineStagesController` and `OpportunitiesController` require
no changes — `custom_attributes`, `value`, and each definition's
`attribute_display_type` are already available in the payloads the board
loads today (since Phase 7).

### Frontend

**FR-006**: A new Vuex module `pipelineCardFieldConfigs` (mirroring
`pipelineClosingRequiredFields`'s `actions`/`getters`/`mutations`/`index`
shape) provides `fetch`, `create`, `update`, `destroy`.

**FR-007**: `KanbanBoard.vue`'s mount logic dispatches
`pipelineCardFieldConfigs/fetch` once per board visit, alongside the
existing `pipelineStages/fetch`.

**FR-008**: The pipeline-stages settings page (`routes/dashboard/settings/pipelineStages/Index.vue`)
gains a third tab, **`Card Fields`, placed first** (before `Pipeline Stages`
and `Closing Requirements`), backed by a new `CardFieldConfig.vue` styled
after `ClosingRequiredFields.vue`:
- Checkbox list of `opportunity_attribute`-model custom attributes (via
  `attributes/getAttributesByModel`) plus a fixed "Deal Value" pseudo-option.
- Checking a field reveals an inline `ColorPicker.vue` (the free-hex
  component already used elsewhere, e.g. portal/inbox branding) for that
  field's badge color.
- Checkboxes disable once 3 fields are selected (client-side mirror of the
  backend's hard cap), with a "3/3 selected" hint.
- On save, diffs selections against the loaded configs: new selections →
  `create`; unchecked existing entries → `destroy`; color changes on
  entries that remain selected → `update`. No manual reordering UI —
  `position` follows creation order, which is sufficient at a 3-item cap.

**FR-009**: `KanbanCard.vue` gains a new row, rendered only when
`pipelineCardFieldConfigs` has at least one entry:
- For each config (ordered by `position`), resolves the opportunity's raw
  value — `custom_attributes[definition.attribute_key]` for
  `custom_attribute`, `opportunity.value` for `deal_value`.
- Skips rendering that config's badge entirely if the resolved value is
  blank (`undefined`/`null`/`''`). If every configured value is blank for
  a given card, the whole row is omitted (no empty gap).
- Formats the value by `attribute_display_type` (currency, date, list,
  plain text/number as appropriate; `deal_value` always formats as
  currency), reusing existing formatting helpers already used elsewhere
  for these types (no new formatter is introduced from scratch).
- Renders each badge using the same inline-style pattern as `Label.vue`
  (`background-color` from the config's `color`, text color via
  `getContrastingTextColor`) — value only, no attribute name.

## Out of Scope (this phase)

- A real `Pipeline` model / per-pipeline scoping — deferred to Phase 17;
  this phase's config is account-scoped, named for an easy later migration.
- Toggling or reordering the card's existing fixed fields (contact,
  assignee, status badge, creation date) — those remain exactly as they
  are today; only the new badge row is configurable.
- A curated/fixed color-token palette — free-hex, matching the existing
  Labels color scheme, is used instead.
- Manual drag-to-reorder of the 3 configured fields — creation order is
  sufficient at this cap.
- Any new "eligible for card display" flag on `CustomAttributeDefinition`
  — eligibility is simply "is an `opportunity_attribute`", same pool as
  Phase 7 and Phase 19.
- Showing a placeholder/empty badge when a configured field has no value
  — the badge is omitted instead.

## Completion Criteria

Verify inside the `rails`/`vite` containers as appropriate.

1. An admin can add up to 3 fields (opportunity custom attributes and/or
   Deal Value) in the new "Card Fields" tab (shown first), each with a
   chosen color; a 4th add attempt is blocked both client-side and by the
   backend (`422`).
2. Every card shows a colored, type-formatted, value-only badge for each
   configured field that has a present value on that opportunity; fields
   with no value show no badge.
3. Removing a config, or deleting the custom attribute definition it
   references, removes the corresponding badge from all cards.
4. Accounts with no configured card fields render cards exactly as before
   this phase (no new row, no visual change).
5. `pnpm eslint` and `bundle exec rubocop` pass for touched files.
