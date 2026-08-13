# Phase 03 — Inbound Call Routing & Concurrency

**Master doc**: `docs/kanban/backlog/sip-ari/spec48.md` §3.3, §3.4, §7.1

## Goal

Turn the raw Stasis events from Phase 02 into real `Call` records, bridges, and agent ringing —
the actual inbound-call business logic, mirroring what `Voice::InboundCallBuilder` /
`Voice::Conference::Manager` do for Twilio today.

## Scope

- ARI Bridge model/service: on `StasisStart` for a new inbound channel, create the `Call` +
  `Conversation` record (mirrors `Voice::InboundCallBuilder`), create an ARI Bridge object (this
  replaces Twilio's `conference_sid` concept), and add the inbound channel to it.
- No busy/queue/voicemail logic — every simultaneous inbound call gets its own Stasis instance /
  `Call` row / bridge, ringing all of the extension's registered contacts independently. This
  mirrors Twilio's actual current behavior (`Voice::InboundCallBuilder` has no "already busy"
  check; `TwilioVoiceClient` sets `allowIncomingWhileBusy: true`) — do not build queue/voicemail
  handling.
- First-agent-to-answer-wins: when an agent's registered contact answers, the Node bridge forwards
  the answer event; Rails claims the call for that agent using the same first-join-wins DB-lock
  pattern `Voice::Conference::Manager#claim_for_user!` uses today, then adds that agent's channel
  to the bridge.
- ARI WebSocket reconnect reconciliation (§7.1): on reconnect, reconcile via `GET /channels` and
  `GET /bridges` against Chatwoot's `Call.active` records, closing out anything that no longer
  exists on the Asterisk side. While disconnected, in-progress `Call` records are left alone (not
  invalidated) — they just stop receiving updates until reconciliation runs.

## Known open item (not blocking, documented, not to be solved in this phase)

Two *distinct simultaneous callers* reaching the extension at once (as opposed to one call
forking to multiple contacts) is validated only for the ring-fork mechanism, not for real trunk
concurrency — the Algar trunk's actual simultaneous-channel capacity is unconfirmed (carrier/plan
constraint, not an architecture concern; see spec48.md §3.4). Live-test once a second phone line
is available. This does not block shipping this phase — code handles it correctly regardless of
whether the trunk currently allows it.

## Acceptance criteria

- A real inbound call produces a `Call` + `Conversation` row and rings all agents' registered
  SIP contacts for the inbox (validated against at least one registered softphone, ahead of the
  browser client landing in Phase 05).
- First agent to answer claims the call; the `Call` row records `accepted_by_agent_id`; other
  ringing contacts stop ringing (Asterisk-native CANCEL, not app logic).
- Killing and restoring the `voice_ari` service mid-idle does not leave stale "active" `Call`
  records after reconciliation runs.
