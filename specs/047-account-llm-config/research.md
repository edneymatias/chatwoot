# Phase 0 Research & Technical Decisions: Account-Level LLM Configuration

## 1. Context & Architecture Validation

This fork isolates custom domain features in `custom/` and prefixes tables with `ichatr_`.
Scout agents previously configured LLM provider settings (provider, model, API key override) on each `Scout` record.
This feature consolidates these credentials into a single account-level configuration entity `ScoutAccountConfig` (table `ichatr_scout_account_configs`), managed exclusively by Account Administrators.

A comprehensive codebase audit across `custom/`, `app/`, and `config/` along with real-world code searches via `gh_grep` and `RubyLLM` gem inspection confirms the following technical decisions:

---

## 2. Technical Decisions & Code Validations

### Decision 1: Model & Storage Strategy
- **Choice**: New table `ichatr_scout_account_configs` and model `ScoutAccountConfig` (`custom/app/models/scout_account_config.rb`).
- **Rationale**:
  - Encapsulates `account_id` (unique foreign key), `provider` (integer enum: `gemini: 0, openai: 1, anthropic: 2`), `model_name` (string), and encrypted `api_key` (`encrypts :api_key`).
  - Keeps core `Account` (`app/models/account.rb`) untouched per constitutional principle I.
  - Queries execute directly via `ScoutAccountConfig.find_by(account_id: account_id)`.
  - Removes `provider`, `model_name`, and `api_key_override` from `Scout` (`custom/app/models/scout.rb`), eliminating the previous ActiveModel `#model_name` method collision workaround.
- **Security & Encryption**:
  - Uses unconditional `encrypts :api_key` (matching `Scout#api_key_override` and `ScoutTool#auth_headers`) ensuring fail-closed security at rest.

### Decision 2: LLM Context Resolution via `RubyLLM` (v1.15.0)
- **Choice**: Refactor `Scout#llm_chat` to fetch the account's `ScoutAccountConfig` and build an isolated `RubyLLM.context`.
- **Validation**:
  - Audited against `ruby_llm 1.15.0` (`Gemfile.lock`).
  - `RubyLLM.context do |c| ... end` creates a thread-safe, isolated configuration copy without polluting global state.
  - Downstream services (`AgentRunner`, `PlaygroundRunner`, `ContactNotesService`) invoke `@scout.llm_chat` without requiring signature changes or explicit config passing.

### Decision 3: Automated Credentials Verification on Save
- **Choice**: Perform automated lightweight verification against the provider API when saving or updating `ScoutAccountConfig`.
- **Implementation & Error Mapping**:
  - Builds candidate `RubyLLM.context` and runs probe `context.chat(model: model_name).ask('ping')`.
  - Handles `ruby_llm` typed exceptions:
    - `RubyLLM::UnauthorizedError`, `RubyLLM::ForbiddenError`: maps to "Invalid API key or insufficient permissions".
    - `RubyLLM::ModelNotFoundError`, `RubyLLM::NotFoundError`: maps to "Model not found or unavailable for this API key".
    - `RubyLLM::PaymentRequiredError`, `RubyLLM::RateLimitError`: maps to "Provider quota or billing limit exceeded".
    - `RubyLLM::Error`, `StandardError`: generic connection failure message.
- **Alternatives Considered**:
  - Format-only regex validation: Cannot detect revoked keys, bad models, or billing limits.

### Decision 4: Sidebar Navigation & Route Restructuring
- **Choice**:
  - Make top-level **Scout** entry in `Sidebar.vue` an expandable group with three children:
    1. **Agentes** (`scouts_index`, active on `scout_detail`, `scout_inboxes`, `scout_products`, `scout_knowledge`, `scout_funnel`, `scout_playground`)
    2. **Configurações** (`scout_settings`, admin-only)
    3. **Ferramentas** (`scout_tools`, moved out of the header button in `ScoutList.vue`)
  - Route permissions: `scout_settings` requires `permissions: ['administrator']` and `featureFlag: FEATURE_FLAGS.SCOUT`.
  - Sidebar integration automatically hides `Configurações` from non-admin agents via `SidebarGroup`'s `isAllowed(child.to)` check.
  - Delete obsolete `dashboard/routes/dashboard/settings/scout/` directory.

### Decision 5: Gating Preconditions for Unconfigured Accounts
- **Choice**:
  - `ScoutsController#create` verifies `ScoutAccountConfig.find_by(account_id: Current.account.id)&.api_key.present?` before creating new Scouts.
  - `ScoutList.vue` displays a gating banner/empty state if unconfigured, guiding administrators to configure LLM settings first.
  - `AgentRunner#pre_call_checks_pass?` checks for valid account configuration alongside quota checks.
