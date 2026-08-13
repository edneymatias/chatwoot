# SIP/ARI Voice Channel — Replace Twilio with Self-Hosted FreePBX/Asterisk

## Goal

Add a new Chatwoot Voice channel backed by the user's own FreePBX/Asterisk server via
ARI (Asterisk REST Interface), fully eliminating the Twilio dependency for voice. This is an
initial, comprehensive design covering the whole feature; it will be broken into per-cycle specs
during a dedicated future development cycle. No implementation should start from this doc alone —
it is the design-doc gate before `writing-plans`.

## Scope decisions (settled during brainstorming)

- 1:1 calls only — no conference/multi-party.
- Both inbound and outbound calls.
- One shared WebRTC/SIP extension per Chatwoot voice inbox. Every available agent's browser tab
  registers as a separate PJSIP *contact* under that same extension (AOR); Asterisk forks each
  new call to all registered contacts; first agent to answer claims it, mirroring the existing
  Twilio "first-join wins" pattern.
- Multiple simultaneous calls from different callers are supported on the same inbox/extension —
  this mirrors Twilio's actual behavior today (see Section 3.4), not a new requirement.
- Recordings are proxied on-demand from Asterisk via ARI, not copied into Chatwoot's S3-backed
  ActiveStorage — Chatwoot's storage has a 3-month rotation policy, and call recording retention
  should instead follow Asterisk's own housekeeping. This is a deliberate departure from how
  Twilio recordings work today (see Section 6.1).
- The existing frontend call UI layer (`useCallSession`, `useCallsStore`, `FloatingCallWidget`,
  call bubbles) is provider-agnostic already and is reused as-is; only a thin new client class and
  a few provider-branch checks are added.

## 1. Architecture Overview

Twilio's model is webhook-push (no persistent connection required): Twilio calls Chatwoot's
webhooks on status changes, and TwiML tells Twilio what to do next. ARI is the opposite: a
persistent WebSocket event stream (Stasis application) plus a REST control API (bridges,
channels, recordings, originate) — Chatwoot must hold a connection open and react to events in
real time.

New components:
- A new `Channel::SipAri` inbox type (Section 2).
- A lightweight Node.js "ARI bridge" service maintaining the WebSocket connection to Asterisk and
  forwarding translated events to Rails (Section 3.1).
- A FreePBX Custom Destination / Stasis dialplan entry per inbox extension (Section 3.2).
- A browser-side SIP client (`sip.js`) replacing `@twilio/voice-sdk` for the shared extension
  (Section 4).

## 2. Data Model

- New channel model: **`Channel::SipAri`** (not a generic "Sip" name) — this specifically names
  the SIP-over-Asterisk-ARI transport, reducing collision risk if upstream Chatwoot ever ships its
  own native SIP/VoIP provider under a more generic name. Confirmed via upstream code search
  (`chatwoot/chatwoot`) that no native SIP/ARI provider exists today — `enterprise/app/models/call.rb`
  upstream has the same `enum :provider, { twilio: 0, whatsapp: 1 }` as this fork.
- New `Call.provider` enum value: **`sip_ari`** (`enum :provider, { twilio: 0, whatsapp: 1, sip_ari: 2 }`).
- No schema change needed for `Call.meta` (jsonb) — new keys are added to the existing
  `store_accessor :meta, ...` list (e.g. `:recording_name`) rather than new columns.
- `channel_sip_aris` table (new migration) + standard `Inbox`/`Channelable` polymorphic wiring —
  no changes needed to `Inbox` or `Channelable` itself.

```ruby
class Channel::SipAri < ApplicationRecord
  include Channelable

  encrypts :extension_secret, :ari_password

  validates :sip_server, :extension, :extension_secret,
            :ari_base_url, :ari_username, :ari_password, presence: true
end
```

## 3. Backend: ARI Connection Service & Call Routing

### 3.1 Connection service

Use the **official Node.js ARI client**, `asterisk/node-ari-client` (npm package `ari-client`) —
maintained directly under the official `asterisk` GitHub organization. No comparable
actively-maintained Ruby ARI client exists, so this is a new lightweight Node.js service (working
name `voice_ari`, containerized like the existing `sidekiq` service), not a Ruby daemon. It:
- Owns the persistent WebSocket connection to Asterisk (one connection per distinct Asterisk
  server, not per inbox).
- Forwards translated events (StasisStart, ChannelStateChange, ChannelDestroyed,
  RecordingFinished, etc.) to Rails via internal HTTP call or Redis pub/sub (already consumed by
  Sidekiq).
- Holds no business logic — all call/state logic stays in Rails/Sidekiq, same as today.
- Reconnects with backoff using `ari-client`'s built-in handling (Section 7.1).

