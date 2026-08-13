# Phase 02 — ARI Bridge Service & FreePBX Dialplan Integration

**Master doc**: `docs/kanban/backlog/sip-ari/spec48.md` §1, §3.1, §3.2

## Goal

Stand up the persistent connection between Asterisk and Chatwoot: a new Node.js service holding
the ARI WebSocket, plus the FreePBX-side dialplan wiring that hands a call off to it. At the end
of this phase, Chatwoot can *observe* Stasis events for a real call, with no call-handling logic
yet (that's Phase 03).

## Scope

- New Node.js service (working name `voice_ari`), containerized alongside the existing `sidekiq`
  service in `docker-compose.yaml`, using the official `asterisk/node-ari-client` npm package
  (`ari-client`) — no Ruby ARI client is used.
- Responsibilities of this service, and only these:
  - Own the persistent WebSocket connection to Asterisk (one connection per distinct Asterisk
    server, not per inbox).
  - Subscribe to the `chatwoot` Stasis application.
  - Forward translated events (`StasisStart`, `ChannelStateChange`, `ChannelDestroyed`,
    `RecordingFinished`, etc.) to Rails via internal HTTP call or Redis pub/sub (reusing the
    existing Sidekiq Redis connection).
  - Hold no business logic — all call/state decisions stay in Rails/Sidekiq (Phase 03 consumes
    these events).
  - Reconnect with backoff using `ari-client`'s built-in reconnect handling.
- FreePBX-side: a Custom Destination per inbox extension invoking `Stasis(chatwoot, inbox_id=<id>)`.
  Confirm/point the existing IVR's "press 1" destination (currently bypassed, pointing directly at
  extension `5001` for testing) at this Custom Destination instead.
- A minimal Rails-side webhook/ingestion endpoint that just logs received events — proves the
  pipe works end to end. Real handling is Phase 03's job.

## Acceptance criteria

- `voice_ari` service starts under `docker compose up -d` and stays connected to the Asterisk ARI
  WebSocket (verify via `voice_ari` logs and `pjsip show channels` staying in sync).
- Dialing the FreePBX extension produces a `StasisStart` event that's visibly forwarded to Rails
  (log line, no business logic yet).
- Reconnect behavior: killing/restoring network to Asterisk causes `voice_ari` to reconnect
  automatically without a service restart.
