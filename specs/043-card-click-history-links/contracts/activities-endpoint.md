# Contract: `GET /api/v1/accounts/:account_id/opportunities/:opportunity_id/activities`

Existing endpoint (`Api::V1::Accounts::Opportunities::ActivitiesController#index`). This feature
adds two fields per array item; it does not change the endpoint's URL, verb, auth requirements
(`authorize(@opportunity, :show?)`, unchanged), or overall response shape.

## Before (current)

```jsonc
[
  {
    "id": 501,
    "event_type": "conversation_opened",
    "occurred_at": "2026-08-30T12:00:00Z",
    "actor": { "id": 3, "name": "Jane" },
    "metadata": {
      "conversation_id": 9042,
      "conversation_display_id": 128,
      "is_origin": true
    }
  },
  {
    "id": 502,
    "event_type": "opportunity_stage_changed",
    "occurred_at": "2026-08-30T12:05:00Z",
    "actor": { "id": 3, "name": "Jane" },
    "metadata": { "from_stage": "New", "to_stage": "Qualified" }
  }
]
```

## After (this feature)

Only entries whose `event_type` is one of `conversation_opened`, `conversation_transferred_in`,
`conversation_transferred_out`, `conversation_detached` gain the two new top-level fields.
All other event types are returned unchanged (FR-008).

```jsonc
[
  {
    "id": 501,
    "event_type": "conversation_opened",
    "occurred_at": "2026-08-30T12:00:00Z",
    "actor": { "id": 3, "name": "Jane" },
    "metadata": {
      "conversation_id": 9042,
      "conversation_display_id": 128,
      "is_origin": true
    },
    "conversation_status": "open",       // NEW — nullable string; null when unresolvable
    "conversation_viewable": true        // NEW — boolean; false when unresolvable or unauthorized
  },
  {
    "id": 502,
    "event_type": "opportunity_stage_changed",
    "occurred_at": "2026-08-30T12:05:00Z",
    "actor": { "id": 3, "name": "Jane" },
    "metadata": { "from_stage": "New", "to_stage": "Qualified" }
    // no conversation_status / conversation_viewable — not a conversation event
  }
]
```

## Consumer contract

- `OpportunityActivityLog.vue` renders a conversation-related entry as a clickable link with a
  status badge **iff** `conversation_viewable === true`; otherwise it renders exactly as it does
  today for non-conversation events — plain text, no link, no badge (FR-006a, FR-011).
- `conversation_status` is only meaningful (and only consulted) when `conversation_viewable` is
  `true`; its value when `false` is not part of the contract (may be `null` or omitted).
- Clicking a rendered link uses `metadata.conversation_display_id` (falling back to
  `metadata.conversation_id`) as the `conversationId` route param, exactly as already used for the
  active-conversation card click — no new identifier scheme.

## Backward compatibility

Additive only — existing consumers of this endpoint (if any beyond `OpportunityActivityLog.vue`)
continue to work unchanged; no field is removed or renamed.
