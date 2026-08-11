# Phase 40: Evolution API Patch — Capture `sourceId`/`sourceType` for WhatsApp Ad Referral

**Depends on**: Phase 26 (feasibility study) — root cause, empirical validation, and reference
implementation (`unoapi-cloud`) already established there. Reads/extends
`edneymatias/evolution-api` (external fork, not part of this repo), branched from `main` at the
current tip (`fa09d378`, matching `package.json` version `2.3.7`, no upstream tags pulled yet — the
fork intentionally tracks upstream's **tagged releases only**, not `main`/dev tip, to avoid pulling
in upstream instability).

## Context

Recap from Phase 26's investigation: WhatsApp's Click-to-WhatsApp (CTWA) ad click carries
attribution metadata (`ExternalAdReplyInfo` in the WhatsApp protobuf) regardless of what text the
lead ultimately sends — empirically validated across three live test sends, surviving both a text
edit and a full text replacement. Meta's official Cloud API already exposes this as a `referral`
object and Chatwoot already stores it verbatim (`Whatsapp::IncomingMessageServiceHelpers#
referral_attributes`, a byte-for-byte passthrough of Meta's webhook payload into
`content_attributes.referral`, **no key renaming or normalization** — the field names Chatwoot
stores today are exactly Meta's own: `source_url`, `source_id`, `source_type`, `headline`, `body`,
`media_type`, `image_url`).

The second number the agency's campaigns use connects through **Evolution API** (self-hosted,
wraps Baileys), which relays messages to Chatwoot via its own Chatwoot integration
(`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts`). Baileys already decodes
the full `ExternalAdReplyInfo` struct (including `sourceId`/`sourceType`) — Evolution's own
`getAdsMessage` (`chatwoot.service.ts:1724`) simply doesn't read those two fields, extracting only
`title`, `body`, `thumbnailUrl`, `sourceUrl` for its human-readable ad-card caption. This is a gap
in this specific connector, not a Baileys/protocol limitation — a different Baileys-to-Chatwoot
connector (`unoapi-cloud`) already extracts `sourceId` from the same struct, and there is no
evidence the omission is deliberate; more likely nobody who built this feature had a downstream
need for the two opaque IDs (see "Why upstream never captured this" below).

**Goal of this phase**: patch Evolution to capture `sourceId`/`sourceType` (and any other available
`ExternalAdReplyInfo` fields) and expose them to Chatwoot in the same structural shape Cloud API
already uses (`content_attributes.referral`), so that a later Chatwoot-side phase (Phase 41) can
treat both providers identically. This phase is Evolution-only — no Chatwoot code changes.

### Why upstream never captured this

Not a technical obstacle — the `unoapi-cloud` reference implementation proves `sourceId`/
`sourceType` are readily extractable from the same Baileys struct. More likely explanation:
Evolution's Chatwoot connector was built to render the ad data as a **visual card for a human
agent** (thumbnail + caption text baked into the message) — `title`/`body`/`thumbnailUrl`/
`sourceUrl` are exactly the fields with display value for that use case, while `sourceId`/
`sourceType` are opaque Meta IDs with no display value. Nobody who contributed that feature had
your specific need (resolving `source_id` via the Marketing Graph API for CRM attribution) — a
fairly specific use case most self-hosted Evolution users, who lean toward bots/automation, don't
have. An unmaintained corner of a community connector, not a deliberate tradeoff.

## Changes

- **FR-001**: `getAdsMessage` (`chatwoot.service.ts:1724`) additionally extracts `sourceId`,
  `sourceType`, `mediaType`, `mediaUrl` from `externalAdReply`, using the same
  `extendedTextMessage?.contextInfo?.externalAdReply ?? contextInfo?.externalAdReply` fallback
  already used for the existing fields. Each new field is optional (typed `?:` on the `AdsMessage`
  interface) — populated only when Meta sent it, left `undefined` otherwise. No new defaults are
  fabricated.
