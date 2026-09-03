# Phase 1 Data Model: Unified Card Click & History Links

No new persisted entities, columns, or migrations. This feature only changes how existing data is
navigated to and, for one field, how much of it is exposed in an existing response. The entities
below are the existing domain concepts this feature reads from and links to (documented for design
context — see `research.md` for why each field is needed).

## Opportunity (existing — `custom/app/models/opportunity.rb`)

Unchanged by this feature. Relevant existing fields used:

| Field | Type | Used for |
|---|---|---|
| `active_conversation_id` | integer, nullable | Decides card-click destination (FR-001/FR-002) |
| `active_conversation_display_id` | integer, nullable (via association) | Route param when opening the active conversation |

## Conversation (existing — core `Conversation` model)

Unchanged by this feature. Relevant existing fields used:

| Field | Type | Used for |
|---|---|---|
| `id` / `display_id` | integer | Resolving/loading a specific conversation (existing drawer path) |
| `status` | enum (`open`/`pending`/`resolved`/`snoozed`) | New: surfaced per history entry (FR-011) |
| `inbox_id`, `team_id` | integer, nullable | Existing `ConversationPolicy#show?` inputs (unchanged; reused, not reimplemented) |

## OpportunityActivity (existing — `custom/app/models/opportunity_activity.rb`, table `ichatr_opportunity_activities`)

Unchanged schema. `metadata` (jsonb) already carries, per event type, what this feature needs to
locate the referenced conversation:

| `event_type` | Existing `metadata` keys (unchanged) |
|---|---|
| `conversation_opened` | `conversation_id`, `conversation_display_id`, `is_origin` |
| `conversation_transferred_in` | `conversation_id`, `conversation_display_id`, `transferred_from_opportunity_id/title` |
| `conversation_transferred_out` | `conversation_id`, `conversation_display_id`, `transferred_to_opportunity_id/title` |
| `conversation_detached` | `conversation_id`, `conversation_display_id` |

No new metadata keys are written at activity-creation time — status is explicitly the conversation's
*current* state (per spec Assumptions), so it must be resolved at read time, not stored historically.

## Response enrichment (new — `Api::V1::Accounts::Opportunities::ActivitiesController#index`)

The `index` action's JSON response gains two computed, non-persisted fields, present only on the
four conversation-related event types listed above (absent/irrelevant on all others, e.g.
`opportunity_stage_changed`):

| New field | Type | Computed from |
|---|---|---|
| `conversation_status` | string, nullable (`open`/`pending`/`resolved`/`snoozed`) | `Conversation#status` for `metadata['conversation_id']`, batch-loaded; `nil` if the conversation no longer exists |
| `conversation_viewable` | boolean | `ConversationPolicy.new(pundit_user, conversation).show?` for `Current.user`, batch-evaluated; `false` when the conversation no longer exists |

The frontend renders a conversation-related entry as a clickable link with a status badge only when
`conversation_viewable` is `true`; otherwise (nonexistent or unauthorized) it renders as plain,
non-clickable text with no status badge (FR-006a, FR-011).

## State / transitions

No new state machine. `conversation_status` simply mirrors the conversation's existing status enum
at read time; it is not tracked, cached, or transitioned by this feature.
