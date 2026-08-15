# Contract: Opportunity Automation Rules API & Event Payloads

## 1. REST API Contract (`/api/v1/accounts/{account_id}/automation_rules`)

### POST /api/v1/accounts/{account_id}/automation_rules

Creates an automation rule configured for opportunity triggers.

#### Request Body
```json
{
  "name": "Auto Assign Enterprise Inbound Leads",
  "description": "Assigns lead to Senior Sales rep and sets initial contact tier when opportunity created",
  "event_name": "opportunity_created",
  "conditions": [
    {
      "attribute_key": "pipeline_id",
      "filter_operator": "equal_to",
      "values": [2],
      "query_operator": "and"
    },
    {
      "attribute_key": "value",
      "filter_operator": "greater_than",
      "values": [10000],
      "query_operator": "and"
    }
  ],
  "actions": [
    {
      "action_name": "update_opportunity_assignee",
      "action_params": [5]
    },
    {
      "action_name": "update_contact_custom_attribute",
      "action_params": [
        {
          "attribute_key": "customer_tier",
          "attribute_value": "Tier 1"
        }
      ]
    },
    {
      "action_name": "add_private_note",
      "action_params": ["Automated: Assigned to Senior Sales (Deal Value > $10,000)"]
    }
  ],
  "active": true
}
```

#### Response (200 OK)
```json
{
  "id": 18,
  "name": "Auto Assign Enterprise Inbound Leads",
  "description": "Assigns lead to Senior Sales rep and sets initial contact tier when opportunity created",
  "event_name": "opportunity_created",
  "conditions": [...],
  "actions": [...],
  "active": true,
  "account_id": 1,
  "created_at": "2026-08-14T18:00:00.000Z",
  "updated_at": "2026-08-14T18:00:00.000Z"
}
```

---

## 2. Event Dispatching Contract

When an opportunity lifecycle event occurs, `Opportunity` callbacks dispatch the event payload to `AsyncDispatcher`:

```ruby
Rails.configuration.dispatcher.dispatch(
  event_name,
  Time.zone.now,
  {
    opportunity: opportunity,
    changed_attributes: opportunity.saved_changes,
    from_pipeline_stage_id: from_stage_id,
    performed_by: Current.executed_by || Current.user
  }
)
```

| Event Name | Conditions to Dispatch |
|:---|:---|
| `opportunity_created` | Triggered on `after_commit, on: :create` |
| `opportunity_updated` | Triggered on `after_commit, on: :update` (when attributes changed) |
| `opportunity_stage_changed` | Triggered on `after_commit, on: :update` (when `saved_change_to_pipeline_stage_id?`) |
| `opportunity_won` | Triggered on `after_commit, on: :update` (when `status == 'won'` and `saved_change_to_status?`) |
| `opportunity_lost` | Triggered on `after_commit, on: :update` (when `status == 'lost'` and `saved_change_to_status?`) |
| `opportunity_reopened` | Triggered on `after_commit, on: :update` (when `status == 'open'` and `status_before_last_save.in?(%w[won lost])`) |

---

## 3. Webhook Event Contract (`send_webhook_event` action)

When an opportunity automation executes `send_webhook_event`, the outgoing HTTP POST payload to the configured webhook URL contains:

```json
{
  "event": "automation_event.opportunity_won",
  "id": 42,
  "title": "Enterprise Plan - ACME Corp",
  "status": "won",
  "value": 25000.0,
  "pipeline_id": 1,
  "pipeline_stage_id": 6,
  "contact": {
    "id": 101,
    "name": "Jane Doe",
    "email": "jane@acme.com",
    "phone_number": "+123456789"
  },
  "assignee": {
    "id": 5,
    "name": "Alex Agent",
    "email": "alex@company.com"
  },
  "custom_attributes": {
    "deal_source": "Outbound",
    "billing_cycle": "Annual"
  },
  "origin_conversation_id": 305,
  "account_id": 1
}
```
