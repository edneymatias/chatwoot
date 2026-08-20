# Phase 1 Data Model: Scout Commercial Configuration UI

Existing tables (`ichatr_scouts`, `ichatr_scout_inboxes`, `ichatr_scout_tools`) already exist from
Phase 01-04 and are **not** re-migrated here except where noted. New tables/columns are additive
migrations under `db/migrate/` (timestamp `21260...`, `ichatr_` prefix, per this fork's convention),
never altering upstream core tables.

## Scout (`ichatr_scouts`) — existing, no schema change

Relevant existing columns this feature's UI reads/writes (see `custom/app/models/scout.rb` for the
full model):

| Column | Type | UI surface |
|---|---|---|
| `name`, `persona` (aliased `system_prompt`) | string/text | Scout create/edit |
| `provider`, `model_name`, `api_key_override` | enum/string/encrypted string | Settings (admin-only), not the primary-menu screens |
| `default_pipeline_stage_id`, `qualified_stage_id`, `unqualified_stage_id` | bigint, FK → `PipelineStage` | Funnel config tab |
| `product_catalog` | jsonb array | Product catalog tab (see below) |
| `handover_team_id` | bigint, FK → `Team` | Funnel config tab |
| `responses_quota` | integer (`-1` = unlimited) | Scout create/edit (plain numeric field, FR-012) |
| `enabled` | boolean | Scout list/edit (active toggle) |

`product_catalog` entry shape (array of objects, each with a server-generated `id`):

```json
{
  "id": "uuid",
  "name": "string",
  "pricing": "string",
  "value_proposition": "string"
}
```

## ScoutInbox (`ichatr_scout_inboxes`) — existing, no schema change

Pivot table, `scout_id` + `inbox_id`, **unique index on `inbox_id`** — an inbox can belong to at
most one Scout. The inbox-association UI (FR-002) must check for and surface this constraint
(offer to move the inbox rather than fail silently on a DB uniqueness error).

## ScoutTool (`ichatr_scout_tools`) — existing, no schema change

Account-scoped (no `scout_id` — every enabled `ScoutTool` on the account is available to every
Scout on that account via the `call_custom_api` native tool, per Phase 04). The Phase 05 CRUD
screen (FR-006) operates on `Current.account.scout_tools`, not on a per-Scout list.

| Column | Type |
|---|---|
| `name`, `description` | string/text |
| `endpoint_url`, `http_method` | string |
| `auth_headers` | encrypted text (jsonb-in-encrypted-string) |
| `parameter_schema` (aliased `parameters_schema`) | jsonb |
| `enabled` | boolean |

## ScoutRequiredField (`ichatr_scout_required_fields`) — NEW

Mirrors `PipelineStageRequiredField` / `ichatr_pipeline_stage_required_fields` exactly.

| Column | Type | Notes |
|---|---|---|
| `account_id` | bigint, indexed, not null | |
| `scout_id` | bigint, indexed, not null, FK → `ichatr_scouts` | |
| `custom_attribute_definition_id` | bigint, indexed, not null, FK → `custom_attribute_definitions` | |
| `created_at`/`updated_at` | timestamps | |

Unique index on `(scout_id, custom_attribute_definition_id)` to prevent duplicate selections.
Unlike `PipelineStageRequiredField` (which enforces account-wide exclusivity — one attribute
required by at most one stage), the same `CustomAttributeDefinition` may be required by multiple
Scouts; this is intentional (see `research.md` §1).

**Validation**: `custom_attribute_definition.attribute_model` must be `Contact` or `Opportunity`
(broader than `PipelineStageRequiredField`'s `Opportunity`-only rule — see `research.md` §1).

Represents the "Qualification field" key entity from `spec.md` (FR-005): which
`CustomAttributeDefinition`s a Scout must collect during qualification (main pain point, estimated
budget, decision timeline, decision maker, etc. — whatever custom attributes the account has
already defined).

## ScoutKnowledgeSource (`ichatr_scout_knowledge_sources`) — NEW

Represents the "Knowledge source" key entity (FR-004): a crawled URL, an uploaded document, or an
FAQ/objection-handling entry.

| Column | Type | Notes |
|---|---|---|
| `account_id` | bigint, indexed, not null | |
| `scout_id` | bigint, indexed, not null, FK → `ichatr_scouts` | |
| `kind` | integer enum: `url` (0), `document` (1), `faq` (2), not null | |
| `url` | string, nullable | required when `kind == url` |
| `question` | text, nullable | required when `kind == faq` |
| `answer` | text, nullable | required when `kind == faq` |
| `status` | integer enum: `pending` (0), `ready` (1), `failed` (2), default `pending`, not null | |
| `error_message` | text, nullable | populated when `status == failed` |
| `content` | text, nullable | extracted/crawled text once `status == ready`, fed into the Scout's RAG context |
| `created_at`/`updated_at` | timestamps | |

`ActiveStorage` attachment `document_file` (only present when `kind == document`), validated the
same way as `Captain::Document`:
- Content type MUST be `application/pdf`.
- Byte size MUST NOT exceed 10 megabytes.

**Validations**:
- `kind` presence.
- `url` presence + valid-URL format when `kind == url`.
- `question`/`answer` presence when `kind == faq`.
- `document_file` attached when `kind == document`; format/size validated as above.

**State transitions**: `pending → ready` (processing succeeded) or `pending → failed` (crawl fetch
failed / PDF text extraction failed / validation failed after enqueue). A background job
(`Scout::KnowledgeSources::ProcessJob`, enqueued on create) performs a single-page fetch (`url`) or
PDF text extraction (`document`) and updates `status`/`content`/`error_message`. This is
intentionally simpler than `Captain::Documents::CrawlJob`'s multi-page/Firecrawl fanout — Scout does
not call any `Captain::*` (`enterprise/`) classes directly (see `research.md` §2). `ready`/`failed`
sources can be re-processed by the user (re-enqueues the job, resets to `pending`).

**Required follow-up**: `Scout::AgentRunner` (`custom/app/services/custom/scout/agent_runner.rb:85`)
currently reads `@scout.knowledge_sources` as jsonb; it must be updated to read
`scout.scout_knowledge_sources.where(status: :ready)` once this table ships (see `research.md` §2).

## Relationships summary

```text
Account
  ├─< Scout (has_many)
  │     ├─ belongs_to default_pipeline_stage / qualified_stage / unqualified_stage → PipelineStage
  │     ├─ belongs_to handover_team → Team
  │     ├─< ScoutInbox >─ Inbox            (unique per inbox)
  │     ├─< ScoutRequiredField >─ CustomAttributeDefinition
  │     ├─< ScoutKnowledgeSource
  │     └─ product_catalog (jsonb array, no association)
  └─< ScoutTool (account-scoped, no scout_id)
```

## Non-persistent entity: Playground session

Not a table. A Playground exchange (FR-007) is a single request/response cycle:
`{ scout_id, message }` in → `{ reply, tool_calls: [{ tool_name, arguments, result, error }] }` out.
See `research.md` §4 (`Scout::PlaygroundRunner`) — safety is guaranteed by an explicit `playground:
true` flag threaded through `AgentRunner`/native tools (each mutating tool skips its `.save!` and
returns a simulated result), not by feeding in unpersisted ActiveRecord objects.
