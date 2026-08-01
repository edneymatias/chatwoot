# Data Model: Card Info Enrichment & Lane Ordering

No database schema changes. This feature only changes the JSON representation
produced by `Opportunity#as_json` and the ordering of the `#index` query result.

## Entity: Opportunity (`custom/app/models/opportunity.rb`)

Existing columns are unchanged. `#as_json` is extended to merge additional
derived keys on top of the model's own columns.

### `as_json` shape — before

```json
{
  "id": 1,
  "contact_id": 10,
  "pipeline_stage_id": 2,
  "assignee_id": 5,
  "created_at": "2026-07-31T12:00:00.000Z",
  "origin_conversation_display_id": 42,
  "...": "other own columns"
}
```

### `as_json` shape — after

```json
{
  "id": 1,
  "contact_id": 10,
  "pipeline_stage_id": 2,
  "assignee_id": 5,
  "created_at": 1785499200,
  "origin_conversation_display_id": 42,
  "contact": {
    "id": 10,
    "name": "Jane Doe",
    "email": "jane@example.com",
    "avatar_url": "https://.../avatar.png"
  },
  "assignee": {
    "id": 5,
    "name": "Agent Smith",
    "avatar_url": ""
  },
  "...": "other own columns unchanged"
}
```

`contact` is `nil` if `contact_id` is absent; `assignee` is `nil` if unassigned.

### Field provenance

| Field | Source |
|-------|--------|
| `created_at` (epoch seconds) | `Opportunity#created_at.to_i` — overrides default ISO8601 string |
| `contact.id` / `contact.name` / `contact.email` | `Opportunity#contact` (existing `belongs_to`) |
| `contact.avatar_url` | `Contact#avatar_url` via `Avatarable` concern |
| `assignee.id` / `assignee.name` | `Opportunity#assignee` (existing `belongs_to`) |
| `assignee.avatar_url` | `User#avatar_url` via `Avatarable` concern |

## Ordering contract

`OpportunitiesController#index` returns opportunities ordered by
`created_at: :desc` (newest first). This ordering is stable across page reloads
and independent of any client-side drag state, since a reload always re-issues
the `#index` request against the ordered query. No pagination or cursor changes
are introduced.
