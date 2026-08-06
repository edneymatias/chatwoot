# Contract: `create_opportunity` automation action config

**Producer**: `AutomationActionCreateOpportunityInput.vue` (dashboard automation rule editor)
**Consumer**: `Custom::AutomationRules::ActionService#create_opportunity`
**Transport**: `action_params` JSON column on `AutomationRule.actions[]`, unchanged shape end-to-end (no serialization step beyond normal JSON persistence).

## Request shape (action_params)

```jsonc
{
  "pipeline_stage_id": 42,           // integer, required for the opportunity to save
  "assignee_id": "same_as_conversation"  // OR an integer user id, OR null/absent
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `pipeline_stage_id` | integer | Yes (for `Opportunity.create!` to succeed — `pipeline_stage_id` has a presence validation) | Must belong to the same account as the conversation, per `Opportunity`'s existing `pipeline_stage_belongs_to_account` validation. |
| `assignee_id` | string `'same_as_conversation'`, integer user id, or absent/`null` | No | `'same_as_conversation'` is a sentinel, not a real user id — resolved server-side, never looked up as a `User`. |

## Behavior contract

- `assignee_id == 'same_as_conversation'` → resolved to `@conversation.assignee_id` at the moment the action runs. If the conversation has no assignee, the opportunity is created with `assignee_id: nil` — no fallback, no error.
- `assignee_id` is any other truthy value → passed through as-is to `Opportunity.create!(assignee_id: ...)`.
- `assignee_id` blank/absent → `Opportunity.create!(assignee_id: nil)`.
- `pipeline_stage_id` missing or invalid → `Opportunity.create!` raises `ActiveRecord::RecordInvalid`, caught by the automation runner's existing generic error handling (unchanged from today — this contract does not add new error handling, it fixes the *input* that was previously always malformed).

## Backward compatibility

Automation rules persisted before this feature ships used the shape `{ id, name }` (no `pipeline_stage_id` or `assignee_id` keys at all). This contract does **not** retroactively interpret that shape — the config UI simply renders both fields as unset when it encounters the old shape, per spec FR-009. No adapter/migration is part of this contract.
