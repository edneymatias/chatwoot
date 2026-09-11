# Contract: `Api::V1::Accounts::ScoutsController` — new/changed fields

Existing endpoints, unchanged shape otherwise (`GET/POST/PATCH /api/v1/accounts/:account_id/scouts[/:id]`).

## Request — permitted params (additive)

`scout_params` gains two new permitted keys, alongside the existing ones:

| Field | Type | Constraints |
|---|---|---|
| `rescue_stage_id` | integer / string (Rails coerces) | Must reference a `PipelineStage` belonging to the same account, or be blank/null. No FK-ownership validation beyond what the existing `qualified_stage_id`/`unqualified_stage_id` pattern already does at the DB level (`on_delete: :nullify`; no explicit account-scoping validation exists for those either — cross-account misuse is a pre-existing risk class, not introduced here). |
| `follow_up_delays_hours` | array of integers | Must be exactly 3 strictly ascending, unique, positive integers (validated on the model — see `data-model.md`). Submitting an array of the wrong length, or an unordered/non-positive/duplicate one, returns `422` with `@scout.errors.full_messages`. |

## Response — `Scout#as_json` (additive)

No explicit custom `as_json` override on `Scout` today (default ActiveRecord serialization via
`include_associations`), so `rescue_stage_id` and `follow_up_delays_hours` appear automatically as
plain attributes once added to the schema — no controller/serializer change needed beyond the
permitted-params update above.

---

# Contract: `Opportunity#as_json` — new field

| Field | Type | Semantics |
|---|---|---|
| `scout_engaged` | boolean | `true` when the opportunity's `active_conversation` is currently `pending` and that conversation's inbox has an `enabled` Scout attached (see `data-model.md`). Consumed by `KanbanCard.vue` to render/hide the "Scout" badge. Always present (never `null`) — derived, defaults to `false`. |

No breaking change to any existing field; this is a pure addition to the JSON payload already
returned by every endpoint that serializes an `Opportunity` (board listing, single-opportunity
fetch, websocket broadcast payloads that reuse `as_json`).