### 3.2 FreePBX dialplan integration

Each `Channel::SipAri` inbox's extension is reached via a FreePBX Custom Destination that invokes
`Stasis(chatwoot, inbox_id=<id>)`. Stasis only takes control of a channel once the dialplan
explicitly hands it off — anything upstream of that (IVR/URA menus, business-hours checks, digit
routing) is invisible to the ARI bridge and needs no design accommodation:

```
Inbound trunk → Inbound Route → IVR ("press 1") → Custom Destination
  → Stasis(chatwoot, inbox_id=<id>) → Node ARI bridge
```

Confirmed live on the user's FreePBX: the inbound route currently points directly at extension
`5001` only because the IVR was temporarily bypassed for testing; production routing normally
goes through an IVR first. No design change is needed to accommodate this — only the IVR's
"press 1" destination needs to point at the same Custom Destination that today points at `5001`.

### 3.3 ARI Bridge model

Replaces Twilio's `conference_sid` concept — an ARI Bridge object per call, used to connect the
inbound/outbound channel to whichever agent channel answers.

### 3.4 Concurrent calls: no busy/queue/voicemail

Investigated what Twilio does today for a second inbound call arriving while the inbox already
has one active call — there is **no busy/queue/voicemail handling at all**:
- `Voice::InboundCallBuilder` creates a new `Call` + conversation + conference for every inbound
  call, with no inbox-level "already busy" check.
- `TwilioVoiceClient.initializeDevice` sets `allowIncomingWhileBusy: true`, explicitly allowing a
  second call to ring in over the Twilio Device while one is already connected.
- `Voice::Conference::Manager#claim_for_user!` implements first-join-wins for one call being
  joined by multiple agent tabs — not concurrency handling across distinct calls.

**Decision: replicate this for SIP/ARI.** Every simultaneous inbound call becomes its own Stasis
instance / `Call` row / bridge, and rings all agents' registered contacts independently — no
busy/queue/voicemail logic is built. This is simpler than the alternatives considered (SBC-level
busy/queue) and consistent with existing product behavior.

Ring-fork validated live (Image #17, this session): two SIP clients (MicroSIP at work, Linphone
at home) registered simultaneously as separate contacts under the same extension, and both rang
concurrently for one live inbound test call, confirming PJSIP's `Max Contacts` / `Remove Existing`
settings support this on the user's real, third-party-hosted FreePBX (`dens.lansip.net.br`) — no
SBC/hosting-plan restriction blocks it.

**Not yet validated**: two *distinct simultaneous callers* both reaching the extension at once
(as opposed to one call forking to multiple contacts). This depends on:
- `Call Waiting` = `Yes` on the extension (should be default; PJSIP has no built-in per-extension
  concurrent-call cap).
- The inbound **trunk's** simultaneous-channel capacity — checked on the user's FreePBX
  (`Maximum Channels` on the Algar trunk is blank, which means "no limit imposed by Asterisk," not
  "unlimited on Algar's side"). The user suspects their Algar trunk plan may only support one
  simultaneous inbound channel. **This is a carrier/plan-level constraint, not visible from
  FreePBX and not an architecture concern** — if true, it caps real-world concurrent inbound calls
  regardless of what the SIP/ARI design supports, and is resolved by a plan upgrade, not code.
  Documented here as a known infra constraint (Section 3.4 note), test pending a second phone
  line.
- Suggested CLI verification once a second line is available: `asterisk -rvvv` +
  `pjsip set logger on` to watch whether a second INVITE from Algar even arrives during a second
  simultaneous call, plus `pjsip show channels` / `core show channels` to confirm two independent
  channels.

### 3.5 Outbound calls

ARI `originate` targeting the specific contact/channel that initiated the call — implementation
detail, no infra risk identified (not live-validated, but considered low-risk relative to 3.4).

## 4. Frontend SIP Client

### 4.1 Library

`sip.js` (actively maintained WebRTC-SIP stack) replaces `@twilio/voice-sdk`, for the same reason
the backend uses the official `ari-client` — avoid hand-rolling SIP/WebRTC signaling.

### 4.2 Integration shape

New `app/javascript/dashboard/api/channel/voice/sipAriVoiceClient.js`, mirroring
`twilioVoiceClient.js`'s `EventTarget`-based singleton shape 1:1 so the rest of the call UI layer
needs no changes:
- `initializeDevice(inboxId)` fetches SIP credentials for the shared inbox extension (not a
  Twilio JWT) and does `UserAgent.register()` over `wss://<server>` — every agent's browser
  becomes another PJSIP contact under the shared AOR, same mechanism validated live in Section 3.4.
