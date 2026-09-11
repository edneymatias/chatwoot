# Phase 1 Data Model: Account-Level LLM Configuration

## 1. Schema Definitions

### Table: `ichatr_scout_account_configs`

Represents the single account-level LLM configuration per tenant.

| Column | Type | Nullable | Default | Constraints / Index | Description |
|---|---|---|---|---|---|
| `id` | bigint | false | auto | Primary Key | Record identifier |
| `account_id` | bigint | false | - | Unique Index, FK -> `accounts.id` | Tenant owner |
| `provider` | integer | false | 0 | Enum | `gemini` (0), `openai` (1), `anthropic` (2) |
| `model_name` | string | false | - | - | Selected model ID (e.g. `gemini-2.5-flash`) |
| `api_key` | text | false | - | Encrypted (`encrypts :api_key`) | Active API key for the provider |
| `created_at` | datetime | false | - | - | Timestamp |
| `updated_at` | datetime | false | - | - | Timestamp |

### Table: `ichatr_scouts` (Modifications)

Drop obsolete per-Scout configuration columns.

| Column | Action | Note |
|---|---|---|
| `provider` | DROP | Superseded by `ichatr_scout_account_configs.provider` |
| `model_name` | DROP | Superseded by `ichatr_scout_account_configs.model_name` |
| `api_key_override` | DROP | Superseded by `ichatr_scout_account_configs.api_key` |

---

## 2. Models & Relationships

### Model: `ScoutAccountConfig` (`custom/app/models/scout_account_config.rb`)
- **Table**: `ichatr_scout_account_configs`
- **Associations**:
  - `belongs_to :account`
- **Enums**:
  - `enum provider: { gemini: 0, openai: 1, anthropic: 2 }`
- **Encryption**:
  - `encrypts :api_key`
- **Validations**:
  - `validates :account_id, presence: true, uniqueness: true`
  - `validates :provider, :model_name, :api_key, presence: true`
  - Custom validation / callback: `validate_credentials!` to test connection against provider.

### Model: `Scout` (`custom/app/models/scout.rb`)
- **Modifications**:
  - Remove `encrypts :api_key_override`
  - Remove `enum provider: ...`
  - Remove `validates :provider, :model_name, presence: true`
  - Remove custom `def model_name` override
  - Update `def llm_chat`:
    ```ruby
    def llm_chat
      config = ScoutAccountConfig.find_by!(account_id: account_id)
      context = RubyLLM.context do |c|
        case config.provider.to_sym
        when :gemini
          c.gemini_api_key = config.api_key
        when :openai
          c.openai_api_key = config.api_key
        when :anthropic
          c.anthropic_api_key = config.api_key
        end
      end
      context.chat(model: config.model_name)
    end
    ```

---

## 3. Entity State Transitions

`ScoutAccountConfig` operates as a singular singleton per account:
- **Unconfigured**: No row in `ichatr_scout_account_configs`. Scout creation / tool management is gated in UI and API.
- **Configured & Active**: Row exists, verified against provider API, all Scouts inherit configuration for chat invocations.
- **Updated**: Changes to provider, model, or API key re-verify against provider API and instantly apply to all Scouts in the account.
