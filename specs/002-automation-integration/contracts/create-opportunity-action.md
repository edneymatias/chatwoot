# Contract: `create_opportunity` Automation Rule Action

This is not an HTTP endpoint — it is a dynamic-dispatch action contract consumed by
`AutomationRules::ActionService#perform`, matching the exact pattern already used by every other
automation action (`add_label`, `assign_agent`, `send_message`, etc.).

## Registration

- `AutomationRule#actions_attributes` MUST include `"create_opportunity"` in its returned array
  (verifiable via `AutomationRule.new.actions_attributes.include?('create_opportunity')`).
- Any `AutomationRule#actions` entry with `action_name: "create_opportunity"` MUST pass the
  existing `json_actions_format` validation (no new validation logic required beyond the existing
  generic name-membership check).

## Dispatch contract

- `AutomationRules::ActionService` MUST respond to `create_opportunity(params)` as a private
  instance method, callable via `send(:create_opportunity, action_params)` exactly as every other
  action is dispatched inside `#perform`.
- `params` is the `action_params` array/hash from the rule's `actions` entry, indifferent-access
  wrapped by the caller (matching existing dispatch behavior).

## Input

| Key | Required | Type | Validation |
|---|---|---|---|
| `pipeline_stage_id` | Yes | Integer | Must reference a `PipelineStage` belonging to the same account as `@conversation.account`; a cross-account or nonexistent id MUST cause Opportunity creation to fail (propagated as `ActiveRecord::RecordInvalid`/`ActiveRecord::RecordNotFound`, caught by the existing per-action rescue in `#perform`). |
| `title_template` | No | String | If blank, defaults to `"#{@conversation.contact.name} - #{Date.current}"`. |

## Output / side effects

- On first execution for a given `@conversation`: creates exactly one `Opportunity` with
  `account: @conversation.account`, `contact: @conversation.contact`,
  `pipeline_stage_id: params[:pipeline_stage_id]`, `origin_conversation: @conversation`,
  `status: :open`, and the resolved title.
- On any subsequent execution for the same `@conversation` (an `Opportunity` with that
  `origin_conversation_id` already exists): no new `Opportunity` is created; no error is raised;
  the method returns without side effects.
- On any other failure (e.g. invalid `contact`, invalid `pipeline_stage_id`): the exception
  propagates out of `create_opportunity` uncaught, to be caught by the existing
  `rescue StandardError => e; ChatwootExceptionTracker.new(e, account: @account).capture_exception`
  wrapper in `AutomationRules::ActionService#perform` — no rescue block inside
  `create_opportunity` itself.

## I18n contract

- `app/javascript/dashboard/i18n/locale/en/automation.json` → `ACTIONS.CREATE_OPPORTUNITY` MUST
  resolve to a human-readable label (e.g. `"Create Opportunity"`), consumed by Phase 3's dropdown
  rendering — not yet rendered in this phase, but the key MUST exist so Phase 3 requires no
  further backend change.

## Non-goals (out of scope this phase)

- No new HTTP endpoint, controller action, or route.
- No Vue-side parameter picker or dropdown rendering (Phase 3).
- No new `AutomationRule` trigger event or condition type.
