# Research: Scout Core & Data Model

## 1. Multi-provider LLM client integration

**Decision**: Use `RubyLLM.context { |c| ... }` (per-call scoped context), not the global
`RubyLLM.configure` block, to instantiate a Scout's client. The context is built by setting only
the provider-specific key/base pair that matches `Scout#provider`
(`gemini_api_key`/`anthropic_api_key`/`openai_api_key`, all confirmed as registered
`configuration_options` on the vendored `ruby_llm` 1.15.0 provider classes), then calling
`context.chat(model: scout.model_name)`.

**Rationale**: The existing `Llm::Config` (`lib/llm/config.rb`) and `Llm::BaseAiService`
(`enterprise/app/services/llm/base_ai_service.rb`) used by Captain are OpenAI-only and configure
RubyLLM **globally** via `RubyLLM.configure`, backed by a single installation-wide
`CAPTAIN_OPEN_AI_API_KEY`. That pattern cannot be reused as-is: Scout must support 3 different
providers (FR-001a) with **per-Scout** credentials (`api_key_override`), and mutating global
RubyLLM config per-request would create cross-request races under concurrent Scouts. RubyLLM
already exposes `RubyLLM.context` for exactly this per-call-scoped-config use case (used
elsewhere as `Llm::Config.with_api_key`), so Scout reuses that primitive instead of inventing a
new one, keeping this change additive rather than a fork of `Llm::Config`.

**Alternatives considered**:
- Reuse `Llm::Config`/`Llm::BaseAiService` directly — rejected, OpenAI-only and global-config, not
  multi-provider or per-request safe.
- Build a new custom gateway/abstraction over `ruby_llm` — explicitly rejected by spec62.md and
  the feature spec's Assumptions ("no custom gateway/abstraction is built for this phase").

## 2. Encryption strategy for `api_key_override` / `auth_headers`

**Decision**: Call `encrypts :api_key_override` / `encrypts :auth_headers` **unconditionally** —
no `if Chatwoot.encryption_configured?` guard.

**Rationale**: Every existing encrypted-credential model in this codebase (`DataImport`,
`Integrations::Hook`, `Channel::Whatsapp`, `Channel::Telegram`, `Channel::Instagram`,
`Channel::TwilioSms`, `Channel::FacebookPage`, `Channel::Email`, `Channel::Line`,
`Channel::Tiktok`, `Concerns::WebhookSecretable`) guards `encrypts` with
`Chatwoot.encryption_configured?`, which means when
`ACTIVE_RECORD_ENCRYPTION_*` env vars are absent (the default in `.env.example`, and the default
in this repo's dev/test environment), those models silently fall back to storing the credential
as **plaintext**. FR-005/FR-006 (driven directly by spec62.md's "no environment-based bypass"
requirement) explicitly reject that fallback for Scout: writing `api_key_override` or
`auth_headers` without encryption configured must raise, not silently persist plaintext. Removing
the guard is sufficient — `ActiveRecord::Encryption` itself raises
`ActiveRecord::Encryption::Errors::Configuration` on save when no encryption keys are present, so
no custom validation/error-raising code is needed to satisfy FR-006.

**Alternatives considered**:
- Match the existing `if Chatwoot.encryption_configured?` guard convention for consistency —
  rejected, directly contradicts the explicit acceptance criteria in spec62.md and FR-005/006.
- Add a custom `before_save` validation that manually checks `Chatwoot.encryption_configured?` and
  raises — rejected as redundant; unconditional `encrypts` already produces the required raise
  behavior for free.

## 3. `ScoutInbox` uniqueness enforcement

**Decision**: A unique database index on `ichatr_scout_inboxes.inbox_id` alone (not a composite
`[scout_id, inbox_id]` index), plus a matching `validates :inbox_id, uniqueness: true` on the
model.

**Rationale**: Clarified directly with the user (see spec.md Clarifications, Q2) — an inbox may be
linked to at most one Scout at a time, not merely "not linked to the *same* Scout twice." A
composite index would not enforce that stronger rule.

## 4. Scout deletion cascade behavior

**Decision**: `has_many :scout_inboxes, dependent: :destroy`; `ScoutTool` has no `belongs_to
:scout` at all — it belongs only to `account` and is merely referenced (not owned) by Scouts that
enable it.

**Rationale**: Verified against Chatwoot's Enterprise Captain feature, per explicit user
instruction to mirror its convention (see spec.md Clarifications, Q3).
`Captain::Assistant` (`enterprise/app/models/captain/assistant.rb`) cascade-deletes its inbox
pivot (`has_many :captain_inboxes, ..., dependent: :destroy_async`) but never owns
`Captain::CustomTool` — that belongs to `Account`
(`enterprise/app/models/enterprise/concerns/account.rb`: `has_many :captain_custom_tools,
dependent: :destroy_async, class_name: 'Captain::CustomTool'`) and is only referenced via
`account.captain_custom_tools.enabled`. Scout mirrors this exactly: `ScoutInbox` is a pure pivot
owned by `Scout`; `ScoutTool` is owned by `Account` and independent of any single Scout's
lifecycle. (This phase uses synchronous `dependent: :destroy` rather than Captain's
`:destroy_async`, since Scout has no background-job infrastructure yet in Phase 01 and pivot
volume per Scout is expected to be small — revisit if that assumption changes in a later phase.)

## 5. Migration & table naming convention

**Decision**: Follow `db/migrate/21260817140000_create_ichatr_opportunity_activities.rb` exactly:
far-future timestamp prefix (`21260819...`), `Create<TableName>` class name, `up`/`down` methods
(not reversible `change`), `t.timestamps`, and explicit named indexes to stay under PostgreSQL's
63-char identifier limit.

**Rationale**: Established, working convention already used by every `ichatr_` migration in this
fork; no reason to deviate.

## 6. Provider enum representation

**Decision**: Rails `enum :provider, { gemini: 0, openai: 1, anthropic: 2 }` backed by an
`integer` column, validated as present.

**Rationale**: Matches the existing `Opportunity` model's `enum status: { open: 0, won: 1, lost:
2 }` convention in this codebase, gives FR-001a's "reject anything else" behavior for free
(assigning an unrecognized string raises `ArgumentError` at the Rails level before it ever reaches
the database), and avoids a `CHECK` constraint or a separate validation list to keep in sync.
