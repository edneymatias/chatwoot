# Research: Scout Cross-Channel Activation

## Context

The spec requires two independent fixes so Scout works on any inbox channel, not just WhatsApp:
(1) the message listener that triggers Scout processing must stop gating on
`Channel::Whatsapp`, and (2) new conversations must start `pending` on any inbox with an enabled
Scout, not just ones where the legacy Dialogflow bot happens to be active. This document records
the existing mechanisms this feature must plug into, discovered by reading the current codebase
(no unresolved `NEEDS CLARIFICATION` items remained after `/speckit-clarify`).

## Decision 1: Remove the channel gate in `Custom::ScoutListener` directly

**Decision**: Delete the line `return unless inbox&.channel_type == 'Channel::Whatsapp'` from
`custom/app/listeners/custom/scout_listener.rb#message_created`. No replacement gate is added —
the existing guards (`message.incoming? && !message.private?`, `scout&.enabled?`,
`conversation&.pending?`) already fully determine eligibility once the channel check is gone.

**Rationale**: `custom/app/listeners/custom/scout_listener.rb:10` is confirmed to be the *only*
call site of `Custom::Scout::ProcessMessageJob.enqueue_debounced` in the codebase (per the source
phase document's investigation, re-confirmed by reading the file). The channel check is not load-
bearing for anything else — it does not gate any WhatsApp-specific data access, only the decision
of whether to enqueue the job at all. Every other condition in the method (incoming, public,
Scout enabled, conversation pending) is already channel-agnostic.

**Alternatives considered**:
- Replacing the WhatsApp allowlist with an explicit denylist or allowlist of "supported" channel
  types — rejected: the spec (FR-001, User Story 1 Acceptance Scenario 3) explicitly requires the
  fix to be channel-agnostic, and no product requirement restricts which channels can carry a
  Scout; introducing a new allowlist would just relocate the same arbitrary restriction the spec
  exists to remove (Constitution Principle II: no speculative scope narrowing).

## Decision 2: Make `Inbox#active_bot?` Scout-aware via `Custom::Inbox`, mirroring Captain's `Enterprise::Inbox`

**Decision**: Add `custom/app/models/custom/inbox.rb` defining `module Custom::Inbox` with:

```ruby
def active_bot?
  super || scout_active?
end

private

def scout_active?
  scout&.enabled? || false
end
```

**Rationale**: `app/models/conversation.rb:293-299` (`determine_conversation_status`) only calls
`set_active_bot_conversation` (which sets `status = :pending`) when `inbox.active_bot?` is true.
Core `Inbox#active_bot?` (`app/models/inbox.rb:180-183`) only checks `agent_bot_inbox&.active?` and
Dialogflow hooks — it has no knowledge of Scout. `enterprise/app/models/enterprise/inbox.rb:11-17`
already solves the identical problem for Captain with `active_bot? → super || captain_active?`,
composed onto core `Inbox` via the same `Inbox.prepend_mod_with('Inbox')` call already
unconditionally present at `app/models/inbox.rb:288`. Reusing this exact pattern for Scout — rather
than inventing a new one — keeps the fix minimal, consistent with an already-proven mechanism in
this codebase, and requires zero changes to `conversation.rb` or any other call site of
`active_bot?`.

The `scout` association (`has_one :scout, through: :scout_inbox`) is already defined on `Inbox` via
`custom/app/models/custom/concerns/inbox.rb` (`Custom::Concerns::Inbox`, included via
`Inbox.include_mod_with('Concerns::Inbox')` at `app/models/inbox.rb:290`), so `scout_active?` needs
no new association — it reuses the existing `inbox.scout&.enabled?` idiom already used identically
in `custom/app/listeners/custom/scout_listener.rb` and `custom/app/models/custom/message.rb`
(Phase 10).

**Alternatives considered**:
- Overriding `Conversation#determine_conversation_status` directly to add a Scout branch —
  rejected: `active_bot?` is the established, single point of truth for "does this inbox have an
  automated responder," already proven for Captain; branching in `Conversation` would duplicate
  that decision point and diverge from the existing pattern for no benefit.
- Building on top of the legacy `agent_bot_inbox`/Dialogflow mechanism (e.g., creating a synthetic
  `AgentBotInbox` row for Scout inboxes) — explicitly rejected by the spec/source document: Scout
  must not depend on or entangle with the legacy bot system; `super ||` composition keeps the two
  fully independent while preserving legacy behavior unchanged (FR-004).

## Decision 3: New file location and wiring (no edits to `app/models/inbox.rb` or `enterprise/`)

**Decision**: `custom/app/models/custom/inbox.rb` is a purely additive new file. No existing file
needs to change to wire it in.

**Rationale**: Identical reasoning and prepend order to Phase 10's `Custom::Message` (see
`specs/054-scout-human-handoff/research.md` Decision 4). `ChatwootApp.extensions`
(`lib/chatwoot_app.rb:36-44`) returns `%w[enterprise custom]` in this repo (both directories
present), and `Inbox.prepend_mod_with('Inbox')` (`config/initializers/01_inject_enterprise_edition_module.rb`)
prepends `Enterprise::Inbox` then `Custom::Inbox` in that order — Ruby prepend semantics place the
most-recently-prepended module first in the ancestor chain, so `Custom::Inbox#active_bot?` runs
first. Its `super` call delegates to `Enterprise::Inbox#active_bot?` (Captain's check), which
itself calls `super` to reach core `Inbox#active_bot?` (the legacy Dialogflow check). This means:
if either the legacy bot or Captain already marks the inbox as bot-active, `super` already returns
`true` and `scout_active?` is never even evaluated (short-circuiting `||`) — no double-work, no
behavior change for accounts not using Scout. This satisfies Constitution Principle I (Upstream
Compatibility First) and Principle V (Dual-Tree Awareness — Enterprise's own Captain behavior is
left untouched and composes via `super`, decision recorded here).

**Alternatives considered**:
- Editing `enterprise/app/models/enterprise/inbox.rb` directly to add the Scout check — rejected:
  Scout is a fork-specific, non-enterprise concept; editing enterprise/ code directly for a
  fork-only concern would violate Principle I/V and create merge risk against upstream's own
  Enterprise changes to that file.

## Decision 4: No backfill/migration for pre-existing conversations

**Decision**: This fix touches only (a) the incoming-message gate in the listener and (b) the
conversation-*creation* status decision. No rake task, migration, or background job is added to
retroactively flip already-existing `open` conversations on Scout-enabled inboxes to `pending`.

**Rationale**: Directly required by the spec's resolved clarification (FR-008): "forward-only —
only conversations created after the fix ships are affected." `Inbox#active_bot?` is only ever
consulted at conversation-creation time (`before_create :determine_conversation_status` in
`app/models/conversation.rb:132`), so simply shipping the `Custom::Inbox` override naturally
produces forward-only behavior with no extra code needed — there is no code path that re-evaluates
`active_bot?` against already-persisted conversations.

**Alternatives considered**:
- A one-off rake task or migration to backfill stuck `open` conversations — explicitly rejected by
  the spec clarification; would also require deciding which stale conversations are "safe" to
  retroactively hand to a bot (e.g., ones a human already replied to), a design question the spec
  deliberately scoped out.

## Open questions

None — all technical unknowns were resolved above by reading the existing codebase; no
`NEEDS CLARIFICATION` markers remain.
