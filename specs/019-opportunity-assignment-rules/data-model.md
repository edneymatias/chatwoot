# Phase 1 Data Model: Opportunity Assignment Rules

No schema migration is required — every field this feature needs already exists. This document records the entities/fields this feature reads and writes, not new ones.

## Opportunity (`custom/app/models/opportunity.rb`, table `matias_opportunities`)

| Field | Type | Status | Notes |
|---|---|---|---|
| `assignee_id` | integer, FK → `users.id` | Already exists | `belongs_to :assignee, class_name: 'User', optional: true`. This feature is the first to ever *write* it (via automation or manual modals) — it has existed unused until now. |
| `pipeline_stage_id` | integer, FK | Already exists | This feature fixes the automation path that sets it on create; no field-level change. |

No new validations are introduced: `assignee_id` is `optional: true` today (an opportunity may have no owner), consistent with FR-002/FR-007 (unassigned is a valid, expected state, not an error).

### Serialization

`Opportunity#as_json` already includes a nested `assignee` object (`{ id, name, avatar_url }` or `nil`) — no change needed; the frontend already has a shape to render once the field is populated.

## Automation Rule Action Config: `create_opportunity`

Not a persisted entity of its own — it's the `action_params` JSON blob stored per-action inside an `AutomationRule`'s `actions` array. This feature changes its shape:

| Version | Shape | Status |
|---|---|---|
| Before (broken) | `{ id, name }` (from the generic `search_select` input; `id` intended as stage id but never read by the backend under that key) | Existing rules keep this shape until reconfigured — not migrated (FR-009) |
| After | `{ pipeline_stage_id: <id>, assignee_id: <user id \| 'same_as_conversation' \| nil> }` | New shape produced by `AutomationActionCreateOpportunityInput.vue`, read by `Custom::AutomationRules::ActionService#create_opportunity` |

**Assignee resolution values**:
- `'same_as_conversation'` — sentinel string; resolved at execution time to `@conversation.assignee_id` (may be `nil`).
- Any other non-blank value — a `User` id, used directly as `assignee_id`.
- Blank/absent — opportunity created with `assignee_id: nil`.

No new backend entity/table is needed to represent this — it stays as opaque JSON on the existing `AutomationRule` record, exactly like every other action's `action_params`.

## Relationships touched

```text
AutomationRule --(has many, JSON actions[])--> action_params { pipeline_stage_id, assignee_id }
                                                        │
                                                        ▼ (on rule execution)
Opportunity --belongs_to--> assignee (User, optional)
Opportunity --belongs_to--> pipeline_stage (PipelineStage, required)
Conversation --belongs_to--> assignee (User, optional)   # read-only source for "same as conversation"
```

No new relationships are created; this feature is entirely about *populating* an existing relationship (`Opportunity.assignee`) through two new write paths (automation, manual modals).
