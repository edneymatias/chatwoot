# Data Model: Scout Core & Data Model

## Scout

Account-scoped AI agent configuration. Table: `ichatr_scouts`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | bigint PK | |
| `account_id` | bigint, FK → `accounts`, NOT NULL | scoping; indexed |
| `name` | string, NOT NULL | operator-facing label |
| `persona` | text | system prompt / persona instructions; nullable in this phase |
| `provider` | integer, NOT NULL | `enum :provider, { gemini: 0, openai: 1, anthropic: 2 }` — FR-001a; assigning any other value raises `ArgumentError` before reaching the DB |
| `model_name` | string, NOT NULL | e.g. `gemini-2.0-flash`, `gpt-4o`, `claude-3-5-sonnet` — free text, not validated against a provider's live model list in this phase |
| `api_key_override` | string, encrypted | `encrypts :api_key_override` **unconditionally** (no `Chatwoot.encryption_configured?` guard) — FR-005/006, research.md §2 |
| `default_pipeline_stage_id` | bigint, FK → `ichatr_pipeline_stages`, nullable | routing hint reserved for a later phase; not enforced/used in this phase beyond existing |
| `responses_quota` | integer, NOT NULL, default `-1` | `-1` = unlimited (FR-001, FR-007) |
| `responses_consumed` | integer, NOT NULL, default `0` | FR-001, FR-007 |
| `enabled` | boolean, NOT NULL, default `true` | active/inactive flag |
| `created_at`/`updated_at` | timestamps | |

**Validations**:
- `provider`, `model_name`, `account_id` presence (enum backing already enforces `provider`
  domain).
- `responses_quota`: integer, `>= -1` (FR-007's edge case: `0` must be valid and immediately
  exhausted, not rejected).
- `responses_consumed`: integer, `>= 0`.

**Associations**:
- `belongs_to :account`
- `has_many :scout_inboxes, dependent: :destroy` (research.md §4)
- `has_many :inboxes, through: :scout_inboxes`

**Methods**:
- `quota_available?` → `true` if `responses_quota == -1`; otherwise `responses_consumed <
  responses_quota` (FR-007, covers unlimited / under / at / over quota per spec.md Acceptance
  Scenarios for User Story 3).
- LLM client resolution (FR-004): a method (e.g. `#llm_chat`) that opens a `RubyLLM.context` scoped
  to this Scout's `provider`/`api_key_override` and returns `context.chat(model: model_name)` — see
  research.md §1 for the exact provider-key mapping.

## ScoutInbox

Pivot between a `Scout` and a core `inbox`. Table: `ichatr_scout_inboxes`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | bigint PK | |
| `scout_id` | bigint, FK → `ichatr_scouts`, NOT NULL, `on_delete: :cascade` | |
| `inbox_id` | bigint, FK → `inboxes`, NOT NULL | core table reference; no column added to `inboxes` itself (FR-002) |
| `created_at`/`updated_at` | timestamps | |

**Validations**:
- `inbox_id` uniqueness (**not** composite with `scout_id`) — enforced both at the DB level
  (unique index on `inbox_id` alone) and via `validates :inbox_id, uniqueness: true` on the model,
  per research.md §3 / spec.md Clarifications Q2: an inbox may be linked to at most one Scout at a
  time.

**Associations**:
- `belongs_to :scout`
- `belongs_to :inbox`

**Lifecycle**: destroyed automatically when its `Scout` is destroyed (`dependent: :destroy` on
`Scout#scout_inboxes`) — FR-003a.

## ScoutTool

Account-scoped external REST tool definition. Table: `ichatr_scout_tools`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | bigint PK | |
| `account_id` | bigint, FK → `accounts`, NOT NULL | scoping; indexed |
| `name` | string, NOT NULL | tool identifier surfaced to the LLM (tool-calling schema) |
| `description` | text, NOT NULL | tool-calling schema description |
| `endpoint_url` | string, NOT NULL | external REST endpoint |
| `http_method` | string, NOT NULL | e.g. `GET`/`POST`/`PUT`/`DELETE`; simple string column, no enum needed in this phase |
| `auth_headers` | text, encrypted | `encrypts :auth_headers` **unconditionally** — FR-005/006, research.md §2; stores a serialized header map |
| `parameter_schema` | jsonb, NOT NULL, default `{}` | tool-calling parameter schema (JSON Schema shape), consumed by a later phase's tool-calling pipeline — this phase only needs the shape to exist (FR-003) |
| `created_at`/`updated_at` | timestamps | |

**Validations**:
- `name`, `description`, `endpoint_url`, `http_method`, `account_id` presence.

**Associations**:
- `belongs_to :account`
- No `belongs_to :scout` — deliberately independent of any single Scout's lifecycle
  (research.md §4, FR-003a); a later phase introduces an enablement join (e.g.
  `Scout#scout_tools` via an explicit pivot) if/when tool-calling is wired up, out of scope here.

**Lifecycle**: NOT deleted when a `Scout` is deleted (FR-003a) — independent, account-owned.

## Opportunity (extended)

Existing model (`custom/app/models/opportunity.rb`, table `ichatr_opportunities`). One additive
column:

| Field | Type | Notes |
|-------|------|-------|
| `lost_reason` | string, nullable | optional; populated by a later phase's stage-move tooling when a lead is disqualified (FR-008) — no validation added in this phase beyond nullability |

No association or enum changes to `Opportunity` in this phase.

## Entity Relationship Summary

```text
Account 1──* Scout 1──* ScoutInbox *──1 Inbox (core)
Account 1──* ScoutTool                (no direct Scout relationship in this phase)
Account 1──* Opportunity (existing; gains lost_reason)
```
