# Phase 1 Data Model: Automation Integration — Create Opportunity Action

This phase introduces no new entities. It adds one schema-level constraint to the existing
`Opportunity` entity (defined in Phase 1, `specs/001-kanban-backend-core/data-model.md`) and one
new configuration-only entity representing the action's parameters within an `AutomationRule`.

## Modified: `Opportunity` (`matias_opportunities`, `custom/app/models/opportunity.rb`)

No column changes. One new constraint:

| Constraint | Detail |
|---|---|
| Partial unique index on `origin_conversation_id` | `WHERE origin_conversation_id IS NOT NULL` — guarantees at most one `Opportunity` per originating conversation across the whole table, closing the race window a pure application-level check cannot close. Does not restrict `Opportunity` rows where `origin_conversation_id` is `NULL` (manually-created Opportunities with no origin conversation remain unrestricted, per Phase 1's edge cases). |

No model-level validation changes are required beyond this index — `create_opportunity` handles
the "already exists" case by checking first and treating the resulting `ActiveRecord::RecordNotUnique`
(if a race is lost) as an already-idempotent no-op, not a failure.

## New (configuration-only): `create_opportunity` Automation Action Parameters

Not a persisted entity — this is the shape of one entry in `AutomationRule#actions` (a `jsonb`
array column, unchanged structurally from Phase 1/pre-existing Chatwoot):

```json
{
  "action_name": "create_opportunity",
  "action_params": {
    "pipeline_stage_id": 123,
    "title_template": "optional string, defaults to \"{contact.name} - {Date.current}\" if blank"
  }
}
```

| Field | Required | Type | Notes |
|---|---|---|---|
| `pipeline_stage_id` | Yes | Integer (PipelineStage id) | Must belong to the same account as the conversation/rule; a mismatched account MUST fail Opportunity creation (surfaced via the existing per-action rescue, not a custom check). |
| `title_template` | No | String | Defaults to `"#{@conversation.contact.name} - #{Date.current}"` when blank. |

No new validation is added to `AutomationRule#json_actions_format` beyond the existing generic
check (action name must be present in `actions_attributes`) — `create_opportunity` parameter
validation happens at Opportunity-creation time via the existing `Opportunity` model validations
(Phase 1: `title`, `contact_id`, `pipeline_stage_id`, `account_id` presence; cross-account
pipeline stage rejection).
