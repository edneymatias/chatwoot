# Phase 05 — Frontend SIP Client

**Master doc**: `docs/kanban/backlog/sip-ari/spec48.md` §4, §7.2, §7.4

## Goal

Replace the Twilio browser SDK with a SIP.js-based client for SIP/ARI inboxes, wired into the
existing (provider-agnostic) call UI layer.

## Scope

- New `app/javascript/dashboard/api/channel/voice/sipAriVoiceClient.js`, mirroring
  `twilioVoiceClient.js`'s `EventTarget`-based singleton shape 1:1:
  - `initializeDevice(inboxId)` fetches SIP credentials for the shared inbox extension (not a
    Twilio JWT) and does `UserAgent.register()` over `wss://<server>` — every agent's browser
    becomes another PJSIP contact under the shared AOR (mechanism validated live during
    brainstorming, see spec48.md §3.4).
  - `joinClientCall` → accept the inbound `Invitation`.
  - `endClientCall` → `session.bye()` / `session.reject()`.
- `useCallSession.js`: add an `isSipAriCall` provider branch anywhere `TwilioVoiceClient` is
  called directly, mirroring the existing `isWhatsappCall` fork. No other changes — `useCallsStore`,
  `FloatingCallWidget`, call bubbles, `VOICE_CALL_STATUS`/`VOICE_CALL_DIRECTION` constants are
  already provider-agnostic.
- Ring-fork "first to answer wins" needs no app-level race logic (Asterisk cancels the other
  INVITEs natively) — only the call-record claim (`accepted_by_agent_id`, conversation
  auto-assignment) needs the Phase 03 first-join-wins DB-lock path, driven off the ARI answer
  event.
- SIP registration failure/timeout (§7.2): surface as a connection-status indicator, mirroring the
  existing Twilio Device init failure path — same debounced/backoff pattern already used for
  Action Cable reconnects, no retry storm.
- Agent tab closes mid-call (§7.4): wire the SIP session's `bye()` into the same `sendBeacon`
  teardown path `sendWhatsappTerminateBeacon` uses in `useCallSession.js`'s
  `beforeunload`/`pagehide` listeners (already provider-agnostic, just needs the SIP call added).

## Acceptance criteria

- An agent's browser registers as a SIP contact on page load / dashboard mount for any inbox with
  a SIP/ARI channel they belong to.
- An inbound call (from Phase 03) rings in the browser and can be answered/rejected via the
  existing `FloatingCallWidget`/call-bubble UI with no UI code changes beyond the provider branch.
- Closing the browser tab mid-call terminates the SIP session server-side (verified via Asterisk
  channel teardown, not just local cleanup).
- Killing SIP registration (e.g. blocking the WSS port) surfaces a visible connection-failed state
  in the dashboard, without a reconnect storm.
