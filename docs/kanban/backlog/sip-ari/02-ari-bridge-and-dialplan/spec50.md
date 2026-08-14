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

## Deployment topology & audio quality

Confirmed during implementation planning (this session):

- **Asterisk/FreePBX is third-party-hosted**, not on infrastructure we control — it runs in its
  own datacenter, managed by an outside provider. `voice_ari` will run as a new container on our
  own Hetzner VPS, in a separate datacenter from Asterisk.
- **`voice_ari` is control-plane only — no media ever traverses it.** It holds the ARI WebSocket
  (JSON events: `StasisStart`, `ChannelStateChange`, etc.) and issues REST calls (`originate`,
  bridge manipulation). RTP audio flows directly between Asterisk and each SIP endpoint (agent
  browser, customer/carrier leg) — it never routes through our VPS. Consequence: CPU/memory
  contention on our VPS (it's a shared box also running minio, several n8n instances, MySQL,
  Postgres, Metabase, etc. — see `top`/`docker ps` review, load average ~1.2-1.5 on 4 vCPUs, some
  swap in use) **cannot degrade call audio quality**, since no audio packet passes through it.
  What matters instead is network latency/stability between the Hetzner VPS and Asterisk's
  datacenter for the ARI control channel — this affects event delivery and command responsiveness
  (mitigated by `ari-client`'s reconnect-with-backoff, plus Phase 03's `GET
  /channels`/`GET /bridges` reconciliation on reconnect), not audio.
- **Browser replaces MicroSip as the SIP endpoint, on the same physical machine.** Today, agents
  use MicroSip (a native SIP softphone) on their workstation, registered directly to the
  third-party Asterisk, with no reported call-quality complaints. Phase 05's `sip.js` client
  (`spec53.md`) will register the same way (WebRTC SIP.js, agent browser → Asterisk directly,
  same network path MicroSip uses today) instead of a native softphone. Since the network path to
  Asterisk is unchanged and the current baseline (MicroSip) has no quality issues, the browser
  client is not expected to introduce new audio-quality risk — it's a client-software swap on the
  same last-mile network, not a new media route.

## Acceptance criteria

- `voice_ari` service starts under `docker compose up -d` and stays connected to the Asterisk ARI
  WebSocket (verify via `voice_ari` logs and `pjsip show channels` staying in sync).
- Dialing the FreePBX extension produces a `StasisStart` event that's visibly forwarded to Rails
  (log line, no business logic yet).
- Reconnect behavior: killing/restoring network to Asterisk causes `voice_ari` to reconnect
  automatically without a service restart.
