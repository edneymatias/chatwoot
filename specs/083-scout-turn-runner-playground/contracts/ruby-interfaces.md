# Contracts: Scout V2 Turn Runner and Qualification Playbook (Playground)

This feature exposes no new REST endpoint and no new request/response shape — both dispatch
points keep their existing HTTP contracts unchanged (data-model.md "Dispatch Points"). The actual
new interfaces other code depends on are Ruby service contracts.

## `Custom::ScoutV2::TurnRunner`

```
Custom::ScoutV2::TurnRunner.new(
  scout:, conversation:, message:, message_history: nil
).perform
# => { reply: String, tool_calls: Array<{ tool_name: String, arguments: Hash, result: String }> }
```

**Preconditions**: `scout` and `conversation` are persisted records; `conversation.inbox`,
`conversation.contact` resolvable (real or sandbox, data-model.md). `message` is the current
turn's user-facing text.

**Postconditions**:
- At most one top-level LLM call is made per invocation (FR-011, SC-001) — zero if the infra gate
  fails (research.md D10).
- `ScoutConversationState` for `conversation` reflects the router's decision for this turn before
  `#perform` returns (research.md D11) — this is what "persisted before the reply is sent" means
  operationally: the write happens inside `#perform`, strictly before the caller dispatches the
  returned reply.
- The Langfuse trace for the call carries `playbook`/`activation_reason`/`unsatisfied_flags`
  metadata (research.md D14, FR-014).
- Never raises for infra-gate failure (handled internally, research.md D10); may raise for
  genuinely unexpected errors, same as `AgentRunner`'s top-level `rescue StandardError` in its
  caller (`ProcessMessageJob`) — `TurnRunner` itself does not swallow unexpected exceptions, matching
  `AgentRunner`'s own boundary (the `rescue` lives in the dispatch point, not the runner).

**Consumers**: `Custom::Scout::ProcessMessageJob` (inbox surface), `Api::V1::Accounts::Scouts::
PlaygroundMessagesController` (playground surface, via `PlaygroundConversation.for` first).

## `Custom::ScoutV2::PlaygroundConversation`

```
Custom::ScoutV2::PlaygroundConversation.for(scout) # => Conversation
```

**Preconditions**: `scout` persisted.

**Postconditions**: Returns the same `Conversation` on every call for the same `scout` (idempotent
find-or-create, data-model.md). Never returns a conversation belonging to a different scout's
sandbox. Side effects (first call only): creates one `Contact`, one `Channel::Api`, one `Inbox`,
one `ScoutInbox`, one `ContactInbox`, one `Conversation` — all real, persisted, account-scoped
records (research.md D1/D2).

**Consumers**: `Api::V1::Accounts::Scouts::PlaygroundMessagesController#create`, v2 branch only.

## HTTP surfaces (unchanged contracts, confirmed no diff needed)

### `POST /api/v1/accounts/:account_id/scouts/:scout_id/playground_messages`

Request: unchanged (`message: String`, `message_history: Array<{role, content}>`, `permitted_message_history`
already accepts exactly what the frontend already sends — no new param).

Response: unchanged shape (`{ reply: String, tool_calls: Array<Hash>, error: String? }`) —
`ScoutPlaygroundChat.vue:53-55,150-157` already reads exactly this shape; verified no Vue file
needs to change.

### Inbox message intake (`Custom::ScoutListener` → `ProcessMessageJob` → dispatch)

Unchanged trigger conditions and unchanged debounce contract (`AGENTS.md`/design.md §4.11 —
"porteiros... são os mesmos nas duas engines"). Only the final dispatch call inside
`process_debounce` branches on `scout_v2`.

## Feature flag contract

`config/features.yml` entry `scout_v2` (`column: feature_flags_ext_1`, `enabled: false`),
read via `account.feature_enabled?('scout_v2')` (upstream `Featurable`). No controller/serializer
exposes it as a per-request field — it is read directly from `Current.account`/`scout.account` at
each dispatch point, matching the `captain_integration_v2` precedent exactly (no new API surface).
