# API Contract: Opportunities & Pipeline Stages

Base path (mirrors existing account-scoped API): `/api/v1/accounts/:account_id/`

All endpoints require the existing account-scoped authentication already used by every other
`Api::V1::Accounts::*` controller, and require the `opportunities` feature flag to be active for
the account (FR-012) — requests against an account where the feature is not activated receive a
`403` (enforced by the shared `KanbanFeatureGuard` controller concern on both controllers).

## Pipeline Stages — `Api::V1::Accounts::PipelineStagesController`

Admin-only for every action (FR-007, FR-009).

| Method | Path | Action | Notes |
|---|---|---|---|
| GET | `/pipeline_stages` | `index` | Lazily seeds the two default stages ("Leads Recebidos", "Em Contato") on an account's first call if zero stages exist (FR-005). Idempotent — repeat calls never duplicate. |
| POST | `/pipeline_stages` | `create` | Body: `{ name }`. `position` is never accepted from the client — always server-assigned as `max(position) + 1`. |
| PUT/PATCH | `/pipeline_stages/:id` | `update` | Body: `{ name, position }` (both optional/partial). |
| DELETE | `/pipeline_stages/:id` | `destroy` | Rejected (error response) if any Opportunity still references this stage. |

## Opportunities — `Api::V1::Accounts::OpportunitiesController`

Access scoped per `OpportunityPolicy` (FR-006): administrators see/edit all; agents see/edit only
Opportunities where they are `assignee_id` or have inbox/team access to `origin_conversation`.

| Method | Path | Action | Notes |
|---|---|---|---|
| GET | `/opportunities` | `index` | Not paginated (matches the existing unpaginated convention of comparable account-scoped settings resources like Macros/Custom Attribute Definitions), scoped to what the requester is permitted to see. |
| GET | `/opportunities/:id` | `show` | `403` if not permitted per policy. |
| POST | `/opportunities` | `create` | Body: `{ contact_id, pipeline_stage_id, title, origin_conversation_id? , assignee_id? }`. `contact_id` and `pipeline_stage_id` required. `pipeline_stage_id` must belong to the same account or the request is rejected (FR-004). |
| PUT/PATCH | `/opportunities/:id` | `update` | Body: any of `{ title, pipeline_stage_id, assignee_id, status }`. Attempting to include/change `origin_conversation_id` is ignored/rejected — the persisted value never changes after creation (FR-008). |
| DELETE | `/opportunities/:id` | `destroy` | Per policy scoping. |

### Error cases (all endpoints)

- Missing required field → validation error response (standard Rails/ActiveRecord error shape
  already used across the app).
- Cross-account `pipeline_stage_id` on an Opportunity → validation error.
- Unauthorized access (policy `false`) → standard Pundit-driven `403`, consistent with the rest
  of the app's controllers.
