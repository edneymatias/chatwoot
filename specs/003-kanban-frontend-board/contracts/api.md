# Contract: REST API (client of Phase 1/2 endpoints, with 2 required additive changes)

Base path: `/api/v1/accounts/:account_id/` (existing `Api::V1::Accounts::BaseController` convention).

## Pipeline Stages — `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`

| Method | Path | Params | Response | Notes |
|---|---|---|---|---|
| GET | `/pipeline_stages` | — | `200` array of `{ id, name, position, account_id }`, ordered by `position` (model `default_scope`) | Seeds two default stages on first call if account has none (`seed_defaults_for!`) — existing behavior, unchanged |
| POST | `/pipeline_stages` | `pipeline_stage: { name }` | `200` created stage \| `422 { error }` | Unchanged |
| PATCH/PUT | `/pipeline_stages/:id` | `pipeline_stage: { name, position }` | `200` updated stage \| `422 { error }` | **REQUIRES BACKEND CHANGE**: `position` is not currently permitted — add `:position` to `pipeline_stage_params` to support FR-010 drag-to-reorder |
| DELETE | `/pipeline_stages/:id` | — | `200` \| `422 { error }` | Blocked automatically when the stage has opportunities via `dependent: :restrict_with_error` (already satisfies FR-010's block-with-message requirement — no change needed); error message surfaces via the existing `{ error: @pipeline_stage.errors.full_messages.join(', ') }` shape |

## Opportunities — `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`

| Method | Path | Params | Response | Notes |
|---|---|---|---|---|
| GET | `/opportunities` | `pipeline_stage_id` (required for board use), `page` | `200` array of opportunities (each includes `contact`, `pipeline_stage`, `assignee` per existing `.includes`) | **REQUIRES BACKEND CHANGE**: index currently returns the full unfiltered/unpaginated `policy_scope` — add `where(pipeline_stage_id: params[:pipeline_stage_id])` when present and standard Kaminari-style `page(params[:page])` to support FR-002/FR-004 per-column infinite scroll without cross-stage scans |
| GET | `/opportunities/:id` | — | `200` single opportunity | Unchanged; used by the detail view (FR-007) |
| POST | `/opportunities` | `opportunity: { title, contact_id, pipeline_stage_id, status, origin_conversation_id, assignee_id }` | `200` created opportunity \| `422 { error }` | Unchanged; used by manual-creation flow (FR-008/FR-009). `title`/`contact_id`/`pipeline_stage_id` required by frontend form validation; `origin_conversation_id` optional, omitted when not launched from a conversation |
| PATCH/PUT | `/opportunities/:id` | `opportunity: { title, contact_id, pipeline_stage_id, status, assignee_id }` | `200` updated opportunity \| `422 { error }` | Reused for two distinct frontend operations: (1) drag-and-drop move — send only `pipeline_stage_id`; (2) status change (Mark as Won/Lost/Reopen) — send only `status`. Both are the same endpoint/shape; the frontend action determines which key(s) to send per FR-005 / FR-007a |
| DELETE | `/opportunities/:id` | — | `200` \| `422 { error }` | Not used by any user story in this phase (no delete-a-card flow specified); client included for completeness of the API wrapper only |

## Automation Rules (Phase 2, read-only in this phase)

No new endpoint. This phase only reads the existing `automation_rules` action-type registry client-side (`AUTOMATION_ACTION_TYPES` in `constants.js`) plus `GET /pipeline_stages` (above) to populate the `create_opportunity` action's stage dropdown (FR-013). The `create_opportunity` action's own params (`pipeline_stage_id`, optional `title_template`) are persisted as part of the existing `automation_rules` create/update payload's `actions` array — no contract change to that endpoint from this phase.