- `joinClientCall` → accept the inbound `Invitation`.
- `endClientCall` → `session.bye()` / `session.reject()`.
- Ring-fork "first to answer wins" is inherent to PJSIP (Asterisk cancels the other INVITEs) — no
  app-level ring race logic needed. The **call-record claim** (`accepted_by_agent_id`,
  conversation auto-assignment) still needs the same first-join-wins DB-lock pattern
  `Voice::Conference::Manager#claim_for_user!` uses today, driven off the ARI answer event
  forwarded by the Node bridge.

### 4.3 Unchanged

`useCallSession.js`, `useCallsStore`, `FloatingCallWidget`, call bubbles, `VOICE_CALL_STATUS`/
`VOICE_CALL_DIRECTION` constants are already provider-agnostic. Only a small `isSipAriCall`
provider branch is needed anywhere `TwilioVoiceClient` is called directly, mirroring the existing
`isWhatsappCall` fork.

## 5. Inbox Settings / Admin UI

### 5.1 Setup flow

New "SIP" option in the inbox-creation channel picker, backed by `Channel::SipAri`, mirroring the
existing Twilio setup wizard.

### 5.2 Fields at creation

- SIP server host (e.g. `dens.lansip.net.br`)
- WSS port/URI (confirmed already available as a transport option on the user's PBX — no new
  transport config needed)
- Extension (AOR), e.g. `5001`
- Extension secret/password
- ARI credentials: base URL (e.g. `https://dens.lansip.net.br:8089`), ARI username, ARI password —
  server-side only, never exposed to the frontend, encrypted attributes (same treatment as
  `account_sid`/`auth_token` on `Channel::Twilio`)
- Display name / phone number label for the inbox

### 5.3 Validation on save

