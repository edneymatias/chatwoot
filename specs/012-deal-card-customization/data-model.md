# Data Model: Deal Card Customization

## Entity: `PipelineCardFieldConfig`

Table: `matias_pipeline_card_field_configs`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | primary key |
| `account_id` | bigint, not null | FK → `accounts` |
| `custom_attribute_definition_id` | bigint, nullable | FK → `custom_attribute_definitions`; null when `field_type` is `deal_value` |
| `field_type` | integer, not null | enum: `custom_attribute: 0`, `deal_value: 1` |
| `color` | string, not null | free-hex string (e.g. `#FF5733`), admin-chosen |
| `position` | integer, not null | append-only ordering, auto-assigned on create |
| `created_at` / `updated_at` | datetime | standard timestamps |

### Relationships

- `belongs_to :account`
- `belongs_to :custom_attribute_definition, optional: true`
- `Account has_many :pipeline_card_field_configs, dependent: :destroy` (via `Custom::Concerns::Account`)
- `CustomAttributeDefinition has_many :pipeline_card_field_configs, dependent: :destroy` (via new
  `Custom::Concerns::CustomAttributeDefinition`)

### Validations

- `color` presence
- `custom_attribute_definition_id` uniqueness scoped to `account_id`, only when `field_type` is
  `custom_attribute` (same shape as `PipelineStageRequiredField`/`PipelineClosingRequiredField`)
- Custom validation: referenced `custom_attribute_definition` (when present) must have
  `attribute_model == 'opportunity_attribute'`
- Custom validation: at most one row with `field_type: deal_value` per `account_id`
- Custom validation: at most 3 total rows per `account_id` (across both field types)

### Lifecycle

- `position` auto-assigned on create: `(account.pipeline_card_field_configs.maximum(:position) || 0) + 1`
  (mirrors `PipelineStage#set_position`)
- No renumbering on destroy — gaps in `position` are harmless (relative order only)
- Destroyed automatically when the account is destroyed, or when its referenced
  `custom_attribute_definition` is destroyed

## Entity: `PipelineCurrencySetting`

Table: `matias_pipeline_currency_settings` — one row per account (singleton).

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | primary key |
| `account_id` | bigint, not null, unique | FK → `accounts`, one row per account |
| `currency` | string, not null, default `'usd'` | one of the fixed supported codes (`usd`, `brl`) |
| `created_at` / `updated_at` | datetime | standard timestamps |

### Relationships

- `belongs_to :account`
- `Account has_one :pipeline_currency_setting, dependent: :destroy` (via `Custom::Concerns::Account`)

### Validations

- `currency` presence, inclusion in the fixed supported list (`%w[usd brl]`, mirroring
  `SUPPORTED_BILLING_CURRENCIES` in `app/javascript/dashboard/constants/billing.js`)
- `account_id` uniqueness (one row per account)

### Lifecycle

- Lazily created on first `show`/`update` if it doesn't exist yet (no seeding step); reading it
  for an account with no row returns the default (`'usd'`) without persisting a row until the
  admin explicitly saves a change.
- Independent of `PipelineCardFieldConfig` — does not count against, or interact with, the
  3-row cap on badge fields.

## No changes to existing entities' shape

- `Opportunity` (`custom_attributes`, `value`) — already exposes everything this feature reads;
  no schema change.
- `CustomAttributeDefinition` — no new columns; gains one `has_many` association only.
- `PipelineStage` — untouched.
