# Contract: `opportunity_updated` ActionCable event

## Channel / stream

Delivered over the existing account-level stream `account_#{account_id}` (the same stream
`RoomChannel` already subscribes every logged-in agent/admin session to). No new
`ActionCable::Channel` subclass.

## Trigger

Emitted once per `Opportunity` create or update, after the database transaction commits
(`after_commit on: %i[create update]`).

## Payload

```json
{
  "event": "opportunity_updated",
  "data": {
    "id": 123,
    "pipeline_stage_id": 4,
    "status": "open",
    "contact_id": 55,
    "assignee_id": 9,
    "updated_at": "2026-07-31T12:00:00.000Z",
    "account_id": 1
  }
}
```

| Field | Type | Nullable | Notes |
|---|---|---|---|
| `id` | integer | no | |
| `pipeline_stage_id` | integer | no | |
| `status` | string enum: `open`, `won`, `lost` | no | |
| `contact_id` | integer | no | |
| `assignee_id` | integer | yes | |
| `updated_at` | ISO8601 string | no | |
| `account_id` | integer | no | Merged in for routing, matches every other account-broadcast payload |

## Consumer contract (frontend)

`app/javascript/dashboard/helper/actionCable.js`'s `this.events` map MUST have an
`'opportunity_updated'` key. Its handler MUST dispatch into the Phase 3 `opportunities` Vuex
module using the payload's `id`/`pipeline_stage_id` to move the card between `cardIdsByStage`
arrays if the stage changed, and upsert `cardsById[id]` with the remaining fields — reusing the
mutation Phase 3 already built, not new mutation logic.

## Backward/idempotency notes

Receiving the same payload twice (e.g. duplicate delivery) MUST be safe — upserting `cardsById`
and recomputing `cardIdsByStage` membership from `pipeline_stage_id` is naturally idempotent.
