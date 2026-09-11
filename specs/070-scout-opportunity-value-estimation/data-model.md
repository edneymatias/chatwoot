# Data Model: Scout Opportunity Value Estimation

No new tables. One existing table gains two new columns; no existing column changes shape or
meaning.

## `Scout` (`ichatr_scouts`)

| Field | Type | Notes |
|---|---|---|
| `interest_attribute_definition_id` | `bigint`, nullable, FK → `custom_attribute_definitions.id` | New. `on_delete: :nullify` — if the referenced attribute definition is deleted, the Scout silently reverts to "no interest attribute configured" (FR-003) rather than being blocked or destroyed. Not required to be a `list`-type attribute at the database level, but the configuration UI and controller-level validation only ever let a `list`-type attribute be assigned (Clarification: restrict to list-type only). |
| `value_by_interest` | `jsonb`, `NOT NULL DEFAULT '{}'` | New. Shape: `{ "<interest option string>" => <number> }`. Keys are a subset of `interest_attribute_definition.attribute_values`; an option absent from this hash is intentionally unpriced (FR-007) — never defaulted to `0`. |

**Association**: `belongs_to :interest_attribute_definition, class_name: 'CustomAttributeDefinition', optional: true`

**Relationship semantics**: A Scout has at most one interest attribute. That attribute definition
is strictly `attribute_model: opportunity_attribute` (unlike `required_custom_attribute_definitions`
which allows both contact and opportunity attributes) and `attribute_display_type: list`, because
the interest signal and monetary value belong directly to the Opportunity.

**Validation**: `optional: true` on the association and the `NOT NULL DEFAULT '{}'` column default
already make the feature fully inert when unconfigured (FR-003) — no guard code needed for that
case. One model-level validation is added: `interest_attribute_definition`, when present, MUST
have `attribute_display_type == 'list'`. This is the system-of-record enforcement of FR-001
("MUST NOT be selectable" for non-list attributes) — the config UI's interactive chip filter is a
convenience on top of it, not a substitute for it, since a non-list attribute ID could otherwise
reach `scout_params` through the API directly, bypassing the dashboard. Per the project's
"enforce eligibility rules at the earliest shared entry point" convention, this single model
validation covers every write path (API, Rails console, future callers) rather than duplicating
the check in the controller.

## `Opportunity` (existing, unchanged shape)

No schema change. This feature only *writes* to two already-existing fields, under new
conditions:

- `custom_attributes` (jsonb) — gains the interest attribute's key/value when auto-classified from
  ad content (new) or from the lead's qualification answer (existing behavior, unchanged).
- `value` (decimal/numeric, existing) — now also written by `Custom::Scout::ValueEstimationService#sync!`
  whenever the interest attribute changes and a mapping exists, in addition to the existing paths
  (human entry, `estimated_value` param already wired but previously unused in practice).

## `CustomAttributeDefinition` (existing, read-only for this feature)

Read via `scout.interest_attribute_definition`:

- `attribute_key` (string) — the key used both to read `opportunity.custom_attributes[key]` and to
  look up `scout.value_by_interest[value]`.
- `attribute_values` (jsonb array of strings) — the closed set of options
  `Custom::Scout::ReferralInterestClassifierSchema.for_options` constrains the classifier to (or
  a distinct `null`/not-identified outcome — never a value outside this set).
- `attribute_display_type` — must equal `list` for the attribute to be selectable as a Scout's
  interest attribute (Clarification: enforced at selection time, not by a new column here).

## Derived/computed concepts (not persisted)

- **"Not identified"**: the classifier's `null` result. Not a sentinel string, not a real option —
  represented in code as `nil`/absence, distinct from any member of `attribute_values` (Decision
  #3 in the source design doc; FR-005).
- **Referral/ad content used for classification**: concatenation of
  `opportunity.campaign_name`, `campaign_adset_name`, `campaign_ad_name`, `campaign_headline`,
  `campaign_body` (all already persisted by `Custom::ReferralAttributionService` before this
  feature's classification step runs) — not a new field, just the input the classifier reads.

## State/flow summary

```text
Opportunity created from paid-ad referral
  └─ Custom::ReferralAttributionService.process (existing, persists campaign_* fields)
  └─ [NEW] classify ad content → interest option | nil
       ├─ nil → no-op, qualification conversation proceeds as today
       └─ option → opp.custom_attributes[interest_key] = option
                 → Custom::Scout::ValueEstimationService#sync!(opp)
                      ├─ value_by_interest[option] present → opp.value = mapped amount
                      └─ absent → opp.value left untouched (no zero, no placeholder)

Opportunity updated during qualification (lead answers directly)
  └─ apply_opportunity_fields merges custom_attributes (existing)
  └─ [NEW] Custom::Scout::ValueEstimationService#sync!(opp) — same lookup, same rules,
           regardless of whether interest came from the lead or an earlier auto-classification
```
