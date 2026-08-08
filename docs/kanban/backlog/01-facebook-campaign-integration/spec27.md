# Phase 27: Facebook Campaign Data & Conversions API Integration

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 26 (WhatsApp referral attribution study, Ciclo 5 —
this phase is one concrete direction that study's open questions could
lead to), existing Facebook Login flow already shipped for Page/Instagram
channel connection (`useFacebookPageConnect.js`,
`Api::V1::Accounts::CallbacksController`)

## Quick Preview

Small module, two related capabilities, both scoped to click-to-WhatsApp
(CTWA) ad conversations:

1. **Campaign/ad-set/ad enrichment via Facebook Login.** Chatwoot already
   has a working Facebook Login flow (`FACEBOOK_PAGE_SCOPES` in
   `facebookScopes.js`, already includes `business_management`; token
   exchange happens in `CallbacksController` via `Koala::Facebook::API`).
   That flow is scoped for connecting a Page/Instagram inbox today — this
   phase extends it (new scope(s), likely `ads_read` for the Marketing
   API) so an already-connected Business Manager can be used to look up
   campaign/ad-set/ad names for the ad IDs Chatwoot already receives.
   The referral payload captured on inbound CTWA messages
   (`content_attrs[:referral]`, source_id = ad id, per Phase 26) is raw
   IDs only today — this phase resolves those IDs into human-readable
   campaign/ad-set/ad names via the Marketing API, likely caching the
   lookup rather than calling on every message.
2. **Conversions API (CAPI) for CTWA.** Meta's Conversions API lets an
   app report back offline/business events tied to a `ctwa_clid` (the
   click id captured in the same referral payload), so ad performance
   reporting in Meta Ads Manager reflects what actually happened after
   the chat started — not just that a chat started. This phase sends
   conversion events (e.g. "agendamento", "venda", "perda") back to Meta
   when they happen in Chatwoot, most naturally tied to Opportunity
   status/stage changes (kanban module) rather than raw conversation
   events, since those already carry clear won/lost semantics.

## Open questions for the brainstorm

- **Scope of Facebook Login extension**: does `ads_read` require the
  connected Business Manager to have ad account access explicitly
  granted, separate from the Page permissions already requested? Needs
  a quick check against current Marketing API requirements before
  assuming it slots into the existing scope list.
- **Where do resolved campaign/ad-set/ad names live?** Options: resolve
  and store on the `Message`'s `content_attributes` at ingestion time
  (mirrors how referral is stored today), or resolve on-demand/cached
  separately with its own TTL (campaign names can be renamed after the
  ad ran). Leaning toward caching with a TTL, given names can change.
- **Conversions API event mapping**: which Opportunity status/stage
  transitions map to which Meta standard/custom event names (e.g.
  `won` → `Purchase`/`Schedule`, `lost` → no standard equivalent, likely
  needs a custom event name)? Needs product input on which events are
  actually valuable in Ads Manager, not just technically mappable.
- **Auth for CAPI specifically**: Conversions API calls need a
  dataset/pixel ID plus an access token with `ads_management` (broader
  than `ads_read`) — confirm whether CTWA CAPI requires a WhatsApp
  Business Account-linked dataset rather than a traditional pixel,
  since this is the WhatsApp-specific flavor of CAPI, not the standard
  web-pixel one.
- **Failure/retry semantics**: if a CAPI call fails (expired token,
  rate limit), does that block the Opportunity status change in
  Chatwoot, or fire-and-forget with logging/retry via a background job
  (latter seems clearly right — ad reporting shouldn't be able to block
  a sales action)?
- **Multi-account/multi-BM scoping**: is one Facebook Login connection
  per Chatwoot account assumed, or does an account need to map
  different inboxes/pipelines to different Business Managers?

## Out of scope (tentative, confirm during brainstorm)

- Any changes to the existing Page/Instagram channel connection flow
  itself (scope addition should be additive, not a rework).
- Ads Manager-side campaign creation/editing — this is read-only
  (campaign data) + write-only (conversion events), not a campaign
  management tool.
- Attribution reporting UI inside Chatwoot (that's Phase 26's territory,
  if pursued) — this phase is the data plumbing to/from Meta, not the
  in-app reporting surface.
