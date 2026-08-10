# Phase 26: WhatsApp Referral (Facebook/Instagram Ad) Attribution — feasibility study

**Status**: investigation paused, resumable — root cause confirmed, two
candidate solution paths identified, not yet decided/committed to
implementation (see "Investigation log" below for full findings)
**Depends on**: none functionally; reads data already captured by the
existing WhatsApp Cloud integration

## Quick Preview

WhatsApp's Cloud API already sends a `referral` object on the first
inbound message of a "click-to-WhatsApp" conversation started from a
Facebook/Instagram ad (source ad/post id, source URL, headline, body,
media type/URL, CTWA click id). Chatwoot already captures this today:
`Whatsapp::IncomingMessageServiceHelpers#referral_attributes` pulls
`message[:referral]` from the webhook payload and
`IncomingMessageBaseService` stores it as-is into
`content_attrs[:referral]` on the `Message` record's
`content_attributes` — but that's the entire extent of what exists. The
raw hash is persisted and never touched again: not normalized into a
predictable schema, not surfaced anywhere in the frontend (conversation
sidebar, contact panel), not copied onto the `Conversation` or `Contact`
for cross-message reuse, and not aggregated into any report.

This phase is explicitly a **feasibility/design study**, not committed
implementation — the goal is to figure out what "reading referral data"
should mean product-wise before building it:
- Surfacing it per-conversation (e.g. a "veio de anúncio: <headline>"
  badge/panel in the conversation view) — lowest-effort, data already
  exists, closest to a pure UI phase.
