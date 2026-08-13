# Phase 06 — Call Recording

**Master doc**: `docs/kanban/backlog/sip-ari/spec48.md` §6

## Goal

Make recorded calls playable from Chatwoot, proxied on-demand from Asterisk rather than copied
into ActiveStorage — a deliberate departure from Twilio's model (see spec48.md §6.1 for why:
Chatwoot's S3 storage has a 3-month rotation policy that would silently delete old recordings;
Asterisk's own recording retention should govern instead).

## Scope

- Recording lifecycle: start recording via ARI's `POST /channels/{channelId}/record` when the
  bridge is created, **or** confirm FreePBX's own dialplan-level `MIXMONITOR` already handles it
  before Stasis takes over — this needs confirming against the live PBX config before choosing
  which path to implement (open item carried from the master doc).
- On `RecordingFinished` (forwarded by the Phase 02 `voice_ari` service), Rails stores the
  recording name/ID + ARI server reference on `Call.meta` (new `store_accessor` key
  `:recording_name`, no schema change).
- New proxy endpoint `GET /api/v1/accounts/:account_id/calls/:id/recording`:
  1. Same conversation-access authorization as any other call resource.
  2. Server-side `GET /recordings/stored/{recordingName}/file` directly against ARI (one-shot file
     download, not through the Node bridge/event stream).
  3. Streams bytes back as the response body — Rails is a thin authenticated proxy; ARI
     credentials never reach the browser.
  4. If ARI 404s (recording purged server-side per Asterisk's own retention), surface a clean
     "recording no longer available" error, not a raw 500.
- `Call#recording_url` provider branch (`enterprise/app/models/call.rb`):

```ruby
def recording_url
  return sip_ari_recording_proxy_url if sip_ari? && meta['recording_name'].present?
  return nil unless recording.attached?

  Rails.application.routes.url_helpers.rails_blob_url(recording)
end
```

## Out of scope

- No Chatwoot-side recording retention/deletion logic — entirely Asterisk/FreePBX's own
  housekeeping.
- `CallRecordingPlayer.vue` needs zero changes — confirmed it takes a plain `src: String` prop and
  plays via a native `<audio>` element with no Twilio-specific logic; it works identically against
  the new proxy URL.

## Acceptance criteria

- A completed SIP/ARI call has a working `recording_url` that streams audio through the new proxy
  endpoint, playable in the existing `CallRecordingPlayer.vue` with no frontend changes.
- A recording purged on the Asterisk side (simulate by deleting the file server-side) returns a
  clean error from the proxy endpoint, not a 500.
- Authorization on the proxy endpoint matches existing call-resource access rules (an agent
  without conversation access cannot fetch the recording by ID).
