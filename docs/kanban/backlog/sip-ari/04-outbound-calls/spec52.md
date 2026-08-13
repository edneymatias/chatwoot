# Phase 04 — Outbound Calls

**Master doc**: `docs/kanban/backlog/sip-ari/spec48.md` §3.5, §7.3

## Goal

Support agent-initiated outbound calls through the same ARI/bridge machinery Phase 03 built for
inbound.

## Scope

- ARI `originate` targeting the specific contact/channel that initiated the call from the agent's
  side, joining it into a bridge with the dialed external number once answered.
- Reuse the `Channel::SipAri` fix from Phase 01 (§5.5 of the master doc) — the contact-panel
  outbound call button (`Api::V1::Accounts::Contacts::CallsController`) already resolves
  `Channel::SipAri` inboxes as of Phase 01; this phase makes the actual call succeed rather than
  just resolving the inbox.
- Failure handling: `originate` failure (unreachable extension, invalid number, trunk rejects) →
  Node bridge forwards a failure event → Rails marks the `Call` `failed` with `end_reason`, same
  terminal-status handling `Voice::Conference::Manager#finalize!` already does for Twilio.

## Acceptance criteria

- An agent can start an outbound call from the contact panel on a SIP/ARI inbox and it rings the
  dialed number.
- A deliberately invalid outbound number produces a `Call` row with `status: failed` and a
  populated `end_reason`, not a stuck `ringing` record.