- Attribution reporting (e.g. "opportunities/conversations originated
  from ad X", tying `referral.source_id`/`ctwa_clid` through to
  Opportunity creation and eventually to Phase 21's funnel report) —
  meaningfully bigger scope, needs a place to persist normalized
  referral data (new column/table vs. reading `content_attributes` live
  each time) and a decision on which record it belongs to (message vs.
  conversation vs. contact, since a contact could have multiple
  ad-originated conversations over time).

Open questions for the brainstorm:
- Confirm the actual field set Meta sends today (may differ from the
  stored raw hash across API versions) — worth a quick reference check
  against WhatsApp Cloud API docs before designing a schema, rather than
  inferring from whatever's currently landing in `content_attributes`.
- Does this apply only to WhatsApp Cloud (`incoming_message_whatsapp_cloud_
  service.rb`), or do other WhatsApp providers (360dialog, Twilio) send
  an equivalent referral payload worth normalizing the same way?
- Scope for this phase: read-only surfacing (badge/panel), or does it
  extend into attribution reporting/analytics? Recommend treating those
  as two separate phases even if this one studies both — surfacing is a
  much smaller, faster win.
- Is there a data-retention/PII concern with persisting ad creative
  content (headline/body/media URL) beyond the message it already lives
  on?

## Investigation log (2026-08-09)

Context that triggered this investigation: the original ask behind this whole
Kanban/CRM effort. Dens Odontologia (dental clinic) runs Click-to-WhatsApp
(CTWA) ad campaigns via a marketing agency. Today the *only* signal the SDR
has that a conversation came from a campaign is the pre-filled suggested
message text — and leads frequently edit or delete that text before sending,
so text-matching is not a reliable attribution mechanism. Goal: identify
CTWA-originated conversations unambiguously, then populate specific
Opportunity fields from that data.

### Discovery: two WhatsApp numbers, two different code paths

The agency's campaigns actually run across **two different WhatsApp
numbers/inboxes**, each hitting a completely different Chatwoot channel:

1. **Official WhatsApp Cloud API** (`Channel::Whatsapp`) — already fully
   working, no code changes needed.
2. **Evolution API** (self-hosted, wraps Baileys) connected via webhook
   integration — has a real, fixable gap (see below).

This was not known at the start of the investigation; discovered mid-way via
live production test traffic landing on different inboxes.

### Path 1 — Cloud API: already works out of the box

Confirmed via a live production test message (id `1352475`, contact Gabriel
Gonzales, edited-text test) that WhatsApp Cloud API delivers a fully
structured `referral` object on the webhook payload, and Chatwoot already
persists it verbatim:

- `Whatsapp::IncomingMessageServiceHelpers#referral_attributes` pulls
  `message[:referral]` from the webhook.
- `IncomingMessageBaseService` stores it into `content_attrs[:referral]` on
  the `Message`'s `content_attributes`.
- Observed real payload shape: `source_url`, `source_id` (the actual Meta ad
  ID), `source_type`, `headline`, `body`, `media_type`, `image_url`.

Crucially, `source_id` — the field needed to resolve back to
campaign/ad-set/ad via the Marketing Graph API — is present here. No patch
needed for this number.

### Path 2 — Evolution API: real gap, but small and well-scoped

Evolution API (repo `evolution-foundation/evolution-api`, formerly
`EvolutionAPI/evolution-api` — same repo, org renamed) wraps Baileys
(`WhiskeySockets/Baileys`) and forwards messages to Chatwoot via its own
Chatwoot integration service.

**Root cause is Evolution-side, not Baileys-side.** WhatsApp's protobuf
`ContextInfo.ExternalAdReplyInfo` (declared in Baileys'
`WAProto/WAProto.proto`) already includes `sourceId` (field 8) alongside
`title`, `body`, `mediaType`, `thumbnailUrl`, `mediaUrl`, `thumbnail`,
`sourceType`, `sourceUrl`. Baileys decodes all of these fields automatically
via standard protobuf decoding — there is nothing Baileys needs to expose
that it doesn't already expose.

Evolution's own code simply doesn't read the field. In
`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts`:

- `getAdsMessage(msg)` (~line 1722–1741) extracts only `title`, `body`,
  `thumbnailUrl`, `sourceUrl` from `contextInfo.externalAdReply` — **omits
  `sourceId`/`sourceType`**. This is the exact function that needs patching
  to add those two fields.
- The call site (~line 2034, `const adsMessage = this.getAdsMessage(body)`)
  and the send logic (~line 2208–2260) render the ad data into a caption
  string concatenated onto the **same message** as the lead's own text and
  send it to Chatwoot as an image attachment:
  ``` 
  `${bodyMessage}\n\n\n**${title}**\n${description}\n${adsMessage.sourceUrl}`
  ```
  This means the ad info is not stored structurally (no equivalent of
  Cloud API's `content_attributes.referral`) — it's free text baked into a
  caption. A patch should also change this to store structured data instead
  of (or in addition to) the concatenated caption, otherwise `source_id`
  would still be unusable without regex-parsing message text.
- Reference implementation for shape: `clairton/unoapi-cloud`'s
  `src/services/transformer.ts` already does the equivalent extraction —
  `externalAdReply.sourceId` → `referral.source_id` — useful as a design
  reference for the Evolution patch.

### Empirical validation: does editing/clearing the suggested text break attribution?

This was the central open question — the user's literal concern was: lead
clicks the ad, WhatsApp opens with a suggested message, and *before sending*
the lead edits or deletes that suggested text. Does that wipe the ad
metadata too?

Tested live against real ad campaigns (Meta Ads Manager Ad Preview, not
scripted/automated clicks — avoids invalid-traffic/click-fraud policy risk)
with three real test sends, SQL run directly by the user against
production and pasted back for analysis (I never had direct DB/VPS access
this round — by design, see "Constraints" below):

1. **Test 1** — Cloud API number, text edited before sending (message id
   `1352475`, contact Gabriel Gonzales). Referral metadata present and
   intact.
2. **Test 2** — Evolution/WhatsApp Business number, text sent unedited
   (message id `1352606`, same contact, via Instagram-sourced ad). Ad-card
   metadata present.
3. **Test 3** — Evolution/WhatsApp Business number, text replaced entirely
   with "Abobrinha" before sending (message id `1352618`). Ad-card metadata
   still present.

**Conclusion: metadata survives text edits on both numbers.** The
attribution signal is tied to the ad-click origin itself (`ctwa_clid`-style
tracking baked into the click, not the literal message body), not to
whatever text the lead actually sends. This fully de-risks the plan —
editing/clearing the suggested message is *not* the failure mode to design
around.

### Architectural caveat: post-send deletion (different from the above)

Separately investigated (and distinct from the pre-send editing question
above): what happens if a lead deletes the message *after* sending it?
Chatwoot represents a deleted message by overwriting `content` and setting
`content_attributes.deleted = true` — this **destroys** whatever was in that
message, including any ad-card info if it was embedded in the same message
(as Evolution's current design does, via the concatenated caption format).
No genuine occurrence of this was found in production data during the
search, but it's a real architectural weak point specific to Evolution's
current combined-message design — not present on the Cloud API path, where
`referral` lives in `content_attributes` on the lead's actual message
regardless of what happens to later messages. If pursuing the Evolution
patch, consider sending the ad-card as Chatwoot metadata on the same message
without depending on a separate always-undeletable message, or at minimum
document this residual risk rather than treating it as fully solved.

### Two candidate solution paths (not yet decided)

1. **Patch Evolution API's `getAdsMessage`** to capture `sourceId`/
   `sourceType` and store them structurally (not concatenated into message
   text) — needed only to fix the Evolution-connected number. Small,
   well-scoped, independently validated by the `unoapi-cloud` reference
   implementation. Requires forking/patching Evolution API itself (an
   external project, not part of this repo) and deploying the patched
   image.
2. **Standardize campaigns on the Cloud API number**, which already works
   out of the box via Chatwoot's existing `referral_attributes` handling —
   no patch needed at all. The user is independently checking with the
   agency which campaigns run through which number
   (*"vejo agora que a agencia está usando dois números nas campanhas. vou
   dar uma olhada a mais."*) — this may make path 1 partially or entirely
   unnecessary depending on what they find.

### Remaining open questions for when work resumes

- Which number will the agency's campaigns ultimately standardize on (or
  will both stay in use, requiring both paths)?
- Once `source_id` is captured, what resolves it into human-readable
  campaign/ad-set/ad names? Needs a call to the Meta Marketing Graph API
  (`GET /{ad_id}?fields=name,adset{id,name},campaign{id,name}`) with an
  access token scoped `ads_read` for the ad account — not yet designed.
- Where should resolved attribution data live: `content_attributes.referral`
  as-is (message-level, Cloud API's existing shape), or copied onto the
  Conversation/Contact/Opportunity for cross-message reuse and reporting?
  The user's original goal was specifically "preencher campos específicos
  da oportunidade" — populate custom fields on the Opportunity — which
  implies a normalization/copy step is needed regardless of which number is
  in use, since `content_attributes` alone isn't queryable/reportable at
  the Opportunity level today.
- Exact design of the Evolution patch (if still needed after the
  two-number question is resolved): field additions to `getAdsMessage`,
  and whether to keep the concatenated-caption message format or switch to
  storing referral data in `content_attributes` the same way Cloud API
  does, for a consistent downstream schema regardless of which number a
  conversation came in on.

### Constraints observed during investigation (for future reference)

- Evolution API and Baileys are external repos, not part of this
  codebase — any patch work happens in a separate fork/deployment, not
  in this repo.
- Live testing against real Meta ad campaigns must go through Ads
  Manager's **Ad Preview** tool (Campaigns → Ads → select ad → Preview
  panel), not scripted/automated clicks — avoids invalid-traffic/click-fraud
  policy risk, even against one's own campaign.
- Per user's explicit workflow preference this round: I do not get direct
  production DB/VPS access. I provide SQL, the user runs it against
  production themselves and pastes the output back for analysis. (A
  root VPS password was offered but declined in favor of this, and in
  favor of least-privilege if DB access is ever granted directly.)
