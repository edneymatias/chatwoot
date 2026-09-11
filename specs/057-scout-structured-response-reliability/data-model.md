# Phase 1 Data Model: Scout Structured Response Reliability

No new database tables, columns, or ActiveRecord models — matches spec Assumptions and
Constitution Principle IV (no migrations). The one "Key Entity" named in the spec is a plain Ruby
class, not a persisted record.

## Structured Turn Response

Not a Chatwoot-persisted record. Represented in code as `Custom::Scout::ResponseSchema`, a
`RubyLLM::Schema` subclass declaring the shape the model's final turn response must conform to:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `reasoning` | string | yes | Internal-only justification for how the model arrived at its answer. Logged (`Rails.logger.info`), never shown to the customer — unchanged from today (spec FR-006). |
| `response` | string | yes | The customer-facing reply text. The only field ever passed to `dispatch_outgoing_reply`. |

This mirrors `Captain::ResponseSchema` field-for-field (same two fields, same purpose), not by
sharing code but by matching the existing structure Scout's own prompt already instructs the model
to return (`Custom::Scout::SystemPromptsService`'s `{"reasoning": ..., "response": ...}` contract,
established in the prior system-prompt-guardrails phase) — this feature makes that existing
contract *enforced*, not different.

## Runtime shape after this change

`AgentRunner#execute_chat`'s return value (`RubyLLM::Message#content`) can now be one of two
shapes, both already anticipated by `parse_structured_response`'s updated branch (see
`research.md` §3):

- **`Hash`** (string keys, e.g. `{"reasoning" => "...", "response" => "..."}`) — when the
  configured provider/model honors the schema and `RubyLLM` successfully auto-parses it.
- **`String`** — the existing fenced-JSON-or-plain-text shape, used as a fallback when the
  provider/model doesn't honor the schema, or schema-mode parsing itself failed.

## Validation rules

- `reasoning` and `response` are both required in the schema (`strict` mode, matching
  `Captain::ResponseSchema`'s default) — a response missing either field fails schema validation on
  providers that enforce it at the API level, which (per FR-003) is treated identically to any
  other unparseable response: fail closed, existing fail-safe handoff.
- No new validation is added to `parse_structured_response` beyond the existing check that
  `response` is present and non-blank — this is unchanged from today, now just reachable via two
  possible input shapes instead of one.

## State transitions

None — this feature does not touch conversation/message state transitions. It only changes how
reliably `AgentRunner` obtains a response it can act on before those existing transitions
(dispatch reply vs. fail-safe handoff) run, unchanged, per FR-003.
