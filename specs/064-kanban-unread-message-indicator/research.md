# Phase 0 Research: Kanban Unread Message Indicator (Post-Handoff Only)

No `[NEEDS CLARIFICATION]` markers remain in the spec or in this plan's Technical Context, so this
phase consolidates the design decisions already investigated (in the source planning doc this
feature amends) and re-validates each one against the current state of the codebase rather than
opening new unknowns.

## Decision: Gate the indicator on `!scout_engaged? && has_unread_messages_present?`

**Rationale**: The spec's addendum requires the dot to be hidden while Scout still owns the
conversation. `Opportunity#scout_engaged?` (`custom/app/models/opportunity.rb:47`) already exists,
is already broadcast in real time, and is the exact signal that drives the existing "Scout" badge
— reusing it keeps the two indicators consistent by construction (a card can never show both a
"Scout" badge and an unread dot backed by contradictory engagement signals) and needs no new
concept.

**Alternatives considered**:
- A separate "handoff happened" flag/timestamp on `Opportunity` or `Conversation`. Rejected: no
  such state exists today, and introducing one would duplicate what `scout_engaged?` already
  derives correctly and consistently, violating Constitution Principle II (smallest
  production-ready change).
- Checking only `active_conversation`'s own Scout status, ignoring other linked conversations.
  Rejected in favor of reusing `scout_engaged?` unmodified: `scout_engaged?` already evaluates
  across all linked `conversations` (not just `active_conversation`), and diverging from it would
  make the "Scout" badge and the unread dot answer "is Scout involved?" inconsistently on the same
  card for multi-conversation opportunities.

## Decision: Reuse and generalize the Phase 22 broadcast mechanism (rename, don't duplicate)

**Rationale**: Phase 22 already solved "how does a change that doesn't touch the `Opportunity`
record itself get pushed to the Kanban board in real time" via
`Opportunity#broadcast_scout_badge_refresh` and
`Custom::Concerns::Conversation#refresh_linked_opportunities_scout_badge`. Both methods already
broadcast the full `as_json` payload, so adding a new derived field needs no payload change — only
more triggers that call the same (renamed) methods. Renaming to
`broadcast_kanban_badges_refresh` / `refresh_linked_opportunities_kanban_badges` is a one-time,
mechanical rename that keeps a single broadcast pipeline instead of two parallel ones.

**Alternatives considered**:
- A second, parallel broadcast method/job dedicated to the unread indicator. Rejected: would
  duplicate the exact same `ActionCableBroadcastJob.perform_later(["account_#{account_id}"],
  'opportunity_updated', as_json)` call for no behavioral difference, doubling the broadcast volume
  on every relevant event and duplicating maintenance surface.

## Decision: Two additional `after_commit` triggers, not one

**Rationale**: `has_unread_messages?` can flip on two events, neither of which the existing
`saved_change_to_status?` guard observes:
1. A new incoming message arrives — no column on `Conversation` itself changes, only its
   `messages` association. Verified: `app/models/message.rb` already calls
   `Message.include_mod_with('Concerns::Message')` (line 464), but no
   `custom/app/models/custom/concerns/message.rb` exists yet — this fork has never used that
   inclusion point before, so this is the first file to fill it.
2. The agent reads the conversation — updates `Conversation#agent_last_seen_at`, a different column
   than `status`. Verified current guard: `after_commit :refresh_linked_opportunities_scout_badge,
   on: :update, if: :saved_change_to_status?` (`custom/app/models/custom/concerns/conversation.rb`)
   — confirmed it does not already cover `agent_last_seen_at`.

**Alternatives considered**:
- A single generic `after_commit` on `Conversation` covering every attribute change. Rejected:
  would broadcast (and enqueue an ActionCable job) on every unrelated column change, an
  unnecessary broadcast-volume regression for no additional correctness.

## Decision: No new "unread" computation — reuse `Conversation#unread_incoming_messages` as-is

**Rationale**: Confirmed still present and unchanged at `app/models/conversation.rb:203-204`
(`unread_messages.where(account_id: account_id).incoming.last(10)`), already the same mechanism
backing standard inbox unread badges. Returns an `Array` (via `.last(10)`), so the derived method
must use `.any?`, not `.exists?` (which `Array` does not implement).

**Alternatives considered**: None — this is explicitly out of scope per the spec's "Fora de
escopo" section (no new definition of "unread", no message count).

## Decision: Visual treatment — dot with slow pulse, not a text pill

**Rationale**: Already settled in the source design conversation and restated in the spec's
Assumptions: state badges (Scout) stay as labeled pills; a notification/urgency signal (unread) is
a plain dot, a convention that needs no label. `animate-pulse [animation-duration:3s]` is a
Tailwind utility (arbitrary value), not custom CSS, satisfying Constitution Principle III /
"Tailwind only".

**Alternatives considered**: A numeric badge (message count). Rejected per explicit scope
exclusion in the spec (presence/absence only).