Live-check ARI connectivity (`GET /ari/asterisk/info`) before persisting — fail fast with a clear
error rather than silently saving broken credentials. No live SIP-registration check at save time
(that's async via the Node bridge).

### 5.4 Out of scope

No per-agent extension/credential management — single shared-extension model only, agents just
need inbox membership, same as Twilio voice today.

### 5.5 Existing Twilio-hardcoded call path to fix

`Api::V1::Accounts::Contacts::CallsController#voice_inbox` (the endpoint the contact panel's
"call" button hits to start an outbound call) currently looks up the inbox with
`channel_type: 'Channel::TwilioSms'` hardcoded, then checks `inbox.channel.voice_enabled?`. This
must change to accept `Channel::SipAri` inboxes too — either look up by `channel_type: ['Channel::TwilioSms', 'Channel::SipAri']`
or drop the `channel_type` filter entirely and rely on `voice_enabled?` alone. Without this fix,
outbound calling from the contact panel silently breaks for SIP/ARI inboxes.

## 6. Call Recording

### 6.1 On-demand ARI proxy, not a storage copy

Confirmed (this session) that Twilio recordings today are **not** proxied — they're downloaded
and permanently attached to the `Call` via ActiveStorage
(`Voice::RecordingStatusService` → `Voice::Provider::Twilio::RecordingAttachmentJob` →
`Voice::Provider::Twilio::RecordingAttachmentService#attach_recording!`,
`Call#recording_url` returns `rails_blob_url(recording)`), inheriting the 3-month S3 rotation
policy as a side effect. SIP/ARI deliberately does **not** replicate this — Asterisk recordings
stay on the PBX and are streamed through Rails on request instead.

### 6.2 Recording lifecycle

- Recording starts via ARI's `POST /channels/{channelId}/record` when the bridge is created, or
  is picked up from FreePBX's own dialplan-level `MIXMONITOR` if recording is already configured
  before Stasis takes over (needs confirming which applies on this PBX).
- On `RecordingFinished`, the Node bridge notifies Rails; Rails stores the recording
  name/ID + ARI server reference on `Call.meta` (new `store_accessor` key, no schema change).

### 6.3 Playback/proxy endpoint

New `GET /api/v1/accounts/:account_id/calls/:id/recording`:
1. Same conversation-access authorization as any other call resource.
2. Server-side `GET /recordings/stored/{recordingName}/file` directly against ARI (one-shot file
   download, not through the Node bridge/event stream).
3. Streams bytes back as the response body — Rails is a thin authenticated proxy; ARI credentials
   never reach the browser.

### 6.4 Frontend

Checked `CallRecordingPlayer.vue` (this session) — it takes a plain `src: String` prop and plays
it via a native `<audio>` element, with **no Twilio-specific logic**. No frontend changes needed;
it works identically against the new proxy URL.

### 6.5 `Call#recording_url` provider branch

`Call#recording_url` currently hard-assumes ActiveStorage. Needs a `sip_ari?` branch (the enum
value from Section 2 already provides this method for free) pointing at the new proxy route
instead of `rails_blob_url`:

```ruby
def recording_url
  return sip_ari_recording_proxy_url if sip_ari? && meta['recording_name'].present?
  return nil unless recording.attached?

  Rails.application.routes.url_helpers.rails_blob_url(recording)
end
```

No other ripple effects — `push_event_data` and the frontend already just consume whatever string
`recording_url` returns.

### 6.6 Retention

No Chatwoot-side deletion logic — retention is entirely Asterisk/FreePBX's own recording
housekeeping, outside this design's scope. If a recording has been purged server-side, ARI 404s;
the proxy endpoint should surface a clean "recording no longer available" error, not a raw 500.

## 7. Error Handling & Edge Cases

### 7.1 ARI WebSocket disconnects

Reconnect with backoff via `ari-client`'s built-in handling. While disconnected, in-progress
`Call` records are not actively invalidated — they just stop receiving updates. On reconnect,
reconcile via `GET /channels` and `GET /bridges` against Chatwoot's `Call.active` records, closing
out anything that no longer exists on the Asterisk side. Twilio's webhook model is inherently
resilient to gaps; ARI's persistent-connection model needs this explicit reconciliation step.

### 7.2 SIP registration failures (agent's browser)

`sip.js` registration failure/timeout surfaces as a connection-status indicator, mirroring the
existing Twilio Device init failure path in `useCallSession.js`. No retry storm — same
debounced/backoff pattern already used for Action Cable reconnects.

### 7.3 Outbound call failures

ARI `originate` failure (unreachable extension, invalid number, trunk rejects) → Node bridge
forwards a failure event → Rails marks the `Call` `failed` with `end_reason`, same terminal-status
handling `Voice::Conference::Manager#finalize!` already does for Twilio.

### 7.4 Agent tab closes mid-call

No SIP-specific handling beyond what exists already: `beforeunload`/`pagehide` listeners in
`useCallSession.js` are already provider-agnostic. The SIP session's `bye()` needs wiring into the
same teardown path `sendWhatsappTerminateBeacon` uses (a `sendBeacon` call so hangup fires even as
the tab closes).

### 7.5 Trunk capacity exceeded

If the carrier's trunk rejects a call before it reaches Asterisk, no Stasis event is ever
generated — Chatwoot never sees the call at all. Nothing to catch; the caller gets the carrier's
own busy/network response. Documented as an accepted infra limitation (see Section 3.4), not a
Chatwoot code path.

### 7.6 Agent availability

Checked `dashboard/helper/voice.js:shouldRingInbound` (this session) — Twilio's "unavailable"
handling is purely app-layer: Twilio never dials any agent's Device directly for inbound calls;
Chatwoot broadcasts a cable event to every connected agent browser, and each browser locally
decides whether to show/ring the incoming-call popup based on `currentUserAvailability ===
'online'` — the same status field used everywhere else in the app, no separate voice-availability
concept.

SIP/PJSIP ring-fork is structurally different: ringing happens at the phone layer (Asterisk forks
the INVITE to every registered contact), not the app layer. This still works cleanly **as long as
the browser's `sip.js` client is the registered contact** — the browser physically receives the
INVITE and the same JS-layer gating (`shouldRingInbound`-equivalent) suppresses/shows it exactly
like today.

**Constraint**: if an agent also runs a separate physical/softphone (e.g. MicroSIP, Linphone — as
used for the Section 3.4 validation test) registered as an additional contact under the same
shared extension, that device rings regardless of the agent's Chatwoot availability status —
Chatwoot cannot reach into a third-party SIP client to suppress it, since the fork happens inside
Asterisk. **Production posture: agents should use the built-in browser SIP client as their primary
registered device, not a parallel hardphone/softphone, if Chatwoot's availability toggle is
expected to be authoritative.**

## Open items carried forward (not blocking this doc, to resolve before/during implementation)

- Live-test two distinct simultaneous callers against the real Algar trunk once a second phone
  line is available (Section 3.4).
- Confirm whether call recording should be started by the ARI bridge (`POST
  /channels/{channelId}/record`) or is already handled by FreePBX's own dialplan-level
  `MIXMONITOR` before Stasis takes over (Section 6.2).
- File path/spec breakdown for the dedicated implementation cycle — this doc will be split into
  per-cycle specs at that time, not implemented directly from here.

## Non-goals

- No conference/multi-party calling.
- No busy/queue/voicemail handling (Section 3.4).
- No per-agent SIP credential management (Section 5.4).
- No Chatwoot-side recording retention/deletion logic (Section 6.6).
