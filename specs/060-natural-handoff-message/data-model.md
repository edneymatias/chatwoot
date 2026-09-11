# Data Model: Natural Handoff Message

No database schema changes. This feature only changes how an in-memory message string is sourced
and passed between existing Ruby objects during a single conversation turn — there are no new
persisted tables, columns, or migrations. The entities below (from the spec's Key Entities section)
map onto existing runtime objects and method contracts.

## Entities

### Handoff message

The single string the customer sees when a conversation is transferred to a human.

| Attribute | Type | Notes |
|---|---|---|
| `content` | String | Either the assistant's parsed turn text, or the fixed `I18n.t('conversations.scout.handoff')` sentence — never both, never blank |
| `source` | enum (conceptual, not persisted) | `:model_text` \| `:fixed_fallback` — determines which of the two content origins was used |

**Validation rules** (FR-002, FR-003):
- Exactly one message is ever sent per handoff — `content` is never a concatenation of model text
  and the fixed sentence.
- `source` resolves to `:fixed_fallback` whenever the candidate model text is blank or the turn's
  response could not be parsed into a `response` field (mirrors the existing
  `parse_structured_response` blank-check already used elsewhere in `AgentRunner`).

**Carrier**: `Custom::Scout::HandoffService#perform` gains an optional `message:` keyword param.
`message.presence || I18n.t(...)` is the resolution rule (FR-003) — no new class/model is
introduced for this entity; it stays a plain string parameter.

### Conversation turn

One cycle of the assistant producing a response, which may end in a decision to hand off.

| Attribute | Type | Notes |
|---|---|---|
| `parsed_response` | String \| nil | The `response` field already extracted by `AgentRunner#parse_structured_response` from the model's structured output |
| `ends_in_handoff` | Boolean (conceptual) | True when any tool used in this turn reports `handoff_needed` truthy |

**State transition** (FR-001, FR-007): A turn's outcome is decided the same way as today — no new
states are introduced. What changes is *when* parsing happens relative to the handoff check:

- **Today**: `handover_to_human` path returns immediately on tool execution (`handoff_executed`),
  before any parsing occurs; the qualification path parses but then discards `parsed_response` in
  favor of the fixed sentence.
- **After this feature**: parsing always happens first (`process_response` unconditionally calls
  `parse_structured_response`), then a single generalized check
  (`tools.find { |t| t.respond_to?(:handoff_needed) && t.handoff_needed }`) determines whether this
  turn ends in handoff, regardless of which tool set the flag. `parsed_response` is what gets
  carried into the Handoff message's `content` when available.

**Carrier**: `Custom::Scout::AgentRunner` — no new class introduced; existing private methods are
reordered/consolidated (see `plan.md` Summary).

### Opportunity qualification event

The automatic, event-driven trigger that fires when an opportunity reaches the qualified pipeline
stage during a conversation, independent of the assistant's own turn-level decision.

| Attribute | Type | Notes |
|---|---|---|
| `handoff_needed` | Boolean | Already exposed by `OpportunityStageTransitionService`, and duck-typed onto `ManageOpportunity`/`MoveOpportunityStage` tool instances — unchanged by this feature |

**Relationship**: This event is one of (now) three objects that can expose `handoff_needed` truthy
in a given turn — `ManageOpportunity`, `MoveOpportunityStage` (both already existing), and now
`HandoverToHuman` (changed by this feature from executing synchronously to flagging
`handoff_needed` the same way). `AgentRunner` treats all three uniformly via the shared duck-type;
no entity relationship or trigger-priority logic is added, since the message content is a
turn-level property (`parsed_response`), not a per-tool property — so it does not matter which tool
in the list is matched first when more than one could technically be true in the same turn.

## No persisted entities

This feature does not add, remove, or alter any ActiveRecord model, migration, or database column.
All objects above are transient Ruby objects scoped to a single `AgentRunner#perform` invocation.
