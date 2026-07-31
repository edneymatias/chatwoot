# Phase 1 Data Model: Kanban Backend Core

## PipelineStage

Table: `matias_pipeline_stages`

| Field | Type | Notes |
|---|---|---|
| `id` | bigint (PK) | |
| `account_id` | bigint (FK → `accounts`) | required |
| `name` | string | required |
| `position` | integer | required; auto-assigned server-side as `max(position) + 1` within the account on create (FR-002, clarified) |
| `created_at` / `updated_at` | timestamps | |

**Associations**:
- `belongs_to :account`
- `has_many :opportunities` (inverse of `Opportunity#pipeline_stage`)

**Validations**:
- `account_id`, `name` presence required.

**Scopes**:
- Default/ordered scope by `position` ascending.

**Lifecycle rules**:
- On destroy: reject via `has_many :opportunities, dependent: :restrict_with_error` — no cascade,
  no orphaning (clarified answer), satisfying FR-007's "reject deletion" requirement at the model
  level (matches `tasks.md` T006).

**Cross-account rule**: N/A directly (a PipelineStage only ever belongs to its own account); the
cross-account guard lives on `Opportunity` (see below).

## Opportunity

Table: `matias_opportunities`

| Field | Type | Notes |
|---|---|---|
| `id` | bigint (PK) | |
| `account_id` | bigint (FK → `accounts`) | required |
| `contact_id` | bigint (FK → `contacts`) | required; no uniqueness constraint — a Contact may have multiple simultaneous Opportunities |
| `pipeline_stage_id` | bigint (FK → `matias_pipeline_stages`) | required; MUST belong to the same `account_id` as the Opportunity |
| `origin_conversation_id` | bigint (FK → `conversations`), nullable | settable only at creation; immutable thereafter (no update path) |
| `assignee_id` | bigint (FK → `users`), nullable | |
| `title` | string | required |
| `status` | enum (`open` default, `won`, `lost`) | independent of `pipeline_stage_id`; freely editable in any direction, no transition restriction (clarified) |
| `created_at` / `updated_at` | timestamps | |

**Associations**:
- `belongs_to :account`
- `belongs_to :contact`
- `belongs_to :pipeline_stage`
- `belongs_to :origin_conversation, class_name: 'Conversation', optional: true`
- `belongs_to :assignee, class_name: 'User', optional: true`

**Validations**:
- `title`, `contact_id`, `pipeline_stage_id`, `account_id` presence required.
- Custom validation: `pipeline_stage.account_id == account_id` (reject cross-account assignment,
  FR-004).

**State**: `status` enum has no transition guard — any value is reachable from any other value at
any time (clarified answer favors MVP simplicity over a state machine).

**Contact association** (FR-011): exposed via `Contact#opportunities`
(`has_many :opportunities, dependent: :destroy`), added through
`custom/app/models/custom/concerns/contact.rb` — zero edits to `app/models/contact.rb` itself.

## Relationships summary

```
Account 1──* PipelineStage 1──* Opportunity *──1 Contact
                                      │
                                      ├──0..1 Conversation (origin_conversation, immutable after create)
                                      └──0..1 User (assignee)
```

## Notes carried from clarifications

- Deleting a `PipelineStage` with existing `Opportunity` rows attached is rejected, not
  cascaded and not nullified.
- `PipelineStage.position` is never client-supplied on create in this phase; reordering is
  deferred.
- `Opportunity.status` is a plain freely-editable enum in this phase; no reopen restriction.
