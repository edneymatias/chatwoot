# Phase 08: Agent-to-Agent Call Transfer

**Status**: placeholder — pending brainstorm session
**Depends on**: Phases 01-03 (data model, ARI bridge service, inbound call routing) must exist
before this is buildable — transfer manipulates the same ARI Bridge object Phase 03 introduces.

## Quick Preview

Not part of the original SIP/ARI design (`spec48.md`) or Phases 01-07 — those explicitly scope to
"1:1 calls only," with the existing first-agent-to-answer-wins claim model and no notion of moving
an already-claimed call to a different agent.

Confirmed during a follow-up discussion (this session):
- **Twilio today has no call-transfer concept in this fork** — searched `enterprise/app/services/voice`,
  the voice controllers, `Call` model, and the frontend call-session code; no transfer-related code
  exists anywhere. The only "handoff" mechanism today is ring-all-agents /
  `Voice::Conference::Manager#claim_for_user!` first-join-wins at call-start time.
- **Technically feasible with ARI** — well-established patterns:
  - Blind transfer: remove agent A's channel from the Bridge, ARI `originate` a new channel to
    agent B's extension, add it to the same Bridge.
  - Attended/warm transfer: create a second Bridge, agent A consults agent B in it, then move the
    customer's channel from Bridge 1 to Bridge 2 and drop agent A.

## Open questions for the brainstorm

- Blind transfer only, warm/attended transfer only, or both? (Different UI and backend
  complexity — warm transfer needs a consultation-call UI state that doesn't exist today.)
- What happens to `Call.accepted_by_agent_id` and `Conversation` assignment on transfer — does the
  conversation reassign to the receiving agent, same as today's claim model, or stay put?
- Does the receiving agent need to be online/available, and does the existing ring-fork/
  availability gating (Phase 05, `shouldRingInbound`-equivalent) apply to the transfer target?
- Does a transferred call need a new `Call` row (like a new leg) or stay the same row with new
  `meta` tracking the transfer, for reporting/history purposes (`CallFinder`, the Calls page)?
- Should this be scoped only to SIP/ARI inboxes, or does the same design apply to (future) Twilio
  parity — i.e., is this SIP/ARI-only or a general voice-channel feature?
- UI entry point: where does "Transfer" live during an active call (`FloatingCallWidget`?), and
  how does the agent picker work (all account agents, only agents assigned to the inbox, only
  online agents)?
