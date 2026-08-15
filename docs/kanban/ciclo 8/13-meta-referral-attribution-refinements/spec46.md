# Phase 46: Meta Referral Attribution Refinements — Organic Post Handling, Ad Creative Thumbnails, Robust OAuth Error Handling & Auto-Recovery

**Status**: candidate / draft backlog item — pending brainstorm & refinement
**Depends on**: Phase 26 (`docs/kanban/ciclo 7/08-whatsapp-referral-attribution/spec26.md`) / Spec 031 (WhatsApp Referral Attribution via Meta Marketing API).

---

## 1. Context & Motivation

Phase 26 / Spec 031 successfully introduced Click-to-WhatsApp campaign referral capture, async resolution of campaign/ad-set/ad names via Meta Graph API, and visual attribution badges on Opportunity cards.

Initial production usage revealed four key areas that need structural improvement:

1. **False-Positive Account Disconnections on Organic Posts**:
   - Meta Graph API returns `"type": "OAuthException"` for almost all query errors, including `code: 100` (e.g., querying an organic Page Post or Story ID with ad-specific fields like `adset` or `campaign`).
   - The current resolution job catches any `"OAuthException"` and treats it as a permanent token revocation, wiping `access_token` and flipping `enabled: false` on the account's `CampaignAttributionSetting`.
   - This causes subsequent real ad opportunities to remain stuck in `pending` indefinitely.
2. **Lack of Distinction Between Ads and Organic Posts in Kanban**:
   - Inbound WhatsApp referral payloads can originate from organic Facebook/Instagram posts, stories, or profile links (`source_type: "post"`, `source_id: "<post_id>"`).
   - Currently, these fail Graph API ad resolution and fallback to showing a raw numeric ID (e.g. `1587983499577672`) in the card tooltip without clarifying that the lead came from an organic post.
3. **Card Visual Enrichment: Ad Creative Preview / Thumbnail**:
   - The WhatsApp referral payload frequently delivers `thumbnail_url`, `image_url`, or `video_url` directly on the incoming message's `content_attributes['referral']`.
   - Graph API resolution also returns creative references (`creative.effective_object_story_id`, `object_story_spec`, `thumbnail_url`).
   - Adding an optional/configurable visual thumbnail on the Opportunity card improves agent scannability and context on Kanban.
4. **Orphaned `pending` Opportunities During Disconnections / Downtime**:
   - Opportunities created while the Meta integration is temporarily disabled or disconnected receive `campaign_resolution_status: 'pending'`, but the resolution job is skipped.
   - When an administrator reconnects the integration, there is no automatic sweeper or trigger to process those backlog `pending` opportunities, leaving them stuck until manually resolved via script.

---

## 2. Scope & Target Capabilities

### Feature 1: Robust OAuth Error Handling (Distinguish Token Invalidation vs. Query Failures)
- **Problem**: Broad `OAuthException` string matching triggers destructive disconnects.
- **Solution**:
  - Only disconnect the integration (`enabled: false`, wipe token) on authentic authentication/authorization revocation error codes:
    - `code: 190` (Invalid OAuth Access Token / Token expired / User deauthorized app / Password changed), matching specific subcodes (`458`, `460`, `463`, `467`, `490`).
  - For `code: 100` (Invalid parameter / Object does not exist / Not an Ad node) or other standard 4xx/404 errors:
    - Mark the individual opportunity's `campaign_resolution_status` as `failed` (or `organic_post`), without affecting the account's connection status.
  - Log diagnostic error metadata to Sidekiq / Rails logs for easier debugging.

### Feature 2: Organic Post Identification & Distinct Kanban Badge
- **Problem**: When `source_type == "post"`, resolution attempts to fetch it as an ad and fails, dumping the raw numeric ID.
- **Solution**:
  - Synchronous inspection in `ActionService`: if `referral['source_type'] == 'post'` or if `video_url`/`story_fbid` is present, record `campaign_origin_type: 'organic_post'` (or resolution status `organic_post`).
  - Skip calling `fetch_ad_details` for purely organic posts, saving Meta API rate limit quota.
  - Card UI representation:
    - Dedicated badge / tooltip (e.g. icon indicating organic post or story, tooltip: *"Origem: Publicação Orgânica (Facebook/Instagram)"*).
    - If `headline` or `body` is available in `referral`, display the post headline/summary instead of a raw ID number.

### Feature 3: Ad Preview / Creative Thumbnail on Kanban Card
- **Problem**: Cards show platform icons and text names, but no visual representation of the creative that attracted the lead.
- **Solution**:
  - Storage: capture and store `campaign_thumbnail_url` or `creative_media_url` on `Opportunity` (persisting the referral's `thumbnail_url` / `image_url` or fetching `creative` from Graph API).
  - UI Card Customization:
    - Add a toggle in Card Fields configuration (`app/javascript/dashboard/routes/dashboard/settings/pipelineStages/CardFieldConfig.vue`) allowing admins to enable/disable "Creative Thumbnail" on cards.
    - Render a compact, elegant thumbnail with a popover/lightbox preview on hover or click.

### Feature 4: Automatic Reconnect Drain & Scheduled Sweeper for Pending Attributions
- **Problem**: When connection is re-established, opportunities that were generated during disconnection stay stuck in `pending`.
- **Solution**:
  - **Auto-Drain on Reconnection**:
    - When `CampaignAttributionSettingsController#connect` or `#update(enabled: true)` succeeds, automatically enqueue a background job (`Meta::DrainPendingAttributionsJob`) to resolve all opportunities with `campaign_resolution_status: 'pending'` for that account.
  - **Recurring Sweeper**:
    - Add a periodic Sidekiq-cron job (e.g. hourly or daily `Meta::PendingAttributionsSweeperJob`) that sweeps and enqueues resolution for any opportunities stuck in `pending` longer than 15 minutes where the account's integration is active.
  - **Manual Trigger in Settings**:
    - Add a "Reprocessar Pendentes" (Reprocess Pending) action button in the Campaign Attribution Settings tab (`CampaignAttributionSettings.vue`), giving admins instant manual control with visible progress feedback.

---

## 3. Open Questions for Brainstorm

1. **Storage for Organic Post Metadata**: Should we store the referral's `headline`, `body`, and `thumbnail_url` in dedicated columns on `Opportunity`, or inside `additional_attributes['referral']` for flexible access?
2. **Creative Media Expiration**: Meta's CDN URLs (`scontent...fbcdn.net`) for thumbnails have expiring URL signatures (`oh` and `oe` params, typically valid for ~30–60 days). Should we cache/download thumbnails to ActiveStorage or rely on transient CDN URLs?
3. **Card Space vs. Visual Noise**: How should the thumbnail be presented on Kanban (e.g., small badge preview vs. hero card image like Trello)?
4. **Rate Limiting on Bulk Sweepers**: How should the automatic reconnect sweeper throttle its batch requests against Meta API rate limits (e.g. leveraging `Meta::RateLimiter` with spaced job delays)?

---

## 4. Acceptance Criteria (Draft)

1. Receiving a lead from an organic Facebook/Instagram post marks the opportunity with an organic post badge and does **NOT** disconnect the Meta account.
2. Only true token invalidations (`code: 190`) trigger the integration disconnection state.
3. Card tooltips for failed or organic referrals provide human-readable explanations instead of raw numeric IDs.
4. Opportunities can display the ad/post creative thumbnail on the Kanban card if configured.
5. Reconnecting or enabling the Meta integration automatically resolves all opportunities currently stuck in `pending` without requiring manual console scripts.
6. A scheduled sweeper ensures no opportunity remains in `pending` longer than the sweeper interval when the integration is active.
