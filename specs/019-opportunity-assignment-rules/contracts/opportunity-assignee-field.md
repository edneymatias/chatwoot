# Contract: `assignee_id` on the Opportunity create/update API

**Endpoint**: `Api::V1::Accounts::OpportunitiesController#create` and `#update` (existing endpoints, no route changes)
**Status**: `assignee_id` is already a permitted param on both actions today — this feature is the first *caller* to actually populate it from the UI. No controller/params change is required.

## Request

`POST /api/v1/accounts/:account_id/opportunities` and `PATCH /api/v1/accounts/:account_id/opportunities/:id`

```jsonc
{
  "opportunity": {
    "title": "...",
    "contact_id": 1,
    "pipeline_stage_id": 2,
    "assignee_id": 5      // or null / omitted for "no owner"
  }
}
```

`assignee_id` accepts any `User` id on the account — no server-side restriction on who can be set as assignee (spec FR-004). No new validation is introduced for this field.

## Response

`Opportunity#as_json` already includes a nested `assignee` object when present:

```jsonc
{
  "id": 10,
  "assignee_id": 5,
  "assignee": { "id": 5, "name": "Jane Agent", "avatar_url": "..." }
}
```

or `"assignee": null` when unassigned. No response shape change.

## Frontend payload-building contract (must be honored by callers)

- **`OpportunityBackfillModal.vue` → `opportunities/updateOpportunity`**: dispatch payload's `assignee_id` is spread straight through to the API by the existing `updateOpportunity` action (`opportunitiesAPI.update(id, data)`) — no store-layer change needed.
- **`OpportunityCreateModal.vue` → `opportunities/create`**: the `create` action currently whitelists which destructured fields reach the API payload and does **not** currently include an assignee. It MUST be extended to accept `assigneeId` and forward it as `assignee_id` in the `opportunitiesAPI.create(...)` call, or the modal's new field will have no effect.
