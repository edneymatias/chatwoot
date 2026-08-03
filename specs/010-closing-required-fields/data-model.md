# Data Model: Closing Required Fields (Win/Loss)

## Entity: PipelineClosingRequiredField

New model, new table `matias_pipeline_closing_required_fields`. Independent of
`PipelineStageRequiredField` (no shared table, no shared association).

| Field | Type | Notes |
|---|---|---|
| `id` | bigint | primary key |
| `account_id` | bigint, FK → `accounts` | required |
| `custom_attribute_definition_id` | bigint, FK → `custom_attribute_definitions` | required |
| `outcome` | integer, enum `{ won: 0, lost: 1 }` | required |
| `created_at` / `updated_at` | datetime | standard timestamps |

**Indexes**:
- Unique index on `(account_id, custom_attribute_definition_id, outcome)` — named e.g.
  `idx_matias_pipeline_closing_req_fields_on_acc_attr_outcome`. Prevents duplicate entries within
  the same outcome (FR-003) while allowing the same attribute to appear under both `won` and `lost`
  (two rows, different `outcome` value, both satisfy the unique index).

**Associations**:
- `belongs_to :account`
- `belongs_to :custom_attribute_definition`
- On `Account` (or wherever `PipelineStageRequiredField` is exposed today — currently only reachable
  through `PipelineStage`): add `has_many :pipeline_closing_required_fields` on `Account` directly,
  since this entity is account-scoped, not stage-scoped (no `PipelineStage` association at all).

**Validations** (mirrors `PipelineStageRequiredField`):
- `validates :account, presence: true`
- `validates :custom_attribute_definition, presence: true`
- `validates :custom_attribute_definition_id, uniqueness: { scope: %i[account_id outcome] }` —
  note the scope includes `outcome` (unlike the sibling model's scope, which is just `account_id`)
  to satisfy FR-003.
- `validate :definition_must_be_opportunity_attribute` — identical logic to the sibling model:
  reject if `custom_attribute_definition.opportunity_attribute?` is false (FR-004).

**Lifecycle**: No state transitions on this entity itself — it is a pure configuration row, created
via settings UI and destroyed when an admin removes an attribute from a list (FR-001, FR-002).
Deletion is immediate (no soft-delete), matching the sibling model.

## Entity: Opportunity (extended)

No new columns. Gains one new validation, additive to the existing one:

```ruby
validate :validate_closing_requirements, on: :update, if: :status_changed?
```

**Behavior**:
- Runs only on `update` (never on `create` — an opportunity cannot be created already won/lost per
  existing scope, unchanged by this feature).
- Guard clause: `return unless status.to_s.in?(%w[won lost])` — satisfies FR-007 (no check on
  reopen to `open`).
- Looks up `PipelineClosingRequiredField.where(account_id: account_id, outcome: status)`.
- For each returned row's `custom_attribute_definition`, checks presence via
  `(custom_attributes || {}).key?(definition.attribute_key)` — same "key presence" semantics as
  the existing `validate_forward_stage_move_requirements` (confirmed by reading
  `custom/app/models/opportunity.rb`), not a blank/empty-string check, for consistency with the
  sibling mechanism's existing behavior.
- On any missing key: `self.missing_required_fields = { custom_attribute_keys: missing_keys }` and
  `errors.add(:base, 'Missing required fields to close this opportunity')`.

**Relationship to existing `validate_forward_stage_move_requirements`**: fully independent method,
runs on a different `if:` condition (`status_changed?` vs. `pipeline_stage_id_changed?`). Both can
run in the same `update` call if both `status` and `pipeline_stage_id` change together; see
`research.md`'s risk note on `missing_required_fields` being a single attr_accessor in that
(UI-unreachable) combined case.

## State / Outcome Model

```
Opportunity.status: open (0) ─┬─→ won (1)   [validate_closing_requirements checks outcome: won]
                               └─→ lost (2)  [validate_closing_requirements checks outcome: lost]

won (1) ──→ open (0)   [reopen — no check, FR-007]
lost (2) ─→ open (0)   [reopen — no check, FR-007]
```

No direct `won ↔ lost` transition modeling assumed beyond what the existing `status` enum already
allows; both are treated as independent target outcomes for validation purposes only.
