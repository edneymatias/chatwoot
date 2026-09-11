# Research: Scout Human Handoff on Manual Intervention

## Context

The spec requires: when a human agent sends a public reply to a `pending` conversation whose
inbox has an enabled Scout, the conversation is synchronously reopened to `open` before any
already-queued Scout reply can be delivered. This document records the existing mechanisms this
feature must plug into, discovered by reading the current codebase (no unresolved
NEEDS CLARIFICATION items remained after `/speckit-clarify`).

## Decision 1: Reuse the existing `mark_pending_conversation_as_open_for_human_response` hook

**Decision**: Override `Message#mark_pending_conversation_as_open_for_human_response` from a new
prepended module, calling `super` first, then applying an equivalent rule for Scout.

**Rationale**: `app/models/message.rb` already runs this exact method from
`execute_after_create_commit_callbacks` (an `after_create_commit` callback) for every message:

```ruby
def mark_pending_conversation_as_open_for_human_response
  return unless captain_pending_conversation?
  return unless human_response?
  return if private?

  conversation.open!
end

def captain_pending_conversation?
  false
end
```

`human_response?` and `private?` already encode exactly the "public reply from a human agent"
rule the spec requires (sender is a `User`, not an automation rule/campaign echo, not a private
note). `enterprise/app/models/enterprise/message.rb` (`Enterprise::Message`) already prepends
this same method for Captain, redefining `captain_pending_conversation?` to check
`conversation.pending? && CaptainInbox.exists?(inbox_id: conversation.inbox_id)` and calling
`conversation.open!` synchronously inside the same `after_create_commit` callback — i.e. before
the message transaction that triggers any queued bot reply can be considered "sent". This is the
exact "already proven mechanism" referenced in the source phase document. Reusing the same hook
guarantees the Scout transition happens at the same synchronous point in the request lifecycle,
satisfying FR-002/FR-003/SC-004 without inventing a new callback or background job.

**Alternatives considered**:
- A new dedicated `after_create` callback in a Scout-specific concern, independent of
  `mark_pending_conversation_as_open_for_human_response` — rejected: would duplicate the
  `human_response?`/`private?` guard logic already correct and battle-tested, and would not
  compose with Captain's existing override through `super`.
- Handling this in the Scout reply-sending path (e.g., `ProcessMessageJob` re-checking status
  before send) instead of reopening the conversation — rejected: the spec's acceptance criteria
  explicitly require the conversation to reopen synchronously as the source of truth, matching
  the Captain precedent; it's simpler to prevent the send by changing the state the send job
  already depends on than to duplicate the human-response detection logic in the job.

## Decision 2: Determine "Scout enabled for this conversation" via `inbox.scout&.enabled?`

**Decision**: The new override's Scout-specific guard checks
`conversation.pending? && conversation.inbox&.scout&.enabled?`.

**Rationale**: `Scout` (`custom/app/models/scout.rb`, table `ichatr_scouts`) belongs to `Account`
and is linked to inboxes through `ScoutInbox` (`custom/app/models/scout_inbox.rb`, table
`ichatr_scout_inboxes`, unique index on `inbox_id` — one Scout per inbox). This association is
exposed on core `Inbox` via `custom/app/models/custom/concerns/inbox.rb`:
`has_one :scout_inbox ... ; has_one :scout, through: :scout_inbox`. There is no separate
inbox-level or account-level enable flag; the single gate is the boolean `enabled` column
(default `true`) on `Scout` itself. The existing call sites
(`custom/app/listeners/custom/scout_listener.rb`,
`custom/app/jobs/custom/scout/process_message_job.rb`) both gate identically:
`scout = inbox.scout; return unless scout&.enabled?` — so this override follows the same
established idiom rather than introducing a new helper method.

**Alternatives considered**:
- Adding a new `Inbox#scout_enabled?` helper method — rejected as unnecessary indirection for a
  single one-line check reused in only one more place; the existing call sites don't use such a
  helper either, so introducing one here would be an inconsistent, one-off abstraction (Principle
  II: smallest change, no speculative abstraction).

## Decision 3: Do not replicate Captain's extra side effects (activity message, `Current.user` reset, template-bootstrap guard)

**Decision**: The Scout branch of the override performs only the status transition
(`conversation.open!`), guarded by `conversation.pending?` and `inbox.scout&.enabled?`. It does
not create an activity/system message, does not null out `Current.user`/`Current.executed_by`,
and does not special-case template-bootstrap messages.

**Rationale**: The source phase document's technical approach section describes exactly one
outcome for the Scout branch — "conversa pending, inbox com Scout habilitado →
`conversation.open!`" — and explicitly scopes this phase down to "um único mecanismo de backend"
with "nenhuma mudança de frontend". Captain's richer implementation
(`Enterprise::Message#mark_pending_conversation_as_open_for_human_response`) adds a conversation
activity message (`captain.auto_opened_after_agent_reply`) and other guards that were built for
Captain's own maturity level; the spec for this phase, and its explicitly out-of-scope section
("qualquer elemento visual novo na conversa"), does not call for an equivalent for Scout yet — any
such indicator was deliberately deferred to Phase 15. Adding it speculatively here would violate
Principle II (smallest production-ready change) and could pre-empt Phase 15's own design.

**Alternatives considered**:
- Mirroring Captain's activity message 1:1 for consistency — rejected for this phase per the
  scope note above; can be added later without breaking this phase's contract if Phase 15 decides
  it's wanted.

## Decision 4: New file location and wiring

**Decision**: Add `custom/app/models/custom/message.rb` defining `module Custom::Message`, private
method `mark_pending_conversation_as_open_for_human_response` (calls `super`, then applies the
Scout rule) and a private predicate method for the Scout condition. No changes to any other file
are required to wire it in.

**Rationale**: `app/models/message.rb:460` already unconditionally calls
`Message.prepend_mod_with('Message')`, which (via `config/initializers/01_inject_enterprise_edition_module.rb`)
iterates `ChatwootApp.extensions` (`['enterprise', 'custom']` when both directories exist, which
they do in this repo) and prepends `Enterprise::Message` then `Custom::Message` in that order. Ruby
prepend semantics place the most-recently-prepended module first in the ancestor chain, so
`Custom::Message`'s override runs first when `mark_pending_conversation_as_open_for_human_response`
is invoked, and its `super` call delegates to `Enterprise::Message`'s override (which itself falls
back to core `Message`'s default `captain_pending_conversation? == false` no-op if Enterprise were
ever absent). This means: existing Captain behavior runs unchanged via `super`, then the Scout
rule is applied independently — if Captain already reopened the conversation, `conversation.pending?`
is now false and the Scout branch naturally no-ops, so no double-transition/duplicate work occurs.
This is a purely additive new file; it requires no edit to any existing core, enterprise, or
`config/application.rb` wiring, satisfying Constitution Principle I (Upstream Compatibility First)
and Principle V (Dual-Tree Awareness — Enterprise's own Captain behavior is left untouched and
composes via `super`, decision recorded here).

**Alternatives considered**:
- Editing `enterprise/app/models/enterprise/message.rb` directly to add the Scout check —
  rejected: Scout is a fork-specific, non-enterprise concept; editing enterprise/ code directly
  for a fork-only concern would violate Principle I/V and create merge risk against upstream's own
  Enterprise changes.

## Open questions

None — all technical unknowns were resolved above by reading the existing codebase; no
`NEEDS CLARIFICATION` markers remain.