- **FR-002**: A small step, kept separate from `getAdsMessage` so "extract raw Baileys fields" and
  "shape for Chatwoot's API" stay independently reasoned about, builds a normalized `referral`
  object from the extracted `AdsMessage`, using Cloud API's exact field names (confirmed against
  Chatwoot's actual behavior, not assumed):
  ```ts
  {
    source_id: adsMessage.sourceId,
    source_type: adsMessage.sourceType,
    source_url: adsMessage.sourceUrl,
    headline: adsMessage.title,
    body: adsMessage.body,
    media_type: adsMessage.mediaType,
    image_url: adsMessage.thumbnailUrl, // not mediaUrl — thumbnailUrl is already proven fetchable
                                         // as an image; mediaUrl may point at non-image media for
                                         // video ads and isn't otherwise used by this code path.
  }
  ```
  Only defined keys are included (no `null`/`undefined` noise sent to Chatwoot). If no field is
  present at all, `referral` is omitted entirely (mirrors Cloud API's own `.present?` guard).
- **FR-003**: `sendData` (`chatwoot.service.ts:1050`) gains a new, optional, **last** positional
  parameter (`referral`), appended after the existing `quotedMsg` param so the two call sites that
  already pass 9 args are unaffected. Internally, `sendData` merges `referral` with any existing
  `replyToIds` into a **single** object before calling `data.append('content_attributes', ...)` —
  see "Impact analysis" below for why merging (not a second `append` call) is required, not
  optional.
- **FR-004**: The ads-message call site (`chatwoot.service.ts:~2250`) passes the normalized
  `referral` object from FR-002 into `sendData`. The existing image+caption send is otherwise
  **unchanged** — same visual message in the agent's timeline as today; `content_attributes.
  referral` is purely additive.

## Impact analysis

A second, careful pass through both sides of the wire (Evolution's send path and Chatwoot's
message-ingestion path) before committing to this design, specifically to surface non-obvious
risk:

- **Duplicate `content_attributes` form field (real risk, addressed by FR-003).** `sendData`
  today calls `data.append('content_attributes', ...)` only when `replyToIds` is present. Naively
  adding a second, independent `append` call for `referral` would produce **two form fields with
  the same name** in the multipart body — Rails/Rack does not merge same-named fields, so one
  would silently clobber the other depending on field order. FR-003's merge-before-append is a
  required fix, not a style preference.
- **Positional-argument safety.** `sendData` has 3 call sites; 2 already pass all 9 existing
  positional args (including `quotedMsg`), 1 (the ads-message branch) passes only 8. Appending
  `referral` as the 10th, final parameter keeps both untouched call sites valid — they implicitly
  pass `undefined`, which is correct (non-ads messages have no referral to attach).
- **Zero Chatwoot-side changes needed for storage.** Traced the full path:
  `Api::V1::Accounts::Conversations::MessagesController#create` →
  `Messages::MessageBuilder#content_attributes` parses whatever JSON string arrives in the
  `content_attributes` form field and stores it **verbatim** — no key allow-list, no schema
  validation. `Message`'s `store :content_attributes, accessors: [...]` only defines convenience
  dot-accessors for a fixed list of known keys (`email`, `in_reply_to`, `deleted`, etc.);
  `referral` isn't among them — same as it isn't for Cloud API's own `referral` data either — but
  unlisted keys persist in the JSON column fine, just without a dedicated Ruby accessor.
- **Field-name parity confirmed, not assumed.** Chatwoot's Cloud API path does **zero**
  normalization on Meta's `referral` webhook payload — verbatim passthrough with
  `deep_stringify_keys`. So "the Cloud API shape" isn't a Chatwoot-side convention to
  approximate — it's exactly whatever Meta sends, which Phase 26's investigation already captured.
  FR-002's field names were checked against that source directly.
- **No separate "marketing message" flag exists or is needed.** Checked `Message`'s
  `message_type` (`incoming`/`outgoing`/`activity`/`template`) and `content_type`
  (`text`/`cards`/`form`/etc.) enums — neither has an ad/marketing concept, and Chatwoot doesn't
  set any additional flag for Cloud API's referral messages either. The presence of
  `content_attributes.referral` **is** the marketing-origin indicator on both providers, by
  design — this is also the hook Phase 41 will use to decide when to render an ad-origin badge.
- **Pre-existing bug found, unrelated to this patch — flagged for awareness, not fixed here**
  (out of scope per minimal-change principle, and it predates this patch): `isAdsMessage`
  (`chatwoot.service.ts:2213`) treats `title`/`body`/`thumbnailUrl` as independently sufficient to
  trigger the ads-message branch, but the code immediately does
  `axios.get(adsMessage.thumbnailUrl, ...)` unconditionally — if an ad reply has `title`/`body`
  but no `thumbnailUrl` (plausible for a non-image ad), this throws today, already, before this
  patch touches the file.

## Validation

Manual only — build the patched image locally, point a test Evolution instance at it, and re-run
the same live Ad Preview flow used for Phase 26's Cloud API validation (including the "replace
suggested text entirely" case), confirming `content_attributes.referral` lands on the Chatwoot
message with the expected fields. No automated test added: this fork has **no test framework at
all** today (no jest/vitest/mocha, no existing `.spec.ts`/`.test.ts` files; the `dev:test` script
in `package.json` points at a `test/all.test.ts` that doesn't exist) — introducing a framework for
one small pure-function change is disproportionate ceremony, and the pre-existing gap is
upstream's, not something to fix incidentally here.

## Out of scope

- **CI/CD pipeline to publish the patched image to Docker Hub** (`edneymatias/evolution-api`) —
  a real prerequisite for deploying this patch to staging/production, but tracked as a separate
  backlog item, not a requirement of this spec.
- **`ctwa_clid` capture** — not present in Cloud API's observed real payload (Phase 26) nor
  confirmed present in Baileys' `ExternalAdReplyInfo`; nothing concrete to capture yet.
- **Chatwoot-side reading/surfacing of `referral`** (conversation badge, Opportunity field
  population, attribution reporting) — Phase 41, to be detailed after this patch lands.
- **Fixing the pre-existing `isAdsMessage`/`thumbnailUrl` bug** noted in "Impact analysis" —
  real, but predates and is unrelated to this patch.
