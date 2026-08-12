# Contract: `opportunity_updated` Realtime Event (extended payload)

Existing event, existing frontend consumer (`app/javascript/dashboard/helper/actionCable.js` →
`opportunities/updateOpportunity`). This feature does not change the event name or the frontend
contract — only ensures the resolution job triggers the same event, and that the payload includes
the new campaign fields so the card can update without a refetch.

**Channel**: `"account_#{account_id}"` (existing account-wide stream every logged-in agent already
subscribes to via `app/channels/room_channel.rb`).

**Trigger sources** (both dispatch through `Rails.configuration.dispatcher.dispatch`, per the
Phase 0 research decision — no direct `ActionCableBroadcastJob` calls):
1. `Opportunity#broadcast_opportunity_updated` (existing `after_commit`, unchanged trigger
   conditions — create/update).
2. The async resolution job, on completion (success or terminal failure) — fires the same event
   for the affected Opportunity so the card updates the moment resolution status changes, without
   requiring an unrelated Opportunity field to also change.

**Payload** (extends the existing shape with the new fields, all other fields unchanged):
```json
{
  "id": 123,
  "pipeline_stage_id": 4,
  "status": "open",
  "contact_id": 55,
  "assignee_id": 9,
  "updated_at": "2026-08-11T12:00:00Z",
  "account_id": 1,
  "origin_conversation_display_id": 987,
  "current_stage_entered_at": 1755000000,
  "campaign_source_id": "120246899522180701",
  "campaign_source_url": "https://fb.me/3nQ212CeX",
  "campaign_platform": "instagram",
  "campaign_name": "Consulta Gratuita — Agosto",
  "campaign_adset_name": "Interesse: Odontologia",
  "campaign_ad_name": "Criativo A — Carrossel",
  "campaign_resolution_status": "resolved"
}
```

- `campaign_*` fields are `null` (not omitted) when `campaign_resolution_status` is
  `not_applicable`, matching how the existing payload already includes always-present-but-nullable
  fields like `assignee_id`.
- Frontend handling requires no changes: `opportunities/updateOpportunity` already merges the
  full payload into store state by `id`; new keys pass through unchanged.
