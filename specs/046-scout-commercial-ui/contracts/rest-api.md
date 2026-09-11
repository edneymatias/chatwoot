# API Contract: Scout Commercial Configuration

All routes are nested under `/api/v1/accounts/:account_id/`, follow this fork's existing
`PipelineStagesController`/`OpportunitiesController` conventions (Pundit policy + strong params +
`render json:`), and require the standard Chatwoot dashboard auth. Permission column reflects
`meta.permissions` on the matching frontend route (mirrors Captain's split, per `spec.md` FR-008/010).

## Scouts

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/scouts` | admin, agent | List, excludes `api_key_override` |
| POST | `/scouts` | admin, agent | Create (business fields); `provider`/`model_name`/`api_key_override` also settable here since they're required at creation, but not editable again outside Settings — see Open Question below |
| GET | `/scouts/:id` | admin, agent | Show, excludes `api_key_override` |
| PATCH/PUT | `/scouts/:id` | admin, agent | Update business fields (name, persona, funnel stages, quota, handover team, enabled) |
| DELETE | `/scouts/:id` | admin | Destroy |

## Scout ↔ Inbox association

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/scouts/:scout_id/scout_inboxes` | admin, agent | List attached inboxes |
| POST | `/scouts/:scout_id/scout_inboxes` | admin, agent | Body: `{ inbox_id }`. Returns `422` with a clear error (not a raw DB uniqueness error) if the inbox already belongs to another Scout |
| DELETE | `/scouts/:scout_id/scout_inboxes/:id` | admin, agent | Detach |

## Product catalog entries (mutate `Scout#product_catalog` jsonb)

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/scouts/:scout_id/product_catalog_items` | admin, agent | List |
| POST | `/scouts/:scout_id/product_catalog_items` | admin, agent | Body: `{ name, pricing, value_proposition }`; server assigns `id` |
| PATCH | `/scouts/:scout_id/product_catalog_items/:id` | admin, agent | `:id` is the entry's jsonb `id` |
| DELETE | `/scouts/:scout_id/product_catalog_items/:id` | admin, agent | |

## Knowledge sources

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/scouts/:scout_id/knowledge_sources` | admin, agent | List with `status` |
| POST | `/scouts/:scout_id/knowledge_sources` | admin, agent | Body varies by `kind`: `{ kind: "url", url }` / `{ kind: "document", document_file }` (multipart) / `{ kind: "faq", question, answer }`. Enqueues processing job for `url`/`document` |
| PATCH | `/scouts/:scout_id/knowledge_sources/:id` | admin, agent | Edit `faq` question/answer, or re-trigger processing (`{ reprocess: true }`) for `url`/`document` |
| DELETE | `/scouts/:scout_id/knowledge_sources/:id` | admin, agent | |

Rejecting an invalid upload (wrong content type, over 10MB) returns `422` with a field-level error
on `document_file`, per FR-004's clarified upload constraint.

## Funnel & qualification config

Folded into `PATCH /scouts/:id`: `default_pipeline_stage_id`, `qualified_stage_id`,
`unqualified_stage_id`, `handover_team_id`, and `required_field_ids: []` (drives
`ScoutRequiredField` sync, same `sync_required_attributes`-style diffing as
`PipelineStagesController`).

## Scout tools (account-scoped, not nested under a Scout)

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/scout_tools` | admin, agent | List, excludes `auth_headers` |
| POST | `/scout_tools` | admin, agent | Create |
| PATCH | `/scout_tools/:id` | admin, agent | Update, including `enabled` toggle |
| DELETE | `/scout_tools/:id` | admin, agent | Destroy |

## Playground

| Method | Path | Permission | Notes |
|---|---|---|---|
| POST | `/scouts/:scout_id/playground_messages` | admin, agent | Body: `{ message }`. Response: `{ reply, tool_calls: [{ tool_name, arguments, result, error }] }`. Synchronous — no message/conversation is persisted; see `research.md` §4 |

## LLM provider settings (admin-only, under Settings, not the primary menu)

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/scouts/:id/provider_settings` (or folded into an admin-only view of `GET /scouts/:id`) | admin only | Includes `provider`, `model_name`; `api_key_override` presence flag only, never the raw value |
| PATCH | `/scouts/:id/provider_settings` | admin only | Body: `{ provider, model_name, api_key_override }` |

**Decision** (resolved in `tasks.md` T031/T032): provider/model/API-key are managed through the
separate `ProviderSettingsController`/`provider_settings` route tabulated above, admin-only.
`ScoutsController`'s `PATCH /scouts/:id` (business fields, admin+agent) additionally excludes and
sanitizes any provider/API-key params a non-admin might submit, as defense in depth rather than as
the primary enforcement point. This satisfies FR-008/FR-010 without changing the frontend contract
(the Settings screen calls the distinct `provider_settings` API either way).
