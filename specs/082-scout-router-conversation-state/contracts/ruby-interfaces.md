# Contract: Ruby Interfaces

Internal library surface this phase exposes. No HTTP/API contract — purely internal Rails module
code; the contract is the public method signatures brief 03 (`TurnRunner`) and brief 04
(`open_playbook`) build against without needing to know this phase's internals. Extends brief 01's
`specs/081-scout-playbook-loader-validation/contracts/ruby-interfaces.md`, which is unchanged by
this phase (`Playbook`, `Playbook::Catalog`, `Playbook::Loader`, `Playbook::Validator`,
`Predicates::*`, `Capabilities::Catalog` all keep their brief-01 contracts verbatim).

## `Custom::ScoutV2::RoutingSnapshot`

```ruby
Custom::ScoutV2::RoutingSnapshot.new(
  conversation: nil, contact: nil, inbox: nil, scout: nil,
  opportunity: nil, opportunity_stage_role: :none,
  pending_fields: [], active_playbook: nil, transitions: 0,
  satisfied_capabilities: []
) -> RoutingSnapshot
```

- Every keyword is optional; omitted keys take the defaults shown (see data-model.md for the full
  field table). No database query, no network call, no LLM call inside `.new` (FR-003).
- Immutable once constructed. `pending_fields`/`satisfied_capabilities` are always `Array`, never
  `nil`, regardless of what was passed (frozen empty array when omitted or passed `nil`).
- This is the exact type every predicate's `ctx` parameter is called with (`Predicates::Base#call(ctx, arg)`,
  brief 01, unchanged) and the exact type `Router.call(ctx, catalog)`'s first argument is.

## `Custom::ScoutV2::RoutingSnapshot::Builder`

```ruby
Custom::ScoutV2::RoutingSnapshot::Builder.call(
  conversation:, catalog:, turn_transition_count: 0
) -> RoutingSnapshot
```

- The only component in this phase permitted to query the database (FR-002 restricts every other
  routing component — `Router`, the predicates — to reading only from an already-built
  `RoutingSnapshot`).
- `conversation` and `catalog` (a `Playbook::Catalog`) are required; `turn_transition_count`
  defaults to `0` and is never read from any persisted value (research.md D6) — callers driving a
  real turn attempt (brief 03) are responsible for passing the attempt's own in-progress count.
- Never raises for a conversation with no linked `Opportunity`, no `Scout`-linked `Inbox`, or no
  existing `ScoutConversationState` row — each resolves to the documented default (`nil`/`:none`/
  `[]`/`nil`, see data-model.md) rather than erroring; "no persisted routing state yet" is
  spec.md's own first-turn Edge Case, not a failure.
- Zero LLM calls, zero network calls (SC-001).

## `Custom::ScoutV2::Router`

```ruby
Custom::ScoutV2::Router.call(ctx, catalog) -> Router::Decision
```

- `ctx` is a `RoutingSnapshot` (any object responding to `#active_playbook` and whatever the
  evaluated playbooks' `when_state` predicates read from it also works, matching `Predicates::Base`'s
  existing duck-typed contract). `catalog` is a `Playbook::Catalog`.
- Pure function: no I/O, no database query, no LLM call, no mutation of either argument (FR-002,
  SC-001). Safe to call with an in-memory `RoutingSnapshot` and an in-memory `Playbook::Catalog`
  built entirely from `Playbook.new(...)` literals — no database connection required (US2's own
  Independent Test).
- Never itself calls any `ScoutConversationState` method — persisting the resulting decision (if
  it differs from `ctx.active_playbook`) is the caller's responsibility (data-model.md, Router
  section).
- Idempotent: calling it twice with the same `ctx`/`catalog` returns an equal `Decision` both
  times (no hidden state).

### `Custom::ScoutV2::Router::Decision`

```ruby
decision.playbook    # -> Custom::ScoutV2::Playbook | nil
decision.confidence   # -> 1.0 | nil   (1.0 iff playbook is present)
```

## `ScoutConversationState` (flat, unnamespaced — `custom/app/models/scout_conversation_state.rb`)

```ruby
ScoutConversationState.for_conversation(conversation) -> ScoutConversationState
```

- `find_or_initialize_by(conversation_id: conversation.id)` — returns a persisted record if one
  exists for this conversation, otherwise a new, **unsaved** instance with `account_id` prefilled
  from `conversation.account_id` and every other attribute at its column default (`active_playbook:
  nil`, `transition_count: 0`, etc.). Never performs a write (research.md D9).

```ruby
state.record_state_activation!(playbook_name) -> state
```

- Persists a state-based activation (used identically for a fresh activation, FR-008, and a
  priority-based interruption, FR-009 — both are reason `:state`, spec clarification #1).
  `playbook_name` is a `String` (a `Playbook#name`). Sets `active_playbook`, `activated_at =
  Time.current`, `activation_reason = :state`. Never modifies `last_exit`, `transition_count`, or
  `handoff_limit_reached_at`. Raises `ActiveRecord::RecordInvalid` on validation failure, same as
  any other `update!`.

```ruby
state.record_transition!(target_playbook_name, turn_transition_count:) -> true | false
```

- `target_playbook_name` (`String`) is the playbook a declared "transition" ending hands off to.
  `turn_transition_count:` (`Integer`, required) is the number of transition hand-offs already
  performed **this turn attempt** — supplied by the caller, never read from this record's own
  `transition_count` (FR-021, research.md D6).
- If `turn_transition_count >= 2`: refuses the hand-off — sets only `handoff_limit_reached_at =
  Time.current` (overwriting any prior value, never accumulating), changes nothing else, returns
  `false` (FR-017/FR-018).
- Otherwise: performs the hand-off — sets `active_playbook = target_playbook_name`, `activated_at =
  Time.current`, `activation_reason = :transition`, increments the persisted cumulative
  `transition_count` by exactly `1` (FR-021), returns `true`. Never modifies `last_exit` (FR-020).

```ruby
state.record_terminal_exit!(exit_name) -> state
```

- `exit_name` (`String`) is the name of the declared "terminal" ending reached. Sets
  `active_playbook = nil`, `activated_at = nil`, `activation_reason = nil`, `last_exit = exit_name`
  — replacing whatever `last_exit` held before (FR-019). A subsequent `record_state_activation!` or
  `record_transition!` reactivating any playbook (including the one that just exited) never reads
  or clears `last_exit` — only this method ever writes it (FR-020, spec clarification #3).

## Boot wiring (none — this phase adds no new boot-time validation)

Unlike brief 01, this phase introduces no new `Rails.application.config.after_initialize` hook.
`ScoutConversationState` is an ordinary AR model (schema-validated by the migration itself, plus
standard Rails model validations); `Router`/`RoutingSnapshot`/`Builder` have no catalog of their
own to validate at boot — they consume brief 01's already-boot-validated `Playbook::Catalog`.
